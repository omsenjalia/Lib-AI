import { router } from 'expo-router';
import { ArrowRight } from 'phosphor-react-native';
import { useMemo } from 'react';
import { StyleSheet, View } from 'react-native';
import Animated, { FadeIn, FadeInDown } from 'react-native-reanimated';

import { AppText, PressableScale } from '@/components/ui/primitives';
import { suggestionChips } from '@/core/constants';
import { greetingFor } from '@/core/utils/formatters';
import { useChat } from '@/state/chat';
import { useActiveModelId } from '@/state/library';
import { useTheme } from '@/theme/ThemeProvider';
import { radius, space } from '@/theme/tokens';
import { BrandMark } from './BrandMark';

/**
 * The empty thread: mark, a serif greeting that follows the time of day, and
 * four starters in a 2x2 grid that rise in on a short stagger. A starter fills
 * the composer instead of sending, so the student finishes the sentence.
 */
export function HomeView() {
  const { colors } = useTheme();
  const setDraft = useChat((s) => s.setDraft);
  const activeId = useActiveModelId();
  const greeting = useMemo(() => greetingFor(), []);

  return (
    <View style={styles.wrap}>
      <Animated.View entering={FadeIn.duration(500)} style={{ alignItems: 'center', gap: space.md }}>
        <BrandMark size={40} />
        <AppText serif variant="display" style={{ textAlign: 'center' }} accessibilityRole="header">
          {greeting}
        </AppText>
      </Animated.View>

      {activeId ? (
        <View style={styles.grid}>
          {suggestionChips.map((chip, i) => (
            <Animated.View key={chip.title} entering={FadeInDown.delay(120 + i * 60).springify().damping(20)} style={styles.cell}>
              <PressableScale
                accessibilityRole="button"
                accessibilityHint="Puts a starter in the message box"
                onPress={() => setDraft(chip.prompt)}
                haptic
                style={[styles.chip, { backgroundColor: colors.surface, borderColor: colors.hairline }]}
              >
                <AppText variant="bodySmall" weight="medium" numberOfLines={2}>
                  {chip.title}
                </AppText>
              </PressableScale>
            </Animated.View>
          ))}
        </View>
      ) : (
        <Animated.View entering={FadeInDown.delay(150).springify().damping(20)} style={{ width: '100%', maxWidth: 420 }}>
          <PressableScale
            accessibilityRole="button"
            onPress={() => router.push('/library')}
            haptic
            style={[styles.setup, { backgroundColor: colors.surface, borderColor: colors.hairline }]}
          >
            <View style={{ flex: 1, gap: 4 }}>
              <AppText weight="bold">Download a model to begin</AppText>
              <AppText variant="bodySmall" tone="muted">
                Everything runs on this phone. After one download you can study with the radio off.
              </AppText>
            </View>
            <View style={[styles.arrow, { backgroundColor: colors.ink }]}>
              <ArrowRight size={16} color={colors.canvas} weight="bold" />
            </View>
          </PressableScale>
        </Animated.View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingHorizontal: space.md, gap: space.xl, paddingBottom: space.xl },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: space.xs, width: '100%', maxWidth: 460 },
  cell: { width: '48.8%' },
  chip: { minHeight: 64, borderRadius: radius.lg, borderWidth: 1, paddingHorizontal: space.md, paddingVertical: space.sm, justifyContent: 'center' },
  setup: { flexDirection: 'row', alignItems: 'center', gap: space.md, padding: space.md, borderRadius: radius.lg, borderWidth: 1 },
  arrow: { width: 34, height: 34, borderRadius: 17, alignItems: 'center', justifyContent: 'center' },
});
