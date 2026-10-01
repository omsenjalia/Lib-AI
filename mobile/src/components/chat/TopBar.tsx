import { CaretDown, DotsThreeVertical, List, NotePencil } from 'phosphor-react-native';
import { useEffect, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import Animated, { useAnimatedStyle, useSharedValue, withTiming } from 'react-native-reanimated';

import { AppText, IconButton, PressableScale } from '@/components/ui/primitives';
import { modelById } from '@/core/catalogue';
import { isCritical, isWarning, usageFraction } from '@/core/utils/tokenEstimator';
import { useChat, useContextUsage } from '@/state/chat';
import { useEngineStatus } from '@/state/engineStatus';
import { useActiveModelId, useLibrary } from '@/state/library';
import { useTheme } from '@/theme/ThemeProvider';
import { layout, motion, space } from '@/theme/tokens';

/**
 * Menu on the left, the model name in the middle (one tap target that opens
 * the switcher), new chat on the right. The context meter is a 2 dp rule
 * along the bottom edge; long-press the title for the numbers.
 */
export function TopBar({
  onMenu,
  onModel,
  onMore,
}: {
  onMenu: () => void;
  onModel: () => void;
  onMore: () => void;
}) {
  const { colors } = useTheme();
  const activeId = useActiveModelId();
  const model = modelById(activeId);
  const installed = useLibrary((s) => (activeId ? Boolean(s.installations[activeId]) : false));
  const failed = useEngineStatus((s) => s.stage === 'failed' && s.modelId === activeId);
  const conversationId = useChat((s) => s.conversationId);
  const newChat = useChat((s) => s.newChat);
  const [showNumbers, setShowNumbers] = useState(false);
  const usage = useContextUsage();

  const label = !model ? 'No model' : failed ? 'Model failed to load' : model.displayName;
  return (
    <View style={[styles.bar, { borderBottomColor: colors.hairlineSoft }]}>
      <IconButton icon={List} label="Open chats" onPress={onMenu} />
      <PressableScale
        accessibilityRole="button"
        accessibilityLabel={`Model: ${label}. Change model`}
        onPress={onModel}
        onLongPress={() => setShowNumbers((s) => !s)}
        scaleTo={0.96}
        style={styles.title}
      >
        <View style={{ alignItems: 'center' }}>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4 }}>
            <AppText variant="bodySmall" weight="bold" numberOfLines={1} tone={failed || (!installed && model) ? 'error' : 'ink'} style={{ maxWidth: 210 }}>
              {label}
            </AppText>
            <CaretDown size={13} color={colors.muted} weight="bold" />
          </View>
          {showNumbers && conversationId !== null ? (
            <AppText variant="micro" tone="muted">
              {usage.exact ? '' : '~'}
              {usage.used.toLocaleString()} of {usage.total.toLocaleString()} tokens
            </AppText>
          ) : null}
        </View>
      </PressableScale>
      {conversationId !== null ? (
        <View style={{ flexDirection: 'row' }}>
          <IconButton icon={DotsThreeVertical} label="Chat options" onPress={onMore} />
          <IconButton icon={NotePencil} label="New chat" onPress={newChat} tone="ink" />
        </View>
      ) : (
        <IconButton icon={NotePencil} label="New chat" onPress={newChat} tone="ink" disabled />
      )}
      {conversationId !== null ? <ContextMeter used={usage.used} total={usage.total} /> : null}
    </View>
  );
}

function ContextMeter({ used, total }: { used: number; total: number }) {
  const { colors } = useTheme();
  const fraction = usageFraction(used, total);
  const w = useSharedValue(0);
  useEffect(() => {
    w.set(withTiming(fraction, { duration: motion.slow, easing: motion.easeOut }));
  }, [fraction, w]);
  const style = useAnimatedStyle(() => ({ transform: [{ scaleX: Math.max(0.001, w.value) }] }));
  const color = isCritical(used, total) ? colors.error : isWarning(used, total) ? colors.warning : colors.primary;
  return (
    <View
      style={styles.meterTrack}
      accessible
      accessibilityRole="progressbar"
      accessibilityLabel="Context window used"
      accessibilityValue={{ min: 0, max: total, now: used }}
    >
      <Animated.View style={[styles.meterFill, { backgroundColor: color }, style]} />
    </View>
  );
}

const styles = StyleSheet.create({
  bar: {
    height: layout.topBar,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: space.xs,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  title: { flex: 1, alignItems: 'center', justifyContent: 'center', height: 44, marginHorizontal: space.xs },
  meterTrack: { position: 'absolute', left: 0, right: 0, bottom: -1, height: 2, overflow: 'hidden' },
  meterFill: { height: 2, width: '100%', transformOrigin: 'left' },
});
