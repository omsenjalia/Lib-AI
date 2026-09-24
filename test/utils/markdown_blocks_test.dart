import 'package:flutter_test/flutter_test.dart';
import 'package:library_ai/core/utils/markdown_blocks.dart';

/// The block splitter decides what the markdown engine sees, what the highlighter
/// sees, and what the TeX renderer sees. Getting it wrong is how a code sample
/// ends up typeset as mathematics.
void main() {
  group('code fences', () {
    test('a fenced block is extracted with its language', () {
      const input = 'Before\n'
          '```dart\n'
          'void main() {}\n'
          '```\n'
          'After';

      final blocks = splitMessageBlocks(input);

      expect(blocks, hasLength(3));
      expect(blocks[0], isA<ProseBlock>());
      expect(blocks[1], isA<CodeBlock>());

      final code = blocks[1] as CodeBlock;
      expect(code.language, 'dart');
      expect(code.source, 'void main() {}');
      expect(blocks[2], isA<ProseBlock>());
    });

    test('a fence with no language yields an empty language string', () {
      final blocks = splitMessageBlocks('```\nplain\n```');
      expect((blocks.single as CodeBlock).language, '');
      expect((blocks.single as CodeBlock).source, 'plain');
    });

    test('display maths inside a fence is not treated as maths', () {
      final blocks = splitMessageBlocks(
        '```tex\n'
        r'$$\frac{a}{b}$$'
        '\n```',
      );

      expect(blocks, hasLength(1));
      expect(blocks.single, isA<CodeBlock>());
      expect((blocks.single as CodeBlock).source, contains(r'\frac'));
    });

    test('an unterminated fence is code to the end of the message', () {
      // This is the shape of a streaming message mid-code-block.
      final blocks = splitMessageBlocks('Here:\n```python\nprint(1)\nprint(2)');

      expect(blocks, hasLength(2));
      expect(blocks.last, isA<CodeBlock>());
      expect((blocks.last as CodeBlock).source, 'print(1)\nprint(2)');
    });

    test('two fenced blocks produce two code blocks', () {
      final blocks = splitMessageBlocks(
        '```dart\nvar a = 1;\n```\n'
        'and\n'
        '```dart\nvar b = 2;\n```',
      );

      final code = blocks.whereType<CodeBlock>().toList();
      expect(code, hasLength(2));
      expect(code[0].source, 'var a = 1;');
      expect(code[1].source, 'var b = 2;');
    });
  });

  group('display maths', () {
    test(r'$$ ... $$ becomes a DisplayMathBlock', () {
      final blocks = splitMessageBlocks(r'Area: $$A = \pi r^2$$ done.');

      expect(blocks.map((b) => b.runtimeType).toList(), [
        ProseBlock,
        DisplayMathBlock,
        ProseBlock,
      ]);
      expect((blocks[1] as DisplayMathBlock).latex, r'A = \pi r^2');
    });

    test(r'\[ ... \] becomes a DisplayMathBlock', () {
      final blocks = splitMessageBlocks(r'So \[x = 1\] holds.');
      expect(blocks.whereType<DisplayMathBlock>(), hasLength(1));
    });

    test('inline maths stays inside the prose', () {
      // Critical for layout: if inline maths were extracted, the paragraph
      // would be broken into three stacked widgets.
      final blocks = splitMessageBlocks(r'The value $x^2$ grows fast.');

      expect(blocks, hasLength(1));
      expect(blocks.single, isA<ProseBlock>());
      expect((blocks.single as ProseBlock).text, contains(r'$x^2$'));
    });
  });

  group('prose', () {
    test('markdown structure is preserved untouched', () {
      const input = '# Heading\n\n- one\n- two\n\n| a | b |\n|---|---|\n| 1 | 2 |';
      final blocks = splitMessageBlocks(input);

      expect(blocks, hasLength(1));
      expect((blocks.single as ProseBlock).text, input);
    });

    test('text before and after maths keeps its order', () {
      final blocks = splitMessageBlocks(
        r'First $a$ middle $$b$$ last',
      );
      final kinds = blocks.map((b) => b.runtimeType).toList();

      expect(kinds, [ProseBlock, DisplayMathBlock, ProseBlock]);
      expect((blocks.first as ProseBlock).text, startsWith('First'));
      expect((blocks.last as ProseBlock).text.trim(), 'last');
    });

    test('whitespace-only runs between blocks are dropped', () {
      final blocks = splitMessageBlocks(
        'Text\n\n```dart\nx\n```\n\nMore',
      );
      expect(blocks.whereType<ProseBlock>(), hasLength(2));
    });

    test('an empty message produces no blocks', () {
      expect(splitMessageBlocks(''), isEmpty);
    });

    test('a whitespace-only message produces no blocks', () {
      expect(splitMessageBlocks('   \n\n  '), isEmpty);
    });
  });

  group('forceMath', () {
    test('bare LaTeX is wrapped so the markdown engine sees a formula', () {
      final blocks = splitMessageBlocks(
        r'Compute \frac{a}{b} now.',
        forceMath: true,
      );

      expect(blocks, hasLength(1));
      expect((blocks.single as ProseBlock).text, contains(r'$\frac{a}{b}$'));
    });

    test('without forceMath the same text is left alone', () {
      final blocks = splitMessageBlocks(r'Compute \frac{a}{b} now.');
      expect(
        (blocks.single as ProseBlock).text,
        isNot(contains(r'$')),
      );
    });
  });
}
