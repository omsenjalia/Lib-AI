import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../data/database.dart';
import '../models/app_settings.dart';
import '../theme/claude_tokens.dart';

/// Loads and persists [AppSettings] against the `SettingEntries` table.
///
/// The database is the single source of truth - there is no second copy in
/// shared preferences. One consequence worth noting: because the whole settings
/// map is small, [save] writes every key rather than diffing, which keeps the
/// store self-describing and costs nothing measurable.
class SettingsService {
  SettingsService(this._db);

  final AppDatabase _db;

  /// Reads the persisted settings, falling back to defaults for anything
  /// missing or corrupt.
  ///
  /// This never throws on bad data: `AppSettings.fromMap` already coerces
  /// unparseable values, and a database read failure degrades to defaults so
  /// the app still starts. A preference store that can prevent startup would be
  /// a worse bug than a lost preference.
  Future<AppSettings> load() async {
    try {
      final map = await _db.allSettings();
      return AppSettings.fromMap(map);
    } catch (_) {
      return const AppSettings();
    }
  }

  /// Persists [settings] in one transaction.
  Future<void> save(AppSettings settings) async {
    final map = settings.toMap();
    await _db.transaction(() async {
      for (final entry in map.entries) {
        await _db.putSetting(entry.key, entry.value);
      }
      // A cleared default model must actually be removed, not merely omitted
      // from the map, or the old value would survive the write.
      if (settings.defaultModelId == null) {
        await _db.deleteSetting(SettingKeys.defaultModelId);
      }
      if (settings.modelStorageTreeUri == null) {
        await _db.deleteSetting(SettingKeys.modelStorageTreeUri);
      }
      if (settings.modelStorageFolderName == null) {
        await _db.deleteSetting(SettingKeys.modelStorageFolderName);
      }
    });
  }

  /// Convenience for single-key updates.
  Future<AppSettings> patch(
    AppSettings current, {
    ThemeMode? themeMode,
    String? defaultModelId,
    int? contextLength,
    double? temperature,
    double? topP,
    int? topK,
    int? gpuLayers,
    bool? autoUpdateCheckEnabled,
    ChatFontFamily? chatFont,
    String? systemPrompt,
    bool clearSystemPrompt = false,
  }) async {
    final next = current.copyWith(
      themeMode: themeMode,
      defaultModelId: defaultModelId,
      contextLength: contextLength,
      temperature: temperature,
      topP: topP,
      topK: topK,
      gpuLayers: gpuLayers,
      autoUpdateCheckEnabled: autoUpdateCheckEnabled,
      chatFont: chatFont,
      systemPrompt: systemPrompt,
      clearSystemPrompt: clearSystemPrompt,
    );
    await save(next);
    return next;
  }

  /// Clears the stored default model, used when the model it names is deleted.
  Future<AppSettings> clearDefaultModel(AppSettings current) async {
    final next = current.copyWith(clearDefaultModelId: true);
    await save(next);
    return next;
  }

  /// The context-length bounds offered for [model], respecting the model's own
  /// declared ceiling.
  static (int min, int max) contextBoundsFor({
    int? modelMaxContext,
    int? modelRecommendedContext,
  }) {
    final max = (modelMaxContext ?? AppConstants.defaultContextLength)
        .clamp(
          AppConstants.minContextLength,
          // No model in the catalogue declares anything near this, but the
          // slider value is persisted and later fed to fllama's contextSize, so
          // it is clamped rather than trusted.
          262144,
        )
        .toInt();
    return (AppConstants.minContextLength, max);
  }
}
