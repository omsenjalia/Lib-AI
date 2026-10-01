/**
 * Errors are values with advice: a user-facing `message`, an optional
 * technical `detail`, and a `recovery` line that says what to do about it.
 */
export type AppErrorKind =
  | 'modelFileMissing'
  | 'modelCorrupt'
  | 'insufficientMemory'
  | 'engineUnavailable'
  | 'download'
  | 'checksumMismatch'
  | 'unsupportedModality'
  | 'wifiRequired'
  | 'insufficientStorage'
  | 'missingFromCatalogue'
  | 'unknown';

const defaultRecovery: Partial<Record<AppErrorKind, string>> = {
  modelFileMissing: 'Re-download the model from Model Library.',
  modelCorrupt: 'The file may be truncated. Delete it and download again.',
  insufficientMemory:
    'Choose a smaller quantisation (Q3_K_M or Q4_K_M), or lower the context length in Settings.',
  engineUnavailable: 'Reinstall the app from a release build.',
  checksumMismatch: 'The download was corrupted in transit. Try again.',
  unsupportedModality: 'Switch to a vision-capable model to attach images.',
  wifiRequired: 'Connect to Wi-Fi and try again.',
  insufficientStorage: 'Free up space, or delete a model you no longer use.',
  missingFromCatalogue: 'Delete it from Model Library, then download a supported model.',
};

export class AppError extends Error {
  readonly kind: AppErrorKind;
  readonly detail?: string;
  readonly recovery?: string;

  constructor(kind: AppErrorKind, message: string, opts: { detail?: string; recovery?: string } = {}) {
    super(message);
    this.name = 'AppError';
    this.kind = kind;
    this.detail = opts.detail;
    this.recovery = opts.recovery ?? defaultRecovery[kind];
  }

  /** The text stored in the transcript when a turn fails. */
  toTranscript(): string {
    return this.recovery ? `${this.message}\n\n${this.recovery}` : this.message;
  }
}

export function asAppError(error: unknown, fallback = 'Something went wrong.'): AppError {
  if (error instanceof AppError) return error;
  const detail = error instanceof Error ? error.message : String(error);
  return new AppError('unknown', fallback, { detail });
}

const engineSignals = [
  'failed to load dynamic library',
  'dlopen',
  'unsatisfiedlinkerror',
  'no implementation found for',
  'jsi',
  'native module',
];

const memorySignals = [
  'out of memory',
  'failed to allocate',
  'unable to allocate',
  'insufficient memory',
  'ggml_backend_alloc',
  'failed to create context',
  'cannot allocate',
  'bad_alloc',
];

const corruptSignals = ['failed to load model', 'invalid magic', 'gguf', 'tensor', 'unknown model architecture'];

/**
 * Turns a raw native load failure into an error with the right advice. Order
 * matters: a missing engine is not the user's file, and memory is the failure
 * a phone actually hits, so both are checked before "corrupt".
 */
export function classifyLoadFailure(raw: string): AppError {
  const lower = raw.toLowerCase();
  if (engineSignals.some((s) => lower.includes(s))) {
    return new AppError('engineUnavailable', 'This build is missing its inference engine.', { detail: raw });
  }
  if (memorySignals.some((s) => lower.includes(s))) {
    return new AppError('insufficientMemory', 'Not enough free memory to load this model.', { detail: raw });
  }
  if (corruptSignals.some((s) => lower.includes(s))) {
    return new AppError('modelCorrupt', 'The model could not be loaded.', { detail: raw });
  }
  return new AppError('unknown', 'The model could not be loaded.', { detail: raw });
}
