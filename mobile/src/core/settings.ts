import { AppConstants } from './constants';

/**
 * Preferences, stored as key/value rows. Keys match the Flutter build's
 * `SettingKeys`, so upgrading users keep their choices. An unparseable value
 * falls back to its default: a corrupt preference must never stop startup.
 */
export const SettingKeys = {
  themeMode: 'theme_mode',
  chatFont: 'chat_font',
  systemPrompt: 'system_prompt',
  defaultModelId: 'default_model_id',
  contextLength: 'context_length',
  temperature: 'temperature',
  topP: 'top_p',
  topK: 'top_k',
  gpuLayers: 'gpu_layers',
  autoUpdateCheckEnabled: 'auto_update_check_enabled',
  haptics: 'haptics',
  legacyImportDone: 'legacy_import_done',
} as const;

export type ThemeMode = 'dark' | 'light' | 'system';
export type ChatFont = 'lato' | 'lora' | 'system';

export type AppSettings = {
  themeMode: ThemeMode;
  chatFont: ChatFont;
  systemPrompt: string | null;
  defaultModelId: string | null;
  contextLength: number;
  temperature: number;
  topP: number;
  topK: number;
  gpuLayers: number;
  autoUpdateCheckEnabled: boolean;
  haptics: boolean;
};

export const defaultSettings: AppSettings = {
  themeMode: 'system',
  chatFont: 'lato',
  systemPrompt: null,
  defaultModelId: null,
  contextLength: AppConstants.defaultContextLength,
  temperature: AppConstants.defaultTemperature,
  topP: AppConstants.defaultTopP,
  topK: AppConstants.defaultTopK,
  gpuLayers: AppConstants.defaultGpuLayers,
  autoUpdateCheckEnabled: true,
  haptics: true,
};

const int = (v: string | undefined) => {
  const x = v === undefined ? NaN : Number.parseInt(v, 10);
  return Number.isFinite(x) ? x : undefined;
};
const float = (v: string | undefined) => {
  const x = v === undefined ? NaN : Number.parseFloat(v);
  return Number.isFinite(x) ? x : undefined;
};

export function settingsFromMap(map: Record<string, string>): AppSettings {
  const theme = map[SettingKeys.themeMode];
  const font = map[SettingKeys.chatFont];
  const prompt = (map[SettingKeys.systemPrompt] ?? '').trim();
  return {
    themeMode: theme === 'dark' || theme === 'light' || theme === 'system' ? theme : defaultSettings.themeMode,
    chatFont: font === 'lato' || font === 'lora' || font === 'system' ? font : defaultSettings.chatFont,
    systemPrompt: prompt ? map[SettingKeys.systemPrompt] : null,
    defaultModelId: map[SettingKeys.defaultModelId] || null,
    contextLength: int(map[SettingKeys.contextLength]) ?? defaultSettings.contextLength,
    temperature: float(map[SettingKeys.temperature]) ?? defaultSettings.temperature,
    topP: float(map[SettingKeys.topP]) ?? defaultSettings.topP,
    topK: int(map[SettingKeys.topK]) ?? defaultSettings.topK,
    gpuLayers: int(map[SettingKeys.gpuLayers]) ?? defaultSettings.gpuLayers,
    autoUpdateCheckEnabled: map[SettingKeys.autoUpdateCheckEnabled] !== 'false',
    haptics: map[SettingKeys.haptics] !== 'false',
  };
}

export function settingsToMap(s: AppSettings): Record<string, string | null> {
  return {
    [SettingKeys.themeMode]: s.themeMode,
    [SettingKeys.chatFont]: s.chatFont,
    [SettingKeys.systemPrompt]: s.systemPrompt?.trim() ? s.systemPrompt : null,
    [SettingKeys.defaultModelId]: s.defaultModelId,
    [SettingKeys.contextLength]: String(s.contextLength),
    [SettingKeys.temperature]: String(s.temperature),
    [SettingKeys.topP]: String(s.topP),
    [SettingKeys.topK]: String(s.topK),
    [SettingKeys.gpuLayers]: String(s.gpuLayers),
    [SettingKeys.autoUpdateCheckEnabled]: String(s.autoUpdateCheckEnabled),
    [SettingKeys.haptics]: String(s.haptics),
  };
}

/** The context window a model can be given: the slider's bounds. */
export function contextBoundsFor(maxContextLength?: number): { min: number; max: number } {
  const max = Math.min(
    Math.max(maxContextLength ?? AppConstants.defaultContextLength, AppConstants.minContextLength),
    AppConstants.maxContextCeiling,
  );
  return { min: AppConstants.minContextLength, max };
}
