import { router } from 'expo-router';
import { View } from 'react-native';

import { AppText, Button } from '@/components/ui/primitives';
import { useTheme } from '@/theme/ThemeProvider';
import { space } from '@/theme/tokens';

export default function NotFound() {
  const { colors } = useTheme();
  return (
    <View style={{ flex: 1, backgroundColor: colors.canvas, alignItems: 'center', justifyContent: 'center', gap: space.md, padding: space.lg }}>
      <AppText serif variant="heading">
        This page does not exist
      </AppText>
      <Button label="Back to chat" onPress={() => router.replace('/')} />
    </View>
  );
}
