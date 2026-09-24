import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../core/theme/app_colors.dart';
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
class MessageContent extends StatelessWidget {
  const MessageContent({
    super.key,
    required this.content,
    this.forceMath = false,
    this.textStyle,
    this.selectable = true,
  });

  final String content;
  final bool forceMath;
  final TextStyle? textStyle;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final blocks = splitMessageBlocks(content, forceMath: forceMath);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++)
          Padding(
            padding: EdgeInsets.only(
              top: i == 0 ? 0 : _spacingBefore(blocks[i]),
            ),
            child: _block(context, blocks[i]),
          ),
      ],
    );
  }

  double _spacingBefore(MessageBlock block) => switch (block) {
        CodeBlock() => 10,
        DisplayMathBlock() => 10,
        ProseBlock() => 6,
      };

  Widget _block(BuildContext context, MessageBlock block) {
    switch (block) {
      case ProseBlock(:final text):
        return _prose(context, text);
      case CodeBlock(:final source, :final language):
        return CodeBlockView(source: source, language: language);
      case DisplayMathBlock(:final latex):
        return DisplayMathView(latex: latex, textStyle: textStyle);
    }
  }

  Widget _prose(BuildContext context, String text) {
    return MarkdownBody(
      data: text,
      selectable: selectable,
      // Custom inline syntax, added to the GitHub-style extension set rather
      // than replacing it, so tables, strikethrough and the rest still work.
      inlineSyntaxes: [_LatexInlineSyntax(text)],
      builders: {'latex-inline': _LatexInlineBuilder(textStyle: textStyle)},
      styleSheet: _styleSheet(context, textStyle),
    );
  }

  static MarkdownStyleSheet _styleSheet(
    BuildContext context,
    TextStyle? base,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = scheme.brightness == Brightness.light;
    final secondary =
        isLight ? AppColors.lightTextSecondary : AppColors.textSecondary;
    final codeBackground =
        isLight ? AppColors.codeBackgroundLight : AppColors.codeBackgroundDark;

    final body = base ??
        TextStyle(
          fontSize: 14,
          height: 1.55,
          color: scheme.onSurface,
        );

    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: body,
      listBullet: body,
      // Tables and blockquotes are the two constructs most likely to look like
      // an accident if they inherit the default styling over a dark surface.
      tableBorder: TableBorder.all(
        color: isLight ? AppColors.lightOutline : AppColors.outline,
        width: 0.6,
      ),
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 5,
      ),
      blockquoteDecoration: BoxDecoration(
        color: isLight
            ? AppColors.lightSurfaceHigh
            : AppColors.surfaceHigh.withValues(alpha: 0.5),
        border: Border(
          left: BorderSide(
            color: AppColors.accent.withValues(alpha: 0.6),
            width: 3,
          ),
        ),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: 12.5,
        backgroundColor: codeBackground,
        color: scheme.onSurface,
      ),
      codeblockDecoration: BoxDecoration(
        color: codeBackground,
        borderRadius: BorderRadius.circular(6),
      ),
      h1: body.copyWith(fontSize: 19, fontWeight: FontWeight.w700),
      h2: body.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
      h3: body.copyWith(fontSize: 15.5, fontWeight: FontWeight.w600),
      h4: body.copyWith(fontSize: 14.5, fontWeight: FontWeight.w600),
      a: body.copyWith(
        color: AppColors.accent,
        decoration: TextDecoration.underline,
      ),
      em: body.copyWith(fontStyle: FontStyle.italic, color: secondary),
      strong: body.copyWith(fontWeight: FontWeight.w700),
    );
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

/// Centred display maths.
///
/// Horizontally scrollable, because a long derivation is wider than a phone
/// screen and wrapping a formula is not something TeX can do gracefully.
class DisplayMathView extends StatelessWidget {
  const DisplayMathView({super.key, required this.latex, this.textStyle});

  final String latex;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.brightness == Brightness.dark
            ? AppColors.surfaceHigh.withValues(alpha: 0.35)
            : AppColors.lightSurfaceHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Center(
              child: Math.tex(
                latex,
                mathStyle: MathStyle.display,
                textStyle: textStyle ?? TextStyle(
                  fontSize: 15,
                  color: scheme.onSurface,
                ),
                onErrorFallback: (error) => _MathError(latex: latex),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: _CopyButton(
              tooltip: 'Copy LaTeX',
              payload: latex,
              compact: true,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Text(
        latex,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12.5,
          color: AppColors.error,
        ),
      ),
    );
  }
}

/// A fenced code block with a language label and a copy button.
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = scheme.brightness == Brightness.light;
    final background =
        isLight ? AppColors.codeBackgroundLight : AppColors.codeBackgroundDark;
    final border = isLight ? AppColors.lightOutline : AppColors.outline;
    final resolved = _resolveLanguage(language);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 0.7),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: border, width: 0.7)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    language.trim().isEmpty ? 'code' : language.trim(),
                    style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 0.4,
                      fontWeight: FontWeight.w600,
                      color: isLight
                          ? AppColors.lightTextSecondary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
                _CopyButton(
                  tooltip: 'Copy code',
                  payload: source,
                  compact: true,
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: HighlightView(
              source,
              language: resolved,
              theme: isLight ? githubTheme : atomOneDarkTheme,
              padding: const EdgeInsets.all(12),
              textStyle: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Copies [payload] to the clipboard and confirms it briefly.
class _CopyButton extends StatelessWidget {
  const _CopyButton({
    required this.payload,
    required this.tooltip,
    this.compact = false,
  });

  final String payload;
  final String tooltip;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      iconSize: compact ? 15 : 17,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: payload));
        if (!context.mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('$tooltip - copied'),
            duration: const Duration(milliseconds: 1200),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      icon: const Icon(Icons.content_copy_rounded, size: 15),
    );
  }
}
