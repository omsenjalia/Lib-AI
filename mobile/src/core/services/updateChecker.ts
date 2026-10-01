import { AppConstants } from '../constants';
import type { CatalogueModel } from '../catalogue';
import type { ModelInstallation, UpdateCheck } from '../db/types';
import type { NetworkKind } from './connectivity';

/**
 * Checks whether a downloaded model's file has changed upstream.
 *
 * A check can only ever produce a badge. This module holds no reference to the
 * download manager, which is the structural guarantee that an available update
 * never starts a transfer. Offline is a silent skip; a Wi-Fi-only model is
 * never polled on mobile data; each model is checked at most once per 24 h.
 */
export type RemoteRepoState = { sha: string | null; fileOids: Record<string, string> };

export async function fetchRepoState(repoId: string, fetchImpl: typeof fetch = fetch): Promise<RemoteRepoState> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), AppConstants.metadataTimeoutMs);
  try {
    const res = await fetchImpl(`${AppConstants.huggingFaceApiBase}/${repoId}?blobs=true`, {
      headers: { 'User-Agent': 'LibraryAI/2.0 (+offline-first study app)' },
      signal: controller.signal,
    });
    if (!res.ok) throw new Error(`HuggingFace returned HTTP ${res.status}`);
    const data = (await res.json()) as { sha?: string; siblings?: { rfilename?: string; blobId?: string; lfs?: { oid?: string } }[] };
    const fileOids: Record<string, string> = {};
    for (const s of data.siblings ?? []) {
      if (!s.rfilename) continue;
      // For LFS files the oid IS the SHA-256 of the content: the value stored at install.
      const oid = s.lfs?.oid ?? s.blobId;
      if (oid) fileOids[s.rfilename] = oid;
    }
    return { sha: data.sha ?? null, fileOids };
  } finally {
    clearTimeout(timer);
  }
}

export function hasChanged(install: ModelInstallation, remote: RemoteRepoState): boolean {
  const remoteOid = remote.fileOids[install.fileName];
  if (remoteOid && install.sha256) return remoteOid.toLowerCase() !== install.sha256.toLowerCase();
  // No per-file data: fall back to the repository commit.
  return Boolean(remote.sha && install.repoSha && remote.sha !== install.repoSha);
}

export type UpdateDeps = {
  network(): Promise<NetworkKind>;
  installations(): Promise<ModelInstallation[]>;
  checks(): Promise<UpdateCheck[]>;
  save(check: UpdateCheck): Promise<void>;
  fetchRepo(repoId: string): Promise<RemoteRepoState>;
  now?: () => number;
};

export async function checkForUpdates(models: CatalogueModel[], deps: UpdateDeps, force = false): Promise<void> {
  const now = deps.now ?? Date.now;
  const net = await deps.network();
  if (net === 'offline') return;
  const installs = await deps.installations();
  const checks = new Map((await deps.checks()).map((c) => [c.modelId, c]));
  for (const install of installs) {
    const model = models.find((m) => m.id === install.modelId);
    if (!model) continue;
    if (model.wifiOnly && net !== 'unmetered') continue;
    const last = checks.get(model.id);
    if (!force && last && now() - last.lastCheckedAt < AppConstants.updateCheckThrottleMs) continue;
    try {
      const remote = await deps.fetchRepo(model.ggufRepoId);
      await deps.save({
        modelId: model.id,
        lastCheckedAt: now(),
        remoteSha: remote.sha,
        updateAvailable: hasChanged(install, remote),
      });
    } catch {
      // A metadata call failing is not worth interrupting study for.
    }
  }
}
