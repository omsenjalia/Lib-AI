/**
 * LaTeX to readable Unicode text.
 *
 * Used for inline maths on screen (React Native has no inline TeX renderer, and
 * a WebView per `$x$` would be absurd) and for plain-text exports. Display maths
 * is typeset properly by KaTeX; see MathBlock.
 *
 * `\frac{a}{b}` becomes `(a)/(b)`, `x^2` becomes `x²`, `\alpha` becomes `α`.
 */
const symbols: Record<string, string> = {
  '\\alpha': 'α', '\\beta': 'β', '\\gamma': 'γ', '\\delta': 'δ', '\\epsilon': 'ε',
  '\\varepsilon': 'ε', '\\zeta': 'ζ', '\\eta': 'η', '\\theta': 'θ', '\\iota': 'ι',
  '\\kappa': 'κ', '\\lambda': 'λ', '\\mu': 'μ', '\\nu': 'ν', '\\xi': 'ξ', '\\pi': 'π',
  '\\rho': 'ρ', '\\sigma': 'σ', '\\tau': 'τ', '\\upsilon': 'υ', '\\phi': 'φ',
  '\\varphi': 'φ', '\\chi': 'χ', '\\psi': 'ψ', '\\omega': 'ω',
  '\\Gamma': 'Γ', '\\Delta': 'Δ', '\\Theta': 'Θ', '\\Lambda': 'Λ', '\\Xi': 'Ξ',
  '\\Pi': 'Π', '\\Sigma': 'Σ', '\\Phi': 'Φ', '\\Psi': 'Ψ', '\\Omega': 'Ω',
  '\\pm': '±', '\\mp': '∓', '\\times': '×', '\\div': '÷', '\\cdot': '·', '\\ast': '*',
  '\\star': '⋆', '\\circ': '∘', '\\bullet': '•', '\\le': '≤', '\\leq': '≤', '\\ge': '≥',
  '\\geq': '≥', '\\neq': '≠', '\\ne': '≠', '\\approx': '≈', '\\equiv': '≡', '\\sim': '∼',
  '\\propto': '∝', '\\ll': '≪', '\\gg': '≫',
  '\\to': '→', '\\rightarrow': '→', '\\leftarrow': '←', '\\leftrightarrow': '↔',
  '\\Rightarrow': '⇒', '\\Leftarrow': '⇐', '\\Leftrightarrow': '⇔', '\\mapsto': '↦',
  '\\sum': '∑', '\\prod': '∏', '\\int': '∫', '\\iint': '∬', '\\oint': '∮',
  '\\partial': '∂', '\\nabla': '∇', '\\infty': '∞', '\\sqrt': '√',
  '\\in': '∈', '\\notin': '∉', '\\subset': '⊂', '\\subseteq': '⊆', '\\supset': '⊃',
  '\\cup': '∪', '\\cap': '∩', '\\emptyset': '∅', '\\varnothing': '∅', '\\forall': '∀',
  '\\exists': '∃', '\\neg': '¬', '\\land': '∧', '\\lor': '∨',
  '\\degree': '°', '\\hbar': 'ℏ', '\\ell': 'ℓ', '\\dots': '…', '\\ldots': '…',
  '\\cdots': '⋯', '\\quad': ' ', '\\qquad': '  ',
};

// Every character Unicode has a superscript or subscript form for. A script is
// converted only when all of its characters are covered; otherwise it falls
// back to ^(...) / _(...) so nothing is silently dropped.
const superscripts: Record<string, string> = {
  '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴', '5': '⁵', '6': '⁶', '7': '⁷',
  '8': '⁸', '9': '⁹', '+': '⁺', '-': '⁻', '=': '⁼', '(': '⁽', ')': '⁾',
  a: 'ᵃ', b: 'ᵇ', c: 'ᶜ', d: 'ᵈ', e: 'ᵉ', f: 'ᶠ', g: 'ᵍ', h: 'ʰ', i: 'ⁱ', j: 'ʲ',
  k: 'ᵏ', l: 'ˡ', m: 'ᵐ', n: 'ⁿ', o: 'ᵒ', p: 'ᵖ', r: 'ʳ', s: 'ˢ', t: 'ᵗ', u: 'ᵘ',
  v: 'ᵛ', w: 'ʷ', x: 'ˣ', y: 'ʸ', z: 'ᶻ',
  A: 'ᴬ', B: 'ᴮ', D: 'ᴰ', E: 'ᴱ', G: 'ᴳ', H: 'ᴴ', I: 'ᴵ', J: 'ᴶ', K: 'ᴷ', L: 'ᴸ',
  M: 'ᴹ', N: 'ᴺ', O: 'ᴼ', P: 'ᴾ', R: 'ᴿ', T: 'ᵀ', U: 'ᵁ', V: 'ⱽ', W: 'ᵂ',
  'α': 'ᵅ', 'β': 'ᵝ', 'γ': 'ᵞ', 'δ': 'ᵟ', 'ε': 'ᵋ', 'θ': 'ᶿ', 'φ': 'ᵠ', 'χ': 'ᵡ',
  '′': '′', '∗': '*', '*': '*',
};

const subscripts: Record<string, string> = {
  '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄', '5': '₅', '6': '₆', '7': '₇',
  '8': '₈', '9': '₉', '+': '₊', '-': '₋', '=': '₌', '(': '₍', ')': '₎',
  a: 'ₐ', e: 'ₑ', h: 'ₕ', i: 'ᵢ', j: 'ⱼ', k: 'ₖ', l: 'ₗ', m: 'ₘ', n: 'ₙ', o: 'ₒ',
  p: 'ₚ', r: 'ᵣ', s: 'ₛ', t: 'ₜ', u: 'ᵤ', v: 'ᵥ', x: 'ₓ',
  'β': 'ᵦ', 'γ': 'ᵧ', 'ρ': 'ᵨ', 'φ': 'ᵩ', 'χ': 'ᵪ',
};

/** \mathbb letters with a Unicode double-struck form. */
const blackboard: Record<string, string> = {
  N: 'ℕ', Z: 'ℤ', Q: 'ℚ', R: 'ℝ', C: 'ℂ', P: 'ℙ', H: 'ℍ', E: '𝔼', F: '𝔽', '1': '𝟙',
};

/** Accents become combining marks on the last character of their argument. */
const accents: Record<string, string> = {
  '\\vec': '\u20D7', '\\hat': '\u0302', '\\widehat': '\u0302', '\\bar': '\u0304', '\\overline': '\u0305',
  '\\dot': '\u0307', '\\ddot': '\u0308', '\\tilde': '\u0303', '\\widetilde': '\u0303',
};

const transparentCommands = [
  '\\text', '\\textrm', '\\textbf', '\\textit', '\\mathrm', '\\mathbf', '\\mathit',
  '\\operatorname', '\\mbox', '\\boldsymbol', '\\bm', '\\bf', '\\it', '\\mathcal',
  '\\mathfrak', '\\mathsf', '\\mathtt', '\\underline', '\\boxed',
];

const structuralCommands = [
  'frac', 'dfrac', 'tfrac', 'cfrac', 'binom',
  'begin', 'end', 'left', 'right', 'limits', 'displaystyle', 'textstyle', 'overbrace',
  'underbrace', 'stackrel', 'overset', 'underset', 'boxed', 'cancel', 'color', 'nonumber',
  'pmod', 'mod', 'choose', 'sideset',
  'sin', 'cos', 'tan', 'cot', 'sec', 'csc', 'arcsin', 'arccos', 'arctan', 'sinh', 'cosh',
  'tanh', 'log', 'ln', 'exp', 'lim', 'max', 'min', 'gcd', 'sup', 'inf', 'det', 'dim', 'ker',
  'deg', 'arg', 'hom', 'Pr',
  'hat', 'widehat', 'tilde', 'widetilde', 'bar', 'overline', 'underline', 'vec', 'dot',
  'ddot', 'acute', 'grave', 'breve', 'check', 'mathring',
  'mathbb', 'mathcal', 'mathfrak', 'mathsf', 'mathtt', 'bm',
  'xrightarrow', 'xleftarrow', 'mathrel', 'mathbin', 'mathop', 'prec', 'succ', 'preceq',
  'succeq', 'subsetneq', 'supseteq', 'nmid', 'cong', 'asymp', 'doteq', 'triangle', 'angle',
  'prime', 'mid', 'parallel', 'perp', 'backslash', 'vert', 'Vert', 'lvert', 'rvert', 'lVert',
  'rVert',
];

const knownCommandNames = new Set<string>([
  ...Object.keys(symbols).map((c) => c.slice(1)),
  ...transparentCommands.map((c) => c.slice(1)),
  ...structuralCommands,
]);

/**
 * Whether `name` (without the backslash) is a LaTeX command the app knows.
 * The splitter uses it to tell `\sin` from `\nis` (a newline escape before "is").
 */
export function isKnownLatexCommand(name: string): boolean {
  return knownCommandNames.has(name);
}

export const knownLatexCommandCount = () => knownCommandNames.size;

function matchBrace(input: string, open: number): number {
  if (open >= input.length || input[open] !== '{') return -1;
  let depth = 0;
  for (let i = open; i < input.length; i++) {
    const c = input[i];
    if (c === '\\') {
      i++;
      continue;
    }
    if (c === '{') depth++;
    if (c === '}') {
      depth--;
      if (depth === 0) return i;
    }
  }
  return -1;
}

function rewriteBinary(input: string, command: string, fn: (a: string, b: string) => string): string {
  let result = input;
  for (let guard = 0; guard < 64; guard++) {
    const start = result.indexOf(`${command}{`);
    if (start === -1) return result;
    const firstOpen = start + command.length;
    const firstClose = matchBrace(result, firstOpen);
    if (firstClose === -1) return result;
    const secondOpen = firstClose + 1;
    const secondClose = matchBrace(result, secondOpen);
    if (secondClose === -1) return result;
    const a = result.slice(firstOpen + 1, firstClose);
    const b = result.slice(secondOpen + 1, secondClose);
    result = result.slice(0, start) + fn(a, b) + result.slice(secondClose + 1);
  }
  return result;
}

function toSuperscript(body: string): string {
  return [...body].map((c) => superscripts[c] ?? c).join('');
}

function rewriteSquareRoot(input: string): string {
  let result = input;
  for (let guard = 0; guard < 64; guard++) {
    const start = result.indexOf('\\sqrt');
    if (start === -1) return result;
    let index = start + '\\sqrt'.length;
    let indexText: string | null = null;
    if (result[index] === '[') {
      const close = result.indexOf(']', index);
      if (close === -1) return result;
      indexText = result.slice(index + 1, close);
      index = close + 1;
    }
    const close = matchBrace(result, index);
    if (close === -1) return result;
    const body = result.slice(index + 1, close);
    const replacement = indexText === null ? `√(${body})` : `${toSuperscript(indexText)}√(${body})`;
    result = result.slice(0, start) + replacement + result.slice(close + 1);
  }
  return result;
}

function toScript(body: string, table: Record<string, string>): string | null {
  let out = '';
  for (const c of body) {
    const mapped = table[c];
    if (mapped === undefined) return null;
    out += mapped;
  }
  return out || null;
}

function rewriteScripts(input: string, marker: string, table: Record<string, string>): string {
  let out = '';
  let i = 0;
  while (i < input.length) {
    const ch = input[i];
    if (ch !== marker || i + 1 >= input.length) {
      out += ch;
      i++;
      continue;
    }
    let body: string;
    let consumedTo: number;
    if (input[i + 1] === '{') {
      const close = matchBrace(input, i + 1);
      if (close === -1) {
        out += ch;
        i++;
        continue;
      }
      body = input.slice(i + 2, close);
      consumedTo = close;
    } else {
      body = input[i + 1];
      consumedTo = i + 1;
    }
    const converted = toScript(body, table);
    out += converted ?? `${marker}(${body})`;
    i = consumedTo + 1;
  }
  return out;
}

function replaceCommand(input: string, command: string, replacement: string): string {
  let out = '';
  let i = 0;
  while (i < input.length) {
    if (input.startsWith(command, i)) {
      const after = i + command.length;
      const next = after < input.length ? input[after] : '';
      // A letter right after means this is a longer command name.
      if (!/[a-zA-Z]/.test(next)) {
        out += replacement;
        i = after;
        continue;
      }
    }
    out += input[i];
    i++;
  }
  return out;
}

/** `\\cmd{body}` or `\\cmd x` rewritten through `fn`. Longer command names are left alone. */
function rewriteMapped(input: string, command: string, fn: (body: string) => string): string {
  let result = input;
  let from = 0;
  for (let guard = 0; guard < 64; guard++) {
    const start = result.indexOf(command, from);
    if (start === -1) return result;
    let i = start + command.length;
    if (/[a-zA-Z]/.test(result[i] ?? '')) {
      from = i;
      continue;
    }
    while (result[i] === ' ') i++;
    let body: string;
    let end: number;
    if (result[i] === '{') {
      const close = matchBrace(result, i);
      if (close === -1) return result;
      body = result.slice(i + 1, close);
      end = close + 1;
    } else if (i < result.length) {
      body = result[i];
      end = i + 1;
    } else {
      return result;
    }
    const replacement = fn(body);
    result = result.slice(0, start) + replacement + result.slice(end);
    from = start + replacement.length;
  }
  return result;
}

function unwrapCommand(input: string, command: string): string {
  let result = input;
  for (let guard = 0; guard < 64; guard++) {
    const start = result.indexOf(`${command}{`);
    if (start === -1) return result;
    const open = start + command.length;
    const close = matchBrace(result, open);
    if (close === -1) return result;
    result = result.slice(0, start) + result.slice(open + 1, close) + result.slice(close + 1);
  }
  return result;
}

const sortedSymbolKeys = Object.keys(symbols).sort((a, b) => b.length - a.length);

export function latexToPlainText(latex: string): string {
  let out = latex;
  out = out.replace(/\\begin\{[a-zA-Z*]+\}/g, '').replace(/\\end\{[a-zA-Z*]+\}/g, '');
  // Delimiter sizing only changes how tall a bracket is drawn: keep the bracket.
  out = out.replace(/\\(?:left|right|middle|[Bb]igg?[lr]?)(?![a-zA-Z])\s*\.?/g, '');
  out = out.replace(/\\([{}])/g, (_, b: string) => (b === '{' ? '⦃' : '⦄'));
  out = out.split('\\\\').join(' ');
  for (const cmd of ['\\frac', '\\dfrac', '\\tfrac']) out = rewriteBinary(out, cmd, (a, b) => `(${a})/(${b})`);
  out = rewriteBinary(out, '\\binom', (a, b) => `C(${a}, ${b})`);
  out = rewriteSquareRoot(out);
  out = rewriteMapped(out, '\\mathbb', (body) => [...body].map((c) => blackboard[c] ?? c).join(''));
  for (const [cmd, mark] of Object.entries(accents)) out = rewriteMapped(out, cmd, (body) => body + mark);
  for (const cmd of transparentCommands) out = unwrapCommand(out, cmd);
  // Longest first so \leq is not half-consumed by \le.
  for (const key of sortedSymbolKeys) out = replaceCommand(out, key, symbols[key]);
  out = out
    .split('\\,').join(' ')
    .split('\\;').join(' ')
    .split('\\!').join('')
    .split('\\:').join(' ')
    .split('\\ ').join(' ');
  out = rewriteScripts(out, '^', superscripts);
  out = rewriteScripts(out, '_', subscripts);
  // An unknown command keeps its name, so `\foo{x}` reads `foo(x)` rather than vanishing.
  out = out.replace(/\\([a-zA-Z]+)/g, '$1');
  out = out.replace(/[{}]/g, '');
  // Escaped braces were parked as placeholders so the grouping-brace sweep left them alone.
  out = out.replace(/⦃/g, '{').replace(/⦄/g, '}');
  return out.replace(/[ \t]{2,}/g, ' ').trim();
}
