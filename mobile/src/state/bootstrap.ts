import { router } from 'expo-router';
import { Platform } from 'react-native';

import { catalogue } from '@/core/catalogue';
import { getDb, listInstallations, upsertInstallation } from '@/core/db/database';
import { onNetworkChange } from '@/core/services/connectivity';
import { downloads } from '@/core/services/downloads';
import { files } from '@/core/services/files';
import { importLegacyData } from '@/core/services/legacyImport';
import { initNotifications, onNotificationResponse } from '@/core/services/notifications';
import { usePersonas, useConversations } from './collections';
import { useLibrary } from './library';
import { useSettings } from './settings';

let started = false;

/**
 * Cold start to chat-ready: open the database, import the Flutter build's data
 * once, read settings, hydrate the lists. No model is loaded here: paging in
 * gigabytes while someone is only looking at the app would slow the start and
 * risk the process being killed. The first question pays for the load, and the
 * UI shows it as a stage.
 */
export async function bootstrap(): Promise<void> {
  if (started) return;
  started = true;
  try {
    await start();
  } catch (e) {
    started = false;
    throw e;
  }
}

async function start(): Promise<void> {
  await getDb();
  await importLegacyData();
  await useSettings.getState().load();
  if (Platform.OS === 'web') await seedWebPreview();
  await Promise.all([useLibrary.getState().refresh(), useConversations.getState().refresh(), usePersonas.getState().refresh()]);

  if (files.supportsModels) await downloads.restorePartials(catalogue.models);

  void initNotifications();
  onNotificationResponse({
    pause: (modelId) => downloads.pause(modelId),
    open: (route) => router.push(route as '/library'),
  });

  scheduleUpdateChecks();
}

/**
 * Once per launch (after things settle) and whenever connectivity returns.
 * Each model is still throttled to one check per 24 h inside the checker.
 */
function scheduleUpdateChecks() {
  const run = () => {
    if (useSettings.getState().settings.autoUpdateCheckEnabled) void useLibrary.getState().checkUpdates();
  };
  setTimeout(run, 5000);
  let last: string | null = null;
  onNetworkChange((kind) => {
    if (last === 'offline' && kind !== 'offline') run();
    last = kind;
  });
}

/**
 * The browser preview has no llama.cpp; its backend streams a canned answer.
 * Give it one "installed" model so the chat surface can be exercised.
 */
async function seedWebPreview() {
  if ((await listInstallations()).length) return;
  const model = catalogue.models.find((m) => m.id === 'phi-4-mini-3.8b') ?? catalogue.models[0];
  const q = model.quants.find((x) => x.quant === model.recommendedQuant) ?? model.quants[0];
  await upsertInstallation({
    modelId: model.id,
    quant: q.quant,
    fileName: q.fileName,
    localPath: `${files.modelDir(model.id)}/${q.fileName}`,
    mmprojPath: null,
    sizeBytes: q.sizeBytes,
    sha256: q.sha256 ?? null,
    repoSha: model.ggufRepoSha ?? null,
    totalBytes: q.sizeBytes,
    downloadedAt: Date.now(),
  });
}
