import { AppConstants } from '../constants';

/**
 * Character-ratio token estimate. It drives the context meter while a reply is
 * streaming; once a turn completes the model's own tokeniser replaces it and
 * the meter stops saying "estimated".
 */
export function estimateTokens(text: string): number {
  if (!text) return 0;
  const codeFences = (text.match(/```[\s\S]*?```/g) ?? []).length;
  const mathSpans = (text.match(/\$\$[\s\S]*?\$\$/g) ?? []).length;
  let ratio: number = AppConstants.averageCharsPerToken;
  if (codeFences > 0) ratio -= 0.8; // code: ~3.2 chars/token
  if (mathSpans > 0) ratio -= 0.4; // maths: ~3.6 chars/token
  if (ratio < 2.5) ratio = 2.5;
  return Math.ceil(text.length / ratio);
}

/** Role and turn-separator overhead the chat template adds per message. */
export const perMessageOverhead = 4;

export function usageFraction(used: number, contextLength: number): number {
  if (contextLength <= 0) return 0;
  return Math.min(1, Math.max(0, used / contextLength));
}

export const isWarning = (used: number, ctx: number) => usageFraction(used, ctx) > 0.75;
export const isCritical = (used: number, ctx: number) => usageFraction(used, ctx) > 0.9;
export const remainingTokens = (used: number, ctx: number) => Math.max(0, ctx - used);
