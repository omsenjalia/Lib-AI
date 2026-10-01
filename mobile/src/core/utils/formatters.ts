/** Decimal units, matching how HuggingFace and the catalogue report sizes. */
export function formatBytes(bytes: number, decimals = 2): string {
  if (!Number.isFinite(bytes) || bytes < 0) return '0 B';
  if (bytes < 1000) return `${Math.round(bytes)} B`;
  const units = ['KB', 'MB', 'GB', 'TB'];
  let value = bytes / 1000;
  let unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  const places = value >= 100 ? 1 : decimals;
  return `${value.toFixed(places)} ${units[unit]}`;
}

/** Token counts the way Claude Code prints them: 203, 1.2k, 12.4k, 1.1M. */
export function formatTokenCount(n: number): string {
  if (!Number.isFinite(n) || n < 0) return '0';
  if (n < 1000) return String(Math.round(n));
  if (n < 1_000_000) return `${(n / 1000).toFixed(n < 10_000 ? 1 : 0).replace(/\.0$/, '')}k`;
  return `${(n / 1_000_000).toFixed(1).replace(/\.0$/, '')}M`;
}

/** "41.2 tok/s"; one decimal under 100, whole numbers above. */
export function formatTokensPerSecond(tps: number): string {
  if (!Number.isFinite(tps) || tps <= 0) return '-- tok/s';
  return `${tps < 100 ? tps.toFixed(1) : Math.round(tps)} tok/s`;
}

/** Elapsed time like Claude Code: 4.9s under a minute, then 1m 05s. */
export function formatElapsed(ms: number): string {
  if (ms < 60_000) return `${(Math.max(0, ms) / 1000).toFixed(ms < 10_000 ? 1 : 0)}s`;
  const s = Math.round(ms / 1000);
  return `${Math.floor(s / 60)}m ${String(s % 60).padStart(2, '0')}s`;
}

export function formatSpeed(bytesPerSecond: number): string {
  if (bytesPerSecond <= 0) return '--';
  return `${formatBytes(Math.round(bytesPerSecond))}/s`;
}

export function formatDuration(ms: number): string {
  const s = Math.floor(ms / 1000);
  if (s <= 0) return '--';
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  if (m < 60) {
    const rem = s % 60;
    return rem === 0 ? `${m}m` : `${m}m ${rem}s`;
  }
  const h = Math.floor(m / 60);
  const remM = m % 60;
  return remM === 0 ? `${h}h` : `${h}h ${remM}m`;
}

const pad2 = (v: number) => String(v).padStart(2, '0');

function startOfDay(t: number): number {
  const d = new Date(t);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
}

export function formatRelativeTime(time: number, now: number = Date.now()): string {
  const diff = now - time;
  if (diff < 45_000) return 'just now';
  const minutes = Math.floor(diff / 60_000);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(diff / 3_600_000);
  if (hours < 24) return `${hours}h ago`;
  const dayDiff = Math.round((startOfDay(now) - startOfDay(time)) / 86_400_000);
  if (dayDiff === 1) return 'Yesterday';
  if (dayDiff < 7) return `${dayDiff}d ago`;
  const d = new Date(time);
  return `${pad2(d.getDate())}/${pad2(d.getMonth() + 1)}/${d.getFullYear()}`;
}

export function formatAbsoluteTime(time: number): string {
  const d = new Date(time);
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} ${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

export function slugify(input: string, maxLength = 60): string {
  const cleaned = input
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  if (!cleaned) return 'untitled';
  return cleaned.length <= maxLength ? cleaned : cleaned.slice(0, maxLength);
}

/** A conversation title from its first message: whole words, about 48 characters. */
export function autoTitleFromMessage(message: string, maxLength = 48): string {
  const flat = message.replace(/\s+/g, ' ').trim();
  if (!flat) return 'New chat';
  if (flat.length <= maxLength) return flat;
  const cut = flat.slice(0, maxLength);
  const lastSpace = cut.lastIndexOf(' ');
  const trimmed = lastSpace > maxLength * 0.5 ? cut.slice(0, lastSpace) : cut;
  return `${trimmed.trimEnd()}...`;
}

export type RecencyGroup = 'Today' | 'Yesterday' | 'Previous 7 days' | 'Previous 30 days' | 'Older';

export function recencyGroup(time: number, now: number = Date.now()): RecencyGroup {
  const days = Math.round((startOfDay(now) - startOfDay(time)) / 86_400_000);
  if (days <= 0) return 'Today';
  if (days === 1) return 'Yesterday';
  if (days < 7) return 'Previous 7 days';
  if (days < 30) return 'Previous 30 days';
  return 'Older';
}

/** "Good morning" and friends, for the home greeting. */
export function greetingFor(date: Date = new Date()): string {
  const h = date.getHours();
  if (h < 5) return 'Up late studying?';
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}
