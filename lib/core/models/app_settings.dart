import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// Keys used in the `SettingEntries` table. Kept as constants so a typo shows up
/// as a compile error rather than a silently ignored preference.
abstract final class SettingKeys {
  static const String themeMode = 'theme_mode';
  static const String defaultModelId = 'default_model_id';
  static const String contextLength = 'context_length';
  static const String temperature = 'temperature';
  static const String topP = 'top_p';
  static const String topK = 'top_k';
  static const String defaultSubjectTagId = 'default_subject_tag_id';
  static const String gpuLayers = 'gpu_layers';
  static const String autoUpdateCheckEnabled = 'auto_update_check_enabled';
}

/// Every user-facing preference, with the brief's defaults.
///
/// Immutable; the settings controller replaces the whole object on change and
/// persists the affected key.
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.defaultModelId,
    this.contextLength = AppConstants.defaultContextLength,
    this.temperature = AppConstants.defaultTemperature,
    this.topP = AppConstants.defaultTopP,
    this.topK = AppConstants.defaultTopK,
    this.defaultSubjectTagId,
    this.gpuLayers = AppConstants.defaultGpuLayers,
    this.autoUpdateCheckEnabled = true,
  });

  /// Dark-mode-first, per the brief.
  final ThemeMode themeMode;

  final String? defaultModelId;
  final int contextLength;
  final double temperature;
  final double topP;

  /// Persisted and rendered, but **not applied to inference**.
  ///
  /// fllama's `OpenAiRequest` exposes temperature, topP and the two penalties;
  /// it does not expose `top_k`. The settings screen says so in-line rather
  /// than pretending the slider does something. See ARCHITECTURE.md.
  final int topK;

  final int? defaultSubjectTagId;
  final int gpuLayers;
  final bool autoUpdateCheckEnabled;

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? defaultModelId,
    bool clearDefaultModelId = false,
    int? contextLength,
    double? temperature,
    double? topP,
    int? topK,
    int? defaultSubjectTagId,
    bool clearDefaultSubjectTagId = false,
    int? gpuLayers,
    bool? autoUpdateCheckEnabled,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        defaultModelId: clearDefaultModelId
            ? null
            : (defaultModelId ?? this.defaultModelId),
        contextLength: contextLength ?? this.contextLength,
        temperature: temperature ?? this.temperature,
        topP: topP ?? this.topP,
        topK: topK ?? this.topK,
        defaultSubjectTagId: clearDefaultSubjectTagId
            ? null
            : (defaultSubjectTagId ?? this.defaultSubjectTagId),
        gpuLayers: gpuLayers ?? this.gpuLayers,
        autoUpdateCheckEnabled:
            autoUpdateCheckEnabled ?? this.autoUpdateCheckEnabled,
      );

  /// Reads the persisted map, falling back to defaults for anything absent or
  /// unparseable. A corrupt preference should never stop the app starting.
  factory AppSettings.fromMap(Map<String, String> map) {
    int? asInt(String key) => int.tryParse(map[key] ?? '');
    double? asDouble(String key) => double.tryParse(map[key] ?? '');

    return AppSettings(
      themeMode: _themeModeFromName(map[SettingKeys.themeMode]),
      defaultModelId: map[SettingKeys.defaultModelId],
      contextLength:
          asInt(SettingKeys.contextLength) ?? AppConstants.defaultContextLength,
      temperature:
          asDouble(SettingKeys.temperature) ?? AppConstants.defaultTemperature,
      topP: asDouble(SettingKeys.topP) ?? AppConstants.defaultTopP,
      topK: asInt(SettingKeys.topK) ?? AppConstants.defaultTopK,
      defaultSubjectTagId: asInt(SettingKeys.defaultSubjectTagId),
      gpuLayers: asInt(SettingKeys.gpuLayers) ?? AppConstants.defaultGpuLayers,
      autoUpdateCheckEnabled:
          map[SettingKeys.autoUpdateCheckEnabled] != 'false',
    );
  }

  /// The key/value pairs to persist. Only keys the user has actually changed
  /// need writing, but writing the full set keeps the store self-describing.
  Map<String, String> toMap() => {
        SettingKeys.themeMode: themeMode.name,
        SettingKeys.contextLength: '$contextLength',
        SettingKeys.temperature: '$temperature',
        SettingKeys.topP: '$topP',
        SettingKeys.topK: '$topK',
        SettingKeys.gpuLayers: '$gpuLayers',
        SettingKeys.autoUpdateCheckEnabled: '$autoUpdateCheckEnabled',
        if (defaultModelId != null)
          SettingKeys.defaultModelId: defaultModelId!,
        if (defaultSubjectTagId != null)
          SettingKeys.defaultSubjectTagId: '$defaultSubjectTagId',
      };

  static ThemeMode _themeModeFromName(String? name) {
    switch (name) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      case 'dark':
      default:
        return ThemeMode.dark;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.themeMode == themeMode &&
      other.defaultModelId == defaultModelId &&
      other.contextLength == contextLength &&
      other.temperature == temperature &&
      other.topP == topP &&
      other.topK == topK &&
      other.defaultSubjectTagId == defaultSubjectTagId &&
      other.gpuLayers == gpuLayers &&
      other.autoUpdateCheckEnabled == autoUpdateCheckEnabled;

  @override
  int get hashCode => Object.hash(
        themeMode,
        defaultModelId,
        contextLength,
        temperature,
        topP,
        topK,
        defaultSubjectTagId,
        gpuLayers,
        autoUpdateCheckEnabled,
      );
}
