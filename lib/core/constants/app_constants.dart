/// Every fixed value the app relies on, in one place.
abstract final class AppConstants {
  static const String appName = 'Library AI';
  static const String tagline = 'Learn anywhere. No internet required.';

  /// Database file name inside the app documents directory.
  static const String databaseName = 'library_ai.sqlite';

  /// Directory (under app support storage) holding downloaded GGUF files.
  static const String modelsDirectoryName = 'models';

  /// Directory holding PDF/ZIP exports before they are shared.
  static const String exportsDirectoryName = 'exports';

  /// Asset holding the model catalogue.
  static const String catalogueAssetPath = 'assets/models_catalogue.json';

  // ------------------------------------------------------------- HuggingFace
  static const String huggingFaceApiBase = 'https://huggingface.co/api/models';
  static const String huggingFaceBase = 'https://huggingface.co';

  /// The auto-update check runs at most once per model per this window.
  static const Duration updateCheckThrottle = Duration(hours: 24);

  /// Timeout for metadata calls. Metadata is small; a slow response should just
  /// be abandoned rather than holding a socket open.
  static const Duration metadataTimeout = Duration(seconds: 20);

  // ---------------------------------------------------------------- inference
  /// Context length floor/ceiling for the settings slider when a model declares
  /// nothing more specific.
  static const int minContextLength = 512;
  static const int defaultContextLength = 4096;

  /// A 512-token context is smaller than most system prompts. Below this the
  /// app warns rather than silently truncating the conversation.
  static const int unsafeContextLength = 1024;

  /// Default sampling. These match the model cards' own recommendations.
  static const double defaultTemperature = 0.6;
  static const double defaultTopP = 0.95;
  static const int defaultTopK = 20;

  /// Qwythos's card documents repetition loops below this temperature.
  static const double repetitionRiskTemperature = 0.3;

  /// Default number of layers offered to the GPU. 99 means "all".
  static const int defaultGpuLayers = 0;

  /// Rough characters-per-token ratio used for the live context estimate while
  /// streaming. Real counts come from fllamaTokenize once a turn completes.
  static const double averageCharsPerToken = 4.0;

  /// How many recent messages are sent to the model. Guards against a long
  /// conversation silently blowing past the context window.
  static const int maxMessagesInContext = 40;

  /// How many llama.cpp sequences the pinned fllama build runs per context.
  ///
  /// Not a choice this app can make. At the pinned ref `fllama.cpp` sets
  /// `params.n_parallel = ServerManager::DEFAULT_N_PARALLEL` for every request,
  /// and `fllama_inference_queue.h` defines that as 4; the request's own
  /// `nParallel` field is documented as a web-only override. llama.cpp then
  /// divides the requested context between the sequences whenever the KV cache
  /// is not unified - `n_ctx_seq = n_ctx / n_seq_max` in `llama-context.cpp` -
  /// and fllama leaves `kv_unified` at its `false` default. A request for 8192
  /// tokens therefore gives each conversation 2048, while the KV cache is still
  /// allocated for the whole 8192.
  static const int parallelSlots = 4;

  /// The window one conversation actually gets from a requested total.
  ///
  /// llama.cpp pads the per-sequence figure up to a multiple of 256, so the
  /// real value can be slightly larger than this - never smaller, which is the
  /// direction that matters for a budget. The only case that returns the input
  /// unchanged is a request too small to divide at all.
  static int perChatContextLength(int requestedContextLength) {
    if (requestedContextLength <= 0) return requestedContextLength;
    final perSlot = requestedContextLength ~/ parallelSlots;
    final padded = perSlot < 256 ? 256 : perSlot;
    return padded > requestedContextLength ? requestedContextLength : padded;
  }
}
