import { create } from 'zustand';

import { allSettings, putSettings } from '@/core/db/database';
import { defaultSettings, settingsFromMap, settingsToMap, type AppSettings } from '@/core/settings';

type SettingsState = {
  settings: AppSettings;
  loaded: boolean;
  load(): Promise<void>;
  patch(patch: Partial<AppSettings>): Promise<void>;
};

export const useSettings = create<SettingsState>((set, get) => ({
  settings: defaultSettings,
  loaded: false,
  async load() {
    try {
      set({ settings: settingsFromMap(await allSettings()), loaded: true });
    } catch {
      set({ settings: defaultSettings, loaded: true });
    }
  },
  async patch(patch) {
    const next = { ...get().settings, ...patch };
    set({ settings: next });
    await putSettings(settingsToMap(next));
  },
}));
