import { BookOpenText } from 'phosphor-react-native';
import { useEffect } from 'react';
import Animated, {
  cancelAnimation,
  Easing,
  useAnimatedStyle,
  useReducedMotion,
  useSharedValue,
  withRepeat,
  withSequence,
  withTiming,
} from 'react-native-reanimated';

import { useTheme } from '@/theme/ThemeProvider';

/**
 * Library AI's mark: an open book in the clay accent. It breathes while the
 * model is writing, which doubles as the "still working" signal in the gutter.
 * Deliberately not a copy of any other product's logo.
 */
export function BrandMark({ size = 24, spinning = false }: { size?: number; spinning?: boolean }) {
  const { colors } = useTheme();
  const reduce = useReducedMotion();
  const s = useSharedValue(1);
  useEffect(() => {
    if (!spinning || reduce) {
      s.set(withTiming(1, { duration: 150 }));
      return;
    }
    s.set(withRepeat(
      withSequence(
        withTiming(1.12, { duration: 520, easing: Easing.inOut(Easing.sin) }),
        withTiming(0.94, { duration: 520, easing: Easing.inOut(Easing.sin) }),
      ),
      -1,
      true,
    ));
    return () => cancelAnimation(s);
  }, [spinning, reduce, s]);
  const style = useAnimatedStyle(() => ({ transform: [{ scale: s.value }] }));
  return (
    <Animated.View style={style} accessibilityElementsHidden importantForAccessibility="no-hide-descendants">
      <BookOpenText size={size} color={colors.primary} weight="duotone" />
    </Animated.View>
  );
}
