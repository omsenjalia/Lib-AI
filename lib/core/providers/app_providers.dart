import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../models/app_settings.dart';
import '../models/model_catalogue.dart';
import '../models/transfer_state.dart';
import '../services/catalogue_repository.dart';
import '../services/connectivity_service.dart';
import '../services/download_manager.dart';
import '../services/download_notification_service.dart';
import '../services/huggingface_client.dart';
import '../services/inference_engine.dart';
import '../services/settings_service.dart';
import '../services/update_checker.dart';
import '../services/update_scheduler.dart';

/// The provider graph.
///
/// Everything the app needs is a singleton scoped to the app's lifetime, so
/// these are all plain `Provider`s rather than auto-disposed ones. The
/// exceptions are the family providers, which are disposed with their screen.
///
/// Order of construction matters in exactly one place: [inferenceEngineProvider]
/// and [downloadManagerProvider] both sit above the feature layer, and neither
/// knows about the other. In particular the update checker has no reference to
/// the download manager - that absence is what structurally guarantees an
/// update can never begin downloading on its own.

// ------------------------------------------------------------------ storage

/// The single SQLite connection for the app.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final settingsServiceProvider = Provider<SettingsService>(
  (ref) => SettingsService(ref.watch(databaseProvider)),
);

/// The user's preferences, loaded once at startup.
///
/// Held as an [AsyncNotifier] so the settings screen can write and re-render
/// without a second source of truth. Reads never throw: a corrupt value falls
/// back to its default, and a database read failure yields defaults, so this
/// provider resolving to an error state would mean the app is already broken.
class SettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() => ref.watch(settingsServiceProvider).load();

  SettingsService get _service => ref.read(settingsServiceProvider);

  /// Persists a full settings object and publishes it.
  Future<void> save(AppSettings settings) async {
    state = AsyncData(settings);
    await _service.save(settings);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final current = state.valueOrNull ?? const AppSettings();
    await save(current.copyWith(themeMode: mode));
  }

  Future<void> setDefaultModel(String? modelId) async {
    final current = state.valueOrNull ?? const AppSettings();
    await save(
      modelId == null
          ? current.copyWith(clearDefaultModelId: true)
          : current.copyWith(defaultModelId: modelId),
    );
  }

  Future<void> setDefaultSubjectTag(int? tagId) async {
    final current = state.valueOrNull ?? const AppSettings();
    await save(
      tagId == null
          ? current.copyWith(clearDefaultSubjectTagId: true)
          : current.copyWith(defaultSubjectTagId: tagId),
    );
  }

  Future<void> setContextLength(int length) async {
    final current = state.valueOrNull ?? const AppSettings();
    await save(current.copyWith(contextLength: length));
  }

  Future<void> setSampling({
    double? temperature,
    double? topP,
    int? topK,
    int? gpuLayers,
  }) async {
    final current = state.valueOrNull ?? const AppSettings();
    await save(
      current.copyWith(
        temperature: temperature,
        topP: topP,
        topK: topK,
        gpuLayers: gpuLayers,
      ),
    );
  }

  Future<void> setAutoUpdateCheck(bool enabled) async {
    final current = state.valueOrNull ?? const AppSettings();
    await save(current.copyWith(autoUpdateCheckEnabled: enabled));
  }

  /// Called when the model named as the default is deleted from the device.
  Future<void> clearDefaultModelIf(String modelId) async {
    final current = state.valueOrNull;
    if (current == null || current.defaultModelId != modelId) return;
    await save(current.copyWith(clearDefaultModelId: true));
  }
}

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

/// Synchronous access to the current settings, for widgets that already know
/// the settings have loaded (the app root gates on that).
final currentSettingsProvider = Provider<AppSettings>((ref) {
  return ref.watch(settingsControllerProvider).valueOrNull ??
      const AppSettings();
});

// ----------------------------------------------------------------- catalogue

/// The bundled catalogue. Asset-backed, so this never fails for network
/// reasons; it can only fail if the asset itself is malformed, which the
/// catalogue test suite guards against.
final catalogueRepositoryProvider = Provider<CatalogueRepository>(
  (ref) => CatalogueRepository(),
);

final catalogueProvider = FutureProvider<ModelCatalogue>(
  (ref) => ref.watch(catalogueRepositoryProvider).load(),
);

// ------------------------------------------------------- connectivity + models

final connectivityServiceProvider = Provider<ConnectivityService>(
  (ref) => ConnectivityService(),
);

/// Emits on every connectivity change. Used by the model library to keep the
/// Wi-Fi-only block and the "check for updates" affordance honest.
final connectivityStreamProvider = StreamProvider<bool>(
  (ref) => ref.watch(connectivityServiceProvider).onlineChanges,
);

final huggingFaceClientProvider = Provider<HuggingFaceClient>(
  (ref) => HuggingFaceClient(),
);

final downloadManagerProvider = Provider<DownloadManager>((ref) {
  final manager = DownloadManager(
    database: ref.watch(databaseProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
  ref.onDispose(manager.dispose);
  return manager;
});

/// Live download state, keyed by model id.
final downloadTasksProvider = StreamProvider<Map<String, DownloadTask>>(
  (ref) => ref.watch(downloadManagerProvider).tasksStream,
);

// -------------------------------------------------- download notifications

/// Incremented when the user taps a download notification.
///
/// The notification plumbing lives in core and must not import a feature
/// screen, so it does not navigate. It raises this counter instead, and the app
/// root - which is allowed to know about screens - does the pushing.
final openModelLibraryRequestProvider = StateProvider<int>((ref) => 0);

/// Posts the Play-Store-style progress notification for each download, and
/// routes its Cancel action back to [DownloadManager].
final downloadNotificationServiceProvider =
    ChangeNotifierProvider<DownloadNotificationService>((ref) {
  return DownloadNotificationService(
    onCancelRequested: (modelId) =>
        ref.read(downloadManagerProvider).cancel(modelId),
    onOpenRequested: (_) =>
        ref.read(openModelLibraryRequestProvider.notifier).state++,
  );
});

/// Subscribes the notification service to the download stream.
///
/// This is a provider rather than a background job so that it starts with the
/// app and stops with it, and so that the dependency stays visible: nothing
/// else in the graph knows about notifications, and the download manager
/// itself has no idea they exist.
///
/// Watching it in the app root is what keeps it alive.
final downloadNotificationBinderProvider = Provider<void>((ref) {
  final service = ref.read(downloadNotificationServiceProvider);
  // Watching `.future` keeps the subscription to the catalogue alive and hands
  // back the awaitable directly - `AsyncValue` itself has no `future` getter.
  final catalogueFuture = ref.watch(catalogueProvider.future);

  // Names come from the catalogue, so a notification reads
  // `Phi-4-mini-instruct` rather than `phi-4-mini-3.8b`. The first task can
  // arrive before the asset has finished loading, so this waits rather than
  // falling back to the raw id.
  var names = const <String, String>{};
  Future<String> nameFor(String modelId) async {
    if (names.isEmpty) {
      try {
        final value = await catalogueFuture;
        names = {for (final model in value.models) model.id: model.displayName};
      } catch (_) {
        // A malformed catalogue is reported by the Model Library, not here.
      }
    }
    return names[modelId] ?? modelId;
  }

  final subscription = ref
      .watch(downloadManagerProvider)
      .tasksStream
      .listen((tasks) async {
    for (final task in tasks.values) {
      await service.apply(
        task,
        modelName: await nameFor(task.modelId),
      );
    }
  });

  ref.onDispose(subscription.cancel);
});

final updateCheckerProvider = Provider<UpdateChecker>((ref) {
  final checker = UpdateChecker(
    database: ref.watch(databaseProvider),
    client: ref.watch(huggingFaceClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
  ref.onDispose(checker.dispose);
  return checker;
});

final updateSchedulerProvider = Provider<UpdateScheduler>((ref) {
  final scheduler = UpdateScheduler(
    connectivity: ref.watch(connectivityServiceProvider),
    checker: ref.watch(updateCheckerProvider),
    catalogue: ref.watch(catalogueRepositoryProvider),
    settings: ref.watch(settingsServiceProvider),
  );
  ref.onDispose(scheduler.dispose);
  return scheduler;
});

/// Live update state, keyed by model id.
final updateStateProvider = StreamProvider<Map<String, ModelUpdateInfo>>(
  (ref) => ref.watch(updateCheckerProvider).updatesStream,
);

/// True once the user has dismissed the update banner in this session.
///
/// Session-scoped on purpose: dismissing should not permanently silence the
/// notification, or the user would never be told again.
final updateBannerDismissedProvider = StateProvider<bool>((ref) => false);

/// Models installed on this device.
final installationsProvider = StreamProvider<List<ModelInstallation>>(
  (ref) => ref.watch(databaseProvider).watchInstallations(),
);

/// The installation for one catalogue model, or null when not downloaded.
final installationProvider =
    StreamProvider.family<ModelInstallation?, String>((ref, modelId) {
  return ref.watch(databaseProvider).watchInstallation(modelId);
});

final totalModelBytesProvider = FutureProvider<int>(
  (ref) => ref.watch(databaseProvider).totalModelBytes(),
);

// ------------------------------------------------------------------ inference

final inferenceEngineProvider = Provider<InferenceEngine>((ref) {
  final engine = InferenceEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

/// Engine stage: unloaded, loading, ready, generating, failed.
final engineStatusProvider = StreamProvider<EngineStatus>(
  (ref) => ref.watch(inferenceEngineProvider).statusStream,
);

/// The model the chat panel should talk to.
///
/// Resolution order: the user's explicit default, then the most recently
/// downloaded installation. If neither exists the chat screen shows its
/// "no model installed" state rather than a dead composer.
final activeModelIdProvider = Provider<String?>((ref) {
  final settings = ref.watch(currentSettingsProvider);
  final installations = ref.watch(installationsProvider).valueOrNull;

  final preferred = settings.defaultModelId;
  if (preferred != null &&
      installations != null &&
      installations.any((i) => i.modelId == preferred)) {
    return preferred;
  }

  if (installations == null || installations.isEmpty) return null;
  final sorted = [...installations]
    ..sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
  return sorted.first.modelId;
});

// --------------------------------------------------------------------- data

final subjectTagsProvider = StreamProvider<List<SubjectTag>>(
  (ref) => ref.watch(databaseProvider).watchSubjectTags(),
);

final personasProvider = StreamProvider<List<Persona>>(
  (ref) => ref.watch(databaseProvider).watchPersonas(),
);

final conversationsProvider = StreamProvider<List<Conversation>>(
  (ref) => ref.watch(databaseProvider).watchConversations(),
);

/// Messages for one conversation, oldest first.
final messagesProvider =
    StreamProvider.family<List<Message>, int>((ref, conversationId) {
  return ref.watch(databaseProvider).watchMessages(conversationId);
});

/// Count of imported documents. Always 0 in v1; the My Notes screen reads it so
/// that the screen is already wired for Phase 2.
final documentCountProvider = FutureProvider<int>(
  (ref) => ref.watch(databaseProvider).documentCount(),
);
