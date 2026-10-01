/**
 * The seam between engine logic and the native binding. `backend.native.ts`
 * implements it with llama.rn; `backend.web.ts` with a canned demo for the
 * browser preview; tests with a fake.
 */
export type BackendMessage = {
  role: 'system' | 'user' | 'assistant';
  content: string;
  /** Absolute path of an attached image, for vision models. */
  imagePath?: string | null;
};

export type CompletionParams = {
  messages: BackendMessage[];
  maxTokens: number;
  temperature: number;
  topP: number;
  topK: number;
  repeatPenalty: number;
};

export type CompletionOutcome = {
  text: string;
  interrupted: boolean;
  contextFull: boolean;
  tokensPredicted: number;
  /** Prompt tokens evaluated for this reply (not counting cached prefix reuse). */
  promptTokens: number | null;
  tokensPerSecond: number | null;
};

export interface BackendContext {
  readonly gpu: boolean;
  readonly reasonNoGpu: string;
  initVision(mmprojPath: string): Promise<boolean>;
  complete(params: CompletionParams, onToken: (token: string) => void): Promise<CompletionOutcome>;
  stop(): Promise<void>;
  countTokens(text: string): Promise<number>;
  release(): Promise<void>;
}

export interface LlamaBackend {
  /** False when the native engine is not linked into this build. */
  readonly available: boolean;
  /** Reads the GGUF header without loading weights: cheap corruption check. */
  readModelInfo(path: string): Promise<Record<string, unknown>>;
  init(
    opts: { path: string; contextLength: number; gpuLayers: number; vision: boolean },
    onProgress: (fraction: number) => void,
  ): Promise<BackendContext>;
}
