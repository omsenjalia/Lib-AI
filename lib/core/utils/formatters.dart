/// Small pure formatting helpers. Kept Flutter-free so they are unit testable.
library;

/// Formats a byte count the way a file manager does (decimal units, 1 decimal
/// place above 100 MB) so the number matches what HuggingFace displays.
///
/// The catalogue's `sizeGb` values were derived from the same convention, which
/// is why a 5,841,049,120-byte file reads as 5.84 GB in both places.
String formatBytes(int bytes, {int decimals = 2}) {
  if (bytes < 0) return '0 B';
  if (bytes < 1000) return '$bytes B';

  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1000;
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }

  // Above 100 MB a single decimal is plenty and keeps card layouts stable.
  final places = value >= 100 ? 1 : decimals;
  return '${value.toStringAsFixed(places)} ${units[unit]}';
}

/// Formats a transfer rate.
String formatSpeed(double bytesPerSecond) {
  if (bytesPerSecond <= 0) return '--';
  return '${formatBytes(bytesPerSecond.round())}/s';
}

/// Formats a remaining duration as a short, human string.
///
/// Deliberately coarse: an ETA that counts down by the second is noise, and
/// download speeds on a phone fluctuate enough that the precision would be
/// false anyway.
String formatDuration(Duration d) {
  if (d.inSeconds <= 0) return '--';
  if (d.inSeconds < 60) return '${d.inSeconds}s';
  if (d.inMinutes < 60) {
    final seconds = d.inSeconds % 60;
    return seconds == 0 ? '${d.inMinutes}m' : '${d.inMinutes}m ${seconds}s';
  }
  final minutes = d.inMinutes % 60;
  return minutes == 0 ? '${d.inHours}h' : '${d.inHours}h ${minutes}m';
}

/// Relative timestamp for the conversation list: "just now", "12m", "3h",
/// "Yesterday", then a date.
String formatRelativeTime(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(time);

  if (diff.isNegative || diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';

  final today = DateTime(reference.year, reference.month, reference.day);
  final that = DateTime(time.year, time.month, time.day);
  final dayDiff = today.difference(that).inDays;
  if (dayDiff == 1) return 'Yesterday';
  if (dayDiff < 7) return '${dayDiff}d ago';

  return '${time.day.toString().padLeft(2, '0')}/'
      '${time.month.toString().padLeft(2, '0')}/${time.year}';
}

/// Absolute timestamp used in PDF exports and message metadata.
String formatAbsoluteTime(DateTime time) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}';
}

/// File-system-safe slug for export filenames and model directories.
String slugify(String input, {int maxLength = 60}) {
  final cleaned = input
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (cleaned.isEmpty) return 'untitled';
  return cleaned.length <= maxLength ? cleaned : cleaned.substring(0, maxLength);
}

/// Auto-generates a conversation title from its first user message.
///
/// Mirrors how Claude labels chats: take the opening question, collapse
/// whitespace, and cut at a word boundary rather than mid-word.
String autoTitleFromMessage(String message, {int maxLength = 48}) {
  final flat = message.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.isEmpty) return 'New chat';
  if (flat.length <= maxLength) return flat;

  final cut = flat.substring(0, maxLength);
  final lastSpace = cut.lastIndexOf(' ');
  final trimmed = lastSpace > maxLength * 0.5 ? cut.substring(0, lastSpace) : cut;
  return '${trimmed.trimRight()}...';
}
