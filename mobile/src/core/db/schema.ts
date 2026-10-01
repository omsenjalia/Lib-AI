/**
 * SQLite schema, versioned with PRAGMA user_version.
 *
 * Column names follow the Flutter build's drift schema (snake_case) so the
 * legacy importer is a straight copy. Differences: timestamps are milliseconds,
 * the retired subject-tag table is gone, and conversations can be pinned.
 *
 * Every migration is append-only. Never edit a shipped step; add the next one.
 */
export const migrations: string[] = [
  // v1
  `
  CREATE TABLE IF NOT EXISTS personas (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    emoji TEXT NOT NULL DEFAULT '📚',
    system_prompt TEXT NOT NULL,
    is_built_in INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
  );
  CREATE TABLE IF NOT EXISTS conversations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    model_id TEXT,
    persona_id INTEGER REFERENCES personas(id) ON DELETE SET NULL,
    context_length_override INTEGER,
    pinned INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  );
  CREATE INDEX IF NOT EXISTS conversations_updated ON conversations(updated_at DESC);
  CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    conversation_id INTEGER NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    role TEXT NOT NULL,
    content TEXT NOT NULL,
    image_path TEXT,
    is_error INTEGER NOT NULL DEFAULT 0,
    render_math INTEGER NOT NULL DEFAULT 0,
    token_count INTEGER,
    is_estimated_tokens INTEGER NOT NULL DEFAULT 1,
    created_at INTEGER NOT NULL
  );
  CREATE INDEX IF NOT EXISTS messages_conversation ON messages(conversation_id, id);
  CREATE TABLE IF NOT EXISTS model_installations (
    model_id TEXT PRIMARY KEY NOT NULL,
    quant TEXT NOT NULL,
    file_name TEXT NOT NULL,
    local_path TEXT NOT NULL,
    mmproj_path TEXT,
    size_bytes INTEGER NOT NULL,
    sha256 TEXT,
    repo_sha TEXT,
    total_bytes INTEGER NOT NULL,
    downloaded_at INTEGER NOT NULL
  );
  CREATE TABLE IF NOT EXISTS model_update_checks (
    model_id TEXT PRIMARY KEY NOT NULL,
    last_checked_at INTEGER NOT NULL,
    remote_sha TEXT,
    update_available INTEGER NOT NULL DEFAULT 0
  );
  CREATE TABLE IF NOT EXISTS setting_entries (
    key TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS documents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    source_path TEXT,
    page_count INTEGER,
    chunk_count INTEGER NOT NULL DEFAULT 0,
    embedding_model_id TEXT,
    imported_at INTEGER NOT NULL
  );
  CREATE TABLE IF NOT EXISTS document_chunks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    document_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    chunk_index INTEGER NOT NULL,
    content TEXT NOT NULL,
    token_count INTEGER,
    embedding BLOB,
    created_at INTEGER NOT NULL
  );
  `,
  // v2: per-response stats shown under each answer (prompt tokens in, speed, time).
  `
  ALTER TABLE messages ADD COLUMN prompt_tokens INTEGER;
  ALTER TABLE messages ADD COLUMN tokens_per_second REAL;
  ALTER TABLE messages ADD COLUMN generation_ms INTEGER;
  `,
];

export const schemaVersion = migrations.length;
