import type { Message, Persona } from '../src/core/db/types';
import { buildPrompt, maxTokensFor, systemPromptFor } from '../src/core/prompt';

let nextId = 1;
const msg = (role: 'user' | 'assistant', content: string, over: Partial<Message> = {}): Message => ({
  id: nextId++,
  conversationId: 1,
  role,
  content,
  imagePath: null,
  isError: false,
  renderMath: false,
  tokenCount: null,
  isEstimatedTokens: true,
  promptTokens: null,
  tokensPerSecond: null,
  generationMs: null,
  createdAt: 0,
  ...over,
});

const persona: Persona = { id: 1, name: 'Tutor', emoji: 'x', systemPrompt: 'PERSONA', isBuiltIn: true, createdAt: 0 };

describe('system prompt', () => {
  it('prefers persona, then user default, then built-in', () => {
    expect(systemPromptFor(persona, 'MINE')).toMatch(/^PERSONA/);
    expect(systemPromptFor(null, 'MINE')).toMatch(/^MINE/);
    expect(systemPromptFor(null, null)).toMatch(/^You are a study assistant/);
  });
  it('always says the user is offline', () => {
    expect(systemPromptFor(null, null)).toContain('no internet access');
  });
});

describe('buildPrompt', () => {
  const base = { persona: null, userDefaultPrompt: null, contextLength: 4096, visionReady: false };

  it('skips errors and empty placeholders', () => {
    const p = buildPrompt({
      ...base,
      history: [msg('user', 'q'), msg('assistant', 'boom', { isError: true }), msg('assistant', '')],
    });
    expect(p.map((m) => m.content)).toEqual([expect.any(String), 'q']);
  });

  it('keeps the newest turns when the budget runs out', () => {
    const long = 'x'.repeat(4000); // ~1000 tokens each
    const history = [msg('user', `old ${long}`), msg('assistant', `mid ${long}`), msg('user', `new ${long}`)];
    const p = buildPrompt({ ...base, contextLength: 2048, history });
    expect(p[p.length - 1].content.startsWith('new')).toBe(true);
    expect(p.some((m) => m.content.startsWith('old'))).toBe(false);
  });

  it('always keeps at least the latest turn', () => {
    const p = buildPrompt({ ...base, contextLength: 512, history: [msg('user', 'y'.repeat(10_000))] });
    expect(p).toHaveLength(2);
  });

  it('caps the history at 40 messages', () => {
    const history = Array.from({ length: 60 }, (_, i) => msg(i % 2 ? 'assistant' : 'user', `m${i}`));
    expect(buildPrompt({ ...base, contextLength: 100_000, history })).toHaveLength(41);
  });

  it('strips past reasoning from assistant turns', () => {
    const p = buildPrompt({ ...base, history: [msg('user', 'q'), msg('assistant', '<think>secret</think>Answer')] });
    expect(p[2].content).toBe('Answer');
  });

  it('attaches only the newest image, and only with vision ready', () => {
    const history = [msg('user', 'a', { imagePath: '/1.jpg' }), msg('user', 'b', { imagePath: '/2.jpg' })];
    expect(buildPrompt({ ...base, history }).every((m) => !m.imagePath)).toBe(true);
    const withVision = buildPrompt({ ...base, visionReady: true, history });
    expect(withVision.map((m) => m.imagePath ?? null)).toEqual([null, null, '/2.jpg']);
  });
});

describe('maxTokensFor', () => {
  it('stays between a paragraph and 4096', () => {
    expect(maxTokensFor([{ role: 'user', content: 'x'.repeat(100_000) }], 4096)).toBe(128);
    expect(maxTokensFor([{ role: 'user', content: 'hi' }], 100_000)).toBe(4096);
  });
});
