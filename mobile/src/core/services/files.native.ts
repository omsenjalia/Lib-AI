import ReactNativeBlobUtil from 'react-native-blob-util';

import { AppConstants } from '../constants';
import { parseMemAvailable } from '../utils/memoryBudget';
import type { DownloadHandle, DownloadRequest, FileService } from './fileTypes';

/**
 * Native file service.
 *
 * Models live under the app's private files directory:
 *   <files>/models/<modelId>/<file>.gguf
 * which is the same place the Flutter build kept them, so an in-place upgrade
 * finds its models without downloading them again.
 */
const fs = ReactNativeBlobUtil.fs;
const base = fs.dirs.DocumentDir;

const stripScheme = (p: string) => (p.startsWith('file://') ? p.slice(7) : p);

export const files: FileService = {
  supportsModels: true,
  filesDir: () => base,
  modelDir: (modelId) => `${base}/${AppConstants.modelsDirectoryName}/${modelId}`,
  attachmentsDir: () => `${base}/${AppConstants.attachmentsDirectoryName}`,
  exportsDir: () => `${fs.dirs.CacheDir}/${AppConstants.exportsDirectoryName}`,
  cacheDir: () => fs.dirs.CacheDir,

  exists: (path) => fs.exists(stripScheme(path)),

  async size(path) {
    try {
      return Number((await fs.stat(stripScheme(path))).size) || 0;
    } catch {
      return 0;
    }
  },

  async mkdirp(path) {
    let current = '';
    for (const part of path.split('/').filter(Boolean)) {
      current = `${current}/${part}`;
      if (!(await fs.exists(current))) {
        try {
          await fs.mkdir(current);
        } catch {
          // Raced with another mkdir, or the prefix is a system path we cannot
          // create (and that already exists). The final exists check decides.
        }
      }
    }
    if (!(await fs.exists(path))) throw new Error(`Could not create ${path}`);
  },

  async unlink(path) {
    if (await fs.exists(stripScheme(path))) await fs.unlink(stripScheme(path));
  },

  async move(from, to) {
    if (await fs.exists(to)) await fs.unlink(to);
    await fs.mv(stripScheme(from), to);
  },

  async copy(from, to) {
    if (await fs.exists(to)) await fs.unlink(to);
    await fs.cp(stripScheme(from), to);
  },

  writeText: (path, text) => fs.writeFile(path, text, 'utf8'),

  async sha256(path) {
    return String(await fs.hash(stripScheme(path), 'sha256')).toLowerCase();
  },

  async freeBytes() {
    try {
      const df = await fs.df();
      const free = Number(df.internal_free ?? df.free);
      return Number.isFinite(free) ? free : null;
    } catch {
      return null;
    }
  },

  async memAvailableBytes() {
    try {
      return parseMemAvailable(String(await fs.readFile('/proc/meminfo', 'utf8')));
    } catch {
      return null;
    }
  },

  async partialBytes() {
    let total = 0;
    for (const p of await listPartials()) total += await files.size(p);
    return total;
  },

  async deletePartials() {
    let total = 0;
    for (const p of await listPartials()) {
      total += await files.size(p);
      await files.unlink(p);
    }
    return total;
  },

  download(req: DownloadRequest): DownloadHandle {
    const task = ReactNativeBlobUtil.config({
      path: req.path,
      overwrite: !req.append,
      wifiOnly: req.wifiOnly,
      followRedirect: true,
      // Two minutes without bytes is a stall. The partial survives it, and
      // Resume continues from the last flushed byte.
      timeout: 120_000,
    }).fetch('GET', req.url, req.headers);
    task.progress({ interval: 250 }, (received, total) => req.onProgress(Number(received), Number(total)));
    const done = task.then((res) => {
      const info = res.info();
      return { status: info.status, headers: (info.headers ?? {}) as Record<string, string> };
    });
    return { done, cancel: () => void task.cancel() };
  },

  toUri: (path) => (path.startsWith('file://') ? path : `file://${path}`),
};

async function listPartials(): Promise<string[]> {
  const root = `${base}/${AppConstants.modelsDirectoryName}`;
  if (!(await fs.exists(root))) return [];
  const out: string[] = [];
  for (const dir of await fs.ls(root)) {
    const full = `${root}/${dir}`;
    if (!(await fs.isDir(full))) continue;
    for (const f of await fs.ls(full)) if (f.endsWith('.part')) out.push(`${full}/${f}`);
  }
  return out;
}
