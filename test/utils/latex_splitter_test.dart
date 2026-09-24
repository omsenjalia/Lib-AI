import 'package:flutter_test/flutter_test.dart';
import 'package:library_ai/core/utils/latex_splitter.dart';

/// Delimiter handling is the single most visible correctness risk in the chat
/// panel: a formula that fails to render looks like a broken answer, and a
/// sentence about money that renders as an equation looks ridiculous.
void main() {
  group('block maths', () {
    test(r'$$ ... $$ becomes one blockMath segment', () {
      final segments = splitLatex(r'Area is $$A = \pi r^2$$ for a circle.');

      expect(segments, hasLength(3));
      expect(segments[1].kind, SegmentKind.blockMath);
      expect(segments[1].text, r'A = \pi r^2');
    });

    test(r'\[ ... \] becomes blockMath', () {
      final segments = splitLatex(r'Thus \[ x = \frac{-b}{2a} \] holds.');

      expect(segments[1].kind, SegmentKind.blockMath);
      expect(segments[1].text, r'x = \frac{-b}{2a}');
    });

    test(r'\begin{align} ... \end{align} keeps its environment', () {
      final source = 'See:\n'
          r'\begin{align}a &= b \\ c &= d\end{align}'
          '\nDone.';

      final math = splitLatex(source).firstWhere((s) => s.isMath);
      expect(math.kind, SegmentKind.blockMath);
      // The environment markers are retained: the TeX renderer needs them.
      expect(math.text, contains(r'\begin{align}'));
      expect(math.text, contains(r'\end{align}'));
    });

    test('an unterminated $$ falls through as prose', () {
      const source = r'Broken $$x = 1';
      final segments = splitLatex(source);

      expect(segments.every((s) => !s.isMath), isTrue);
      expect(segments.single.text, source);
    });
  });

  group('inline maths', () {
    test(r'$ ... $ becomes inlineMath', () {
      final segments = splitLatex(r'The value $x^2$ grows fast.');

      expect(segments.map((s) => s.kind).toList(), [
        SegmentKind.text,
        SegmentKind.inlineMath,
        SegmentKind.text,
      ]);
      expect(segments[1].text, r'x^2');
    });

    test(r'\( ... \) becomes inlineMath', () {
      final segments = splitLatex(r'Given \(n = 5\) we proceed.');
      expect(segments[1].kind, SegmentKind.inlineMath);
      expect(segments[1].text, 'n = 5');
    });

    test('currency is never mistaken for maths', () {
      const prose = 'It costs \$5 and then \$10 more.';
      final segments = splitLatex(prose);

      // The escaped dollars are unescaped into text, and nothing is treated as
      // a formula.
      expect(segments, hasLength(1));
      expect(segments.single.kind, SegmentKind.text);
      expect(segments.single.text, contains('5 and'));
    });

    test('two dollar signs on the same line do become maths', () {
      // The splitter's dollar heuristic is intentionally permissive inside a
      // single line, matching what models actually emit ($x$), so this pairing
      // is expected to render as maths.
      final segments = splitLatex(r'We have $a + b$ and $c$.');
      final mathTexts = segments
          .where((s) => s.isMath)
          .map((s) => s.text)
          .toList();

      expect(mathTexts, contains('a + b'));
      expect(mathTexts, contains('c'));
    });

    test('a body with a newline is not inline maths', () {
      const source = 'Price \$5\nand \$10';
      final segments = splitLatex(source);
      expect(segments.every((s) => !s.isMath), isTrue);
    });
  });

  group('code is never maths', () {
    test('a fenced block containing dollar signs stays text', () {
      const source = 'Use it:\n'
          '```bash\n'
          r'echo $PATH and $$ for the pid'
          '\n```\n';

      final segments = splitLatex(source);
      expect(segments.every((s) => !s.isMath), isTrue);
    });

    test('an inline code span containing a dollar stays text', () {
      const source = r'The shell variable `$HOME` is set.';
      final segments = splitLatex(source);
      expect(segments.every((s) => !s.isMath), isTrue);
    });
  });

  group('extractInline: false', () {
    test('inline maths is left inside the prose for the markdown engine', () {
      final segments = splitLatex(
        r'The value $x^2$ grows fast.',
        extractInline: false,
      );

      expect(segments, hasLength(1));
      expect(segments.single.kind, SegmentKind.text);
      expect(segments.single.text, contains(r'$x^2$'));
    });

    test(r'\( ... \) is likewise preserved verbatim', () {
      final segments = splitLatex(
        r'Given \(n = 5\) we proceed.',
        extractInline: false,
      );

      expect(segments.single.text, contains(r'\(n = 5\)'));
    });

    test('display maths is still extracted', () {
      final segments = splitLatex(
        r'Area $$A = 1$$ here.',
        extractInline: false,
      );

      expect(segments.map((s) => s.kind), [
        SegmentKind.text,
        SegmentKind.blockMath,
        SegmentKind.text,
      ]);
    });
  });

  group('forceMath', () {
    test('bare LaTeX becomes inline maths when forced', () {
      final segments = splitLatex(
        r'Compute \frac{a}{b} now.',
        forceMath: true,
      );

      final math = segments.firstWhere((s) => s.isMath);
      expect(math.kind, SegmentKind.inlineMath);
      expect(math.text, r'\frac{a}{b}');
    });

    test('forceMath is off by default', () {
      final segments = splitLatex(r'Compute \frac{a}{b} now.');
      expect(segments.every((s) => !s.isMath), isTrue);
    });

    test('prose escapes such as \\n are not treated as commands', () {
      // The letter run after the backslash is `nis` - a newline escape followed
      // by the word "is" - which is not a command, so the sentence stays prose.
      final segments = splitLatex('A newline\nis not maths.', forceMath: true);
      expect(segments.every((s) => !s.isMath), isTrue);
      expect(segments.single.text, 'A newline\nis not maths.');
    });

    test('every single-letter prose escape stays prose', () {
      for (final escape in ['n', 't', 'r', 's', 'd', 'w', 'b']) {
        final source = 'A ${escape}is escaped.';
        final segments = splitLatex(source, forceMath: true);
        expect(
          segments.every((s) => !s.isMath),
          isTrue,
          reason: '\\$escape was treated as a command',
        );
      }
    });

    test('an unknown command name is left as prose', () {
      // A made-up command renders as an error inside a sentence, which is worse
      // than leaving the raw text visible. So an unrecognised name is prose.
      final segments = splitLatex(
        r'The \notacommand{x} here.',
        forceMath: true,
      );
      expect(segments.every((s) => !s.isMath), isTrue);
    });

    test('commands whose names start with an escape letter are still maths',
        () {
      // The vocabulary, not the first letter, is what decides: `\\theta` and
      // `\\sin` begin with letters that also begin prose escapes.
      for (final source in [r'\theta = 2', r'\sin x', r'\times 3', r'\to 1']) {
        final segments = splitLatex(source, forceMath: true);
        final maths = segments.where((s) => s.isMath).toList();
        expect(maths, isNotEmpty, reason: source);
        expect(maths.first.text, startsWith(source.split(' ').first));
      }
    });

    test('a fraction is maths even though it has no symbol of its own', () {
      // `\\frac` is rewritten to `(a)/(b)` by the text converter rather than
      // substituted for a character, so it is easy to leave out of a command
      // list. This is the regression guard for exactly that.
      for (final command in ['frac', 'dfrac', 'tfrac', 'binom']) {
        final segments = splitLatex(
          'Compute \\$command{a}{b} now.',
          forceMath: true,
        );
        expect(
          segments.any((s) => s.isMath),
          isTrue,
          reason: '\\$command was not treated as maths',
        );
      }
    });

    test('with extractInline false, forced maths is wrapped in dollars', () {
      final segments = splitLatex(
        r'Compute \frac{a}{b} now.',
        forceMath: true,
        extractInline: false,
      );

      expect(segments.single.kind, SegmentKind.text);
      expect(segments.single.text, contains(r'$\frac{a}{b}$'));
    });

    test('a trailing operator continues the forced span', () {
      final segments = splitLatex(
        r'So \alpha + \beta = \gamma',
        forceMath: true,
      );
      final math = segments.firstWhere((s) => s.isMath);
      expect(math.text, contains(r'\alpha'));
      expect(math.text, contains(r'\gamma'));
    });
  });

  group('edge cases', () {
    test('empty input yields one empty text segment', () {
      final segments = splitLatex('');
      expect(segments, hasLength(1));
      expect(segments.single.text, '');
    });

    test('empty surrounding text runs are dropped', () {
      final segments = splitLatex(r'$$x$$');
      expect(segments, hasLength(1));
      expect(segments.single.kind, SegmentKind.blockMath);
    });

    test('an empty maths body is not treated as maths', () {
      final segments = splitLatex(r'$$$$');
      expect(segments.every((s) => !s.isMath), isTrue);
    });

    test('LatexSegment equality is value based', () {
      const a = LatexSegment(text: 'x', kind: SegmentKind.inlineMath);
      const b = LatexSegment(text: 'x', kind: SegmentKind.inlineMath);
      const c = LatexSegment(text: 'x', kind: SegmentKind.blockMath);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
