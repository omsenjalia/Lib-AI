import { useEffect } from 'react';
import { StyleSheet, View } from 'react-native';
import Animated, { FadeInDown, FadeOutDown } from 'react-native-reanimated';
import { create } from 'zustand';

import { useTheme } from '@/theme/ThemeProvider';
import { radius, space } from '@/theme/tokens';
import { AppText, PressableScale } from './primitives';

/**
 * One transient message at the bottom of the screen, optionally with an
 * action (Undo). Replaces the previous one rather than stacking.
 */
type ToastState = {
  toast: { id: number; text: string; action?: { label: string; run: () => void }; ms: number } | null;
  show(text: string, opts?: { action?: { label: string; run: () => void }; ms?: number }): void;
  hide(): void;
};

export const useToast = create<ToastState>((set) => ({
  toast: null,
  show: (text, opts) => set({ toast: { id: Date.now(), text, action: opts?.action, ms: opts?.ms ?? 3200 } }),
  hide: () => set({ toast: null }),
}));

export const toast = (text: string, opts?: { action?: { label: string; run: () => void }; ms?: number }) =>
  useToast.getState().show(text, opts);

export function ToastHost({ bottom }: { bottom: number }) {
  const { colors } = useTheme();
  const t = useToast((s) => s.toast);
  const hide = useToast((s) => s.hide);
  useEffect(() => {
    if (!t) return;
    const timer = setTimeout(hide, t.ms);
    return () => clearTimeout(timer);
  }, [t, hide]);
  if (!t) return null;
  return (
    <View style={[StyleSheet.absoluteFill, { justifyContent: 'flex-end', paddingBottom: bottom, pointerEvents: 'box-none' }]}>
      <Animated.View
        key={t.id}
        entering={FadeInDown.springify().damping(20)}
        exiting={FadeOutDown.duration(160)}
        accessibilityLiveRegion="polite"
        style={[styles.toast, { backgroundColor: colors.ink }]}
      >
        <AppText variant="bodySmall" style={{ color: colors.canvas, flex: 1 }}>
          {t.text}
        </AppText>
        {t.action ? (
          <PressableScale
            accessibilityRole="button"
            onPress={() => {
              t.action?.run();
              hide();
            }}
            style={{ paddingHorizontal: space.xs, paddingVertical: 4 }}
          >
            <AppText variant="bodySmall" weight="bold" style={{ color: colors.primary }}>
              {t.action.label}
            </AppText>
          </PressableScale>
        ) : null}
      </Animated.View>
    </View>
  );
}

const styles = StyleSheet.create({
  toast: {
    marginHorizontal: space.md,
    borderRadius: radius.md,
    paddingHorizontal: space.md,
    paddingVertical: space.sm,
    flexDirection: 'row',
    alignItems: 'center',
    gap: space.sm,
    alignSelf: 'center',
    maxWidth: 560,
    width: '92%',
  },
});
