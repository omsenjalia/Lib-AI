import * as Application from 'expo-application';
import { useEffect, useState, type ReactNode } from 'react';
import { Platform, StyleSheet, TextInput, View } from 'react-native';

import { ConfirmSheet, Screen } from '@/components/ui/Screen';
import { Segmented, Slider, Toggle } from '@/components/ui/controls';
import { AppText, Button, Divider, SectionLabel } from '@/components/ui/primitives';
import { toast } from '@/components/ui/Toast';
import { modelById } from '@/core/catalogue';
import { AppConstants } from '@/core/constants';
import { deleteAllConversations, messageStats } from '@/core/db/database';
import { shareBackup } from '@/core/services/exporter';
import { files } from '@/core/services/files';
import { contextBoundsFor, type ChatFont, type ThemeMode } from '@/core/settings';
import { formatBytes } from '@/core/utils/formatters';
import { useChat } from '@/state/chat';
import { useEngineStatus } from '@/state/engineStatus';
import { useActiveModelId, useLibrary } from '@/state/library';
import { useSettings } from '@/state/settings';
import { useTheme } from '@/theme/ThemeProvider';
import { radius, space } from '@/theme/tokens';

export default function SettingsScreen() {
  const { colors } = useTheme();
  const s = useSettings((x) => x.settings);
  const patch = useSettings((x) => x.patch);
  const activeId = useActiveModelId();
  const model = modelById(activeId);
  const installations = useLibrary((x) => x.installations);
  const engine = useEngineStatus();
  const bounds = contextBoundsFor(model?.maxContextLength);

  // Live values while a slider is dragged; committed on release.
  const [ctx, setCtx] = useState(s.contextLength);
  const [temp, setTemp] = useState(s.temperature);
  const [topP, setTopP] = useState(s.topP);
  const [topK, setTopK] = useState(s.topK);
  const [gpu, setGpu] = useState(s.gpuLayers);
  const [prompt, setPrompt] = useState(s.systemPrompt ?? '');
  const [stats, setStats] = useState({ conversations: 0, messages: 0 });
  const [partials, setPartials] = useState(0);
  const [confirmWipe, setConfirmWipe] = useState(false);

  useEffect(() => {
    void messageStats().then(setStats);
    void files.partialBytes().then(setPartials);
  }, []);

  const modelBytes = Object.values(installations).reduce((t, i) => t + i.totalBytes, 0);

  return (
    <Screen title="Settings">
      <SectionLabel>Appearance</SectionLabel>
      <Group>
        <Row label="Theme">
          <Segmented<ThemeMode>
            value={s.themeMode}
            onChange={(v) => void patch({ themeMode: v })}
            options={[
              { value: 'system', label: 'System' },
              { value: 'light', label: 'Light' },
              { value: 'dark', label: 'Dark' },
            ]}
          />
        </Row>
        <Row label="Chat font">
          <Segmented<ChatFont>
            value={s.chatFont}
            onChange={(v) => void patch({ chatFont: v })}
            options={[
              { value: 'lato', label: 'Sans' },
              { value: 'lora', label: 'Serif' },
              { value: 'system', label: 'System' },
            ]}
          />
        </Row>
        <InlineRow label="Haptic feedback">
          <Toggle value={s.haptics} onChange={(v) => void patch({ haptics: v })} label="Haptic feedback" />
        </InlineRow>
      </Group>

      <SectionLabel>AI behaviour</SectionLabel>
      <Group>
        <Row label="Context length" value={`${ctx.toLocaleString()} tokens`}>
          <Slider
            label="Context length"
            value={ctx}
            min={bounds.min}
            max={Math.min(bounds.max, 32768)}
            step={512}
            onChange={setCtx}
            onCommit={(v) => {
              setCtx(v);
              void patch({ contextLength: v });
            }}
          />
          <Hint>
            {ctx < AppConstants.unsafeContextLength
              ? 'Below 1,024 tokens most system prompts barely fit. Expect the model to forget quickly.'
              : model
                ? `${model.displayName} recommends ${model.recommendedContextLength.toLocaleString()}. More context costs memory: about 200 MB per extra 1,024 tokens.`
                : 'More context costs memory.'}
          </Hint>
        </Row>
        <Row label="Temperature" value={temp.toFixed(2)}>
          <Slider label="Temperature" value={temp} min={0} max={1.5} step={0.05} onChange={setTemp} onCommit={(v) => void patch({ temperature: v })} />
          {temp < AppConstants.repetitionRiskTemperature ? <Hint tone="warning">Very low temperatures can make some models repeat themselves.</Hint> : null}
        </Row>
        <Row label="Top-p" value={topP.toFixed(2)}>
          <Slider label="Top-p" value={topP} min={0.05} max={1} step={0.05} onChange={setTopP} onCommit={(v) => void patch({ topP: v })} />
        </Row>
        <Row label="Top-k" value={String(topK)}>
          <Slider label="Top-k" value={topK} min={1} max={100} step={1} onChange={setTopK} onCommit={(v) => void patch({ topK: v })} />
        </Row>
        <Row label="GPU layers" value={gpu === 0 ? 'CPU only' : gpu >= 99 ? 'All' : String(gpu)}>
          <Slider label="GPU layers" value={gpu} min={0} max={99} step={1} onChange={setGpu} onCommit={(v) => void patch({ gpuLayers: v })} />
          <Hint>
            OpenCL offload works on Adreno 700-series GPUs and newer. If it fails, the model reloads on the CPU automatically.
            {engine.stage === 'ready' ? (engine.gpu ? ' The loaded model is using the GPU.' : ' The loaded model is running on the CPU.') : ''}
          </Hint>
        </Row>
        <Row label="Default instruction">
          <TextInput
            value={prompt}
            onChangeText={setPrompt}
            onEndEditing={() => void patch({ systemPrompt: prompt.trim() ? prompt : null })}
            multiline
            placeholder="How should the assistant answer when no persona is chosen?"
            placeholderTextColor={colors.mutedSoft}
            accessibilityLabel="Default instruction"
            style={[styles.textArea, { color: colors.ink, borderColor: colors.hairline, backgroundColor: colors.surfaceSoft }]}
          />
          <Hint>A persona on a chat replaces this. Neither is stacked on the other.</Hint>
        </Row>
      </Group>

      <SectionLabel>Updates</SectionLabel>
      <Group>
        <InlineRow label="Check for model updates" hint="At most once a day per model, never on mobile data for Wi-Fi-only models. Never downloads on its own.">
          <Toggle value={s.autoUpdateCheckEnabled} onChange={(v) => void patch({ autoUpdateCheckEnabled: v })} label="Check for model updates" />
        </InlineRow>
      </Group>

      <SectionLabel>Storage</SectionLabel>
      <Group>
        <InlineRow label="Models" hint={`${Object.keys(installations).length} installed`}>
          <AppText variant="bodySmall" tone="muted">
            {formatBytes(modelBytes)}
          </AppText>
        </InlineRow>
        <InlineRow label="Conversations" hint={`${stats.messages.toLocaleString()} messages`}>
          <AppText variant="bodySmall" tone="muted">
            {stats.conversations.toLocaleString()}
          </AppText>
        </InlineRow>
        {partials > 0 ? (
          <InlineRow label="Unfinished downloads" hint={formatBytes(partials)}>
            <Button
              label="Discard"
              variant="danger"
              compact
              onPress={async () => {
                const freed = await files.deletePartials();
                setPartials(0);
                toast(`Freed ${formatBytes(freed)}.`);
              }}
            />
          </InlineRow>
        ) : null}
        <View style={styles.buttons}>
          <Button
            label="Export all chats"
            variant="tonal"
            compact
            disabled={Platform.OS === 'web'}
            onPress={() => void shareBackup().catch(() => toast('Export failed.'))}
          />
          <Button label="Delete all chats" variant="danger" compact onPress={() => setConfirmWipe(true)} />
        </View>
      </Group>

      <SectionLabel>About</SectionLabel>
      <Group>
        <InlineRow label="Version">
          <AppText variant="bodySmall" tone="muted">
            {Application.nativeApplicationVersion ?? '2.0.0'}
            {Application.nativeBuildVersion ? ` (${Application.nativeBuildVersion})` : ''}
          </AppText>
        </InlineRow>
        <View style={{ padding: space.md, gap: space.xs }}>
          <AppText variant="bodySmall" tone="body">
            Every answer is generated on this phone by llama.cpp. Conversations, personas and settings live in one SQLite file in
            private app storage. There is no account, no server and no analytics.
          </AppText>
          <AppText variant="caption" tone="muted">
            Open source: llama.cpp and llama.rn (MIT), KaTeX (MIT), marked (MIT), Lato, Lora and JetBrains Mono (SIL Open Font
            License 1.1). Model weights are not part of the app; each carries its own licence on HuggingFace.
          </AppText>
          {Platform.OS === 'web' ? (
            <AppText variant="caption" tone="warning">
              This is the browser preview. It streams a sample answer instead of running a model.
            </AppText>
          ) : null}
        </View>
      </Group>

      <ConfirmSheet
        visible={confirmWipe}
        title="Delete every conversation?"
        body="This removes all chats from this phone. It cannot be undone. Export first if you want a copy."
        confirmLabel="Delete all"
        danger
        onConfirm={async () => {
          useChat.getState().newChat();
          await deleteAllConversations();
          setStats({ conversations: 0, messages: 0 });
          toast('All conversations deleted.');
        }}
        onClose={() => setConfirmWipe(false)}
      />
    </Screen>
  );
}

function Group({ children }: { children: ReactNode }) {
  const { colors } = useTheme();
  const items = Array.isArray(children) ? children.filter(Boolean) : [children];
  return (
    <View style={[styles.group, { backgroundColor: colors.surface, borderColor: colors.hairline }]}>
      {items.map((c, i) => (
        <View key={i}>
          {i > 0 ? <Divider inset={space.md} /> : null}
          {c}
        </View>
      ))}
    </View>
  );
}

function Row({ label, value, children }: { label: string; value?: string; children: ReactNode }) {
  return (
    <View style={{ padding: space.md, gap: space.xs }}>
      <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
        <AppText weight="medium">{label}</AppText>
        {value ? (
          <AppText tone="muted" style={{ fontVariant: ['tabular-nums'] }}>
            {value}
          </AppText>
        ) : null}
      </View>
      {children}
    </View>
  );
}

function InlineRow({ label, hint, children }: { label: string; hint?: string; children: ReactNode }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: space.sm, paddingHorizontal: space.md, paddingVertical: space.sm, minHeight: 56 }}>
      <View style={{ flex: 1 }}>
        <AppText weight="medium">{label}</AppText>
        {hint ? (
          <AppText variant="caption" tone="muted">
            {hint}
          </AppText>
        ) : null}
      </View>
      {children}
    </View>
  );
}

function Hint({ children, tone = 'muted' }: { children: ReactNode; tone?: 'muted' | 'warning' }) {
  const { colors } = useTheme();
  return (
    <AppText variant="caption" tone="muted" style={tone === 'warning' ? { color: colors.warning } : undefined}>
      {children}
    </AppText>
  );
}

const styles = StyleSheet.create({
  group: { marginHorizontal: space.md, borderRadius: radius.xl, borderWidth: 1, overflow: 'hidden' },
  textArea: { minHeight: 88, borderWidth: 1, borderRadius: radius.md, padding: space.sm, fontSize: 15, textAlignVertical: 'top' },
  buttons: { flexDirection: 'row', gap: space.xs, padding: space.md, flexWrap: 'wrap' },
});
