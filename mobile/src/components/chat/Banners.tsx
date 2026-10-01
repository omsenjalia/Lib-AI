import { router } from 'expo-router';
import { ArrowsClockwise, X } from 'phosphor-react-native';
import { useEffect } from 'react';
import { StyleSheet, View } from 'react-native';
import Animated, { FadeInUp, FadeOutUp, useAnimatedStyle, useSharedValue, withTiming } from 'react-native-reanimated';

import { AppText, PressableScale } from '@/components/ui/primitives';
import { modelById } from '@/core/catalogue';
import { useEngineStatus } from '@/state/engineStatus';
import { useLibrary } from '@/state/library';
import { useTheme } from '@/theme/ThemeProvider';
import { motion, radius, space } from '@/theme/tokens';
import { Shimmer } from './Shimmer';

/**
 * Loading a 5 GB model takes a while on a phone. The stage is shown as words
 * plus a determinate bar while weights page in, rather than a bare spinner.
 */
export function EngineBanner() {
  const { colors } = useTheme();
  const status = useEngineStatus();
  const loading = status.stage === 'verifying' || status.stage === 'readingMetadata' || status.stage === 'loadingWeights';
  const p = useSharedValue(0);
  useEffect(() => {
    p.set(withTiming(status.stage === 'loadingWeights' ? status.progress : status.stage === 'readingMetadata' ? 0.04 : 0.01, {
      duration: motion.base,
    }));
  }, [status.stage, status.progress, p]);
  const bar = useAnimatedStyle(() => ({ transform: [{ scaleX: Math.max(0.01, p.value) }] }));
  if (!loading) return null;
  const name = modelById(status.modelId)?.displayName ?? 'model';
  return (
    <Animated.View
      entering={FadeInUp.duration(motion.base)}
      exiting={FadeOutUp.duration(motion.fast)}
      style={[styles.banner, { backgroundColor: colors.surface, borderColor: colors.hairline }]}
      accessibilityLiveRegion="polite"
    >
      <Shimmer>
        <AppText variant="bodySmall" weight="medium">
          {status.message ?? 'Loading'}
        </AppText>
      </Shimmer>
      <AppText variant="caption" tone="muted">
        {name}
        {status.stage === 'loadingWeights' ? `, ${Math.round(status.progress * 100)}%` : ''}
      </AppText>
      <View style={[styles.track, { backgroundColor: colors.hairline }]}>
        <Animated.View style={[styles.fill, { backgroundColor: colors.primary }, bar]} />
      </View>
    </Animated.View>
  );
}

/** "A newer file is available upstream." Display only; tapping goes to the library. */
export function UpdateBanner() {
  const { colors } = useTheme();
  const updates = useLibrary((s) => s.updates);
  const dismiss = useLibrary((s) => s.dismissUpdate);
  const pending = Object.values(updates).find((u) => u.updateAvailable);
  const model = modelById(pending?.modelId);
  if (!pending || !model) return null;
  return (
    <Animated.View entering={FadeInUp.duration(motion.base)} exiting={FadeOutUp.duration(motion.fast)}>
      <PressableScale
        accessibilityRole="button"
        onPress={() => router.push('/library')}
        style={[styles.banner, styles.row, { backgroundColor: colors.primaryWash, borderColor: 'transparent' }]}
      >
        <ArrowsClockwise size={18} color={colors.primary} />
        <AppText variant="bodySmall" style={{ flex: 1 }}>
          An update for <AppText variant="bodySmall" weight="bold">{model.displayName}</AppText> is available.
        </AppText>
        <PressableScale accessibilityRole="button" accessibilityLabel="Dismiss" onPress={() => void dismiss(pending.modelId)} hitSlop={10}>
          <X size={16} color={colors.muted} />
        </PressableScale>
      </PressableScale>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  banner: {
    marginHorizontal: space.sm,
    marginTop: space.xs,
    padding: space.sm,
    borderRadius: radius.lg,
    borderWidth: 1,
    gap: 4,
  },
  row: { flexDirection: 'row', alignItems: 'center', gap: space.sm },
  track: { height: 3, borderRadius: 2, overflow: 'hidden', marginTop: 4 },
  fill: { height: 3, width: '100%', transformOrigin: 'left' },
});
