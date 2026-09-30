package com.toxee.app

import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * What the Dart NotificationAccessMonitor cannot read through
 * flutter_local_notifications, and the settings deep links its notice offers.
 *
 * Channel name: `toxee/notification_access`.
 *
 *  - `sdkInt()` — Build.VERSION.SDK_INT (channels exist from 26, the
 *    full-screen-intent permission from 34).
 *  - `canUseFullScreenIntent()` — NotificationManager.canUseFullScreenIntent
 *    on API 34+, true below (granted by the manifest there).
 *  - `openSettings({target: app|channel|fullScreenIntent, channelId?})` —
 *    opens the page that fixes the problem; falls back to the app's
 *    notification page, then to its details page.
 *  - `isIgnoringBatteryOptimizations()` / `requestIgnoreBatteryOptimizations()`
 *    — whether Doze / OEM battery management may stop the background
 *    session, and the system dialog that exempts it (falls back to the
 *    battery-optimization list). Tox has no push server to wake the app.
 */
class NotificationAccessChannel(
    private val context: Context,
) : MethodChannel.MethodCallHandler {

    fun register(binaryMessenger: BinaryMessenger) {
        MethodChannel(binaryMessenger, CHANNEL_NAME).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "sdkInt" -> result.success(Build.VERSION.SDK_INT)
            "canUseFullScreenIntent" -> result.success(canUseFullScreenIntent())
            "isIgnoringBatteryOptimizations" ->
                result.success(isIgnoringBatteryOptimizations())
            "requestIgnoreBatteryOptimizations" -> {
                requestIgnoreBatteryOptimizations()
                result.success(null)
            }
            "openSettings" -> {
                openSettings(
                    call.argument<String>("target") ?: "app",
                    call.argument<String>("channelId"),
                )
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun canUseFullScreenIntent(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        val manager = context.getSystemService(NotificationManager::class.java)
        return manager?.canUseFullScreenIntent() ?: true
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val power = context.getSystemService(PowerManager::class.java) ?: return true
        return power.isIgnoringBatteryOptimizations(context.packageName)
    }

    private fun requestIgnoreBatteryOptimizations() {
        val request = Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:${context.packageName}"),
        )
        val list = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        for (intent in listOf(request, list)) {
            try {
                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return
            } catch (_: ActivityNotFoundException) {
                // Some OEM builds lack the direct dialog; try the list.
            }
        }
    }

    private fun openSettings(target: String, channelId: String?) {
        val packageName = context.packageName
        val specific: Intent? = when {
            target == "fullScreenIntent" &&
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE ->
                Intent(
                    Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                    Uri.parse("package:$packageName"),
                )
            target == "channel" && channelId != null &&
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ->
                Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    .putExtra(Settings.EXTRA_CHANNEL_ID, channelId)
            else -> null
        }
        val appNotifications =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            } else {
                null
            }
        val details = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:$packageName"),
        )
        for (intent in listOfNotNull(specific, appNotifications, details)) {
            try {
                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return
            } catch (_: ActivityNotFoundException) {
                // Try the next, more generic page.
            }
        }
    }

    companion object {
        const val CHANNEL_NAME = "toxee/notification_access"
    }
}
