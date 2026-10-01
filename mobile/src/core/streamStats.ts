/**
 * Numbers behind the Claude Code-style token readout. Pure, so it is tested
 * without a device.
 */
export type StreamStats = {
  /** When the request went to the engine (prompt processing starts here). */
  startedAt: number;
  /** When the first token arrived; tokens/s is measured from here. */
  firstTokenAt: number | null;
  /** Output tokens so far: one per streamed piece, as llama.cpp emits them. */
  tokens: number;
  /** Prompt size estimate, shown as ↑ until the engine reports the real count. */
  promptTokens: number;
};

/** Live decode speed: tokens since the first one, over the time since it. */
export function liveTokensPerSecond(s: StreamStats, now: number): number | null {
  if (s.firstTokenAt === null || s.tokens < 2) return null;
  const secs = (now - s.firstTokenAt) / 1000;
  return secs > 0 ? (s.tokens - 1) / secs : null;
}
