import { useFonts } from 'expo-font';
import { Stack } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { StatusBar } from 'expo-status-bar';
import * as SystemUI from 'expo-system-ui';
import { useEffect, useState } from 'react';
import { View } from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { KeyboardProvider } from 'react-native-keyboard-controller';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { AppText, Button } from '@/components/ui/primitives';
import { bootstrap } from '@/state/bootstrap';
import { ThemeProvider, useTheme } from '@/theme/ThemeProvider';
import { space } from '@/theme/tokens';

void SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  const [fontsLoaded, fontError] = useFonts({
    'Lato-Regular': require('../../assets/fonts/Lato-Regular.ttf'),
    'Lato-Medium': require('../../assets/fonts/Lato-Medium.ttf'),
    'Lato-Bold': require('../../assets/fonts/Lato-Bold.ttf'),
    'Lato-Italic': require('../../assets/fonts/Lato-Italic.ttf'),
    'Lora-Variable': require('../../assets/fonts/Lora-Variable.ttf'),
    'Lora-Italic-Variable': require('../../assets/fonts/Lora-Italic-Variable.ttf'),
    'JetBrainsMono-Variable': require('../../assets/fonts/JetBrainsMono-Variable.ttf'),
  });
  const [ready, setReady] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    let alive = true;
    bootstrap()
      .then(() => alive && setReady(true))
      .catch((e: unknown) => alive && setError(e instanceof Error ? e.message : String(e)));
    return () => {
      alive = false;
    };
  }, [attempt]);

  const retry = () => {
    setError(null);
    setAttempt((a) => a + 1);
  };

  const fontsDone = fontsLoaded || Boolean(fontError);
  useEffect(() => {
    if (fontsDone && (ready || error)) void SplashScreen.hideAsync();
  }, [fontsDone, ready, error]);

  if (!fontsDone || (!ready && !error)) return null;

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <KeyboardProvider>
          <ThemeProvider>
            {error ? <StartupError message={error} onRetry={retry} /> : <AppStack />}
          </ThemeProvider>
        </KeyboardProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}

function AppStack() {
  const { colors, scheme } = useTheme();
  useEffect(() => {
    void SystemUI.setBackgroundColorAsync(colors.canvas);
  }, [colors.canvas]);
  return (
    <>
      <StatusBar style={scheme === 'dark' ? 'light' : 'dark'} />
      <Stack
        screenOptions={{
          headerShown: false,
          contentStyle: { backgroundColor: colors.canvas },
          animation: 'slide_from_right',
          animationDuration: 260,
        }}
      >
        <Stack.Screen name="index" options={{ animation: 'fade' }} />
      </Stack>
    </>
  );
}

/** A database that will not open is the one failure the app cannot route around. */
function StartupError({ message, onRetry }: { message: string; onRetry: () => void }) {
  const { colors } = useTheme();
  return (
    <View style={{ flex: 1, backgroundColor: colors.canvas, justifyContent: 'center', padding: space.lg, gap: space.md }}>
      <AppText serif variant="heading">
        Library AI could not start
      </AppText>
      <AppText tone="body">The local database did not open. Your conversations are still on the phone.</AppText>
      <AppText variant="caption" mono tone="muted" selectable>
        {message}
      </AppText>
      <Button label="Try again" onPress={onRetry} style={{ alignSelf: 'flex-start' }} />
    </View>
  );
}
