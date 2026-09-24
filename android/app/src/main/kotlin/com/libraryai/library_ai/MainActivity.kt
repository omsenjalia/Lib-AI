package com.libraryai.library_ai

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Owns the small platform seam used to start and stop the user-initiated
 * model-download foreground service. Inference remains in the Flutter app.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DOWNLOAD_SERVICE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val intent = Intent(this, ModelDownloadService::class.java).apply {
                        action = ModelDownloadService.ACTION_START
                        putExtra(
                            ModelDownloadService.EXTRA_ID,
                            call.argument<Int>("id") ?: 64013,
                        )
                        putExtra(
                            ModelDownloadService.EXTRA_TITLE,
                            call.argument<String>("title"),
                        )
                        putExtra(
                            ModelDownloadService.EXTRA_BODY,
                            call.argument<String>("body"),
                        )
                        putExtra(
                            ModelDownloadService.EXTRA_PERCENT,
                            call.argument<Int>("percent") ?: 0,
                        )
                        putExtra(
                            ModelDownloadService.EXTRA_INDETERMINATE,
                            call.argument<Boolean>("indeterminate") ?: false,
                        )
                    }
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("foreground_service_start", error.message, null)
                    }
                }

                "stop" -> {
                    stopService(Intent(this, ModelDownloadService::class.java))
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    companion object {
        private const val DOWNLOAD_SERVICE_CHANNEL = "library_ai/download_service"
    }
}
