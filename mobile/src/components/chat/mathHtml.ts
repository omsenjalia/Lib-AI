import katex from 'katex';

/**
 * Display maths, typeset by KaTeX in pure JavaScript. The HTML output is drawn
 * with KaTeX's own fonts (inlined in katexCss.generated.ts), so formulas look
 * the same on every device and delimiters stretch properly, offline. A hidden
 * MathML copy rides along for screen readers.
 */
export function renderDisplayMath(latex: string): { html: string; ok: boolean } {
  try {
    return {
      html: katex.renderToString(latex, { displayMode: true, output: 'htmlAndMathml', throwOnError: true, strict: 'ignore' }),
      ok: true,
    };
  } catch {
    return { html: '', ok: false };
  }
}
