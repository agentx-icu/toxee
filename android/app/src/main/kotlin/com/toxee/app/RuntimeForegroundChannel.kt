package com.toxee.app

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel bridge that lets Dart drive [ToxPollingService] without owning
 * the binder API.
 *
 * Channel name: `toxee/runtime_foreground`.
 *
 * Methods:
 *  - `start({title, body, settingsLabel})` — start the service in dataSync mode
 *  - `stop()` — stop the service
 *  - `elevateToCall({title, body})` — swap service type to phoneCall
 *  - `restoreFromCall()` — swap service type back to dataSync
 *
 * All Method results are completed on the main thread, per the Flutter
 * MethodChannel contract.
 */
class RuntimeForegroundChannel(
    private val context: Context,
) : MethodChannel.MethodCallHandler {

    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(binaryMessenger: BinaryMessenger) {
        MethodChannel(binaryMessenger, CHANNEL_NAME).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val intent = Intent(context, ToxPollingService::class.java).apply {
                    action = ToxPollingService.ACTION_START
                    putExtra(
                        ToxPollingService.EXTRA_TITLE,
                        call.argument<String>("title"),
                    )
                    putExtra(
                        ToxPollingService.EXTRA_BODY,
                        call.argument<String>("body"),
                    )
                    putExtra(
                        ToxPollingService.EXTRA_SETTINGS_LABEL,
                        call.argument<String>("settingsLabel"),
                    )
                    putExtra(ToxPollingService.EXTRA_FOR_CALL, false)
                }
                startServiceCompat(intent)
                replyOnMain(result, null)
            }

            "stop" -> {
                // Use stopService rather than startForegroundService+ACTION_STOP.
                // The latter would arm the "must call startForeground within 5s"
                // watchdog that startForegroundService triggers on Android 8+,
                // and ACTION_STOP's handler intentionally never calls
                // startForeground — risking a RemoteServiceException.
                // stopService drives ToxPollingService.onDestroy, which already
                // performs stopForegroundCompat() cleanup.
                val intent = Intent(context, ToxPollingService::class.java)
                runCatching { context.stopService(intent) }
                replyOnMain(result, null)
            }

            "elevateToCall" -> {
                val intent = Intent(context, ToxPollingService::class.java).apply {
                    action = ToxPollingService.ACTION_ELEVATE_CALL
                    putExtra(
                        ToxPollingService.EXTRA_TITLE,
                        call.argument<String>("title"),
                    )
                    putExtra(
                        ToxPollingService.EXTRA_BODY,
                        call.argument<String>("body"),
                    )
                    putExtra(
                        ToxPollingService.EXTRA_SETTINGS_LABEL,
                        call.argument<String>("settingsLabel"),
                    )
                    putExtra(ToxPollingService.EXTRA_FOR_CALL, true)
                    putExtra(
                        ToxPollingService.EXTRA_USE_CAMERA,
                        call.argument<Boolean>("usesCamera") ?: false,
                    )
                }
                startServiceCompat(intent)
                replyOnMain(result, null)
            }

            "restoreFromCall" -> {
                val intent = Intent(context, ToxPollingService::class.java).apply {
                    action = ToxPollingService.ACTION_RESTORE_DATA_SYNC
                    putExtra(
                        ToxPollingService.EXTRA_TITLE,
                        call.argument<String>("title"),
                    )
                    putExtra(
                        ToxPollingService.EXTRA_BODY,
                        call.argument<String>("body"),
                    )
                    putExtra(
                        ToxPollingService.EXTRA_SETTINGS_LABEL,
                        call.argument<String>("settingsLabel"),
                    )
                    putExtra(ToxPollingService.EXTRA_FOR_CALL, false)
                }
                startServiceCompat(intent)
                replyOnMain(result, null)
            }

            else -> replyOnMain(result, NotImplemented)
        }
    }

    private fun startServiceCompat(intent: Intent) {
        // On Android 8+ a backgrounded app must use startForegroundService.
        // The service must then call startForeground within ~5 seconds or the
        // system raises ANR. ToxPollingService.onStartCommand satisfies this
        // for every action (including ACTION_STOP, which still calls
        // stopForeground before stopSelf).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }

    private fun replyOnMain(result: MethodChannel.Result, value: Any?) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            if (value === NotImplemented) {
                result.notImplemented()
            } else {
                result.success(value)
            }
            return
        }
        mainHandler.post {
            if (value === NotImplemented) {
                result.notImplemented()
            } else {
                result.success(value)
            }
        }
    }

    private object NotImplemented

    companion object {
        const val CHANNEL_NAME = "toxee/runtime_foreground"
    }
}
