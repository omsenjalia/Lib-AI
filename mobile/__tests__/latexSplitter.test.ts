import { splitLatex } from '../src/core/utils/latexSplitter';

// Ported from test/utils/latex_splitter_test.dart. One deliberate change:
// with extractInline off, \( ... \) is normalised to $...$ (the Dart build kept
// it verbatim) so the markdown layer only has one inline syntax to recognise.

const isMath = (s: { kind: string }) => s.kind !== 'text';

describe('block maths', () => {
  it('$$ ... $$ becomes one blockMath segment', () => {
    const s = splitLatex('Area is $$A = \\pi r^2$$ for a circle.');
    expect(s).toHaveLength(3);
    expect(s[1]).toEqual({ kind: 'blockMath', text: 'A = \\pi r^2' });
  });
  it('\\[ ... \\] becomes blockMath', () => {
    const s = splitLatex('Thus \\[ x = \\frac{-b}{2a} \\] holds.');
    expect(s[1]).toEqual({ kind: 'blockMath', text: 'x = \\frac{-b}{2a}' });
  });
  it('\\begin{align} keeps its environment', () => {
    const math = splitLatex('See:\n\\begin{align}a &= b \\\\ c &= d\\end{align}\nDone.').find(isMath)!;
    expect(math.kind).toBe('blockMath');
    expect(math.text).toContain('\\begin{align}');
    expect(math.text).toContain('\\end{align}');
  });
  it('an unterminated $$ falls through as prose', () => {
    const s = splitLatex('Broken $$x = 1');
    expect(s.every((x) => !isMath(x))).toBe(true);
    expect(s[0].text).toBe('Broken $$x = 1');
  });
});

describe('inline maths', () => {
  it('$ ... $ becomes inlineMath', () => {
    const s = splitLatex('The value $x^2$ grows fast.');
    expect(s.map((x) => x.kind)).toEqual(['text', 'inlineMath', 'text']);
    expect(s[1].text).toBe('x^2');
  });
  it('\\( ... \\) becomes inlineMath', () => {
    expect(splitLatex('Given \\(n = 5\\) we proceed.')[1]).toEqual({ kind: 'inlineMath', text: 'n = 5' });
  });
  it('currency is never mistaken for maths', () => {
    const s = splitLatex('It costs $5 and then $10 more.');
    expect(s).toHaveLength(1);
    expect(s[0].kind).toBe('text');
  });
  it('two dollar spans on one line do become maths', () => {
    const maths = splitLatex('We have $a + b$ and $c$.').filter(isMath).map((x) => x.text);
    expect(maths).toEqual(['a + b', 'c']);
  });
  it('a body with a newline is not inline maths', () => {
    expect(splitLatex('Price $5\nand $10').every((x) => !isMath(x))).toBe(true);
  });
});

describe('code is never maths', () => {
  it('fenced block with dollars stays text', () => {
    expect(splitLatex('Use it:\n```bash\necho $PATH and $$ for the pid\n```\n').every((x) => !isMath(x))).toBe(true);
  });
  it('inline code with a dollar stays text', () => {
    expect(splitLatex('The shell variable `$HOME` is set.').every((x) => !isMath(x))).toBe(true);
  });
});

describe('extractInline: false', () => {
  it('leaves inline maths inside the prose', () => {
    const s = splitLatex('The value $x^2$ grows fast.', { extractInline: false });
    expect(s).toHaveLength(1);
    expect(s[0].text).toContain('$x^2$');
  });
  it('normalises \\( ... \\) to dollars', () => {
    expect(splitLatex('Given \\(n = 5\\) we proceed.', { extractInline: false })[0].text).toContain('$n = 5$');
  });
  it('keeps an escaped dollar escaped for the markdown layer', () => {
    expect(splitLatex('A \\$5 fee', { extractInline: false })[0].text).toBe('A \\$5 fee');
  });
  it('still extracts display maths', () => {
    expect(splitLatex('Area $$A = 1$$ here.', { extractInline: false }).map((x) => x.kind)).toEqual([
      'text',
      'blockMath',
      'text',
    ]);
  });
});

describe('forceMath', () => {
  it('bare LaTeX becomes inline maths when forced', () => {
    expect(splitLatex('Compute \\frac{a}{b} now.', { forceMath: true }).find(isMath)).toEqual({
      kind: 'inlineMath',
      text: '\\frac{a}{b}',
    });
  });
  it('is off by default', () => {
    expect(splitLatex('Compute \\frac{a}{b} now.').every((x) => !isMath(x))).toBe(true);
  });
  it('single-letter prose escapes stay prose', () => {
    for (const e of ['n', 't', 'r', 's', 'd', 'w', 'b']) {
      expect(splitLatex(`A \\${e}is escaped.`, { forceMath: true }).every((x) => !isMath(x))).toBe(true);
    }
  });
  it('an unknown command stays prose', () => {
    expect(splitLatex('The \\notacommand{x} here.', { forceMath: true }).every((x) => !isMath(x))).toBe(true);
  });
  it('commands starting with an escape letter are still maths', () => {
    for (const src of ['\\theta = 2', '\\sin x', '\\times 3', '\\to 1']) {
      const maths = splitLatex(src, { forceMath: true }).filter(isMath);
      expect(maths.length).toBeGreaterThan(0);
      expect(maths[0].text.startsWith(src.split(' ')[0])).toBe(true);
    }
  });
  it('fractions count as maths', () => {
    for (const c of ['frac', 'dfrac', 'tfrac', 'binom']) {
      expect(splitLatex(`Compute \\${c}{a}{b} now.`, { forceMath: true }).some(isMath)).toBe(true);
    }
  });
  it('wraps forced maths in dollars when not extracting', () => {
    const s = splitLatex('Compute \\frac{a}{b} now.', { forceMath: true, extractInline: false });
    expect(s).toHaveLength(1);
    expect(s[0].text).toContain('$\\frac{a}{b}$');
  });
  it('an operator continues the forced span', () => {
    const math = splitLatex('So \\alpha + \\beta = \\gamma', { forceMath: true }).find(isMath)!;
    expect(math.text).toContain('\\alpha');
    expect(math.text).toContain('\\gamma');
  });
});

describe('edge cases', () => {
  it('empty input yields one empty text segment', () => {
    expect(splitLatex('')).toEqual([{ kind: 'text', text: '' }]);
  });
  it('empty surrounding runs are dropped', () => {
    expect(splitLatex('$$x$$')).toEqual([{ kind: 'blockMath', text: 'x' }]);
  });
  it('an empty maths body is not maths', () => {
    expect(splitLatex('$$$$').every((x) => !isMath(x))).toBe(true);
  });
});
