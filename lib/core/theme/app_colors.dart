import 'package:flutter/material.dart';

/// Library AI's palette.
///
/// Dark-mode-first, built around a library/study aesthetic: deep charcoal,
/// candlelight amber, and near-white text on a night reading surface.
/// Deliberately unrelated to WeatherGPT's colour scheme.
///
/// The base colour is mirrored in `android/app/src/main/res/values/colors.xml`
/// so the Android window behind the Flutter surface matches exactly and cold
/// start never flashes a foreign colour.
abstract final class AppColors {
  // ---------------------------------------------------------------- dark mode
  /// App background. Deep charcoal.
  static const Color base = Color(0xFF1A1A2E);

  /// Raised surface: cards, sheets, bubbles, the sidebar.
  static const Color surface = Color(0xFF16213E);

  /// A step above [surface], for nested/raised elements like menus.
  static const Color surfaceHigh = Color(0xFF1F2B4D);

  /// Hairline borders and dividers.
  static const Color outline = Color(0xFF2E3A5C);

  /// Candlelight amber. The single accent, used sparingly so it keeps meaning.
  static const Color accent = Color(0xFFE8A838);

  /// Amber at low opacity, for tinted fills behind the accent.
  static const Color accentMuted = Color(0xFF3A2F1C);

  /// Near-white body text.
  static const Color textPrimary = Color(0xFFE8E8E8);

  /// Muted grey for metadata, timestamps, helper text.
  static const Color textSecondary = Color(0xFF8A8A9A);

  /// Soft red. Errors that need attention but should not shout.
  static const Color error = Color(0xFFD96C6C);

  /// Muted green. Confirmations that should not celebrate.
  static const Color success = Color(0xFF7FB069);

  /// Context meter states.
  static const Color meterNormal = accent;
  static const Color meterWarning = Color(0xFFD99A38);
  static const Color meterCritical = Color(0xFFD96C6C);

  // --------------------------------------------------------------- light mode
  /// Light mode is warm paper, not clinical white - it reads as a study desk.
  static const Color lightBase = Color(0xFFFAF7F2);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceHigh = Color(0xFFF2EDE4);
  static const Color lightOutline = Color(0xFFDDD5C8);

  /// Amber needs to darken considerably to hold contrast on a light surface.
  static const Color lightAccent = Color(0xFF9C6210);
  static const Color lightAccentMuted = Color(0xFFF6E8CE);

  static const Color lightTextPrimary = Color(0xFF1A1A2E);
  static const Color lightTextSecondary = Color(0xFF5F5F70);
  static const Color lightError = Color(0xFFB04A4A);
  static const Color lightSuccess = Color(0xFF4F7A3C);

  /// Message bubble fill for user messages (right-aligned, filled).
  static const Color userBubbleDark = Color(0xFF243254);
  static const Color userBubbleLight = Color(0xFFEDE4D3);

  /// Code block background, distinct from the surrounding surface.
  static const Color codeBackgroundDark = Color(0xFF10182C);
  static const Color codeBackgroundLight = Color(0xFFF4F1EA);
}
