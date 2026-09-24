import 'package:drift/drift.dart';

/// Table definitions for Library AI.
///
/// Split from `database.dart` so the schema can be read on its own. Everything
/// is local: no table here has a server counterpart, and nothing in this file
/// involves a network call.
///
/// Naming note: drift derives data class names by singularising the table name,
/// so `Messages` yields a `Message` data class. That collides in name with
/// fllama's `Message` type, which is why the inference layer imports fllama
/// behind a prefix.

/// Retired subject-tag table kept only for Drift schema compatibility.
///
/// Schema v2 clears all rows and assignments; application code must not use it.
class SubjectTags extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 40)();

  /// ARGB colour, stored as an int so no type converter is needed.
  IntColumn get colorValue => integer()();

  /// Legacy flag retained with the retired table for schema compatibility.
  BoolColumn get isBuiltIn =>
      boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}

/// Saved system prompts the user can apply to a conversation.
class Personas extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 60)();

  TextColumn get emoji => text().withDefault(const Constant('\u{1F4DA}'))();

  TextColumn get systemPrompt => text()();

  BoolColumn get isBuiltIn =>
      boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}

/// A chat thread.
class Conversations extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Auto-generated from the first user message; renameable afterwards.
  TextColumn get title => text().withLength(min: 1, max: 200)();

  /// Retired legacy FK. Schema v2 clears it; conversations are never tagged.
  IntColumn get subjectTagId =>
      integer().nullable().references(SubjectTags, #id)();

  /// Catalogue id of the model this conversation was last used with, e.g.
  /// `qwythos-9b-v2`. Not a row id, so a conversation survives a model being
  /// deleted.
  TextColumn get modelId => text().nullable()();

  IntColumn get personaId => integer().nullable().references(Personas, #id)();

  /// Overrides the global context length for this thread.
  IntColumn get contextLengthOverride => integer().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// Drives the newest-first ordering of the sidebar.
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
}

/// A single turn in a conversation.
class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get conversationId => integer().references(Conversations, #id)();

  /// `user`, `assistant` or `system`. Stored as text rather than an enum so a
  /// future role needs no migration.
  TextColumn get role => text().withLength(min: 1, max: 16)();

  TextColumn get content => text()();

  /// Absolute path to an image attached to this turn (OCR mode or an attached
  /// photo). The image itself never leaves the device.
  TextColumn get imagePath => text().nullable()();

  /// Marks a stored failure (model unloaded, OOM) so it renders as an error
  /// rather than as something the model said.
  BoolColumn get isError => boolean().withDefault(const Constant(false))();

  /// Per-message "Render math" toggle, for models that emit raw LaTeX.
  BoolColumn get renderMath => boolean().withDefault(const Constant(false))();

  /// Tokens for this message. See [isEstimatedTokens] for how much to trust it.
  IntColumn get tokenCount => integer().nullable()();

  /// True when [tokenCount] came from the character-ratio estimator rather than
  /// the model's own tokeniser, so the UI can be honest about precision.
  BoolColumn get isEstimatedTokens =>
      boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}

/// A model that is present on the device.
///
/// Keyed by catalogue id: one installation per model, because a model has one
/// active quantisation at a time. Switching quant means downloading again.
class ModelInstallations extends Table {
  /// Catalogue id, e.g. `mimo-v2.6-9b`.
  TextColumn get modelId => text()();

  /// The quantisation label that was downloaded, e.g. `Q4_K_M`.
  TextColumn get quant => text()();

  TextColumn get fileName => text()();

  TextColumn get localPath => text()();

  /// Vision projector, when the model is multimodal and one was downloaded.
  TextColumn get mmprojPath => text().nullable()();

  IntColumn get sizeBytes => integer()();

  /// SHA-256 actually computed from the file on disk after download.
  TextColumn get sha256 => text().nullable()();

  /// Version baseline captured at download time. This is what the auto-update
  /// checker compares the remote value against.
  TextColumn get repoSha => text().nullable()();

  DateTimeColumn get repoLastModified => dateTime().nullable()();

  /// Total bytes including the projector, for the storage breakdown.
  IntColumn get totalBytes => integer()();

  DateTimeColumn get downloadedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {modelId};
}

/// Throttle + result record for the HuggingFace update check.
class ModelUpdateChecks extends Table {
  TextColumn get modelId => text()();

  DateTimeColumn get lastCheckedAt => dateTime()();

  TextColumn get remoteSha => text().nullable()();

  DateTimeColumn get remoteLastModified => dateTime().nullable()();

  /// Set when the remote repository has moved on from the stored baseline.
  /// Display only - never triggers a download on its own.
  BoolColumn get updateAvailable =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {modelId};
}

/// Simple key/value store for app settings.
///
/// Named `SettingEntries` so the generated data class `SettingEntry` does not
/// collide with the `AppSettings` value object used by the settings layer.
class SettingEntries extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

// ---------------------------------------------------------------------------
// RAG placeholders.
//
// Phase 2 scope. These tables are created now, and the "My Notes" screen exists
// with a Coming Soon state, so that adding retrieval later is a pure addition
// rather than a schema migration plus a UI rebuild. Nothing writes to them in
// v1.
// ---------------------------------------------------------------------------

/// An imported PDF or note collection.
class Documents extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get title => text()();

  TextColumn get sourcePath => text().nullable()();

  IntColumn get pageCount => integer().nullable()();

  IntColumn get chunkCount => integer().withDefault(const Constant(0))();

  /// Which local embedding model produced the vectors in [DocumentChunks].
  /// Recorded now so a future re-embed can detect a model change.
  TextColumn get embeddingModelId => text().nullable()();

  DateTimeColumn get importedAt =>
      dateTime().withDefault(currentDateAndTime)();
}

/// One retrievable fragment of a document, with its embedding.
class DocumentChunks extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get documentId => integer().references(Documents, #id)();

  /// Ordinal position within the source document, so retrieved chunks can be
  /// reassembled in reading order.
  IntColumn get chunkIndex => integer()();

  TextColumn get content => text()();

  IntColumn get tokenCount => integer().nullable()();

  /// Raw float32 vector. Stored as a blob to keep the schema stable regardless
  /// of embedding dimension.
  BlobColumn get embedding => blob().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}
