import { create } from 'zustand';

import * as db from '@/core/db/database';
import { onChange } from '@/core/db/events';
import type { Conversation, ConversationSearchHit, Message, Persona } from '@/core/db/types';

type Snapshot = { conversation: Conversation; messages: Message[] };

type ConversationsState = {
  list: Conversation[];
  query: string;
  results: ConversationSearchHit[] | null;
  /** The last deletion, held for the Undo bar. */
  lastDeleted: Snapshot | null;
  refresh(): Promise<void>;
  search(query: string): Promise<void>;
  remove(id: number): Promise<void>;
  undoDelete(): Promise<void>;
  clearUndo(): void;
  rename(id: number, title: string): Promise<void>;
  togglePin(c: Conversation): Promise<void>;
};

export const useConversations = create<ConversationsState>((set, get) => ({
  list: [],
  query: '',
  results: null,
  lastDeleted: null,
  async refresh() {
    set({ list: await db.listConversations() });
    if (get().query) await get().search(get().query);
  },
  async search(query) {
    set({ query });
    if (!query.trim()) return set({ results: null });
    const results = await db.searchConversations(query);
    if (get().query === query) set({ results });
  },
  async remove(id) {
    const snapshot = await db.deleteConversation(id);
    if (snapshot) set({ lastDeleted: snapshot });
  },
  async undoDelete() {
    const snap = get().lastDeleted;
    set({ lastDeleted: null });
    if (snap) await db.restoreConversation(snap);
  },
  clearUndo: () => set({ lastDeleted: null }),
  async rename(id, title) {
    const t = title.trim();
    if (t) await db.updateConversation(id, { title: t.slice(0, 200) });
  },
  togglePin: (c) => db.updateConversation(c.id, { pinned: !c.pinned }),
}));

onChange(['conversations', 'messages'], () => void useConversations.getState().refresh());

type PersonasState = {
  list: Persona[];
  refresh(): Promise<void>;
  save(p: { id?: number; name: string; emoji: string; systemPrompt: string }): Promise<number>;
  remove(id: number): Promise<void>;
};

export const usePersonas = create<PersonasState>((set) => ({
  list: [],
  async refresh() {
    set({ list: await db.listPersonas() });
  },
  save: (p) => db.savePersona(p),
  remove: (id) => db.deletePersona(id),
}));

onChange(['personas'], () => void usePersonas.getState().refresh());
