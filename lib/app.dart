import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/providers/app_providers.dart';
import 'core/theme/app_theme.dart';
import 'features/chat/screens/chat_screen.dart';

/// The application root.
///
/// Startup is deliberately serial and short: open the database, read settings,
/// render the chat screen. No model is loaded here - loading is user-triggered,
/// because pulling gigabytes of weights into RAM while somebody is merely
/// looking at the app would both slow the start and risk an out-of-memory kill
/// before they have done anything.
///
/// The two background jobs that *are* started here are non-blocking and both
/// tolerate being offline: the update scheduler (which silently no-ops without
/// a connection) and the partial-download sweep (which is local file cleanup).
class LibraryAiApp extends ConsumerWidget {
  const LibraryAiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(
      settingsControllerProvider.select(
        (settings) => settings.valueOrNull?.themeMode ?? ThemeMode.dark,
      ),
    );

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Dark-mode-first: until the stored preference has loaded, dark is the
      // assumption, and the platform colour in android/res/values matches it so
      // there is no flash.
      themeMode: themeMode,
      home: const _Bootstrap(),
    );
  }
}

/// Prepares background work, then shows the app.
///
/// The gate exists so that startup side effects have one obvious home instead
/// of being scattered across `initState` methods.
class _Bootstrap extends ConsumerStatefulWidget {
  const _Bootstrap();

  @override
  ConsumerState<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends ConsumerState<_Bootstrap> {
  @override
  void initState() {
    super.initState();
    // After the first frame, so nothing here delays chat-readiness.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    // 1. Clear out any `.part` files from downloads that were interrupted by a
    //    process kill. Local, fast, and safe to run every launch.
    unawaited(
      ref.read(downloadManagerProvider).sweepPartialDownloads().catchError(
            (Object _) {},
          ),
    );

    // 2. Publish the stored update state so badges are correct immediately,
    //    without waiting for a network round trip.
    final catalogue = ref.read(catalogueProvider);
    try {
      final models = (await catalogue.future).models;
      await ref.read(updateCheckerProvider).hydrate(models);
    } catch (_) {
      // A malformed catalogue is surfaced by the Model Library screen; it must
      // not stop the app from starting.
    }

    // 3. Watch for connectivity changes and check for model updates when the
    //    device comes back online. Does nothing at all while offline.
    unawaited(
      ref.read(updateSchedulerProvider).start().catchError((Object _) {}),
    );
  }

  @override
  Widget build(BuildContext context) => const ChatScreen();
}
