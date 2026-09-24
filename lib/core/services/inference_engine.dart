import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fllama/fllama.dart' as fl;

import '../errors/app_exception.dart';
import '../models/model_catalogue.dart';

/// Stage of the model lifecycle, as far as the UI can honestly report it.
///
/// **Why these stages and not a percentage:** fllama exposes no model-load
/// progress callback on native. The native side loads weights lazily, inside
/// the first inference call, so there is no byte counter to report. Rather than
/// invent a progress bar, the engine reports the three real phases it *can*
/// observe, and the UI shows an indeterminate indicator underneath them.
enum EngineStage {
  /// Nothing loaded.
  unloaded,

  /// Confirming the GGUF files exist and are non-empty.
  verifying,

  /// Reading GGUF metadata (chat template, EOS token). This genuinely parses
  /// the file header, so it catches a truncated download before the expensive
  /// step.
  readingMetadata,

  /// Weights are being mapped into memory. This is the long, opaque one.
  loadingWeights,

  /// A one-token warm-up pass, which is what forces fllama to actually
  /// instantiate the context and surfaces out-of-memory at load time rather
  /// than mid-conversation.
  warmingUp,

  ready,

  failed,
}

/// Immutable snapshot of what the engine is doing.
@immutable
class EngineStatus {
  const EngineStatus({
    this.stage = EngineStage.unloaded,
    this.modelId,
    this.modelPath,
    this.mmprojPath,
    this.contextLength = 0,
    this.visionReady = false,
    this.message,
    this.error,
    this.lastActivityAt,
  });

  final EngineStage stage;
  final String? modelId;
  final String? modelPath;
  final String? mmprojPath;
  final int contextLength;

  /// True when a projector is loaded, so OCR mode can be offered.
  final bool visionReady;

  /// Human-readable progress or failure text.
  final String? message;

  final AppException? error;

  /// When the last generation finished. Used to explain the platform's idle
  /// release timer rather than guessing at it.
  final DateTime? lastActivityAt;

  bool get isReady => stage == EngineStage.ready;
  bool get isLoading =>
      stage == EngineStage.verifying ||
      stage == EngineStage.readingMetadata ||
      stage == EngineStage.loadingWeights ||
      stage == EngineStage.warmingUp;
  bool get hasFailed => stage == EngineStage.failed;

  /// True when the engine currently holds this model.
  bool holds(String? id) => id != null && id == modelId && stage != EngineStage.unloaded;

  EngineStatus copyWith({
    EngineStage? stage,
    String? modelId,
    String? modelPath,
    String? mmprojPath,
    int? contextLength,
    bool? visionReady,
    String? message,
    bool clearMessage = false,
    AppException? error,
    bool clearError = false,
    DateTime? lastActivityAt,
  }) =>
      EngineStatus(
        stage: stage ?? this.stage,
        modelId: modelId ?? this.modelId,
        modelPath: modelPath ?? this.modelPath,
        mmprojPath: mmprojPath ?? this.mmprojPath,
        contextLength: contextLength ?? this.contextLength,
        visionReady: visionReady ?? this.visionReady,
        message: clearMessage ? null : (message ?? this.message),
        error: clearError ? null : (error ?? this.error),
        lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      );
}

/// A message destined for the model.
///
/// Deliberately not `fl.Message`: keeping this engine's input type independent
/// of the binding means the vendor prefix is contained to this one file, and
/// the chat layer never has to care which llama.cpp binding is underneath.
@immutable
class PromptMessage {
  const PromptMessage({
    required this.role,
    required this.content,
    this.imagePath,
  });

  /// `system`, `user` or `assistant`.
  final String role;
  final String content;

  /// Local path to an attached image, for multimodal models.
  final String? imagePath;
}

/// Result of one generation.
@immutable
class GenerationResult {
  const GenerationResult({
    required this.text,
    required this.stopped,
    this.error,
  });

  final String text;

  /// True when the user pressed Stop. A stopped generation is a normal
  /// outcome, not a failure, and the partial text is kept.
  final bool stopped;

  final AppException? error;

  bool get isFailure => error != null;
}

/// Owns the one loaded model and drives generation.
///
/// ## Memory behaviour, and what "unload" can honestly mean
///
/// fllama caches a llama.cpp server context per model path and exposes **no**
/// call to free one. Its `ServerManager` reaps an idle context after
/// `MODEL_INACTIVITY_TIMEOUT_SEC = 120` seconds, checked every
/// `CLEANUP_INTERVAL_SEC = 30` seconds (both in
/// `fllama/src/fllama_inference_queue.cpp`).
///
/// Two consequences the app has to live with, and does not hide:
///
///  * [unload] cannot free native memory immediately. It cancels any in-flight
///    generation and marks the engine unloaded so nothing new is sent, and then
///    the platform's own timer does the actual releasing.
///  * Switching to a *different* model creates a new context straight away
///    while the old one is still resident, so peak memory briefly holds both.
///    [estimatedReleaseAt] exposes when that transient ends, and the model
///    switcher surfaces it.
class InferenceEngine {
  InferenceEngine({this.onLog});

  /// Receives llama.cpp's own log lines when a debug logger is attached.
  final void Function(String message)? onLog;

  final _statusController = StreamController<EngineStatus>.broadcast();
  EngineStatus _status = const EngineStatus();

  /// Identifier handed back by fllama for the in-flight request, used to cancel.
  int? _activeRequestId;

  /// Cumulative text of the response so far. fllama's callback hands back the
  /// whole response each time, not just the newest token, so deltas are derived
  /// by diffing against this.
  String _accumulated = '';

  bool _stopRequested = false;
  Completer<GenerationResult>? _generationCompleter;

  Stream<EngineStatus> get statusStream => _statusController.stream;
  EngineStatus get status => _status;

  /// When the native side is expected to have released the current model,
  /// assuming no further generations. This is the platform's 120 s idle
  /// timeout plus one 30 s reap interval, surfaced so the UI can be specific
  /// instead of vague.
  DateTime? get estimatedReleaseAt {
    final last = _status.lastActivityAt;
    if (last == null) return null;
    return last.add(const Duration(seconds: 150));
  }

  void _emit(EngineStatus next) {
    _status = next;
    if (!_statusController.isClosed) _statusController.add(next);
  }

  // --------------------------------------------------------------------- load

  /// Loads [model] at [quant], forcing the weights into memory.
  ///
  /// Returns normally on success. Throws a typed [AppException] on failure so
  /// the caller can show specific recovery guidance - in particular, memory
  /// exhaustion gets different advice from a corrupt file.
  Future<void> load({
    required CatalogueModel model,
    required QuantOption quant,
    required ModelInstallationPaths paths,
    required int contextLength,
    required int gpuLayers,
    bool includeMmproj = true,
  }) async {
    _emit(
      EngineStatus(
        stage: EngineStage.verifying,
        modelId: model.id,
        modelPath: paths.modelPath,
        mmprojPath: includeMmproj ? paths.mmprojPath : null,
        contextLength: contextLength,
        visionReady: includeMmproj && paths.mmprojPath != null,
        message: 'Checking ${quant.fileName}',
      ),
    );

    // 1. The file must exist and be non-trivially sized. A 0-byte or missing
    //    file is the most common failure after an interrupted download.
    final modelFile = File(paths.modelPath);
    if (!await modelFile.exists()) {
      final error = ModelFileMissingException(
        'The model file for ${model.displayName} is missing.',
        detail: 'Expected at ${paths.modelPath}',
      );
      _fail(error);
      throw error;
    }
    final actualSize = await modelFile.length();
    if (actualSize < 1024 * 1024) {
      final error = ModelCorruptException(
        'The model file for ${model.displayName} looks incomplete.',
        detail: 'Only $actualSize bytes on disk, expected '
            '${quant.sizeBytes} bytes.',
      );
      _fail(error);
      throw error;
    }

    if (paths.mmprojPath != null) {
      final mmprojFile = File(paths.mmprojPath!);
      if (!await mmprojFile.exists()) {
        // Not fatal - the model still works for text. Drop to text-only and
        // carry on rather than blocking the whole load.
        paths = paths.withoutMmproj();
        _emit(_status.copyWith(
          mmprojPath: null,
          visionReady: false,
          message: 'Vision projector missing; loading text-only.',
        ));
      }
    }

    // 2. Metadata read. This genuinely parses the GGUF header, so a truncated
    //    file fails here cheaply rather than after minutes of loading.
    _emit(_status.copyWith(
      stage: EngineStage.readingMetadata,
      message: 'Reading model metadata',
    ));
    try {
      final template = await fl.fllamaChatTemplateGet(paths.modelPath);
      if (template.isEmpty) {
        throw ModelCorruptException(
          'Could not read a chat template from ${quant.fileName}.',
          detail: 'The GGUF header did not parse.',
        );
      }
    } on AppException {
      rethrow;
    } catch (error) {
      final wrapped = ModelCorruptException(
        'The model file could not be read.',
        detail: '$error',
      );
      _fail(wrapped);
      throw wrapped;
    }

    // 3. Weights + warm-up. This is where memory is actually committed, and
    //    where an out-of-RAM failure appears.
    _emit(_status.copyWith(
      stage: EngineStage.loadingWeights,
      message: 'Loading weights into memory',
    ));

    try {
      await _warmUp(paths: paths, contextLength: contextLength, gpuLayers: gpuLayers);
    } on AppException catch (error) {
      _fail(error);
      rethrow;
    } catch (error) {
      final wrapped = _classifyLoadFailure('$error');
      _fail(wrapped);
      throw wrapped;
    }

    _emit(_status.copyWith(
      stage: EngineStage.ready,
      message: null,
      clearMessage: true,
      clearError: true,
      lastActivityAt: DateTime.now(),
    ));
  }

  /// Forces fllama to instantiate the context by running a single-token pass.
  ///
  /// fllama has no explicit load call, so this is the only way to learn whether
  /// the model fits *before* the user starts a real conversation.
  Future<void> _warmUp({
    required ModelInstallationPaths paths,
    required int contextLength,
    required int gpuLayers,
  }) async {
    _emit(_status.copyWith(
      stage: EngineStage.warmingUp,
      message: 'Warming up',
    ));

    final request = fl.OpenAiRequest(
      messages: [fl.Message(fl.Role.user, 'hi')],
      modelPath: paths.modelPath,
      mmprojPath: paths.mmprojPath,
      contextSize: contextLength,
      maxTokens: 1,
      numGpuLayers: gpuLayers,
      temperature: 0.1,
    );

    final completer = Completer<String>();
    final buffer = StringBuffer();

    final id = await fl.fllamaChat(request, (response, openAiJson, done) {
      buffer.write(response);
      if (fl.fllamaOutputIndicatesLoadError(response)) {
        if (!completer.isCompleted) completer.completeError(response);
        return;
      }
      if (done && !completer.isCompleted) completer.complete(buffer.toString());
    });

    // Warm-up has no user-facing cancel, but a hung load should not pin the
    // spinner forever.
    _activeRequestId = id;

    try {
      await completer.future.timeout(const Duration(minutes: 5));
    } on TimeoutException {
      fl.fllamaCancelInference(id);
      throw const InsufficientMemoryException(
        'The model did not finish loading in five minutes.',
        detail: 'Load timed out.',
      );
    } finally {
      _activeRequestId = null;
    }
  }

  /// Maps a raw llama.cpp failure string onto the right user-facing exception.
  ///
  /// "Failed to create context" is the signature of an allocation that could
  /// not be satisfied - on this device that almost always means the quant is
  /// too large, so it is classified as a memory problem and the user is pointed
  /// at a smaller quant rather than told their file is broken.
  AppException _classifyLoadFailure(String raw) {
    final lower = raw.toLowerCase();
    const memorySignals = [
      'out of memory',
      'failed to allocate',
      'unable to allocate',
      'insufficient memory',
      'ggml_backend_alloc',
      'failed to create context',
      'cannot allocate',
      'bad_alloc',
    ];
    for (final signal in memorySignals) {
      if (lower.contains(signal)) {
        return InsufficientMemoryException(
          'Not enough free memory to load this model.',
          detail: raw,
        );
      }
    }
    if (fl.fllamaOutputIndicatesLoadError(raw)) {
      return ModelCorruptException(
        'The model could not be loaded.',
        detail: raw,
      );
    }
    return UnknownAppException('The model could not be loaded.', detail: raw);
  }

  void _fail(AppException error) {
    if (_activeRequestId != null) {
      fl.fllamaCancelInference(_activeRequestId!);
      _activeRequestId = null;
    }
    _emit(_status.copyWith(
      stage: EngineStage.failed,
      error: error,
      message: error.message,
    ));
  }

  // --------------------------------------------------------------- generation

  /// Streams a completion for [messages].
  ///
  /// [onToken] receives each *delta* - the text added since the previous call -
  /// because fllama's callback is cumulative and the UI needs per-token events
  /// to animate. The full text is returned when generation ends.
  Future<GenerationResult> generate({
    required List<PromptMessage> messages,
    required int maxTokens,
    required double temperature,
    required double topP,
    double repeatPenalty = 1.1,
    int? contextLengthOverride,
    int gpuLayers = 0,
    required void Function(String delta) onToken,
  }) async {
    final status = _status;
    final modelPath = status.modelPath;
    if (modelPath == null || !status.isReady) {
      return const GenerationResult(
        text: '',
        stopped: false,
        error: UnknownAppException('No model is loaded.'),
      );
    }

    _stopRequested = false;
    _accumulated = '';
    _generationCompleter = Completer<GenerationResult>();

    final request = fl.OpenAiRequest(
      messages: await _toFllamaMessages(messages),
      modelPath: modelPath,
      mmprojPath: status.mmprojPath,
      contextSize: contextLengthOverride ?? status.contextLength,
      maxTokens: maxTokens,
      temperature: temperature,
      topP: topP,
      // fllama maps presencePenalty onto llama.cpp's penalty_repeat, and
      // frequencyPenalty onto penalty_frequency.
      presencePenalty: repeatPenalty,
      frequencyPenalty: 0,
      // top_k is deliberately absent: the binding does not expose it. See
      // ARCHITECTURE.md and the note on the Settings screen.
      numGpuLayers: gpuLayers,
      logger: onLog,
    );

    AppException? failure;
    var stopped = false;
    final finished = Completer<void>();

    final requestId = await fl.fllamaChat(request, (response, openAiJson, done) {
      // fllama may deliver a load error through this callback instead of
      // throwing, so it has to be checked on every tick.
      if (fl.fllamaOutputIndicatesLoadError(response)) {
        failure = _classifyLoadFailure(response);
        _accumulated = '';
        if (!finished.isCompleted) finished.complete();
        return;
      }

      final delta = _diff(_accumulated, response);
      _accumulated = response;
      if (delta.isNotEmpty && !_stopRequested) {
        onToken(delta);
      }

      if (done && !finished.isCompleted) finished.complete();
    });

    _activeRequestId = requestId;

    try {
      await finished.future;
    } catch (error) {
      failure = _classifyLoadFailure('$error');
    } finally {
      _activeRequestId = null;
      stopped = _stopRequested;
      _emit(_status.copyWith(lastActivityAt: DateTime.now()));
    }

    final result = GenerationResult(
      text: _accumulated,
      stopped: stopped,
      error: failure,
    );
    _generationCompleter?.complete(result);
    _generationCompleter = null;
    return result;
  }

  /// Derives the new text from two cumulative snapshots.
  ///
  /// Guarded with `startsWith` because a backend that re-emits a corrected
  /// prefix would otherwise cause the UI to duplicate text.
  String _diff(String previous, String next) {
    if (next.length >= previous.length && next.startsWith(previous)) {
      return next.substring(previous.length);
    }
    // Not a simple extension - treat the whole payload as new rather than
    // dropping it.
    return next;
  }

  /// Converts prompt messages, inlining images as data URIs.
  ///
  /// llama.cpp's multimodal path consumes `<img src="data:image/...;base64,...">`
  /// tags inside the message text; there is no separate image parameter. The
  /// image is read from local storage and never uploaded anywhere.
  Future<List<fl.Message>> _toFllamaMessages(
    List<PromptMessage> messages,
  ) async {
    final result = <fl.Message>[];
    for (final message in messages) {
      var text = message.content;

      if (message.imagePath != null) {
        final dataUri = await _encodeImage(message.imagePath!);
        if (dataUri != null) {
          text = '<img src="$dataUri">\n\n$text';
        }
      }

      result.add(fl.Message(_roleFor(message.role), text));
    }
    return result;
  }

  Future<String?> _encodeImage(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final extension = path.split('.').last.toLowerCase();
      final mime = switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        _ => 'image/jpeg',
      };
      return 'data:$mime;base64,${base64Encode(bytes)}';
    } catch (_) {
      // A missing or unreadable attachment degrades to a text-only turn rather
      // than failing the whole request.
      return null;
    }
  }

  fl.Role _roleFor(String role) {
    switch (role) {
      case 'system':
        return fl.Role.system;
      case 'assistant':
        return fl.Role.assistant;
      default:
        return fl.Role.user;
    }
  }

  /// Requests cancellation. The partial response already streamed so far is
  /// kept and returned as a normal (stopped) result.
  void stop() {
    _stopRequested = true;
    final id = _activeRequestId;
    if (id != null) {
      fl.fllamaCancelInference(id);
    }
    final completer = _generationCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(
        GenerationResult(text: _accumulated, stopped: true),
      );
      _generationCompleter = null;
    }
  }

  // ---------------------------------------------------------------- tokenising

  /// Exact token count from the model's own vocabulary.
  ///
  /// Returns null when the count cannot be obtained, in which case the caller
  /// falls back to [TokenEstimator.estimate] and labels the number as an
  /// estimate. A wrong-but-labelled estimate is preferable to a spinner.
  Future<int?> countTokens(String text) async {
    final modelPath = _status.modelPath;
    if (modelPath == null || text.isEmpty) return null;
    try {
      return await fl.fllamaTokenize(
        fl.FllamaTokenizeRequest(input: text, modelPath: modelPath),
      ).timeout(const Duration(seconds: 30));
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------ unload

  /// Stops generation and marks the engine unloaded.
  ///
  /// This does **not** free native memory - see the class docs. It prevents
  /// further work from being dispatched and records the idle timestamp that
  /// makes [estimatedReleaseAt] meaningful.
  Future<void> unload() async {
    stop();
    _activeRequestId = null;
    _accumulated = '';
    _emit(
      EngineStatus(lastActivityAt: DateTime.now()),
    );
  }

  Future<void> dispose() async {
    stop();
    await _statusController.close();
  }
}

/// Where a model's files live on disk.
///
/// Passed into [InferenceEngine.load] instead of being read from the database
/// so the engine stays free of any persistence dependency and can be unit
/// tested with temp-directory paths.
@immutable
class ModelInstallationPaths {
  const ModelInstallationPaths({
    required this.modelPath,
    this.mmprojPath,
  });

  final String modelPath;
  final String? mmprojPath;

  ModelInstallationPaths withoutMmproj() =>
      ModelInstallationPaths(modelPath: modelPath);
}
