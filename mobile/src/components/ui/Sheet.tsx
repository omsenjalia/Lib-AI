import { useEffect, useState, type ReactNode } from 'react';
import { Modal, Pressable, StyleSheet, useWindowDimensions, View } from 'react-native';
import { Gesture, GestureDetector, GestureHandlerRootView } from 'react-native-gesture-handler';
import Animated, {
  runOnJS,
  useAnimatedStyle,
  useReducedMotion,
  useSharedValue,
  withSpring,
  withTiming,
} from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { useTheme } from '@/theme/ThemeProvider';
import { motion, radius, space } from '@/theme/tokens';
import { AppText } from './primitives';

/**
 * Bottom sheet: springs up, scrim fades in, drag the handle (or the sheet)
 * down to dismiss, tap the scrim to dismiss, back button dismisses.
 */
export function Sheet({
  visible,
  onClose,
  title,
  children,
  maxHeightFraction = 0.88,
}: {
  visible: boolean;
  onClose: () => void;
  title?: string;
  children: ReactNode;
  maxHeightFraction?: number;
}) {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const { height } = useWindowDimensions();
  const reduce = useReducedMotion();
  const [mounted, setMounted] = useState(visible);
  const offset = useSharedValue(height);
  const scrim = useSharedValue(0);

  // Mount in the render that turns visible on; unmount after the exit animation.
  if (visible && !mounted) setMounted(true);

  useEffect(() => {
    if (visible) {
      offset.set(height);
      // Travel is timed, not sprung: a spring across a full screen height has a long, mushy tail.
      offset.set(withTiming(0, { duration: reduce ? 1 : motion.base + 40, easing: motion.easeOut }));
      scrim.set(withTiming(1, { duration: motion.base }));
    } else if (mounted) {
      scrim.set(withTiming(0, { duration: motion.fast }));
      offset.set(withTiming(height, { duration: motion.base, easing: motion.easeOut }, (done) => {
        if (done) runOnJS(setMounted)(false);
      }));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visible]);

  const pan = Gesture.Pan()
    .activeOffsetY(8)
    .failOffsetX([-20, 20])
    .onUpdate((e) => {
      offset.set(Math.max(0, e.translationY));
    })
    .onEnd((e) => {
      if (e.translationY > 110 || e.velocityY > 900) runOnJS(onClose)();
      else offset.set(withSpring(0, motion.spring));
    });

  const sheetStyle = useAnimatedStyle(() => ({ transform: [{ translateY: offset.value }] }));
  const scrimStyle = useAnimatedStyle(() => ({ opacity: scrim.value }));

  if (!mounted) return null;
  return (
    <Modal transparent visible statusBarTranslucent navigationBarTranslucent onRequestClose={onClose} animationType="none">
      <GestureHandlerRootView style={{ flex: 1 }}>
        <Animated.View style={[StyleSheet.absoluteFill, { backgroundColor: colors.scrim }, scrimStyle]}>
          <Pressable style={{ flex: 1 }} onPress={onClose} accessibilityRole="button" accessibilityLabel="Close" />
        </Animated.View>
        <GestureDetector gesture={pan}>
          <Animated.View
            accessibilityViewIsModal
            style={[
              styles.sheet,
              {
                backgroundColor: colors.surface,
                maxHeight: height * maxHeightFraction,
                paddingBottom: insets.bottom + space.sm,
                borderColor: colors.hairline,
              },
              sheetStyle,
            ]}
          >
            <View style={styles.handleArea}>
              <View style={[styles.handle, { backgroundColor: colors.mutedSoft }]} />
            </View>
            {title ? (
              <AppText variant="title" weight="medium" style={{ paddingHorizontal: space.md, paddingBottom: space.sm }}>
                {title}
              </AppText>
            ) : null}
            {children}
          </Animated.View>
        </GestureDetector>
      </GestureHandlerRootView>
    </Modal>
  );
}

const styles = StyleSheet.create({
  sheet: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    borderTopLeftRadius: radius.xl,
    borderTopRightRadius: radius.xl,
    borderWidth: StyleSheet.hairlineWidth,
    borderBottomWidth: 0,
    alignSelf: 'center',
    width: '100%',
    maxWidth: 640,
  },
  handleArea: { alignItems: 'center', paddingTop: space.xs, paddingBottom: space.sm },
  handle: { width: 36, height: 4, borderRadius: 2, opacity: 0.6 },
});
