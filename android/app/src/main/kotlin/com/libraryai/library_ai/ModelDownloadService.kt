package com.libraryai.library_ai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log

/**
 * Keeps a user-started large model transfer scheduled while the screen is off.
 * Flutter owns the HTTP stream; this service only supplies Android's
 * user-visible foreground lifetime and short-lived transfer locks.
 */
class ModelDownloadService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onCreate() {
        super.onCreate()
        createProgressChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action != ACTION_START) {
            stopSelf(startId)
            return START_NOT_STICKY
        }

        val notificationId = intent.getIntExtra(EXTRA_ID, DEFAULT_NOTIFICATION_ID)
        val notification = buildNotification(intent)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                notificationId,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(notificationId, notification)
        }
        acquireTransferLocks()
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        releaseTransferLocks()
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun buildNotification(intent: Intent): Notification {
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "Downloading model"
        val body = intent.getStringExtra(EXTRA_BODY) ?: "Transfer in progress"
        val percent = intent.getIntExtra(EXTRA_PERCENT, 0).coerceIn(0, 100)
        val indeterminate = intent.getBooleanExtra(EXTRA_INDETERMINATE, false)
        return Notification.Builder(this, PROGRESS_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_download)
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(100, percent, indeterminate)
            .build()
    }

    private fun createProgressChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            PROGRESS_CHANNEL_ID,
            "Model download progress",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Silent, in-place progress for user-started model downloads."
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun acquireTransferLocks() {
        try {
            if (wakeLock?.isHeld != true) {
                val power = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = power.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "LibraryAI:ModelDownload",
                ).apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
        } catch (error: Exception) {
            Log.e(TAG, "Could not acquire the transfer wake lock", error)
        }

        try {
            if (wifiLock?.isHeld != true) {
                val wifi = getSystemService(Context.WIFI_SERVICE) as WifiManager
                wifiLock = wifi.createWifiLock(
                    WifiManager.WIFI_MODE_FULL,
                    "LibraryAI:ModelDownload",
                ).apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
        } catch (error: Exception) {
            Log.e(TAG, "Could not acquire the transfer Wi-Fi lock", error)
        }
    }

    private fun releaseTransferLocks() {
        try {
            wifiLock?.takeIf { it.isHeld }?.release()
        } catch (error: Exception) {
            Log.e(TAG, "Could not release the transfer Wi-Fi lock", error)
        } finally {
            wifiLock = null
        }
        try {
            wakeLock?.takeIf { it.isHeld }?.release()
        } catch (error: Exception) {
            Log.e(TAG, "Could not release the transfer wake lock", error)
        } finally {
            wakeLock = null
        }
    }

    companion object {
        const val ACTION_START = "com.libraryai.library_ai.action.START_MODEL_DOWNLOAD"
        const val EXTRA_ID = "notification_id"
        const val EXTRA_TITLE = "notification_title"
        const val EXTRA_BODY = "notification_body"
        const val EXTRA_PERCENT = "notification_percent"
        const val EXTRA_INDETERMINATE = "notification_indeterminate"
        const val PROGRESS_CHANNEL_ID = "model_download_progress"
        private const val DEFAULT_NOTIFICATION_ID = 64013
        private const val TAG = "LibraryAI.DownloadService"
    }
}
