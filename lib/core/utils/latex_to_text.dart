/// Converts LaTeX into readable plain text.
///
/// The `pdf` package cannot typeset LaTeX - it has no glyph run for math
/// layout. Rather than dumping raw `\frac{-b \pm \sqrt{b^2-4ac}}{2a}` into an
/// exported PDF, the exporter runs formulae through this first and gets
/// `(-b ± √(b²-4ac))/(2a)`, which a human can actually read.
///
/// This is a lossy readability transform, not a typesetter. On-screen rendering
/// is done properly by the math renderer; this exists purely for export.
///
/// Pure Dart, no Flutter dependency, so it is unit tested directly.
library;

const Map<String, String> _symbols = {
  // Greek, lower case
  r'\alpha': 'α',
  r'\beta': 'β',
  r'\gamma': 'γ',
  r'\delta': 'δ',
  r'\epsilon': 'ε',
  r'\varepsilon': 'ε',
  r'\zeta': 'ζ',
  r'\eta': 'η',
  r'\theta': 'θ',
  r'\iota': 'ι',
  r'\kappa': 'κ',
  r'\lambda': 'λ',
  r'\mu': 'μ',
  r'\nu': 'ν',
  r'\xi': 'ξ',
  r'\pi': 'π',
  r'\rho': 'ρ',
  r'\sigma': 'σ',
  r'\tau': 'τ',
  r'\upsilon': 'υ',
  r'\phi': 'φ',
  r'\varphi': 'φ',
  r'\chi': 'χ',
  r'\psi': 'ψ',
  r'\omega': 'ω',
  // Greek, upper case
  r'\Gamma': 'Γ',
  r'\Delta': 'Δ',
  r'\Theta': 'Θ',
  r'\Lambda': 'Λ',
  r'\Xi': 'Ξ',
  r'\Pi': 'Π',
  r'\Sigma': 'Σ',
  r'\Phi': 'Φ',
  r'\Psi': 'Ψ',
  r'\Omega': 'Ω',
  // Operators and relations
  r'\pm': '±',
  r'\mp': '∓',
  r'\times': '×',
  r'\div': '÷',
  r'\cdot': '·',
  r'\ast': '*',
  r'\star': '⋆',
  r'\circ': '∘',
  r'\bullet': '•',
  r'\le': '≤',
  r'\leq': '≤',
  r'\ge': '≥',
  r'\geq': '≥',
  r'\neq': '≠',
  r'\ne': '≠',
  r'\approx': '≈',
  r'\equiv': '≡',
  r'\sim': '∼',
  r'\propto': '∝',
  r'\ll': '≪',
  r'\gg': '≫',
  // Arrows
  r'\to': '→',
  r'\rightarrow': '→',
  r'\leftarrow': '←',
  r'\leftrightarrow': '↔',
  r'\Rightarrow': '⇒',
  r'\Leftarrow': '⇐',
  r'\Leftrightarrow': '⇔',
  r'\mapsto': '↦',
  // Big operators
  r'\sum': '∑',
  r'\prod': '∏',
  r'\int': '∫',
  r'\iint': '∬',
  r'\oint': '∮',
  r'\partial': '∂',
  r'\nabla': '∇',
  r'\infty': '∞',
  r'\sqrt': '√',
  // Set theory and logic
  r'\in': '∈',
  r'\notin': '∉',
  r'\subset': '⊂',
  r'\subseteq': '⊆',
  r'\supset': '⊃',
  r'\cup': '∪',
  r'\cap': '∩',
  r'\emptyset': '∅',
  r'\varnothing': '∅',
  r'\forall': '∀',
  r'\exists': '∃',
  r'\neg': '¬',
  r'\land': '∧',
  r'\lor': '∨',
  // Misc
  r'\degree': '°',
  r'\hbar': 'ℏ',
  r'\ell': 'ℓ',
  r'\dots': '…',
  r'\ldots': '…',
  r'\cdots': '⋯',
  r'\quad': ' ',
  r'\qquad': '  ',
};

const Map<String, String> _superscripts = {
  '0': '⁰',
  '1': '¹',
  '2': '²',
  '3': '³',
  '4': '⁴',
  '5': '⁵',
  '6': '⁶',
  '7': '⁷',
  '8': '⁸',
  '9': '⁹',
  '+': '⁺',
  '-': '⁻',
  '(': '⁽',
  ')': '⁾',
  'n': 'ⁿ',
  'i': 'ⁱ',
};

const Map<String, String> _subscripts = {
  '0': '₀',
  '1': '₁',
  '2': '₂',
  '3': '₃',
  '4': '₄',
  '5': '₅',
  '6': '₆',
  '7': '₇',
  '8': '₈',
  '9': '₉',
  '+': '₊',
  '-': '₋',
  '(': '₍',
  ')': '₎',
  'n': 'ₙ',
  'i': 'ᵢ',
  'j': 'ⱼ',
  'k': 'ₖ',
};

/// Commands whose sole braced argument should be kept verbatim.
const Set<String> _transparentCommands = {
  r'\text',
  r'\textrm',
  r'\mathrm',
  r'\mathbf',
  r'\mathit',
  r'\operatorname',
  r'\mbox',
  r'\boldsymbol',
  r'\bf',
  r'\it',
};

/// Environments that are structural rather than symbolic.
const List<String> _environmentNames = [
  'matrix',
  'pmatrix',
  'bmatrix',
  'vmatrix',
  'cases',
  'aligned',
  'align',
  'array',
  'equation',
  'gather',
];

/// Converts a LaTeX fragment to a readable plain-text approximation.
String latexToPlainText(String latex) {
  var out = latex;

  // Drop display/env wrappers first so their contents are processed normally.
  out = out.replaceAll(RegExp(r'\\begin\{[a-zA-Z*]+\}'), '');
  out = out.replaceAll(RegExp(r'\\end\{[a-zA-Z*]+\}'), '');
  out = out.replaceAll(r'\\', ' '); // row separator inside matrices

  // \frac{a}{b} -> (a)/(b), innermost first so nested fractions work.
  out = _rewriteBinary(
    out,
    r'\frac',
    (a, b) => '($a)/($b)',
  );
  out = _rewriteBinary(
    out,
    r'\dfrac',
    (a, b) => '($a)/($b)',
  );
  out = _rewriteBinary(
    out,
    r'\tfrac',
    (a, b) => '($a)/($b)',
  );
  out = _rewriteBinary(
    out,
    r'\binom',
    (a, b) => 'C($a, $b)',
  );

  // \sqrt[n]{x} -> ⁿ√(x); \sqrt{x} -> √(x)
  out = _rewriteSquareRoot(out);

  // \text{...} and friends keep their contents, minus the braces.
  for (final command in _transparentCommands) {
    out = _unwrapCommand(out, command);
  }

  // Symbol commands. Longest first so \varepsilon wins over \varepsilon's
  // prefix and \leq is not half-consumed by \le.
  final keys = _symbols.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final key in keys) {
    out = _replaceCommand(out, key, _symbols[key]!);
  }

  // Spacing macros.
  out = out
      .replaceAll(r'\,', ' ')
      .replaceAll(r'\;', ' ')
      .replaceAll(r'\!', '')
      .replaceAll(r'\:', ' ')
      .replaceAll('\\ ', ' ');

  // Superscripts and subscripts.
  out = _rewriteScripts(out, '^', _superscripts, '^');
  out = _rewriteScripts(out, '_', _subscripts, '_');

  // Any command we did not recognise: keep its name rather than the backslash,
  // so `\foo{x}` becomes `foo(x)` instead of silently vanishing.
  out = out.replaceAllMapped(
    RegExp(r'\\([a-zA-Z]+)'),
    (m) => m.group(1)!,
  );

  // Leftover grouping braces are noise in prose.
  out = out.replaceAll('{', '').replaceAll('}', '');

  // Collapse the whitespace the removals leave behind.
  out = out.replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
  return out;
}

/// Rewrites `\command{a}{b}` into `fn(a, b)`, innermost first.
String _rewriteBinary(String input, String command, String Function(String, String) fn) {
  var result = input;
  // Bound the loop: each pass strictly shrinks the number of commands, but a
  // malformed input should not spin forever.
  for (var guard = 0; guard < 64; guard++) {
    final start = result.indexOf('$command{');
    if (start == -1) return result;

    final firstOpen = start + command.length;
    final firstClose = _matchBrace(result, firstOpen);
    if (firstClose == -1) return result;

    final secondOpen = firstClose + 1;
    final secondClose = _matchBrace(result, secondOpen);
    if (secondClose == -1) return result;

    final a = result.substring(firstOpen + 1, firstClose);
    final b = result.substring(secondOpen + 1, secondClose);
    result = result.substring(0, start) + fn(a, b) + result.substring(secondClose + 1);
  }
  return result;
}

/// Rewrites `\sqrt{x}` and `\sqrt[n]{x}`.
String _rewriteSquareRoot(String input) {
  var result = input;
  for (var guard = 0; guard < 64; guard++) {
    final start = result.indexOf(r'\sqrt');
    if (start == -1) return result;

    var index = start + r'\sqrt'.length;
    String? indexText;

    if (index < result.length && result[index] == '[') {
      final close = result.indexOf(']', index);
      if (close == -1) return result;
      indexText = result.substring(index + 1, close);
      index = close + 1;
    }

    final open = index;
    final close = _matchBrace(result, open);
    if (close == -1) return result;

    final body = result.substring(open + 1, close);
    final replacement = indexText == null
        ? '√($body)'
        : '${_toSuperscript(indexText)}√($body)';
    result = result.substring(0, start) + replacement + result.substring(close + 1);
  }
  return result;
}

/// Rewrites `^{...}` / `^x` and `_{...}` / `_x` into Unicode scripts.
///
/// Falls back to the plain marker when a character has no Unicode counterpart,
/// so `x^{ab}` becomes `x^(ab)` rather than losing information.
String _rewriteScripts(
  String input,
  String marker,
  Map<String, String> table,
  String fallbackMarker,
) {
  final buffer = StringBuffer();
  var i = 0;

  while (i < input.length) {
    final ch = input[i];
    if (ch != marker || i + 1 >= input.length) {
      buffer.write(ch);
      i++;
      continue;
    }

    final next = input[i + 1];
    String body;
    var consumedTo = i + 1;

    if (next == '{') {
      final close = _matchBrace(input, i + 1);
      if (close == -1) {
        buffer.write(ch);
        i++;
        continue;
      }
      body = input.substring(i + 2, close);
      consumedTo = close;
    } else {
      body = next;
      consumedTo = i + 1;
    }

    final converted = _toScript(body, table);
    if (converted != null) {
      buffer.write(converted);
      i = consumedTo + 1;
      continue;
    }

    buffer.write(fallbackMarker);
    buffer.write('(');
    buffer.write(body);
    buffer.write(')');
    i = consumedTo + 1;
  }

  return buffer.toString();
}

String? _toScript(String body, Map<String, String> table) {
  final buffer = StringBuffer();
  for (var i = 0; i < body.length; i++) {
    final mapping = table[body[i]];
    if (mapping == null) return null;
    buffer.write(mapping);
  }
  return buffer.isEmpty ? null : buffer.toString();
}

String _toSuperscript(String body) {
  final buffer = StringBuffer();
  for (var i = 0; i < body.length; i++) {
    buffer.write(_superscripts[body[i]] ?? body[i]);
  }
  return buffer.toString();
}

/// Index of the `}` matching the `{` at [open], or -1.
int _matchBrace(String input, int open) {
  if (open >= input.length || input[open] != '{') return -1;
  var depth = 0;
  for (var i = open; i < input.length; i++) {
    final c = input[i];
    if (c == r'\') {
      i++;
      continue;
    }
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// Replaces `\command` only where it is not a prefix of a longer command.
String _replaceCommand(String input, String command, String replacement) {
  final buffer = StringBuffer();
  var i = 0;
  while (i < input.length) {
    if (input.startsWith(command, i)) {
      final after = i + command.length;
      final nextChar = after < input.length ? input[after] : '';
      // A letter immediately after means this is a longer command name.
      final isLonger = nextChar.isNotEmpty && RegExp(r'[a-zA-Z]').hasMatch(nextChar);
      if (!isLonger) {
        buffer.write(replacement);
        i = after;
        continue;
      }
    }
    buffer.write(input[i]);
    i++;
  }
  return buffer.toString();
}

/// Removes `\command{...}` but keeps the contents.
String _unwrapCommand(String input, String command) {
  var result = input;
  for (var guard = 0; guard < 64; guard++) {
    final start = result.indexOf('$command{');
    if (start == -1) return result;
    final open = start + command.length;
    final close = _matchBrace(result, open);
    if (close == -1) return result;
    final body = result.substring(open + 1, close);
    result = result.substring(0, start) + body + result.substring(close + 1);
  }
  return result;
}

/// True when [text] mentions a structural LaTeX environment.
bool containsLatexEnvironment(String text) =>
    _environmentNames.any((env) => text.contains(r'\begin{' + env));
