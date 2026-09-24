import 'package:flutter/material.dart';

/// Library AI's own reading-room palette.
///
/// Warm paper and dark graphite are paired with a restrained clay accent and
/// quiet olive confirmations. The design takes broad inspiration from calm
/// editorial reading surfaces without reusing another product's identity,
/// colors, marks, or copy.
abstract final class AppColors {
  // ---------------------------------------------------------------- dark mode
  /// Warm graphite app background.
  static const Color base = Color(0xFF171918);

  /// Raised surface for cards, sheets, bubbles, and the sidebar.
  static const Color surface = Color(0xFF202321);

  /// A step above [surface], for nested or raised elements.
  static const Color surfaceHigh = Color(0xFF2B302D);

  /// Hairline borders and dividers.
  static const Color outline = Color(0xFF3B413D);

  /// Soft clay accent, bright enough to remain clear on dark surfaces.
  static const Color accent = Color(0xFFE6A58E);
  static const Color accentMuted = Color(0xFF3D2E29);

  /// Warm near-white reading text.
  static const Color textPrimary = Color(0xFFF1EEE7);

  /// Muted metadata; intentionally remains above 4.5:1 on the dark surface.
  static const Color textSecondary = Color(0xFFADB2AA);

  static const Color error = Color(0xFFF2988B);
  static const Color success = Color(0xFF9BC28D);

  /// Context meter states.
  static const Color meterNormal = accent;
  static const Color meterWarning = Color(0xFFE8B86B);
  static const Color lightMeterWarning = Color(0xFF8C570D);
  static const Color meterCritical = error;

  // --------------------------------------------------------------- light mode
  /// Warm paper canvas rather than clinical white.
  static const Color lightBase = Color(0xFFF7F5EF);
  static const Color lightSurface = Color(0xFFFFFEFB);
  static const Color lightSurfaceHigh = Color(0xFFEFECE5);
  static const Color lightOutline = Color(0xFFD6D2C9);

  /// Burnt-clay accent selected for strong contrast on light surfaces.
  static const Color lightAccent = Color(0xFFA34832);
  static const Color lightAccentMuted = Color(0xFFF4E0D8);

  static const Color lightTextPrimary = Color(0xFF242724);
  static const Color lightTextSecondary = Color(0xFF5D635C);
  static const Color lightError = Color(0xFFAC3730);
  static const Color lightSuccess = Color(0xFF496C4C);

  /// Message treatments and code areas.
  static const Color userBubbleDark = Color(0xFF303632);
  static const Color userBubbleLight = Color(0xFFEFE7DB);
  static const Color codeBackgroundDark = Color(0xFF131614);
  static const Color codeBackgroundLight = Color(0xFFF2EFE8);
}
