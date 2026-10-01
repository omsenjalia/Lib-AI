import { ArrowDown } from 'phosphor-react-native';
import { useCallback, useEffect, useRef, useState } from 'react';
import { FlatList, StyleSheet, View, type NativeScrollEvent, type NativeSyntheticEvent } from 'react-native';
import Animated, { ZoomIn, ZoomOut } from 'react-native-reanimated';

import { PressableScale } from '@/components/ui/primitives';
import type { Message } from '@/core/db/types';
import { useChat } from '@/state/chat';
import { useTheme } from '@/theme/ThemeProvider';
import { layout, space } from '@/theme/tokens';
import { MessageRow } from './MessageRow';

/**
 * The transcript. It follows the stream only while the reader is at the
 * bottom; scroll up to re-read and it stays put, with a button to jump back.
 */
export function MessageList() {
  const { colors } = useTheme();
  const messages = useChat((s) => s.messages);
  const streamingId = useChat((s) => s.streamingId);
  const streamingText = useChat((s) => s.streamingText);
  const list = useRef<FlatList<Message>>(null);
  /** True once the reader drags up; cleared when they return to the bottom or a new turn starts. */
  const detached = useRef(false);
  const [showJump, setShowJump] = useState(false);

  const lastAssistant = [...messages].reverse().find((m) => m.role === 'assistant')?.id;
  const lastUser = [...messages].reverse().find((m) => m.role === 'user')?.id;

  const onScroll = useCallback((e: NativeSyntheticEvent<NativeScrollEvent>) => {
    const { contentOffset, contentSize, layoutMeasurement } = e.nativeEvent;
    const distance = contentSize.height - (contentOffset.y + layoutMeasurement.height);
    if (distance < 80) detached.current = false;
    setShowJump(detached.current && distance > 320);
  }, []);

  // Scroll to the height the list just reported: scrollToEnd() uses the list's
  // own tracked length, which lags while a reply grows quickly.
  const follow = useCallback((_w: number, h: number) => {
    if (!detached.current) list.current?.scrollToOffset({ offset: h, animated: false });
  }, []);

  // A new turn always brings the reader to it.
  useEffect(() => {
    detached.current = false;
    requestAnimationFrame(() => list.current?.scrollToEnd({ animated: true }));
  }, [messages.length]);

  return (
    <View style={{ flex: 1 }}>
      <FlatList
        ref={list}
        data={messages}
        keyExtractor={(m) => String(m.id)}
        renderItem={({ item }) => (
          <MessageRow
            message={item}
            isStreaming={item.id === streamingId}
            streamingText={item.id === streamingId ? streamingText : null}
            isLastAssistant={item.id === lastAssistant}
            isLastUser={item.id === lastUser}
          />
        )}
        extraData={streamingText}
        contentContainerStyle={styles.content}
        ItemSeparatorComponent={() => <View style={{ height: space.lg }} />}
        onScroll={onScroll}
        onScrollBeginDrag={() => {
          detached.current = true;
        }}
        scrollEventThrottle={32}
        onContentSizeChange={follow}
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="interactive"
        removeClippedSubviews={false}
        initialNumToRender={12}
        windowSize={11}
      />
      {showJump ? (
        <Animated.View entering={ZoomIn.springify().damping(16)} exiting={ZoomOut.duration(120)} style={styles.jumpWrap}>
          <PressableScale
            accessibilityRole="button"
            accessibilityLabel="Jump to latest"
            onPress={() => {
              detached.current = false;
              setShowJump(false);
              list.current?.scrollToEnd({ animated: true });
            }}
            scaleTo={0.9}
            style={[styles.jump, { backgroundColor: colors.surface, borderColor: colors.hairline }]}
          >
            <ArrowDown size={17} color={colors.ink} weight="bold" />
          </PressableScale>
        </Animated.View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  content: {
    paddingHorizontal: space.md,
    paddingTop: space.md,
    paddingBottom: space.lg,
    width: '100%',
    maxWidth: layout.maxReadingWidth,
    alignSelf: 'center',
  },
  jumpWrap: { position: 'absolute', bottom: space.sm, alignSelf: 'center' },
  jump: { width: 38, height: 38, borderRadius: 19, borderWidth: 1, alignItems: 'center', justifyContent: 'center' },
});
