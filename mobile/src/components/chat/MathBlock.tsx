import { memo, useEffect, useMemo, useState } from 'react';
import { View } from 'react-native';
import { WebView } from 'react-native-webview';

import { files } from '@/core/services/files';
import { useTheme } from '@/theme/ThemeProvider';
import { katexCss, katexVersion } from './katexCss.generated';
import { MathError } from './MathError';
import { renderDisplayMath } from './mathHtml';

/**
 * A display formula in a small WebView that reports its own height.
 *
 * KaTeX's stylesheet (fonts inlined, about 360 KB) is written once to the cache
 * directory and linked from each formula's page, so a reply with ten formulas
 * does not push ten copies across the bridge. The page loads nothing else;
 * navigation away from it is refused, and its script only posts the measured
 * height.
 */
const cssName = `katex-${katexVersion}.css`;
let cssReady: Promise<void> | null = null;

function ensureCss(): Promise<void> {
  cssReady ??= (async () => {
    const path = `${files.cacheDir()}/${cssName}`;
    if (!(await files.exists(path))) await files.writeText(path, katexCss);
  })().catch((e: unknown) => {
    cssReady = null;
    throw e;
  });
  return cssReady;
}

export const MathBlock = memo(function MathBlock({ latex }: { latex: string }) {
  const { colors } = useTheme();
  const [height, setHeight] = useState(48);
  const [ready, setReady] = useState(false);
  const { html, ok } = useMemo(() => renderDisplayMath(latex), [latex]);

  useEffect(() => {
    let alive = true;
    // Without the stylesheet the hidden MathML copy still renders, so a write
    // failure degrades rather than blanks.
    const done = () => alive && setReady(true);
    ensureCss().then(done, done);
    return () => {
      alive = false;
    };
  }, []);

  const page = useMemo(
    () => `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"/>
<link rel="stylesheet" href="${cssName}"/>
<style>html,body{margin:0;padding:0;background:transparent;color:${colors.ink};}
body{font-size:14px;overflow-x:auto;overflow-y:hidden;scrollbar-width:none;}
.katex-display{margin:2px 0;}</style></head>
<body><div id="m">${html}</div>
<script>function post(){window.ReactNativeWebView.postMessage(String(document.getElementById('m').scrollHeight));}
post();(document.fonts&&document.fonts.ready?document.fonts.ready:Promise.resolve()).then(post);setTimeout(post,120);</script></body></html>`,
    [html, colors.ink],
  );

  if (!ok) return <MathError latex={latex} />;
  return (
    <View style={{ height, marginVertical: 2 }} accessibilityLabel={`Equation: ${latex}`}>
      {ready ? (
        <WebView
          source={{ html: page, baseUrl: `${files.toUri(files.cacheDir())}/` }}
          allowFileAccess
          allowFileAccessFromFileURLs
          onShouldStartLoadWithRequest={(req) => req.url.startsWith('file://') || req.url === 'about:blank' || req.url.startsWith('data:')}
          style={{ backgroundColor: 'transparent' }}
          scrollEnabled={false}
          javaScriptEnabled
          androidLayerType="hardware"
          onMessage={(e) => {
            const h = Number(e.nativeEvent.data);
            if (Number.isFinite(h) && h > 0) setHeight(Math.ceil(h) + 4);
          }}
          showsHorizontalScrollIndicator={false}
          setSupportMultipleWindows={false}
        />
      ) : null}
    </View>
  );
});
