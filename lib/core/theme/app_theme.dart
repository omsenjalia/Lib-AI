import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Builds Library AI's Material 3 themes.
///
/// Dark mode is the primary design and is tuned first; light mode is a genuine
/// second design (warm paper stock) rather than a mechanical inversion, because
/// a study app that goes blinding-white at night is not intentional.
///
/// Note throughout: `withValues(alpha:)` is used instead of the deprecated
/// `withOpacity()`, and Material 3 `surfaceContainer*` roles are used instead of
/// the deprecated `background`/`surfaceVariant` pair.
abstract final class AppTheme {
  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.accent,
      onPrimary: AppColors.base,
      primaryContainer: AppColors.accentMuted,
      onPrimaryContainer: AppColors.accent,
      secondary: AppColors.accent,
      onSecondary: AppColors.base,
      tertiary: AppColors.success,
      onTertiary: AppColors.base,
      error: AppColors.error,
      onError: AppColors.base,
      surface: AppColors.base,
      onSurface: AppColors.textPrimary,
      surfaceContainerLowest: AppColors.base,
      surfaceContainerLow: AppColors.surface,
      surfaceContainer: AppColors.surface,
      surfaceContainerHigh: AppColors.surfaceHigh,
      surfaceContainerHighest: AppColors.surfaceHigh,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.outline,
      outlineVariant: AppColors.outline,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: AppColors.textPrimary,
      onInverseSurface: AppColors.base,
      inversePrimary: AppColors.base,
    );

    return _base(scheme).copyWith(
      scaffoldBackgroundColor: AppColors.base,
      cardTheme: _cardTheme(AppColors.surface, AppColors.outline),
      dividerTheme: const DividerThemeData(
        color: AppColors.outline,
        thickness: 1,
        space: 1,
      ),
    );
  }

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.lightAccent,
      onPrimary: Colors.white,
      primaryContainer: AppColors.lightAccentMuted,
      onPrimaryContainer: AppColors.lightAccent,
      secondary: AppColors.lightAccent,
      onSecondary: Colors.white,
      tertiary: AppColors.lightSuccess,
      onTertiary: Colors.white,
      error: AppColors.lightError,
      onError: Colors.white,
      surface: AppColors.lightBase,
      onSurface: AppColors.lightTextPrimary,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: AppColors.lightSurface,
      surfaceContainer: AppColors.lightSurface,
      surfaceContainerHigh: AppColors.lightSurfaceHigh,
      surfaceContainerHighest: AppColors.lightSurfaceHigh,
      onSurfaceVariant: AppColors.lightTextSecondary,
      outline: AppColors.lightOutline,
      outlineVariant: AppColors.lightOutline,
      shadow: Colors.black26,
      scrim: Colors.black45,
      inverseSurface: AppColors.lightTextPrimary,
      onInverseSurface: Colors.white,
      inversePrimary: AppColors.accent,
    );

    return _base(scheme).copyWith(
      scaffoldBackgroundColor: AppColors.lightBase,
      cardTheme: _cardTheme(AppColors.lightSurface, AppColors.lightOutline),
      dividerTheme: const DividerThemeData(
        color: AppColors.lightOutline,
        thickness: 1,
        space: 1,
      ),
    );
  }

  /// Everything the two modes share.
  static ThemeData _base(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    final textColor =
        isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final mutedColor =
        isDark ? AppColors.textSecondary : AppColors.lightTextSecondary;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Bundled locally; the app works identically in airplane mode.
      fontFamily: 'Inter',
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      textTheme: _textTheme(textColor, mutedColor).apply(fontFamily: 'Inter'),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: textColor,
        titleTextStyle: TextStyle(
          color: textColor,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      iconTheme: IconThemeData(color: mutedColor, size: 20),
      listTileTheme: ListTileThemeData(
        iconColor: mutedColor,
        textColor: textColor,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        side: BorderSide(color: scheme.outline),
        labelStyle: TextStyle(color: mutedColor, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        hintStyle: TextStyle(color: mutedColor, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textColor,
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.primary),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.14),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return mutedColor;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary.withValues(alpha: 0.35);
          }
          return scheme.surfaceContainerHighest;
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        showDragHandle: true,
        dragHandleColor: scheme.outline,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        titleTextStyle: TextStyle(
          color: textColor,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(color: mutedColor, fontSize: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle: TextStyle(color: textColor, fontSize: 14),
        actionTextColor: scheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        linearMinHeight: 4,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(color: textColor, fontSize: 12),
      ),
    );
  }

  static CardThemeData _cardTheme(Color fill, Color border) => CardThemeData(
        color: fill,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border),
        ),
      );

  static TextTheme _textTheme(Color primary, Color secondary) => TextTheme(
        displaySmall: TextStyle(
          color: primary,
          fontSize: 30,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.6,
        ),
        headlineMedium: TextStyle(
          color: primary,
          fontSize: 24,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
        headlineSmall: TextStyle(
          color: primary,
          fontSize: 19,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        titleMedium: TextStyle(
          color: primary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: TextStyle(
          color: primary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(color: primary, fontSize: 15.5, height: 1.6),
        bodyMedium: TextStyle(color: primary, fontSize: 14, height: 1.55),
        bodySmall: TextStyle(color: secondary, fontSize: 12, height: 1.45),
        labelLarge: TextStyle(
          color: primary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        labelMedium: TextStyle(color: secondary, fontSize: 11.5),
        labelSmall: TextStyle(color: secondary, fontSize: 10.5),
      );
}
