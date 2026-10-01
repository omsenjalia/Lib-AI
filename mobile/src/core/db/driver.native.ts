import * as SQLite from 'expo-sqlite';

import { AppConstants } from '../constants';
import type { SqlDriver } from './driverTypes';

/** The app's SQLite file, through expo-sqlite. */
export async function openDriver(): Promise<SqlDriver> {
  const db = await SQLite.openDatabaseAsync(AppConstants.databaseName);
  await db.execAsync('PRAGMA journal_mode = WAL;');
  return {
    execAsync: (source) => db.execAsync(source),
    runAsync: (source, params = []) => db.runAsync(source, params),
    getFirstAsync: (source, params = []) => db.getFirstAsync(source, params),
    getAllAsync: (source, params = []) => db.getAllAsync(source, params),
    withTransactionAsync: (task) => db.withTransactionAsync(task),
  };
}
