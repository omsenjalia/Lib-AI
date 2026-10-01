import initSqlJs from 'sql.js/dist/sql-asm.js';

import type { SqlDriver, SqlValue } from './driverTypes';

/**
 * Browser preview database: sql.js (SQLite compiled to asm.js) in memory.
 *
 * Not expo-sqlite, deliberately. Its web build always sets up an OPFS-backed
 * storage layer first, even for `:memory:`, and OPFS lets one tab hold it at a
 * time: a second tab (or a reload that has not released it yet) fails setup
 * and every later open throws "Invalid VFS state". The preview keeps nothing
 * between reloads, so it needs no browser storage at all. The asm.js build also
 * means there is no .wasm file for the dev server to serve.
 */
export async function openDriver(): Promise<SqlDriver> {
  const SQL = await initSqlJs();
  const db = new SQL.Database();
  // One transaction at a time: sql.js has a single connection, and a BEGIN
  // inside another BEGIN is an error rather than a wait.
  let txQueue: Promise<unknown> = Promise.resolve();

  const all = <T>(source: string, params: SqlValue[] = []): T[] => {
    const stmt = db.prepare(source);
    try {
      stmt.bind(params);
      const rows: T[] = [];
      while (stmt.step()) rows.push(stmt.getAsObject() as T);
      return rows;
    } finally {
      stmt.free();
    }
  };

  return {
    async execAsync(source) {
      db.exec(source);
    },
    async runAsync(source, params = []) {
      db.run(source, params);
      const changes = db.getRowsModified();
      const id = all<{ id: number }>('SELECT last_insert_rowid() AS id')[0]?.id ?? 0;
      return { lastInsertRowId: Number(id), changes };
    },
    async getFirstAsync<T>(source: string, params?: SqlValue[]) {
      return all<T>(source, params)[0] ?? null;
    },
    async getAllAsync<T>(source: string, params?: SqlValue[]) {
      return all<T>(source, params);
    },
    withTransactionAsync(task) {
      const run = txQueue.then(async () => {
        db.exec('BEGIN');
        try {
          await task();
          db.exec('COMMIT');
        } catch (e) {
          db.exec('ROLLBACK');
          throw e;
        }
      });
      txQueue = run.catch(() => undefined);
      return run;
    },
  };
}
