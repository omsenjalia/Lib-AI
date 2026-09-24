import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A subject tag pill.
///
/// The tag's own colour comes from SQLite (`SubjectTags.colorValue`) rather than
/// from the theme, so that the nine seeded tags stay visually distinct in both
/// light and dark mode. The text colour is derived from the tag colour's
/// luminance instead of being hard-coded, because the palette mixes light
/// (Maths) and dark (OS) hues and a fixed foreground would be unreadable on one
/// or the other.
class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.name,
    required this.colorValue,
    this.selected = false,
    this.onTap,
    this.onDeleted,
    this.compact = false,
  });

  final String name;

  /// ARGB value as stored in the database.
  final int colorValue;

  /// Filled style for the currently-filtered tag.
  final bool selected;

  final VoidCallback? onTap;
  final VoidCallback? onDeleted;

  /// Headline-only variant for message headers, where the tag is context rather
  /// than a control.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tagColor = Color(colorValue);
    final scheme = Theme.of(context).colorScheme;

    // Pick a foreground that holds contrast against the tag fill. Using the
    // same colour at full strength on a 22% tint keeps tags recognisable while
    // staying legible on the dark base.
    final foreground = _readableOn(tagColor, scheme.brightness);

    final background = selected
        ? tagColor.withValues(alpha: scheme.brightness == Brightness.dark
            ? 0.34
            : 0.22)
        : tagColor.withValues(alpha: 0.14);

    final chip = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 1 : 3,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: tagColor.withValues(alpha: selected ? 0.8 : 0.35),
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: foreground,
          fontSize: compact ? 10 : 11.5,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
    );

    final withDelete = onDeleted == null
        ? chip
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              chip,
              const SizedBox(width: 2),
              InkWell(
                onTap: onDeleted,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close_rounded,
                    size: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          );

    if (onTap == null) return withDelete;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: withDelete,
    );
  }

  /// Returns a version of [tagColor] with enough contrast against the surface.
  ///
  /// Dark mode lightens, light mode darkens. Doing this by mixing toward white
  /// or black preserves the hue, which is what makes a tag recognisable at a
  /// glance.
  static Color _readableOn(Color tagColor, Brightness brightness) {
    final hsl = HSLColor.fromColor(tagColor);
    if (brightness == Brightness.dark) {
      return hsl.withLightness(hsl.lightness.clamp(0.62, 0.80)).toColor();
    }
    return hsl.withLightness(hsl.lightness.clamp(0.26, 0.40)).toColor();
  }
}
