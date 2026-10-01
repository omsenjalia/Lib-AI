import { router } from 'expo-router';
import {
  Books,
  Check,
  Copy,
  Eye,
  FilePdf,
  FileText,
  PencilSimple,
  PushPin,
  Trash,
  UserSound,
} from 'phosphor-react-native';
import { useState } from 'react';
import { ScrollView, TextInput, View } from 'react-native';

import { Sheet } from '@/components/ui/Sheet';
import { AppText, Button, Chip, PressableScale, useHaptic } from '@/components/ui/primitives';
import { toast } from '@/components/ui/Toast';
import { catalogue, modelById } from '@/core/catalogue';
import * as db from '@/core/db/database';
import type { Conversation } from '@/core/db/types';
import { sharePdf, shareMarkdown } from '@/core/services/exporter';
import { useChat } from '@/state/chat';
import { useConversations, usePersonas } from '@/state/collections';
import { useEngineStatus } from '@/state/engineStatus';
import { useActiveModelId, useLibrary } from '@/state/library';
import { useTheme } from '@/theme/ThemeProvider';
import { radius, space } from '@/theme/tokens';
import { SheetRow } from './Composer';

// ---------------------------------------------------------- model switcher

export function ModelSwitcherSheet({ visible, onClose }: { visible: boolean; onClose: () => void }) {
  const { colors } = useTheme();
  const installations = useLibrary((s) => s.installations);
  const setActive = useLibrary((s) => s.setActive);
  const activeId = useActiveModelId();
  const resident = useEngineStatus((s) => (s.stage === 'ready' ? s.modelId : null));
  const buzz = useHaptic();
  const installed = catalogue.models.filter((m) => installations[m.id]);
  const others = catalogue.models.filter((m) => !installations[m.id]);

  return (
    <Sheet visible={visible} onClose={onClose} title="Switch model">
      <ScrollView contentContainerStyle={{ paddingHorizontal: space.md, gap: space.xs, paddingBottom: space.sm }}>
        {installed.length === 0 ? (
          <AppText tone="muted" variant="bodySmall">
            No models on this phone yet.
          </AppText>
        ) : null}
        {installed.map((m) => {
          const active = m.id === activeId;
          const vision = m.visionSupported && Boolean(installations[m.id]?.mmprojPath);
          return (
            <PressableScale
              key={m.id}
              accessibilityRole="radio"
              accessibilityState={{ selected: active }}
              onPress={() => {
                buzz('select');
                void setActive(m.id);
                onClose();
              }}
              style={{
                flexDirection: 'row',
                alignItems: 'center',
                gap: space.sm,
                padding: space.sm,
                borderRadius: radius.lg,
                borderWidth: 1,
                borderColor: active ? colors.primary : colors.hairline,
                backgroundColor: active ? colors.primaryWash : colors.surface,
              }}
            >
              <View style={{ flex: 1, gap: 4 }}>
                <AppText weight="medium">{m.displayName}</AppText>
                <View style={{ flexDirection: 'row', gap: 6, flexWrap: 'wrap' }}>
                  <Chip label={m.parameterCount} />
                  <Chip label={installations[m.id]!.quant} />
                  {vision ? <Chip label="Vision" tone="accent" /> : null}
                  {resident === m.id ? <Chip label="In memory" tone="success" /> : null}
                </View>
              </View>
              {active ? <Check size={20} color={colors.primary} weight="bold" /> : null}
            </PressableScale>
          );
        })}
        {others.length ? (
          <View style={{ marginTop: space.sm }}>
            <SheetRow
              icon={Books}
              label="Get more models"
              hint={`${others.length} more in the Model Library`}
              onPress={() => {
                onClose();
                router.push('/library');
              }}
            />
          </View>
        ) : null}
        <AppText variant="caption" tone="mutedSoft" style={{ marginTop: space.xs }}>
          Switching frees the current model from memory before the next one loads.
        </AppText>
      </ScrollView>
    </Sheet>
  );
}

// ---------------------------------------------------------- persona picker

export function PersonaPickerSheet({
  visible,
  onClose,
  conversation,
}: {
  visible: boolean;
  onClose: () => void;
  conversation: Conversation | null;
}) {
  const { colors } = useTheme();
  const personas = usePersonas((s) => s.list);
  const setPersona = useChat((s) => s.setPersona);
  const current = conversation?.personaId ?? null;
  const pick = (id: number | null) => {
    void setPersona(id);
    onClose();
  };
  return (
    <Sheet visible={visible} onClose={onClose} title="Study persona">
      <ScrollView contentContainerStyle={{ paddingHorizontal: space.md, gap: 6, paddingBottom: space.sm }}>
        <PersonaOption emoji="✦" name="None" hint="Your default instruction, or the built-in study prompt" selected={current === null} onPress={() => pick(null)} />
        {personas.map((p) => (
          <PersonaOption
            key={p.id}
            emoji={p.emoji}
            name={p.name}
            hint={p.systemPrompt}
            selected={current === p.id}
            onPress={() => pick(p.id)}
          />
        ))}
        <Button
          label="Manage personas"
          variant="ghost"
          compact
          onPress={() => {
            onClose();
            router.push('/personas');
          }}
          style={{ marginTop: space.xs, alignSelf: 'flex-start', borderColor: colors.hairline }}
        />
      </ScrollView>
    </Sheet>
  );
}

function PersonaOption({ emoji, name, hint, selected, onPress }: { emoji: string; name: string; hint: string; selected: boolean; onPress: () => void }) {
  const { colors } = useTheme();
  return (
    <PressableScale
      accessibilityRole="radio"
      accessibilityState={{ selected }}
      onPress={onPress}
      haptic
      style={{
        flexDirection: 'row',
        gap: space.sm,
        alignItems: 'center',
        padding: space.sm,
        borderRadius: radius.md,
        backgroundColor: selected ? colors.primaryWash : 'transparent',
      }}
    >
      <AppText variant="title">{emoji}</AppText>
      <View style={{ flex: 1 }}>
        <AppText weight="medium">{name}</AppText>
        <AppText variant="caption" tone="muted" numberOfLines={1}>
          {hint}
        </AppText>
      </View>
      {selected ? <Check size={18} color={colors.primary} weight="bold" /> : null}
    </PressableScale>
  );
}

// -------------------------------------------------------- chat actions

export function ConversationActionsSheet({
  conversation,
  onClose,
  onPersona,
}: {
  conversation: Conversation | null;
  onClose: () => void;
  onPersona: () => void;
}) {
  if (!conversation) return <Sheet visible={false} onClose={onClose}>{null}</Sheet>;
  // Keyed so the rename field starts fresh for each conversation.
  return <ActionsBody key={conversation.id} conversation={conversation} onClose={onClose} onPersona={onPersona} />;
}

function ActionsBody({
  conversation,
  onClose,
  onPersona,
}: {
  conversation: Conversation;
  onClose: () => void;
  onPersona: () => void;
}) {
  const { colors } = useTheme();
  const [renaming, setRenaming] = useState(false);
  const [title, setTitle] = useState(conversation.title);
  const rename = useConversations((s) => s.rename);
  const togglePin = useConversations((s) => s.togglePin);
  const remove = useConversations((s) => s.remove);
  const undo = useConversations((s) => s.undoDelete);
  const open = useChat((s) => s.open);
  const newChat = useChat((s) => s.newChat);
  const activeId = useChat((s) => s.conversationId);
  const personas = usePersonas((s) => s.list);

  const persona = personas.find((p) => p.id === conversation.personaId);
  const modelName = modelById(conversation.modelId)?.displayName ?? null;
  const run = (fn: () => Promise<void>, failure: string) => async () => {
    onClose();
    try {
      await fn();
    } catch (e) {
      toast(e instanceof Error && e.message ? e.message : failure);
    }
  };

  return (
    <Sheet visible onClose={onClose}>
      <View style={{ paddingHorizontal: space.md, paddingBottom: space.xs }}>
        {renaming ? (
          <View style={{ gap: space.xs }}>
            <TextInput
              value={title}
              onChangeText={setTitle}
              autoFocus
              selectTextOnFocus
              maxLength={200}
              accessibilityLabel="Conversation title"
              style={{
                fontSize: 17,
                color: colors.ink,
                borderWidth: 1,
                borderColor: colors.primary,
                borderRadius: radius.md,
                paddingHorizontal: space.sm,
                paddingVertical: 10,
              }}
              onSubmitEditing={() => {
                void rename(conversation.id, title);
                onClose();
              }}
            />
            <View style={{ flexDirection: 'row', justifyContent: 'flex-end', gap: space.xs }}>
              <Button label="Cancel" variant="ghost" compact onPress={() => setRenaming(false)} />
              <Button
                label="Save"
                compact
                disabled={!title.trim()}
                onPress={() => {
                  void rename(conversation.id, title);
                  onClose();
                }}
              />
            </View>
          </View>
        ) : (
          <AppText variant="title" weight="medium" numberOfLines={2} style={{ paddingBottom: space.xs }}>
            {conversation.title}
          </AppText>
        )}
      </View>
      {!renaming ? (
        <ScrollView contentContainerStyle={{ paddingHorizontal: space.md, paddingBottom: space.xs }}>
          <SheetRow icon={PencilSimple} label="Rename" onPress={() => setRenaming(true)} />
          <SheetRow
            icon={PushPin}
            label={conversation.pinned ? 'Unpin' : 'Pin to top'}
            onPress={() => {
              void togglePin(conversation);
              onClose();
            }}
          />
          <SheetRow
            icon={UserSound}
            label="Study persona"
            hint={persona ? `${persona.emoji} ${persona.name}` : 'None'}
            onPress={() => {
              onClose();
              if (activeId !== conversation.id) void open(conversation.id);
              onPersona();
            }}
          />
          <SheetRow
            icon={Copy}
            label="Duplicate"
            onPress={run(async () => {
              const id = await db.duplicateConversation(conversation.id);
              if (id) await open(id);
            }, 'Could not duplicate this chat.')}
          />
          <SheetRow icon={FilePdf} label="Share as PDF" hint="Typeset maths, offline" onPress={run(() => sharePdf(conversation.id, modelName), 'Could not create the PDF.')} />
          <SheetRow icon={FileText} label="Share as Markdown" onPress={run(() => shareMarkdown(conversation.id), 'Could not export.')} />
          {activeId !== conversation.id ? (
            <SheetRow icon={Eye} label="Open" onPress={run(() => open(conversation.id), 'Could not open.')} />
          ) : null}
          <SheetRow
            icon={Trash}
            label="Delete"
            danger
            onPress={run(async () => {
              if (activeId === conversation.id) newChat();
              await remove(conversation.id);
              toast(`Deleted "${conversation.title}"`, { action: { label: 'Undo', run: () => void undo() }, ms: 5000 });
            }, 'Could not delete.')}
          />
        </ScrollView>
      ) : null}
    </Sheet>
  );
}
