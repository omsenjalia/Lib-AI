import { catalogue } from '../src/core/catalogue';
import type { ModelInstallation, UpdateCheck } from '../src/core/db/types';
import { checkForUpdates, hasChanged, type UpdateDeps } from '../src/core/services/updateChecker';

const model = catalogue.models.find((m) => !m.wifiOnly)!;
// No shipped model is Wi-Fi only any more, but the gate still exists, so it is
// tested against a fixture built from a real entry.
const big = { ...catalogue.models.find((m) => m.id !== model.id)!, id: 'wifi-only-fixture', wifiOnly: true };
const models = [...catalogue.models, big];

const install = (modelId: string, over: Partial<ModelInstallation> = {}): ModelInstallation => ({
  modelId,
  quant: 'Q4_K_M',
  fileName: 'model.gguf',
  localPath: '/x',
  mmprojPath: null,
  sizeBytes: 1,
  sha256: 'aaa',
  repoSha: 'r1',
  totalBytes: 1,
  downloadedAt: 0,
  ...over,
});

function deps(over: Partial<UpdateDeps> & { saved?: UpdateCheck[]; fetched?: string[] }): UpdateDeps {
  const saved = over.saved ?? [];
  const fetched = over.fetched ?? [];
  return {
    network: async () => 'unmetered',
    installations: async () => [install(model.id), install(big.id)],
    checks: async () => [],
    save: async (c) => void saved.push(c),
    fetchRepo: async (id) => {
      fetched.push(id);
      return { sha: 'r2', fileOids: { 'model.gguf': 'bbb' } };
    },
    now: () => 10 * 86_400_000,
    ...over,
  };
}

describe('hasChanged', () => {
  it('compares the per-file LFS oid with the stored SHA-256', () => {
    expect(hasChanged(install('m'), { sha: 'r1', fileOids: { 'model.gguf': 'AAA' } })).toBe(false);
    expect(hasChanged(install('m'), { sha: 'r1', fileOids: { 'model.gguf': 'bbb' } })).toBe(true);
  });
  it('falls back to the repo commit without per-file data', () => {
    expect(hasChanged(install('m'), { sha: 'r2', fileOids: {} })).toBe(true);
    expect(hasChanged(install('m'), { sha: 'r1', fileOids: {} })).toBe(false);
  });
});

describe('checkForUpdates', () => {
  it('does nothing offline', async () => {
    const fetched: string[] = [];
    await checkForUpdates(models, deps({ network: async () => 'offline', fetched }));
    expect(fetched).toEqual([]);
  });
  it('never polls a Wi-Fi-only model on mobile data', async () => {
    const fetched: string[] = [];
    await checkForUpdates(models, deps({ network: async () => 'metered', fetched }));
    expect(fetched).toEqual([model.ggufRepoId]);
  });
  it('respects the 24-hour throttle unless forced', async () => {
    const fetched: string[] = [];
    const recent = [{ modelId: model.id, lastCheckedAt: 10 * 86_400_000 - 1000, remoteSha: null, updateAvailable: false }];
    await checkForUpdates(models, deps({ checks: async () => recent, fetched }));
    expect(fetched).not.toContain(model.ggufRepoId);
    await checkForUpdates(models, deps({ checks: async () => recent, fetched }), true);
    expect(fetched).toContain(model.ggufRepoId);
  });
  it('records an available update as a flag only', async () => {
    const saved: UpdateCheck[] = [];
    await checkForUpdates(models, deps({ saved }));
    expect(saved.find((s) => s.modelId === model.id)?.updateAvailable).toBe(true);
  });
});
