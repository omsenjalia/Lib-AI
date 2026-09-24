import 'dart:io';

/// What the device can actually afford right now.
///
/// The catalogue carries a `ramRequirementGb` figure per model, derived for the
/// target device with nothing else running. That is the right number for a
/// *catalogue*, but it is the wrong number for a *decision*: the phone in
/// someone's hand has other apps on it, and the model they are about to load
/// may not be the only one resident (llama.cpp keeps the previous model alive
/// for around two minutes after a swap).
///
/// So the preflight reads the kernel's own estimate of what a new allocation
/// can get, and refuses the load when it is not enough. A refusal is a message
/// the user can act on; the alternative is a native allocation failure, which
/// on Android is a process kill with no Dart-level exception and therefore no
/// message at all.
abstract final class MemoryBudget {
  /// Headroom over the estimate.
  ///
  /// `MemAvailable` already accounts for reclaimable page cache, but it does
  /// not know that llama.cpp will ask for its buffers in a handful of large
  /// blocks, and it is sampled before the load rather than during it. Fifteen
  /// percent is a compromise: enough to stop the obvious over-commit, small
  /// enough that a marginal-but-workable model is not refused.
  static const double headroom = 1.15;

  /// Extra allowance per 1024 tokens of context beyond a model's recommended
  /// length, in bytes.
  ///
  /// The KV cache is not derivable from the catalogue: it depends on layer
  /// count, head count and head width, none of which the catalogue records.
  /// 200 MB per 1024 tokens is a deliberately pessimistic figure for the model
  /// sizes this app ships (a 7-8B model at 8k context lands near 1-1.5 GB).
  /// Pessimistic is the correct direction here: a refused load is recoverable,
  /// a native abort is not.
  static const int kvBytesPer1024Tokens = 200 * 1024 * 1024;

  /// Bytes a new allocation can expect to get, or null when unknown.
  ///
  /// Null means "do not preflight": iOS and the desktop shells do not expose
  /// `/proc/meminfo`, and refusing every load on those platforms because the
  /// number is missing would be worse than the crash this guards against.
  static Future<int?> availableBytes() async {
    if (!Platform.isAndroid && !Platform.isLinux) return null;
    try {
      return parseMemAvailable(await File(memInfoPath).readAsString());
    } catch (_) {
      // A missing or unreadable /proc is not an error worth surfacing; it just
      // means this device gets no preflight.
      return null;
    }
  }

  /// The parsing half of [availableBytes], exposed for tests: reading the file
  /// is the kernel's job, interpreting it is the part that can be wrong.
  static int? parseMemAvailable(String memInfo) {
    for (final line in memInfo.split('\n')) {
      if (!line.startsWith('MemAvailable:')) continue;
      final fields = line.split(RegExp(r'\s+'));
      if (fields.length < 2) return null;
      final kilobytes = int.tryParse(fields[1]);
      return kilobytes == null ? null : kilobytes * 1024;
    }
    return null;
  }

  /// The file the kernel exposes this through, on Android and Linux.
  static const String memInfoPath = '/proc/meminfo';

  /// Peak bytes needed to have [requirementGb] resident alongside anything the
  /// caller passes in [alsoResidentGb].
  ///
  /// [extraBytes] is for the vision projector when one is being loaded: the
  /// catalogue's `ramRequirementGb` is a per-model figure and does not say
  /// whether it counted the projector, and a projector is hundreds of megabytes
  /// that either fits or does not.
  static int peakRequirementBytes({
    required double requirementGb,
    double alsoResidentGb = 0,
    int contextLength = 0,
    int recommendedContextLength = 0,
    int extraBytes = 0,
  }) {
    var bytes = ((requirementGb + alsoResidentGb) * 1000 * 1000 * 1000).round();
    bytes += extraBytes;
    final extraTokens = contextLength - recommendedContextLength;
    if (recommendedContextLength > 0 && extraTokens > 0) {
      bytes += (extraTokens / 1024).ceil() * kvBytesPer1024Tokens;
    }
    return bytes;
  }

  /// Whether [available] can cover [required] with [headroom] to spare.
  static bool fits({required int available, required int required}) =>
      available >= required * headroom;
}
