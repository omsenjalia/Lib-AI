import { useEffect, useState } from 'react';
import { Platform, StyleSheet, Switch, View, type LayoutChangeEvent } from 'react-native';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import Animated, { runOnJS, useAnimatedStyle, useSharedValue, withSpring, withTiming } from 'react-native-reanimated';

import { useTheme } from '@/theme/ThemeProvider';
import { motion, radius, space } from '@/theme/tokens';
import { AppText, PressableScale, useHaptic } from './primitives';

/** Segmented control with a sliding thumb. */
export function Segmented<T extends string>({
  value,
  options,
  onChange,
}: {
  value: T;
  options: { value: T; label: string }[];
  onChange: (v: T) => void;
}) {
  const { colors } = useTheme();
  const [width, setWidth] = useState(0);
  const index = Math.max(0, options.findIndex((o) => o.value === value));
  const x = useSharedValue(0);
  const seg = width / options.length;
  useEffect(() => {
    x.set(withSpring(index * seg, motion.spring));
  }, [index, seg, x]);
  const thumb = useAnimatedStyle(() => ({ transform: [{ translateX: x.value }] }));
  const buzz = useHaptic();
  return (
    <View
      accessibilityRole="radiogroup"
      onLayout={(e: LayoutChangeEvent) => setWidth(e.nativeEvent.layout.width - 4)}
      style={[styles.segment, { backgroundColor: colors.surfaceSoft, borderColor: colors.hairline }]}
    >
      {width > 0 ? (
        <Animated.View style={[styles.thumb, { width: seg, backgroundColor: colors.surface, borderColor: colors.hairline }, thumb]} />
      ) : null}
      {options.map((o) => (
        <PressableScale
          key={o.value}
          accessibilityRole="radio"
          accessibilityState={{ selected: o.value === value }}
          onPress={() => {
            buzz('select');
            onChange(o.value);
          }}
          style={styles.segmentItem}
        >
          <AppText variant="bodySmall" weight="medium" tone={o.value === value ? 'ink' : 'muted'}>
            {o.label}
          </AppText>
        </PressableScale>
      ))}
    </View>
  );
}

/**
 * Continuous slider. Gesture-driven thumb; commits on release so a drag does
 * not write the database sixty times a second.
 */
export function Slider({
  value,
  min,
  max,
  step,
  onChange,
  onCommit,
  label,
}: {
  value: number;
  min: number;
  max: number;
  step: number;
  onChange?: (v: number) => void;
  onCommit: (v: number) => void;
  label: string;
}) {
  const { colors } = useTheme();
  const [width, setWidth] = useState(0);
  const frac = useSharedValue((value - min) / (max - min));
  const startFrac = useSharedValue(0);
  useEffect(() => {
    frac.set(withTiming((value - min) / (max - min), { duration: motion.fast }));
  }, [value, min, max, frac]);

  const snap = (f: number) => {
    const raw = min + Math.min(1, Math.max(0, f)) * (max - min);
    const stepped = Math.round(raw / step) * step;
    return Number(Math.min(max, Math.max(min, stepped)).toFixed(4));
  };
  const emit = (f: number) => onChange?.(snap(f));
  const commit = (f: number) => onCommit(snap(f));

  const pan = Gesture.Pan()
    .hitSlop({ vertical: 16 })
    .onBegin((e) => {
      if (width <= 0) return;
      frac.set(Math.min(1, Math.max(0, e.x / width)));
      startFrac.set(frac.value);
      runOnJS(emit)(frac.value);
    })
    .onUpdate((e) => {
      if (width <= 0) return;
      frac.set(Math.min(1, Math.max(0, startFrac.value + e.translationX / width)));
      runOnJS(emit)(frac.value);
    })
    .onFinalize(() => runOnJS(commit)(frac.value));

  const fill = useAnimatedStyle(() => ({ width: `${frac.value * 100}%` }));
  const thumb = useAnimatedStyle(() => ({ transform: [{ translateX: frac.value * width - 11 }] }));

  return (
    <GestureDetector gesture={pan}>
      <View
        accessible
        accessibilityRole="adjustable"
        accessibilityLabel={label}
        accessibilityValue={{ min, max, now: value }}
        accessibilityActions={[{ name: 'increment' }, { name: 'decrement' }]}
        onAccessibilityAction={(e) => {
          const next = e.nativeEvent.actionName === 'increment' ? value + step : value - step;
          onCommit(Math.min(max, Math.max(min, next)));
        }}
        onLayout={(e) => setWidth(e.nativeEvent.layout.width)}
        style={styles.sliderHit}
      >
        <View style={[styles.track, { backgroundColor: colors.hairline }]}>
          <Animated.View style={[styles.fill, { backgroundColor: colors.primary }, fill]} />
        </View>
        <Animated.View style={[styles.sliderThumb, { backgroundColor: colors.surface, borderColor: colors.primary }, thumb]} />
      </View>
    </GestureDetector>
  );
}

export function Toggle({ value, onChange, label }: { value: boolean; onChange: (v: boolean) => void; label: string }) {
  const { colors } = useTheme();
  const buzz = useHaptic();
  return (
    <Switch
      accessibilityLabel={label}
      value={value}
      onValueChange={(v) => {
        buzz('select');
        onChange(v);
      }}
      trackColor={{ false: colors.hairline, true: colors.primary }}
      thumbColor="#FAF9F5"
      ios_backgroundColor={colors.hairline}
      {...(Platform.OS === 'web' ? { activeThumbColor: '#FAF9F5', activeTrackColor: colors.primary } : null)}
    />
  );
}

const styles = StyleSheet.create({
  segment: { flexDirection: 'row', borderRadius: radius.md, borderWidth: 1, padding: 2 },
  thumb: { position: 'absolute', top: 2, bottom: 2, left: 2, borderRadius: radius.sm, borderWidth: StyleSheet.hairlineWidth },
  segmentItem: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingVertical: space.xs },
  sliderHit: { height: 36, justifyContent: 'center' },
  track: { height: 4, borderRadius: 2, overflow: 'hidden' },
  fill: { height: 4 },
  sliderThumb: { position: 'absolute', left: 0, width: 22, height: 22, borderRadius: 11, borderWidth: 2 },
});
