import type { BackendContext, CompletionParams, LlamaBackend } from './backendTypes';
import { demoShowcase } from './demoShowcase';

/**
 * Browser preview only. There is no llama.cpp in the browser build, so this
 * streams a fixed showcase answer that exercises every renderer. Nothing here
 * ships to Android.
 */
class DemoContext implements BackendContext {
  readonly gpu = false;
  readonly reasonNoGpu = 'Web preview';
  private stopped = false;

  async initVision() {
    return true;
  }

  async complete(params: CompletionParams, onToken: (t: string) => void) {
    this.stopped = false;
    const pieces = demoShowcase.match(/\s*\S+/g) ?? [];
    let text = '';
    for (const piece of pieces) {
      if (this.stopped) break;
      await new Promise((r) => setTimeout(r, 8));
      text += piece;
      onToken(piece);
    }
    const promptTokens = Math.ceil(params.messages.reduce((t, m) => t + m.content.length, 0) / 4);
    return { text, interrupted: this.stopped, contextFull: false, tokensPredicted: pieces.length, promptTokens, tokensPerSecond: 118.4 };
  }

  async stop() {
    this.stopped = true;
  }

  async countTokens(text: string) {
    return Math.ceil(text.length / 4);
  }

  async release() {}
}

export const backend: LlamaBackend = {
  available: true,
  async readModelInfo() {
    return {};
  },
  async init(_, onProgress) {
    for (let p = 0; p <= 1; p += 0.25) {
      onProgress(p);
      await new Promise((r) => setTimeout(r, 120));
    }
    return new DemoContext();
  },
};
