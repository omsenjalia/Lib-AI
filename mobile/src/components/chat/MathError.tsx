import { View } from 'react-native';

import { AppText } from '@/components/ui/primitives';
import { useTheme } from '@/theme/ThemeProvider';
import { radius, space } from '@/theme/tokens';

/**
 * Broken TeX shows its source in a red-edged chip. A model emitting invalid
 * TeX should look like that, not like an app that lost the answer.
 */
export function MathError({ latex }: { latex: string }) {
  const { colors } = useTheme();
  return (
    <View style={{ borderRadius: radius.sm, borderWidth: 1, borderColor: colors.error, backgroundColor: colors.errorWash, padding: space.xs }}>
      <AppText variant="bodySmall" mono selectable style={{ color: colors.error }}>
        {latex}
      </AppText>
    </View>
  );
}
