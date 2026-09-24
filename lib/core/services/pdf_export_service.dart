import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/database.dart';
import '../utils/formatters.dart';
import '../utils/latex_splitter.dart';
import '../utils/latex_to_text.dart';
import '../utils/pdf_text.dart';
import 'storage_paths.dart';

/// Everything needed to render one conversation.
@immutable
class ConversationExport {
  const ConversationExport({
    required this.conversation,
    required this.messages,
    this.tag,
    this.personaName,
    this.modelName,
  });

  final Conversation conversation;
  final List<Message> messages;
  final SubjectTag? tag;
  final String? personaName;
  final String? modelName;

  String get safeTitle => slugify(conversation.title);
}

/// Renders conversations to PDF, and bulk-exports them as a ZIP.
///
/// ## Two constraints that shaped this file
///
/// **No network.** An exported PDF has to be produced identically in airplane
/// mode, so no font is ever downloaded. See `pdf_text.dart` for how Unicode is
/// handled as a consequence.
///
/// **No LaTeX typesetting.** The `pdf` package lays out text, not mathematics.
/// Formulae are therefore converted to readable plain text by
/// `latex_to_text.dart` rather than dumped in raw. On-screen rendering is
/// unaffected and still uses the real math renderer.
class PdfExportService {
  const PdfExportService();

  // ------------------------------------------------------------- colours

  static const _base = PdfColor.fromInt(0xFF1A1A2E);
  static const _surface = PdfColor.fromInt(0xFFF7F5F1);
  static const _accent = PdfColor.fromInt(0xFF9C6210);
  static const _textPrimary = PdfColor.fromInt(0xFF1A1A2E);
  static const _textSecondary = PdfColor.fromInt(0xFF5F5F70);
  static const _outline = PdfColor.fromInt(0xFFD5CEC2);
  static const _codeBg = PdfColor.fromInt(0xFFF2EFE9);

  /// Builds the PDF bytes for one conversation.
  ///
  /// Deliberately light-on-white even though the app is dark-mode-first: a PDF
  /// is read on paper and in other people's viewers, where a dark background
  /// wastes ink and looks broken.
  Future<Uint8List> buildPdf(ConversationExport bundle) async {
    final doc = pw.Document(
      title: bundle.conversation.title,
      author: 'Library AI',
      creator: 'Library AI',
    );

    final regular = pw.Font.helvetica();
    final bold = pw.Font.helveticaBold();
    final italic = pw.Font.helveticaOblique();
    final mono = pw.Font.courier();

    final styles = _Styles(
      regular: regular,
      bold: bold,
      italic: italic,
      mono: mono,
    );

    // Pre-load images once; a failure to read one must not abort the export.
    final images = await _loadImages(bundle.messages);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 44, 40, 44),
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox()
            : _pageHeader(bundle, styles, bold),
        footer: (context) => _pageFooter(context, styles),
        build: (context) => [
          _titleBlock(bundle, styles, regular, bold),
          pw.SizedBox(height: 18),
          for (final message in bundle.messages) ...[
            _messageBlock(message, bundle, styles, images),
            pw.SizedBox(height: 12),
          ],
        ],
      ),
    );

    return doc.save();
  }

  /// Writes the PDF to the exports directory and returns the file.
  Future<File> writePdf(ConversationExport bundle) async {
    final bytes = await buildPdf(bundle);
    final dir = await StoragePaths.exportsDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final file = File(p.join(dir.path, '${bundle.safeTitle}-$stamp.pdf'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Opens the system share sheet for one conversation's PDF.
  Future<void> sharePdf(ConversationExport bundle) async {
    final bytes = await buildPdf(bundle);
    await HapticFeedback.lightImpact();
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${bundle.safeTitle}.pdf',
    );
  }

  /// Exports every conversation as a ZIP of PDFs.
  ///
  /// Returns the written archive. Note that this only produces the file - see
  /// `SettingsScreen` for why the ZIP is not additionally pushed to a share
  /// sheet, and what the user is shown instead.
  Future<File> exportAllAsZip(List<ConversationExport> bundles) async {
    final archive = Archive();
    final usedNames = <String, int>{};

    for (final bundle in bundles) {
      final bytes = await buildPdf(bundle);

      // Two conversations can share a title, so de-duplicate file names rather
      // than silently overwriting one with the other.
      final base = bundle.safeTitle;
      final seen = usedNames.update(base, (v) => v + 1, ifAbsent: () => 0);
      final name = seen == 0 ? base : '$base-$seen';

      final data = bytes;
      archive.addFile(ArchiveFile('$name.pdf', data.length, data));
    }

    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      throw const FileSystemException('Could not encode the export archive.');
    }

    final dir = await StoragePaths.exportsDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File(
      p.join(dir.path, 'library-ai-conversations-${stamp.substring(0, 16)}.zip'),
    );
    await file.writeAsBytes(encoded, flush: true);
    return file;
  }

  // -------------------------------------------------------------- internals

  Future<Map<int, Uint8List>> _loadImages(List<Message> messages) async {
    final images = <int, Uint8List>{};
    for (final message in messages) {
      final path = message.imagePath;
      if (path == null) continue;
      try {
        final file = File(path);
        if (await file.exists()) {
          images[message.id] = await file.readAsBytes();
        }
      } catch (_) {
        // A missing attachment is not worth failing an export over.
      }
    }
    return images;
  }

  pw.Widget _pageHeader(
    ConversationExport bundle,
    _Styles styles,
    pw.Font bold,
  ) =>
      pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(bottom: 12),
        child: pw.Text(
          pdfSafeText(bundle.conversation.title),
          style: pw.TextStyle(
            font: styles.regular,
            fontSize: 8,
            color: _textSecondary,
          ),
        ),
      );

  pw.Widget _pageFooter(pw.Context context, _Styles styles) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 10),
        child: pw.Text(
          '${context.pageNumber} / ${context.pagesCount}  ·  Library AI',
          style: pw.TextStyle(
            font: styles.regular,
            fontSize: 8,
            color: _textSecondary,
          ),
        ),
      );

  pw.Widget _titleBlock(
    ConversationExport bundle,
    _Styles styles,
    pw.Font regular,
    pw.Font bold,
  ) {
    final conversation = bundle.conversation;
    final meta = <String>[
      if (bundle.tag != null) bundle.tag!.name,
      if (bundle.modelName != null) bundle.modelName!,
      if (bundle.personaName != null) bundle.personaName!,
      formatAbsoluteTime(conversation.createdAt),
    ];

    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: _accent, width: 2),
        ),
      ),
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            pdfSafeText(conversation.title),
            style: pw.TextStyle(font: bold, fontSize: 19, color: _textPrimary),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            pdfSafeText(meta.join('  ·  ')),
            style: pw.TextStyle(
              font: regular,
              fontSize: 9,
              color: _textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _messageBlock(
    Message message,
    ConversationExport bundle,
    _Styles styles,
    Map<int, Uint8List> images,
  ) {
    final isUser = message.role == 'user';
    final label = isUser
        ? 'You'
        : (bundle.modelName ?? 'Assistant');

    final children = <pw.Widget>[
      pw.Row(
        children: [
          pw.Text(
            pdfSafeText(label),
            style: pw.TextStyle(
              font: styles.bold,
              fontSize: 9,
              color: isUser ? _textSecondary : _accent,
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Text(
            formatAbsoluteTime(message.createdAt),
            style: pw.TextStyle(
              font: styles.regular,
              fontSize: 8,
              color: _textSecondary,
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 4),
    ];

    final image = images[message.id];
    if (image != null) {
      children.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Image(pw.MemoryImage(image), height: 130),
        ),
      );
    }

    if (message.isError) {
      children.add(
        pw.Container(
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(
            color: const PdfColor.fromInt(0xFFFBEDED),
            borderRadius: pw.BorderRadius.circular(3),
          ),
          child: pw.Text(
            pdfSafeText(message.content),
            style: pw.TextStyle(
              font: styles.italic,
              fontSize: 9.5,
              color: const PdfColor.fromInt(0xFF8A3A3A),
            ),
          ),
        ),
      );
    } else {
      children.addAll(
        _renderMarkdown(
          message.content,
          styles,
          forceMath: message.renderMath,
        ),
      );
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: isUser
          ? pw.BoxDecoration(
              color: _surface,
              borderRadius: pw.BorderRadius.circular(4),
            )
          : null,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  /// A deliberately small markdown subset, rendered natively by the PDF engine.
  ///
  /// Supported: headings, bold, italic, inline code, fenced code blocks,
  /// bullet and numbered lists, blockquotes, tables, horizontal rules and
  /// LaTeX (converted, not typeset). Anything unrecognised falls through as a
  /// paragraph, which is the safe failure mode: content is never dropped.
  List<pw.Widget> _renderMarkdown(
    String markdown,
    _Styles styles, {
    bool forceMath = false,
  }) {
    final widgets = <pw.Widget>[];
    final segments = splitLatex(markdown, forceMath: forceMath);

    for (final segment in segments) {
      if (segment.isMath) {
        widgets.add(_mathBlock(segment, styles));
        continue;
      }
      widgets.addAll(_renderProse(segment.text, styles));
    }

    return widgets;
  }

  /// Renders a formula as readable text, centred when it was a display block.
  pw.Widget _mathBlock(LatexSegment segment, _Styles styles) {
    final text = pdfSafeText(latexToPlainText(segment.text));
    return pw.Container(
      width: double.infinity,
      alignment: segment.isBlockMath
          ? pw.Alignment.center
          : pw.Alignment.centerLeft,
      padding: pw.EdgeInsets.symmetric(
        vertical: segment.isBlockMath ? 6 : 0,
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: styles.italic,
          fontSize: 10.5,
          color: _textPrimary,
        ),
      ),
    );
  }

  List<pw.Widget> _renderProse(String prose, _Styles styles) {
    final widgets = <pw.Widget>[];
    final lines = prose.split('\n');

    var index = 0;
    while (index < lines.length) {
      final raw = lines[index];
      final line = raw.trimRight();

      // --- fenced code block -------------------------------------------
      if (line.trimLeft().startsWith('```')) {
        final language = line.trim().substring(3).trim();
        final code = <String>[];
        index++;
        while (index < lines.length &&
            !lines[index].trimLeft().startsWith('```')) {
          code.add(lines[index]);
          index++;
        }
        index++; // consume the closing fence
        widgets.add(_codeBlock(code, language, styles));
        widgets.add(pw.SizedBox(height: 6));
        continue;
      }

      // --- heading ------------------------------------------------------
      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
      if (heading != null) {
        final level = heading.group(1)!.length;
        final size = switch (level) {
          1 => 15.0,
          2 => 13.0,
          3 => 11.5,
          _ => 10.5,
        };
        widgets.add(pw.SizedBox(height: level <= 2 ? 6 : 3));
        widgets.add(
          pw.Inline(
            baseline: 0,
            children: _inlineSpans(
              pdfSafeText(heading.group(2)!),
              styles,
              baseSize: size,
              forceBold: true,
            ),
          ),
        );
        continue;
      }

      // --- horizontal rule ----------------------------------------------
      if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(line.trim())) {
        widgets.add(
          pw.Container(
            margin: const pw.EdgeInsets.symmetric(vertical: 6),
            height: 0.7,
            color: _outline,
          ),
        );
        index++;
        continue;
      }

      // --- table --------------------------------------------------------
      if (line.trim().startsWith('|')) {
        final rows = <List<String>>[];
        while (index < lines.length &&
            lines[index].trim().startsWith('|')) {
          final cells = lines[index]
              .trim()
              .replaceAll(RegExp(r'^\||\|$'), '')
              .split('|')
              .map((c) => c.trim())
              .toList();
          // Skip the `|---|` alignment separator row.
          final isSeparator =
              cells.every((c) => RegExp(r'^:?-{2,}:?$').hasMatch(c));
          if (!isSeparator) rows.add(cells);
          index++;
        }
        if (rows.isNotEmpty) {
          widgets.add(_table(rows, styles));
          widgets.add(pw.SizedBox(height: 6));
        }
        continue;
      }

      // --- bullet -------------------------------------------------------
      final bullet = RegExp(r'^\s*[-*+]\s+(.*)$').firstMatch(line);
      if (bullet != null) {
        widgets.add(
          pw.Bullet(
            bulletColor: _accent,
            margin: const pw.EdgeInsets.only(left: 8, bottom: 1),
            child: pw.Inline(
              baseline: 0,
              children: _inlineSpans(
                pdfSafeText(bullet.group(1)!),
                styles,
                baseSize: 10,
              ),
            ),
          ),
        );
        index++;
        continue;
      }

      // --- numbered list ------------------------------------------------
      final numbered = RegExp(r'^\s*(\d+)[.)]\s+(.*)$').firstMatch(line);
      if (numbered != null) {
        widgets.add(
          pw.Container(
            margin: const pw.EdgeInsets.only(left: 8, bottom: 1),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: 18,
                  child: pw.Text(
                    '${numbered.group(1)}.',
                    style: pw.TextStyle(
                      font: styles.regular,
                      fontSize: 10,
                      color: _textSecondary,
                    ),
                  ),
                ),
                pw.Expanded(
                  child: pw.Inline(
                    baseline: 0,
                    children: _inlineSpans(
                      pdfSafeText(numbered.group(2)!),
                      styles,
                      baseSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        index++;
        continue;
      }

      // --- blockquote ---------------------------------------------------
      final quote = RegExp(r'^\s*>\s?(.*)$').firstMatch(line);
      if (quote != null) {
        widgets.add(
          pw.Container(
            margin: const pw.EdgeInsets.only(left: 8, bottom: 3),
            padding: const pw.EdgeInsets.only(left: 8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                left: pw.BorderSide(color: _outline, width: 2),
              ),
            ),
            child: pw.Text(
              pdfSafeText(quote.group(1)!),
              style: pw.TextStyle(
                font: styles.italic,
                fontSize: 10,
                color: _textSecondary,
              ),
            ),
          ),
        );
        index++;
        continue;
      }

      // --- blank line ---------------------------------------------------
      if (line.trim().isEmpty) {
        widgets.add(pw.SizedBox(height: 4));
        index++;
        continue;
      }

      // --- paragraph ----------------------------------------------------
      widgets.add(
        pw.Inline(
          baseline: 0,
          children: _inlineSpans(
            pdfSafeText(line),
            styles,
            baseSize: 10,
          ),
        ),
      );
      index++;
    }

    return widgets;
  }

  pw.Widget _table(List<List<String>> rows, _Styles styles) {
    final columnCount =
        rows.map((r) => r.length).fold<int>(0, (a, b) => a > b ? a : b);

    return pw.Table(
      border: pw.TableBorder.all(color: _outline, width: 0.5),
      children: [
        for (var r = 0; r < rows.length; r++)
          pw.TableRow(
            decoration: r == 0
                ? const pw.BoxDecoration(color: _surface)
                : null,
            children: [
              for (var c = 0; c < columnCount; c++)
                pw.Padding(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text(
                    c < rows[r].length ? rows[r][c] : '',
                    style: pw.TextStyle(
                      font: r == 0 ? styles.bold : styles.regular,
                      fontSize: 8.5,
                      color: _textPrimary,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  pw.Widget _codeBlock(List<String> code, String language, _Styles styles) {
    final header = language.isEmpty ? 'code' : language;
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        color: _codeBg,
        borderRadius: pw.BorderRadius.circular(3),
        border: pw.Border.all(color: _outline, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: _outline, width: 0.5),
              ),
            ),
            child: pw.Text(
              pdfSafeText(header),
              style: pw.TextStyle(
                font: styles.regular,
                fontSize: 7.5,
                color: _textSecondary,
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text(
              pdfSafeText(code.join('\n')),
              style: pw.TextStyle(
                font: styles.mono,
                fontSize: 8,
                lineHeight: 1.35,
                color: _textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Parses the inline markdown that can appear inside a paragraph.
  ///
  /// Link targets are written out after the label rather than as clickable
  /// annotations, because a printed page cannot be tapped.
  List<pw.TextSpan> _inlineSpans(
    String text,
    _Styles styles, {
    required double baseSize,
    bool forceBold = false,
  }) {
    final spans = <pw.TextSpan>[];
    final pattern = RegExp(
      r'(\*\*(.+?)\*\*)' // bold
      r'|(\*(.+?)\*)' // italic
      r'|(`(.+?)`)' // inline code
      r'|(\[(.+?)\]\((.+?)\))', // link
    );

    var cursor = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(
          pw.TextSpan(
            text: text.substring(cursor, match.start),
            style: pw.TextStyle(
              font: forceBold ? styles.bold : styles.regular,
              fontSize: baseSize,
              color: _textPrimary,
            ),
          ),
        );
      }

      if (match.group(1) != null) {
        spans.add(
          pw.TextSpan(
            text: match.group(2)!,
            style: pw.TextStyle(
              font: styles.bold,
              fontSize: baseSize,
              color: _textPrimary,
            ),
          ),
        );
      } else if (match.group(3) != null) {
        spans.add(
          pw.TextSpan(
            text: match.group(4)!,
            style: pw.TextStyle(
              font: styles.italic,
              fontSize: baseSize,
              color: _textPrimary,
            ),
          ),
        );
      } else if (match.group(5) != null) {
        spans.add(
          pw.TextSpan(
            text: match.group(6)!,
            style: pw.TextStyle(
              font: styles.mono,
              fontSize: baseSize - 1,
              color: _textPrimary,
            ),
          ),
        );
      } else if (match.group(7) != null) {
        spans.add(
          pw.TextSpan(
            text: '${match.group(8)!} (${match.group(9)!})',
            style: pw.TextStyle(
              font: styles.regular,
              fontSize: baseSize,
              color: _accent,
            ),
          ),
        );
      }

      cursor = match.end;
    }

    if (cursor < text.length) {
      spans.add(
        pw.TextSpan(
          text: text.substring(cursor),
          style: pw.TextStyle(
            font: forceBold ? styles.bold : styles.regular,
            fontSize: baseSize,
            color: _textPrimary,
          ),
        ),
      );
    }

    return spans;
  }
}

/// The four font handles threaded through every render call.
class _Styles {
  const _Styles({
    required this.regular,
    required this.bold,
    required this.italic,
    required this.mono,
  });

  final pw.Font regular;
  final pw.Font bold;
  final pw.Font italic;
  final pw.Font mono;
}
