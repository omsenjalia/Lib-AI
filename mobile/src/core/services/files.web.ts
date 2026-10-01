import type { FileService } from './fileTypes';

/**
 * Web preview stub. The browser build exists so the interface can be reviewed
 * on a laptop; it has no model files and cannot download them. The one
 * "installed" model that bootstrap seeds for the preview is reported present so
 * the demo backend can stream into the real chat surface.
 */
const previewModel = (p: string) => p.startsWith('/web/models/');
const unsupported = () => Promise.reject(new Error('Model files are not available in the web preview.'));

export const files: FileService = {
  supportsModels: false,
  filesDir: () => '/web',
  modelDir: (id) => `/web/models/${id}`,
  attachmentsDir: () => '/web/attachments',
  exportsDir: () => '/web/exports',
  cacheDir: () => '/web/cache',
  exists: async (p) => previewModel(p),
  size: async (p) => (previewModel(p) ? 2_000_000_000 : 0),
  mkdirp: async () => undefined,
  unlink: async () => undefined,
  move: unsupported,
  copy: async () => undefined,
  writeText: async () => undefined,
  sha256: unsupported,
  freeBytes: async () => null,
  memAvailableBytes: async () => null,
  partialBytes: async () => 0,
  deletePartials: async () => 0,
  download: () => ({ done: unsupported(), cancel: () => undefined }),
  toUri: (p) => p,
};
