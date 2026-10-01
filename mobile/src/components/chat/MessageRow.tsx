import * as Clipboard from 'expo-clipboard';
import { Image } from 'expo-image';
import { router } from 'expo-router';
import {
  ArrowClockwise,
  Check,
  Copy,
  FunctionIcon,
  PencilSimple,
  Trash,
  WarningCircle,
} from 'phosphor-react-native';
import { memo, useMemo, useState } from 'react';
import { StyleSheet, TextInput, View } from 'react-native';
import Animated, { FadeIn, FadeInDown } from 'react-native-reanimated';

import { AppText, Button, PressableScale, useHaptic } from '@/components/ui/primitives';
import { toast } from '@/components/ui/Toast';
import type { Message } from '@/core/db/types';
import { files } from '@/core/services/files';
import { answerText, holdOpenDisplayMath, splitMessageBlocks } from '@/core/utils/markdownBlocks';
import { useChat } from '@/state/chat';
import { useTheme } from '@/theme/ThemeProvider';
import { motion, radius, space } from '@/theme/tokens';
import { BrandMark } from './BrandMark';
import { CodeBlock } from './CodeBlock';
import { Markdown } from './Markdown';
import { MathBlock } from './MathBlock';
import { ThinkBlock } from './ThinkBlock';
import { ResponseStats, StreamStatus } from './TokenStats';

export const MessageRow = memo(function MessageRow({
  message,
  streamingText,
  isStreaming,
  isLastAssistant,
  isLastUser,
}: {
  message: Message;
  streamingText: string | null;
  isStreaming: boolean;
  isLastAssistant: boolean;
  isLastUser: boolean;
}) {
  if (message.role === 'user') return <UserMessage message={message} canEdit={isLastUser} />;
  if (message.isError) return <ErrorMessage message={message} />;
  return (
    <AssistantMessage
      message={message}
      text={isStreaming ? streamingText ?? '' : message.content}
      isStreaming={isStreaming}
      showActions={!isStreaming && isLastAssistant}
    />
  );
});

// ------------------------------------------------------------------- user

function UserMessage({ message, canEdit }: { message: Message; canEdit: boolean }) {
  const { colors, chatFont } = useTheme();
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(message.content);
  const editAndResend = useChat((s) => s.editAndResend);
  const busy = useChat((s) => s.isGenerating);
  const buzz = useHaptic();

  return (
    <Animated.View entering={FadeInDown.duration(motion.base).springify().damping(22)} style={styles.userWrap}>
      {message.imagePath ? (
        <Image
          source={{ uri: files.toUri(message.imagePath) }}
          style={[styles.attachment, { borderColor: colors.hairline }]}
          contentFit="cover"
          accessibilityLabel="Attached image"
        />
      ) : null}
      {editing ? (
        <View style={[styles.editBox, { backgroundColor: colors.surface, borderColor: colors.primary }]}>
          <TextInput
            value={draft}
            onChangeText={setDraft}
            multiline
            autoFocus
            style={{ color: colors.ink, fontFamily: chatFont, fontSize: 16, lineHeight: 24, maxHeight: 200 }}
            accessibilityLabel="Edit message"
          />
          <View style={styles.editActions}>
            <Button label="Cancel" variant="ghost" compact onPress={() => setEditing(false)} />
            <Button
              label="Send"
              compact
              disabled={!draft.trim() || busy}
              onPress={() => {
                setEditing(false);
                void editAndResend(message, draft);
              }}
            />
          </View>
        </View>
      ) : message.content ? (
        <PressableScale
          scaleTo={0.985}
          onLongPress={() => {
            buzz('medium');
            void Clipboard.setStringAsync(message.content);
            toast('Message copied');
          }}
          accessibilityHint="Long press to copy"
          style={[styles.userBubble, { backgroundColor: colors.userBubble }]}
        >
          <AppText selectable style={{ fontFamily: chatFont }}>
            {message.content}
          </AppText>
        </PressableScale>
      ) : null}
      {canEdit && !editing && !busy ? (
        <PressableScale
          accessibilityRole="button"
          accessibilityLabel="Edit and resend"
          onPress={() => {
            setDraft(message.content);
            setEditing(true);
          }}
          hitSlop={8}
          style={styles.editLink}
        >
          <PencilSimple size={14} color={colors.mutedSoft} />
          <AppText variant="caption" tone="mutedSoft">
            Edit
          </AppText>
        </PressableScale>
      ) : null}
    </Animated.View>
  );
}

// -------------------------------------------------------------- assistant

function AssistantMessage({
  message,
  text,
  isStreaming,
  showActions,
}: {
  message: Message;
  text: string;
  isStreaming: boolean;
  showActions: boolean;
}) {
  const blocks = useMemo(
    () => splitMessageBlocks(isStreaming ? holdOpenDisplayMath(text) : text, { forceMath: message.renderMath }),
    [text, isStreaming, message.renderMath],
  );
  const waiting = isStreaming && blocks.length === 0;
  const last = blocks[blocks.length - 1];
  const thinking = last?.type === 'think' && !last.complete;
  return (
    <Animated.View entering={FadeIn.duration(motion.base)} style={styles.assistantWrap}>
      <View style={styles.gutter}>
        <BrandMark size={22} spinning={isStreaming} />
      </View>
      <View style={styles.assistantBody}>
        {waiting ? null : (
          blocks.map((b, i) => {
            switch (b.type) {
              case 'prose':
                return <Markdown key={i} text={b.text} />;
              case 'code':
                return <CodeBlock key={i} source={b.source} language={b.language} />;
              case 'math':
                return <MathBlock key={i} latex={b.latex} />;
              case 'think':
                return <ThinkBlock key={i} text={b.text} complete={b.complete} />;
            }
          })
        )}
        {isStreaming ? <StreamStatus thinking={thinking} /> : null}
        {showActions ? <ActionRow message={message} /> : null}
        {!isStreaming ? <ResponseStats message={message} /> : null}
      </View>
    </Animated.View>
  );
}

function ActionRow({ message }: { message: Message }) {
  const regenerate = useChat((s) => s.regenerate);
  const toggleMath = useChat((s) => s.toggleRenderMath);
  const remove = useChat((s) => s.deleteMessage);
  const [copied, setCopied] = useState(false);
  const buzz = useHaptic();
  return (
    <Animated.View entering={FadeIn.delay(80).duration(motion.fast)} style={styles.actions}>
      <Action
        icon={copied ? Check : Copy}
        label="Copy answer"
        onPress={async () => {
          await Clipboard.setStringAsync(answerText(message.content).trim());
          buzz('success');
          setCopied(true);
          setTimeout(() => setCopied(false), 1500);
        }}
      />
      <Action icon={ArrowClockwise} label="Regenerate" onPress={() => void regenerate()} />
      <Action
        icon={FunctionIcon}
        label={message.renderMath ? 'Show raw text' : 'Render maths'}
        active={message.renderMath}
        onPress={() => void toggleMath(message)}
      />
      <Action icon={Trash} label="Delete answer" onPress={() => void remove(message)} />
    </Animated.View>
  );
}

function Action({ icon: Icon, label, onPress, active }: { icon: typeof Copy; label: string; onPress: () => void; active?: boolean }) {
  const { colors } = useTheme();
  return (
    <PressableScale
      accessibilityRole="button"
      accessibilityLabel={label}
      onPress={onPress}
      scaleTo={0.88}
      hitSlop={4}
      style={[styles.action, active && { backgroundColor: colors.primaryWash }]}
    >
      <Icon size={17} color={active ? colors.primary : colors.muted} />
    </PressableScale>
  );
}

// ------------------------------------------------------------------ error

function ErrorMessage({ message }: { message: Message }) {
  const { colors } = useTheme();
  const [title, ...rest] = message.content.split('\n\n');
  const recovery = rest.join('\n\n');
  const regenerate = useChat((s) => s.regenerate);
  const memory = /memory/i.test(message.content);
  const missing = /missing|download|Model Library/i.test(message.content);
  return (
    <Animated.View
      entering={FadeInDown.duration(motion.base)}
      style={[styles.error, { backgroundColor: colors.errorWash, borderColor: colors.error }]}
      accessibilityRole="alert"
    >
      <View style={{ flexDirection: 'row', gap: space.xs, alignItems: 'flex-start' }}>
        <WarningCircle size={20} color={colors.error} />
        <View style={{ flex: 1, gap: 4 }}>
          <AppText weight="medium">{title}</AppText>
          {recovery ? (
            <AppText variant="bodySmall" tone="body">
              {recovery}
            </AppText>
          ) : null}
        </View>
      </View>
      <View style={{ flexDirection: 'row', gap: space.xs, flexWrap: 'wrap', marginTop: space.sm }}>
        <Button label="Try again" variant="tonal" compact icon={ArrowClockwise} onPress={() => void regenerate()} />
        {missing || memory ? <Button label="Model Library" variant="ghost" compact onPress={() => router.push('/library')} /> : null}
        {memory ? <Button label="Settings" variant="ghost" compact onPress={() => router.push('/settings')} /> : null}
      </View>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  userWrap: { alignItems: 'flex-end', gap: 6, paddingLeft: '14%' },
  userBubble: {
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderRadius: 20,
    borderBottomRightRadius: 6,
    maxWidth: '100%',
  },
  attachment: { width: 168, height: 168, borderRadius: radius.lg, borderWidth: 1 },
  editBox: { alignSelf: 'stretch', borderRadius: radius.lg, borderWidth: 1.5, padding: space.sm, gap: space.xs },
  editActions: { flexDirection: 'row', justifyContent: 'flex-end', gap: space.xs },
  editLink: { flexDirection: 'row', alignItems: 'center', gap: 4, paddingHorizontal: 4 },
  assistantWrap: { flexDirection: 'row', gap: space.sm },
  gutter: { width: 24, paddingTop: 2, alignItems: 'center' },
  assistantBody: { flex: 1, gap: space.sm, minWidth: 0 },
  actions: { flexDirection: 'row', alignItems: 'center', gap: 2, marginLeft: -6 },
  action: { width: 34, height: 34, borderRadius: radius.sm, alignItems: 'center', justifyContent: 'center' },
  error: { borderRadius: radius.lg, borderWidth: 1, padding: space.md, marginLeft: 36 },
});
