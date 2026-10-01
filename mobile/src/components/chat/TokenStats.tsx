import { useEffect, useState } from 'react';
import { View } from 'react-native';
import { useReducedMotion } from 'react-native-reanimated';

import { AppText } from '@/components/ui/primitives';
import type { Message } from '@/core/db/types';
import { formatElapsed, formatTokenCount, formatTokensPerSecond } from '@/core/utils/formatters';
import { liveTokensPerSecond } from '@/core/streamStats';
import { useChat } from '@/state/chat';
import { useTheme } from '@/theme/ThemeProvider';
import { space } from '@/theme/tokens';

/**
 * Token readouts in the style of Claude Code's terminal status line:
 *
 *   ✻ Writing… (4.2s · ↓ 312 tokens · 41.2 tok/s)      while streaming
 *   ↑ 1.2k · ↓ 312 tokens · 41.2 tok/s · 7.9s           under every finished reply
 *
 * ↑ is what the model read (the whole prompt), ↓ is what it wrote. Speed is
 * decode speed: tokens after the first one, over the time since the first one,
 * so prompt processing does not drag the number down. Monospace, like the
 * terminal it imitates.
 */
const spinner = ['·', '✢', '✳', '✶', '✻', '✽', '✻', '✶', '✳', '✢'];

export function StreamStatus({ thinking }: { thinking: boolean }) {
  const { colors } = useTheme();
  const stats = useChat((s) => s.streamStats);
  const reduce = useReducedMotion();
  const [now, setNow] = useState(() => Date.now());
  const [frame, setFrame] = useState(0);

  useEffect(() => {
    const t = setInterval(() => {
      setNow(Date.now());
      setFrame((f) => (f + 1) % spinner.length);
    }, 120);
    return () => clearInterval(t);
  }, []);

  if (!stats) return null;
  const tps = liveTokensPerSecond(stats, now);
  const verb = stats.firstTokenAt === null ? 'Reading prompt' : thinking ? 'Thinking' : 'Writing';
  const parts = [
    formatElapsed(now - stats.startedAt),
    stats.firstTokenAt === null ? `↑ ${formatTokenCount(stats.promptTokens)} tokens` : `↓ ${formatTokenCount(stats.tokens)} tokens`,
    ...(tps !== null ? [formatTokensPerSecond(tps)] : []),
  ];
  return (
    <View
      style={{ flexDirection: 'row', alignItems: 'center', gap: space.xs, flexWrap: 'wrap' }}
      accessibilityLiveRegion="polite"
      accessibilityLabel={`${verb}. ${parts.join(', ')}`}
    >
      <AppText mono variant="bodySmall" style={{ color: colors.primary, width: 14, textAlign: 'center' }}>
        {reduce ? '✻' : spinner[frame]}
      </AppText>
      <AppText mono variant="caption" style={{ color: colors.primary }}>
        {verb}…
      </AppText>
      <AppText mono variant="caption" tone="mutedSoft" style={{ fontVariant: ['tabular-nums'] }}>
        ({parts.join(' · ')})
      </AppText>
    </View>
  );
}

export function ResponseStats({ message }: { message: Message }) {
  if (message.tokenCount === null && message.tokensPerSecond === null) return null;
  const parts: string[] = [];
  if (message.promptTokens !== null) parts.push(`↑ ${formatTokenCount(message.promptTokens)}`);
  if (message.tokenCount !== null) parts.push(`↓ ${message.isEstimatedTokens ? '~' : ''}${formatTokenCount(message.tokenCount)} tokens`);
  if (message.tokensPerSecond !== null) parts.push(formatTokensPerSecond(message.tokensPerSecond));
  if (message.generationMs !== null) parts.push(formatElapsed(message.generationMs));
  return (
    <AppText
      mono
      variant="micro"
      tone="mutedSoft"
      style={{ fontVariant: ['tabular-nums'] }}
      accessibilityLabel={`Read ${message.promptTokens ?? 'unknown'} tokens, wrote ${message.tokenCount ?? 'unknown'} tokens${
        message.tokensPerSecond ? ` at ${message.tokensPerSecond.toFixed(1)} tokens per second` : ''
      }`}
    >
      {parts.join(' · ')}
    </AppText>
  );
}
