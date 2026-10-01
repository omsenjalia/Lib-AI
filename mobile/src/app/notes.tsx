import { FilePdf, MagnifyingGlass, Quotes } from 'phosphor-react-native';
import { useEffect, useState } from 'react';
import { View } from 'react-native';
import Animated, { FadeInDown } from 'react-native-reanimated';

import { Screen } from '@/components/ui/Screen';
import { AppText, Chip } from '@/components/ui/primitives';
import { documentCount } from '@/core/db/database';
import { useTheme } from '@/theme/ThemeProvider';
import { radius, space } from '@/theme/tokens';

/**
 * Phase 2 placeholder, as in the Flutter build. The `documents` and
 * `document_chunks` tables already exist, so retrieval lands as an addition.
 */
export default function NotesScreen() {
  const { colors } = useTheme();
  const [count, setCount] = useState(0);
  useEffect(() => {
    void documentCount().then(setCount);
  }, []);
  const steps = [
    { icon: FilePdf, title: 'Import your PDFs and notes', body: 'Split into passages and stored in the same local database.' },
    { icon: MagnifyingGlass, title: 'Search them on the phone', body: 'A small embedding model finds the passages that answer your question.' },
    { icon: Quotes, title: 'Answers that cite your notes', body: 'Each answer says which document it came from.' },
  ];
  return (
    <Screen title="My Notes">
      <View style={{ padding: space.md, gap: space.lg }}>
        <View style={{ gap: space.xs }}>
          <Chip label="Coming soon" tone="accent" />
          <AppText serif variant="heading">
            Ask questions about your own material
          </AppText>
          <AppText tone="body">
            {count === 0 ? 'No documents yet.' : `${count} documents imported.`} Retrieval stays opt-in because the embedding model is
            another few hundred megabytes.
          </AppText>
        </View>
        {steps.map((s, i) => (
          <Animated.View
            key={s.title}
            entering={FadeInDown.delay(80 + i * 70).springify().damping(20)}
            style={{ flexDirection: 'row', gap: space.sm, padding: space.md, borderRadius: radius.xl, backgroundColor: colors.surface, borderWidth: 1, borderColor: colors.hairline }}
          >
            <s.icon size={22} color={colors.primary} />
            <View style={{ flex: 1, gap: 2 }}>
              <AppText weight="bold">{s.title}</AppText>
              <AppText variant="bodySmall" tone="muted">
                {s.body}
              </AppText>
            </View>
          </Animated.View>
        ))}
      </View>
    </Screen>
  );
}
