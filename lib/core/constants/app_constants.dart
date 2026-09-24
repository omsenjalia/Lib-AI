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
}
