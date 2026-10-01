/**
 * Load preflight. A load that does not fit fails inside llama.cpp, where
 * Android kills the process instead of raising something catchable, so the
 * app refuses up front and says why. Pure functions; the /proc/meminfo read
 * lives in the platform file service.
 */
export const memoryHeadroom = 1.15;
export const kvBytesPer1024Tokens = 200 * 1024 * 1024;

export function parseMemAvailable(memInfo: string): number | null {
  for (const line of memInfo.split('\n')) {
    if (!line.startsWith('MemAvailable:')) continue;
    const fields = line.split(/\s+/);
    const kb = Number.parseInt(fields[1] ?? '', 10);
    return Number.isFinite(kb) ? kb * 1024 : null;
  }
  return null;
}

export function peakRequirementBytes(opts: {
  requirementGb: number;
  contextLength?: number;
  recommendedContextLength?: number;
  extraBytes?: number;
}): number {
  let bytes = Math.round(opts.requirementGb * 1e9) + (opts.extraBytes ?? 0);
  const ctx = opts.contextLength ?? 0;
  const rec = opts.recommendedContextLength ?? 0;
  const extraTokens = ctx - rec;
  if (rec > 0 && extraTokens > 0) bytes += Math.ceil(extraTokens / 1024) * kvBytesPer1024Tokens;
  return bytes;
}

export const fitsInMemory = (available: number, required: number) => available >= required * memoryHeadroom;
