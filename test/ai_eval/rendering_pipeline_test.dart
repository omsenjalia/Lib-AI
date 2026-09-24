/// Offline evaluation of the answer-rendering pipeline.
///
/// The prompts below are real-shaped model outputs, not fixtures written to make
/// the test pass: a worked derivation, a code answer with an explanation, a
/// comparison table, and a model that ignored the "use LaTeX delimiters"
/// instruction. Each one is pushed through the same pipeline the chat panel and
/// the PDF exporter use, and the assertions are about what a student would
/// actually see.
///
/// What this cannot check is whether a *model* produces good answers - that needs
/// a device and a loaded GGUF. What it can check is that the app does not mangle
/// a good answer, which is the failure mode that is fully in our control.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:library_ai/core/utils/latex_splitter.dart';
import 'package:library_ai/core/utils/latex_to_text.dart';
import 'package:library_ai/core/utils/markdown_blocks.dart';
import 'package:library_ai/core/utils/pdf_text.dart';


void main() {
  group('scenario: worked derivation with a display equation', () {
    const answer = r'''
To solve $ax^2 + bx + c = 0$ we complete the square:

$$x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$$

The discriminant $b^2 - 4ac$ decides the number of real roots:

- positive: two distinct real roots
- zero: one repeated root
- negative: no real roots
''';

    test('the display equation is separated from the prose', () {
      final blocks = splitMessageBlocks(answer);
      final maths = blocks.whereType<DisplayMathBlock>().toList();

      expect(maths, hasLength(1));
      expect(maths.single.latex, contains(r'\frac'));
      expect(maths.single.latex, contains(r'\sqrt'));
    });

    test('the inline maths stays in the sentences that use it', () {
      final blocks = splitMessageBlocks(answer);
      final prose =
          blocks.whereType<ProseBlock>().map((b) => b.text).join('\n');

      expect(prose, contains(r'$ax^2 + bx + c = 0$'));
      expect(prose, contains(r'$b^2 - 4ac$'));
    });

    test('the bullet list survives for the markdown engine', () {
      final blocks = splitMessageBlocks(answer);
      final prose =
          blocks.whereType<ProseBlock>().map((b) => b.text).join('\n');

      expect(prose, contains('- positive: two distinct real roots'));
    });

    test('the exported plain text is readable and PDF-safe', () {
      final plain = latexToPlainText(answer);
      final safe = pdfSafeText(plain);

      expect(safe, contains('2a'));
      expect(isPdfSafe(safe), isTrue);
      expect(plain, isNot(contains(r'\frac')));
    });
  });

  group('scenario: code answer with an explanation', () {
    const answer = '''
Binary search halves the interval each step:

```dart
int search(List<int> xs, int target) {
  var low = 0, high = xs.length - 1;
  while (low <= high) {
    final mid = low + (high - low) ~/ 2;
    if (xs[mid] == target) return mid;
    if (xs[mid] < target) low = mid + 1; else high = mid - 1;
  }
  return -1;
}
```

Its cost is \$O(\\log n)\$ because the interval halves each iteration.
''';

    test('exactly one code block is extracted, with its language', () {
      final blocks = splitMessageBlocks(answer);
      final code = blocks.whereType<CodeBlock>().toList();

      expect(code, hasLength(1));
      expect(code.single.language, 'dart');
      expect(code.single.source, contains('while (low <= high)'));
    });

    test('LaTeX inside the code block is not treated as maths', () {
      const withLatexCode = 'See:\n'
          '```python\n'
          r'# \frac{a}{b} is not rendered here'
          '\n```';

      final blocks = splitMessageBlocks(withLatexCode);
      expect(blocks.whereType<DisplayMathBlock>(), isEmpty);
      expect(blocks.whereType<CodeBlock>(), hasLength(1));
    });

    test('the trailing inline maths is found after the code block', () {
      final blocks = splitMessageBlocks(answer);
      final prose =
          blocks.whereType<ProseBlock>().map((b) => b.text).join('\n');

      expect(prose, contains(r'$O(\log n)$'));
    });

    test('the code block survives PDF export as monospaced text', () {
      final plain = latexToPlainText(answer);
      expect(plain, contains('return -1;'));
      expect(pdfSafeText(plain), contains('return -1;'));
    });
  });

  group('scenario: comparison table', () {
    const answer = '''
| Algorithm | Best | Average | Worst |
|---|---|---|---|
| Quick sort | \$O(n \\log n)\$ | \$O(n \\log n)\$ | \$O(n^2)\$ |
| Merge sort | \$O(n \\log n)\$ | \$O(n \\log n)\$ | \$O(n \\log n)\$ |

Merge sort is stable; quick sort usually is not.
''';

    test('the table is left to the markdown engine', () {
      final blocks = splitMessageBlocks(answer);
      final prose =
          blocks.whereType<ProseBlock>().map((b) => b.text).join('\n');

      expect(prose, contains('| Algorithm | Best | Average | Worst |'));
      expect(prose, contains('|---|'));
    });

    test('no part of the table is mistaken for display maths', () {
      final blocks = splitMessageBlocks(answer);
      expect(blocks.whereType<DisplayMathBlock>(), isEmpty);
    });

    test('the PDF export keeps the pipes and drops the backslashes', () {
      final plain = latexToPlainText(answer);
      expect(plain, contains('| Quick sort |'));
      expect(plain, isNot(contains(r'\log')));
    });
  });

  group('scenario: a model that ignores the formatting instruction', () {
    // No delimiters anywhere: exactly why the per-message "Render math" toggle
    // exists.
    const answer = r'''
The derivative of x^n is n x^{n-1}.

To integrate \frac{1}{x} you get \ln|x| + C.

For a Gaussian, \int_{-\infty}^{\infty} e^{-x^2} dx = \sqrt{\pi}.
''';

    test('without the toggle nothing is treated as maths', () {
      final blocks = splitMessageBlocks(answer);
      expect(blocks.whereType<DisplayMathBlock>(), isEmpty);
      expect(blocks.every((b) => b is ProseBlock), isTrue);
    });

    test('with the toggle the commands become inline maths', () {
      final blocks = splitMessageBlocks(answer, forceMath: true);
      final prose = blocks.whereType<ProseBlock>().map((b) => b.text).join('\n');

      expect(prose, contains(r'$\frac{1}{x}$'));
      expect(prose, contains(r'\sqrt{\pi}'));
    });

    test('the toggle does not break the surrounding sentences', () {
      final blocks = splitMessageBlocks(answer, forceMath: true);
      final prose = blocks.whereType<ProseBlock>().map((b) => b.text).join('\n');

      expect(prose, contains('The derivative of'));
      expect(prose, contains('For a Gaussian,'));
    });

    test('the same answer exports as readable plain text', () {
      final plain = latexToPlainText(answer);
      expect(plain, contains('(1)/(x)'));
      expect(plain, contains('\u221A'));
      expect(isPdfSafe(pdfSafeText(plain)), isTrue);
    });
  });

  group('scenario: an answer that is still streaming', () {
    test('an unterminated code fence renders as code, not as a crash', () {
      const partial = 'Here is the loop:\n```python\nfor i in range(10):';

      final blocks = splitMessageBlocks(partial);
      final code = blocks.whereType<CodeBlock>().toList();

      expect(code, hasLength(1));
      expect(code.single.language, 'python');
      expect(code.single.source, contains('for i in range(10):'));
    });

    test('an unterminated display equation is left as prose', () {
      const partial = r'The result is $$x = \frac{1}{2}';
      final blocks = splitMessageBlocks(partial);

      expect(blocks.whereType<DisplayMathBlock>(), isEmpty);
      expect(
        (blocks.single as ProseBlock).text,
        contains('The result is'),
      );
    });

    test('an incomplete sentence with an open inline dollar stays text', () {
      final segments = splitLatex(r'The cost is $O(n');
      expect(segments.every((s) => !s.isMath), isTrue);
    });
  });

  group('scenario: OCR-style answer about a photographed question', () {
    const answer = r'''
From the image, the question asks for the area of a circle with $r = 7$.

$$A = \pi r^2 = \pi \cdot 49 \approx 153.94$$

So the area is about $153.94$ square units.
''';

    test('it renders and exports without loss', () {
      final blocks = splitMessageBlocks(answer);
      expect(blocks.whereType<DisplayMathBlock>(), hasLength(1));

      final prose = blocks.whereType<ProseBlock>().map((b) => b.text).join('\n');
      expect(prose, contains(r'$r = 7$'));

      // The formula itself lives in the display block, delimiters stripped.
      final maths = blocks.whereType<DisplayMathBlock>().single;
      expect(maths.latex, contains(r'\pi'));

      final safe = pdfSafeText(latexToPlainText(answer));
      expect(isPdfSafe(safe), isTrue);
      expect(safe, contains('153.94'));
    });
  });
}
