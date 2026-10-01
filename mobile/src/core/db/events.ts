/**
 * Write notifications. Every repository write announces the tables it touched,
 * and stores re-query what they show. Cheaper and more predictable than a
 * native change listener, and identical on web.
 */
export type Table = 'personas' | 'conversations' | 'messages' | 'installations' | 'updates' | 'settings';

type Listener = (tables: ReadonlySet<Table>) => void;
const listeners = new Set<Listener>();

let pending = new Set<Table>();
let scheduled = false;

export function emitChange(...tables: Table[]): void {
  for (const t of tables) pending.add(t);
  if (scheduled) return;
  scheduled = true;
  // Coalesce a burst of writes (a transaction, a duplicate) into one refresh.
  queueMicrotask(() => {
    const batch = pending;
    pending = new Set();
    scheduled = false;
    for (const l of listeners) l(batch);
  });
}

export function onChange(tables: Table[], listener: () => void): () => void {
  const wrapped: Listener = (changed) => {
    if (tables.some((t) => changed.has(t))) listener();
  };
  listeners.add(wrapped);
  return () => listeners.delete(wrapped);
}
