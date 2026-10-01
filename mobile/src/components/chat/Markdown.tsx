import * as Linking from 'expo-linking';
import { Marked, type Token, type Tokens, type TokenizerAndRendererExtension } from 'marked';
import { memo, useMemo, type ReactNode } from 'react';
import { ScrollView, StyleSheet, Text, View, type TextStyle } from 'react-native';

import { AppText } from '@/components/ui/primitives';
import { latexToPlainText } from '@/core/utils/latexToText';
import { useTheme } from '@/theme/ThemeProvider';
import { fonts, radius, space, type } from '@/theme/tokens';

/**
 * Markdown to native components, from `marked`'s token stream. Written here
 * rather than taken from a library so inline maths, streaming and the type
 * scale behave exactly as the rest of the app does.
 *
 * Inline `$...$` stays inside the sentence it was written in: React Native has
 * no inline TeX engine, so it renders as readable Unicode (x², α, √(x)) in the
 * serif italic used for maths. Display maths never reaches this component;
 * the block splitter hands it to MathBlock.
 */
const inlineMath: TokenizerAndRendererExtension = {
  name: 'inlineMath',
  level: 'inline',
  start(src: string) {
    const i = src.indexOf('$');
    return i === -1 ? undefined : i;
  },
  tokenizer(src: string) {
    // Same guards as the splitter: non-space at both ends, one line.
    const m = /^\$(?!\s)([^$\n]*?[^\s$\\])\$(?!\d)/.exec(src) ?? /^\$([^\s$])\$/.exec(src);
    if (!m) return undefined;
    return { type: 'inlineMath', raw: m[0], text: m[1] };
  },
  renderer: () => '',
};

const parser = new Marked({ gfm: true, breaks: false, extensions: [inlineMath] });

type InlineCtx = { base: TextStyle; colors: ReturnType<typeof useTheme>['colors'] };

function renderInline(tokens: Token[] | undefined, ctx: InlineCtx, keyPrefix = ''): ReactNode[] {
  if (!tokens) return [];
  return tokens.map((t, i) => {
    const key = `${keyPrefix}${i}`;
    switch (t.type) {
      case 'text': {
        const tt = t as Tokens.Text;
        return tt.tokens ? (
          <Text key={key}>{renderInline(tt.tokens, ctx, `${key}.`)}</Text>
        ) : (
          <Text key={key}>{decode(tt.text)}</Text>
        );
      }
      case 'escape':
        return <Text key={key}>{(t as Tokens.Escape).text}</Text>;
      case 'strong':
        return (
          <Text key={key} style={{ fontFamily: fonts.sansBold }}>
            {renderInline((t as Tokens.Strong).tokens, ctx, `${key}.`)}
          </Text>
        );
      case 'em':
        return (
          <Text key={key} style={{ fontFamily: ctx.base.fontFamily === fonts.serif ? fonts.serifItalic : fonts.sansItalic }}>
            {renderInline((t as Tokens.Em).tokens, ctx, `${key}.`)}
          </Text>
        );
      case 'del':
        return (
          <Text key={key} style={{ textDecorationLine: 'line-through' }}>
            {renderInline((t as Tokens.Del).tokens, ctx, `${key}.`)}
          </Text>
        );
      case 'codespan':
        return (
          <Text
            key={key}
            style={{
              fontFamily: fonts.mono,
              fontSize: (ctx.base.fontSize ?? 16) * 0.86,
              backgroundColor: ctx.colors.surfaceRaised,
              color: ctx.colors.bodyStrong,
            }}
          >
            {` ${decode((t as Tokens.Codespan).text)} `}
          </Text>
        );
      case 'link': {
        const l = t as Tokens.Link;
        return (
          <Text
            key={key}
            accessibilityRole="link"
            onPress={() => void Linking.openURL(l.href)}
            style={{ color: ctx.colors.primary, textDecorationLine: 'underline' }}
          >
            {renderInline(l.tokens, ctx, `${key}.`)}
          </Text>
        );
      }
      case 'br':
        return <Text key={key}>{'\n'}</Text>;
      case 'checkbox':
        // The list item draws its own ☑/☐ glyph.
        return null;
      case 'image':
        return <Text key={key}>{`[${(t as Tokens.Image).text || 'image'}]`}</Text>;
      case 'inlineMath':
        return (
          <Text key={key} style={{ fontFamily: fonts.serifItalic, color: ctx.colors.ink }}>
            {latexToPlainText((t as unknown as { text: string }).text)}
          </Text>
        );
      default:
        return <Text key={key}>{'raw' in t ? decode(String(t.raw)) : ''}</Text>;
    }
  });
}

const entities: Record<string, string> = { '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'" };
const decode = (s: string) => s.replace(/&(amp|lt|gt|quot|#39);/g, (m) => entities[m] ?? m);

function Block({ token, ctx, depth }: { token: Token; ctx: InlineCtx; depth: number }) {
  const { colors } = ctx;
  switch (token.type) {
    case 'space':
    case 'checkbox':
      return null;
    case 'paragraph':
      return <Text style={ctx.base}>{renderInline((token as Tokens.Paragraph).tokens, ctx)}</Text>;
    case 'text': {
      const t = token as Tokens.Text;
      return <Text style={ctx.base}>{t.tokens ? renderInline(t.tokens, ctx) : decode(t.text)}</Text>;
    }
    case 'heading': {
      const h = token as Tokens.Heading;
      const size = h.depth <= 1 ? type.heading : h.depth === 2 ? type.title : { fontSize: 16.5, lineHeight: 24 };
      return (
        <Text
          accessibilityRole="header"
          style={[ctx.base, size, { fontFamily: h.depth <= 2 ? fonts.serif : fonts.sansBold, color: colors.ink, marginTop: space.xs }]}
        >
          {renderInline(h.tokens, ctx)}
        </Text>
      );
    }
    case 'list': {
      const l = token as Tokens.List;
      const start = typeof l.start === 'number' ? l.start : 1;
      return (
        <View style={{ gap: 6 }}>
          {l.items.map((item, i) => (
            <View key={i} style={{ flexDirection: 'row', paddingLeft: depth * 4 }}>
              <Text style={[ctx.base, { width: l.ordered ? 26 : 18, color: colors.muted, fontFamily: fonts.sansMedium }]}>
                {item.task ? (item.checked ? '☑' : '☐') : l.ordered ? `${start + i}.` : depth % 2 ? '◦' : '•'}
              </Text>
              <View style={{ flex: 1, gap: 6 }}>
                {item.tokens.map((child, j) => (
                  <Block key={j} token={child} ctx={ctx} depth={depth + 1} />
                ))}
              </View>
            </View>
          ))}
        </View>
      );
    }
    case 'blockquote':
      return (
        <View style={{ borderLeftWidth: 3, borderLeftColor: colors.hairline, paddingLeft: space.sm, gap: space.xs }}>
          {(token as Tokens.Blockquote).tokens.map((child, i) => (
            <Block key={i} token={child} ctx={{ ...ctx, base: { ...ctx.base, color: colors.body } }} depth={depth} />
          ))}
        </View>
      );
    case 'hr':
      return <View style={{ height: 1, backgroundColor: colors.hairline, marginVertical: space.xs }} />;
    case 'table':
      return <Table token={token as Tokens.Table} ctx={ctx} />;
    case 'code':
      // Fenced code is split out before markdown; an indented block lands here.
      return (
        <View style={{ backgroundColor: colors.codeSurface, borderRadius: radius.md, padding: space.sm }}>
          <Text style={{ fontFamily: fonts.mono, fontSize: 13, lineHeight: 19, color: colors.codeInk }}>
            {(token as Tokens.Code).text}
          </Text>
        </View>
      );
    case 'html':
      return <Text style={ctx.base}>{(token as Tokens.HTML).text.trim()}</Text>;
    default:
      return 'raw' in token ? <Text style={ctx.base}>{String(token.raw).trim()}</Text> : null;
  }
}

function Table({ token, ctx }: { token: Tokens.Table; ctx: InlineCtx }) {
  const { colors } = ctx;
  const cell = { ...ctx.base, fontSize: 14, lineHeight: 20 };
  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginVertical: 2 }}>
      <View style={[styles.table, { borderColor: colors.hairline }]}>
        <View style={[styles.row, { backgroundColor: colors.surfaceSoft }]}>
          {token.header.map((h, i) => (
            <View key={i} style={[styles.cell, { borderColor: colors.hairline }]}>
              <Text style={[cell, { fontFamily: fonts.sansBold }]}>{renderInline(h.tokens, ctx)}</Text>
            </View>
          ))}
        </View>
        {token.rows.map((row, r) => (
          <View key={r} style={[styles.row, { borderTopWidth: 1, borderColor: colors.hairlineSoft }]}>
            {row.map((c, i) => (
              <View key={i} style={[styles.cell, { borderColor: colors.hairline }]}>
                <Text style={[cell, { textAlign: token.align[i] === 'right' ? 'right' : token.align[i] === 'center' ? 'center' : 'left' }]}>
                  {renderInline(c.tokens, ctx)}
                </Text>
              </View>
            ))}
          </View>
        ))}
      </View>
    </ScrollView>
  );
}

export const Markdown = memo(function Markdown({ text, muted }: { text: string; muted?: boolean }) {
  const { colors, chatFont } = useTheme();
  const tokens = useMemo(() => parser.lexer(text), [text]);
  const ctx: InlineCtx = {
    colors,
    base: { ...type.body, fontFamily: chatFont, color: muted ? colors.body : colors.ink },
  };
  return (
    <View style={{ gap: space.sm }}>
      {tokens.map((t, i) => (
        <Block key={i} token={t} ctx={ctx} depth={0} />
      ))}
    </View>
  );
});

/** Plain fallback used for user turns, which are never markdown-rendered. */
export function PlainText({ text }: { text: string }) {
  const { chatFont } = useTheme();
  return (
    <AppText selectable style={{ fontFamily: chatFont }}>
      {text}
    </AppText>
  );
}

const styles = StyleSheet.create({
  table: { borderWidth: 1, borderRadius: radius.sm, overflow: 'hidden' },
  row: { flexDirection: 'row' },
  cell: { minWidth: 96, maxWidth: 260, paddingHorizontal: 10, paddingVertical: 7 },
});
