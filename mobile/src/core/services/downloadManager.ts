import type { CatalogueModel, QuantOption } from '../catalogue';
import type { ModelInstallation } from '../db/types';
import { AppError, asAppError } from '../errors';
import type { FileService } from './fileTypes';
import type { NetworkKind } from './connectivity';
import type { ProgressNote } from './notifications';

/**
 * Downloads a model and its vision projector, and installs them only once the
 * checksum matches.
 *
 * Non-negotiables carried over from the Flutter build:
 * 1. The Wi-Fi gate is re-checked before every file. For a `wifiOnly` model it
 *    is absolute, and the request itself is bound to Wi-Fi by the OS.
 * 2. A download is not a model until its SHA-256 matches the catalogue. Bytes
 *    stream to `<file>.part`; a mismatch deletes it; a match renames it into
 *    place, and only then is the installation row written.
 * 3. Pause, network loss and app death keep the `.part`. The next attempt sends
 *    `Range: bytes=N-`, and if the server ignores the range the partial is
 *    discarded and one full request is made.
 *
 * New here: free space is checked before a byte is requested.
 */
export type DownloadPhase = 'downloading' | 'verifying' | 'paused' | 'failed';

export type DownloadTask = {
  modelId: string;
  quant: string;
  includeMmproj: boolean;
  phase: DownloadPhase;
  fileIndex: number;
  fileCount: number;
  fileName: string;
  /** Bytes across every file in this download. */
  received: number;
  total: number;
  bytesPerSecond: number;
  etaMs: number;
  error: AppError | null;
};

export type DownloadDeps = {
  files: FileService;
  network(): Promise<NetworkKind>;
  saveInstallation(i: ModelInstallation): Promise<void>;
  notify: {
    permission(): Promise<boolean>;
    progress(p: ProgressNote): void;
    result(modelId: string, title: string, body: string): void;
    clear(modelId: string): void;
  };
  now?: () => number;
};

type FileJob = { fileName: string; url: string; sizeBytes: number; sha256?: string; isProjector: boolean };

const cancelledError = new Error('cancelled');

export function jobsFor(model: CatalogueModel, quant: QuantOption, includeMmproj: boolean): FileJob[] {
  const jobs: FileJob[] = [
    { fileName: quant.fileName, url: quant.downloadUrl, sizeBytes: quant.sizeBytes, sha256: quant.sha256, isProjector: false },
  ];
  if (includeMmproj && model.mmproj) {
    jobs.push({
      fileName: model.mmproj.fileName,
      url: model.mmproj.downloadUrl,
      sizeBytes: model.mmproj.sizeBytes,
      sha256: model.mmproj.sha256,
      isProjector: true,
    });
  }
  return jobs;
}

export class DownloadManager {
  private tasks = new Map<string, DownloadTask>();
  private cancels = new Map<string, () => void>();
  private intent = new Map<string, 'pause' | 'cancel'>();
  private listeners = new Set<(tasks: ReadonlyMap<string, DownloadTask>) => void>();
  private lastNotified = new Map<string, number>();
  private readonly now: () => number;

  constructor(private readonly deps: DownloadDeps) {
    this.now = deps.now ?? Date.now;
  }

  subscribe(listener: (tasks: ReadonlyMap<string, DownloadTask>) => void): () => void {
    this.listeners.add(listener);
    listener(this.tasks);
    return () => this.listeners.delete(listener);
  }

  get(modelId: string): DownloadTask | undefined {
    return this.tasks.get(modelId);
  }

  private set(modelId: string, patch: Partial<DownloadTask> | null) {
    if (patch === null) this.tasks.delete(modelId);
    else this.tasks.set(modelId, { ...(this.tasks.get(modelId) as DownloadTask), ...patch });
    const snapshot = new Map(this.tasks);
    this.tasks = snapshot;
    for (const l of this.listeners) l(snapshot);
  }

  isActive(modelId: string): boolean {
    const t = this.tasks.get(modelId);
    return t?.phase === 'downloading' || t?.phase === 'verifying';
  }

  /**
   * Rebuilds paused tasks from `.part` files left by a previous run, so the
   * library can offer Resume instead of pretending nothing happened.
   */
  async restorePartials(models: CatalogueModel[]): Promise<void> {
    for (const model of models) {
      if (this.tasks.has(model.id)) continue;
      const dir = this.deps.files.modelDir(model.id);
      for (const quant of model.quants) {
        const part = `${dir}/${quant.fileName}.part`;
        if (!(await this.deps.files.exists(part))) continue;
        const have = await this.deps.files.size(part);
        const includeMmproj = model.visionSupported && Boolean(model.mmproj);
        const jobs = jobsFor(model, quant, includeMmproj);
        this.set(model.id, {
          modelId: model.id,
          quant: quant.quant,
          includeMmproj,
          phase: 'paused',
          fileIndex: 0,
          fileCount: jobs.length,
          fileName: quant.fileName,
          received: have,
          total: jobs.reduce((t, j) => t + j.sizeBytes, 0),
          bytesPerSecond: 0,
          etaMs: 0,
          error: null,
        });
        break;
      }
    }
  }

  /** Throws before any transfer for gates the user must act on (Wi-Fi, space). */
  async preflight(model: CatalogueModel, quant: QuantOption, includeMmproj: boolean): Promise<void> {
    const kind = await this.deps.network();
    if (kind === 'offline') {
      throw new AppError('download', 'You are offline.', { recovery: 'Connect to a network to download models.' });
    }
    if (model.wifiOnly && kind !== 'unmetered') {
      throw new AppError('wifiRequired', `${model.displayName} downloads over Wi-Fi only.`, {
        detail: 'This is a hard block for very large models, not a setting.',
      });
    }
    const jobs = jobsFor(model, quant, includeMmproj);
    let needed = 0;
    for (const j of jobs) {
      const part = `${this.deps.files.modelDir(model.id)}/${j.fileName}.part`;
      needed += Math.max(0, j.sizeBytes - (await this.deps.files.size(part)));
    }
    const free = await this.deps.files.freeBytes();
    // Keep 500 MB spare: Android misbehaves well before the disk is truly full.
    if (free !== null && free < needed + 500_000_000) {
      throw new AppError('insufficientStorage', 'Not enough free storage for this download.', {
        detail: `Needs about ${Math.ceil(needed / 1e8) / 10} GB plus headroom.`,
      });
    }
  }

  async start(model: CatalogueModel, quant: QuantOption, includeMmproj: boolean): Promise<void> {
    if (this.isActive(model.id)) return;
    await this.preflight(model, quant, includeMmproj);
    void this.deps.notify.permission();
    const jobs = jobsFor(model, quant, includeMmproj);
    const total = jobs.reduce((t, j) => t + j.sizeBytes, 0);
    this.intent.delete(model.id);
    this.set(model.id, {
      modelId: model.id,
      quant: quant.quant,
      includeMmproj,
      phase: 'downloading',
      fileIndex: 0,
      fileCount: jobs.length,
      fileName: jobs[0].fileName,
      received: this.tasks.get(model.id)?.received ?? 0,
      total,
      bytesPerSecond: 0,
      etaMs: 0,
      error: null,
    });
    void this.run(model, quant, jobs);
  }

  pause(modelId: string): void {
    if (!this.isActive(modelId)) return;
    this.intent.set(modelId, 'pause');
    this.cancels.get(modelId)?.();
  }

  /** Stops and discards the partial bytes. */
  async cancel(model: CatalogueModel): Promise<void> {
    const task = this.tasks.get(model.id);
    this.intent.set(model.id, 'cancel');
    this.cancels.get(model.id)?.();
    if (task) {
      for (const q of model.quants) await this.deps.files.unlink(`${this.deps.files.modelDir(model.id)}/${q.fileName}.part`);
      if (model.mmproj) await this.deps.files.unlink(`${this.deps.files.modelDir(model.id)}/${model.mmproj.fileName}.part`);
    }
    this.deps.notify.clear(model.id);
    this.set(model.id, null);
  }

  private async run(model: CatalogueModel, quant: QuantOption, jobs: FileJob[]): Promise<void> {
    const dir = this.deps.files.modelDir(model.id);
    const total = jobs.reduce((t, j) => t + j.sizeBytes, 0);
    const paths: string[] = [];
    let doneBytes = 0;
    try {
      await this.deps.files.mkdirp(dir);
      for (let i = 0; i < jobs.length; i++) {
        const job = jobs[i];
        // Re-checked per file: dropping off Wi-Fi between files stops a Wi-Fi-only model.
        if (model.wifiOnly && (await this.deps.network()) !== 'unmetered') {
          throw new AppError('wifiRequired', `${model.displayName} downloads over Wi-Fi only.`);
        }
        this.set(model.id, { fileIndex: i, fileName: job.fileName, phase: 'downloading' });
        const finalPath = `${dir}/${job.fileName}`;
        const part = `${finalPath}.part`;
        await this.transferFile(model, job, part, doneBytes, total, i, jobs.length);

        this.set(model.id, { phase: 'verifying', received: doneBytes + job.sizeBytes });
        this.notifyProgress(model, true);
        if (job.sha256) {
          const actual = await this.deps.files.sha256(part);
          if (actual !== job.sha256.toLowerCase()) {
            await this.deps.files.unlink(part);
            throw new AppError('checksumMismatch', 'Downloaded file failed its integrity check.', {
              detail: `${job.fileName}: expected ${job.sha256}, got ${actual}`,
            });
          }
        }
        await this.deps.files.move(part, finalPath);
        paths.push(finalPath);
        doneBytes += job.sizeBytes;
      }

      await this.deps.saveInstallation({
        modelId: model.id,
        quant: quant.quant,
        fileName: quant.fileName,
        localPath: paths[0],
        mmprojPath: jobs.length > 1 ? paths[1] : null,
        sizeBytes: quant.sizeBytes,
        sha256: quant.sha256 ?? null,
        repoSha: model.ggufRepoSha ?? null,
        totalBytes: total,
        downloadedAt: this.now(),
      });
      this.set(model.id, null);
      this.deps.notify.result(model.id, `${model.displayName} is ready`, 'Tap to open the Model Library.');
    } catch (e) {
      const intent = this.intent.get(model.id);
      this.intent.delete(model.id);
      if (intent === 'cancel') return;
      if (intent === 'pause') {
        this.set(model.id, { phase: 'paused', bytesPerSecond: 0, etaMs: 0 });
        this.deps.notify.clear(model.id);
        return;
      }
      const error = e === cancelledError ? new AppError('download', 'The download stopped.') : asDownloadError(e);
      this.set(model.id, { phase: 'failed', error, bytesPerSecond: 0, etaMs: 0 });
      this.deps.notify.result(model.id, `${model.displayName} could not be downloaded`, error.message);
    } finally {
      this.cancels.delete(model.id);
    }
  }

  private async transferFile(
    model: CatalogueModel,
    job: FileJob,
    part: string,
    doneBytes: number,
    total: number,
    fileIndex: number,
    fileCount: number,
  ): Promise<void> {
    let have = (await this.deps.files.exists(part)) ? await this.deps.files.size(part) : 0;
    if (have > job.sizeBytes) {
      await this.deps.files.unlink(part);
      have = 0;
    }
    if (have === job.sizeBytes) return;

    const attempt = async (from: number) => {
      let lastBytes = from;
      let lastAt = this.now();
      let speed = 0;
      const handle = this.deps.files.download({
        url: job.url,
        path: part,
        append: from > 0,
        headers: {
          'User-Agent': 'LibraryAI/2.0 (+offline-first study app)',
          ...(from > 0 ? { Range: `bytes=${from}-` } : {}),
        },
        wifiOnly: model.wifiOnly,
        onProgress: (received) => {
          const fileBytes = from + received;
          const t = this.now();
          if (t - lastAt >= 500) {
            const instant = ((fileBytes - lastBytes) * 1000) / (t - lastAt);
            // Smoothed, so the ETA does not jump around with every chunk.
            speed = speed === 0 ? instant : speed * 0.7 + instant * 0.3;
            lastBytes = fileBytes;
            lastAt = t;
          }
          const overall = doneBytes + fileBytes;
          this.set(model.id, {
            received: overall,
            bytesPerSecond: speed,
            etaMs: speed > 0 ? ((total - overall) / speed) * 1000 : 0,
            fileIndex,
            fileCount,
          });
          this.notifyProgress(model, false);
        },
      });
      this.cancels.set(model.id, () => handle.cancel());
      if (this.intent.has(model.id)) handle.cancel();
      try {
        return await handle.done;
      } catch (e) {
        if (this.intent.has(model.id)) throw cancelledError;
        throw e;
      }
    };

    let res = await attempt(have);
    if (have > 0 && res.status === 200) {
      // The server ignored the range and sent the whole file, which was
      // appended to the partial. Start again from zero, once.
      await this.deps.files.unlink(part);
      res = await attempt(0);
    } else if (res.status === 416) {
      // Range not satisfiable: the partial was already complete. The size check decides.
    } else if (res.status >= 400) {
      throw new AppError('download', `The server refused the download (HTTP ${res.status}).`, {
        recovery: res.status === 404 ? 'This file was removed upstream. Check for an app update.' : 'Try again later.',
      });
    }
    const size = await this.deps.files.size(part);
    if (size !== job.sizeBytes) {
      if (size > job.sizeBytes) await this.deps.files.unlink(part);
      throw new AppError('download', 'The download ended early.', {
        detail: `${job.fileName}: ${size} of ${job.sizeBytes} bytes`,
        recovery: 'Tap Resume. The bytes already saved are kept.',
      });
    }
  }

  private notifyProgress(model: CatalogueModel, force: boolean) {
    const t = this.now();
    if (!force && t - (this.lastNotified.get(model.id) ?? 0) < 1000) return;
    this.lastNotified.set(model.id, t);
    const task = this.tasks.get(model.id);
    if (!task) return;
    this.deps.notify.progress({
      modelId: model.id,
      modelName: model.displayName,
      phase: task.phase === 'verifying' ? 'verifying' : 'downloading',
      received: task.received,
      total: task.total,
      bytesPerSecond: task.bytesPerSecond,
      etaMs: task.etaMs,
      fileIndex: task.fileIndex,
      fileCount: task.fileCount,
    });
  }
}

function asDownloadError(e: unknown): AppError {
  if (e instanceof AppError) return e;
  const err = asAppError(e, 'The download was interrupted.');
  return new AppError('download', 'The download was interrupted.', {
    detail: err.detail,
    recovery: 'Tap Resume. The bytes already saved are kept.',
  });
}
