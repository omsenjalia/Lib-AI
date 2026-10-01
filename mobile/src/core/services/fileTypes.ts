/**
 * The file operations the app needs, behind one interface so the native
 * implementation (react-native-blob-util) and the web preview stub can be
 * swapped by Metro's platform extensions (`files.native.ts` / `files.web.ts`).
 */
export type DownloadHandle = {
  /** Resolves with the HTTP status once the body has been written. */
  done: Promise<{ status: number; headers: Record<string, string> }>;
  cancel(): void;
};

export type DownloadRequest = {
  url: string;
  /** Destination file; bytes are appended when `append` is set (Range resume). */
  path: string;
  append: boolean;
  headers: Record<string, string>;
  /** Bind the request to Wi-Fi at the OS level, not just check it first. */
  wifiOnly: boolean;
  onProgress(received: number, total: number): void;
};

export interface FileService {
  /** False on the web preview: no model files, no downloads. */
  readonly supportsModels: boolean;
  filesDir(): string;
  modelDir(modelId: string): string;
  attachmentsDir(): string;
  exportsDir(): string;
  /** Scratch space the system may clear. */
  cacheDir(): string;
  exists(path: string): Promise<boolean>;
  size(path: string): Promise<number>;
  mkdirp(path: string): Promise<void>;
  unlink(path: string): Promise<void>;
  move(from: string, to: string): Promise<void>;
  copy(from: string, to: string): Promise<void>;
  writeText(path: string, text: string): Promise<void>;
  /** Streaming SHA-256, computed natively so a 7 GB file is never held in memory. */
  sha256(path: string): Promise<string>;
  freeBytes(): Promise<number | null>;
  memAvailableBytes(): Promise<number | null>;
  /** Sizes of leftover `.part` files, by model directory. */
  partialBytes(): Promise<number>;
  deletePartials(): Promise<number>;
  download(req: DownloadRequest): DownloadHandle;
  /** A `file://` URI for components that want one. */
  toUri(path: string): string;
}
