/// Splits an assistant message into alternating plain-text and LaTeX segments so
/// each half can be rendered by the right engine: markdown for prose, the math
/// renderer for formulae.
///
/// This is pure Dart with no Flutter dependency specifically so it can be unit
/// tested without a device - the correctness of delimiter handling is the part
/// most likely to break, and the part users notice immediately.
///
/// Recognised delimiters:
///
/// | Delimiter        | Rendered as |
/// |------------------|-------------|
/// | `$$ ... $$`      | block math  |
/// | `\[ ... \]`      | block math  |
/// | `\begin{env} ... \end{env}` | block math |
/// | `$ ... $`        | inline math |
/// | `\( ... \)`      | inline math |
///
/// Delimiters inside fenced code blocks (```` ``` ````) and inline code (`` ` ``)
/// are **ignored**, so a code sample that prints `$PATH` is never mistaken for
/// a formula. A backslash-escaped `\$` is treated as a literal dollar sign.
///
/// [forceMath] additionally treats bare LaTeX that has no delimiters at all as
/// math. It backs the per-message "Render math" toggle, for models that emit
/// raw LaTeX such as `\frac{a}{b}` with nothing wrapping it.
library;

/// What a segment of an assistant message should be rendered as.
enum SegmentKind {
  /// Ordinary prose, bullet lists, tables, code - render as markdown.
  text,

  /// `$ ... $` style maths - flows inline with the surrounding text.
  inlineMath,

  /// `$$ ... $$` style maths - rendered centred on its own line.
  blockMath,
}

/// One contiguous run of an assistant message.
class LatexSegment {
  const LatexSegment({required this.text, required this.kind});

  /// The raw content, with delimiters already stripped for math segments.
  final String text;

  final SegmentKind kind;

  bool get isMath => kind != SegmentKind.text;
  bool get isBlockMath => kind == SegmentKind.blockMath;
  bool get isInlineMath => kind == SegmentKind.inlineMath;

  @override
  String toString() => 'LatexSegment($kind, ${text.length} chars)';

  @override
  bool operator ==(Object other) =>
      other is LatexSegment && other.text == text && other.kind == kind;

  @override
  int get hashCode => Object.hash(text, kind);
}

/// Splits [input] into renderable segments. See the library docs for the
/// delimiter rules.
///
/// [extractInline] controls what happens to inline maths (`$...$`, `\(...\)`).
///
///  * `true` (default) lifts it out into its own [SegmentKind.inlineMath]
///    segment. That is what the PDF exporter and the plain-text converter need,
///    because they can only place a formula on its own run of text.
///  * `false` leaves it in the surrounding prose untouched. The chat renderer
///    wants this, because it hands the prose to the markdown engine, which
///    turns `$...$` into an inline widget - keeping the formula on the same line
///    as the sentence around it instead of breaking the paragraph in three.
///
/// Display maths (`$$...$$`, `\[...\]`, `\begin{env}`) is always extracted.
List<LatexSegment> splitLatex(
  String input, {
  bool forceMath = false,
  bool extractInline = true,
}) {
  if (input.isEmpty) {
    return const [LatexSegment(text: '', kind: SegmentKind.text)];
  }

  final segments = <LatexSegment>[];
  final buffer = StringBuffer();

  void flushText() {
    if (buffer.isNotEmpty) {
      segments.add(LatexSegment(text: buffer.toString(), kind: SegmentKind.text));
      buffer.clear();
    }
  }

  var i = 0;
  var inFence = false;
  var inInlineCode = false;

  while (i < input.length) {
    final ch = input[i];

    // --- fenced code blocks -------------------------------------------------
    if (ch == '`' && _isRun(input, i, 3, '`')) {
      final fenceEnd = input.indexOf('```', i + 3);
      if (fenceEnd == -1) {
        // Unterminated fence: the remainder is literal text.
        buffer.write(input.substring(i));
        i = input.length;
        break;
      }
      buffer.write(input.substring(i, fenceEnd + 3));
      i = fenceEnd + 3;
      inFence = !inFence;
      continue;
    }

    if (inFence) {
      buffer.write(ch);
      i++;
      continue;
    }

    // --- inline code spans --------------------------------------------------
    if (ch == '`' && !_isRun(input, i, 2, '`')) {
      inInlineCode = !inInlineCode;
      buffer.write(ch);
      i++;
      continue;
    }

    if (inInlineCode) {
      buffer.write(ch);
      i++;
      continue;
    }

    if (ch == '\n') {
      buffer.write(ch);
      i++;
      continue;
    }

    // --- escaped dollar -----------------------------------------------------
    if (ch == r'\' && i + 1 < input.length && input[i + 1] == r'$') {
      buffer.write(r'$');
      i += 2;
      continue;
    }

    // --- block math: $$ ... $$ ---------------------------------------------
    if (ch == r'$' && _isRun(input, i, 2, r'$')) {
      final close = input.indexOf(r'$$', i + 2);
      if (close != -1) {
        final body = input.substring(i + 2, close);
        if (body.trim().isNotEmpty) {
          flushText();
          segments.add(
            LatexSegment(text: body.trim(), kind: SegmentKind.blockMath),
          );
          i = close + 2;
          continue;
        }
      }
    }

    // --- block math: \[ ... \] ---------------------------------------------
    if (ch == r'\' && i + 1 < input.length && input[i + 1] == '[') {
      final close = input.indexOf(r'\]', i + 2);
      if (close != -1) {
        flushText();
        segments.add(
          LatexSegment(
            text: input.substring(i + 2, close).trim(),
            kind: SegmentKind.blockMath,
          ),
        );
        i = close + 2;
        continue;
      }
    }

    // --- inline math: \( ... \) --------------------------------------------
    if (ch == r'\' && i + 1 < input.length && input[i + 1] == '(') {
      final close = input.indexOf(r'\)', i + 2);
      if (close != -1 && !extractInline) {
        buffer.write(input.substring(i, close + 2));
        i = close + 2;
        continue;
      }
      if (close != -1) {
        flushText();
        segments.add(
          LatexSegment(
            text: input.substring(i + 2, close).trim(),
            kind: SegmentKind.inlineMath,
          ),
        );
        i = close + 2;
        continue;
      }
    }

    // --- block math: \begin{env} ... \end{env} -----------------------------
    if (ch == r'\' && input.startsWith(r'\begin{', i)) {
      final envEnd = input.indexOf('}', i + 7);
      if (envEnd != -1) {
        final env = input.substring(i + 7, envEnd);
        final closeTag = '${r'\end{'}$env}';
        final close = input.indexOf(closeTag, envEnd);
        if (close != -1) {
          flushText();
          segments.add(
            LatexSegment(
              text: input.substring(i, close + closeTag.length),
              kind: SegmentKind.blockMath,
            ),
          );
          i = close + closeTag.length;
          continue;
        }
      }
    }

    // --- inline math: $ ... $ ----------------------------------------------
    if (ch == r'$') {
      final close = _findInlineDollarClose(input, i + 1);
      if (close != -1 && !extractInline) {
        buffer.write(input.substring(i, close + 1));
        i = close + 1;
        continue;
      }
      if (close != -1) {
        flushText();
        segments.add(
          LatexSegment(
            text: input.substring(i + 1, close).trim(),
            kind: SegmentKind.inlineMath,
          ),
        );
        i = close + 1;
        continue;
      }
    }

    // --- forced math on bare LaTeX -----------------------------------------
    if (forceMath && ch == r'\' && _looksLikeCommand(input, i)) {
      final end = _bareLatexEnd(input, i);
      if (end > i && !extractInline) {
        // Wrap rather than lift, so the caller's inline-math handling picks it
        // up and it stays in the flow of the sentence it was written in.
        buffer.write(r'$');
        buffer.write(input.substring(i, end).trim());
        buffer.write(r'$');
        i = end;
        continue;
      }
      if (end > i) {
        flushText();
        segments.add(
          LatexSegment(
            text: input.substring(i, end).trim(),
            kind: SegmentKind.inlineMath,
          ),
        );
        i = end;
        continue;
      }
    }

    buffer.write(ch);
    i++;
  }

  flushText();

  // Drop an empty leading/trailing text run so callers never render a blank
  // MarkdownBody above or below a formula.
  if (segments.length > 1 &&
      segments.first.kind == SegmentKind.text &&
      segments.first.text.trim().isEmpty) {
    segments.removeAt(0);
  }
  if (segments.length > 1 &&
      segments.last.kind == SegmentKind.text &&
      segments.last.text.trim().isEmpty) {
    segments.removeLast();
  }
  return segments;
}

/// True when [input] has [n] consecutive copies of [char] starting at [index].
///
/// The character is a parameter rather than being hard-coded, because this
/// guards two different delimiters: backtick runs (fenced and inline code) and
/// dollar runs (`$$` display maths).
bool _isRun(String input, int index, int n, String char) {
  if (index + n > input.length) return false;
  for (var k = 0; k < n; k++) {
    if (input[index + k] != char) return false;
  }
  return true;
}

/// Finds the closing `$` for an inline span that opened just before [start].
///
/// Returns -1 when the candidate is not really inline math. These heuristics
/// are what stop ordinary prose like "costs $5 and then $10" becoming a
/// formula: no newline in the body, non-empty, no leading/trailing whitespace.
int _findInlineDollarClose(String input, int start) {
  var j = start;
  while (j < input.length) {
    final c = input[j];
    if (c == '\n') return -1;
    if (c == r'\') {
      j += 2;
      continue;
    }
    if (c == r'$') {
      final body = input.substring(start, j);
      if (body.isEmpty) return -1;
      if (body != body.trim()) return -1;
      if (body.contains('\n\n')) return -1;
      return j;
    }
    j++;
  }
  return -1;
}

/// True when the backslash at [index] starts a LaTeX command rather than an
/// ordinary prose escape.
bool _looksLikeCommand(String input, int index) {
  final rest = input.substring(index + 1);
  if (rest.isEmpty) return false;
  final match = RegExp(r'^[a-zA-Z]+').firstMatch(rest);
  if (match == null) return false;
  // \n, \t and friends are escapes in prose, never commands here.
  const escapes = {'n', 't', 'r', 's', 'd', 'w', 'b'};
  return !escapes.contains(match.group(0));
}

/// Extent of a bare LaTeX command sequence, e.g. `\frac{a}{b} + \sqrt{x}`.
int _bareLatexEnd(String input, int index) {
  var j = index;
  var braceDepth = 0;
  while (j < input.length) {
    final c = input[j];
    if (c == '{') {
      braceDepth++;
    } else if (c == '}') {
      braceDepth--;
      if (braceDepth < 0) break;
    } else if (c == '\n' && braceDepth == 0) {
      break;
    } else if ((c == ' ' || c == '&' || c == ';') && braceDepth == 0) {
      final next = _nextNonSpace(input, j);
      if (next == null) break;
      // The span continues while the next token is an operator or another
      // command, so `\alpha + \beta = \gamma` stays one formula instead of
      // becoming three widgets separated by stray spaces.
      if (!_spanContinuations.contains(next)) break;
    }
    j++;
  }
  return j;
}

/// Characters that let a forced (undelimited) LaTeX span keep going.
///
/// A backslash is included because `\alpha + \beta` is one expression: after
/// the `+` and the space that follows it, the next non-space character is a
/// backslash.
const Set<String> _spanContinuations = {
  '+', '-', '=', '<', '>', '/', '*', '^', '_', '\\',
};

String? _nextNonSpace(String input, int index) {
  for (var k = index; k < input.length; k++) {
    if (input[k] != ' ') return input[k];
  }
  return null;
}
