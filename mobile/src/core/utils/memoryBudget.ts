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

/**
 * What the library says about loading a model right now. `available` should
 * already include memory the resident model would give back on a switch.
 */
export type LoadFit = { kind: 'resident' } | { kind: 'fits' } | { kind: 'short'; required: number; available: number };

export function loadFit(opts: { required: number; available: number; resident: boolean }): LoadFit {
  if (opts.resident) return { kind: 'resident' };
  return fitsInMemory(opts.available, opts.required)
    ? { kind: 'fits' }
    : { kind: 'short', required: Math.ceil(opts.required * memoryHeadroom), available: opts.available };
}
