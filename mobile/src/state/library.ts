import { create } from 'zustand';

import { catalogue, modelById, type CatalogueModel, type QuantOption } from '@/core/catalogue';
import { deleteInstallation, listInstallations, listUpdateChecks, upsertUpdateCheck } from '@/core/db/database';
import { onChange } from '@/core/db/events';
import type { ModelInstallation, UpdateCheck } from '@/core/db/types';
import { engine } from '@/core/engine';
import { currentNetwork } from '@/core/services/connectivity';
import type { DownloadTask } from '@/core/services/downloadManager';
import { downloads } from '@/core/services/downloads';
import { files } from '@/core/services/files';
import { checkForUpdates, fetchRepoState } from '@/core/services/updateChecker';
import { useSettings } from './settings';

type LibraryState = {
  installations: Record<string, ModelInstallation>;
  updates: Record<string, UpdateCheck>;
  tasks: ReadonlyMap<string, DownloadTask>;
  checkingUpdates: boolean;
  refresh(): Promise<void>;
  download(model: CatalogueModel, quant: QuantOption, includeMmproj: boolean): Promise<void>;
  pause(modelId: string): void;
  cancel(model: CatalogueModel): Promise<void>;
  /** Takes an id, not a catalogue entry, so a model the catalogue dropped can still be deleted. */
  remove(modelId: string): Promise<void>;
  setActive(modelId: string): Promise<void>;
  checkUpdates(force?: boolean): Promise<void>;
  dismissUpdate(modelId: string): Promise<void>;
};

export const useLibrary = create<LibraryState>((set, get) => ({
  installations: {},
  updates: {},
  tasks: new Map(),
  checkingUpdates: false,

  async refresh() {
    const [installs, checks] = await Promise.all([listInstallations(), listUpdateChecks()]);
    set({
      installations: Object.fromEntries(installs.map((i) => [i.modelId, i])),
      updates: Object.fromEntries(checks.map((c) => [c.modelId, c])),
    });
  },

  download: (model, quant, includeMmproj) => downloads.start(model, quant, includeMmproj),
  pause: (modelId) => downloads.pause(modelId),
  cancel: (model) => downloads.cancel(model),

  async remove(modelId) {
    const install = get().installations[modelId];
    if (engine.getStatus().modelId === modelId) await engine.unload();
    if (install) {
      await files.unlink(install.localPath);
      if (install.mmprojPath) await files.unlink(install.mmprojPath);
    }
    await deleteInstallation(modelId);
    if (useSettings.getState().settings.defaultModelId === modelId) {
      await useSettings.getState().patch({ defaultModelId: null });
    }
  },

  async setActive(modelId) {
    await useSettings.getState().patch({ defaultModelId: modelId });
  },

  async checkUpdates(force = false) {
    if (get().checkingUpdates || !files.supportsModels) return;
    set({ checkingUpdates: true });
    try {
      await checkForUpdates(
        catalogue.models,
        {
          network: currentNetwork,
          installations: listInstallations,
          checks: listUpdateChecks,
          save: upsertUpdateCheck,
          fetchRepo: (id) => fetchRepoState(id),
        },
        force,
      );
    } finally {
      set({ checkingUpdates: false });
    }
  },

  async dismissUpdate(modelId) {
    const check = get().updates[modelId];
    if (check) await upsertUpdateCheck({ ...check, updateAvailable: false });
  },
}));

downloads.subscribe((tasks) => useLibrary.setState({ tasks }));
onChange(['installations', 'updates'], () => void useLibrary.getState().refresh());

/**
 * The model chats use: the user's default if it is installed, otherwise the
 * first installed model, otherwise none.
 */
export function useActiveModelId(): string | null {
  const installations = useLibrary((s) => s.installations);
  const preferred = useSettings((s) => s.settings.defaultModelId);
  return resolveActiveModel(installations, preferred);
}

export function resolveActiveModel(installations: Record<string, ModelInstallation>, preferred: string | null): string | null {
  if (preferred && installations[preferred] && modelById(preferred)) return preferred;
  const first = Object.values(installations).find((i) => modelById(i.modelId));
  return first?.modelId ?? null;
}

export function getActiveModelId(): string | null {
  return resolveActiveModel(useLibrary.getState().installations, useSettings.getState().settings.defaultModelId);
}
