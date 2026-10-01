import { Image } from 'expo-image';
import { router } from 'expo-router';
import { ArrowUp, Camera, ImageSquare, Plus, Stop, X } from 'phosphor-react-native';
import { useEffect, useRef, useState } from 'react';
import { Platform, StyleSheet, TextInput, View } from 'react-native';
import Animated, { FadeIn, FadeOut, LinearTransition, ZoomIn, ZoomOut } from 'react-native-reanimated';

import { Sheet } from '@/components/ui/Sheet';
import { AppText, PressableScale, useHaptic } from '@/components/ui/primitives';
import { toast } from '@/components/ui/Toast';
import { modelById } from '@/core/catalogue';
import { deleteAttachment, pickImage, type PickSource } from '@/core/services/attachments';
import { files } from '@/core/services/files';
import { useChat } from '@/state/chat';
import { useEngineStatus } from '@/state/engineStatus';
import { useActiveModelId, useLibrary } from '@/state/library';
import { useTheme } from '@/theme/ThemeProvider';
import { motion, radius, space } from '@/theme/tokens';

/**
 * The composer floats on the canvas: a pill field, attach on the left, a send
 * button on the right that becomes Stop while the model writes. It grows to
 * about six lines, then scrolls inside itself.
 */
export function Composer() {
  const { colors, chatFont } = useTheme();
  const [text, setText] = useState('');
  const [image, setImage] = useState<string | null>(null);
  const [attachOpen, setAttachOpen] = useState(false);
  const [focused, setFocused] = useState(false);
  // react-native-web does not auto-grow a textarea; track its content height there.
  const [webHeight, setWebHeight] = useState(36);
  const input = useRef<TextInput>(null);
  const buzz = useHaptic();

  const send = useChat((s) => s.send);
  const stop = useChat((s) => s.stop);
  const busy = useChat((s) => s.isGenerating);
  const activeId = useActiveModelId();
  const install = useLibrary((s) => (activeId ? s.installations[activeId] : undefined));
  const loading = useEngineStatus((s) => s.stage === 'verifying' || s.stage === 'readingMetadata' || s.stage === 'loadingWeights');
  const model = modelById(activeId);
  const vision = Boolean(model?.visionSupported && install?.mmprojPath);
  const noModel = !activeId;

  // A starter chip hands the composer a draft. Subscribing (rather than
  // mirroring the store into state in an effect) applies it exactly once.
  useEffect(
    () =>
      useChat.subscribe((s, prev) => {
        if (s.draft && s.draft !== prev.draft) {
          setText(s.draft.text);
          input.current?.focus();
        }
      }),
    [],
  );

  const canSend = !busy && !noModel && (text.trim().length > 0 || image !== null);

  const submit = () => {
    if (!canSend) return;
    buzz('light');
    const t = text;
    const img = image;
    setText('');
    setWebHeight(36);
    setImage(null);
    void send(t, img);
  };

  const attach = async (source: PickSource) => {
    setAttachOpen(false);
    try {
      const path = await pickImage(source);
      if (path) {
        if (image) await deleteAttachment(image);
        setImage(path);
      }
    } catch {
      toast('Could not attach that image.');
    }
  };

  return (
    <View style={styles.wrap}>
      {image ? (
        <Animated.View entering={ZoomIn.springify().damping(18)} exiting={ZoomOut.duration(motion.fast)} style={styles.preview}>
          <Image source={{ uri: files.toUri(image) }} style={[styles.thumb, { borderColor: colors.hairline }]} contentFit="cover" />
          <PressableScale
            accessibilityRole="button"
            accessibilityLabel="Remove image"
            onPress={() => {
              void deleteAttachment(image);
              setImage(null);
            }}
            style={[styles.removeImage, { backgroundColor: colors.ink }]}
            hitSlop={8}
          >
            <X size={12} color={colors.canvas} weight="bold" />
          </PressableScale>
        </Animated.View>
      ) : null}

      <Animated.View
        layout={LinearTransition.duration(motion.fast)}
        // The pill's border is the focus indicator, so it must change visibly.
        style={[styles.field, { backgroundColor: colors.surface, borderColor: focused ? colors.primary : colors.hairline }]}
      >
        <PressableScale
          accessibilityRole="button"
          accessibilityLabel="Attach an image"
          onPress={() => {
            if (!vision) {
              toast(noModel ? 'Download a model first.' : `${model?.displayName ?? 'This model'} reads text only. Pick a vision model to attach images.`, {
                ms: 4200,
              });
              return;
            }
            setAttachOpen(true);
          }}
          scaleTo={0.88}
          style={[styles.roundBtn, { backgroundColor: colors.surfaceSoft, opacity: vision ? 1 : 0.55 }]}
        >
          <Plus size={18} color={colors.body} />
        </PressableScale>

        <TextInput
          ref={input}
          value={text}
          onChangeText={(t) => {
            setText(t);
            if (!t) setWebHeight(36);
          }}
          editable={!noModel}
          onFocus={() => setFocused(true)}
          onBlur={() => setFocused(false)}
          placeholder={noModel ? 'Download a model to start' : loading ? 'Loading the model...' : 'Message Library AI'}
          placeholderTextColor={colors.mutedSoft}
          multiline
          // react-native-web defaults a multiline field to two rows.
          {...(Platform.OS === 'web' ? { rows: 1 } : null)}
          accessibilityLabel="Message"
          style={[
            styles.input,
            webNoOutline,
            Platform.OS === 'web' ? { height: Math.min(164, Math.max(36, webHeight)) } : null,
            { color: colors.ink, fontFamily: chatFont },
          ]}
          // On a keyboard, Enter sends and Shift+Enter starts a new line.
          onKeyPress={
            Platform.OS === 'web'
              ? (e) => {
                  const ev = e.nativeEvent as unknown as { key: string; shiftKey?: boolean };
                  if (ev.key === 'Enter' && !ev.shiftKey) {
                    (e as unknown as { preventDefault(): void }).preventDefault();
                    submit();
                  }
                }
              : undefined
          }
          onContentSizeChange={Platform.OS === 'web' ? (e) => setWebHeight(e.nativeEvent.contentSize.height) : undefined}
          cursorColor={colors.primary}
          selectionColor={colors.primaryWash}
        />

        {busy ? (
          <Animated.View key="stop" entering={ZoomIn.duration(motion.fast)} exiting={FadeOut.duration(80)}>
            <PressableScale
              accessibilityRole="button"
              accessibilityLabel="Stop generating"
              onPress={() => {
                buzz('medium');
                void stop();
              }}
              scaleTo={0.88}
              style={[styles.roundBtn, { backgroundColor: colors.ink }]}
            >
              <Stop size={14} color={colors.canvas} weight="fill" />
            </PressableScale>
          </Animated.View>
        ) : noModel ? (
          <Animated.View key="library" entering={FadeIn}>
            <PressableScale
              accessibilityRole="button"
              accessibilityLabel="Open Model Library"
              onPress={() => router.push('/library')}
              style={[styles.libraryBtn, { backgroundColor: colors.ink }]}
            >
              <AppText variant="caption" weight="bold" tone="onAccent">
                Get a model
              </AppText>
            </PressableScale>
          </Animated.View>
        ) : (
          <Animated.View key="send" entering={ZoomIn.duration(motion.fast)} exiting={FadeOut.duration(80)}>
            <PressableScale
              accessibilityRole="button"
              accessibilityLabel="Send"
              accessibilityState={{ disabled: !canSend }}
              onPress={submit}
              disabled={!canSend}
              scaleTo={0.88}
              style={[styles.roundBtn, { backgroundColor: canSend ? colors.primary : colors.hairline }]}
            >
              <ArrowUp size={18} color={canSend ? '#FFFFFF' : colors.mutedSoft} weight="bold" />
            </PressableScale>
          </Animated.View>
        )}
      </Animated.View>
      <AppText variant="micro" tone="mutedSoft" style={{ textAlign: 'center', marginTop: 6 }}>
        Runs on this phone. Answers can be wrong; check what matters.
      </AppText>

      <Sheet visible={attachOpen} onClose={() => setAttachOpen(false)} title="Add an image">
        <View style={{ paddingHorizontal: space.md, gap: space.xs }}>
          <SheetRow icon={Camera} label="Take a photo" hint="OCR mode: photograph a page or a problem" onPress={() => void attach('camera')} />
          <SheetRow icon={ImageSquare} label="Choose from gallery" onPress={() => void attach('library')} />
        </View>
      </Sheet>
    </View>
  );
}

export function SheetRow({
  icon: Icon,
  label,
  hint,
  onPress,
  danger,
  trailing,
}: {
  icon: typeof Camera;
  label: string;
  hint?: string;
  onPress: () => void;
  danger?: boolean;
  trailing?: React.ReactNode;
}) {
  const { colors } = useTheme();
  return (
    <PressableScale
      accessibilityRole="button"
      onPress={onPress}
      haptic
      style={{ flexDirection: 'row', alignItems: 'center', gap: space.sm, paddingVertical: space.sm, paddingHorizontal: space.xs, borderRadius: radius.md }}
    >
      <View style={{ width: 36, height: 36, borderRadius: radius.md, backgroundColor: danger ? colors.errorWash : colors.surfaceSoft, alignItems: 'center', justifyContent: 'center' }}>
        <Icon size={19} color={danger ? colors.error : colors.body} />
      </View>
      <View style={{ flex: 1 }}>
        <AppText weight="medium" tone={danger ? 'error' : 'ink'}>
          {label}
        </AppText>
        {hint ? (
          <AppText variant="caption" tone="muted">
            {hint}
          </AppText>
        ) : null}
      </View>
      {trailing}
    </PressableScale>
  );
}

/** The browser's own focus ring would double the pill border. */
const webNoOutline = (Platform.OS === 'web' ? { outlineStyle: 'none' } : {}) as object;

const styles = StyleSheet.create({
  wrap: { paddingHorizontal: space.sm, paddingTop: space.xs },
  field: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    borderRadius: 26,
    borderWidth: 1,
    padding: 6,
    gap: 6,
  },
  input: {
    flex: 1,
    fontSize: 16,
    lineHeight: 22,
    maxHeight: 150,
    paddingTop: Platform.OS === 'ios' ? 9 : 7,
    paddingBottom: Platform.OS === 'ios' ? 9 : 7,
    paddingHorizontal: 4,
    textAlignVertical: 'center',
  },
  roundBtn: { width: 36, height: 36, borderRadius: 18, alignItems: 'center', justifyContent: 'center' },
  libraryBtn: { height: 36, borderRadius: 18, paddingHorizontal: 14, alignItems: 'center', justifyContent: 'center' },
  preview: { marginLeft: space.xs, marginBottom: space.xs, alignSelf: 'flex-start' },
  thumb: { width: 64, height: 64, borderRadius: radius.md, borderWidth: 1 },
  removeImage: { position: 'absolute', top: -6, right: -6, width: 22, height: 22, borderRadius: 11, alignItems: 'center', justifyContent: 'center' },
});
