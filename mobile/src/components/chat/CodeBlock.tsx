import * as Clipboard from 'expo-clipboard';
import { Check, Copy } from 'phosphor-react-native';
import { Highlight, type PrismTheme } from 'prism-react-renderer';
import { memo, useState } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';

import { AppText, PressableScale, useHaptic } from '@/components/ui/primitives';
import { useTheme } from '@/theme/ThemeProvider';
import { fonts, radius, space } from '@/theme/tokens';

/**
 * Fenced code: dark surface in both themes, highlighted, never wrapped,
 * scrolls sideways, one-tap copy. The palette is warm to sit with the canvas
 * rather than the usual blue-purple editor theme.
 */
const warmTheme: PrismTheme = {
  plain: { color: '#ECE8DF', backgroundColor: 'transparent' },
  styles: [
    { types: ['comment', 'prolog', 'doctype', 'cdata'], style: { color: '#8E8B82', fontStyle: 'italic' } },
    { types: ['punctuation', 'operator'], style: { color: '#BDB8AE' } },
    { types: ['keyword', 'atrule', 'important', 'selector'], style: { color: '#E59A7E' } },
    { types: ['string', 'char', 'attr-value', 'inserted', 'regex'], style: { color: '#B9CC8F' } },
    { types: ['number', 'boolean', 'constant', 'symbol'], style: { color: '#E6C07B' } },
    { types: ['function', 'class-name', 'builtin'], style: { color: '#9EC3D6' } },
    { types: ['tag', 'property', 'attr-name', 'variable'], style: { color: '#D8B4E2' } },
    { types: ['deleted'], style: { color: '#E08A7C' } },
  ],
};

const aliases: Record<string, string> = {
  js: 'javascript',
  ts: 'typescript',
  py: 'python',
  sh: 'bash',
  shell: 'bash',
  'c++': 'cpp',
  h: 'c',
  kt: 'kotlin',
  yml: 'yaml',
  html: 'markup',
  xml: 'markup',
  md: 'markdown',
};

export const CodeBlock = memo(function CodeBlock({ source, language }: { source: string; language: string }) {
  const { colors } = useTheme();
  const [copied, setCopied] = useState(false);
  const buzz = useHaptic();
  const lang = aliases[language.toLowerCase()] ?? language.toLowerCase();
  return (
    <View style={[styles.wrap, { backgroundColor: colors.codeSurface }]}>
      <View style={[styles.header, { borderBottomColor: 'rgba(255,255,255,0.07)' }]}>
        <AppText variant="caption" mono style={{ color: colors.codeMuted }}>
          {language || 'code'}
        </AppText>
        <PressableScale
          accessibilityRole="button"
          accessibilityLabel={copied ? 'Copied' : 'Copy code'}
          onPress={async () => {
            await Clipboard.setStringAsync(source);
            buzz('success');
            setCopied(true);
            setTimeout(() => setCopied(false), 1600);
          }}
          hitSlop={8}
          style={styles.copy}
        >
          {copied ? <Check size={15} color={colors.codeInk} /> : <Copy size={15} color={colors.codeMuted} />}
          <AppText variant="caption" style={{ color: copied ? colors.codeInk : colors.codeMuted }}>
            {copied ? 'Copied' : 'Copy'}
          </AppText>
        </PressableScale>
      </View>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ padding: space.sm }}>
        <Highlight code={source || ' '} language={lang} theme={warmTheme}>
          {({ tokens, getTokenProps }) => (
            <Text selectable style={styles.code}>
              {tokens.map((line, i) => (
                <Text key={i}>
                  {line.map((token, j) => {
                    // Prism marks a blank line with an empty newline token; the line break is added below.
                    if (token.empty) return null;
                    const p = getTokenProps({ token });
                    return (
                      <Text key={j} style={{ color: p.style?.color as string | undefined, fontStyle: p.style?.fontStyle === 'italic' ? 'italic' : 'normal' }}>
                        {p.children}
                      </Text>
                    );
                  })}
                  {i < tokens.length - 1 ? '\n' : ''}
                </Text>
              ))}
            </Text>
          )}
        </Highlight>
      </ScrollView>
    </View>
  );
});

const styles = StyleSheet.create({
  wrap: { borderRadius: radius.md, overflow: 'hidden' },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingLeft: space.sm,
    paddingRight: space.xs,
    paddingVertical: 6,
    borderBottomWidth: 1,
  },
  copy: { flexDirection: 'row', alignItems: 'center', gap: 5, paddingHorizontal: 6, paddingVertical: 3 },
  code: { fontFamily: fonts.mono, fontSize: 13, lineHeight: 20, color: '#ECE8DF' },
});
