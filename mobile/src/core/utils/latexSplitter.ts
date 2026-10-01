import { isKnownLatexCommand } from './latexToText';

/**
 * Splits text into prose and maths segments.
 *
 * Rules carried over from the Flutter build, each of which fixed a real bug:
 * - fenced and inline code are never scanned for maths;
 * - inline `$...$` must start and end with a non-space and stay on one line,
 *   which is what stops "costs $5 and then $10" becoming an equation;
 * - `\$` is a literal dollar;
 * - with `forceMath`, a bare `\command` is only maths if the command is known.
 */
export type SegmentKind = 'text' | 'inlineMath' | 'blockMath';
export type LatexSegment = { text: string; kind: SegmentKind };

const isRun = (input: string, index: number, n: number, char: string) => {
  if (index + n > input.length) return false;
  for (let k = 0; k < n; k++) if (input[index + k] !== char) return false;
  return true;
};

function findInlineDollarClose(input: string, start: number): number {
  let j = start;
  while (j < input.length) {
    const c = input[j];
    if (c === '\n') return -1;
    if (c === '\\') {
      j += 2;
      continue;
    }
    if (c === '$') {
      const body = input.slice(start, j);
      if (!body || body !== body.trim()) return -1;
      return j;
    }
    j++;
  }
  return -1;
}

function looksLikeCommand(input: string, index: number): boolean {
  const match = /^[a-zA-Z]+/.exec(input.slice(index + 1));
  return match !== null && isKnownLatexCommand(match[0]);
}

const spanContinuations = new Set(['+', '-', '=', '<', '>', '/', '*', '^', '_', '\\']);

function nextNonSpace(input: string, index: number): string | null {
  for (let k = index; k < input.length; k++) if (input[k] !== ' ') return input[k];
  return null;
}

function bareLatexEnd(input: string, index: number): number {
  let j = index;
  let depth = 0;
  while (j < input.length) {
    const c = input[j];
    if (c === '{') depth++;
    else if (c === '}') {
      depth--;
      if (depth < 0) break;
    } else if (c === '\n' && depth === 0) break;
    else if ((c === ' ' || c === '&' || c === ';') && depth === 0) {
      // `\alpha + \beta = \gamma` stays one formula.
      const next = nextNonSpace(input, j);
      if (next === null || !spanContinuations.has(next)) break;
    }
    j++;
  }
  return j;
}

export function splitLatex(
  input: string,
  opts: { forceMath?: boolean; extractInline?: boolean } = {},
): LatexSegment[] {
  const forceMath = opts.forceMath ?? false;
  const extractInline = opts.extractInline ?? true;
  if (!input) return [{ text: '', kind: 'text' }];

  const segments: LatexSegment[] = [];
  let buffer = '';
  const flush = () => {
    if (buffer) {
      segments.push({ text: buffer, kind: 'text' });
      buffer = '';
    }
  };

  let i = 0;
  let inFence = false;
  let inInlineCode = false;
  while (i < input.length) {
    const ch = input[i];

    if (ch === '`' && isRun(input, i, 3, '`')) {
      const fenceEnd = input.indexOf('```', i + 3);
      if (fenceEnd === -1) {
        buffer += input.slice(i);
        i = input.length;
        break;
      }
      buffer += input.slice(i, fenceEnd + 3);
      i = fenceEnd + 3;
      inFence = !inFence;
      continue;
    }
    if (inFence) {
      buffer += ch;
      i++;
      continue;
    }
    if (ch === '`' && !isRun(input, i, 2, '`')) {
      inInlineCode = !inInlineCode;
      buffer += ch;
      i++;
      continue;
    }
    if (inInlineCode || ch === '\n') {
      buffer += ch;
      i++;
      continue;
    }

    if (ch === '\\' && input[i + 1] === '$') {
      // Kept escaped when inline maths stays in the prose, so the markdown
      // layer does not mistake it for a delimiter; unescaped otherwise.
      buffer += extractInline ? '$' : '\\$';
      i += 2;
      continue;
    }

    if (ch === '$' && isRun(input, i, 2, '$')) {
      const close = input.indexOf('$$', i + 2);
      if (close !== -1) {
        const body = input.slice(i + 2, close);
        if (body.trim()) {
          flush();
          segments.push({ text: body.trim(), kind: 'blockMath' });
          i = close + 2;
          continue;
        }
      }
    }

    if (ch === '\\' && input[i + 1] === '[') {
      const close = input.indexOf('\\]', i + 2);
      if (close !== -1) {
        flush();
        segments.push({ text: input.slice(i + 2, close).trim(), kind: 'blockMath' });
        i = close + 2;
        continue;
      }
    }

    if (ch === '\\' && input[i + 1] === '(') {
      const close = input.indexOf('\\)', i + 2);
      if (close !== -1) {
        if (!extractInline) {
          // Normalise to `$...$` so the prose renderer has one syntax to handle.
          buffer += `$${input.slice(i + 2, close).trim()}$`;
        } else {
          flush();
          segments.push({ text: input.slice(i + 2, close).trim(), kind: 'inlineMath' });
        }
        i = close + 2;
        continue;
      }
    }

    if (ch === '\\' && input.startsWith('\\begin{', i)) {
      const envEnd = input.indexOf('}', i + 7);
      if (envEnd !== -1) {
        const env = input.slice(i + 7, envEnd);
        const closeTag = `\\end{${env}}`;
        const close = input.indexOf(closeTag, envEnd);
        if (close !== -1) {
          flush();
          segments.push({ text: input.slice(i, close + closeTag.length), kind: 'blockMath' });
          i = close + closeTag.length;
          continue;
        }
      }
    }

    if (ch === '$') {
      const close = findInlineDollarClose(input, i + 1);
      if (close !== -1) {
        if (!extractInline) {
          buffer += input.slice(i, close + 1);
        } else {
          flush();
          segments.push({ text: input.slice(i + 1, close).trim(), kind: 'inlineMath' });
        }
        i = close + 1;
        continue;
      }
    }

    if (forceMath && ch === '\\' && looksLikeCommand(input, i)) {
      const end = bareLatexEnd(input, i);
      if (end > i) {
        if (!extractInline) {
          buffer += `$${input.slice(i, end).trim()}$`;
        } else {
          flush();
          segments.push({ text: input.slice(i, end).trim(), kind: 'inlineMath' });
        }
        i = end;
        continue;
      }
    }

    buffer += ch;
    i++;
  }
  flush();

  if (segments.length > 1 && segments[0].kind === 'text' && !segments[0].text.trim()) segments.shift();
  const last = segments[segments.length - 1];
  if (segments.length > 1 && last.kind === 'text' && !last.text.trim()) segments.pop();
  return segments;
}
