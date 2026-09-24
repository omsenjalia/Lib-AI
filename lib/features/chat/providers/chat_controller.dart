import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/data/database.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/models/model_catalogue.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/services/inference_engine.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/token_estimator.dart';

/// Drives one conversation: assembling the prompt, streaming the answer,
/// persisting both sides of the turn, and keeping the context meter honest.
///
/// ## Why a single controller rather than one per conversation
///
/// The app shows exactly one chat panel at a time (the sidebar is a drawer over
/// it), and only one model can be resident in memory at a time. A per-thread
/// controller would imply multiple concurrent generations are possible, which
/// they are not. Keeping one controller makes that constraint visible in the
/// type rather than hiding it behind a family provider.
///
/// ## Persistence during streaming
///
/// An empty assistant row is written *before* generation starts, and its content
/// is flushed to SQLite at most once every [dbFlushInterval] while tokens
/// arrive. That costs one extra row per turn and buys two things: a
/// conversation killed mid-answer still contains the partial reply, and the
/// message ordering never depends on the UI finishing a stream.
class ChatController extends ChangeNotifier {
  ChatController(this._ref) {
    _engineStatusSub =
        _ref.read(inferenceEngineProvider).statusStream.listen((status) {
      _statusLabel = status.message;
      final error = status.error;
      if (status.hasFailed && error != null) {
        _lastError = error;
      } else if (status.isReady) {
        _lastError = null;
      }
      notifyListeners();
    });
  }

  final Ref _ref;

  /// How often streamed text is written to SQLite. Frequent enough that a kill
  /// loses at most a couple of seconds of output, rare enough that a long answer
  /// does not cause hundreds of writes.
  static const Duration dbFlushInterval = Duration(seconds: 2);

  StreamSubscription<EngineStatus>? _engineStatusSub;
  StreamSubscription<List<Message>>? _messagesSub;

  int? _conversationId;
  List<Message> _messages = const [];

  bool _isGenerating = false;
  String _streamingText = '';
  int? _streamingMessageId;

  AppException? _lastError;
  String? _statusLabel;

  DateTime _lastFlush = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;

  // ------------------------------------------------------------------ getters

  int? get conversationId => _conversationId;

  List<Message> get messages => _messages;

  bool get isGenerating => _isGenerating;

  /// Text received so far for the in-flight answer.
  String get streamingText => _streamingText;

  /// Id of the assistant row currently being written, so the UI can render
  /// [streamingText] in its place instead of the lagging database copy.
  int? get streamingMessageId => _streamingMessageId;

  /// The engine's own progress text, e.g. "Loading weights into memory".
  String? get statusLabel => _statusLabel;

  /// Most recent engine failure. Held in memory as well as being persisted into
  /// the transcript, so the model switcher can explain why a load failed.
  AppException? get lastError => _lastError;

  bool get hasMessages => _messages.isNotEmpty;

  /// True when the active model can accept images *and* its projector is on
  /// disk. OCR mode is refused whenever this is false.
  bool get visionAvailable {
    final modelId = _ref.read(activeModelIdProvider);
    if (modelId == null) return false;
    final model = _ref.read(catalogueProvider).valueOrNull?.byId(modelId);
    if (model == null || !model.visionSupported) return false;
    final installation =
        _ref.read(installationProvider(modelId)).valueOrNull;
    return installation?.mmprojPath != null;
  }

  /// Context window of the active model, honouring a per-conversation override.
  int get contextLength {
    final settings = _ref.read(currentSettingsProvider);
    final conversation = _conversation;
    final override = conversation?.contextLengthOverride;
    if (override != null) return override;

    final modelId = _ref.read(activeModelIdProvider);
    final model = modelId == null
        ? null
        : _ref.read(catalogueProvider).valueOrNull?.byId(modelId);
    if (model == null) return settings.contextLength;
    return settings.contextLength.clamp(
      AppConstants.minContextLength,
      model.maxContextLength,
    );
  }

  Conversation? get _conversation {
    final id = _conversationId;
    if (id == null) return null;
    final all = _ref.read(conversationsProvider).valueOrNull;
    if (all == null) return null;
    for (final conversation in all) {
      if (conversation.id == id) return conversation;
    }
    return null;
  }

  /// Tokens currently occupying the context window.
  ///
  /// Per-message counts come from the model's tokeniser once a turn has
  /// completed, and from [TokenEstimator] in between. The meter says which of
  /// the two it is showing.
  int get usedTokens {
    var total = 0;
    final personaId = _conversation?.personaId;
    if (personaId != null) {
      final persona = _personaById(personaId);
      if (persona != null) total += TokenEstimator.estimate(persona.systemPrompt);
    }
    for (final message in _messages) {
      total += message.tokenCount ?? TokenEstimator.estimate(message.content);
      total += 4; // chat-template role/turn overhead
    }
    if (_isGenerating) total += TokenEstimator.estimate(_streamingText);
    return total;
  }

  /// True when every count behind [usedTokens] came from the tokeniser.
  bool get tokensAreExact =>
      !_isGenerating &&
      _messages.every((m) => m.tokenCount != null && !m.isEstimatedTokens);

  Persona? _personaById(int id) {
    final personas = _ref.read(personasProvider).valueOrNull;
    if (personas == null) return null;
    for (final persona in personas) {
      if (persona.id == id) return persona;
    }
    return null;
  }

  // ------------------------------------------------------------- conversation

  /// Attaches to an existing conversation and streams its messages.
  void openConversation(int id) {
    if (_conversationId == id) return;
    _conversationId = id;
    _messages = const [];
    _streamingText = '';
    _streamingMessageId = null;
    _lastError = null;
    _subscribe(id);
    notifyListeners();
  }

  /// Detaches from the current thread without deleting it. The empty
  /// conversation row created on first send is left in place; pruning is the
  /// sidebar's job, not the controller's.
  void startNewChat() {
    _messagesSub?.cancel();
    _messagesSub = null;
    _conversationId = null;
    _messages = const [];
    _streamingText = '';
    _streamingMessageId = null;
    _lastError = null;
    notifyListeners();
  }

  void _subscribe(int conversationId) {
    _messagesSub?.cancel();
    _messagesSub = _ref
        .read(databaseProvider)
        .watchMessages(conversationId)
        .listen((rows) {
      if (_disposed) return;
      _messages = rows;
      notifyListeners();
    });
  }

  /// Copies an existing conversation into a new thread.
  Future<void> duplicateConversation(int id) async {
    final db = _ref.read(databaseProvider);
    final conversation = await db.conversationById(id);
    if (conversation == null) return;
    final history = await db.messagesFor(id);

    final newId = await db.createConversation(
      title: '${conversation.title} (copy)',
      subjectTagId: conversation.subjectTagId,
      modelId: conversation.modelId,
      personaId: conversation.personaId,
    );
    for (final message in history) {
      await db.addMessage(
        conversationId: newId,
        role: message.role,
        content: message.content,
        imagePath: message.imagePath,
        isError: message.isError,
        tokenCount: message.tokenCount,
        isEstimatedTokens: message.isEstimatedTokens,
      );
    }
    openConversation(newId);
  }

  // --------------------------------------------------------------- parameters

  Future<void> setSubjectTag(int? tagId) async {
    final id = _conversationId;
    if (id == null) return;
    await _ref.read(databaseProvider).updateConversationMeta(
          id: id,
          subjectTagId: tagId,
          clearSubjectTag: tagId == null,
        );
  }

  Future<void> setPersona(int? personaId) async {
    final id = _conversationId;
    if (id == null) return;
    await _ref.read(databaseProvider).updateConversationMeta(
          id: id,
          personaId: personaId,
          clearPersona: personaId == null,
        );
  }

  Future<void> renameConversation(int id, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    await _ref
        .read(databaseProvider)
        .updateConversationMeta(id: id, title: trimmed);
  }

  /// Per-message "Render math" toggle, for models that emit bare LaTeX.
  Future<void> toggleRenderMath(Message message) async {
    await _ref.read(databaseProvider).updateMessage(
          id: message.id,
          renderMath: !message.renderMath,
        );
  }

  // --------------------------------------------------------------- generation

  /// Sends a turn and streams the reply.
  ///
  /// [imagePath] is set by OCR mode; it is refused outright when the active
  /// model is not vision-capable, rather than being silently dropped.
  Future<void> send(String text, {String? imagePath}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && imagePath == null) return;
    if (_isGenerating) return;

    final settings = _ref.read(currentSettingsProvider);
    final db = _ref.read(databaseProvider);

    // 1. Resolve the destination thread, creating one on the first message.
    var conversationId = _conversationId;
    if (conversationId == null) {
      conversationId = await db.createConversation(
        title: autoTitleFromMessage(trimmed.isEmpty ? 'Image question' : trimmed),
        subjectTagId: settings.defaultSubjectTagId,
        modelId: _ref.read(activeModelIdProvider),
      );
      _conversationId = conversationId;
      _subscribe(conversationId);
      notifyListeners();
    }

    // 2. Make sure the model is resident before writing anything, so a load
    //    failure does not leave a question with no answer and no explanation.
    //
    //    The flag is raised first because loading can take tens of seconds on
    //    this device, and the UI needs to show the engine's own stage text
    //    ("Loading weights into memory") rather than appear to ignore the send.
    _isGenerating = true;
    _lastError = null;
    notifyListeners();

    try {
      await ensureModelLoaded();
    } on AppException catch (error) {
      _isGenerating = false;
      notifyListeners();
      await _persistError(conversationId, error);
      return;
    } catch (error) {
      // A non-AppException here means something unexpected (a malformed
      // catalogue, a missing plugin). Wrap it so the transcript records a
      // readable failure instead of an empty answer.
      const fallback = UnknownAppException(
        'The model could not be prepared.',
        detail: 'See the engine log for details.',
      );
      _isGenerating = false;
      notifyListeners();
      await _persistError(conversationId, fallback);
      return;
    }

    // 3. Persist the user's turn. The question is written before the answer is
    //    attempted, so the transcript is coherent even if generation then fails.
    //    (_isGenerating stays raised through this, so the loading state does not
    //    flicker between the load and the first token.)
    await db.addMessage(
      conversationId: conversationId,
      role: 'user',
      content: trimmed,
      imagePath: imagePath,
      tokenCount: TokenEstimator.estimate(trimmed),
      isEstimatedTokens: true,
    );
    await db.touchConversation(conversationId);

    await _generate(conversationId);
  }

  /// Discards the last answer and asks again.
  Future<void> regenerate() async {
    final conversationId = _conversationId;
    if (conversationId == null || _isGenerating) return;

    // Find the last assistant turn and drop it plus anything after it.
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].role == 'assistant') {
        await _ref
            .read(databaseProvider)
            .deleteMessagesFrom(conversationId, _messages[i].id);
        break;
      }
    }

    try {
      await ensureModelLoaded();
    } on AppException catch (error) {
      await _persistError(conversationId, error);
      return;
    }
    await _generate(conversationId);
  }

  /// Asks the engine to stop. The partial answer is kept - stopping is a normal
  /// outcome, not a failure.
  void stop() => _ref.read(inferenceEngineProvider).stop();

  /// Loads the active model if it is not already resident with the right
  /// context length.
  ///
  /// Public because the chat screen calls it when a conversation is opened, so
  /// that the load happens while the user is reading rather than after they hit
  /// send.
  Future<void> ensureModelLoaded() async {
    final engine = _ref.read(inferenceEngineProvider);
    final modelId = _ref.read(activeModelIdProvider);
    if (modelId == null) {
      throw const UnknownAppException(
        'No model is installed yet.',
        detail: 'Open Model Library and download one to start chatting.',
      );
    }

    final db = _ref.read(databaseProvider);
    final installation = await db.installation(modelId);
    if (installation == null) {
      throw ModelFileMissingException(
        'The installed model is missing from the library.',
        detail: 'No installation record for $modelId',
      );
    }

    final catalogue = await _ref.read(catalogueRepositoryProvider).load();
    final model = catalogue.byId(modelId);
    if (model == null) {
      throw ModelMissingFromCatalogueException(modelId);
    }

    final settings = _ref.read(currentSettingsProvider);
    final contextLength = this.contextLength;

    // A model swap also has to respect context length: fllama only reuses its
    // cached context when the parameters match, so changing the slider forces a
    // rebuild and must go through load() rather than being ignored.
    if (engine.status.holds(modelId) &&
        engine.status.contextLength == contextLength &&
        engine.status.isReady) {
      return;
    }

    final quant = model.quants.firstWhere(
      (q) => q.quant == installation.quant,
      orElse: () => QuantOption(
        quant: installation.quant,
        fileName: installation.fileName,
        sizeBytes: installation.sizeBytes,
        sha256: installation.sha256,
        qualityNote: 'Installed version.',
        fitsTargetDevice: true,
        downloadUrl: '',
      ),
    );

    await engine.load(
      model: model,
      quant: quant,
      paths: ModelInstallationPaths(
        modelPath: installation.localPath,
        mmprojPath: installation.mmprojPath,
      ),
      contextLength: contextLength,
      gpuLayers: settings.gpuLayers,
      includeMmproj: model.visionSupported && installation.mmprojPath != null,
    );
  }

  /// Frees the loaded model.
  ///
  /// fllama has no unload call, so this only stops generation and lets the
  /// platform's idle reaper release memory. The UI must not claim otherwise.
  Future<void> releaseModel() => _ref.read(inferenceEngineProvider).unload();

  Future<void> _generate(int conversationId) async {
    final engine = _ref.read(inferenceEngineProvider);
    final db = _ref.read(databaseProvider);
    final settings = _ref.read(currentSettingsProvider);

    final history = await db.messagesFor(conversationId);
    final persona = _conversation?.personaId == null
        ? null
        : _personaById(_conversation!.personaId!);

    final prompt = _buildPrompt(
      history: history,
      persona: persona,
      contextLength: contextLength,
    );

    // The assistant row is written before generation starts, so an interrupted
    // stream still leaves a coherent transcript.
    final assistantId = await db.addMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: '',
      isEstimatedTokens: true,
    );
    _streamingMessageId = assistantId;
    _streamingText = '';
    _isGenerating = true;
    _lastError = null;
    _lastFlush = DateTime.now();
    notifyListeners();

    final result = await engine.generate(
      messages: prompt,
      maxTokens: _maxTokensFor(history),
      temperature: settings.temperature,
      topP: settings.topP,
      repeatPenalty: _repeatPenalty(),
      contextLengthOverride: contextLength,
      gpuLayers: settings.gpuLayers,
      onToken: (delta) {
        _streamingText += delta;
        notifyListeners();
        _flushIfDue(assistantId);
      },
    );

    _isGenerating = false;
    final text = result.text.isEmpty ? _streamingText : result.text;

    if (result.isFailure) {
      _lastError = result.error;
      // Fold the failure into the placeholder row, so the transcript records
      // what went wrong rather than an empty answer.
      await db.updateMessage(
        id: assistantId,
        content: _errorText(result.error!),
      );
    } else {
      final exact = await engine.countTokens(text);
      await db.updateMessage(
        id: assistantId,
        content: text.isEmpty ? '_(empty response)_' : text,
        tokenCount: exact ?? TokenEstimator.estimate(text),
        isEstimatedTokens: exact == null,
      );
      if (exact != null) await _refreshExactCounts(conversationId);
    }

    await db.touchConversation(conversationId);
    _streamingMessageId = null;
    notifyListeners();
  }

  /// Writes streamed text to SQLite, rate-limited.
  void _flushIfDue(int messageId) {
    final now = DateTime.now();
    if (now.difference(_lastFlush) < dbFlushInterval) return;
    _lastFlush = now;
    // Fire and forget: a failed intermediate flush is harmless because the
    // final write always runs, and awaiting here would block the token
    // callback and stutter the stream.
    unawaited(_flushToDb(messageId));
  }

  Future<void> _flushToDb(int messageId) async {
    try {
      await _ref
          .read(databaseProvider)
          .updateMessage(id: messageId, content: _streamingText);
    } catch (_) {
      // Ignored on purpose - see _flushIfDue.
    }
  }

  /// Re-tokenises the conversation with the model's own vocabulary.
  ///
  /// Only the messages that are still carrying estimates are touched, so this
  /// is a bounded amount of work however long the thread is.
  Future<void> _refreshExactCounts(int conversationId) async {
    final engine = _ref.read(inferenceEngineProvider);
    final db = _ref.read(databaseProvider);
    final rows = await db.messagesFor(conversationId);

    for (final row in rows) {
      if (row.tokenCount != null && !row.isEstimatedTokens) continue;
      if (row.content.isEmpty) continue;
      final exact = await engine.countTokens(row.content);
      if (exact == null) return; // tokeniser unavailable; keep estimates
      await db.updateMessage(
        id: row.id,
        tokenCount: exact,
        isEstimatedTokens: false,
      );
    }
  }

  Future<void> _persistError(
    int conversationId,
    AppException error, {
    int? afterMessageId,
  }) async {
    final db = _ref.read(databaseProvider);
    if (afterMessageId != null) {
      // Fold the failure into the existing assistant row rather than adding a
      // second bubble for one failed turn.
      await db.updateMessage(
        id: afterMessageId,
        content: _errorText(error),
      );
      await db.updateMessage(
        id: afterMessageId,
        content: '${error.message}\n\n${error.recovery ?? ''}'.trim(),
      );
      return;
    }
    await db.addMessage(
      conversationId: conversationId,
      role: 'assistant',
      content: _errorText(error),
      isError: true,
      isEstimatedTokens: true,
    );
  }

  String _errorText(AppException error) {
    final recovery = error.recovery;
    if (recovery == null || recovery.isEmpty) return error.message;
    return '${error.message}\n\n$recovery';
  }

  // ------------------------------------------------------------ prompt build

  /// Builds the message list actually sent to the model.
  ///
  /// The newest turns are kept and older ones dropped until the estimated size
  /// fits inside [contextBudgetFraction] of the window. Truncating from the
  /// front rather than the back is deliberate: a question refers to the
  /// immediately preceding answer, so that is the pair worth protecting.
  List<PromptMessage> _buildPrompt({
    required List<Message> history,
    required Persona? persona,
    required int contextLength,
  }) {
    final budget = (contextLength * contextBudgetFraction).floor();
    final system = _systemPrompt(persona);

    final selected = <Message>[];
    var spent = TokenEstimator.estimate(system);

    for (var i = history.length - 1; i >= 0; i--) {
      final message = history[i];
      if (selected.length >= AppConstants.maxMessagesInContext) break;
      // Never send an empty assistant placeholder or a stored error to the
      // model; both would teach it a shape it should not imitate.
      if (message.isError) continue;
      if (message.content.isEmpty && message.imagePath == null) continue;

      final cost = TokenEstimator.estimate(message.content) + 4;
      if (spent + cost > budget && selected.isNotEmpty) break;
      spent += cost;
      selected.add(message);
    }

    final ordered = selected.reversed.toList(growable: false);

    return [
      PromptMessage(role: 'system', content: system),
      for (final message in ordered)
        PromptMessage(
          role: message.role,
          content: message.content,
          imagePath: message.imagePath,
        ),
    ];
  }

  /// How much of the window the prompt may occupy.
  ///
  /// The remaining headroom is where the answer goes; filling the window with
  /// history is how a chat ends up producing two tokens of reply before hitting
  /// the limit.
  static const double contextBudgetFraction = 0.70;

  String _systemPrompt(Persona? persona) {
    final base = persona?.systemPrompt ??
        'You are a study assistant in an offline app. Answer clearly and '
            'concisely, and show your working for anything mathematical.';
    return '$base\n\n'
        'The user is offline on a phone. You have no internet access and must '
        'not suggest searching the web. Format mathematics as LaTeX between '
        r'$...$'
        ' for inline and '
        r'$$...$$'
        ' for display.';
  }

  int _maxTokensFor(List<Message> history) {
    var used = 0;
    for (final message in history) {
      used += message.tokenCount ?? TokenEstimator.estimate(message.content);
    }
    final remaining = contextLength - used;
    // Never ask for more than the window can hold, and never less than a
    // paragraph's worth - a 3-token budget produces a broken-looking answer.
    return remaining.clamp(128, 4096);
  }

  /// Repeat penalty, defaulting to the model card's recommendation.
  ///
  /// Qwythos's card pairs low temperature with a light 1.05 penalty; applying
  /// the same value everywhere would be a guess, so the catalogue's own figure
  /// wins when it has one.
  double _repeatPenalty() {
    final modelId = _ref.read(activeModelIdProvider);
    final model = modelId == null
        ? null
        : _ref.read(catalogueProvider).valueOrNull?.byId(modelId);
    return model?.samplingDefaults.repeatPenalty ?? 1.1;
  }

  @override
  void dispose() {
    _disposed = true;
    _messagesSub?.cancel();
    _engineStatusSub?.cancel();
    super.dispose();
  }
}

/// App-wide chat session. Single instance: see the controller's class docs.
final chatControllerProvider = ChangeNotifierProvider<ChatController>(
  ChatController.new,
);
