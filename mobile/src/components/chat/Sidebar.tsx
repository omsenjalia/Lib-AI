import { router } from 'expo-router';
import { Books, GearSix, MagnifyingGlass, Notebook, NotePencil, PushPin, Trash, UserSound, X } from 'phosphor-react-native';
import { memo, useMemo, useRef } from 'react';
import { SectionList, StyleSheet, TextInput, View } from 'react-native';
import ReanimatedSwipeable, { type SwipeableMethods } from 'react-native-gesture-handler/ReanimatedSwipeable';
import Animated, { FadeIn, FadeOut, LinearTransition, useAnimatedStyle, type SharedValue } from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppText, PressableScale, useHaptic } from '@/components/ui/primitives';
import { toast } from '@/components/ui/Toast';
import type { Conversation, ConversationSearchHit } from '@/core/db/types';
import { formatRelativeTime, recencyGroup } from '@/core/utils/formatters';
import { useChat } from '@/state/chat';
import { useConversations } from '@/state/collections';
import { useTheme } from '@/theme/ThemeProvider';
import { motion, radius, space } from '@/theme/tokens';
import { BrandMark } from './BrandMark';

type Section = { title: string; data: ConversationSearchHit[] };

/**
 * Recents, grouped by recency, pinned first. Swipe a row left to delete (with
 * Undo, because a swipe is easy to trigger by accident); long-press for the
 * full action sheet. Search covers titles and message text.
 */
export function SidebarContent({ onClose, onActions }: { onClose: () => void; onActions: (c: Conversation) => void }) {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const list = useConversations((s) => s.list);
  const query = useConversations((s) => s.query);
  const results = useConversations((s) => s.results);
  const search = useConversations((s) => s.search);
  const activeId = useChat((s) => s.conversationId);
  const open = useChat((s) => s.open);
  const newChat = useChat((s) => s.newChat);

  const sections = useMemo<Section[]>(() => {
    if (results) return [{ title: results.length ? 'Results' : 'No matches', data: results }];
    const pinned = list.filter((c) => c.pinned);
    const groups = new Map<string, ConversationSearchHit[]>();
    for (const c of list) {
      if (c.pinned) continue;
      const g = recencyGroup(c.updatedAt);
      if (!groups.has(g)) groups.set(g, []);
      groups.get(g)!.push({ ...c, snippet: null });
    }
    const out: Section[] = [];
    if (pinned.length) out.push({ title: 'Pinned', data: pinned.map((c) => ({ ...c, snippet: null })) });
    for (const [title, data] of groups) out.push({ title, data });
    return out;
  }, [list, results]);

  const go = (path: '/library' | '/personas' | '/notes' | '/settings') => {
    onClose();
    router.push(path);
  };

  return (
    <View style={[styles.wrap, { paddingTop: insets.top + space.xs, backgroundColor: colors.sidebar }]}>
      <View style={styles.header}>
        <BrandMark size={22} />
        <AppText serif variant="title" style={{ flex: 1 }}>
          Library AI
        </AppText>
        <PressableScale accessibilityRole="button" accessibilityLabel="Close" onPress={onClose} hitSlop={10} style={{ padding: 6 }}>
          <X size={18} color={colors.muted} />
        </PressableScale>
      </View>

      <PressableScale
        accessibilityRole="button"
        onPress={() => {
          newChat();
          onClose();
        }}
        haptic
        style={[styles.newChat, { backgroundColor: colors.ink }]}
      >
        <NotePencil size={18} color={colors.canvas} />
        <AppText weight="medium" tone="onAccent">
          New chat
        </AppText>
      </PressableScale>

      <View style={[styles.search, { backgroundColor: colors.surfaceSoft, borderColor: colors.hairline }]}>
        <MagnifyingGlass size={16} color={colors.mutedSoft} />
        <TextInput
          value={query}
          onChangeText={(q) => void search(q)}
          placeholder="Search conversations"
          placeholderTextColor={colors.mutedSoft}
          style={[styles.searchInput, { color: colors.ink }]}
          accessibilityLabel="Search conversations"
          returnKeyType="search"
        />
        {query ? (
          <PressableScale accessibilityLabel="Clear search" onPress={() => void search('')} hitSlop={8}>
            <X size={14} color={colors.muted} />
          </PressableScale>
        ) : null}
      </View>

      <SectionList
        sections={sections}
        keyExtractor={(c) => String(c.id)}
        stickySectionHeadersEnabled={false}
        keyboardShouldPersistTaps="handled"
        contentContainerStyle={{ paddingBottom: space.md }}
        ListEmptyComponent={
          <View style={{ padding: space.lg, alignItems: 'center' }}>
            <AppText variant="bodySmall" tone="muted" style={{ textAlign: 'center' }}>
              Your conversations will appear here. They are stored only on this phone.
            </AppText>
          </View>
        }
        renderSectionHeader={({ section }) => (
          <AppText variant="caption" tone="muted" weight="medium" style={styles.sectionHeader}>
            {section.title}
          </AppText>
        )}
        renderItem={({ item }) => (
          <Row
            item={item}
            active={item.id === activeId}
            onOpen={() => {
              void open(item.id);
              onClose();
            }}
            onLong={() => onActions(item)}
          />
        )}
      />

      <View style={[styles.footer, { borderTopColor: colors.hairlineSoft, paddingBottom: insets.bottom + space.xs }]}>
        <FooterItem icon={Books} label="Model Library" onPress={() => go('/library')} />
        <FooterItem icon={UserSound} label="Study personas" onPress={() => go('/personas')} />
        <FooterItem icon={Notebook} label="My Notes" onPress={() => go('/notes')} />
        <FooterItem icon={GearSix} label="Settings" onPress={() => go('/settings')} />
      </View>
    </View>
  );
}

const Row = memo(function Row({
  item,
  active,
  onOpen,
  onLong,
}: {
  item: ConversationSearchHit;
  active: boolean;
  onOpen: () => void;
  onLong: () => void;
}) {
  const { colors } = useTheme();
  const swipe = useRef<SwipeableMethods>(null);
  const remove = useConversations((s) => s.remove);
  const undo = useConversations((s) => s.undoDelete);
  const newChat = useChat((s) => s.newChat);
  const activeChat = useChat((s) => s.conversationId);
  const buzz = useHaptic();

  const del = async () => {
    buzz('warning');
    if (activeChat === item.id) newChat();
    await remove(item.id);
    toast(`Deleted "${item.title}"`, { action: { label: 'Undo', run: () => void undo() }, ms: 5000 });
  };

  return (
    <Animated.View layout={LinearTransition.duration(motion.base)} entering={FadeIn} exiting={FadeOut.duration(motion.fast)}>
      <ReanimatedSwipeable
        ref={swipe}
        friction={1.6}
        rightThreshold={48}
        overshootRight={false}
        renderRightActions={(_p, translation) => <DeleteAction translation={translation} onPress={() => void del()} />}
      >
        <PressableScale
          accessibilityRole="button"
          accessibilityState={{ selected: active }}
          accessibilityHint="Long press for options"
          onPress={onOpen}
          onLongPress={() => {
            buzz('medium');
            onLong();
          }}
          scaleTo={0.985}
          style={[styles.row, { backgroundColor: active ? colors.surfaceRaised : colors.sidebar }]}
        >
          <View style={{ flex: 1, gap: 2 }}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
              {item.pinned ? <PushPin size={12} color={colors.primary} weight="fill" /> : null}
              <AppText variant="bodySmall" weight="medium" numberOfLines={1} style={{ flex: 1, color: colors.bodyStrong }}>
                {item.title}
              </AppText>
              <AppText variant="micro" tone="mutedSoft">
                {formatRelativeTime(item.updatedAt)}
              </AppText>
            </View>
            {item.snippet ? (
              <AppText variant="caption" tone="muted" numberOfLines={1}>
                {item.snippet}
              </AppText>
            ) : null}
          </View>
        </PressableScale>
      </ReanimatedSwipeable>
    </Animated.View>
  );
});

function DeleteAction({ translation, onPress }: { translation: SharedValue<number>; onPress: () => void }) {
  const { colors } = useTheme();
  const style = useAnimatedStyle(() => ({ opacity: Math.min(1, Math.abs(translation.value) / 60) }));
  return (
    <Animated.View style={[{ width: 72, justifyContent: 'center', alignItems: 'center' }, style]}>
      <PressableScale
        accessibilityRole="button"
        accessibilityLabel="Delete conversation"
        onPress={onPress}
        style={{ width: 44, height: 44, borderRadius: 22, backgroundColor: colors.errorWash, alignItems: 'center', justifyContent: 'center' }}
      >
        <Trash size={19} color={colors.error} />
      </PressableScale>
    </Animated.View>
  );
}

function FooterItem({ icon: Icon, label, onPress }: { icon: typeof Books; label: string; onPress: () => void }) {
  const { colors } = useTheme();
  return (
    <PressableScale accessibilityRole="button" onPress={onPress} style={styles.footerItem}>
      <Icon size={19} color={colors.body} />
      <AppText variant="bodySmall" weight="medium" style={{ color: colors.bodyStrong }}>
        {label}
      </AppText>
    </PressableScale>
  );
}

const styles = StyleSheet.create({
  wrap: { flex: 1 },
  header: { flexDirection: 'row', alignItems: 'center', gap: space.xs, paddingHorizontal: space.md, height: 48 },
  newChat: {
    marginHorizontal: space.md,
    marginTop: space.xs,
    height: 44,
    borderRadius: radius.md,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: space.xs,
  },
  search: {
    marginHorizontal: space.md,
    marginTop: space.sm,
    marginBottom: space.xs,
    height: 40,
    borderRadius: radius.pill,
    borderWidth: 1,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: space.sm,
    gap: space.xs,
  },
  searchInput: { flex: 1, fontSize: 14, paddingVertical: 0 },
  sectionHeader: { paddingHorizontal: space.md + 4, paddingTop: space.md, paddingBottom: 6 },
  row: { marginHorizontal: space.xs, paddingHorizontal: space.sm, paddingVertical: 11, borderRadius: radius.md, minHeight: 46, justifyContent: 'center' },
  footer: { borderTopWidth: StyleSheet.hairlineWidth, paddingTop: space.xs, paddingHorizontal: space.xs },
  footerItem: { flexDirection: 'row', alignItems: 'center', gap: space.sm, paddingHorizontal: space.sm, paddingVertical: 10, borderRadius: radius.md },
});
