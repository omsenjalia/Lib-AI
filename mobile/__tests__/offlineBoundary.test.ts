import { readdirSync, readFileSync, statSync } from 'fs';
import { join, relative, sep } from 'path';

/**
 * The offline guarantee, enforced rather than asserted: only the model
 * management services may touch the network. Chat, history, rendering, export
 * and personas must work with the radio off, so nothing else may even import
 * a networking API. (Port of the Flutter build's pr-check boundary job.)
 */
const allowed = new Map<string, RegExp[]>([
  // HuggingFace metadata for the update badge. Never downloads.
  ['core/services/updateChecker.ts', [/\bfetch\(/]],
  // The model file transfer itself.
  ['core/services/files.native.ts', [/react-native-blob-util/]],
  // Reads link state for the Wi-Fi gate; sends nothing.
  ['core/services/connectivity.ts', [/@react-native-community\/netinfo/]],
]);

const networkApis: { name: string; re: RegExp }[] = [
  { name: 'fetch()', re: /(^|[^.\w])fetch\(/ },
  { name: 'XMLHttpRequest', re: /\bXMLHttpRequest\b/ },
  { name: 'WebSocket', re: /\bnew WebSocket\(/ },
  { name: 'axios', re: /from ['"]axios['"]/ },
  { name: 'react-native-blob-util', re: /from ['"]react-native-blob-util['"]/ },
  { name: 'netinfo', re: /from ['"]@react-native-community\/netinfo['"]/ },
  { name: 'expo-file-system download', re: /\b(downloadAsync|createDownloadResumable|createDownloadTask|downloadFileAsync)\b/ },
];

function walk(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const full = join(dir, name);
    return statSync(full).isDirectory() ? walk(full) : /\.(ts|tsx)$/.test(name) ? [full] : [];
  });
}

const srcRoot = join(__dirname, '..', 'src');

describe('offline boundary', () => {
  const files = walk(srcRoot).map((f) => ({ path: relative(srcRoot, f).split(sep).join('/'), text: readFileSync(f, 'utf8') }));

  it('scans the source tree', () => {
    expect(files.length).toBeGreaterThan(30);
  });

  it('keeps network APIs inside the model-management services', () => {
    const violations: string[] = [];
    for (const f of files) {
      const code = f.text.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '');
      for (const api of networkApis) {
        if (!api.re.test(code)) continue;
        const ok = allowed.get(f.path)?.some((re) => re.test(code));
        if (!ok) violations.push(`${f.path} uses ${api.name}`);
      }
    }
    expect(violations).toEqual([]);
  });

  it('the update checker cannot start a download', () => {
    const checker = files.find((f) => f.path === 'core/services/updateChecker.ts')!.text;
    expect(checker).not.toMatch(/downloadManager|downloads|\.download\(/);
  });
});
