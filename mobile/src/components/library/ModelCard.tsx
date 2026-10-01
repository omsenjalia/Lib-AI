import * as Linking from 'expo-linking';
import {
  ArrowSquareOut,
  ArrowsClockwise,
  CaretDown,
  CheckCircle,
  DownloadSimple,
  Pause,
  Play,
  Trash,
  Warning,
  WifiHigh,
  X,
} from 'phosphor-react-native';
import { memo, useEffect, useRef, useState } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import Animated, {
  FadeIn,
  FadeInDown,
  LinearTransition,
  useAnimatedStyle,
  useSharedValue,
  withTiming,
} from 'react-native-reanimated';

import { Shimmer } from '@/components/chat/Shimmer';
import { ConfirmSheet } from '@/components/ui/Screen';
import { AppText, Button, Chip, PressableScale, useHaptic } from '@/components/ui/primitives';
import { Toggle } from '@/components/ui/controls';
import { toast } from '@/components/ui/Toast';
import { recommendedQuantOf, totalDownloadBytes, type CatalogueModel, type QuantOption } from '@/core/catalogue';
import { AppError } from '@/core/errors';
import { files } from '@/core/services/files';
import { formatBytes, formatDuration, formatSpeed } from '@/core/utils/formatters';
import { useActiveModelId, useLibrary } from '@/state/library';
import { useTheme } from '@/theme/ThemeProvider';
import { motion, radius, space } from '@/theme/tokens';

/**
 * One catalogued model: what it is, whether it fits, which quantisation, and
 * the one action that matters right now (download, pause, resume, use,
 * update, delete). Sizes are exact byte counts from the catalogue.
 */
export const ModelCard = memo(function ModelCard({ model, index }: { model: CatalogueModel; index: number }) {
  const { colors } = useTheme();
  const install = useLibrary((s) => s.installations[model.id]);
  const task = useLibrary((s) => s.tasks.get(model.id));
  const update = useLibrary((s) => s.updates[model.id]);
  const activeId = useActiveModelId();
  const { download, pause, cancel, remove, setActive } = useLibrary.getState();
  const buzz = useHaptic();

  const [quant, setQuant] = useState<QuantOption>(() => model.quants.find((q) => q.quant === install?.quant) ?? recommendedQuantOf(model));
  const [vision, setVision] = useState(model.visionSupported && Boolean(model.mmproj));
  const [details, setDetails] = useState(false);
  const [confirm, setConfirm] = useState<'download' | 'delete' | 'discard' | null>(null);
  // The recommended quant is often mid-list; bring the selected chip into view.
  const quantScroll = useRef<ScrollView>(null);

  const total = totalDownloadBytes(model, quant, vision);
  const isActive = install && activeId === model.id;

  const start = async (q: QuantOption, includeMmproj: boolean) => {
    try {
      await download(model, q, includeMmproj);
      buzz('success');
    } catch (e) {
      const err = e instanceof AppError ? e : null;
      toast(err ? `${err.message} ${err.recovery ?? ''}`.trim() : 'The download could not start.', { ms: 5000 });
    }
  };

  return (
    <Animated.View
      entering={FadeInDown.delay(Math.min(index, 6) * 50).springify().damping(20)}
      layout={LinearTransition.duration(motion.base)}
      style={[styles.card, { backgroundColor: colors.surface, borderColor: isActive ? colors.primary : colors.hairline }]}
    >
      <View style={{ gap: 6 }}>
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: space.xs }}>
          <AppText serif variant="title" style={{ flex: 1 }}>
            {model.displayName}
          </AppText>
          {install ? <CheckCircle size={20} color={isActive ? colors.primary : colors.success} weight="fill" /> : null}
        </View>
        <View style={styles.chips}>
          <Chip label={model.parameterCount} />
          {model.visionSupported ? <Chip label="Vision" tone="accent" /> : <Chip label="Text only" />}
          {model.highRam ? <Chip label="High RAM" tone="warning" /> : null}
          {model.wifiOnly ? <Chip label="Wi-Fi only" tone="warning" /> : null}
          {!model.fitsTargetDevice ? <Chip label="Will not load on 8-12 GB phones" tone="error" /> : null}
          {isActive ? <Chip label="Active" tone="accent" /> : null}
          {update?.updateAvailable ? <Chip label="Update available" tone="accent" /> : null}
        </View>
        <AppText variant="bodySmall" tone="body">
          {model.blurb}
        </AppText>
      </View>

      {model.warning ? (
        <View style={[styles.warning, { backgroundColor: colors.errorWash }]}>
          <Warning size={18} color={colors.error} />
          <AppText variant="caption" style={{ flex: 1, color: colors.error }}>
            {model.warning}
          </AppText>
        </View>
      ) : null}

      {!install && !task ? (
        <View style={{ gap: space.xs }}>
          <AppText variant="caption" tone="muted" weight="medium">
            Quantisation
          </AppText>
          <ScrollView ref={quantScroll} horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 6 }}>
            {model.quants.map((q) => {
              const selected = q.quant === quant.quant;
              return (
                <PressableScale
                  key={q.quant}
                  onLayout={(e) => {
                    if (selected) quantScroll.current?.scrollTo({ x: Math.max(0, e.nativeEvent.layout.x - 24), animated: false });
                  }}
                  accessibilityRole="radio"
                  accessibilityState={{ selected }}
                  accessibilityLabel={`${q.quant}, ${formatBytes(q.sizeBytes)}`}
                  onPress={() => {
                    buzz('select');
                    setQuant(q);
                  }}
                  style={[
                    styles.quant,
                    {
                      borderColor: selected ? colors.ink : colors.hairline,
                      backgroundColor: selected ? colors.surfaceSoft : 'transparent',
                      opacity: q.fitsTargetDevice ? 1 : 0.6,
                    },
                  ]}
                >
                  <AppText variant="caption" weight="bold">
                    {q.quant}
                    {q.quant === model.recommendedQuant ? ' ★' : ''}
                  </AppText>
                  <AppText variant="micro" tone="muted">
                    {formatBytes(q.sizeBytes)}
                  </AppText>
                </PressableScale>
              );
            })}
          </ScrollView>
          {quant.qualityNote ? (
            <AppText variant="caption" tone="muted">
              {quant.qualityNote}
            </AppText>
          ) : null}
          {model.visionSupported && model.mmproj ? (
            <View style={styles.visionRow}>
              <View style={{ flex: 1 }}>
                <AppText variant="bodySmall" weight="medium">
                  Include vision projector
                </AppText>
                <AppText variant="caption" tone="muted">
                  {formatBytes(model.mmproj.sizeBytes)} more. Needed to attach images.
                </AppText>
              </View>
              <Toggle value={vision} onChange={setVision} label="Include vision projector" />
            </View>
          ) : null}
        </View>
      ) : null}

      {task ? (
        <TaskPanel
          phase={task.phase}
          received={task.received}
          total={task.total}
          speed={task.bytesPerSecond}
          eta={task.etaMs}
          fileIndex={task.fileIndex}
          fileCount={task.fileCount}
          error={task.error}
          onPause={() => pause(model.id)}
          onResume={() => {
            const q = model.quants.find((x) => x.quant === task.quant) ?? quant;
            void start(q, task.includeMmproj);
          }}
          onDiscard={() => setConfirm('discard')}
        />
      ) : install ? (
        <View style={styles.actions}>
          {isActive ? (
            <View style={[styles.activePill, { backgroundColor: colors.primaryWash }]}>
              <AppText variant="bodySmall" weight="medium" tone="primary">
                In use for new messages
              </AppText>
            </View>
          ) : (
            <Button label="Use this model" onPress={() => void setActive(model.id)} compact />
          )}
          {update?.updateAvailable ? (
            <Button
              label="Update"
              icon={ArrowsClockwise}
              variant="tonal"
              compact
              onPress={() => void start(model.quants.find((q) => q.quant === install.quant) ?? quant, Boolean(install.mmprojPath))}
            />
          ) : null}
          <Button label="Delete" icon={Trash} variant="danger" compact onPress={() => setConfirm('delete')} />
        </View>
      ) : (
        <Button
          label={files.supportsModels ? `Download ${formatBytes(total)}` : 'Downloads need the Android app'}
          icon={model.wifiOnly ? WifiHigh : DownloadSimple}
          disabled={!files.supportsModels}
          onPress={() => setConfirm('download')}
        />
      )}

      {install ? (
        <AppText variant="caption" tone="muted">
          {install.quant}, {formatBytes(install.totalBytes)} on this phone
          {install.mmprojPath ? ', with vision' : ''}
        </AppText>
      ) : null}

      <PressableScale
        accessibilityRole="button"
        accessibilityState={{ expanded: details }}
        onPress={() => setDetails((d) => !d)}
        style={styles.detailsToggle}
      >
        <AppText variant="caption" tone="muted" weight="medium">
          {details ? 'Hide details' : 'Details'}
        </AppText>
        <CaretDown size={12} color={colors.muted} style={{ transform: [{ rotate: details ? '180deg' : '0deg' }] }} />
      </PressableScale>
      {details ? (
        <Animated.View entering={FadeIn.duration(motion.base)} style={{ gap: 6 }}>
          <Detail label="RAM needed" value={`about ${model.ramRequirementGb} GB`} />
          <Detail label="Context" value={`${model.recommendedContextLength.toLocaleString()} recommended, ${model.maxContextLength.toLocaleString()} max`} />
          {model.contextNote ? <AppText variant="caption" tone="muted">{model.contextNote}</AppText> : null}
          {model.visionEvidence ? <Detail label="Vision" value={model.visionEvidence} /> : null}
          {model.visionCaveat ? <Detail label="Caveat" value={model.visionCaveat} /> : null}
          {model.visionAbsenceNote ? <Detail label="Text only" value={model.visionAbsenceNote} /> : null}
          {model.notes ? <Detail label="Notes" value={model.notes} /> : null}
          <Detail label="Sampling" value={`temperature ${model.samplingDefaults.temperature}, top-p ${model.samplingDefaults.topP}, top-k ${model.samplingDefaults.topK}`} />
          <PressableScale accessibilityRole="link" onPress={() => void Linking.openURL(model.ggufRepoUrl)} style={{ flexDirection: 'row', gap: 4, alignItems: 'center' }}>
            <AppText variant="caption" tone="primary">
              {model.ggufRepoId}
            </AppText>
            <ArrowSquareOut size={12} color={colors.primary} />
          </PressableScale>
        </Animated.View>
      ) : null}

      <ConfirmSheet
        visible={confirm === 'download'}
        title={`Download ${model.displayName}?`}
        confirmLabel={`Download ${formatBytes(total)}`}
        onConfirm={() => void start(quant, vision)}
        onClose={() => setConfirm(null)}
      >
        <View style={{ gap: 6 }}>
          <Detail label="Quantisation" value={quant.quant} />
          <Detail label="Size" value={formatBytes(total)} />
          <FreeSpace />
          <AppText variant="caption" tone="muted">
            {model.wifiOnly
              ? 'This model downloads over Wi-Fi only. The block is deliberate and is not a setting.'
              : 'Large download. Wi-Fi is recommended. You can pause and resume, and progress shows in your notifications.'}
          </AppText>
          {!quant.fitsTargetDevice ? (
            <AppText variant="caption" tone="error">
              This quantisation is larger than a typical phone can load. Expect an out-of-memory error.
            </AppText>
          ) : null}
        </View>
      </ConfirmSheet>
      <ConfirmSheet
        visible={confirm === 'delete'}
        title={`Delete ${model.displayName}?`}
        body={install ? `Frees ${formatBytes(install.totalBytes)}. Your conversations are kept.` : undefined}
        confirmLabel="Delete model"
        danger
        onConfirm={() => void remove(model)}
        onClose={() => setConfirm(null)}
      />
      <ConfirmSheet
        visible={confirm === 'discard'}
        title="Discard this download?"
        body="The bytes downloaded so far are deleted. Starting again begins from zero."
        confirmLabel="Discard"
        danger
        onConfirm={() => void cancel(model)}
        onClose={() => setConfirm(null)}
      />
    </Animated.View>
  );
});

function TaskPanel(props: {
  phase: string;
  received: number;
  total: number;
  speed: number;
  eta: number;
  fileIndex: number;
  fileCount: number;
  error: AppError | null;
  onPause: () => void;
  onResume: () => void;
  onDiscard: () => void;
}) {
  const { colors } = useTheme();
  const frac = props.total > 0 ? props.received / props.total : 0;
  const w = useSharedValue(frac);
  useEffect(() => {
    w.set(withTiming(frac, { duration: 300 }));
  }, [frac, w]);
  const bar = useAnimatedStyle(() => ({ transform: [{ scaleX: Math.max(0.005, w.value) }] }));
  const downloading = props.phase === 'downloading';
  return (
    <View style={{ gap: space.xs }}>
      <View style={[styles.track, { backgroundColor: colors.hairline }]}>
        <Animated.View style={[styles.fill, { backgroundColor: props.phase === 'failed' ? colors.error : colors.primary }, bar]} />
      </View>
      {props.phase === 'verifying' ? (
        <Shimmer>
          <AppText variant="caption" weight="medium">
            Verifying checksum
          </AppText>
        </Shimmer>
      ) : (
        <AppText variant="caption" tone="muted" style={{ fontVariant: ['tabular-nums'] }}>
          {Math.floor(frac * 100)}%, {formatBytes(props.received)} of {formatBytes(props.total)}
          {downloading ? `. ${formatSpeed(props.speed)}, ${formatDuration(props.eta)} left` : props.phase === 'paused' ? '. Paused' : ''}
          {props.fileCount > 1 ? `. File ${props.fileIndex + 1} of ${props.fileCount}` : ''}
        </AppText>
      )}
      {props.error ? (
        <AppText variant="caption" tone="error">
          {props.error.message} {props.error.recovery ?? ''}
        </AppText>
      ) : null}
      <View style={styles.actions}>
        {downloading ? (
          <Button label="Pause" icon={Pause} variant="tonal" compact onPress={props.onPause} />
        ) : props.phase === 'paused' || props.phase === 'failed' ? (
          <Button label="Resume" icon={Play} compact onPress={props.onResume} />
        ) : null}
        {props.phase !== 'verifying' ? <Button label="Discard" icon={X} variant="ghost" compact onPress={props.onDiscard} /> : null}
      </View>
    </View>
  );
}

function FreeSpace() {
  const [free, setFree] = useState<number | null>(null);
  useEffect(() => {
    void files.freeBytes().then(setFree);
  }, []);
  return free === null ? null : <Detail label="Free on this phone" value={formatBytes(free)} />;
}

function Detail({ label, value }: { label: string; value: string }) {
  return (
    <View style={{ flexDirection: 'row', gap: space.xs }}>
      <AppText variant="caption" tone="muted" style={{ width: 96 }}>
        {label}
      </AppText>
      <AppText variant="caption" tone="body" style={{ flex: 1 }} selectable>
        {value}
      </AppText>
    </View>
  );
}

const styles = StyleSheet.create({
  card: { borderRadius: radius.xl, borderWidth: 1, padding: space.md, gap: space.sm },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: 6 },
  warning: { flexDirection: 'row', gap: space.xs, padding: space.sm, borderRadius: radius.md },
  quant: { borderWidth: 1, borderRadius: radius.md, paddingHorizontal: 10, paddingVertical: 6, minWidth: 82 },
  visionRow: { flexDirection: 'row', alignItems: 'center', gap: space.sm, paddingTop: 4 },
  actions: { flexDirection: 'row', flexWrap: 'wrap', gap: space.xs, alignItems: 'center' },
  activePill: { paddingHorizontal: space.sm, paddingVertical: 8, borderRadius: radius.md },
  track: { height: 6, borderRadius: 3, overflow: 'hidden' },
  fill: { height: 6, width: '100%', transformOrigin: 'left' },
  detailsToggle: { flexDirection: 'row', alignItems: 'center', gap: 4, alignSelf: 'flex-start', paddingVertical: 2 },
});
