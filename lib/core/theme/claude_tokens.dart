import 'package:flutter/material.dart';

/// Anthropic's chat-surface design tokens, as Flutter constants.
///
/// These are transcribed from Anthropic's own published token document (the
/// chat surface, not the marketing surface) and then cross-checked against the
/// current App Store and Play Store captures. The checks that mattered:
///
///  * `canvas` `#FAF9F5` — sampled `rgb(249,248,244)` off an App Store capture,
///    a per-channel delta of 1, i.e. the token is right.
///  * `surfaceSoft` `#F5F0E8` — the user bubble sampled `rgb(241,238,231)`.
///    Within JPEG error of the token, so the token is used rather than a
///    sampled approximation.
///  * `primary` `#CC785C` — the compose button sampled `rgb(220,115,87)`; the
///    same colour within the error of a 40 px circle in a 350 px wide JPEG.
///
/// The full cross-check, including the two places where the reference and the
/// tokens disagree, is in `docs/CLAUDE_UI_INVENTORY.md`.
///
/// Two values are marked `derived` below. They are the only values in this file
/// that are not a direct transcription, each for a stated reason.
abstract final class ClaudeColors {
  // ------------------------------------------------------------------- light
  /// The warm ivory floor of the entire interface.
  static const canvas = Color(0xFFFAF9F5);

  /// One step up from the canvas: the user's message bubble, the search field.
  static const surfaceSoft = Color(0xFFF5F0E8);

  /// Cards, sheets, the sidebar.
  static const surfaceCard = Color(0xFFEFE9DE);

  /// The deepest cream, for pressed and selected states on cream.
  static const surfaceCreamStrong = Color(0xFFE8E0D2);

  static const ink = Color(0xFF141413);
  static const bodyStrong = Color(0xFF252523);
  static const body = Color(0xFF3D3D3A);
  static const muted = Color(0xFF6C6A64);

  /// Decorative only. At 3.2:1 on the canvas this fails AA for text, so nothing
  /// the user has to read is painted in it — hints and timestamps use [muted].
  static const mutedSoft = Color(0xFF8E8B82);

  static const hairline = Color(0xFFE6DFD8);
  static const hairlineSoft = Color(0xFFEBE6DF);

  // ------------------------------------------------------------------ accent
  /// The single accent. Coral, used for the mark, the compose button, links and
  /// the primary action — and for nothing else.
  static const primary = Color(0xFFCC785C);

  /// Pressed state, and the fill for every accent surface that carries a label
  /// (see [AppTheme] for why).
  static const primaryActive = Color(0xFFA9583E);

  static const primaryDisabled = Color(0xFFE6DFD8);
  static const onPrimary = Color(0xFFFFFFFF);

  // -------------------------------------------------------------------- dark
  /// The dark canvas. Also the code-block surface in *both* modes: the design
  /// system treats dark surfaces as the place product chrome lives.
  static const surfaceDark = Color(0xFF181715);

  /// Subtle elevation on dark.
  static const surfaceDarkSoft = Color(0xFF1F1E1B);

  /// Cards, sheets and the sidebar on dark.
  static const surfaceDarkElevated = Color(0xFF252320);

  static const onDark = Color(0xFFFAF9F5);

  /// Warm grey for secondary text on dark. 6.6:1 on [surfaceDark].
  static const onDarkSoft = Color(0xFFA09D96);

  // ------------------------------------------------------------- status hues
  static const success = Color(0xFF5DB872);
  static const warning = Color(0xFFD4A017);
  static const error = Color(0xFFC64545);

  /// **Derived.** [error] measures 3.7:1 on [surfaceDark], which fails AA for
  /// text. This is the same hue lifted until it clears 4.5:1 — 5.6:1 on the
  /// canvas and 4.9:1 on a sheet — and is used only for error text and glyphs on
  /// dark surfaces. Error *fills* on dark keep the transcribed [error].
  static const errorOnDark = Color(0xFFD1786A);

  /// **Derived.** [warning] and [success] are specified for dark product
  /// surfaces; on the cream canvas they measure 2.3:1, which is not readable
  /// text. These are the same hues taken down to AA on [canvas] — 5.2:1 and
  /// 5.6:1 respectively — and are what light mode uses for status text.
  static const warningOnLight = Color(0xFF8F5F0E);
  static const successOnLight = Color(0xFF496C4C);

  /// **Derived.** The token document defines `hairline` for the cream canvas
  /// only; a warm dark line needs a different treatment. White at 12 %/8 %
  /// composites correctly over whichever dark surface it lands on, which a
  /// fixed hex value cannot do once a sheet stacks on the canvas.
  static const hairlineOnDark = Color(0x1FFFFFFF);
  static const hairlineSoftOnDark = Color(0x14FFFFFF);

  /// The scrim behind the sidebar and modal sheets: black at 40 %.
  static const scrim = Color(0x66000000);
}

/// Motion tokens. Every transition in the shell picks one of these rather than
/// an inline duration, which is what makes the animations feel like one system.
abstract final class ClaudeMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 500);

  /// The streaming cursor blink.
  static const Duration cursorBlink = Duration(milliseconds: 600);

  /// Stagger between suggestion chips as they arrive.
  static const Duration chipStagger = Duration(milliseconds: 60);

  /// The documented ease-out is `cubic-bezier(0.32, 0.72, 0, 1)`. Flutter's
  /// `decelerate` is the closest built-in curve; the difference over 280 ms is
  /// not perceptible.
  static const Curve easeOut = Curves.decelerate;

  /// For sheets and the sidebar, where the travel is large enough that the
  /// asymmetry of the emphasized curve reads.
  static const Curve easeEmphasized = Curves.easeInOutCubicEmphasized;
}

/// Corner radii. Flat buttons, 12 dp cards, 18 dp bubbles with one 4 dp corner,
/// 24 dp pills. Nothing in the shell uses a radius outside this list.
abstract final class ClaudeRadius {
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;

  /// Pills: the composer field, the search field.
  static const double pill = 24;

  /// Message bubbles, with [bubbleTail] on the bottom-right corner.
  static const double bubble = 18;
  static const double bubbleTail = 4;

  static const double sheet = 16;
  static const double full = 999;
}

/// The 4 dp sub-grid the tokens are built on.
abstract final class ClaudeSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// The chat top bar.
  static const double topBarHeight = 56;

  /// A sidebar conversation row.
  static const double sidebarRowHeight = 52;

  /// Minimum touch target, per the platform guidelines and the checklist.
  static const double minTouchTarget = 48;
}

/// Type scale.
///
/// Copernicus and Styrene B are licensed and not distributable, so the
/// documented substitutes are used: Lora for display, Lato for every control
/// and body run, JetBrains Mono for code. Weights are limited to the faces that
/// actually ship: Lato 400/500/700, and Lora and JetBrains Mono held at their
/// variable files' default of 400, which is the only weight either is used at.
abstract final class ClaudeType {
  static const String display = 'Lora';
  static const String ui = 'Lato';
  static const String mono = 'JetBrainsMono';

  /// The home-screen greeting and any large editorial line.
  static const TextStyle greeting = TextStyle(
    fontFamily: display,
    fontSize: 28,
    height: 1.2,
    letterSpacing: -0.4,
    fontWeight: FontWeight.w400,
  );

  /// 32 px display.
  static const TextStyle displayLarge = TextStyle(
    fontFamily: display,
    fontSize: 32,
    height: 1.15,
    letterSpacing: -0.5,
    fontWeight: FontWeight.w400,
  );

  /// 24 px heading.
  static const TextStyle heading = TextStyle(
    fontFamily: display,
    fontSize: 24,
    height: 1.2,
    letterSpacing: -0.4,
    fontWeight: FontWeight.w400,
  );

  /// 20 px title.
  static const TextStyle title = TextStyle(
    fontFamily: ui,
    fontSize: 20,
    height: 1.3,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle titleSmall = TextStyle(
    fontFamily: ui,
    fontSize: 16,
    height: 1.4,
    fontWeight: FontWeight.w500,
  );

  /// 16 px body. Line height stays at 1.65 — the tokens never go below 1.5.
  static const TextStyle body = TextStyle(
    fontFamily: ui,
    fontSize: 16,
    height: 1.65,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: ui,
    fontSize: 14,
    height: 1.55,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: ui,
    fontSize: 12,
    height: 1.4,
    fontWeight: FontWeight.w500,
  );

  /// Section headers in the sidebar and Settings: 12 px, uppercase, tracked.
  static const TextStyle captionCaps = TextStyle(
    fontFamily: ui,
    fontSize: 12,
    height: 1.4,
    letterSpacing: 1.5,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle button = TextStyle(
    fontFamily: ui,
    fontSize: 14,
    height: 1,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle code = TextStyle(
    fontFamily: mono,
    fontSize: 12.5,
    height: 1.6,
  );

  /// The chat body face, honouring the "Chat font" preference.
  ///
  /// Lora is offered as an option because some people read long answers more
  /// comfortably in a serif; the tokens' own display face is the natural
  /// choice for it. `system` drops back to the platform default.
  static TextStyle chatBody(ChatFontFamily family) {
    switch (family) {
      case ChatFontFamily.lato:
        return body;
      case ChatFontFamily.lora:
        return const TextStyle(
          fontFamily: display,
          fontSize: 16.5,
          height: 1.7,
              );
      case ChatFontFamily.system:
        return const TextStyle(fontSize: 16, height: 1.65);
    }
  }
}

/// Which face the chat transcript is set in.
enum ChatFontFamily {
  lato('lato', 'Lato'),
  lora('lora', 'Lora'),
  system('system', 'System');

  const ChatFontFamily(this.id, this.label);

  /// Stable identifier persisted in the settings table.
  final String id;

  /// Shown in the segmented control.
  final String label;

  static ChatFontFamily fromId(String? id) {
    for (final value in ChatFontFamily.values) {
      if (value.id == id) return value;
    }
    return ChatFontFamily.lato;
  }
}

/// The palette resolved for the active brightness.
///
/// Widgets read it through `context.tokens` instead of branching on
/// `Theme.of(context).brightness`, which keeps colour decisions in one place
/// and makes a wrong-brightness bug impossible to write.
@immutable
class ClaudeTokens extends ThemeExtension<ClaudeTokens> {
  const ClaudeTokens({
    required this.canvas,
    required this.surfaceSoft,
    required this.surfaceCard,
    required this.surfaceStrong,
    required this.ink,
    required this.bodyStrong,
    required this.body,
    required this.muted,
    required this.mutedSoft,
    required this.hairline,
    required this.hairlineSoft,
    required this.primary,
    required this.primaryActive,
    required this.primaryDisabled,
    required this.onPrimary,
    required this.codeSurface,
    required this.onCode,
    required this.sheetSurface,
    required this.sidebarSurface,
    required this.bubble,
    required this.scrim,
    required this.error,
    required this.errorText,
    required this.success,
    required this.warning,
    required this.onDark,
    required this.isDark,
  });

  final Color canvas;
  final Color surfaceSoft;
  final Color surfaceCard;
  final Color surfaceStrong;
  final Color ink;
  final Color bodyStrong;
  final Color body;
  final Color muted;
  final Color mutedSoft;
  final Color hairline;
  final Color hairlineSoft;
  final Color primary;
  final Color primaryActive;
  final Color primaryDisabled;
  final Color onPrimary;
  final Color codeSurface;
  final Color onCode;
  final Color sheetSurface;
  final Color sidebarSurface;
  final Color bubble;
  final Color scrim;
  final Color error;
  final Color errorText;
  final Color success;
  final Color warning;
  final Color onDark;
  final bool isDark;

  static const ClaudeTokens light = ClaudeTokens(
    canvas: ClaudeColors.canvas,
    surfaceSoft: ClaudeColors.surfaceSoft,
    surfaceCard: ClaudeColors.surfaceCard,
    surfaceStrong: ClaudeColors.surfaceCreamStrong,
    ink: ClaudeColors.ink,
    bodyStrong: ClaudeColors.bodyStrong,
    body: ClaudeColors.body,
    muted: ClaudeColors.muted,
    mutedSoft: ClaudeColors.mutedSoft,
    hairline: ClaudeColors.hairline,
    hairlineSoft: ClaudeColors.hairlineSoft,
    primary: ClaudeColors.primary,
    primaryActive: ClaudeColors.primaryActive,
    primaryDisabled: ClaudeColors.primaryDisabled,
    onPrimary: ClaudeColors.onPrimary,
    codeSurface: ClaudeColors.surfaceDark,
    onCode: ClaudeColors.onDark,
    sheetSurface: ClaudeColors.surfaceCard,
    sidebarSurface: ClaudeColors.surfaceCard,
    bubble: ClaudeColors.surfaceSoft,
    scrim: ClaudeColors.scrim,
    error: ClaudeColors.error,
    errorText: ClaudeColors.error,
    success: ClaudeColors.successOnLight,
    warning: ClaudeColors.warningOnLight,
    onDark: ClaudeColors.onDark,
    isDark: false,
  );

  static const ClaudeTokens dark = ClaudeTokens(
    canvas: ClaudeColors.surfaceDark,
    surfaceSoft: ClaudeColors.surfaceDarkSoft,
    surfaceCard: ClaudeColors.surfaceDarkElevated,
    // No fourth dark surface exists in the tokens: pressed rows step up to the
    // elevated surface, which is already distinguishable on the dark canvas.
    surfaceStrong: ClaudeColors.surfaceDarkElevated,
    ink: ClaudeColors.onDark,
    bodyStrong: ClaudeColors.onDark,
    body: ClaudeColors.onDarkSoft,
    muted: ClaudeColors.onDarkSoft,
    mutedSoft: ClaudeColors.onDarkSoft,
    hairline: ClaudeColors.hairlineOnDark,
    hairlineSoft: ClaudeColors.hairlineSoftOnDark,
    primary: ClaudeColors.primary,
    primaryActive: ClaudeColors.primaryActive,
    primaryDisabled: ClaudeColors.surfaceDarkElevated,
    onPrimary: ClaudeColors.onPrimary,
    codeSurface: ClaudeColors.surfaceDarkSoft,
    onCode: ClaudeColors.onDark,
    sheetSurface: ClaudeColors.surfaceDarkElevated,
    sidebarSurface: ClaudeColors.surfaceDarkElevated,
    bubble: ClaudeColors.surfaceDarkElevated,
    scrim: ClaudeColors.scrim,
    error: ClaudeColors.error,
    errorText: ClaudeColors.errorOnDark,
    success: ClaudeColors.success,
    warning: ClaudeColors.warning,
    onDark: ClaudeColors.onDark,
    isDark: true,
  );

  @override
  ClaudeTokens copyWith({
    Color? canvas,
    Color? surfaceSoft,
    Color? surfaceCard,
    Color? surfaceStrong,
    Color? ink,
    Color? bodyStrong,
    Color? body,
    Color? muted,
    Color? mutedSoft,
    Color? hairline,
    Color? hairlineSoft,
    Color? primary,
    Color? primaryActive,
    Color? primaryDisabled,
    Color? onPrimary,
    Color? codeSurface,
    Color? onCode,
    Color? sheetSurface,
    Color? sidebarSurface,
    Color? bubble,
    Color? scrim,
    Color? error,
    Color? errorText,
    Color? success,
    Color? warning,
    Color? onDark,
    bool? isDark,
  }) {
    return ClaudeTokens(
      canvas: canvas ?? this.canvas,
      surfaceSoft: surfaceSoft ?? this.surfaceSoft,
      surfaceCard: surfaceCard ?? this.surfaceCard,
      surfaceStrong: surfaceStrong ?? this.surfaceStrong,
      ink: ink ?? this.ink,
      bodyStrong: bodyStrong ?? this.bodyStrong,
      body: body ?? this.body,
      muted: muted ?? this.muted,
      mutedSoft: mutedSoft ?? this.mutedSoft,
      hairline: hairline ?? this.hairline,
      hairlineSoft: hairlineSoft ?? this.hairlineSoft,
      primary: primary ?? this.primary,
      primaryActive: primaryActive ?? this.primaryActive,
      primaryDisabled: primaryDisabled ?? this.primaryDisabled,
      onPrimary: onPrimary ?? this.onPrimary,
      codeSurface: codeSurface ?? this.codeSurface,
      onCode: onCode ?? this.onCode,
      sheetSurface: sheetSurface ?? this.sheetSurface,
      sidebarSurface: sidebarSurface ?? this.sidebarSurface,
      bubble: bubble ?? this.bubble,
      scrim: scrim ?? this.scrim,
      error: error ?? this.error,
      errorText: errorText ?? this.errorText,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      onDark: onDark ?? this.onDark,
      isDark: isDark ?? this.isDark,
    );
  }

  /// Interpolates through Material's [Color.lerp] so a light/dark switch blends
  /// rather than snapping.
  @override
  ClaudeTokens lerp(covariant ClaudeTokens? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return ClaudeTokens(
      canvas: mix(canvas, other.canvas),
      surfaceSoft: mix(surfaceSoft, other.surfaceSoft),
      surfaceCard: mix(surfaceCard, other.surfaceCard),
      surfaceStrong: mix(surfaceStrong, other.surfaceStrong),
      ink: mix(ink, other.ink),
      bodyStrong: mix(bodyStrong, other.bodyStrong),
      body: mix(body, other.body),
      muted: mix(muted, other.muted),
      mutedSoft: mix(mutedSoft, other.mutedSoft),
      hairline: mix(hairline, other.hairline),
      hairlineSoft: mix(hairlineSoft, other.hairlineSoft),
      primary: mix(primary, other.primary),
      primaryActive: mix(primaryActive, other.primaryActive),
      primaryDisabled: mix(primaryDisabled, other.primaryDisabled),
      onPrimary: mix(onPrimary, other.onPrimary),
      codeSurface: mix(codeSurface, other.codeSurface),
      onCode: mix(onCode, other.onCode),
      sheetSurface: mix(sheetSurface, other.sheetSurface),
      sidebarSurface: mix(sidebarSurface, other.sidebarSurface),
      bubble: mix(bubble, other.bubble),
      scrim: mix(scrim, other.scrim),
      error: mix(error, other.error),
      errorText: mix(errorText, other.errorText),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      onDark: mix(onDark, other.onDark),
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

/// `context.tokens` — one lookup, no brightness branching at the call site.
extension ClaudeTokensContext on BuildContext {
  ClaudeTokens get tokens {
    final theme = Theme.of(this);
    return theme.extension<ClaudeTokens>() ??
        (theme.brightness == Brightness.dark
            ? ClaudeTokens.dark
            : ClaudeTokens.light);
  }
}
