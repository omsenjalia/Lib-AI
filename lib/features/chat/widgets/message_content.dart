import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../core/theme/claude_tokens.dart';
import '../../../core/utils/markdown_blocks.dart';

/// Renders one assistant message: markdown, syntax-highlighted code blocks and
/// LaTeX, in the order the model wrote them.
///
/// The three renderers and why each is needed:
///
///  * **Markdown** (`flutter_markdown`) for everything textual, including the
///    inline `$...$` maths, which is registered as a custom inline syntax so a
///    formula sits on the same line as the sentence containing it.
///  * **Syntax highlighting** (`flutter_highlight`) for fenced code, which
///    markdown alone renders as flat monospace text.
///  * **TeX** (`flutter_math_fork`) for display maths, which markdown cannot
///    typeset at all.
///
/// [forceMath] is the per-message "Render math" toggle. It exists because some
/// models emit `\frac{a}{b}` with no delimiters at all; without the toggle the
/// user would see the raw LaTeX source.
///
/// ## Streaming cursor
///
/// While tokens are still arriving the last paragraph carries a blinking accent
/// cursor, which is why [_cursorSentinel] exists: a single private-use
/// character appended to the final prose block and given its own inline syntax,
/// so the cursor sits *after the last token inside the paragraph* rather than
/// floating below the message. Models never emit U+E000, so the sentinel cannot
/// collide with real output.
class MessageContent extends StatelessWidget {
  const MessageContent({
    super.key,
    required this.content,
    this.forceMath = false,
    this.textStyle,
    this.selectable = true,
    this.fontFamily = ChatFontFamily.lato,
    this.showStreamingCursor = false,
  });

  final String content;
  final bool forceMath;
  final TextStyle? textStyle;
  final bool selectable;
  final ChatFontFamily fontFamily;

  /// Draws the blinking accent cursor at the end of the text.
  final bool showStreamingCursor;

  static const String _cursorSentinel = '\uE000';

  @override
  Widget build(BuildContext context) {
    var blocks = splitMessageBlocks(content, forceMath: forceMath);
    var cursorInline = false;

    if (showStreamingCursor && blocks.isNotEmpty) {
      final last = blocks.last;
      if (last is ProseBlock) {
        blocks = [
          ...blocks.take(blocks.length - 1),
          ProseBlock('${last.text}$_cursorSentinel'),
        ];
        cursorInline = true;
      }
    }

    final body = _bodyStyle(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++)
          Padding(
            padding: EdgeInsets.only(
              top: i == 0 ? 0 : _spacingBefore(blocks[i]),
            ),
            child: _block(context, blocks[i], body),
          ),
        // The cursor could not be placed inline (the stream currently ends in a
        // code fence or a display equation), so it follows the last block.
        if (showStreamingCursor && !cursorInline)
          Padding(
            padding: const EdgeInsets.only(top: ClaudeSpacing.xs),
            child: BlinkingCursor(color: context.tokens.primary),
          ),
      ],
    );
  }

  double _spacingBefore(MessageBlock block) => switch (block) {
        CodeBlock() => 10,
        DisplayMathBlock() => 10,
        ProseBlock() => 6,
      };

  Widget _block(BuildContext context, MessageBlock block, TextStyle body) {
    switch (block) {
      case ProseBlock(:final text):
        return _prose(context, text, body);
      case CodeBlock(:final source, :final language):
        return CodeBlockView(source: source, language: language);
      case DisplayMathBlock(:final latex):
        return DisplayMathView(latex: latex, textStyle: body);
    }
  }

  /// The transcript's body face. Honours the "Chat font" setting, so a reader
  /// who prefers a serif for long answers gets one.
  TextStyle _bodyStyle(BuildContext context) {
    final tokens = context.tokens;
    final base = textStyle ?? ClaudeType.chatBody(fontFamily);
    return base.copyWith(color: tokens.ink);
  }

  Widget _prose(BuildContext context, String text, TextStyle body) {
    return MarkdownBody(
      data: text,
      selectable: selectable,
      // Custom inline syntaxes, added to the GitHub-style extension set rather
      // than replacing it, so tables, strikethrough and the rest still work.
      inlineSyntaxes: [_LatexInlineSyntax(text), _CursorSyntax()],
      builders: {
        'latex-inline': _LatexInlineBuilder(textStyle: body),
        'stream-cursor': _CursorBuilder(),
      },
      styleSheet: _styleSheet(context, body),
    );
  }

  static MarkdownStyleSheet _styleSheet(BuildContext context, TextStyle body) {
    final tokens = context.tokens;

    // Headings are the one place the display serif appears inside a message:
    // the answer's own structure, set in the brand's editorial face.
    TextStyle heading(double size) => TextStyle(
          fontFamily: ClaudeType.display,
          fontSize: size,
          height: 1.3,
          fontWeight: FontWeight.w400,
          color: tokens.ink,
        );

    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: body,
      listBullet: body,
      // Tables and blockquotes are the two constructs most likely to look like
      // an accident if they inherit the default styling.
      tableBorder: TableBorder.all(color: tokens.hairline, width: 0.6),
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 5,
      ),
      blockquoteDecoration: BoxDecoration(
        color: tokens.surfaceCard,
        border: Border(
          left: BorderSide(color: tokens.primary, width: 3),
        ),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      // Inline code: monospace on a one-step surface, never a full code block.
      code: ClaudeType.code.copyWith(
        fontSize: 13,
        color: tokens.ink,
        backgroundColor: tokens.surfaceCard,
      ),
      codeblockDecoration: BoxDecoration(
        color: tokens.codeSurface,
        borderRadius: BorderRadius.circular(ClaudeRadius.lg),
      ),
      h1: heading(21),
      h2: heading(18),
      h3: heading(16.5),
      h4: heading(15.5),
      a: body.copyWith(
        color: tokens.primaryActive,
        decoration: TextDecoration.underline,
      ),
      em: body.copyWith(fontStyle: FontStyle.italic),
      strong: body.copyWith(fontWeight: FontWeight.w700),
      blockSpacing: 12,
    );
  }
}

/// The blinking 600 ms accent cursor, used both inline (through the sentinel)
/// and as a trailing block.
class BlinkingCursor extends StatefulWidget {
  const BlinkingCursor({super.key, required this.color, this.height = 17});

  final Color color;
  final double height;

  @override
  State<BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ClaudeMotion.cursorBlink,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      // Never fully transparent: a cursor that vanishes reads as a lost
      // connection rather than a live one.
      opacity: Tween<double>(begin: 1, end: 0.15).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 1.5,
        height: widget.height,
        margin: const EdgeInsets.only(left: 1),
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}

/// Matches the streaming sentinel character.
class _CursorSyntax extends md.InlineSyntax {
  _CursorSyntax() : super('\uE000');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('stream-cursor', ''));
    return true;
  }
}

class _CursorBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return BlinkingCursor(color: context.tokens.primary);
  }
}

/// Matches `$...$` for inline maths.
///
/// The body must start and end with a non-space character and may not contain
/// another `$` or a newline. Those two rules are what stop ordinary money like
/// "costs $5 and then $10" being rendered as an equation - the first `$` has no
/// legal closing delimiter, so the syntax does not fire at all.
class _LatexInlineSyntax extends md.InlineSyntax {
  _LatexInlineSyntax(this.source)
      : super(r'\$(\S(?:[^$\n]*?[^\s])?)\$');

  /// The raw message, kept so an escaped `\$` can be recognised. Markdown
  /// unescapes it later; the inline parser sees the backslash, so checking the
  /// preceding character here is the only place the distinction is available.
  final String source;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    if (match.start > 0 && source[match.start - 1] == r'\') return false;
    // markdown 7.2.x renamed addElement to addNode.
    parser.addNode(md.Element.text('latex-inline', match.group(1)!));
    return true;
  }
}

class _LatexInlineBuilder extends MarkdownElementBuilder {
  // Not const: MarkdownElementBuilder has no const constructor.
  _LatexInlineBuilder({this.textStyle});

  final TextStyle? textStyle;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final style = preferredStyle ?? parentStyle ?? textStyle;
    return Padding(
      // TeX lays out on a maths baseline, which sits a little high next to
      // normal text; this nudges it back onto the line.
      padding: const EdgeInsets.only(top: 2),
      child: Math.tex(
        element.textContent,
        mathStyle: MathStyle.text,
        textStyle: style ?? const TextStyle(fontSize: 14),
        onErrorFallback: (error) => _MathError(latex: element.textContent),
      ),
    );
  }
}

/// Centred display maths on a one-step surface.
///
/// Horizontally scrollable, because a long derivation is wider than a phone
/// screen and wrapping a formula is not something TeX can do gracefully.
class DisplayMathView extends StatelessWidget {
  const DisplayMathView({super.key, required this.latex, this.textStyle});

  final String latex;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(ClaudeRadius.lg),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Center(
              child: Math.tex(
                latex,
                mathStyle: MathStyle.display,
                textStyle: textStyle ?? TextStyle(fontSize: 15, color: tokens.ink),
                onErrorFallback: (error) => _MathError(latex: latex),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: CopyButton(
              tooltip: 'Copy LaTeX',
              payload: latex,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown in place of a formula that failed to parse.
///
/// The raw source is kept visible rather than blanked out: a model that emits
/// broken TeX should look like a model that emitted broken TeX, not like an app
/// that lost the answer.
class _MathError extends StatelessWidget {
  const _MathError({required this.latex});

  final String latex;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: tokens.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ClaudeRadius.xs),
        border: Border.all(color: tokens.error.withValues(alpha: 0.4)),
      ),
      child: Text(
        latex,
        style: ClaudeType.code.copyWith(color: tokens.errorText),
      ),
    );
  }
}

/// A fenced code block: dark surface in both modes, monospace, language label
/// and a copy control in the header.
class CodeBlockView extends StatelessWidget {
  const CodeBlockView({
    super.key,
    required this.source,
    this.language = '',
  });

  final String source;
  final String language;

  /// Languages we pass to the highlighter by name.
  ///
  /// Anything not on this list is rendered as plain monospace. The highlighter
  /// falls back to plaintext for an unknown language anyway, but only after
  /// printing to the console, and a fence labelled `text` should not cost
  /// anything at all.
  static const Map<String, String> _aliases = {
    'py': 'python',
    'python': 'python',
    'js': 'javascript',
    'javascript': 'javascript',
    'ts': 'typescript',
    'typescript': 'typescript',
    'dart': 'dart',
    'java': 'java',
    'kt': 'kotlin',
    'kotlin': 'kotlin',
    'swift': 'swift',
    'c': 'c',
    'h': 'c',
    'cpp': 'cpp',
    'c++': 'cpp',
    'cs': 'csharp',
    'csharp': 'csharp',
    'go': 'go',
    'rs': 'rust',
    'rust': 'rust',
    'rb': 'ruby',
    'ruby': 'ruby',
    'php': 'php',
    'sh': 'bash',
    'bash': 'bash',
    'zsh': 'bash',
    'shell': 'bash',
    'psql': 'sql',
    'sql': 'sql',
    'html': 'xml',
    'xml': 'xml',
    'css': 'css',
    'json': 'json',
    'yaml': 'yaml',
    'yml': 'yaml',
    'toml': 'ini',
    'ini': 'ini',
    'make': 'makefile',
    'makefile': 'makefile',
    'dockerfile': 'dockerfile',
    'tex': 'latex',
    'latex': 'latex',
    'gradle': 'gradle',
    'proto': 'protobuf',
  };

  static String? _resolveLanguage(String raw) {
    final key = raw.trim().toLowerCase();
    if (key.isEmpty) return null;
    return _aliases[key];
  }

  /// The highlighter's own theme is used for token colours, but its cool
  /// slate background is replaced so the block lands on the token surface.
  static Map<String, TextStyle> _theme(ClaudeTokens tokens) {
    final theme = Map<String, TextStyle>.from(atomOneDarkTheme);
    final root = (theme['root'] ?? const TextStyle()).copyWith(
      backgroundColor: Colors.transparent,
      color: tokens.onCode,
      fontFamily: ClaudeType.mono,
      fontSize: 12.5,
      height: 1.55,
    );
    theme['root'] = root;
    theme['code'] = root;
    return theme;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final resolved = _resolveLanguage(language);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tokens.codeSurface,
        borderRadius: BorderRadius.circular(ClaudeRadius.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    language.trim().isEmpty ? 'code' : language.trim(),
                    style: ClaudeType.caption.copyWith(
                      fontSize: 11,
                      letterSpacing: 0.4,
                      color: tokens.onDark.withValues(alpha: 0.55),
                    ),
                  ),
                ),
                CopyButton(
                  tooltip: 'Copy code',
                  payload: source,
                  dark: true,
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: HighlightView(
              source,
              language: resolved,
              theme: _theme(tokens),
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              textStyle: const TextStyle(
                fontFamily: ClaudeType.mono,
                fontSize: 12.5,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Copies [payload] to the clipboard and confirms it briefly.
class CopyButton extends StatelessWidget {
  const CopyButton({
    super.key,
    required this.payload,
    required this.tooltip,
    this.dark = false,
  });

  final String payload;
  final String tooltip;

  /// True inside a code block, where the surface is dark in both modes.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return IconButton(
      tooltip: tooltip,
      iconSize: 16,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      color: dark ? tokens.onDark.withValues(alpha: 0.7) : tokens.muted,
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: payload));
        if (!context.mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('$tooltip - copied'),
            duration: const Duration(milliseconds: 1200),
          ),
        );
      },
      icon: const Icon(Icons.content_copy_rounded),
    );
  }
}
