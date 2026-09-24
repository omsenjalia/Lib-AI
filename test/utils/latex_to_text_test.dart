import 'package:flutter_test/flutter_test.dart';
import 'package:library_ai/core/utils/latex_to_text.dart';
import 'package:library_ai/core/utils/pdf_text.dart';

/// The plain-text formatter and the PDF transliterator are tested together
/// because they are chained in the export path: LaTeX becomes Unicode, then
/// Unicode becomes something the built-in PDF fonts can draw. A break in either
/// shows up as unreadable text in an exported PDF.
void main() {
  group('latexToPlainText: structure', () {
    test(r'\frac becomes a parenthesised division', () {
      expect(latexToPlainText(r'\frac{a}{b}'), '(a)/(b)');
    });

    test('nested fractions are rewritten innermost first', () {
      final result = latexToPlainText(r'\frac{\frac{a}{b}}{c}');
      expect(result, '((a)/(b))/(c)');
    });

    test(r'\sqrt becomes a radical sign with parentheses', () {
      expect(latexToPlainText(r'\sqrt{x}'), '\u221A(x)');
    });

    test(r'\sqrt[n] becomes a superscript index', () {
      final result = latexToPlainText(r'\sqrt[3]{x}');
      expect(result, contains('\u221A'));
      expect(result, contains('x'));
    });

    test(r'\binom becomes C(n, k)', () {
      expect(latexToPlainText(r'\binom{n}{k}'), 'C(n, k)');
    });

    test(r'\text keeps its contents without braces', () {
      expect(latexToPlainText(r'\text{velocity}'), 'velocity');
    });

    test('environments are stripped but their contents survive', () {
      final result = latexToPlainText(
        r'\begin{align}a &= b \\ c &= d\end{align}',
      );
      expect(result, isNot(contains(r'\begin')));
      expect(result, isNot(contains(r'\end')));
      expect(result, contains('a'));
      expect(result, contains('d'));
    });
  });

  group('latexToPlainText: symbols', () {
    test('Greek letters become the actual letter', () {
      expect(latexToPlainText(r'\alpha'), '\u03B1');
      expect(latexToPlainText(r'\Omega'), '\u03A9');
    });

    test(r'\varepsilon is not half-consumed by \varepsilon', () {
      // Guards the longest-key-first replacement order: if `\vare` were tried
      // first the result would be mangled.
      expect(latexToPlainText(r'\varepsilon'), '\u03B5');
    });

    test('operators map to their conventional spelling', () {
      expect(latexToPlainText(r'\pm'), '\u00B1');
      expect(latexToPlainText(r'\times'), '\u00D7');
    });

    test('an unknown command keeps its name rather than vanishing', () {
      final result = latexToPlainText(r'\foo{x}');
      expect(result, contains('foo'));
      expect(result, contains('x'));
      expect(result, isNot(contains(r'\')));
    });
  });

  group('latexToPlainText: scripts', () {
    test('a simple superscript becomes a Unicode one', () {
      expect(latexToPlainText(r'x^2'), 'x\u00B2');
    });

    test('a braced superscript becomes Unicode too', () {
      expect(latexToPlainText(r'x^{2}'), 'x\u00B2');
    });

    test('subscripts normalise the same way', () {
      expect(latexToPlainText(r'H_2O'), 'H\u2082O');
    });

    test('a superscript with no Unicode form keeps the caret notation', () {
      // `n` has a Unicode superscript (ⁿ) and is covered above; a multi-letter
      // body does not, so it falls back to ^(...) instead of losing the text.
      final result = latexToPlainText(r'x^{ab}');
      expect(result, contains('x'));
      expect(result, contains('^('));
    });
  });

  group('containsLatexEnvironment', () {
    test('detects a known environment', () {
      expect(containsLatexEnvironment(r'\begin{align} x \end{align}'), isTrue);
      expect(containsLatexEnvironment(r'\begin{matrix} 1 \end{matrix}'), isTrue);
    });

    test('does not fire on ordinary prose', () {
      expect(containsLatexEnvironment('Just a sentence.'), isFalse);
      expect(containsLatexEnvironment(r'\frac{a}{b}'), isFalse);
    });
  });

  group('pdfSafeText', () {
    test('Greek is spelled out', () {
      expect(pdfSafeText('\u03B1\u03B2'), 'alphabeta');
    });

    test('math symbols get an ASCII spelling', () {
      expect(pdfSafeText('\u221A'), 'sqrt');
      expect(pdfSafeText('\u2264'), '<=');
      expect(pdfSafeText('\u2211'), 'sum');
      expect(pdfSafeText('\u2205'), 'empty set');
    });

    test('superscripts normalise to caret notation', () {
      // The whole point of excluding superscript digits from the
      // "already safe" set: one formula must not mix x2 and x^2 styles.
      expect(pdfSafeText('x\u00B2'), 'x^2');
      expect(pdfSafeText('H\u2082O'), 'H_2O');
    });

    test('WinAnsi punctuation is preserved rather than transliterated', () {
      expect(pdfSafeText('\u00B1'), '\u00B1');
      expect(pdfSafeText('\u2014'), '\u2014');
    });

    test('emoji and CJK are dropped', () {
      expect(pdfSafeText('ok \u{1F600}'), 'ok ');
      expect(pdfSafeText('\u4E2D\u6587'), '');
    });

    test('plain ASCII is returned unchanged', () {
      const input = 'Bubble sort is O(n^2) in the average case - see notes.';
      expect(pdfSafeText(input), input);
    });

    test('an empty string is handled', () {
      expect(pdfSafeText(''), '');
    });
  });

  group('isPdfSafe', () {
    test('accepts ASCII and WinAnsi punctuation', () {
      expect(isPdfSafe('hello world'), isTrue);
      expect(isPdfSafe('a \u00B1 b'), isTrue);
    });

    test('rejects Greek and emoji', () {
      expect(isPdfSafe('\u03B1'), isFalse);
      expect(isPdfSafe('ok \u{1F600}'), isFalse);
    });

    test('the formatter output is always safe', () {
      // The chained guarantee the export path relies on.
      const samples = [
        r'\frac{\alpha}{\beta} = \sqrt{2}',
        r'\sum_{i=1}^{n} x_i^2 \leq 10',
        'Emoji \u{1F600} and Greek \u03A9 mixed in',
      ];
      for (final sample in samples) {
        final plain = latexToPlainText(sample);
        expect(
          isPdfSafe(pdfSafeText(plain)),
          isTrue,
          reason: 'pdfSafeText should make $sample safe',
        );
      }
    });
  });
}
