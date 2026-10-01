import { defaultPersonas } from '../constants';
import { openDriver } from './driver';
import type { SqlDriver } from './driverTypes';
import { emitChange } from './events';
import { migrations } from './schema';
import type {
  Conversation,
  ConversationSearchHit,
  Message,
  ModelInstallation,
  Persona,
  Role,
  UpdateCheck,
} from './types';

/**
 * The one SQLite file, and every query the app runs against it.
 *
 * Deletions are explicit even though foreign keys cascade, so behaviour never
 * silently depends on a pragma.
 */
let dbPromise: Promise<SqlDriver> | null = null;

export function getDb(): Promise<SqlDriver> {
  // A failed open is not cached, so Retry on the startup screen really retries.
  dbPromise ??= open().catch((e: unknown) => {
    dbPromise = null;
    throw e;
  });
  return dbPromise;
}

async function open(): Promise<SqlDriver> {
  // The file on a device; an in-memory sql.js database in the browser preview.
  const db = await openDriver();
  await db.execAsync('PRAGMA foreign_keys = ON;');
  const row = await db.getFirstAsync<{ user_version: number }>('PRAGMA user_version');
  const current = row?.user_version ?? 0;
  for (let v = current; v < migrations.length; v++) {
    await db.withTransactionAsync(async () => {
      await db.execAsync(migrations[v]);
      await db.execAsync(`PRAGMA user_version = ${v + 1}`);
    });
  }
  await seedPersonas(db);
  return db;
}

async function seedPersonas(db: SqlDriver): Promise<void> {
  const row = await db.getFirstAsync<{ n: number }>('SELECT COUNT(*) AS n FROM personas');
  if ((row?.n ?? 0) > 0) return;
  const now = Date.now();
  for (const p of defaultPersonas) {
    await db.runAsync(
      'INSERT INTO personas (name, emoji, system_prompt, is_built_in, created_at) VALUES (?, ?, ?, 1, ?)',
      [p.name, p.emoji, p.systemPrompt, now],
    );
  }
}

// --------------------------------------------------------------------- mapping

type Raw = Record<string, unknown>;
const n = (v: unknown) => (v === null || v === undefined ? null : Number(v));
const s = (v: unknown) => (v === null || v === undefined ? null : String(v));

const toPersona = (r: Raw): Persona => ({
  id: Number(r.id),
  name: String(r.name),
  emoji: String(r.emoji),
  systemPrompt: String(r.system_prompt),
  isBuiltIn: Boolean(r.is_built_in),
  createdAt: Number(r.created_at),
});

const toConversation = (r: Raw): Conversation => ({
  id: Number(r.id),
  title: String(r.title),
  modelId: s(r.model_id),
  personaId: n(r.persona_id),
  contextLengthOverride: n(r.context_length_override),
  pinned: Boolean(r.pinned),
  createdAt: Number(r.created_at),
  updatedAt: Number(r.updated_at),
});

const toMessage = (r: Raw): Message => ({
  id: Number(r.id),
  conversationId: Number(r.conversation_id),
  role: String(r.role) as Role,
  content: String(r.content),
  imagePath: s(r.image_path),
  isError: Boolean(r.is_error),
  renderMath: Boolean(r.render_math),
  tokenCount: n(r.token_count),
  isEstimatedTokens: Boolean(r.is_estimated_tokens),
  promptTokens: n(r.prompt_tokens),
  tokensPerSecond: n(r.tokens_per_second),
  generationMs: n(r.generation_ms),
  createdAt: Number(r.created_at),
});

const toInstallation = (r: Raw): ModelInstallation => ({
  modelId: String(r.model_id),
  quant: String(r.quant),
  fileName: String(r.file_name),
  localPath: String(r.local_path),
  mmprojPath: s(r.mmproj_path),
  sizeBytes: Number(r.size_bytes),
  sha256: s(r.sha256),
  repoSha: s(r.repo_sha),
  totalBytes: Number(r.total_bytes),
  downloadedAt: Number(r.downloaded_at),
});

const toUpdateCheck = (r: Raw): UpdateCheck => ({
  modelId: String(r.model_id),
  lastCheckedAt: Number(r.last_checked_at),
  remoteSha: s(r.remote_sha),
  updateAvailable: Boolean(r.update_available),
});

// -------------------------------------------------------------------- personas

export async function listPersonas(): Promise<Persona[]> {
  const db = await getDb();
  const rows = await db.getAllAsync<Raw>('SELECT * FROM personas ORDER BY is_built_in DESC, id ASC');
  return rows.map(toPersona);
}

export async function savePersona(p: { id?: number; name: string; emoji: string; systemPrompt: string }): Promise<number> {
  const db = await getDb();
  let id = p.id;
  if (id) {
    await db.runAsync('UPDATE personas SET name = ?, emoji = ?, system_prompt = ? WHERE id = ?', [
      p.name,
      p.emoji,
      p.systemPrompt,
      id,
    ]);
  } else {
    const r = await db.runAsync(
      'INSERT INTO personas (name, emoji, system_prompt, is_built_in, created_at) VALUES (?, ?, ?, 0, ?)',
      [p.name, p.emoji, p.systemPrompt, Date.now()],
    );
    id = r.lastInsertRowId;
  }
  emitChange('personas');
  return id;
}

export async function deletePersona(id: number): Promise<void> {
  const db = await getDb();
  await db.withTransactionAsync(async () => {
    await db.runAsync('UPDATE conversations SET persona_id = NULL WHERE persona_id = ?', [id]);
    await db.runAsync('DELETE FROM personas WHERE id = ? AND is_built_in = 0', [id]);
  });
  emitChange('personas', 'conversations');
}

// --------------------------------------------------------------- conversations

export async function listConversations(): Promise<Conversation[]> {
  const db = await getDb();
  const rows = await db.getAllAsync<Raw>('SELECT * FROM conversations ORDER BY pinned DESC, updated_at DESC');
  return rows.map(toConversation);
}

export async function conversationById(id: number): Promise<Conversation | null> {
  const db = await getDb();
  const r = await db.getFirstAsync<Raw>('SELECT * FROM conversations WHERE id = ?', [id]);
  return r ? toConversation(r) : null;
}

/** Title matches first, then message-body matches with a snippet around the hit. */
export async function searchConversations(query: string): Promise<ConversationSearchHit[]> {
  const q = query.trim();
  if (!q) return (await listConversations()).map((c) => ({ ...c, snippet: null }));
  const db = await getDb();
  const like = `%${q.replace(/[\\%_]/g, (m) => `\\${m}`)}%`;
  const rows = await db.getAllAsync<Raw>(
    `SELECT c.*, (
       SELECT m.content FROM messages m
       WHERE m.conversation_id = c.id AND m.is_error = 0 AND m.content LIKE ? ESCAPE '\\'
       ORDER BY m.id DESC LIMIT 1
     ) AS hit
     FROM conversations c
     WHERE c.title LIKE ? ESCAPE '\\'
        OR EXISTS (SELECT 1 FROM messages m WHERE m.conversation_id = c.id AND m.content LIKE ? ESCAPE '\\')
     ORDER BY (c.title LIKE ? ESCAPE '\\') DESC, c.updated_at DESC
     LIMIT 100`,
    [like, like, like, like],
  );
  return rows.map((r) => ({ ...toConversation(r), snippet: snippetAround(s(r.hit), q) }));
}

function snippetAround(text: string | null, q: string): string | null {
  if (!text) return null;
  const flat = text.replace(/\s+/g, ' ');
  const at = flat.toLowerCase().indexOf(q.toLowerCase());
  if (at === -1) return null;
  const start = Math.max(0, at - 32);
  return `${start > 0 ? '...' : ''}${flat.slice(start, at + q.length + 48)}`;
}

export async function createConversation(c: { title: string; modelId: string | null; personaId?: number | null }): Promise<number> {
  const db = await getDb();
  const now = Date.now();
  const r = await db.runAsync(
    'INSERT INTO conversations (title, model_id, persona_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
    [c.title.slice(0, 200) || 'New chat', c.modelId, c.personaId ?? null, now, now],
  );
  emitChange('conversations');
  return r.lastInsertRowId;
}

export async function updateConversation(
  id: number,
  patch: Partial<Pick<Conversation, 'title' | 'modelId' | 'personaId' | 'contextLengthOverride' | 'pinned'>>,
): Promise<void> {
  const db = await getDb();
  const sets: string[] = [];
  const args: (string | number | null)[] = [];
  const col: Record<string, string> = {
    title: 'title',
    modelId: 'model_id',
    personaId: 'persona_id',
    contextLengthOverride: 'context_length_override',
    pinned: 'pinned',
  };
  for (const [k, v] of Object.entries(patch)) {
    if (v === undefined) continue;
    sets.push(`${col[k]} = ?`);
    args.push(typeof v === 'boolean' ? (v ? 1 : 0) : (v as string | number | null));
  }
  if (!sets.length) return;
  await db.runAsync(`UPDATE conversations SET ${sets.join(', ')} WHERE id = ?`, [...args, id]);
  emitChange('conversations');
}

export async function touchConversation(id: number): Promise<void> {
  const db = await getDb();
  await db.runAsync('UPDATE conversations SET updated_at = ? WHERE id = ?', [Date.now(), id]);
  emitChange('conversations');
}

/** Returns what was deleted so the sidebar's Undo can put it back exactly. */
export async function deleteConversation(id: number): Promise<{ conversation: Conversation; messages: Message[] } | null> {
  const db = await getDb();
  const conversation = await conversationById(id);
  if (!conversation) return null;
  const messages = await messagesFor(id);
  await db.withTransactionAsync(async () => {
    await db.runAsync('DELETE FROM messages WHERE conversation_id = ?', [id]);
    await db.runAsync('DELETE FROM conversations WHERE id = ?', [id]);
  });
  emitChange('conversations', 'messages');
  return { conversation, messages };
}

export async function restoreConversation(snapshot: { conversation: Conversation; messages: Message[] }): Promise<void> {
  const db = await getDb();
  const c = snapshot.conversation;
  await db.withTransactionAsync(async () => {
    await db.runAsync(
      `INSERT INTO conversations (id, title, model_id, persona_id, context_length_override, pinned, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      [c.id, c.title, c.modelId, c.personaId, c.contextLengthOverride, c.pinned ? 1 : 0, c.createdAt, c.updatedAt],
    );
    for (const m of snapshot.messages) await insertMessageRow(db, m);
  });
  emitChange('conversations', 'messages');
}

export async function deleteAllConversations(): Promise<void> {
  const db = await getDb();
  await db.withTransactionAsync(async () => {
    await db.runAsync('DELETE FROM messages');
    await db.runAsync('DELETE FROM conversations');
  });
  emitChange('conversations', 'messages');
}

export async function duplicateConversation(id: number): Promise<number | null> {
  const source = await conversationById(id);
  if (!source) return null;
  const history = await messagesFor(id);
  const db = await getDb();
  let newId = 0;
  await db.withTransactionAsync(async () => {
    const now = Date.now();
    const r = await db.runAsync(
      'INSERT INTO conversations (title, model_id, persona_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
      [`${source.title} (copy)`.slice(0, 200), source.modelId, source.personaId, now, now],
    );
    newId = r.lastInsertRowId;
    for (const m of history) await insertMessageRow(db, { ...m, conversationId: newId }, false);
  });
  emitChange('conversations', 'messages');
  return newId;
}

// -------------------------------------------------------------------- messages

export async function messagesFor(conversationId: number): Promise<Message[]> {
  const db = await getDb();
  const rows = await db.getAllAsync<Raw>('SELECT * FROM messages WHERE conversation_id = ? ORDER BY id ASC', [
    conversationId,
  ]);
  return rows.map(toMessage);
}

async function insertMessageRow(db: SqlDriver, m: Message, keepId = true): Promise<number> {
  const r = await db.runAsync(
    `INSERT INTO messages (${keepId ? 'id, ' : ''}conversation_id, role, content, image_path, is_error, render_math,
       token_count, is_estimated_tokens, prompt_tokens, tokens_per_second, generation_ms, created_at)
     VALUES (${keepId ? '?, ' : ''}?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      ...(keepId ? [m.id] : []),
      m.conversationId,
      m.role,
      m.content,
      m.imagePath,
      m.isError ? 1 : 0,
      m.renderMath ? 1 : 0,
      m.tokenCount,
      m.isEstimatedTokens ? 1 : 0,
      m.promptTokens,
      m.tokensPerSecond,
      m.generationMs,
      m.createdAt,
    ],
  );
  return r.lastInsertRowId;
}

export async function addMessage(m: {
  conversationId: number;
  role: Role;
  content: string;
  imagePath?: string | null;
  isError?: boolean;
  tokenCount?: number | null;
  isEstimatedTokens?: boolean;
}): Promise<number> {
  const db = await getDb();
  const id = await insertMessageRow(
    db,
    {
      id: 0,
      conversationId: m.conversationId,
      role: m.role,
      content: m.content,
      imagePath: m.imagePath ?? null,
      isError: m.isError ?? false,
      renderMath: false,
      tokenCount: m.tokenCount ?? null,
      isEstimatedTokens: m.isEstimatedTokens ?? true,
      promptTokens: null,
      tokensPerSecond: null,
      generationMs: null,
      createdAt: Date.now(),
    },
    false,
  );
  emitChange('messages');
  return id;
}

export async function updateMessage(
  id: number,
  patch: Partial<
    Pick<Message, 'content' | 'renderMath' | 'tokenCount' | 'isEstimatedTokens' | 'isError' | 'promptTokens' | 'tokensPerSecond' | 'generationMs'>
  >,
  opts: { silent?: boolean } = {},
): Promise<void> {
  const db = await getDb();
  const col: Record<string, string> = {
    content: 'content',
    renderMath: 'render_math',
    tokenCount: 'token_count',
    isEstimatedTokens: 'is_estimated_tokens',
    isError: 'is_error',
    promptTokens: 'prompt_tokens',
    tokensPerSecond: 'tokens_per_second',
    generationMs: 'generation_ms',
  };
  const sets: string[] = [];
  const args: (string | number | null)[] = [];
  for (const [k, v] of Object.entries(patch)) {
    if (v === undefined) continue;
    sets.push(`${col[k]} = ?`);
    args.push(typeof v === 'boolean' ? (v ? 1 : 0) : (v as string | number | null));
  }
  if (!sets.length) return;
  await db.runAsync(`UPDATE messages SET ${sets.join(', ')} WHERE id = ?`, [...args, id]);
  // Streaming flushes are silent: the screen already shows the live text.
  if (!opts.silent) emitChange('messages');
}

export async function deleteMessage(id: number): Promise<void> {
  const db = await getDb();
  await db.runAsync('DELETE FROM messages WHERE id = ?', [id]);
  emitChange('messages');
}

/** Drops a message and everything after it: used by regenerate and edit-and-resend. */
export async function deleteMessagesFrom(conversationId: number, fromId: number): Promise<void> {
  const db = await getDb();
  await db.runAsync('DELETE FROM messages WHERE conversation_id = ? AND id >= ?', [conversationId, fromId]);
  emitChange('messages');
}

export async function messageStats(): Promise<{ conversations: number; messages: number }> {
  const db = await getDb();
  const c = await db.getFirstAsync<{ n: number }>('SELECT COUNT(*) AS n FROM conversations');
  const m = await db.getFirstAsync<{ n: number }>('SELECT COUNT(*) AS n FROM messages');
  return { conversations: c?.n ?? 0, messages: m?.n ?? 0 };
}

// --------------------------------------------------------------- installations

export async function listInstallations(): Promise<ModelInstallation[]> {
  const db = await getDb();
  return (await db.getAllAsync<Raw>('SELECT * FROM model_installations ORDER BY downloaded_at ASC')).map(toInstallation);
}

export async function installationFor(modelId: string): Promise<ModelInstallation | null> {
  const db = await getDb();
  const r = await db.getFirstAsync<Raw>('SELECT * FROM model_installations WHERE model_id = ?', [modelId]);
  return r ? toInstallation(r) : null;
}

export async function upsertInstallation(i: ModelInstallation): Promise<void> {
  const db = await getDb();
  await db.runAsync(
    `INSERT OR REPLACE INTO model_installations
       (model_id, quant, file_name, local_path, mmproj_path, size_bytes, sha256, repo_sha, total_bytes, downloaded_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [i.modelId, i.quant, i.fileName, i.localPath, i.mmprojPath, i.sizeBytes, i.sha256, i.repoSha, i.totalBytes, i.downloadedAt],
  );
  // A fresh download is the new baseline: any old "update available" is stale.
  await db.runAsync('DELETE FROM model_update_checks WHERE model_id = ?', [i.modelId]);
  emitChange('installations', 'updates');
}

export async function deleteInstallation(modelId: string): Promise<void> {
  const db = await getDb();
  await db.runAsync('DELETE FROM model_installations WHERE model_id = ?', [modelId]);
  await db.runAsync('DELETE FROM model_update_checks WHERE model_id = ?', [modelId]);
  emitChange('installations', 'updates');
}

// ------------------------------------------------------------------- updates

export async function listUpdateChecks(): Promise<UpdateCheck[]> {
  const db = await getDb();
  return (await db.getAllAsync<Raw>('SELECT * FROM model_update_checks')).map(toUpdateCheck);
}

export async function upsertUpdateCheck(u: UpdateCheck): Promise<void> {
  const db = await getDb();
  await db.runAsync(
    'INSERT OR REPLACE INTO model_update_checks (model_id, last_checked_at, remote_sha, update_available) VALUES (?, ?, ?, ?)',
    [u.modelId, u.lastCheckedAt, u.remoteSha, u.updateAvailable ? 1 : 0],
  );
  emitChange('updates');
}

// ------------------------------------------------------------------ settings

export async function allSettings(): Promise<Record<string, string>> {
  const db = await getDb();
  const rows = await db.getAllAsync<{ key: string; value: string }>('SELECT key, value FROM setting_entries');
  return Object.fromEntries(rows.map((r) => [r.key, r.value]));
}

export async function putSettings(entries: Record<string, string | null>): Promise<void> {
  const db = await getDb();
  await db.withTransactionAsync(async () => {
    for (const [key, value] of Object.entries(entries)) {
      if (value === null) await db.runAsync('DELETE FROM setting_entries WHERE key = ?', [key]);
      else await db.runAsync('INSERT OR REPLACE INTO setting_entries (key, value) VALUES (?, ?)', [key, value]);
    }
  });
  emitChange('settings');
}

// --------------------------------------------------------------------- notes

export async function documentCount(): Promise<number> {
  const db = await getDb();
  const r = await db.getFirstAsync<{ n: number }>('SELECT COUNT(*) AS n FROM documents');
  return r?.n ?? 0;
}

// -------------------------------------------------------------------- export

export async function exportAll(): Promise<{
  exportedAt: string;
  personas: Persona[];
  conversations: (Conversation & { messages: Message[] })[];
}> {
  const conversations = await listConversations();
  const out = [];
  for (const c of conversations) out.push({ ...c, messages: await messagesFor(c.id) });
  return { exportedAt: new Date().toISOString(), personas: await listPersonas(), conversations: out };
}
