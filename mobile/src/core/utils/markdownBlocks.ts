import { splitLatex } from './latexSplitter';

/**
 * Splits a model answer into blocks that each need a different renderer:
 *
 *   fenced code      -> CodeBlock    (syntax highlighting, copy button)
 *   display maths    -> MathBlock    (KaTeX)
 *   <think>...</think> -> ThinkBlock (collapsed reasoning, like hosted chat apps)
 *   everything else  -> ProseBlock   (markdown, with inline $...$ left in place)
 *
 * Pure TypeScript, so the rules are unit tested without a device.
 */
export type MessageBlock =
  | { type: 'prose'; text: string }
  | { type: 'code'; source: string; language: string; complete: boolean }
  | { type: 'math'; latex: string }
  | { type: 'think'; text: string; complete: boolean };

const stripTrailingNewline = (v: string) => (v.endsWith('\n') ? v.slice(0, -1) : v);

function proseBlocks(text: string, forceMath: boolean): MessageBlock[] {
  const out: MessageBlock[] = [];
  for (const segment of splitLatex(text, { forceMath, extractInline: false })) {
    if (segment.kind === 'blockMath') out.push({ type: 'math', latex: segment.text });
    else if (segment.kind === 'inlineMath') out.push({ type: 'prose', text: `$${segment.text}$` });
    else if (segment.text.trim()) out.push({ type: 'prose', text: segment.text });
  }
  return out;
}

/**
 * Reasoning models wrap their scratch work in `<think>` tags. It is split out
 * so the answer reads cleanly and the reasoning is one tap away. An unclosed
 * tag (the normal state while streaming) means everything after it is still
 * reasoning.
 */
export function splitThinking(input: string): { thinking: string | null; thinkingComplete: boolean; answer: string } {
  const open = input.indexOf('<think>');
  if (open === -1) {
    // Some templates open the tag in the prompt, so only the close appears.
    const lonelyClose = input.indexOf('</think>');
    if (lonelyClose !== -1 && !input.slice(0, lonelyClose).includes('```')) {
      return {
        thinking: input.slice(0, lonelyClose).trim(),
        thinkingComplete: true,
        answer: input.slice(lonelyClose + 8).replace(/^\s+/, ''),
      };
    }
    return { thinking: null, thinkingComplete: true, answer: input };
  }
  const before = input.slice(0, open);
  const close = input.indexOf('</think>', open + 7);
  if (close === -1) {
    return { thinking: input.slice(open + 7).trim(), thinkingComplete: false, answer: before };
  }
  return {
    thinking: input.slice(open + 7, close).trim(),
    thinkingComplete: true,
    answer: (before + input.slice(close + 8)).replace(/^\s+/, ''),
  };
}

export function splitMessageBlocks(input: string, opts: { forceMath?: boolean } = {}): MessageBlock[] {
  const forceMath = opts.forceMath ?? false;
  const blocks: MessageBlock[] = [];
  if (!input) return blocks;

  const { thinking, thinkingComplete, answer } = splitThinking(input);
  if (thinking !== null) blocks.push({ type: 'think', text: thinking, complete: thinkingComplete });

  let buffer = '';
  const flushProse = () => {
    const text = buffer;
    buffer = '';
    // Whitespace between blocks is layout, not content.
    if (text.trim()) blocks.push(...proseBlocks(text, forceMath));
  };

  let i = 0;
  while (i < answer.length) {
    if (!answer.startsWith('```', i)) {
      buffer += answer[i];
      i++;
      continue;
    }
    const lineEnd = answer.indexOf('\n', i);
    const language = (lineEnd === -1 ? answer.slice(i + 3) : answer.slice(i + 3, lineEnd)).trim();
    if (lineEnd === -1) {
      // A bare fence at the very end: an unfinished code block must never swallow the message.
      flushProse();
      blocks.push({ type: 'code', source: '', language, complete: false });
      break;
    }
    const close = answer.indexOf('```', lineEnd);
    if (close === -1) {
      // Unterminated fence, the common case while streaming.
      flushProse();
      blocks.push({
        type: 'code',
        source: stripTrailingNewline(answer.slice(lineEnd + 1)),
        language,
        complete: false,
      });
      break;
    }
    flushProse();
    blocks.push({
      type: 'code',
      source: stripTrailingNewline(answer.slice(lineEnd + 1, close)),
      language,
      complete: true,
    });
    i = close + 3;
    const restOfLine = answer.indexOf('\n', i);
    if (restOfLine !== -1 && !answer.slice(i, restOfLine).trim()) i = restOfLine + 1;
  }
  flushProse();
  return blocks;
}

/**
 * While a reply streams, a `$$` that has opened but not closed would show as
 * raw TeX for a moment and then jump into a typeset formula. Hold it back
 * until it closes. Code fences are skipped, since `$$` there is just text.
 */
export function holdOpenDisplayMath(text: string): string {
  let inFence = false;
  let open = -1;
  for (let i = 0; i < text.length; i++) {
    if (text.startsWith('```', i)) {
      inFence = !inFence;
      i += 2;
      continue;
    }
    if (inFence) continue;
    if (text[i] === '\\' && text[i + 1] === '$') {
      i++;
      continue;
    }
    if (text.startsWith('$$', i)) {
      open = open === -1 ? i : -1;
      i++;
    }
  }
  return open === -1 ? text : text.slice(0, open).trimEnd();
}

/** Plain text for the clipboard and exports: no think block, maths as readable text kept as source. */
export function answerText(input: string): string {
  return splitThinking(input).answer;
}
