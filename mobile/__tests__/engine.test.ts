import type { BackendContext, LlamaBackend } from '../src/core/engine/backendTypes';
import { InferenceEngine, type EngineStage, type LoadRequest } from '../src/core/engine/engine';

function fakeContext(over: Partial<BackendContext> = {}): BackendContext & { released: number } {
  const ctx = {
    gpu: false,
    reasonNoGpu: '',
    released: 0,
    initVision: async () => true,
    complete: async (_p: unknown, onToken: (t: string) => void) => {
      onToken('Hel');
      onToken('lo');
      return { text: 'Hello', interrupted: false, contextFull: false, tokensPredicted: 2, promptTokens: 9, tokensPerSecond: 12 };
    },
    stop: async () => undefined,
    countTokens: async (t: string) => t.length,
    release: async () => {
      ctx.released++;
    },
    ...over,
  };
  return ctx;
}

function setup(opts: {
  init?: LlamaBackend['init'];
  readModelInfo?: LlamaBackend['readModelInfo'];
  exists?: boolean;
  size?: number;
}) {
  const backend: LlamaBackend = {
    available: true,
    readModelInfo: opts.readModelInfo ?? (async () => ({})),
    init: opts.init ?? (async () => fakeContext()),
  };
  const engine = new InferenceEngine(backend, {
    exists: async () => opts.exists ?? true,
    size: async () => opts.size ?? 5e9,
  });
  const stages: EngineStage[] = [];
  engine.subscribe((s) => {
    if (stages[stages.length - 1] !== s.stage) stages.push(s.stage);
  });
  return { engine, stages };
}

const req = (over: Partial<LoadRequest> = {}): LoadRequest => ({
  modelId: 'phi-4-mini-3.8b',
  displayName: 'Phi-4 mini',
  fileName: 'phi.gguf',
  expectedBytes: 5e9,
  modelPath: '/models/phi.gguf',
  mmprojPath: null,
  contextLength: 4096,
  gpuLayers: 0,
  ...over,
});

describe('InferenceEngine', () => {
  it('walks the load stages in order and reaches ready', async () => {
    const { engine, stages } = setup({});
    await engine.load(req());
    expect(stages).toEqual(['verifying', 'readingMetadata', 'loadingWeights', 'ready']);
    expect(engine.isLoaded(req())).toBe(true);
  });

  it('reports a missing file with re-download advice', async () => {
    const { engine } = setup({ exists: false });
    await expect(engine.load(req())).rejects.toMatchObject({ kind: 'modelFileMissing' });
    expect(engine.getStatus().stage).toBe('failed');
    expect(engine.getStatus().error?.recovery).toMatch(/Re-download/);
  });

  it('treats a tiny file as incomplete', async () => {
    const { engine } = setup({ size: 1000 });
    await expect(engine.load(req())).rejects.toMatchObject({ kind: 'modelCorrupt' });
  });

  it('fails cheaply on an unreadable header', async () => {
    let initCalled = false;
    const { engine } = setup({
      readModelInfo: async () => {
        throw new Error('invalid magic');
      },
      init: async () => {
        initCalled = true;
        return fakeContext();
      },
    });
    await expect(engine.load(req())).rejects.toMatchObject({ kind: 'modelCorrupt' });
    expect(initCalled).toBe(false);
  });

  it('classifies an allocation failure as out of memory', async () => {
    const { engine } = setup({
      init: async () => {
        throw new Error('ggml_backend_alloc: failed to allocate buffer');
      },
    });
    await expect(engine.load(req())).rejects.toMatchObject({ kind: 'insufficientMemory' });
  });

  it('retries on the CPU when a GPU load fails', async () => {
    const layers: number[] = [];
    const { engine } = setup({
      init: async ({ gpuLayers }) => {
        layers.push(gpuLayers);
        if (gpuLayers > 0) throw new Error('opencl: device lost');
        return fakeContext();
      },
    });
    await engine.load(req({ gpuLayers: 99 }));
    expect(layers).toEqual([99, 0]);
    expect(engine.getStatus().stage).toBe('ready');
  });

  it('joins an identical load already in flight', async () => {
    let inits = 0;
    const { engine } = setup({
      init: async () => {
        inits++;
        await new Promise((r) => setTimeout(r, 10));
        return fakeContext();
      },
    });
    await Promise.all([engine.load(req()), engine.load(req())]);
    expect(inits).toBe(1);
  });

  it('releases the previous model before loading the next', async () => {
    const first = fakeContext();
    const contexts = [first, fakeContext()];
    const { engine } = setup({ init: async () => contexts.shift()! });
    await engine.load(req());
    await engine.load(req({ modelId: 'other', modelPath: '/models/other.gguf' }));
    expect(first.released).toBe(1);
  });

  it('a changed context length forces a reload', async () => {
    let inits = 0;
    const { engine } = setup({
      init: async () => {
        inits++;
        return fakeContext();
      },
    });
    await engine.load(req());
    await engine.load(req());
    await engine.load(req({ contextLength: 8192 }));
    expect(inits).toBe(2);
  });

  it('falls back to text-only when the projector file is gone', async () => {
    const { engine } = setup({});
    const e2 = new InferenceEngine(
      { available: true, readModelInfo: async () => ({}), init: async () => fakeContext() },
      { exists: async (p) => !p.includes('mmproj'), size: async () => 5e9 },
    );
    await e2.load(req({ mmprojPath: '/models/mmproj.gguf' }));
    expect(e2.getStatus().visionReady).toBe(false);
    expect(engine.getStatus().stage).toBe('unloaded');
  });

  it('streams tokens and returns the full text', async () => {
    const { engine } = setup({});
    await engine.load(req());
    const tokens: string[] = [];
    const r = await engine.generate({
      messages: [{ role: 'user', content: 'hi' }],
      maxTokens: 16,
      temperature: 0.6,
      topP: 0.95,
      topK: 20,
      repeatPenalty: 1.1,
      onToken: (t) => tokens.push(t),
    });
    expect(tokens.join('')).toBe('Hello');
    expect(r).toMatchObject({ text: 'Hello', stopped: false, error: null });
    expect(engine.getStatus().tokensPerSecond).toBe(12);
  });

  it('refuses to generate with nothing loaded', async () => {
    const { engine } = setup({});
    const r = await engine.generate({
      messages: [],
      maxTokens: 1,
      temperature: 0,
      topP: 1,
      topK: 1,
      repeatPenalty: 1,
      onToken: () => undefined,
    });
    expect(r.error?.message).toBe('No model is loaded.');
  });

  it('unload releases the context immediately', async () => {
    const ctx = fakeContext();
    const { engine } = setup({ init: async () => ctx });
    await engine.load(req());
    await engine.unload();
    expect(ctx.released).toBe(1);
    expect(engine.getStatus().stage).toBe('unloaded');
  });
});
