import { openDriver } from '../src/core/db/driver.web';
import { migrations } from '../src/core/db/schema';

/**
 * Runs the real migrations against real SQLite (sql.js, the preview driver),
 * so a typo in a migration fails here rather than on a phone at first launch.
 */
async function migrated() {
  const db = await openDriver();
  await db.execAsync('PRAGMA foreign_keys = ON;');
  for (let v = 0; v < migrations.length; v++) {
    await db.withTransactionAsync(async () => {
      await db.execAsync(migrations[v]);
      await db.execAsync(`PRAGMA user_version = ${v + 1}`);
    });
  }
  return db;
}

describe('schema migrations', () => {
  it('apply cleanly in order and record the version', async () => {
    const db = await migrated();
    expect((await db.getFirstAsync<{ user_version: number }>('PRAGMA user_version'))?.user_version).toBe(migrations.length);
  });

  it('give messages the per-reply stats columns', async () => {
    const db = await migrated();
    const cols = (await db.getAllAsync<{ name: string }>('PRAGMA table_info(messages)')).map((c) => c.name);
    expect(cols).toEqual(expect.arrayContaining(['prompt_tokens', 'tokens_per_second', 'generation_ms', 'is_estimated_tokens']));
  });

  it('cascade a conversation delete to its messages', async () => {
    const db = await migrated();
    const c = await db.runAsync('INSERT INTO conversations (title, created_at, updated_at) VALUES (?, ?, ?)', ['t', 1, 1]);
    await db.runAsync('INSERT INTO messages (conversation_id, role, content, created_at) VALUES (?, ?, ?, ?)', [
      c.lastInsertRowId,
      'user',
      'hi',
      1,
    ]);
    await db.runAsync('DELETE FROM conversations WHERE id = ?', [c.lastInsertRowId]);
    expect((await db.getFirstAsync<{ n: number }>('SELECT COUNT(*) AS n FROM messages'))?.n).toBe(0);
  });
});

describe('web driver', () => {
  it('reports insert ids and change counts', async () => {
    const db = await migrated();
    const a = await db.runAsync('INSERT INTO setting_entries (key, value) VALUES (?, ?)', ['k', 'v']);
    expect(a.changes).toBe(1);
    const p = await db.runAsync('INSERT INTO personas (name, system_prompt, created_at) VALUES (?, ?, ?)', ['n', 's', 1]);
    expect(p.lastInsertRowId).toBeGreaterThan(0);
  });

  it('rolls back a failed transaction', async () => {
    const db = await migrated();
    await expect(
      db.withTransactionAsync(async () => {
        await db.runAsync('INSERT INTO setting_entries (key, value) VALUES (?, ?)', ['x', '1']);
        throw new Error('boom');
      }),
    ).rejects.toThrow('boom');
    expect(await db.getFirstAsync('SELECT * FROM setting_entries WHERE key = ?', ['x'])).toBeNull();
  });

  it('serialises overlapping transactions instead of nesting them', async () => {
    const db = await migrated();
    const tx = (k: string) =>
      db.withTransactionAsync(async () => {
        await db.runAsync('INSERT INTO setting_entries (key, value) VALUES (?, ?)', [k, k]);
        await new Promise((r) => setTimeout(r, 5));
      });
    await Promise.all([tx('a'), tx('b'), tx('c')]);
    expect((await db.getFirstAsync<{ n: number }>('SELECT COUNT(*) AS n FROM setting_entries'))?.n).toBe(3);
  });
});
