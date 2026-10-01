import { holdOpenDisplayMath, splitMessageBlocks, splitThinking } from '../src/core/utils/markdownBlocks';
import { isKnownLatexCommand, latexToPlainText } from '../src/core/utils/latexToText';
import {
  autoTitleFromMessage,
  formatBytes,
  formatElapsed,
  formatTokenCount,
  formatTokensPerSecond,
  formatDuration,
  formatRelativeTime,
  recencyGroup,
  slugify,
} from '../src/core/utils/formatters';
import { estimateTokens, usageFraction } from '../src/core/utils/tokenEstimator';
import { liveTokensPerSecond } from '../src/core/streamStats';
import { fitsInMemory, kvBytesPer1024Tokens, parseMemAvailable, peakRequirementBytes } from '../src/core/utils/memoryBudget';

describe('splitMessageBlocks', () => {
  it('extracts a fenced block with its language', () => {
    const b = splitMessageBlocks('Before\n```dart\nvoid main() {}\n```\nAfter');
    expect(b.map((x) => x.type)).toEqual(['prose', 'code', 'prose']);
    expect(b[1]).toMatchObject({ language: 'dart', source: 'void main() {}', complete: true });
  });
  it('a fence with no language gives an empty language', () => {
    expect(splitMessageBlocks('```\nplain\n```')).toEqual([
      { type: 'code', source: 'plain', language: '', complete: true },
    ]);
  });
  it('maths inside a fence stays code', () => {
    const b = splitMessageBlocks('```latex\n$$\\frac{a}{b}$$\n```');
    expect(b).toHaveLength(1);
    expect(b[0].type).toBe('code');
  });
  it('an unterminated fence is code to the end (streaming)', () => {
    const b = splitMessageBlocks('Here:\n```python\nprint(1)\nprint(2)');
    expect(b[b.length - 1]).toMatchObject({ type: 'code', source: 'print(1)\nprint(2)', complete: false });
  });
  it('two fences give two code blocks', () => {
    const code = splitMessageBlocks('```js\nvar a = 1;\n```\nand\n```js\nvar b = 2;\n```').filter((x) => x.type === 'code');
    expect(code).toHaveLength(2);
  });
  it('display maths becomes a math block and keeps order', () => {
    const b = splitMessageBlocks('First $$A = \\pi r^2$$ last');
    expect(b.map((x) => x.type)).toEqual(['prose', 'math', 'prose']);
  });
  it('inline maths stays inside the prose', () => {
    expect(splitMessageBlocks('The value $x^2$ grows.')).toEqual([{ type: 'prose', text: 'The value $x^2$ grows.' }]);
  });
  it('markdown structure is untouched', () => {
    const input = '# Heading\n\n- one\n- two\n\n| a | b |\n|---|---|\n| 1 | 2 |';
    expect(splitMessageBlocks(input)).toEqual([{ type: 'prose', text: input }]);
  });
  it('empty and whitespace-only messages give no blocks', () => {
    expect(splitMessageBlocks('')).toEqual([]);
    expect(splitMessageBlocks('   \n\n  ')).toEqual([]);
  });
  it('forceMath wraps bare LaTeX for the prose renderer', () => {
    expect(splitMessageBlocks('Compute \\frac{a}{b} now.', { forceMath: true })[0]).toEqual({
      type: 'prose',
      text: 'Compute $\\frac{a}{b}$ now.',
    });
  });
});

describe('holdOpenDisplayMath', () => {
  it('holds back an unclosed $$ while streaming', () => {
    expect(holdOpenDisplayMath('Then\n\n$$x = \\frac{')).toBe('Then');
  });
  it('leaves closed display maths alone', () => {
    const t = 'A $$x$$ and $$y$$ done';
    expect(holdOpenDisplayMath(t)).toBe(t);
  });
  it('ignores $$ inside code fences', () => {
    const t = '```bash\necho $$\n```\nok';
    expect(holdOpenDisplayMath(t)).toBe(t);
  });
});

describe('thinking', () => {
  it('splits a closed think block from the answer', () => {
    expect(splitThinking('<think>plan it</think>\n\nThe answer.')).toEqual({
      thinking: 'plan it',
      thinkingComplete: true,
      answer: 'The answer.',
    });
  });
  it('an open think block is all reasoning so far', () => {
    expect(splitThinking('<think>still going')).toEqual({ thinking: 'still going', thinkingComplete: false, answer: '' });
  });
  it('handles a template that opened the tag in the prompt', () => {
    expect(splitThinking('reasoning</think>Answer')).toMatchObject({ thinking: 'reasoning', answer: 'Answer' });
  });
  it('becomes the first block', () => {
    expect(splitMessageBlocks('<think>x</think>Hi')[0]).toEqual({ type: 'think', text: 'x', complete: true });
  });
});

describe('latexToPlainText', () => {
  it.each([
    ['\\frac{a}{b}', '(a)/(b)'],
    ['\\frac{\\frac{a}{b}}{c}', '((a)/(b))/(c)'],
    ['\\sqrt{x}', '√(x)'],
    ['\\binom{n}{k}', 'C(n, k)'],
    ['\\text{velocity}', 'velocity'],
    ['\\alpha', 'α'],
    ['\\varepsilon', 'ε'],
    ['\\leq', '≤'],
    ['x^2', 'x²'],
    ['x^{2}', 'x²'],
    ['H_2O', 'H₂O'],
  ])('%s -> %s', (input, expected) => {
    expect(latexToPlainText(input)).toBe(expected);
  });
  it('drops delimiter sizing but keeps the brackets', () => {
    expect(latexToPlainText('\\left(\\frac{b}{2a}\\right)^2')).toBe('((b)/(2a))²');
    expect(latexToPlainText('\\bigl[ x \\bigr]')).toBe('[ x ]');
  });
  it('keeps escaped braces as literal braces', () => {
    expect(latexToPlainText('\\{1, 2\\}')).toBe('{1, 2}');
  });
  it('uses Unicode letter scripts where they exist', () => {
    expect(latexToPlainText('x^{ab}')).toBe('xᵃᵇ');
    expect(latexToPlainText('\\sum_{i=1}^{n} i')).toBe('∑ᵢ₌₁ⁿ i');
    expect(latexToPlainText('e^{-x}')).toBe('e⁻ˣ');
  });
  it('keeps caret notation when a script has no Unicode form', () => {
    expect(latexToPlainText('x^{q}')).toBe('x^(q)');
    expect(latexToPlainText('a_{bc}')).toBe('a_(bc)');
  });
  it('renders blackboard bold, font switches and accents', () => {
    expect(latexToPlainText('\\forall x \\in \\mathbb{R}')).toBe('∀ x ∈ ℝ');
    expect(latexToPlainText('\\mathbb N')).toBe('ℕ');
    expect(latexToPlainText('\\mathcal{L}')).toBe('L');
    expect(latexToPlainText('\\vec{E}')).toBe('E\u20D7');
    expect(latexToPlainText('\\hat x')).toBe('x\u0302');
    expect(latexToPlainText('\\bar{x}')).toBe('x\u0304');
  });
  it('an unknown command keeps its name', () => {
    expect(latexToPlainText('\\foo{x}')).toBe('foox');
  });
  it('knows commands by bare name and rejects prose escapes', () => {
    for (const n of ['alpha', 'pi', 'sum', 'frac', 'sin', 'hat', 'begin']) expect(isKnownLatexCommand(n)).toBe(true);
    for (const n of ['n', 't', 'nis', 'tis', '', '\\theta']) expect(isKnownLatexCommand(n)).toBe(false);
  });
});

describe('formatters', () => {
  it('formats bytes in decimal units', () => {
    expect(formatBytes(999)).toBe('999 B');
    expect(formatBytes(2_490_000_000)).toBe('2.49 GB');
    expect(formatBytes(123_400_000)).toBe('123.4 MB');
  });
  it('formats durations', () => {
    expect(formatDuration(0)).toBe('--');
    expect(formatDuration(45_000)).toBe('45s');
    expect(formatDuration(200_000)).toBe('3m 20s');
    expect(formatDuration(3_600_000)).toBe('1h');
  });
  it('formats relative time', () => {
    const now = new Date(2026, 9, 1, 12, 0).getTime();
    expect(formatRelativeTime(now - 10_000, now)).toBe('just now');
    expect(formatRelativeTime(now - 5 * 60_000, now)).toBe('5m ago');
    expect(formatRelativeTime(new Date(2026, 8, 30, 9).getTime(), now)).toBe('Yesterday');
  });
  it('groups by recency', () => {
    const now = new Date(2026, 9, 1, 12, 0).getTime();
    expect(recencyGroup(now, now)).toBe('Today');
    expect(recencyGroup(new Date(2026, 8, 27).getTime(), now)).toBe('Previous 7 days');
    expect(recencyGroup(new Date(2026, 0, 1).getTime(), now)).toBe('Older');
  });
  it('titles from the first message on a word boundary', () => {
    expect(autoTitleFromMessage('  hello   world ')).toBe('hello world');
    expect(autoTitleFromMessage('Explain the difference between eigenvalues and eigenvectors please')).toBe(
      'Explain the difference between eigenvalues and...',
    );
    expect(autoTitleFromMessage('')).toBe('New chat');
  });
  it('slugifies', () => {
    expect(slugify('Linear Algebra: Week 3!')).toBe('linear-algebra-week-3');
    expect(slugify('???')).toBe('untitled');
  });
});

describe('token estimator', () => {
  it('estimates prose at about four characters per token', () => {
    expect(estimateTokens('a'.repeat(400))).toBe(100);
    expect(estimateTokens('')).toBe(0);
  });
  it('counts code as denser', () => {
    const code = '```\n' + 'a'.repeat(312) + '\n```';
    expect(estimateTokens(code)).toBeGreaterThan(estimateTokens('a'.repeat(code.length)));
  });
  it('clamps the usage fraction', () => {
    expect(usageFraction(5000, 4096)).toBe(1);
    expect(usageFraction(10, 0)).toBe(0);
  });
});

describe('memory budget', () => {
  it('parses MemAvailable', () => {
    expect(parseMemAvailable('MemTotal: 11000000 kB\nMemAvailable:    5242880 kB\n')).toBe(5242880 * 1024);
    expect(parseMemAvailable('MemTotal: 1 kB')).toBeNull();
  });
  it('charges extra KV cache above the recommended context', () => {
    const base = peakRequirementBytes({ requirementGb: 3.4 });
    const bigger = peakRequirementBytes({ requirementGb: 3.4, contextLength: 8192, recommendedContextLength: 4096 });
    expect(bigger - base).toBe(4 * kvBytesPer1024Tokens);
  });
  it('requires headroom', () => {
    expect(fitsInMemory(1150, 1000)).toBe(true);
    expect(fitsInMemory(1100, 1000)).toBe(false);
  });
});

describe('Claude Code-style token readout', () => {
  it('abbreviates token counts', () => {
    expect(formatTokenCount(203)).toBe('203');
    expect(formatTokenCount(1234)).toBe('1.2k');
    expect(formatTokenCount(1000)).toBe('1k');
    expect(formatTokenCount(12_400)).toBe('12k');
    expect(formatTokenCount(1_100_000)).toBe('1.1M');
  });
  it('formats speed and elapsed time', () => {
    expect(formatTokensPerSecond(41.23)).toBe('41.2 tok/s');
    expect(formatTokensPerSecond(118.4)).toBe('118 tok/s');
    expect(formatTokensPerSecond(0)).toBe('-- tok/s');
    expect(formatElapsed(4900)).toBe('4.9s');
    expect(formatElapsed(23_000)).toBe('23s');
    expect(formatElapsed(65_000)).toBe('1m 05s');
  });
  it('measures decode speed from the first token, not from send', () => {
    const s = { startedAt: 0, firstTokenAt: 2000, tokens: 41, promptTokens: 900 };
    // 40 tokens after the first, over 1 s; the 2 s of prompt reading is excluded.
    expect(liveTokensPerSecond(s, 3000)).toBe(40);
    expect(liveTokensPerSecond({ ...s, firstTokenAt: null }, 3000)).toBeNull();
    expect(liveTokensPerSecond({ ...s, tokens: 1 }, 3000)).toBeNull();
  });
});
