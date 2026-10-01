import { initLlama, loadLlamaModelInfo, type LlamaContext, type RNLlamaOAICompatibleMessage } from 'llama.rn';

import { AppConstants } from '../constants';
import type { BackendContext, BackendMessage, CompletionParams, LlamaBackend } from './backendTypes';

const toFileUri = (p: string) => (p.startsWith('file://') ? p : `file://${p}`);

function toLlamaMessages(messages: BackendMessage[]): RNLlamaOAICompatibleMessage[] {
  return messages.map((m) =>
    m.imagePath
      ? {
          role: m.role,
          content: [
            { type: 'image_url', image_url: { url: toFileUri(m.imagePath) } },
            { type: 'text', text: m.content || 'Describe this image.' },
          ],
        }
      : { role: m.role, content: m.content },
  );
}

class LlamaRnContext implements BackendContext {
  constructor(private readonly ctx: LlamaContext) {}

  get gpu() {
    return this.ctx.gpu;
  }

  get reasonNoGpu() {
    return this.ctx.reasonNoGPU;
  }

  async initVision(mmprojPath: string): Promise<boolean> {
    try {
      // CPU projector: the vision encoder is small next to the language model,
      // and GPU support for mtmd on Android varies by driver.
      return await this.ctx.initMultimodal({ path: mmprojPath, use_gpu: false });
    } catch {
      return false;
    }
  }

  async complete(params: CompletionParams, onToken: (token: string) => void) {
    const result = await this.ctx.completion(
      {
        messages: toLlamaMessages(params.messages),
        n_predict: params.maxTokens,
        temperature: params.temperature,
        top_p: params.topP,
        top_k: params.topK,
        penalty_repeat: params.repeatPenalty,
        // Reasoning stays inline as <think> tags; the renderer folds it away.
        reasoning_format: 'none',
      },
      (data) => {
        if (data.token) onToken(data.token);
      },
    );
    const tps = result.timings?.predicted_per_second;
    return {
      text: result.text,
      interrupted: result.interrupted,
      contextFull: result.context_full,
      tokensPredicted: result.tokens_predicted,
      promptTokens: typeof result.tokens_evaluated === 'number' ? result.tokens_evaluated : null,
      tokensPerSecond: typeof tps === 'number' && Number.isFinite(tps) ? tps : null,
    };
  }

  stop() {
    return this.ctx.stopCompletion();
  }

  async countTokens(text: string) {
    return (await this.ctx.tokenize(text)).tokens.length;
  }

  async release() {
    try {
      await this.ctx.releaseMultimodal();
    } catch {
      // Not initialised; nothing to release.
    }
    await this.ctx.release();
  }
}

export const backend: LlamaBackend = {
  available: true,

  async readModelInfo(path) {
    return (await loadLlamaModelInfo(toFileUri(path))) as Record<string, unknown>;
  },

  async init({ path, contextLength, gpuLayers, vision }, onProgress) {
    const ctx = await initLlama(
      {
        model: toFileUri(path),
        n_ctx: contextLength,
        // One sequence: the conversation gets the whole window it pays for.
        n_parallel: AppConstants.parallelSlots,
        n_gpu_layers: gpuLayers,
        use_mmap: true,
        use_mlock: false,
        // Multimodal prompts need stable media positions, so no context shift.
        ctx_shift: !vision,
      },
      (progress) => onProgress(Math.max(0, Math.min(1, progress / 100))),
    );
    return new LlamaRnContext(ctx);
  },
};
