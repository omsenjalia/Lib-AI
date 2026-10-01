import { createContext, useContext, useMemo, type ReactNode } from 'react';
import { useColorScheme } from 'react-native';

import { useSettings } from '@/state/settings';
import { dark, fonts, light, type Palette } from './tokens';

export type Theme = {
  scheme: 'light' | 'dark';
  colors: Palette;
  /** The family used for chat body text, from Settings. */
  chatFont: string;
};

const ThemeContext = createContext<Theme>({ scheme: 'dark', colors: dark, chatFont: fonts.sans });

export function ThemeProvider({ children }: { children: ReactNode }) {
  const system = useColorScheme();
  const mode = useSettings((s) => s.settings.themeMode);
  const font = useSettings((s) => s.settings.chatFont);
  const scheme: 'light' | 'dark' = mode === 'system' ? (system === 'light' ? 'light' : 'dark') : mode;
  const value = useMemo<Theme>(
    () => ({
      scheme,
      colors: scheme === 'dark' ? dark : light,
      chatFont: font === 'lora' ? fonts.serif : font === 'system' ? 'System' : fonts.sans,
    }),
    [scheme, font],
  );
  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export const useTheme = () => useContext(ThemeContext);
