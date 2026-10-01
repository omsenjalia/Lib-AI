import { AppError, classifyLoadFailure } from '../errors';
import type { BackendContext, BackendMessage, CompletionOutcome, LlamaBackend } from './backendTypes';

/**
 * One resident model, its lifecycle, and generation.
 *
 * Load stages are surfaced as status rather than a spinner, because a 9B model
 * takes tens of seconds to page in and the user should see which step it is
 * on. Unlike the Flutter build's fllama, llama.rn has a real load and a real
 * release, so switching models frees memory before the next one is mapped and
 * there is no warm-up turn: `initLlama` itself is where OOM appears.
 */
export type EngineStage = 'unloaded' | 'verifying' | 'readingMetadata' | 'loadingWeights' | 'ready' | 'failed';

export type EngineStatus = {
  stage: EngineStage;
  modelId: string | null;
  contextLength: number;
  visionReady: boolean;
  gpu: boolean;
  /** 0..1 while weights load. */
  progress: number;
  message: string | null;
  error: AppError | null;
  /** Throughput of the last completed reply. */
  tokensPerSecond: number | null;
};

const initialStatus: EngineStatus = {
  stage: 'unloaded',
  modelId: null,
  contextLength: 0,
  visionReady: false,
  gpu: false,
  progress: 0,
  message: null,
  error: null,
  tokensPerSecond: null,
};

export type LoadRequest = {
  modelId: string;
  displayName: string;
  fileName: string;
  expectedBytes: number;
  modelPath: string;
  mmprojPath: string | null;
  contextLength: number;
  gpuLayers: number;
};

export type GenerateRequest = {
  messages: BackendMessage[];
  maxTokens: number;
  temperature: number;
  topP: number;
  topK: number;
  repeatPenalty: number;
  onToken: (delta: string) => void;
};

export type GenerationResult = CompletionOutcome & { stopped: boolean; error: AppError | null };

export type FileProbe = {
  exists(path: string): Promise<boolean>;
  size(path: string): Promise<number>;
};

const loadKey = (r: LoadRequest) =>
  [r.modelId, r.modelPath, r.mmprojPath ?? '', r.contextLength, r.gpuLayers].join('|');

export class InferenceEngine {
  private status: EngineStatus = initialStatus;
  private listeners = new Set<(s: EngineStatus) => void>();
  private ctx: BackendContext | null = null;
  private loadedKey: string | null = null;
  private inFlight: { key: string; promise: Promise<void> } | null = null;
  private generating = false;
  private stopRequested = false;

  constructor(
    private readonly backend: LlamaBackend,
    private readonly probe: FileProbe,
  ) {}

  getStatus(): EngineStatus {
    return this.status;
  }

  subscribe(listener: (s: EngineStatus) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private emit(patch: Partial<EngineStatus>) {
    this.status = { ...this.status, ...patch };
    for (const l of this.listeners) l(this.status);
  }

  isLoaded(req: LoadRequest): boolean {
    return this.ctx !== null && this.loadedKey === loadKey(req) && this.status.stage === 'ready';
  }

  /**
   * Loads are serialised. The same request joins the one in flight; a
   * different one waits for it, then runs (its predecessor's failure is not
   * its own).
   */
  async load(req: LoadRequest): Promise<void> {
    const key = loadKey(req);
    if (this.isLoaded(req)) return;
    while (this.inFlight) {
      if (this.inFlight.key === key) return this.inFlight.promise;
      try {
        await this.inFlight.promise;
      } catch {
        // Not ours.
      }
      if (this.isLoaded(req)) return;
    }
    const promise = this.doLoad(req, key);
    this.inFlight = { key, promise };
    try {
      await promise;
    } finally {
      this.inFlight = null;
    }
  }

  private fail(error: AppError): never {
    this.emit({ stage: 'failed', error, message: error.message, progress: 0 });
    throw error;
  }

  private async doLoad(req: LoadRequest, key: string): Promise<void> {
    if (!this.backend.available) {
      this.fail(new AppError('engineUnavailable', 'This build is missing its inference engine.'));
    }
    if (this.generating) await this.stop();
    await this.releaseContext();

    this.emit({
      ...initialStatus,
      stage: 'verifying',
      modelId: req.modelId,
      contextLength: req.contextLength,
      message: `Checking ${req.fileName}`,
    });

    // 1. The file must exist and be non-trivially sized: the usual state after
    //    an interrupted download or a deleted file.
    if (!(await this.probe.exists(req.modelPath))) {
      this.fail(
        new AppError('modelFileMissing', `The model file for ${req.displayName} is missing.`, {
          detail: `Expected at ${req.modelPath}`,
        }),
      );
    }
    const actual = await this.probe.size(req.modelPath);
    if (actual < 1024 * 1024) {
      this.fail(
        new AppError('modelCorrupt', `The model file for ${req.displayName} looks incomplete.`, {
          detail: `Only ${actual} bytes on disk, expected ${req.expectedBytes}.`,
        }),
      );
    }
    let mmproj = req.mmprojPath;
    if (mmproj && !(await this.probe.exists(mmproj))) {
      // Not fatal: the model still answers text.
      mmproj = null;
    }

    // 2. Header parse. A truncated file fails here in milliseconds instead of
    //    after a long weight load.
    this.emit({ stage: 'readingMetadata', message: 'Reading model metadata' });
    try {
      await this.backend.readModelInfo(req.modelPath);
    } catch (e) {
      this.fail(classifyHeaderFailure(e));
    }

    // 3. Weights. This is where memory is committed and where OOM appears. A
    //    GPU attempt that fails is retried once on the CPU.
    this.emit({ stage: 'loadingWeights', message: 'Loading weights into memory', progress: 0 });
    const onProgress = (p: number) => this.emit({ progress: p });
    const vision = mmproj !== null;
    let ctx: BackendContext;
    try {
      ctx = await this.backend.init({ path: req.modelPath, contextLength: req.contextLength, gpuLayers: req.gpuLayers, vision }, onProgress);
    } catch (gpuError) {
      if (req.gpuLayers <= 0) this.fail(classifyLoadFailure(errorText(gpuError)));
      try {
        ctx = await this.backend.init({ path: req.modelPath, contextLength: req.contextLength, gpuLayers: 0, vision }, onProgress);
      } catch (cpuError) {
        this.fail(classifyLoadFailure(errorText(cpuError)));
      }
    }

    let visionReady = false;
    if (mmproj) {
      this.emit({ message: 'Loading vision projector' });
      visionReady = await ctx.initVision(mmproj);
    }

    this.ctx = ctx;
    this.loadedKey = key;
    this.emit({
      stage: 'ready',
      visionReady,
      gpu: ctx.gpu,
      progress: 1,
      message: vision && !visionReady ? 'Vision projector unavailable; text only.' : null,
      error: null,
    });
  }

  async generate(req: GenerateRequest): Promise<GenerationResult> {
    const ctx = this.ctx;
    if (!ctx || this.status.stage !== 'ready') {
      return {
        text: '',
        interrupted: false,
        contextFull: false,
        tokensPredicted: 0,
        promptTokens: null,
        tokensPerSecond: null,
        stopped: false,
        error: new AppError('unknown', 'No model is loaded.'),
      };
    }
    this.generating = true;
    this.stopRequested = false;
    let streamed = '';
    try {
      const outcome = await ctx.complete(
        {
          messages: req.messages,
          maxTokens: req.maxTokens,
          temperature: req.temperature,
          topP: req.topP,
          topK: req.topK,
          repeatPenalty: req.repeatPenalty,
        },
        (token) => {
          streamed += token;
          if (!this.stopRequested) req.onToken(token);
        },
      );
      this.emit({ tokensPerSecond: outcome.tokensPerSecond });
      return { ...outcome, text: outcome.text || streamed, stopped: this.stopRequested || outcome.interrupted, error: null };
    } catch (e) {
      return {
        text: streamed,
        interrupted: true,
        contextFull: false,
        tokensPredicted: 0,
        promptTokens: null,
        tokensPerSecond: null,
        stopped: this.stopRequested,
        error: this.stopRequested ? null : classifyLoadFailure(errorText(e)),
      };
    } finally {
      this.generating = false;
    }
  }

  get isGenerating(): boolean {
    return this.generating;
  }

  async stop(): Promise<void> {
    this.stopRequested = true;
    if (this.ctx && this.generating) {
      try {
        await this.ctx.stop();
      } catch {
        // Already finished.
      }
    }
  }

  /** Exact count from the model's tokeniser; null when no model is loaded. */
  async countTokens(text: string): Promise<number | null> {
    if (!this.ctx || !text) return null;
    try {
      return await this.ctx.countTokens(text);
    } catch {
      return null;
    }
  }

  private async releaseContext() {
    const ctx = this.ctx;
    this.ctx = null;
    this.loadedKey = null;
    if (ctx) {
      try {
        await ctx.release();
      } catch {
        // A failed release leaves nothing to do; the next init allocates afresh.
      }
    }
  }

  /** Frees the model now. llama.rn releases synchronously, unlike fllama's 120 s reaper. */
  async unload(): Promise<void> {
    await this.stop();
    await this.releaseContext();
    this.emit({ ...initialStatus });
  }
}

function errorText(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

function classifyHeaderFailure(e: unknown): AppError {
  const classified = classifyLoadFailure(errorText(e));
  if (classified.kind === 'engineUnavailable') return classified;
  return new AppError('modelCorrupt', 'The model file could not be read.', { detail: errorText(e) });
}
