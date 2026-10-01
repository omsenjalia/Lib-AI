import * as SQLite from 'expo-sqlite';
import { Platform } from 'react-native';

import { AppConstants } from '../constants';
import { getDb } from '../db/database';
import { emitChange } from '../db/events';
import { SettingKeys } from '../settings';
import { files } from './files';

/**
 * One-time import from the Flutter build.
 *
 * The React Native app keeps the Flutter application id, so installing it
 * over the old app (signed with the same key) keeps the data directory. The
 * old drift database sits at `<data>/app_flutter/library_ai.sqlite` and stores
 * dates as Unix seconds; models already live in `<data>/files/models`, which is
 * where this build looks, so nothing is downloaded twice.
 *
 * Imported: custom personas, conversations, messages, installations whose file
 * is still present, and the preferences this build understands. Not imported:
 * installations held in a user-chosen SAF folder (llama.rn needs a real file
 * path), and the retired subject tags.
 */
const importableSettings = new Set<string>([
  SettingKeys.themeMode,
  SettingKeys.chatFont,
  SettingKeys.systemPrompt,
  SettingKeys.defaultModelId,
  SettingKeys.contextLength,
  SettingKeys.temperature,
  SettingKeys.topP,
  SettingKeys.topK,
  SettingKeys.gpuLayers,
  SettingKeys.autoUpdateCheckEnabled,
]);

type Raw = Record<string, unknown>;
const ms = (v: unknown) => (typeof v === 'number' ? (v < 1e12 ? v * 1000 : v) : Date.now());

export type LegacyImportResult = { conversations: number; messages: number; models: number } | null;

export async function importLegacyData(): Promise<LegacyImportResult> {
  if (Platform.OS === 'web') return null;
  const db = await getDb();
  const done = await db.getFirstAsync<{ value: string }>('SELECT value FROM setting_entries WHERE key = ?', [
    SettingKeys.legacyImportDone,
  ]);
  if (done) return null;
  const markDone = () =>
    db.runAsync('INSERT OR REPLACE INTO setting_entries (key, value) VALUES (?, ?)', [SettingKeys.legacyImportDone, 'true']);

  const legacyDir = files.filesDir().replace(/\/files\/?$/, '/app_flutter');
  if (legacyDir === files.filesDir() || !(await files.exists(`${legacyDir}/${AppConstants.databaseName}`))) {
    await markDone();
    return null;
  }

  let legacy: SQLite.SQLiteDatabase | null = null;
  try {
    legacy = await SQLite.openDatabaseAsync(AppConstants.databaseName, {}, legacyDir);
    const result = { conversations: 0, messages: 0, models: 0 };

    await db.withTransactionAsync(async () => {
      // Personas: built-ins map by name onto this build's seeded rows.
      const personaMap = new Map<number, number>();
      const current = await db.getAllAsync<Raw>('SELECT id, name FROM personas WHERE is_built_in = 1');
      for (const p of await legacy!.getAllAsync<Raw>('SELECT * FROM personas')) {
        const builtIn = current.find((c) => c.name === p.name);
        if (Number(p.is_built_in) === 1 && builtIn) {
          personaMap.set(Number(p.id), Number(builtIn.id));
          continue;
        }
        const r = await db.runAsync(
          'INSERT INTO personas (name, emoji, system_prompt, is_built_in, created_at) VALUES (?, ?, ?, 0, ?)',
          [String(p.name), String(p.emoji ?? '\u{1F4DA}'), String(p.system_prompt ?? ''), ms(p.created_at)],
        );
        personaMap.set(Number(p.id), r.lastInsertRowId);
      }

      for (const c of await legacy!.getAllAsync<Raw>('SELECT * FROM conversations')) {
        const r = await db.runAsync(
          `INSERT INTO conversations (title, model_id, persona_id, context_length_override, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?)`,
          [
            String(c.title),
            c.model_id == null ? null : String(c.model_id),
            c.persona_id == null ? null : personaMap.get(Number(c.persona_id)) ?? null,
            c.context_length_override == null ? null : Number(c.context_length_override),
            ms(c.created_at),
            ms(c.updated_at),
          ],
        );
        result.conversations++;
        const msgs = await legacy!.getAllAsync<Raw>('SELECT * FROM messages WHERE conversation_id = ? ORDER BY id', [Number(c.id)]);
        for (const m of msgs) {
          await db.runAsync(
            `INSERT INTO messages (conversation_id, role, content, image_path, is_error, render_math, token_count,
               is_estimated_tokens, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [
              r.lastInsertRowId,
              String(m.role),
              String(m.content),
              m.image_path == null ? null : String(m.image_path),
              Number(m.is_error) ? 1 : 0,
              Number(m.render_math) ? 1 : 0,
              m.token_count == null ? null : Number(m.token_count),
              Number(m.is_estimated_tokens) ? 1 : 0,
              ms(m.created_at),
            ],
          );
          result.messages++;
        }
      }

      for (const i of await legacy!.getAllAsync<Raw>('SELECT * FROM model_installations')) {
        const path = String(i.local_path);
        if (path.startsWith('content://') || !(await files.exists(path))) continue;
        const mmproj = i.mmproj_path == null ? null : String(i.mmproj_path);
        await db.runAsync(
          `INSERT OR REPLACE INTO model_installations
             (model_id, quant, file_name, local_path, mmproj_path, size_bytes, sha256, repo_sha, total_bytes, downloaded_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [
            String(i.model_id),
            String(i.quant),
            String(i.file_name),
            path,
            mmproj && !mmproj.startsWith('content://') && (await files.exists(mmproj)) ? mmproj : null,
            Number(i.size_bytes),
            i.sha256 == null ? null : String(i.sha256),
            i.repo_sha == null ? null : String(i.repo_sha),
            Number(i.total_bytes),
            ms(i.downloaded_at),
          ],
        );
        result.models++;
      }

      for (const s of await legacy!.getAllAsync<Raw>('SELECT key, value FROM setting_entries')) {
        if (!importableSettings.has(String(s.key))) continue;
        await db.runAsync('INSERT OR REPLACE INTO setting_entries (key, value) VALUES (?, ?)', [String(s.key), String(s.value)]);
      }
      await markDone();
    });
    emitChange('personas', 'conversations', 'messages', 'installations', 'settings');
    return result;
  } catch {
    // A failed import must not block startup. It is retried on the next launch.
    return null;
  } finally {
    await legacy?.closeAsync();
  }
}
