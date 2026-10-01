import * as Haptics from 'expo-haptics';
import type { Icon as PhosphorIcon } from 'phosphor-react-native';
import { forwardRef, type ReactNode } from 'react';
import {
  Platform,
  Pressable,
  Text as RNText,
  View,
  type PressableProps,
  type StyleProp,
  type TextProps,
  type TextStyle,
  type ViewStyle,
} from 'react-native';
import Animated, { useAnimatedStyle, useReducedMotion, useSharedValue, withSpring } from 'react-native-reanimated';

import { useSettings } from '@/state/settings';
import { useTheme } from '@/theme/ThemeProvider';
import { fonts, motion, radius, space, type } from '@/theme/tokens';

// ------------------------------------------------------------------ text

type Variant = keyof typeof type;
type Tone = 'ink' | 'body' | 'muted' | 'mutedSoft' | 'primary' | 'error' | 'warning' | 'onAccent';

export type AppTextProps = TextProps & {
  variant?: Variant;
  tone?: Tone;
  weight?: 'regular' | 'medium' | 'bold';
  serif?: boolean;
  mono?: boolean;
  italic?: boolean;
};

export function AppText({
  variant = 'body',
  tone = 'ink',
  weight = 'regular',
  serif,
  mono,
  italic,
  style,
  ...rest
}: AppTextProps) {
  const { colors } = useTheme();
  const color =
    tone === 'onAccent'
      ? colors.canvas
      : tone === 'primary'
        ? colors.primary
        : tone === 'error'
          ? colors.error
          : tone === 'warning'
            ? colors.warning
            : colors[tone];
  const fontFamily = mono
    ? fonts.mono
    : serif
      ? italic
        ? fonts.serifItalic
        : fonts.serif
      : italic
        ? fonts.sansItalic
        : weight === 'bold'
          ? fonts.sansBold
          : weight === 'medium'
            ? fonts.sansMedium
            : fonts.sans;
  return <RNText {...rest} style={[type[variant], { color, fontFamily }, style]} />;
}

// --------------------------------------------------------------- haptics

export function useHaptic() {
  const enabled = useSettings((s) => s.settings.haptics);
  return (kind: 'light' | 'medium' | 'select' | 'success' | 'warning' = 'light') => {
    if (!enabled || Platform.OS === 'web') return;
    if (kind === 'select') void Haptics.selectionAsync();
    else if (kind === 'success') void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    else if (kind === 'warning') void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning);
    else void Haptics.impactAsync(kind === 'medium' ? Haptics.ImpactFeedbackStyle.Medium : Haptics.ImpactFeedbackStyle.Light);
  };
}

// ---------------------------------------------------- pressable with scale

const AnimatedPressable = Animated.createAnimatedComponent(Pressable);

export type PressableScaleProps = PressableProps & {
  style?: StyleProp<ViewStyle>;
  /** How far it sinks on press. Small elements can take more. */
  scaleTo?: number;
  haptic?: boolean;
  children?: ReactNode;
};

/** Every tappable surface: a spring-back press so the interface feels physical. */
export const PressableScale = forwardRef<View, PressableScaleProps>(function PressableScale(
  { style, scaleTo = 0.97, haptic = false, onPressIn, onPressOut, onPress, children, ...rest },
  ref,
) {
  const reduce = useReducedMotion();
  const scale = useSharedValue(1);
  const buzz = useHaptic();
  const animated = useAnimatedStyle(() => ({ transform: [{ scale: scale.value }] }));
  return (
    <AnimatedPressable
      ref={ref}
      {...rest}
      onPressIn={(e) => {
        if (!reduce) scale.set(withSpring(scaleTo, motion.spring));
        onPressIn?.(e);
      }}
      onPressOut={(e) => {
        scale.set(withSpring(1, motion.spring));
        onPressOut?.(e);
      }}
      onPress={(e) => {
        if (haptic) buzz('light');
        onPress?.(e);
      }}
      style={[style, animated]}
    >
      {children}
    </AnimatedPressable>
  );
});

// ------------------------------------------------------------ icon button

export function IconButton({
  icon: Icon,
  label,
  onPress,
  size = 22,
  tone = 'body',
  filled,
  disabled,
  style,
}: {
  icon: PhosphorIcon;
  label: string;
  onPress?: () => void;
  size?: number;
  tone?: 'body' | 'muted' | 'primary' | 'error' | 'ink';
  filled?: boolean;
  disabled?: boolean;
  style?: StyleProp<ViewStyle>;
}) {
  const { colors } = useTheme();
  const color = tone === 'primary' ? colors.primary : tone === 'error' ? colors.error : colors[tone];
  return (
    <PressableScale
      accessibilityRole="button"
      accessibilityLabel={label}
      hitSlop={6}
      disabled={disabled}
      onPress={onPress}
      scaleTo={0.9}
      haptic
      style={[
        {
          width: 40,
          height: 40,
          borderRadius: radius.pill,
          alignItems: 'center',
          justifyContent: 'center',
          backgroundColor: filled ? colors.surfaceSoft : 'transparent',
          opacity: disabled ? 0.4 : 1,
        },
        style,
      ]}
    >
      <Icon size={size} color={color} weight="regular" />
    </PressableScale>
  );
}

// ---------------------------------------------------------------- buttons

export function Button({
  label,
  onPress,
  variant = 'filled',
  icon: Icon,
  disabled,
  compact,
  style,
}: {
  label: string;
  onPress?: () => void;
  variant?: 'filled' | 'tonal' | 'ghost' | 'danger';
  icon?: PhosphorIcon;
  disabled?: boolean;
  compact?: boolean;
  style?: StyleProp<ViewStyle>;
}) {
  const { colors } = useTheme();
  const bg =
    variant === 'filled' ? colors.ink : variant === 'tonal' ? colors.surfaceRaised : variant === 'danger' ? colors.errorWash : 'transparent';
  const fg = variant === 'filled' ? colors.canvas : variant === 'danger' ? colors.error : colors.ink;
  return (
    <PressableScale
      accessibilityRole="button"
      accessibilityLabel={label}
      disabled={disabled}
      onPress={onPress}
      haptic
      style={[
        {
          minHeight: compact ? 36 : 44,
          paddingHorizontal: compact ? space.sm : space.md,
          borderRadius: radius.md,
          backgroundColor: bg,
          borderWidth: variant === 'ghost' ? 1 : 0,
          borderColor: colors.hairline,
          flexDirection: 'row',
          alignItems: 'center',
          justifyContent: 'center',
          gap: space.xs,
          opacity: disabled ? 0.45 : 1,
        },
        style,
      ]}
    >
      {Icon ? <Icon size={compact ? 16 : 18} color={fg} /> : null}
      <AppText variant={compact ? 'bodySmall' : 'body'} weight="medium" style={{ color: fg }} numberOfLines={1}>
        {label}
      </AppText>
    </PressableScale>
  );
}

// ------------------------------------------------------------------- misc

export function Divider({ inset = 0 }: { inset?: number }) {
  const { colors } = useTheme();
  return <View style={{ height: 1, backgroundColor: colors.hairlineSoft, marginLeft: inset }} />;
}

export function SectionLabel({ children, style }: { children: ReactNode; style?: StyleProp<TextStyle> }) {
  return (
    <AppText variant="caption" tone="muted" weight="medium" style={[{ paddingHorizontal: space.md, paddingTop: space.lg, paddingBottom: space.xs }, style]}>
      {children}
    </AppText>
  );
}

export function Chip({ label, tone = 'neutral' }: { label: string; tone?: 'neutral' | 'accent' | 'warning' | 'error' | 'success' }) {
  const { colors } = useTheme();
  const map = {
    neutral: [colors.surfaceRaised, colors.body],
    accent: [colors.primaryWash, colors.primary],
    warning: [colors.surfaceRaised, colors.warning],
    error: [colors.errorWash, colors.error],
    success: [colors.surfaceRaised, colors.success],
  } as const;
  const [bg, fg] = map[tone];
  return (
    <View style={{ backgroundColor: bg, borderRadius: radius.xs, paddingHorizontal: 7, paddingVertical: 2 }}>
      <AppText variant="micro" weight="medium" style={{ color: fg }}>
        {label}
      </AppText>
    </View>
  );
}
