import * as Notifications from 'expo-notifications';
import { Platform } from 'react-native';

import { formatBytes, formatDuration, formatSpeed } from '../utils/formatters';

/**
 * Download notifications. A 7 GB model takes long enough that progress cannot
 * live only in a screen the user has to keep open.
 *
 * Progress goes on a silent low-importance channel and updates in place under
 * one identifier per model. Completion and failure use a separate default-
 * importance channel, posted once. Android remembers a channel's importance
 * from when it was first created, which is why the two are separate.
 *
 * The permission is asked for when the first download starts, after the user
 * confirmed it; declining costs only the notification.
 */
const progressChannel = 'model-download-progress';
const resultChannel = 'model-download-result';
export const downloadCategory = 'model-download';
export const pauseActionId = 'pause';

let ready = false;

export async function initNotifications(): Promise<void> {
  if (ready || Platform.OS === 'web') return;
  ready = true;
  Notifications.setNotificationHandler({
    handleNotification: async () => ({
      shouldShowBanner: false,
      shouldShowList: true,
      shouldPlaySound: false,
      shouldSetBadge: false,
    }),
  });
  if (Platform.OS === 'android') {
    await Notifications.setNotificationChannelAsync(progressChannel, {
      name: 'Model download progress',
      importance: Notifications.AndroidImportance.LOW,
      vibrationPattern: null,
      enableVibrate: false,
      sound: null,
      showBadge: false,
    });
    await Notifications.setNotificationChannelAsync(resultChannel, {
      name: 'Model download finished',
      importance: Notifications.AndroidImportance.DEFAULT,
      showBadge: false,
    });
  }
  await Notifications.setNotificationCategoryAsync(downloadCategory, [
    { identifier: pauseActionId, buttonTitle: 'Pause', options: { opensAppToForeground: false } },
  ]);
}

let permission: boolean | null = null;

export async function ensureNotificationPermission(): Promise<boolean> {
  if (Platform.OS === 'web') return false;
  if (permission !== null) return permission;
  try {
    const current = await Notifications.getPermissionsAsync();
    permission = current.granted || (current.canAskAgain && (await Notifications.requestPermissionsAsync()).granted);
  } catch {
    permission = false;
  }
  return permission;
}

const idFor = (modelId: string) => `download-${modelId}`;

export type ProgressNote = {
  modelId: string;
  modelName: string;
  phase: 'downloading' | 'verifying';
  received: number;
  total: number;
  bytesPerSecond: number;
  etaMs: number;
  fileIndex: number;
  fileCount: number;
};

export function progressBody(p: ProgressNote): string {
  if (p.phase === 'verifying') return `Verifying ${p.modelName}`;
  const pct = p.total > 0 ? Math.floor((p.received / p.total) * 100) : 0;
  const files = p.fileCount > 1 ? `File ${p.fileIndex + 1} of ${p.fileCount}. ` : '';
  return `${files}${pct}%, ${formatBytes(p.received)} of ${formatBytes(p.total)}. ${formatSpeed(p.bytesPerSecond)}, ${formatDuration(p.etaMs)} left`;
}

export async function showProgress(p: ProgressNote): Promise<void> {
  if (!permission || Platform.OS === 'web') return;
  try {
    await Notifications.scheduleNotificationAsync({
      identifier: idFor(p.modelId),
      content: {
        title: `Downloading ${p.modelName}`,
        body: progressBody(p),
        sticky: true,
        autoDismiss: false,
        categoryIdentifier: downloadCategory,
        data: { modelId: p.modelId, route: '/library' },
        priority: Notifications.AndroidNotificationPriority.LOW,
      },
      trigger: Platform.OS === 'android' ? { channelId: progressChannel } : null,
    });
  } catch {
    // A notification failure must never fail the download.
  }
}

export async function showResult(modelId: string, title: string, body: string): Promise<void> {
  if (Platform.OS === 'web') return;
  await clearProgress(modelId);
  if (!permission) return;
  try {
    await Notifications.scheduleNotificationAsync({
      identifier: `${idFor(modelId)}-result`,
      content: { title, body, data: { modelId, route: '/library' } },
      trigger: Platform.OS === 'android' ? { channelId: resultChannel } : null,
    });
  } catch {
    // Non-fatal.
  }
}

export async function clearProgress(modelId: string): Promise<void> {
  if (Platform.OS === 'web') return;
  try {
    await Notifications.dismissNotificationAsync(idFor(modelId));
  } catch {
    // Already gone.
  }
}

/** Routes a tap or a Pause action. The notification layer never navigates itself. */
export function onNotificationResponse(handlers: {
  pause(modelId: string): void;
  open(route: string): void;
}): () => void {
  if (Platform.OS === 'web') return () => undefined;
  const sub = Notifications.addNotificationResponseReceivedListener((response) => {
    const data = response.notification.request.content.data as { modelId?: string; route?: string } | undefined;
    if (response.actionIdentifier === pauseActionId && data?.modelId) handlers.pause(data.modelId);
    else if (data?.route) handlers.open(data.route);
  });
  return () => sub.remove();
}
