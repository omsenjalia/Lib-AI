import { AppConstants } from './constants';
import type { Message, Persona } from './db/types';
import type { BackendMessage } from './engine/backendTypes';
import { answerText } from './utils/markdownBlocks';
import { estimateTokens, perMessageOverhead } from './utils/tokenEstimator';

const builtInStudyPrompt =
  'You are a study assistant in an offline app. Answer clearly and concisely, and show your working for anything mathematical.';

const offlineSuffix =
  'The user is offline on a phone. You have no internet access and must not suggest searching the web. ' +
  'Format mathematics as LaTeX between $...$ for inline and $$...$$ for display.';

/**
 * Precedence: the thread's persona, then the user's own default instruction,
 * then the built-in study prompt. Only one is used: stacking them would let a
 * persona silently override the person typing.
 */
export function systemPromptFor(persona: Persona | null, userDefault: string | null): string {
  const base = persona?.systemPrompt ?? userDefault ?? builtInStudyPrompt;
  return `${base}\n\n${offlineSuffix}`;
}

/**
 * Newest turns backwards until 70% of the window is spent, at most 40
 * messages. Recent turns win because a question refers to the answer right
 * before it. Errors and empty placeholders are never sent back: both would
 * teach the model a shape it should not imitate. Past reasoning is stripped
 * from assistant turns, as the model cards for reasoning models recommend.
 */
export function buildPrompt(opts: {
  history: Message[];
  persona: Persona | null;
  userDefaultPrompt: string | null;
  contextLength: number;
  visionReady: boolean;
}): BackendMessage[] {
  const budget = Math.floor(opts.contextLength * AppConstants.contextBudgetFraction);
  const system = systemPromptFor(opts.persona, opts.userDefaultPrompt);
  let spent = estimateTokens(system);
  const selected: Message[] = [];
  for (let i = opts.history.length - 1; i >= 0; i--) {
    const m = opts.history[i];
    if (selected.length >= AppConstants.maxMessagesInContext) break;
    if (m.isError) continue;
    if (!m.content && !m.imagePath) continue;
    const content = m.role === 'assistant' ? answerText(m.content) : m.content;
    const cost = estimateTokens(content) + perMessageOverhead;
    if (spent + cost > budget && selected.length > 0) break;
    spent += cost;
    selected.push({ ...m, content });
  }
  selected.reverse();
  // Only the newest image is attached: each costs hundreds of tokens and older
  // ones are rarely what the question is about.
  const lastImageIndex = opts.visionReady ? selected.map((m) => Boolean(m.imagePath)).lastIndexOf(true) : -1;
  return [
    { role: 'system', content: system },
    ...selected.map((m, i) => ({
      role: m.role === 'assistant' ? ('assistant' as const) : ('user' as const),
      content: m.content,
      imagePath: i === lastImageIndex ? m.imagePath : null,
    })),
  ];
}

/** Never more than the window holds, never less than a paragraph. */
export function maxTokensFor(prompt: BackendMessage[], contextLength: number): number {
  const used = prompt.reduce((t, m) => t + estimateTokens(m.content) + perMessageOverhead, 0);
  return Math.min(4096, Math.max(128, contextLength - used));
}

/** The meter's view of a thread. */
export function usedTokens(messages: Message[], systemPrompt: string, streamingText: string): number {
  let total = estimateTokens(systemPrompt);
  for (const m of messages) total += (m.tokenCount ?? estimateTokens(m.content)) + perMessageOverhead;
  return total + estimateTokens(streamingText);
}
