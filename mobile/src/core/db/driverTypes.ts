/**
 * The slice of a SQLite connection the app uses. Native implements it with
 * expo-sqlite (`driver.native.ts`); the browser preview with sql.js
 * (`driver.web.ts`). Method names match expo-sqlite so the native side is a
 * pass-through.
 */
export type SqlValue = string | number | null;

export interface SqlDriver {
  execAsync(source: string): Promise<void>;
  runAsync(source: string, params?: SqlValue[]): Promise<{ lastInsertRowId: number; changes: number }>;
  getFirstAsync<T>(source: string, params?: SqlValue[]): Promise<T | null>;
  getAllAsync<T>(source: string, params?: SqlValue[]): Promise<T[]>;
  withTransactionAsync(task: () => Promise<void>): Promise<void>;
}
