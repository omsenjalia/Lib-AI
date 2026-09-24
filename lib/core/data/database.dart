import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants/app_constants.dart';
import '../constants/builtin_data.dart';
import 'tables.dart';

export 'tables.dart';

part 'database.g.dart';

/// The application's entire persistent state.
///
/// A single SQLite file in the app's documents directory. There is no server
/// side to this schema and nothing here is ever uploaded - the offline-first
/// guarantee depends on that being true, so any future table added here should
/// be checked against the same rule.
@DriftDatabase(
  tables: [
    SubjectTags,
    Personas,
    Conversations,
    Messages,
    ModelInstallations,
    ModelUpdateChecks,
    SettingEntries,
    Documents,
    DocumentChunks,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// In-memory database for tests. Never touches the file system.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedDefaults();
        },
        beforeOpen: (details) async {
          // Referential integrity is off by default in SQLite, and drift does
          // not turn it on for us. Without this the foreign keys declared in
          // tables.dart are documentation rather than constraints.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Seeds the built-in tags and personas, once, on first creation.
  Future<void> _seedDefaults() async {
    await batch((b) {
      b.insertAll(subjectTags, [
        for (final tag in defaultSubjectTags)
          SubjectTagsCompanion.insert(
            name: tag.name,
            colorValue: tag.colorValue,
            isBuiltIn: const Value(true),
          ),
      ]);
      b.insertAll(personas, [
        for (final persona in defaultPersonas)
          PersonasCompanion.insert(
            name: persona.name,
            emoji: Value(persona.emoji),
            systemPrompt: persona.systemPrompt,
            isBuiltIn: const Value(true),
          ),
      ]);
    });
  }

  // ------------------------------------------------------------- subject tags

  Stream<List<SubjectTag>> watchSubjectTags() => (select(subjectTags)
        ..orderBy([
          (t) => OrderingTerm(expression: t.isBuiltIn, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.name),
        ]))
      .watch();

  Future<List<SubjectTag>> allSubjectTags() => select(subjectTags).get();

  Future<int> insertSubjectTag(String name, int colorValue) =>
      into(subjectTags).insert(
        SubjectTagsCompanion.insert(name: name, colorValue: colorValue),
      );

  Future<SubjectTag?> tagById(int id) =>
      (select(subjectTags)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> deleteSubjectTag(int id) => (delete(subjectTags)
        ..where((t) => t.id.equals(id)))
      .go();

  // ---------------------------------------------------------------- personas

  Stream<List<Persona>> watchPersonas() => (select(personas)
        ..orderBy([
          (t) => OrderingTerm(expression: t.isBuiltIn, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.name),
        ]))
      .watch();

  Future<List<Persona>> allPersonas() => select(personas).get();

  Future<Persona?> personaById(int id) =>
      (select(personas)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> insertPersona({
    required String name,
    required String emoji,
    required String systemPrompt,
  }) =>
      into(personas).insert(
        PersonasCompanion.insert(
          name: name,
          emoji: Value(emoji),
          systemPrompt: systemPrompt,
        ),
      );

  Future<void> updatePersona({
    required int id,
    required String name,
    required String emoji,
    required String systemPrompt,
  }) =>
      (update(personas)..where((t) => t.id.equals(id))).write(
        PersonasCompanion(
          name: Value(name),
          emoji: Value(emoji),
          systemPrompt: Value(systemPrompt),
        ),
      );

  Future<void> deletePersona(int id) =>
      (delete(personas)..where((t) => t.id.equals(id))).go();

  // ----------------------------------------------------------- conversations

  Stream<List<Conversation>> watchConversations() => (select(conversations)
        ..orderBy([
          (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
        ]))
      .watch();

  Future<Conversation?> conversationById(int id) =>
      (select(conversations)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Stream<Conversation?> watchConversation(int id) =>
      (select(conversations)..where((t) => t.id.equals(id)))
          .watchSingleOrNull();

  Future<int> createConversation({
    required String title,
    int? subjectTagId,
    String? modelId,
    int? personaId,
  }) =>
      into(conversations).insert(
        ConversationsCompanion.insert(
          title: title,
          subjectTagId: Value(subjectTagId),
          modelId: Value(modelId),
          personaId: Value(personaId),
        ),
      );

  Future<void> updateConversationMeta({
    required int id,
    String? title,
    int? subjectTagId,
    bool clearSubjectTag = false,
    String? modelId,
    int? personaId,
    bool clearPersona = false,
    int? contextLengthOverride,
    bool clearContextOverride = false,
  }) =>
      (update(conversations)..where((t) => t.id.equals(id))).write(
        ConversationsCompanion(
          title: title == null ? const Value.absent() : Value(title),
          subjectTagId: clearSubjectTag
              ? const Value(null)
              : (subjectTagId == null
                  ? const Value.absent()
                  : Value(subjectTagId)),
          modelId:
              modelId == null ? const Value.absent() : Value(modelId),
          personaId: clearPersona
              ? const Value(null)
              : (personaId == null ? const Value.absent() : Value(personaId)),
          contextLengthOverride: clearContextOverride
              ? const Value(null)
              : (contextLengthOverride == null
                  ? const Value.absent()
                  : Value(contextLengthOverride)),
        ),
      );

  /// Bumps `updatedAt` so a thread rises to the top of the sidebar.
  Future<void> touchConversation(int id) =>
      (update(conversations)..where((t) => t.id.equals(id))).write(
        ConversationsCompanion(updatedAt: Value(DateTime.now())),
      );

  /// Removes a conversation and every message in it.
  ///
  /// Messages are deleted explicitly rather than relying on `ON DELETE CASCADE`,
  /// so the behaviour does not depend on the `PRAGMA foreign_keys` setting
  /// having taken effect.
  Future<void> deleteConversation(int id) async {
    await (delete(messages)..where((t) => t.conversationId.equals(id))).go();
    await (delete(conversations)..where((t) => t.id.equals(id))).go();
  }

  // ----------------------------------------------------------------- messages

  Stream<List<Message>> watchMessages(int conversationId) => (select(messages)
        ..where((t) => t.conversationId.equals(conversationId))
        ..orderBy([
          (t) => OrderingTerm(expression: t.createdAt),
          (t) => OrderingTerm(expression: t.id),
        ]))
      .watch();

  Future<List<Message>> messagesFor(int conversationId) => (select(messages)
        ..where((t) => t.conversationId.equals(conversationId))
        ..orderBy([
          (t) => OrderingTerm(expression: t.createdAt),
          (t) => OrderingTerm(expression: t.id),
        ]))
      .get();

  Future<Message?> messageById(int id) =>
      (select(messages)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> addMessage({
    required int conversationId,
    required String role,
    required String content,
    String? imagePath,
    bool isError = false,
    int? tokenCount,
    bool isEstimatedTokens = true,
  }) =>
      into(messages).insert(
        MessagesCompanion.insert(
          conversationId: conversationId,
          role: role,
          content: content,
          imagePath: Value(imagePath),
          isError: Value(isError),
          tokenCount: Value(tokenCount),
          isEstimatedTokens: Value(isEstimatedTokens),
        ),
      );

  Future<void> updateMessage({
    required int id,
    String? content,
    int? tokenCount,
    bool? isEstimatedTokens,
    bool? renderMath,
  }) =>
      (update(messages)..where((t) => t.id.equals(id))).write(
        MessagesCompanion(
          content: content == null ? const Value.absent() : Value(content),
          tokenCount:
              tokenCount == null ? const Value.absent() : Value(tokenCount),
          isEstimatedTokens: isEstimatedTokens == null
              ? const Value.absent()
              : Value(isEstimatedTokens),
          renderMath:
              renderMath == null ? const Value.absent() : Value(renderMath),
        ),
      );

  Future<void> deleteMessage(int id) =>
      (delete(messages)..where((t) => t.id.equals(id))).go();

  /// Deletes [messageId] and everything after it. Used by Regenerate, which
  /// discards the previous answer and everything downstream of it.
  Future<void> deleteMessagesFrom(int conversationId, int messageId) async {
    final target = await messageById(messageId);
    if (target == null) return;
    await (delete(messages)
          ..where((t) =>
              t.conversationId.equals(conversationId) &
              t.id.isBiggerOrEqualValue(messageId)))
        .go();
  }

  Future<int> messageCount(int conversationId) async {
    final count = messages.id.count();
    final query = selectOnly(messages)
      ..addColumns([count])
      ..where(messages.conversationId.equals(conversationId));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  // ----------------------------------------------------- model installations

  Stream<List<ModelInstallation>> watchInstallations() =>
      select(modelInstallations).watch();

  Future<List<ModelInstallation>> allInstallations() =>
      select(modelInstallations).get();

  Future<ModelInstallation?> installation(String modelId) =>
      (select(modelInstallations)..where((t) => t.modelId.equals(modelId)))
          .getSingleOrNull();

  Stream<ModelInstallation?> watchInstallation(String modelId) =>
      (select(modelInstallations)..where((t) => t.modelId.equals(modelId)))
          .watchSingleOrNull();

  Future<void> upsertInstallation(ModelInstallationsCompanion companion) =>
      into(modelInstallations).insertOnConflictUpdate(companion);

  Future<void> removeInstallation(String modelId) =>
      (delete(modelInstallations)..where((t) => t.modelId.equals(modelId)))
          .go();

  /// Total bytes on disk across every downloaded model, for Settings.
  Future<int> totalModelBytes() async {
    final total = modelInstallations.totalBytes.sum();
    final row = await (selectOnly(modelInstallations)..addColumns([total]))
        .getSingle();
    return row.read(total) ?? 0;
  }

  // -------------------------------------------------------- update bookkeeping

  Stream<List<ModelUpdateCheck>> watchUpdateChecks() =>
      select(modelUpdateChecks).watch();

  Future<ModelUpdateCheck?> updateCheck(String modelId) =>
      (select(modelUpdateChecks)..where((t) => t.modelId.equals(modelId)))
          .getSingleOrNull();

  Future<void> upsertUpdateCheck(ModelUpdateChecksCompanion companion) =>
      into(modelUpdateChecks).insertOnConflictUpdate(companion);

  // ----------------------------------------------------------------- settings

  Future<Map<String, String>> allSettings() async {
    final rows = await select(settingEntries).get();
    return {for (final row in rows) row.key: row.value};
  }

  Future<String?> setting(String key) async {
    final row = await (select(settingEntries)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> putSetting(String key, String value) =>
      into(settingEntries).insertOnConflictUpdate(
        SettingEntriesCompanion.insert(key: key, value: value),
      );

  /// Removes a stored preference.
  ///
  /// Needed because a cleared default model or tag has no "empty" representation
  /// to write - `putSetting` could only store a string, which would then parse
  /// back as a value rather than as absence.
  Future<void> deleteSetting(String key) =>
      (delete(settingEntries)..where((t) => t.key.equals(key))).go();

  // -------------------------------------------------------- RAG placeholders

  /// Only ever used to show the document count on the Coming Soon screen.
  Future<int> documentCount() async {
    final count = documents.id.count();
    final row =
        await (selectOnly(documents)..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  Future<List<Document>> allDocuments() => select(documents).get();

  Future<int> insertDocument({
    required String title,
    String? sourcePath,
  }) =>
      into(documents).insert(
        DocumentsCompanion.insert(
          title: title,
          sourcePath: Value(sourcePath),
        ),
      );
}

/// Opens the SQLite file in a background isolate.
///
/// `createInBackground` matters here: it keeps database I/O off the UI isolate,
/// which is one of the requirements for the chat panel never freezing while a
/// model is generating.
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, AppConstants.databaseName));
    return NativeDatabase.createInBackground(file);
  });
}
