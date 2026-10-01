import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { BackHandler, Pressable, StyleSheet, useWindowDimensions, View } from 'react-native';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import { KeyboardAvoidingView } from 'react-native-keyboard-controller';
import Animated, {
  interpolate,
  runOnJS,
  useAnimatedStyle,
  useReducedMotion,
  useSharedValue,
  withTiming,
} from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { EngineBanner, UpdateBanner } from '@/components/chat/Banners';
import { Composer } from '@/components/chat/Composer';
import { HomeView } from '@/components/chat/HomeView';
import { MessageList } from '@/components/chat/MessageList';
import { ConversationActionsSheet, ModelSwitcherSheet, PersonaPickerSheet } from '@/components/chat/Sheets';
import { SidebarContent } from '@/components/chat/Sidebar';
import { TopBar } from '@/components/chat/TopBar';
import { ToastHost } from '@/components/ui/Toast';
import type { Conversation } from '@/core/db/types';
import { useChat } from '@/state/chat';
import { useConversations } from '@/state/collections';
import { useTheme } from '@/theme/ThemeProvider';
import { layout, motion } from '@/theme/tokens';

export default function ChatScreen() {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const { width } = useWindowDimensions();
  const reduce = useReducedMotion();
  const drawerWidth = Math.min(width * layout.sidebarWidthFraction, layout.sidebarMaxWidth);

  const conversationId = useChat((s) => s.conversationId);
  const hasMessages = useChat((s) => s.messages.length > 0);
  const conversation = useConversations((s) => s.list.find((c) => c.id === conversationId) ?? null);

  const [drawerOpen, setDrawerOpen] = useState(false);
  const [modelSheet, setModelSheet] = useState(false);
  const [personaSheet, setPersonaSheet] = useState(false);
  const [actionsFor, setActionsFor] = useState<Conversation | null>(null);

  // 0 = closed, 1 = open.
  const progress = useSharedValue(0);
  const dragStart = useSharedValue(0);

  const animateTo = useCallback(
    (open: boolean) => {
      setDrawerOpen(open);
      progress.set(withTiming(open ? 1 : 0, { duration: reduce ? 1 : motion.base + 20, easing: motion.easeOut }));
    },
    [progress, reduce],
  );

  useFocusEffect(
    useCallback(() => {
      const sub = BackHandler.addEventListener('hardwareBackPress', () => {
        if (!drawerOpen) return false;
        animateTo(false);
        return true;
      });
      return () => sub.remove();
    }, [drawerOpen, animateTo]),
  );

  const settle = (velocity: number) => {
    'worklet';
    const open = velocity > 400 || (velocity > -400 && progress.value > 0.5);
    runOnJS(animateTo)(open);
  };

  const edgePan = Gesture.Pan()
    .activeOffsetX(10)
    .failOffsetY([-14, 14])
    .onBegin(() => {
      dragStart.set(progress.value);
    })
    .onUpdate((e) => {
      progress.set(Math.min(1, Math.max(0, dragStart.value + e.translationX / drawerWidth)));
    })
    .onEnd((e) => settle(e.velocityX));

  const closePan = Gesture.Pan()
    .activeOffsetX(-10)
    .failOffsetY([-14, 14])
    .onBegin(() => {
      dragStart.set(progress.value);
    })
    .onUpdate((e) => {
      progress.set(Math.min(1, Math.max(0, dragStart.value + e.translationX / drawerWidth)));
    })
    .onEnd((e) => settle(e.velocityX));

  const sidebarStyle = useAnimatedStyle(() => ({
    transform: [{ translateX: interpolate(progress.value, [0, 1], [-drawerWidth, 0]) }],
  }));
  const mainStyle = useAnimatedStyle(() => ({
    transform: [{ translateX: progress.value * drawerWidth * 0.22 }],
  }));
  const scrimStyle = useAnimatedStyle(() => ({ opacity: progress.value }));

  return (
    <View style={[styles.root, { backgroundColor: colors.canvas }]}>
      <Animated.View style={[styles.main, { paddingTop: insets.top }, mainStyle]}>
        <TopBar onMenu={() => animateTo(true)} onModel={() => setModelSheet(true)} onMore={() => setActionsFor(conversation)} />
        <UpdateBanner />
        <EngineBanner />
        <KeyboardAvoidingView behavior="padding" style={{ flex: 1 }} keyboardVerticalOffset={0}>
          <View style={{ flex: 1 }}>{conversationId !== null && hasMessages ? <MessageList /> : <HomeView />}</View>
          <View style={{ paddingBottom: Math.max(insets.bottom, 8), width: '100%', maxWidth: layout.maxReadingWidth, alignSelf: 'center' }}>
            <Composer />
          </View>
        </KeyboardAvoidingView>
      </Animated.View>

      {/* Left-edge strip: swipe right anywhere along it to open the drawer. */}
      <GestureDetector gesture={edgePan}>
        <View style={[styles.edge, { top: insets.top + layout.topBar }]} />
      </GestureDetector>

      <Animated.View style={[StyleSheet.absoluteFill, { backgroundColor: colors.scrim, pointerEvents: drawerOpen ? 'auto' : 'none' }, scrimStyle]}>
        <Pressable style={{ flex: 1 }} onPress={() => animateTo(false)} accessibilityRole="button" accessibilityLabel="Close chats" />
      </Animated.View>

      <GestureDetector gesture={closePan}>
        <Animated.View
          style={[styles.sidebar, { width: drawerWidth, borderRightColor: colors.hairline }, sidebarStyle]}
          accessibilityViewIsModal={drawerOpen}
          importantForAccessibility={drawerOpen ? 'auto' : 'no-hide-descendants'}
        >
          <SidebarContent onClose={() => animateTo(false)} onActions={(c) => setActionsFor(c)} />
        </Animated.View>
      </GestureDetector>

      <ModelSwitcherSheet visible={modelSheet} onClose={() => setModelSheet(false)} />
      <PersonaPickerSheet visible={personaSheet} onClose={() => setPersonaSheet(false)} conversation={conversation} />
      <ConversationActionsSheet conversation={actionsFor} onClose={() => setActionsFor(null)} onPersona={() => setPersonaSheet(true)} />
      <ToastHost bottom={insets.bottom + 96} />
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, overflow: 'hidden' },
  main: { flex: 1 },
  edge: { position: 'absolute', left: 0, bottom: 120, width: 22 },
  sidebar: { position: 'absolute', top: 0, bottom: 0, left: 0, borderRightWidth: StyleSheet.hairlineWidth },
});
