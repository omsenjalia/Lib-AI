import 'package:flutter/material.dart';

import 'claude_tokens.dart';

/// Library AI's Material themes, built entirely from the Claude token set.
///
/// Two rules run through this file:
///
///  * **No elevation.** Every surface is flat; depth is expressed as a colour
///    step (`canvas` → `surfaceSoft` → `surfaceCard`) and a 1 px hairline. No
///    Material widget in the app is allowed a shadow, so every theme entry that
///    could introduce one is pinned to zero.
///  * **One accent.** `primary` is the only saturated colour in the interface.
///    Nothing else is allowed to compete with it.
///
/// ## Why accent-coloured *fills* use `primaryActive`
///
/// The reference paints label-bearing accent buttons in coral `#CC785C`, which
/// measures 3.3:1 against white — enough for the icon-only compose button, not
/// enough for a 14 px word. Every accent surface that carries a label therefore
/// uses `primaryActive` `#A9583E` (5.1:1), while icon-only accent fills keep the
/// transcribed `primary`. This is the one visual place the shell intentionally
/// differs from the reference, and it is a contrast requirement rather than a
/// taste call.
abstract final class AppTheme {
  static ThemeData dark() => _build(ClaudeTokens.dark);

  static ThemeData light() => _build(ClaudeTokens.light);

  static ThemeData _build(ClaudeTokens tokens) {
    final scheme = ColorScheme(
      brightness: tokens.isDark ? Brightness.dark : Brightness.light,
      primary: tokens.primaryActive,
      onPrimary: tokens.onPrimary,
      primaryContainer: tokens.primary,
      onPrimaryContainer: tokens.onPrimary,
      secondary: tokens.primary,
      onSecondary: tokens.onPrimary,
      tertiary: tokens.success,
      onTertiary: tokens.onPrimary,
      error: tokens.error,
      onError: Colors.white,
      surface: tokens.canvas,
      onSurface: tokens.ink,
      surfaceContainerLowest: tokens.canvas,
      surfaceContainerLow: tokens.surfaceSoft,
      surfaceContainer: tokens.surfaceCard,
      surfaceContainerHigh: tokens.surfaceCard,
      surfaceContainerHighest: tokens.surfaceStrong,
      onSurfaceVariant: tokens.muted,
      outline: tokens.hairline,
      outlineVariant: tokens.hairlineSoft,
      // Zero elevation everywhere, including the shadow colour itself so a
      // stray `elevation` on a widget cannot paint grey.
      shadow: Colors.transparent,
      scrim: tokens.scrim,
      inverseSurface: tokens.ink,
      onInverseSurface: tokens.canvas,
      inversePrimary: tokens.onPrimary,
    );

    final text = _textTheme(tokens);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      extensions: <ThemeExtension<dynamic>>[tokens],
      // One family for every control and body run. Display copy opts into Lora
      // through the type tokens rather than through the theme default.
      fontFamily: ClaudeType.ui,
      textTheme: text,
      scaffoldBackgroundColor: tokens.canvas,
      canvasColor: tokens.canvas,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        foregroundColor: tokens.ink,
        titleTextStyle: ClaudeType.titleSmall.copyWith(color: tokens.ink),
      ),
      iconTheme: IconThemeData(color: tokens.muted, size: 22),
      dividerTheme: DividerThemeData(
        color: tokens.hairline,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: tokens.muted,
        textColor: tokens.ink,
        titleTextStyle: ClaudeType.bodySmall.copyWith(color: tokens.bodyStrong),
      ),
      cardTheme: CardThemeData(
        color: tokens.surfaceCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ClaudeRadius.lg),
          side: BorderSide(color: tokens.hairline),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: tokens.surfaceCard,
        side: BorderSide(color: tokens.hairline),
        labelStyle: ClaudeType.caption.copyWith(color: tokens.body),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ClaudeRadius.lg),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.surfaceSoft,
        hintStyle: ClaudeType.body.copyWith(color: tokens.muted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ClaudeRadius.pill),
          borderSide: BorderSide(color: tokens.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ClaudeRadius.pill),
          borderSide: BorderSide(color: tokens.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ClaudeRadius.pill),
          borderSide: BorderSide(color: tokens.primary, width: 1),
        ),
      ),
      // Buttons are flat-cornered: the reference has no rounded buttons
      // anywhere, and the 0 dp radius is a load-bearing part of the look.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: tokens.primaryActive,
          foregroundColor: tokens.onPrimary,
          disabledBackgroundColor: tokens.primaryDisabled,
          disabledForegroundColor: tokens.muted,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          minimumSize: const Size(0, 44),
          textStyle: ClaudeType.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.ink,
          side: BorderSide(color: tokens.hairline),
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          minimumSize: const Size(0, 44),
          textStyle: ClaudeType.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tokens.primaryActive,
          textStyle: ClaudeType.button,
          minimumSize: const Size(0, ClaudeSpacing.minTouchTarget),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: tokens.primary,
        inactiveTrackColor: tokens.surfaceStrong,
        thumbColor: tokens.primary,
        overlayColor: tokens.primary.withValues(alpha: 0.14),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return tokens.onPrimary;
          return tokens.muted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return tokens.primary;
          return tokens.surfaceStrong;
        }),
        trackOutlineColor: WidgetStatePropertyAll(tokens.hairline),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.sheetSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        // The handle is drawn by the sheet widgets themselves, at the size the
        // tokens specify (32 x 4).
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(ClaudeRadius.sheet)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.sheetSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ClaudeRadius.xl),
        ),
        titleTextStyle: ClaudeType.titleSmall.copyWith(color: tokens.ink),
        contentTextStyle: ClaudeType.bodySmall.copyWith(color: tokens.body),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: tokens.sheetSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ClaudeRadius.lg),
          side: BorderSide(color: tokens.hairline),
        ),
        textStyle: ClaudeType.bodySmall.copyWith(color: tokens.ink),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: tokens.codeSurface,
        contentTextStyle: ClaudeType.bodySmall.copyWith(color: tokens.onCode),
        actionTextColor: tokens.primary,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ClaudeRadius.lg),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: tokens.primary,
        linearTrackColor: tokens.hairline,
        linearMinHeight: 2,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: tokens.codeSurface,
          borderRadius: BorderRadius.circular(ClaudeRadius.sm),
        ),
        textStyle: ClaudeType.caption.copyWith(color: tokens.onCode),
      ),
      // The banner is a message, not a raised surface: flat fill, hairline
      // edges, no elevation.
      bannerTheme: MaterialBannerThemeData(
        backgroundColor: tokens.surfaceCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        dividerColor: tokens.hairline,
        contentTextStyle: ClaudeType.bodySmall.copyWith(color: tokens.body),
      ),
    );
  }

  static TextTheme _textTheme(ClaudeTokens t) => TextTheme(
        displayLarge: ClaudeType.displayLarge.copyWith(color: t.ink),
        displayMedium: ClaudeType.heading.copyWith(color: t.ink),
        displaySmall: ClaudeType.greeting.copyWith(color: t.ink),
        headlineMedium: ClaudeType.heading.copyWith(color: t.ink),
        headlineSmall: ClaudeType.titleSmall.copyWith(color: t.ink),
        titleLarge: ClaudeType.title.copyWith(color: t.ink),
        titleMedium: ClaudeType.titleSmall.copyWith(
          fontWeight: FontWeight.w500,
          color: t.ink,
        ),
        titleSmall: ClaudeType.caption.copyWith(color: t.bodyStrong),
        bodyLarge: ClaudeType.body.copyWith(color: t.ink),
        bodyMedium: ClaudeType.bodySmall.copyWith(color: t.body),
        bodySmall: ClaudeType.caption.copyWith(
          color: t.muted,
          fontWeight: FontWeight.w400,
        ),
        labelLarge: ClaudeType.button.copyWith(color: t.ink),
        labelMedium: ClaudeType.caption.copyWith(
          color: t.muted,
          fontWeight: FontWeight.w400,
        ),
        labelSmall: ClaudeType.captionCaps.copyWith(
          color: t.muted,
          fontSize: 10,
        ),
      );
}
