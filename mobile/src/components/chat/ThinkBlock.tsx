import { CaretRight, Lightbulb } from 'phosphor-react-native';
import { memo, useEffect, useState } from 'react';
import { View } from 'react-native';
import Animated, { FadeIn, useAnimatedStyle, useSharedValue, withTiming } from 'react-native-reanimated';

import { AppText, PressableScale } from '@/components/ui/primitives';
import { useTheme } from '@/theme/ThemeProvider';
import { motion, radius, space } from '@/theme/tokens';
import { Shimmer } from './Shimmer';

/**
 * A reasoning model's scratch work, folded away. While the model is still
 * thinking the label shimmers; tap to read along.
 */
export const ThinkBlock = memo(function ThinkBlock({ text, complete }: { text: string; complete: boolean }) {
  const { colors } = useTheme();
  const [open, setOpen] = useState(false);
  const rotation = useSharedValue(0);
  useEffect(() => {
    rotation.set(withTiming(open ? 90 : 0, { duration: motion.fast }));
  }, [open, rotation]);
  const caret = useAnimatedStyle(() => ({ transform: [{ rotate: `${rotation.value}deg` }] }));
  const words = text.split(/\s+/).filter(Boolean).length;
  return (
    <View>
      <PressableScale
        accessibilityRole="button"
        accessibilityState={{ expanded: open }}
        accessibilityLabel={complete ? 'Show reasoning' : 'Thinking'}
        onPress={() => setOpen((o) => !o)}
        style={{ flexDirection: 'row', alignItems: 'center', gap: 6, alignSelf: 'flex-start', paddingVertical: 4 }}
      >
        <Lightbulb size={16} color={colors.muted} />
        {complete ? (
          <AppText variant="bodySmall" tone="muted" weight="medium">
            Reasoned for {words} words
          </AppText>
        ) : (
          <Shimmer>
            <AppText variant="bodySmall" tone="muted" weight="medium">
              Thinking
            </AppText>
          </Shimmer>
        )}
        <Animated.View style={caret}>
          <CaretRight size={13} color={colors.muted} />
        </Animated.View>
      </PressableScale>
      {open ? (
        <Animated.View
          entering={FadeIn.duration(motion.base)}
          style={{ borderLeftWidth: 2, borderLeftColor: colors.hairline, paddingLeft: space.sm, marginTop: 4, borderRadius: radius.xs }}
        >
          <AppText variant="bodySmall" tone="muted" selectable>
            {text || '...'}
          </AppText>
        </Animated.View>
      ) : null}
    </View>
  );
});
