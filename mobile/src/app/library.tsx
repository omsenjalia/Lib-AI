import { ArrowsClockwise, Trash } from 'phosphor-react-native';
import { useEffect, useState } from 'react';
import { View } from 'react-native';

import { ModelCard, type MemorySnapshot } from '@/components/library/ModelCard';
import { ConfirmSheet, Screen } from '@/components/ui/Screen';
import { AppText, Button, IconButton, SectionLabel } from '@/components/ui/primitives';
import { toast } from '@/components/ui/Toast';
import { catalogue, installedRequirementGb, modelById, orphanedInstallations } from '@/core/catalogue';
import type { ModelInstallation } from '@/core/db/types';
import { currentNetwork, describeNetwork, onNetworkChange, type NetworkKind } from '@/core/services/connectivity';
import { files } from '@/core/services/files';
import { formatBytes } from '@/core/utils/formatters';
import { useEngineStatus } from '@/state/engineStatus';
import { useLibrary } from '@/state/library';
import { useTheme } from '@/theme/ThemeProvider';
import { radius, space } from '@/theme/tokens';

export default function LibraryScreen() {
  const { colors } = useTheme();
  const installations = useLibrary((s) => s.installations);
  const checking = useLibrary((s) => s.checkingUpdates);
  const checkUpdates = useLibrary((s) => s.checkUpdates);
  const [net, setNet] = useState<NetworkKind | null>(null);
  const [free, setFree] = useState<number | null>(null);
  const [memory, setMemory] = useState<MemorySnapshot>(null);
  const [deleting, setDeleting] = useState<ModelInstallation | null>(null);
  const remove = useLibrary((s) => s.remove);
  const residentId = useEngineStatus((s) => (s.stage === 'ready' ? s.modelId : null));

  useEffect(() => {
    void currentNetwork().then(setNet);
    void files.freeBytes().then(setFree);
    return onNetworkChange(setNet);
  }, []);

  // Re-read whenever the resident model changes: loading or releasing one moves
  // MemAvailable by gigabytes.
  useEffect(() => {
    let live = true;
    void files.memAvailableBytes().then((available) => {
      if (!live) return;
      if (available === null) return setMemory(null);
      // A switch releases the resident model first, so its memory counts as free.
      const resident = modelById(residentId);
      const releasing = resident ? Math.round(installedRequirementGb(resident, installations[resident.id]) * 1e9) : 0;
      setMemory({ available: available + releasing, residentId });
    });
    return () => {
      live = false;
    };
  }, [residentId, installations]);

  const orphans = orphanedInstallations(
    installations,
    catalogue.models.map((m) => m.id),
  );
  const used = Object.values(installations).reduce((t, i) => t + i.totalBytes, 0);
  // Models that fit first, then the rest, keeping catalogue order within each.
  const models = [...catalogue.models].sort((a, b) => Number(b.fitsTargetDevice) - Number(a.fitsTargetDevice));

  return (
    <Screen
      title="Model Library"
      trailing={
        files.supportsModels ? (
          <IconButton
            icon={ArrowsClockwise}
            label="Check for updates"
            disabled={checking || net === 'offline'}
            onPress={async () => {
              await checkUpdates(true);
              toast('Update check finished.');
            }}
          />
        ) : null
      }
    >
      <View style={{ padding: space.md, gap: space.md }}>
        <View style={{ flexDirection: 'row', gap: space.xs }}>
          <Stat label="Models on phone" value={formatBytes(used)} />
          <Stat label="Free space" value={free === null ? '--' : formatBytes(free)} />
          <Stat label="Network" value={net ? describeNetwork(net) : '--'} tone={net === 'offline' ? 'muted' : 'ink'} />
        </View>
        <AppText variant="caption" tone="muted" style={{ paddingHorizontal: 2 }}>
          The network is used only to download a model you choose and to check whether it changed upstream. Chats never leave
          the phone.
        </AppText>
        {models.map((m, i) => (
          <ModelCard key={m.id} model={m} index={i} memory={memory} />
        ))}
        {orphans.length > 0 ? (
          <View style={{ gap: space.xs }}>
            <SectionLabel>Other downloads</SectionLabel>
            <AppText variant="caption" tone="muted" style={{ paddingHorizontal: 2 }}>
              These models are no longer in the library, so the app cannot load them. Delete them to free the space.
            </AppText>
            {orphans.map((o) => (
              <View
                key={o.modelId}
                style={{
                  flexDirection: 'row',
                  alignItems: 'center',
                  gap: space.sm,
                  padding: space.sm,
                  borderRadius: radius.lg,
                  backgroundColor: colors.surface,
                  borderWidth: 1,
                  borderColor: colors.hairline,
                }}
              >
                <View style={{ flex: 1, gap: 2 }}>
                  <AppText variant="bodySmall" weight="medium" numberOfLines={1}>
                    {o.modelId}
                  </AppText>
                  <AppText variant="caption" tone="muted">
                    {o.quant}, {formatBytes(o.totalBytes)}
                  </AppText>
                </View>
                <Button label="Delete" icon={Trash} variant="danger" compact onPress={() => setDeleting(o)} />
              </View>
            ))}
          </View>
        ) : null}
        <View style={{ padding: space.sm, borderRadius: radius.md, backgroundColor: colors.surfaceSoft }}>
          <AppText variant="caption" tone="muted">
            Tuned for {catalogue.targetDevice.name} ({catalogue.targetDevice.ramOptionsGb.join(' or ')} GB RAM). Sizes and checksums are
            exact values from HuggingFace, bundled with the app.
          </AppText>
        </View>
      </View>
      <ConfirmSheet
        visible={deleting !== null}
        title={`Delete ${deleting?.modelId ?? 'this model'}?`}
        body={deleting ? `Frees ${formatBytes(deleting.totalBytes)}. Your conversations are kept.` : undefined}
        confirmLabel="Delete model"
        danger
        onConfirm={() => {
          if (deleting) void remove(deleting.modelId).then(() => toast('Model deleted.'));
        }}
        onClose={() => setDeleting(null)}
      />
    </Screen>
  );
}

function Stat({ label, value, tone = 'ink' }: { label: string; value: string; tone?: 'ink' | 'muted' }) {
  const { colors } = useTheme();
  return (
    <View style={{ flex: 1, padding: space.sm, borderRadius: radius.lg, backgroundColor: colors.surface, borderWidth: 1, borderColor: colors.hairline, gap: 2 }}>
      <AppText variant="micro" tone="muted">
        {label}
      </AppText>
      <AppText variant="bodySmall" weight="bold" tone={tone} numberOfLines={1} style={{ fontVariant: ['tabular-nums'] }}>
        {value}
      </AppText>
    </View>
  );
}
