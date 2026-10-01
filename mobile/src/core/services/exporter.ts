import * as Print from 'expo-print';
import * as Sharing from 'expo-sharing';
import katex from 'katex';
import { marked } from 'marked';
import { Platform } from 'react-native';

import { katexCss } from '../../components/chat/katexCss.generated';
import { AppConstants } from '../constants';
import * as db from '../db/database';
import type { Conversation, Message } from '../db/types';
import { formatAbsoluteTime, slugify } from '../utils/formatters';
import { splitLatex } from '../utils/latexSplitter';
import { splitMessageBlocks } from '../utils/markdownBlocks';
import { files } from './files';

/**
 * Exports. PDFs are rendered by the system print engine from HTML, so they
 * carry real Unicode and real typeset maths (KaTeX with its fonts embedded).
 * That removes the Flutter build's WinAnsi-only font workaround: no more
 * `alpha` for α in exports.
 *
 * Everything here runs offline.
 */
const escapeHtml = (s: string) =>
  s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);

function tex(latex: string, displayMode: boolean): string {
  try {
    return katex.renderToString(latex, { displayMode, output: 'htmlAndMathml', throwOnError: true, strict: 'ignore' });
  } catch {
    return `<code class="tex-error">${escapeHtml(latex)}</code>`;
  }
}

/** Markdown with inline maths swapped for placeholders, so marked never sees TeX. */
function proseToHtml(text: string): string {
  const math: string[] = [];
  const md = splitLatex(text)
    .map((seg) => {
      if (seg.kind === 'text') return seg.text;
      math.push(tex(seg.text, seg.kind === 'blockMath'));
      return `@@MATH${math.length - 1}@@`;
    })
    .join('');
  const html = marked.parse(md, { async: false, gfm: true, breaks: false }) as string;
  return html.replace(/@@MATH(\d+)@@/g, (_, i) => math[Number(i)]);
}

export function messageToHtml(content: string, forceMath = false): string {
  return splitMessageBlocks(content, { forceMath })
    .map((b) => {
      switch (b.type) {
        case 'prose':
          return proseToHtml(b.text);
        case 'math':
          return `<div class="math">${tex(b.latex, true)}</div>`;
        case 'code':
          return `<pre><code>${escapeHtml(b.source)}</code></pre>`;
        case 'think':
          return '';
      }
    })
    .join('\n');
}

export function conversationHtml(conversation: Conversation, messages: Message[], modelName: string | null): string {
  const turns = messages
    .filter((m) => !m.isError && m.content.trim())
    .map(
      (m) => `
      <section class="turn ${m.role}">
        <div class="who">${m.role === 'user' ? 'You' : escapeHtml(modelName ?? 'Assistant')}</div>
        <div class="body">${m.role === 'user' ? `<p>${escapeHtml(m.content).replace(/\n/g, '<br/>')}</p>` : messageToHtml(m.content, m.renderMath)}</div>
      </section>`,
    )
    .join('\n');
  // Light on white on purpose: a PDF is read on paper and in other people's viewers.
  return `<!doctype html><html><head><meta charset="utf-8"/>
  <style>${katexCss}</style>
  <style>
    @page { margin: 18mm 16mm; }
    body { font-family: Georgia, 'Noto Serif', serif; color: #141413; font-size: 11.5pt; line-height: 1.55; }
    header { border-bottom: 1px solid #E6DFD8; padding-bottom: 10px; margin-bottom: 18px; }
    h1.title { font-size: 20pt; font-weight: 400; margin: 0 0 4px; }
    .meta { color: #6C6A64; font: 9pt sans-serif; }
    .turn { margin: 0 0 16px; page-break-inside: avoid; }
    .who { font: 600 8.5pt sans-serif; letter-spacing: .06em; text-transform: uppercase; color: #A9583E; margin-bottom: 4px; }
    .turn.user .body { background: #F5F0E8; border-radius: 10px; padding: 8px 12px; }
    pre { background: #181715; color: #FAF9F5; padding: 10px 12px; border-radius: 8px; font: 9pt 'JetBrains Mono', monospace; white-space: pre-wrap; }
    code { font-family: 'JetBrains Mono', monospace; font-size: 9.5pt; }
    table { border-collapse: collapse; margin: 8px 0; }
    td, th { border: 1px solid #E6DFD8; padding: 4px 8px; }
    .math { text-align: center; margin: 8px 0; overflow-x: auto; }
    .tex-error { color: #C64545; }
    blockquote { border-left: 3px solid #E6DFD8; margin: 8px 0; padding-left: 12px; color: #3D3D3A; }
  </style></head><body>
  <header><h1 class="title">${escapeHtml(conversation.title)}</h1>
  <div class="meta">${AppConstants.appName}. Exported ${formatAbsoluteTime(Date.now())}${modelName ? `. Model: ${escapeHtml(modelName)}` : ''}</div></header>
  ${turns}
  </body></html>`;
}

export function conversationMarkdown(conversation: Conversation, messages: Message[]): string {
  const lines = [`# ${conversation.title}`, '', `_Exported from ${AppConstants.appName} on ${formatAbsoluteTime(Date.now())}_`, ''];
  for (const m of messages) {
    if (m.isError || !m.content.trim()) continue;
    lines.push(`## ${m.role === 'user' ? 'You' : 'Assistant'}`, '', m.content.trim(), '');
  }
  return lines.join('\n');
}

const webUnavailable = () => {
  throw new Error('Sharing files is available in the Android app.');
};

export async function sharePdf(conversationId: number, modelName: string | null): Promise<void> {
  const conversation = await db.conversationById(conversationId);
  if (!conversation) return;
  const html = conversationHtml(conversation, await db.messagesFor(conversationId), modelName);
  if (Platform.OS === 'web') {
    await Print.printAsync({ html });
    return;
  }
  const { uri } = await Print.printToFileAsync({ html });
  const dest = `${files.exportsDir()}/${slugify(conversation.title)}.pdf`;
  await files.mkdirp(files.exportsDir());
  await files.move(uri, dest);
  await Sharing.shareAsync(files.toUri(dest), { mimeType: 'application/pdf', UTI: 'com.adobe.pdf', dialogTitle: conversation.title });
}

export async function shareMarkdown(conversationId: number): Promise<void> {
  if (Platform.OS === 'web') webUnavailable();
  const conversation = await db.conversationById(conversationId);
  if (!conversation) return;
  const dest = `${files.exportsDir()}/${slugify(conversation.title)}.md`;
  await files.mkdirp(files.exportsDir());
  await files.writeText(dest, conversationMarkdown(conversation, await db.messagesFor(conversationId)));
  await Sharing.shareAsync(files.toUri(dest), { mimeType: 'text/markdown', dialogTitle: conversation.title });
}

/** Every conversation and persona as one JSON file: the whole-library backup. */
export async function shareBackup(): Promise<void> {
  if (Platform.OS === 'web') webUnavailable();
  const data = await db.exportAll();
  const stamp = new Date().toISOString().slice(0, 10);
  const dest = `${files.exportsDir()}/library-ai-backup-${stamp}.json`;
  await files.mkdirp(files.exportsDir());
  await files.writeText(dest, JSON.stringify(data, null, 2));
  await Sharing.shareAsync(files.toUri(dest), { mimeType: 'application/json', dialogTitle: 'Library AI backup' });
}
