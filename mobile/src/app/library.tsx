import { ArrowsClockwise } from 'phosphor-react-native';
import { useEffect, useState } from 'react';
import { View } from 'react-native';

import { ModelCard } from '@/components/library/ModelCard';
import { Screen } from '@/components/ui/Screen';
import { AppText, IconButton } from '@/components/ui/primitives';
import { toast } from '@/components/ui/Toast';
import { catalogue } from '@/core/catalogue';
import { currentNetwork, describeNetwork, onNetworkChange, type NetworkKind } from '@/core/services/connectivity';
import { files } from '@/core/services/files';
import { formatBytes } from '@/core/utils/formatters';
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

  useEffect(() => {
    void currentNetwork().then(setNet);
    void files.freeBytes().then(setFree);
    return onNetworkChange(setNet);
  }, []);

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
          <ModelCard key={m.id} model={m} index={i} />
        ))}
        <View style={{ padding: space.sm, borderRadius: radius.md, backgroundColor: colors.surfaceSoft }}>
          <AppText variant="caption" tone="muted">
            Tuned for {catalogue.targetDevice.name} ({catalogue.targetDevice.ramOptionsGb.join(' or ')} GB RAM). Sizes and checksums are
            exact values from HuggingFace, bundled with the app.
          </AppText>
        </View>
      </View>
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
