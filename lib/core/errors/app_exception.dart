/// Errors surfaced to the user, each carrying a message that is actually
/// actionable rather than a stack trace.
sealed class AppException implements Exception {
  const AppException(this.message, {this.detail, this.recovery});

  /// Human-readable, shown in the UI.
  final String message;

  /// Technical detail, shown only in an expandable "details" area.
  final String? detail;

  /// What the user can do about it.
  final String? recovery;

  @override
  String toString() => '$runtimeType: $message${detail == null ? '' : ' ($detail)'}';
}

/// The GGUF file is missing from disk, or is present but unreadable.
class ModelFileMissingException extends AppException {
  const ModelFileMissingException(super.message, {super.detail})
      : super(recovery: 'Re-download the model from Model Library.');
}

/// The GGUF file exists but llama.cpp refused to load it.
class ModelCorruptException extends AppException {
  const ModelCorruptException(super.message, {super.detail})
      : super(
          recovery:
              'The file may be truncated. Delete it and download again.',
        );
}

/// Not enough free RAM to hold the model, its KV cache and the compute buffer.
///
/// This is the single most likely failure on an 8 GB device, so it gets its own
/// type and its own specific guidance.
class InsufficientMemoryException extends AppException {
  const InsufficientMemoryException(super.message, {super.detail})
      : super(
          recovery:
              'Choose a smaller quantisation (Q3_K_M or Q4_K_M), or lower the '
              'context length in Settings.',
        );
}

/// The user asked for a quantisation that the catalogue does not offer.
class UnknownQuantException extends AppException {
  const UnknownQuantException(super.message, {super.detail});
}

/// The native inference engine could not be loaded at all.
///
/// This is deliberately not a [ModelCorruptException]: nothing is wrong with
/// the user's files. It means llama.cpp is not in the build, which in practice
/// means the APK was produced without Flutter's native-assets step enabled, so
/// `libfllama.so` was never packaged. Rebuilding fixes it; no amount of
/// re-downloading a model will.
class EngineUnavailableException extends AppException {
  const EngineUnavailableException(super.message, {super.detail})
      : super(recovery: 'Reinstall the app from a release build.');
}

/// A download failed, or the bytes on disk did not match the expected hash.
class DownloadException extends AppException {
  const DownloadException(super.message, {super.detail, super.recovery});
}

/// The served file did not match the SHA-256 recorded in the catalogue.
class ChecksumMismatchException extends AppException {
  const ChecksumMismatchException(this.fileName, this.expected, this.actual)
      : super(
          'Downloaded file failed its integrity check.',
          detail: 'Expected $expected but got $actual',
          recovery: 'The download was corrupted in transit. Try again.',
        );

  final String fileName;
  final String expected;
  final String actual;
}

/// A modality was requested that the active model cannot provide.
class UnsupportedModalityException extends AppException {
  const UnsupportedModalityException(super.message)
      : super(
          recovery: 'Switch to a vision-capable model to use OCR mode.',
        );
}

/// The 27B download was attempted on mobile data.
class WifiRequiredException extends AppException {
  const WifiRequiredException(super.message)
      : super(recovery: 'Connect to Wi-Fi and try again.');
}

/// Thrown when an installation exists for a model the catalogue no longer
/// describes - normally because the app was updated and a model was retired.
///
/// Lives here rather than next to [ChatController] because [AppException] is
/// sealed: every subclass must stay inside this library.
class ModelMissingFromCatalogueException extends AppException {
  ModelMissingFromCatalogueException(String modelId)
      : super(
          'This model is no longer in the catalogue.',
          detail: 'No catalogue entry for $modelId',
          recovery:
              'Delete it from Model Library, then download a supported model.',
        );
}

/// Anything else, wrapped so the UI still gets a friendly string.
class UnknownAppException extends AppException {
  const UnknownAppException(super.message, {super.detail});
}
