import { router } from 'expo-router';
import { ArrowLeft } from 'phosphor-react-native';
import type { ReactNode } from 'react';
import { ScrollView, StyleSheet, View, type ScrollViewProps } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { useTheme } from '@/theme/ThemeProvider';
import { layout, space } from '@/theme/tokens';
import { AppText, Button, IconButton } from './primitives';
import { Sheet } from './Sheet';
import { ToastHost } from './Toast';

/** A pushed screen: back arrow, serif title, optional trailing action, scrolling body. */
export function Screen({
  title,
  trailing,
  children,
  scroll = true,
  scrollProps,
}: {
  title: string;
  trailing?: ReactNode;
  children: ReactNode;
  scroll?: boolean;
  scrollProps?: ScrollViewProps;
}) {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  return (
    <View style={{ flex: 1, backgroundColor: colors.canvas, paddingTop: insets.top }}>
      <View style={[styles.header, { borderBottomColor: colors.hairlineSoft }]}>
        <IconButton icon={ArrowLeft} label="Back" onPress={() => (router.canGoBack() ? router.back() : router.replace('/'))} tone="ink" />
        <AppText serif variant="title" style={{ flex: 1 }} accessibilityRole="header" numberOfLines={1}>
          {title}
        </AppText>
        {trailing}
      </View>
      {scroll ? (
        <ScrollView
          {...scrollProps}
          contentContainerStyle={[
            { paddingBottom: insets.bottom + space.xl, width: '100%', maxWidth: layout.maxReadingWidth, alignSelf: 'center' },
            scrollProps?.contentContainerStyle,
          ]}
          keyboardShouldPersistTaps="handled"
        >
          {children}
        </ScrollView>
      ) : (
        children
      )}
      <ToastHost bottom={insets.bottom + space.lg} />
    </View>
  );
}

/** Confirmation as a bottom sheet: the action is named on the button, never "OK". */
export function ConfirmSheet({
  visible,
  title,
  body,
  confirmLabel,
  danger,
  onConfirm,
  onClose,
  children,
}: {
  visible: boolean;
  title: string;
  body?: string;
  confirmLabel: string;
  danger?: boolean;
  onConfirm: () => void;
  onClose: () => void;
  children?: ReactNode;
}) {
  return (
    <Sheet visible={visible} onClose={onClose} title={title}>
      <View style={{ paddingHorizontal: space.md, gap: space.md }}>
        {body ? <AppText tone="body">{body}</AppText> : null}
        {children}
        <View style={{ flexDirection: 'row', gap: space.xs, justifyContent: 'flex-end' }}>
          <Button label="Cancel" variant="ghost" onPress={onClose} />
          <Button
            label={confirmLabel}
            variant={danger ? 'danger' : 'filled'}
            onPress={() => {
              onClose();
              onConfirm();
            }}
          />
        </View>
      </View>
    </Sheet>
  );
}

const styles = StyleSheet.create({
  header: {
    height: layout.topBar,
    flexDirection: 'row',
    alignItems: 'center',
    gap: space.xs,
    paddingHorizontal: space.xs,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
});
