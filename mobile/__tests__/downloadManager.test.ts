import type { CatalogueModel } from '../src/core/catalogue';
import { catalogue } from '../src/core/catalogue';
import type { ModelInstallation } from '../src/core/db/types';
import type { NetworkKind } from '../src/core/services/connectivity';
import { DownloadManager, type DownloadTask } from '../src/core/services/downloadManager';
import type { DownloadRequest, FileService } from '../src/core/services/fileTypes';

/**
 * An in-memory disk. A file is its byte count plus the "content hash" the fake
 * server stamped on it, which is enough to exercise resume, append and
 * checksum behaviour without real gigabytes.
 */
type Server = (req: DownloadRequest) => { status: number; bytes: number; hash: string; fail?: boolean };

function fakeFs(server: Server, opts: { free?: number } = {}) {
  const disk = new Map<string, { size: number; hash: string }>();
  const requests: DownloadRequest[] = [];
  let pending: (() => void) | null = null;
  const fs: FileService = {
    supportsModels: true,
    filesDir: () => '/f',
    modelDir: (id) => `/f/models/${id}`,
    attachmentsDir: () => '/f/a',
    exportsDir: () => '/f/e',
    cacheDir: () => '/f/c',
    exists: async (p) => disk.has(p),
    size: async (p) => disk.get(p)?.size ?? 0,
    mkdirp: async () => undefined,
    unlink: async (p) => void disk.delete(p),
    move: async (a, b) => {
      disk.set(b, disk.get(a)!);
      disk.delete(a);
    },
    copy: async () => undefined,
    writeText: async () => undefined,
    sha256: async (p) => disk.get(p)!.hash,
    freeBytes: async () => opts.free ?? 1e12,
    memAvailableBytes: async () => null,
    partialBytes: async () => 0,
    deletePartials: async () => 0,
    toUri: (p) => p,
    download(req) {
      requests.push(req);
      const r = server(req);
      let cancelled = false;
      const done = new Promise<{ status: number; headers: Record<string, string> }>((resolve, reject) => {
        const finish = () => {
          if (cancelled) return reject(new Error('cancelled'));
          if (r.fail) {
            const prev = disk.get(req.path)?.size ?? 0;
            disk.set(req.path, { size: (req.append ? prev : 0) + Math.floor(r.bytes / 2), hash: 'partial' });
            return reject(new Error('socket closed'));
          }
          const prev = req.append ? disk.get(req.path)?.size ?? 0 : 0;
          disk.set(req.path, { size: prev + r.bytes, hash: r.hash });
          req.onProgress(r.bytes, r.bytes);
          resolve({ status: r.status, headers: {} });
        };
        pending = finish;
        setTimeout(() => pending === finish && finish(), 0);
      });
      return {
        done,
        cancel: () => {
          cancelled = true;
          pending?.();
        },
      };
    },
  };
  return { fs, disk, requests };
}

const textModel = catalogue.models.find((m) => !m.mmproj && !m.wifiOnly)!;
const quant = textModel.quants.find((q) => q.quant === textModel.recommendedQuant)!;
// No shipped model is Wi-Fi only any more; the gate is tested on a fixture.
const bigModel = { ...catalogue.models[0], id: 'wifi-only-fixture', wifiOnly: true };

function manager(fs: FileService, network: NetworkKind = 'unmetered') {
  const saved: ModelInstallation[] = [];
  const results: string[] = [];
  const m = new DownloadManager({
    files: fs,
    network: async () => network,
    saveInstallation: async (i) => void saved.push(i),
    notify: {
      permission: async () => true,
      progress: () => undefined,
      result: (_id, title) => void results.push(title),
      clear: () => undefined,
    },
  });
  return { m, saved, results };
}

async function settle(m: DownloadManager, id: string): Promise<DownloadTask | undefined> {
  for (let i = 0; i < 50; i++) {
    await new Promise((r) => setTimeout(r, 1));
    const t = m.get(id);
    if (!t || t.phase === 'failed' || t.phase === 'paused') return t;
  }
  return m.get(id);
}

describe('DownloadManager', () => {
  it('installs only after the checksum matches', async () => {
    const { fs, disk } = fakeFs(() => ({ status: 200, bytes: quant.sizeBytes, hash: quant.sha256! }));
    const { m, saved, results } = manager(fs);
    await m.start(textModel, quant, false);
    expect(await settle(m, textModel.id)).toBeUndefined();
    expect(saved).toHaveLength(1);
    expect(saved[0].localPath).toBe(`/f/models/${textModel.id}/${quant.fileName}`);
    expect(disk.has(`${saved[0].localPath}.part`)).toBe(false);
    expect(results[0]).toMatch(/is ready/);
  });

  it('deletes the partial and installs nothing on a checksum mismatch', async () => {
    const { fs, disk } = fakeFs(() => ({ status: 200, bytes: quant.sizeBytes, hash: 'f'.repeat(64) }));
    const { m, saved } = manager(fs);
    await m.start(textModel, quant, false);
    const t = await settle(m, textModel.id);
    expect(t?.phase).toBe('failed');
    expect(t?.error?.kind).toBe('checksumMismatch');
    expect(saved).toHaveLength(0);
    expect([...disk.keys()]).toHaveLength(0);
  });

  it('resumes a partial with a Range request and appends', async () => {
    const half = Math.floor(quant.sizeBytes / 2);
    const { fs, disk, requests } = fakeFs((req) => ({
      status: req.headers.Range ? 206 : 200,
      bytes: quant.sizeBytes - half,
      hash: quant.sha256!,
    }));
    disk.set(`/f/models/${textModel.id}/${quant.fileName}.part`, { size: half, hash: 'partial' });
    const { m, saved } = manager(fs);
    await m.start(textModel, quant, false);
    await settle(m, textModel.id);
    expect(requests[0].headers.Range).toBe(`bytes=${half}-`);
    expect(requests[0].append).toBe(true);
    expect(saved).toHaveLength(1);
  });

  it('starts over once when the server ignores the range', async () => {
    const half = Math.floor(quant.sizeBytes / 2);
    const { fs, disk, requests } = fakeFs(() => ({ status: 200, bytes: quant.sizeBytes, hash: quant.sha256! }));
    disk.set(`/f/models/${textModel.id}/${quant.fileName}.part`, { size: half, hash: 'partial' });
    const { m, saved } = manager(fs);
    await m.start(textModel, quant, false);
    await settle(m, textModel.id);
    expect(requests).toHaveLength(2);
    expect(requests[1].append).toBe(false);
    expect(requests[1].headers.Range).toBeUndefined();
    expect(saved).toHaveLength(1);
  });

  it('keeps the bytes and offers resume after a network failure', async () => {
    const { fs, disk } = fakeFs(() => ({ status: 200, bytes: quant.sizeBytes, hash: quant.sha256!, fail: true }));
    const { m } = manager(fs);
    await m.start(textModel, quant, false);
    const t = await settle(m, textModel.id);
    expect(t?.phase).toBe('failed');
    expect(t?.error?.recovery).toMatch(/Resume/);
    expect(disk.get(`/f/models/${textModel.id}/${quant.fileName}.part`)?.size).toBeGreaterThan(0);
  });

  it('refuses a Wi-Fi-only model on mobile data before any request', async () => {
    const { fs, requests } = fakeFs(() => ({ status: 200, bytes: 1, hash: 'x' }));
    const { m } = manager(fs, 'metered');
    const q = bigModel.quants[0];
    await expect(m.start(bigModel as CatalogueModel, q, false)).rejects.toMatchObject({ kind: 'wifiRequired' });
    expect(requests).toHaveLength(0);
  });

  it('refuses when free space is short', async () => {
    const { fs, requests } = fakeFs(() => ({ status: 200, bytes: 1, hash: 'x' }), { free: quant.sizeBytes });
    const { m } = manager(fs);
    await expect(m.start(textModel, quant, false)).rejects.toMatchObject({ kind: 'insufficientStorage' });
    expect(requests).toHaveLength(0);
  });

  it('pause keeps the partial and reports paused', async () => {
    const { fs } = fakeFs(() => ({ status: 200, bytes: quant.sizeBytes, hash: quant.sha256! }));
    const { m, saved } = manager(fs);
    await m.start(textModel, quant, false);
    m.pause(textModel.id);
    const t = await settle(m, textModel.id);
    expect(t?.phase).toBe('paused');
    expect(saved).toHaveLength(0);
  });

  it('downloads the projector as a second file for vision models', async () => {
    const vision = catalogue.models.find((m) => m.visionSupported && m.mmproj && !m.wifiOnly)!;
    const vq = vision.quants.find((q) => q.quant === vision.recommendedQuant)!;
    const { fs, requests } = fakeFs((req) =>
      req.url === vision.mmproj!.downloadUrl
        ? { status: 200, bytes: vision.mmproj!.sizeBytes, hash: vision.mmproj!.sha256! }
        : { status: 200, bytes: vq.sizeBytes, hash: vq.sha256! },
    );
    const { m, saved } = manager(fs);
    await m.start(vision, vq, true);
    await settle(m, vision.id);
    expect(requests).toHaveLength(2);
    expect(saved[0].mmprojPath).toContain(vision.mmproj!.fileName);
  });
});
