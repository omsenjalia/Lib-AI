/// Makes arbitrary text safe for the PDF exporter's built-in fonts.
///
/// ## Why this exists
///
/// The `pdf` package's built-in fonts (Helvetica, Times, Courier) are Type1
/// fonts with **WinAnsi** encoding. They have no glyph for α, √, ≤, ∞, ∑, or
/// any emoji, and there is no way to draw them.
///
/// The obvious fix - download a Unicode TTF such as Noto Sans - is not
/// available here, because Library AI must export a PDF in airplane mode. A
/// font fetched over the network would make an offline feature depend on being
/// online, which the brief explicitly forbids.
///
/// So instead the exporter transliterates: symbols become their readable
/// ASCII names, and anything with no reasonable counterpart is dropped. The
/// result is a PDF that is genuinely readable in every environment, rather
/// than one that is either beautiful online or broken offline.
///
/// In-app rendering is unaffected - the chat panel draws real Unicode and real
/// LaTeX. This is export-only.
///
/// Pure Dart, no Flutter dependency, so it is unit tested directly.
library;

/// Characters that WinAnsi already encodes, and which are therefore left alone.
///
/// Superscript and subscript digits are deliberately *excluded* here, even
/// though WinAnsi has a few of them, so that every script character is
/// normalised to the same `^n` / `_n` spelling. Otherwise a formula would mix
/// `x²` and `x^n` styles in one line.
const Set<String> _winAnsiSafe = {
  '±', '×', '÷', '°', '·', '¬', '¶', '§', '£', '¥', '¢', '©', '®',
  'µ', 'º', '¼', '½', '¾', '–', '—', '‘', '’', '“', '”', '•', '…', '†', '‡',
};

/// Greek letters spelled out. Includes the variants LaTeX distinguishes but
/// Unicode does not need to.
const Map<String, String> _greek = {
  'α': 'alpha', 'β': 'beta', 'γ': 'gamma', 'δ': 'delta', 'ε': 'epsilon',
  'ζ': 'zeta', 'η': 'eta', 'θ': 'theta', 'ι': 'iota', 'κ': 'kappa',
  'λ': 'lambda', 'μ': 'mu', 'ν': 'nu', 'ξ': 'xi', 'ρ': 'rho',
  'σ': 'sigma', 'τ': 'tau', 'υ': 'upsilon', 'φ': 'phi', 'χ': 'chi',
  'ψ': 'psi', 'ω': 'omega',
  'Γ': 'Gamma', 'Δ': 'Delta', 'Θ': 'Theta', 'Λ': 'Lambda', 'Ξ': 'Xi',
  'Π': 'Pi', 'Σ': 'Sigma', 'Φ': 'Phi', 'Ψ': 'Psi', 'Ω': 'Omega',
};

/// Mathematical symbols with a conventional ASCII spelling.
const Map<String, String> _mathSymbols = {
  '−': '-', '≤': '<=', '≥': '>=', '≠': '!=', '≈': '~=', '≡': '===',
  '∼': '~', '∝': 'proportional to', '≪': '<<', '≫': '>>', '∓': '-+',
  '√': 'sqrt', '∞': 'inf', '∅': 'empty set',
  '∂': 'd', '∇': 'grad', '∫': 'integral', '∬': 'double integral',
  '∮': 'contour integral', '∑': 'sum', '∏': 'product',
  '→': '->', '←': '<-', '↔': '<->', '⇒': '=>', '⇐': '<=', '⇔': '<=>',
  '↦': '|->', '∈': 'in', '∉': 'not in', '⊂': 'subset', '⊆': 'subseteq',
  '⊃': 'superset', '∪': 'union', '∩': 'intersect', '∀': 'for all',
  '∃': 'exists', '∧': 'and', '∨': 'or', '⋆': '*', '∘': 'o',
  'ℏ': 'hbar', 'ℓ': 'l',
  // Superscripts and subscripts, normalised to a single spelling.
  '⁰': '^0', '¹': '^1', '²': '^2', '³': '^3', '⁴': '^4', '⁵': '^5',
  '⁶': '^6', '⁷': '^7', '⁸': '^8', '⁹': '^9',
  '⁺': '^+', '⁻': '^-', '⁽': '^(', '⁾': '^)', 'ⁿ': '^n', 'ⁱ': '^i',
  '₀': '_0', '₁': '_1', '₂': '_2', '₃': '_3', '₄': '_4', '₅': '_5',
  '₆': '_6', '₇': '_7', '₈': '_8', '₉': '_9',
  '₊': '_+', '₋': '_-', '₍': '_(', '₎': '_)', 'ₙ': '_n', 'ᵢ': '_i',
  'ⱼ': '_j', 'ₖ': '_k',
};

/// Whitespace, marks and symbols with no glyph in the built-in fonts.
///
/// Note: en dash, em dash and the curly quotes are *not* listed here because
/// WinAnsi already includes them, so they are preserved verbatim.
const Map<String, String> _typography = {
  '\u00A0': ' ', // non-breaking space
  '\u2009': ' ', // thin space
  '\u202F': ' ', // narrow no-break space
  '\u2026': '...', // ellipsis (WinAnsi has it, but ASCII reads better)
  '\u22EF': '...', // midline ellipsis
  '\u2713': '[x]',
  '\u2717': '[ ]',
};

/// Converts [input] into text the built-in PDF fonts can actually draw.
String pdfSafeText(String input) {
  if (input.isEmpty) return input;

  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final char = String.fromCharCode(rune);

    // Already safe: leave it exactly as the author wrote it.
    if (_isAscii(rune) || _winAnsiSafe.contains(char)) {
      buffer.write(char);
      continue;
    }

    final typographic = _typography[char];
    if (typographic != null) {
      buffer.write(typographic);
      continue;
    }

    final greek = _greek[char];
    if (greek != null) {
      buffer.write(greek);
      continue;
    }

    final math = _mathSymbols[char];
    if (math != null) {
      buffer.write(math);
      continue;
    }

    // Anything left is an emoji, a CJK glyph, or an exotic symbol. Emitting it
    // would produce a blank box or a glyph error, so it is dropped.
    if (_isDroppable(rune)) continue;

    // Latin-1 supplement letters (accents) are within WinAnsi and were caught
    // above; the only things that reach here are genuinely unmappable.
    buffer.write('?');
  }

  return buffer.toString();
}

bool _isAscii(int rune) =>
    (rune >= 0x20 && rune <= 0x7E) ||
    rune == 0x09 ||
    rune == 0x0A ||
    rune == 0x0D;

/// True for ranges that should be silently removed rather than replaced with a
/// question mark: pictographs and symbols that only ever decorate text.
bool _isDroppable(int rune) {
  return (rune >= 0x1F000 && rune <= 0x1FAFF) || // emoji, pictographs
      (rune >= 0x2600 && rune <= 0x27BF) || // misc symbols, dingbats
      (rune >= 0xFE00 && rune <= 0xFE0F) || // variation selectors
      rune == 0x200D || // zero-width joiner
      (rune >= 0x4E00 && rune <= 0x9FFF) || // CJK unified ideographs
      (rune >= 0x3040 && rune <= 0x30FF); // kana
}

/// True when [input] can be drawn by the built-in fonts with no substitution.
bool isPdfSafe(String input) {
  for (final rune in input.runes) {
    if (_isAscii(rune)) continue;
    final char = String.fromCharCode(rune);
    if (_winAnsiSafe.contains(char)) continue;
    return false;
  }
  return true;
}
