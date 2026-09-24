/// Splits an assistant message into renderable blocks.
///
/// Three kinds of content need three different renderers: prose goes to the
/// markdown engine, fenced code goes to the syntax highlighter, and display
/// maths goes to the TeX renderer. Doing that split here - in pure Dart, with no
/// Flutter dependency - means the rules are unit-testable, and it keeps the
/// widget layer free of string scanning.
///
/// The split is deliberately *not* a markdown parser. It only has to recognise
/// the constructs that cannot be rendered as markdown text: fenced code blocks
/// and display maths. Everything else is passed through untouched so the
/// markdown engine remains the authority on headings, lists, tables, emphasis
/// and links - including inline `$...$` maths, which stays inside the prose so
/// it can flow with the sentence around it.
library;

import 'latex_splitter.dart';

/// One renderable run of a message.
sealed class MessageBlock {
  const MessageBlock();
}

/// Markdown text, possibly containing inline `$...$` maths.
class ProseBlock extends MessageBlock {
  const ProseBlock(this.text);

  final String text;

  @override
  bool operator ==(Object other) => other is ProseBlock && other.text == text;

  @override
  int get hashCode => Object.hash('prose', text);

  @override
  String toString() => 'ProseBlock(${text.length} chars)';
}

/// A fenced code block, with its info string if it had one.
class CodeBlock extends MessageBlock {
  const CodeBlock({required this.source, this.language = ''});

  final String source;

  /// The info string after the opening fence, e.g. `dart` in ```` ```dart ````.
  /// Empty when the fence had none.
  final String language;

  @override
  bool operator ==(Object other) =>
      other is CodeBlock &&
      other.source == source &&
      other.language == language;

  @override
  int get hashCode => Object.hash('code', source, language);

  @override
  String toString() => 'CodeBlock($language, ${source.length} chars)';
}

/// Display maths, shown centred on its own line.
class DisplayMathBlock extends MessageBlock {
  const DisplayMathBlock(this.latex);

  final String latex;

  @override
  bool operator ==(Object other) =>
      other is DisplayMathBlock && other.latex == latex;

  @override
  int get hashCode => Object.hash('math', latex);

  @override
  String toString() => 'DisplayMathBlock(${latex.length} chars)';
}

/// Splits [input] into [MessageBlock]s, in order.
///
/// [forceMath] is the per-message "Render math" toggle: it additionally treats
/// bare LaTeX with no delimiters as maths, which is what a model that ignores
/// the formatting instruction needs.
List<MessageBlock> splitMessageBlocks(String input, {bool forceMath = false}) {
  final blocks = <MessageBlock>[];
  if (input.isEmpty) return blocks;

  final buffer = StringBuffer();

  void flushProse() {
    final text = buffer.toString();
    buffer.clear();
    // Whitespace between two blocks is layout, not content; emitting it would
    // add a visible gap on top of the block spacing.
    if (text.trim().isEmpty) return;
    blocks.addAll(_proseBlocks(text, forceMath));
  }

  var i = 0;
  while (i < input.length) {
    if (!input.startsWith('```', i)) {
      buffer.write(input[i]);
      i++;
      continue;
    }

    // Opening fence. The info string runs to the end of the line.
    var lineEnd = input.indexOf('\n', i);
    final language = (lineEnd == -1
            ? input.substring(i + 3)
            : input.substring(i + 3, lineEnd))
        .trim();

    if (lineEnd == -1) {
      // A fence with nothing after it: treat the remainder as its own block so
      // an unfinished code block never swallows the message.
      flushProse();
      blocks.add(const CodeBlock(source: ''));
      break;
    }

    final close = input.indexOf('```', lineEnd);
    if (close == -1) {
      // Unterminated fence (the common case while streaming). Everything after
      // the opening line is code.
      flushProse();
      blocks.add(
        CodeBlock(
          source: _stripTrailingNewline(input.substring(lineEnd + 1)),
          language: language,
        ),
      );
      break;
    }

    flushProse();
    blocks.add(
      CodeBlock(
        source: _stripTrailingNewline(input.substring(lineEnd + 1, close)),
        language: language,
      ),
    );

    // Step past the closing fence and its line ending.
    i = close + 3;
    final restOfLine = input.indexOf('\n', i);
    if (restOfLine != -1 && input.substring(i, restOfLine).trim().isEmpty) {
      i = restOfLine + 1;
    }
  }

  flushProse();
  return blocks;
}

/// Splits a run of prose at display-maths boundaries.
///
/// Inline maths is left inside the prose (`extractInline: false`) so the
/// markdown engine can render it in the flow of the sentence.
List<MessageBlock> _proseBlocks(String text, bool forceMath) {
  final blocks = <MessageBlock>[];
  final segments = splitLatex(
    text,
    forceMath: forceMath,
    extractInline: false,
  );

  for (final segment in segments) {
    switch (segment.kind) {
      case SegmentKind.blockMath:
        blocks.add(DisplayMathBlock(segment.text));
      case SegmentKind.inlineMath:
        // Unreachable with extractInline: false, but re-wrapping is the correct
        // recovery if this ever changes: the delimiters were stripped, so the
        // text would otherwise be rendered as literal LaTeX.
        blocks.add(ProseBlock(r'$' + segment.text + r'$'));
      case SegmentKind.text:
        if (segment.text.trim().isEmpty) continue;
        blocks.add(ProseBlock(segment.text));
    }
  }

  return blocks;
}

String _stripTrailingNewline(String value) {
  if (value.endsWith('\n')) return value.substring(0, value.length - 1);
  return value;
}
