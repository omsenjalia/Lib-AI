import { Easing } from 'react-native-reanimated';

/**
 * Design tokens. Values come from the reference inventory in
 * docs/CLAUDE_UI_INVENTORY.md, checked against device captures: warm ivory
 * canvas, near-black ink, one clay accent, no shadows, no gradients. Dark mode
 * is designed, not inverted: the same hierarchy on warm charcoal.
 *
 * Components read colours from `useTheme().colors`, never from raw hex.
 */
export type Palette = {
  canvas: string;
  surface: string;
  surfaceSoft: string;
  surfaceRaised: string;
  sidebar: string;
  ink: string;
  bodyStrong: string;
  body: string;
  muted: string;
  mutedSoft: string;
  hairline: string;
  hairlineSoft: string;
  primary: string;
  primaryPressed: string;
  primaryWash: string;
  onPrimary: string;
  codeSurface: string;
  codeInk: string;
  codeMuted: string;
  success: string;
  warning: string;
  error: string;
  errorWash: string;
  scrim: string;
  userBubble: string;
};

export const light: Palette = {
  canvas: '#FAF9F5',
  surface: '#FFFFFF',
  surfaceSoft: '#F5F0E8',
  surfaceRaised: '#EFE9DE',
  sidebar: '#F3EFE7',
  ink: '#141413',
  bodyStrong: '#252523',
  body: '#3D3D3A',
  muted: '#6C6A64',
  mutedSoft: '#8E8B82',
  hairline: '#E6DFD8',
  hairlineSoft: '#EBE6DF',
  primary: '#CC785C',
  primaryPressed: '#A9583E',
  primaryWash: 'rgba(204,120,92,0.12)',
  onPrimary: '#FFFFFF',
  codeSurface: '#181715',
  codeInk: '#FAF9F5',
  codeMuted: '#A09D96',
  success: '#496C4C',
  warning: '#8F5F0E',
  error: '#B23B3B',
  errorWash: 'rgba(198,69,69,0.08)',
  scrim: 'rgba(20,20,19,0.38)',
  userBubble: '#EFE9DE',
};

export const dark: Palette = {
  canvas: '#1F1E1B',
  surface: '#262522',
  surfaceSoft: '#2B2A26',
  surfaceRaised: '#32302C',
  sidebar: '#181715',
  ink: '#F4F2EC',
  bodyStrong: '#E8E5DD',
  body: '#D2CFC7',
  muted: '#A09D96',
  mutedSoft: '#7E7B74',
  hairline: 'rgba(255,255,255,0.10)',
  hairlineSoft: 'rgba(255,255,255,0.06)',
  primary: '#D4876C',
  primaryPressed: '#CC785C',
  primaryWash: 'rgba(212,135,108,0.16)',
  onPrimary: '#1F1E1B',
  codeSurface: '#141412',
  codeInk: '#F4F2EC',
  codeMuted: '#8E8B82',
  success: '#7FBF8A',
  warning: '#D4A84A',
  error: '#E08A7C',
  errorWash: 'rgba(224,138,124,0.10)',
  scrim: 'rgba(0,0,0,0.55)',
  userBubble: '#33312C',
};

/** Font families as registered by expo-font (each weight is its own family on Android). */
export const fonts = {
  serif: 'Lora-Variable',
  serifItalic: 'Lora-Italic-Variable',
  sans: 'Lato-Regular',
  sansMedium: 'Lato-Medium',
  sansBold: 'Lato-Bold',
  sansItalic: 'Lato-Italic',
  mono: 'JetBrainsMono-Variable',
} as const;

export const type = {
  display: { fontSize: 30, lineHeight: 36, letterSpacing: -0.4 },
  heading: { fontSize: 22, lineHeight: 28, letterSpacing: -0.2 },
  title: { fontSize: 18, lineHeight: 24 },
  body: { fontSize: 16, lineHeight: 25 },
  bodySmall: { fontSize: 14, lineHeight: 20 },
  caption: { fontSize: 12, lineHeight: 16 },
  micro: { fontSize: 11, lineHeight: 14, letterSpacing: 0.3 },
} as const;

export const space = { xxs: 4, xs: 8, sm: 12, md: 16, lg: 24, xl: 32, xxl: 48 } as const;

/** Tighter on inner elements, softer on containers. */
export const radius = { xs: 6, sm: 8, md: 12, lg: 16, xl: 22, pill: 999 } as const;

export const motion = {
  fast: 150,
  base: 260,
  slow: 420,
  /** The reference ease-out, cubic-bezier(0.32, 0.72, 0, 1). */
  easeOut: Easing.bezier(0.32, 0.72, 0, 1),
  spring: { damping: 22, stiffness: 240, mass: 0.9 },
  softSpring: { damping: 26, stiffness: 180, mass: 1 },
} as const;

export const layout = {
  topBar: 56,
  maxReadingWidth: 760,
  sidebarWidthFraction: 0.84,
  sidebarMaxWidth: 340,
  minTouch: 44,
} as const;
