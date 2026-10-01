import { upsertInstallation } from '../db/database';
import { currentNetwork } from './connectivity';
import { DownloadManager } from './downloadManager';
import { files } from './files';
import { clearProgress, ensureNotificationPermission, showProgress, showResult } from './notifications';

/** The app-wide download manager, wired to the real disk, network and shade. */
export const downloads = new DownloadManager({
  files,
  network: currentNetwork,
  saveInstallation: upsertInstallation,
  notify: {
    permission: ensureNotificationPermission,
    progress: (p) => void showProgress(p),
    result: (id, title, body) => void showResult(id, title, body),
    clear: (id) => void clearProgress(id),
  },
});
