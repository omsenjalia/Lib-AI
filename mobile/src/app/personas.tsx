import { PencilSimple, Plus, Trash } from 'phosphor-react-native';
import { useState } from 'react';
import { StyleSheet, TextInput, View } from 'react-native';
import Animated, { FadeInDown, LinearTransition } from 'react-native-reanimated';

import { Sheet } from '@/components/ui/Sheet';
import { ConfirmSheet, Screen } from '@/components/ui/Screen';
import { AppText, Button, Chip, IconButton } from '@/components/ui/primitives';
import { toast } from '@/components/ui/Toast';
import type { Persona } from '@/core/db/types';
import { usePersonas } from '@/state/collections';
import { useTheme } from '@/theme/ThemeProvider';
import { motion, radius, space } from '@/theme/tokens';

type Draft = { id?: number; name: string; emoji: string; systemPrompt: string };

/** Six built-in study personas plus your own. A persona is a system prompt with a name. */
export default function PersonasScreen() {
  const { colors } = useTheme();
  const list = usePersonas((s) => s.list);
  const save = usePersonas((s) => s.save);
  const remove = usePersonas((s) => s.remove);
  const [draft, setDraft] = useState<Draft | null>(null);
  const [deleting, setDeleting] = useState<Persona | null>(null);

  return (
    <Screen
      title="Study personas"
      trailing={<IconButton icon={Plus} label="New persona" onPress={() => setDraft({ name: '', emoji: '\u{1F393}', systemPrompt: '' })} tone="ink" />}
    >
      <View style={{ padding: space.md, gap: space.sm }}>
        <AppText variant="bodySmall" tone="muted">
          {"Pick one from a chat's menu. It replaces your default instruction for that chat."}
        </AppText>
        {list.map((p, i) => (
          <Animated.View
            key={p.id}
            entering={FadeInDown.delay(i * 40).springify().damping(20)}
            layout={LinearTransition.duration(motion.base)}
            style={[styles.card, { backgroundColor: colors.surface, borderColor: colors.hairline }]}
          >
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: space.sm }}>
              <AppText variant="heading">{p.emoji}</AppText>
              <View style={{ flex: 1, gap: 2 }}>
                <AppText weight="bold">{p.name}</AppText>
                {p.isBuiltIn ? <Chip label="Built in" /> : null}
              </View>
              {!p.isBuiltIn ? (
                <>
                  <IconButton icon={PencilSimple} label={`Edit ${p.name}`} onPress={() => setDraft({ ...p })} />
                  <IconButton icon={Trash} label={`Delete ${p.name}`} tone="error" onPress={() => setDeleting(p)} />
                </>
              ) : (
                <IconButton
                  icon={PencilSimple}
                  label={`Copy ${p.name} as a new persona`}
                  onPress={() => setDraft({ name: `${p.name} (mine)`, emoji: p.emoji, systemPrompt: p.systemPrompt })}
                />
              )}
            </View>
            <AppText variant="bodySmall" tone="body" numberOfLines={4}>
              {p.systemPrompt}
            </AppText>
          </Animated.View>
        ))}
      </View>

      <Sheet visible={draft !== null} onClose={() => setDraft(null)} title={draft?.id ? 'Edit persona' : 'New persona'}>
        {draft ? (
          <View style={{ paddingHorizontal: space.md, gap: space.sm }}>
            <View style={{ flexDirection: 'row', gap: space.xs }}>
              <TextInput
                value={draft.emoji}
                onChangeText={(emoji) => setDraft({ ...draft, emoji: [...emoji].slice(-2).join('') })}
                accessibilityLabel="Emoji"
                style={[styles.input, { width: 56, textAlign: 'center', color: colors.ink, borderColor: colors.hairline }]}
              />
              <TextInput
                value={draft.name}
                onChangeText={(name) => setDraft({ ...draft, name })}
                placeholder="Name"
                maxLength={60}
                placeholderTextColor={colors.mutedSoft}
                accessibilityLabel="Persona name"
                style={[styles.input, { flex: 1, color: colors.ink, borderColor: colors.hairline }]}
              />
            </View>
            <TextInput
              value={draft.systemPrompt}
              onChangeText={(systemPrompt) => setDraft({ ...draft, systemPrompt })}
              placeholder="You are a ... Explain ... Format maths as LaTeX."
              placeholderTextColor={colors.mutedSoft}
              multiline
              accessibilityLabel="System prompt"
              style={[styles.input, { minHeight: 160, textAlignVertical: 'top', color: colors.ink, borderColor: colors.hairline }]}
            />
            <View style={{ flexDirection: 'row', justifyContent: 'flex-end', gap: space.xs }}>
              <Button label="Cancel" variant="ghost" onPress={() => setDraft(null)} />
              <Button
                label="Save"
                disabled={!draft.name.trim() || !draft.systemPrompt.trim()}
                onPress={async () => {
                  await save({ ...draft, name: draft.name.trim(), emoji: draft.emoji || '\u{1F4DA}' });
                  setDraft(null);
                  toast('Persona saved.');
                }}
              />
            </View>
          </View>
        ) : null}
      </Sheet>

      <ConfirmSheet
        visible={deleting !== null}
        title={`Delete ${deleting?.name ?? 'persona'}?`}
        body="Chats that used it keep their messages and fall back to your default instruction."
        confirmLabel="Delete persona"
        danger
        onConfirm={() => deleting && void remove(deleting.id)}
        onClose={() => setDeleting(null)}
      />
    </Screen>
  );
}

const styles = StyleSheet.create({
  card: { borderRadius: radius.xl, borderWidth: 1, padding: space.md, gap: space.xs },
  input: { borderWidth: 1, borderRadius: radius.md, paddingHorizontal: space.sm, paddingVertical: 10, fontSize: 15 },
});
