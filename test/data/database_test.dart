import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_ai/core/data/database.dart';
import 'package:library_ai/core/models/app_settings.dart';

/// Exercises the schema and the DAO against a real (in-memory) SQLite database.
///
/// Using the actual engine matters here: the schema's foreign keys, defaults and
/// `insertOnConflictUpdate` behaviour are what the app depends on, and none of
/// that is exercised by a fake.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('seeding', () {
    test('retired subject tags are not seeded on first open', () async {
      final row = await db
          .customSelect('SELECT COUNT(*) AS count FROM subject_tags')
          .getSingle();
      expect(row.read<int>('count'), 0);
    });

    test('the six study personas are created on first open', () async {
      final personas = await db.allPersonas();
      expect(personas, hasLength(6));
      expect(
        personas.map((p) => p.name),
        containsAll([
          'General Tutor',
          'Code Reviewer',
          'Maths & Physics Tutor',
          'Exam Prep',
          'Paper Explainer',
          'Essay Editor',
        ]),
      );
      expect(personas.every((p) => p.emoji.isNotEmpty), isTrue);
    });

    test('the persona prompts ask for renderable output', () async {
      final personas = await db.allPersonas();
      final tutor = personas.firstWhere((p) => p.name == 'General Tutor');
      // The chat panel renders LaTeX and markdown; a persona that does not ask
      // for either produces worse output than one that does.
      expect(tutor.systemPrompt.toLowerCase(), contains('latex'));
    });
  });

  group('conversations and messages', () {
    test('new conversations have no subject assignment', () async {
      final id = await db.createConversation(
        title: 'Deadlocks',
        modelId: 'qwythos-9b-v2',
      );

      final conversation = await db.conversationById(id);
      expect(conversation, isNotNull);
      expect(conversation!.title, 'Deadlocks');
      expect(conversation.subjectTagId, isNull);
      expect(conversation.modelId, 'qwythos-9b-v2');
    });

    test('messages come back in insertion order', () async {
      final id = await db.createConversation(title: 'Order');
      await db.addMessage(conversationId: id, role: 'user', content: 'one');
      await db.addMessage(conversationId: id, role: 'assistant', content: 'two');
      await db.addMessage(conversationId: id, role: 'user', content: 'three');

      final messages = await db.messagesFor(id);
      expect(messages.map((m) => m.content).toList(), ['one', 'two', 'three']);
    });

    test('token counts record whether they were estimated', () async {
      final id = await db.createConversation(title: 'Tokens');
      await db.addMessage(
        conversationId: id,
        role: 'assistant',
        content: 'x',
        tokenCount: 12,
        isEstimatedTokens: false,
      );

      final message = (await db.messagesFor(id)).single;
      expect(message.tokenCount, 12);
      expect(message.isEstimatedTokens, isFalse);
    });

    test('an error turn is stored as an error, not as an answer', () async {
      final id = await db.createConversation(title: 'Failure');
      await db.addMessage(
        conversationId: id,
        role: 'assistant',
        content: 'Out of memory.',
        isError: true,
      );

      final message = (await db.messagesFor(id)).single;
      expect(message.isError, isTrue);
    });

    test('the render-math toggle persists per message', () async {
      final id = await db.createConversation(title: 'Maths');
      final messageId = await db.addMessage(
        conversationId: id,
        role: 'assistant',
        content: r'\frac{a}{b}',
      );

      expect((await db.messageById(messageId))!.renderMath, isFalse);
      await db.updateMessage(id: messageId, renderMath: true);
      expect((await db.messageById(messageId))!.renderMath, isTrue);
    });

    test('deleting a conversation removes its messages', () async {
      final id = await db.createConversation(title: 'Doomed');
      await db.addMessage(conversationId: id, role: 'user', content: 'hello');
      await db.addMessage(conversationId: id, role: 'assistant', content: 'hi');

      await db.deleteConversation(id);

      expect(await db.conversationById(id), isNull);
      expect(await db.messagesFor(id), isEmpty);
      expect(await db.messageCount(id), 0);
    });

    test('deleteMessagesFrom removes a message and everything after it', () async {
      final id = await db.createConversation(title: 'Regenerate');
      await db.addMessage(conversationId: id, role: 'user', content: 'q1');
      final answer = await db.addMessage(
        conversationId: id,
        role: 'assistant',
        content: 'a1',
      );
      await db.addMessage(conversationId: id, role: 'user', content: 'q2');

      await db.deleteMessagesFrom(id, answer);

      final remaining = await db.messagesFor(id);
      expect(remaining, hasLength(1));
      expect(remaining.single.content, 'q1');
    });

    test('conversations are ordered by most recently updated', () async {
      final first = await db.createConversation(title: 'First');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final second = await db.createConversation(title: 'Second');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await db.touchConversation(first);

      final rows = await db.watchConversations().first;
      expect(rows.first.id, first);
      expect(rows.last.id, second);
    });

    test('clearing a persona works', () async {
      final personaId = (await db.allPersonas()).first.id;
      final id = await db.createConversation(
        title: 'Clearing',
        personaId: personaId,
      );

      await db.updateConversationMeta(id: id, clearPersona: true);
      final conversation = (await db.conversationById(id))!;
      expect(conversation.subjectTagId, isNull);
      expect(conversation.personaId, isNull);
    });
  });

  group('personas', () {
    test('a custom persona round-trips through insert and update', () async {
      final id = await db.insertPersona(
        name: 'Lab Coach',
        systemPrompt: 'Explain every step of the procedure.',
        emoji: '\u{1F9EA}',
      );

      var persona = (await db.personaById(id))!;
      expect(persona.name, 'Lab Coach');
      expect(persona.isBuiltIn, isFalse);

      await db.updatePersona(
        id: id,
        name: 'Lab Coach (strict)',
        systemPrompt: 'Explain every step, and name the safety hazards.',
        emoji: '\u{1F9EA}',
      );
      persona = (await db.personaById(id))!;
      expect(persona.name, 'Lab Coach (strict)');
      expect(persona.systemPrompt, contains('safety'));
    });

    test('deleting a persona leaves conversations intact', () async {
      final personaId = (await db.allPersonas()).last.id;
      final conversationId = await db.createConversation(
        title: 'Keeps its messages',
        personaId: personaId,
      );
      await db.addMessage(
        conversationId: conversationId,
        role: 'user',
        content: 'still here',
      );

      await db.deletePersona(personaId);

      expect(await db.messageCount(conversationId), 1);
    });
  });

  group('model installations', () {
    test('an installation is keyed by model id and can be replaced', () async {
      await db.upsertInstallation(
        ModelInstallationsCompanion.insert(
          modelId: 'qwythos-9b-v2',
          quant: 'Q4_K_M',
          fileName: 'Qwythos-9B-v2-Q4_K_M.gguf',
          localPath: '/models/qwythos-9b-v2/Qwythos-9B-v2-Q4_K_M.gguf',
          sizeBytes: 5736063744,
          totalBytes: 5736063744,
        ),
      );

      var installation = (await db.installation('qwythos-9b-v2'))!;
      expect(installation.quant, 'Q4_K_M');
      expect(installation.repoSha, isNull);

      // Re-downloading the same model with a different quant replaces the row
      // rather than adding a second one: a model has one active quantisation.
      await db.upsertInstallation(
        ModelInstallationsCompanion.insert(
          modelId: 'qwythos-9b-v2',
          quant: 'Q3_K_M',
          fileName: 'Qwythos-9B-v2-Q3_K_M.gguf',
          localPath: '/models/qwythos-9b-v2/Qwythos-9B-v2-Q3_K_M.gguf',
          sizeBytes: 4000000000,
          totalBytes: 4000000000,
        ),
      );

      installation = (await db.installation('qwythos-9b-v2'))!;
      expect(installation.quant, 'Q3_K_M');
      expect((await db.allInstallations()), hasLength(1));
    });

    test('total model bytes adds up across installations', () async {
      for (final (id, bytes) in [
        ('a', 1000),
        ('b', 2000),
      ]) {
        await db.upsertInstallation(
          ModelInstallationsCompanion.insert(
            modelId: id,
            quant: 'Q4_K_M',
            fileName: '$id.gguf',
            localPath: '/models/$id/$id.gguf',
            sizeBytes: bytes,
            totalBytes: bytes,
          ),
        );
      }

      expect(await db.totalModelBytes(), 3000);
    });

    test('removing an installation clears the row', () async {
      await db.upsertInstallation(
        ModelInstallationsCompanion.insert(
          modelId: 'x',
          quant: 'Q4_K_M',
          fileName: 'x.gguf',
          localPath: '/models/x/x.gguf',
          sizeBytes: 1,
          totalBytes: 1,
        ),
      );

      await db.removeInstallation('x');
      expect(await db.installation('x'), isNull);
      expect(await db.totalModelBytes(), 0);
    });
  });

  group('update checks', () {
    test('a check records the remote state and the available flag', () async {
      await db.upsertUpdateCheck(
        ModelUpdateChecksCompanion.insert(
          modelId: 'qwythos-9b-v2',
          lastCheckedAt: DateTime(2026, 9, 24),
          updateAvailable: const Value(true),
          remoteSha: const Value('abc123'),
        ),
      );

      final check = (await db.updateCheck('qwythos-9b-v2'))!;
      expect(check.updateAvailable, isTrue);
      expect(check.remoteSha, 'abc123');

      // Checking again updates the same row rather than accumulating history.
      await db.upsertUpdateCheck(
        ModelUpdateChecksCompanion.insert(
          modelId: 'qwythos-9b-v2',
          lastCheckedAt: DateTime(2026, 9, 25),
          updateAvailable: const Value(false),
        ),
      );

      final rows = await db.watchUpdateChecks().first;
      expect(rows, hasLength(1));
      expect(rows.single.updateAvailable, isFalse);
    });
  });

  group('settings', () {
    test('keys round-trip through the store', () async {
      await db.putSetting(SettingKeys.temperature, '0.65');
      expect(await db.setting(SettingKeys.temperature), '0.65');

      await db.putSetting(SettingKeys.temperature, '0.7');
      expect(await db.setting(SettingKeys.temperature), '0.7');
    });

    test('a cleared key is removed, not blanked', () async {
      await db.putSetting(SettingKeys.defaultModelId, 'qwythos-9b-v2');
      await db.deleteSetting(SettingKeys.defaultModelId);
      expect(await db.setting(SettingKeys.defaultModelId), isNull);
    });

    test('an empty store yields the documented defaults', () async {
      final settings = AppSettings.fromMap(await db.allSettings());

      expect(settings.themeMode.name, 'dark');
      expect(settings.contextLength, 4096);
      expect(settings.temperature, 0.6);
      expect(settings.topP, 0.95);
      expect(settings.topK, 20);
      expect(settings.autoUpdateCheckEnabled, isTrue);
      expect(settings.defaultModelId, isNull);
    });

    test('corrupt values fall back rather than breaking startup', () async {
      await db.putSetting(SettingKeys.contextLength, 'not-a-number');
      await db.putSetting(SettingKeys.themeMode, 'chartreuse');
      await db.putSetting(SettingKeys.temperature, '');

      final settings = AppSettings.fromMap(await db.allSettings());

      expect(settings.contextLength, 4096);
      expect(settings.themeMode.name, 'dark');
      expect(settings.temperature, 0.6);
    });

    test('a full settings object round-trips', () async {
      const original = AppSettings(
        contextLength: 8192,
        temperature: 0.4,
        topP: 0.9,
        topK: 40,
        gpuLayers: 10,
        autoUpdateCheckEnabled: false,
        defaultModelId: 'mimo-v2.6-9b',
        modelStorageTreeUri: 'content://com.android.externalstorage.documents/tree/primary%3ADocuments',
        modelStorageFolderName: 'Documents',
      );

      for (final entry in original.toMap().entries) {
        await db.putSetting(entry.key, entry.value);
      }

      final restored = AppSettings.fromMap(await db.allSettings());
      expect(restored, original);

      final cleared = restored.copyWith(clearModelStorageLocation: true);
      expect(cleared.modelStorageTreeUri, isNull);
      expect(cleared.modelStorageFolderName, isNull);
      expect(
        cleared.toMap().containsKey(SettingKeys.modelStorageTreeUri),
        isFalse,
      );
    });
  });

  group('RAG placeholders', () {
    test('there are no documents in v1', () async {
      expect(await db.documentCount(), 0);
      expect(await db.allDocuments(), isEmpty);
    });

    test('the documents table accepts a row for the future importer', () async {
      final id = await db.insertDocument(
        title: 'Operating Systems Notes',
        sourcePath: '/notes/os.pdf',
      );

      expect(id, greaterThan(0));
      expect(await db.documentCount(), 1);
      expect((await db.allDocuments()).single.title, 'Operating Systems Notes');
    });
  });
}
