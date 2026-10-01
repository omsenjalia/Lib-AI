import { create } from 'zustand';

import { modelById, recommendedQuantOf } from '@/core/catalogue';
import { AppConstants } from '@/core/constants';
import * as db from '@/core/db/database';
import { onChange } from '@/core/db/events';
import type { Message, Persona } from '@/core/db/types';
import { engine } from '@/core/engine';
import { AppError, asAppError } from '@/core/errors';
import { buildPrompt, maxTokensFor, systemPromptFor, usedTokens } from '@/core/prompt';
import { liveTokensPerSecond, type StreamStats } from '@/core/streamStats';
import { files } from '@/core/services/files';
import { autoTitleFromMessage, formatBytes } from '@/core/utils/formatters';
import { fitsInMemory, peakRequirementBytes } from '@/core/utils/memoryBudget';
import { estimateTokens } from '@/core/utils/tokenEstimator';
import { usePersonas } from './collections';
import { useEngineStatus } from './engineStatus';
import { getActiveModelId, useLibrary } from './library';
import { useSettings } from './settings';

/**
 * The conversation on screen and everything that happens when the user sends.
 *
 * Order of a send, unchanged from the Flutter build because each step fixed
 * something:
 *   1. create the thread on the first message (titled from it);
 *   2. make sure the model is resident BEFORE writing anything, so a load
 *      failure never leaves a question with no answer and no explanation;
 *   3. persist the user's turn;
 *   4. insert an empty assistant row, stream into memory, flush to SQLite at
 *      most every 2 s, finalise with the tokeniser's exact count.
 * A failure is stored as an error turn, so it survives a restart.
 */
type ChatState = {
  conversationId: number | null;
  messages: Message[];
  isGenerating: boolean;
  streamingId: number | null;
  streamingText: string;
  /** Live numbers for the Claude Code-style status line while a reply streams. */
  streamStats: StreamStats | null;
  lastError: AppError | null;
  /** The one-shot draft a suggestion chip puts in the composer. */
  draft: { text: string; nonce: number } | null;

  open(id: number): Promise<void>;
  newChat(): void;
  send(text: string, imagePath?: string | null): Promise<void>;
  regenerate(): Promise<void>;
  editAndResend(message: Message, text: string): Promise<void>;
  stop(): Promise<void>;
  setPersona(personaId: number | null): Promise<void>;
  toggleRenderMath(message: Message): Promise<void>;
  deleteMessage(message: Message): Promise<void>;
  setDraft(text: string): void;
  dismissError(): void;
};

let flushTimer: ReturnType<typeof setTimeout> | null = null;
let uiTimer: ReturnType<typeof setTimeout> | null = null;
let pendingText = '';

export const useChat = create<ChatState>((set, get) => {
  async function reload() {
    const id = get().conversationId;
    if (id === null) return;
    const messages = await db.messagesFor(id);
    if (get().conversationId === id) set({ messages });
  }

  async function personaFor(conversationId: number | null): Promise<Persona | null> {
    if (conversationId === null) return null;
    const conv = await db.conversationById(conversationId);
    if (!conv?.personaId) return null;
    return usePersonas.getState().list.find((p) => p.id === conv.personaId) ?? null;
  }

  async function persistError(conversationId: number, error: AppError) {
    await db.addMessage({ conversationId, role: 'assistant', content: error.toTranscript(), isError: true });
  }

  async function generate(conversationId: number) {
    const settings = useSettings.getState().settings;
    const status = engine.getStatus();
    const ctx = status.contextLength || settings.contextLength;
    const history = await db.messagesFor(conversationId);
    const persona = await personaFor(conversationId);
    const prompt = buildPrompt({
      history,
      persona,
      userDefaultPrompt: settings.systemPrompt,
      contextLength: ctx,
      visionReady: status.visionReady,
    });
    const assistantId = await db.addMessage({ conversationId, role: 'assistant', content: '' });
    pendingText = '';
    const stats: StreamStats = {
      startedAt: Date.now(),
      firstTokenAt: null,
      tokens: 0,
      promptTokens: prompt.reduce((t, m) => t + estimateTokens(m.content) + 4, 0),
    };
    set({ streamingId: assistantId, streamingText: '', streamStats: { ...stats }, isGenerating: true, lastError: null });

    const model = modelById(status.modelId);
    const result = await engine.generate({
      messages: prompt,
      maxTokens: maxTokensFor(prompt, ctx),
      temperature: settings.temperature,
      topP: settings.topP,
      topK: settings.topK,
      // The model card's own recommendation wins over a global guess.
      repeatPenalty: model?.samplingDefaults.repeatPenalty ?? 1.1,
      onToken: (delta) => {
        pendingText += delta;
        stats.tokens++;
        stats.firstTokenAt ??= Date.now();
        // Tokens arrive faster than React needs them; ~30 fps is plenty.
        uiTimer ??= setTimeout(() => {
          uiTimer = null;
          if (get().streamingId === assistantId) set({ streamingText: pendingText, streamStats: { ...stats } });
        }, 33);
        flushTimer ??= setTimeout(() => {
          flushTimer = null;
          void db.updateMessage(assistantId, { content: pendingText }, { silent: true }).catch(() => undefined);
        }, AppConstants.dbFlushIntervalMs);
      },
    });
    if (uiTimer) clearTimeout(uiTimer);
    if (flushTimer) clearTimeout(flushTimer);
    uiTimer = flushTimer = null;

    const text = result.text || pendingText;
    if (result.error) {
      set({ lastError: result.error });
      await db.updateMessage(assistantId, { content: result.error.toTranscript(), isError: true });
    } else {
      let content = text.trim() ? text : '_(empty response)_';
      if (result.contextFull) content += '\n\n_The conversation filled the context window. Start a new chat or raise the context length._';
      const finishedAt = Date.now();
      const exact = await engine.countTokens(text);
      await db.updateMessage(assistantId, {
        content,
        tokenCount: exact ?? estimateTokens(text),
        isEstimatedTokens: exact === null,
        // llama.cpp's own decode timing when it reports one; otherwise measured here.
        tokensPerSecond: result.tokensPerSecond ?? liveTokensPerSecond(stats, finishedAt),
        promptTokens: result.promptTokens ?? stats.promptTokens,
        generationMs: finishedAt - stats.startedAt,
      });
      if (exact !== null) await refreshExactCounts(conversationId);
    }
    await db.touchConversation(conversationId);
    set({ isGenerating: false, streamingId: null, streamingText: '', streamStats: null });
  }

  /** Replace estimates with tokeniser counts so the meter can stop saying "estimated". */
  async function refreshExactCounts(conversationId: number) {
    for (const m of await db.messagesFor(conversationId)) {
      if (!m.isEstimatedTokens || !m.content || m.isError) continue;
      const exact = await engine.countTokens(m.content);
      if (exact === null) return;
      await db.updateMessage(m.id, { tokenCount: exact, isEstimatedTokens: false }, { silent: true });
    }
    await reload();
  }

  async function loadAndRun(conversationId: number, body: () => Promise<void>) {
    set({ isGenerating: true, lastError: null });
    try {
      await ensureModelLoaded(get().conversationId);
    } catch (e) {
      const error = asAppError(e, 'The model could not be prepared.');
      set({ isGenerating: false, lastError: error });
      await persistError(conversationId, error);
      return;
    }
    await body();
  }

  return {
    conversationId: null,
    messages: [],
    isGenerating: false,
    streamingId: null,
    streamingText: '',
    streamStats: null,
    lastError: null,
    draft: null,

    async open(id) {
      if (get().isGenerating) await get().stop();
      set({ conversationId: id, messages: [], streamingId: null, streamingText: '', lastError: null });
      await reload();
    },

    newChat() {
      if (get().isGenerating) void get().stop();
      set({ conversationId: null, messages: [], streamingId: null, streamingText: '', lastError: null });
    },

    async send(text, imagePath = null) {
      const trimmed = text.trim();
      if ((!trimmed && !imagePath) || get().isGenerating) return;
      let conversationId = get().conversationId;
      if (conversationId === null) {
        conversationId = await db.createConversation({
          title: autoTitleFromMessage(trimmed || 'Image question'),
          modelId: getActiveModelId(),
        });
        set({ conversationId });
        await reload();
      }
      const id = conversationId;
      await loadAndRun(id, async () => {
        await db.addMessage({
          conversationId: id,
          role: 'user',
          content: trimmed,
          imagePath,
          tokenCount: estimateTokens(trimmed),
        });
        await db.updateConversation(id, { modelId: getActiveModelId() });
        await generate(id);
      });
    },

    async regenerate() {
      const id = get().conversationId;
      if (id === null || get().isGenerating) return;
      const msgs = get().messages;
      for (let i = msgs.length - 1; i >= 0; i--) {
        if (msgs[i].role === 'assistant') {
          await db.deleteMessagesFrom(id, msgs[i].id);
          break;
        }
        if (msgs[i].role === 'user') break;
      }
      await loadAndRun(id, () => generate(id));
    },

    async editAndResend(message, text) {
      const id = get().conversationId;
      if (id === null || get().isGenerating || !text.trim()) return;
      await db.deleteMessagesFrom(id, message.id);
      await loadAndRun(id, async () => {
        await db.addMessage({
          conversationId: id,
          role: 'user',
          content: text.trim(),
          imagePath: message.imagePath,
          tokenCount: estimateTokens(text),
        });
        await generate(id);
      });
    },

    stop: () => engine.stop(),

    async setPersona(personaId) {
      const id = get().conversationId;
      if (id !== null) await db.updateConversation(id, { personaId });
    },

    toggleRenderMath: (m) => db.updateMessage(m.id, { renderMath: !m.renderMath }),

    async deleteMessage(m) {
      if (get().streamingId === m.id) await get().stop();
      await db.deleteMessage(m.id);
    },

    setDraft: (text) => set({ draft: { text, nonce: Date.now() } }),
    dismissError: () => set({ lastError: null }),
  };
});

onChange(['messages'], () => {
  const { conversationId } = useChat.getState();
  if (conversationId === null) return;
  void db.messagesFor(conversationId).then((messages) => {
    if (useChat.getState().conversationId === conversationId) useChat.setState({ messages });
  });
});

/**
 * Loads the active model if it is not already resident with these settings.
 * Memory is checked first: a load that does not fit gets the process killed by
 * Android rather than raising anything catchable.
 */
export async function ensureModelLoaded(conversationId: number | null): Promise<void> {
  const modelId = getActiveModelId();
  if (!modelId) {
    throw new AppError('modelFileMissing', 'No model is installed yet.', {
      recovery: 'Open Model Library and download one to start chatting.',
    });
  }
  const model = modelById(modelId);
  if (!model) throw new AppError('missingFromCatalogue', 'This model is no longer in the catalogue.');
  const install = useLibrary.getState().installations[modelId] ?? (await db.installationFor(modelId));
  if (!install) throw new AppError('modelFileMissing', 'The installed model is missing from the library.');
  const settings = useSettings.getState().settings;
  const conv = conversationId === null ? null : await db.conversationById(conversationId);
  const contextLength = Math.min(
    Math.max(conv?.contextLengthOverride ?? settings.contextLength, AppConstants.minContextLength),
    model.maxContextLength,
  );
  const quant = model.quants.find((q) => q.quant === install.quant) ?? recommendedQuantOf(model);
  const includeVision = model.visionSupported && install.mmprojPath !== null;
  const request = {
    modelId,
    displayName: model.displayName,
    fileName: install.fileName,
    expectedBytes: quant.sizeBytes,
    modelPath: install.localPath,
    mmprojPath: includeVision ? install.mmprojPath : null,
    contextLength,
    gpuLayers: settings.gpuLayers,
  };
  if (engine.isLoaded(request)) return;

  const available = await files.memAvailableBytes();
  if (available !== null) {
    // The resident model is released before the next one maps, so only the
    // incoming model counts, plus what the current one will give back.
    const resident = modelById(engine.getStatus().modelId);
    const releasing = resident ? Math.round(resident.ramRequirementGb * 1e9) : 0;
    const required = peakRequirementBytes({
      requirementGb: model.ramRequirementGb,
      contextLength,
      recommendedContextLength: model.recommendedContextLength,
      extraBytes: includeVision ? model.mmproj?.sizeBytes ?? 0 : 0,
    });
    if (!fitsInMemory(available + releasing, required)) {
      throw new AppError('insufficientMemory', `Not enough free memory to load ${model.displayName}.`, {
        detail: `It needs about ${formatBytes(required)} free; this device has ${formatBytes(available + releasing)} available right now.`,
      });
    }
  }
  await engine.load(request);
}

/** The context meter's numbers for the open thread. */
export function useContextUsage(): { used: number; total: number; exact: boolean } {
  const messages = useChat((s) => s.messages);
  const streamingText = useChat((s) => s.streamingText);
  const isGenerating = useChat((s) => s.isGenerating);
  const total = useSettings((s) => s.settings.contextLength);
  const userPrompt = useSettings((s) => s.settings.systemPrompt);
  const engineCtx = useEngineStatusContext();
  const window = engineCtx || total;
  const used = usedTokens(messages, systemPromptFor(null, userPrompt), isGenerating ? streamingText : '');
  const exact = !isGenerating && messages.length > 0 && messages.every((m) => m.tokenCount !== null && !m.isEstimatedTokens);
  return { used, total: window, exact };
}

function useEngineStatusContext(): number {
  return useEngineStatus((s) => (s.stage === 'ready' ? s.contextLength : 0));
}
