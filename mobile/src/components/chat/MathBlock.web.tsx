import { createElement, memo, useMemo } from 'react';
import { View } from 'react-native';

import { useTheme } from '@/theme/ThemeProvider';
import { katexCss } from './katexCss.generated';
import { MathError } from './MathError';
import { renderDisplayMath } from './mathHtml';

/** Browser preview: KaTeX renders straight into the page; its stylesheet is injected once. */
let injected = false;
function injectCss() {
  if (injected || typeof document === 'undefined') return;
  injected = true;
  const style = document.createElement('style');
  // Same sizing as the Android WebView page: KaTeX scales its display maths to 1.21em.
  style.textContent = `${katexCss}
.katex-display{margin:2px 0}`;
  document.head.appendChild(style);
}

export const MathBlock = memo(function MathBlock({ latex }: { latex: string }) {
  const { colors } = useTheme();
  const { html, ok } = useMemo(() => renderDisplayMath(latex), [latex]);
  injectCss();
  if (!ok) return <MathError latex={latex} />;
  return (
    <View accessibilityLabel={`Equation: ${latex}`} style={{ marginVertical: 2 }}>
      {createElement('div', {
        style: { color: colors.ink, fontSize: 14, overflowX: 'auto', overflowY: 'hidden', scrollbarWidth: 'none' },
        dangerouslySetInnerHTML: { __html: html },
      })}
    </View>
  );
});
