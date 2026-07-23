package com.toxee.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Persistent foreground service that keeps the Flutter engine — and therefore
 * the tox polling loop in `FfiChatService` — alive while the app is
 * backgrounded.
 *
 * Two service-type modes are supported and can be transitioned at runtime
 * without restarting the service:
 *
 *  - [TYPE_MODE_DATA_SYNC] (default): for keeping the Tox connection alive so
 *    inbound messages, friend events, and ToxAV invites continue to arrive.
 *    Backed by `FOREGROUND_SERVICE_TYPE_DATA_SYNC`.
 *  - [TYPE_MODE_PHONE_CALL]: elevated while a ToxAV call is in progress so
 *    audio/video capture isn't throttled and the OS treats the process as a
 *    real call. Backed by `FOREGROUND_SERVICE_TYPE_PHONE_CALL`.
 *
 * The service is controlled exclusively via [Intent] actions sent from the
 * Dart-side `RuntimeForegroundService` MethodChannel. [onBind] returns null
 * because no binder API is exposed.
 *
 * **Process-kill caveat**: this service runs in the same Application process
 * as `MainActivity`. If the user swipes the app away from recent-apps, Android
 * will kill the process and stop the service — Tox polling will halt until the
 * user re-opens the app. This is intentional; we do not implement
 * `START_STICKY` restart-with-empty-intent or a sidecar process.
 */
class ToxPollingService : Service() {

    private var currentTypeMode: Int = TYPE_MODE_DATA_SYNC

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START
        when (action) {
            ACTION_START -> {
                val forCall = intent?.getBooleanExtra(EXTRA_FOR_CALL, false) ?: false
                currentTypeMode = if (forCall) TYPE_MODE_PHONE_CALL else TYPE_MODE_DATA_SYNC
                startInForeground(intent, currentTypeMode)
            }
            ACTION_ELEVATE_CALL -> {
                currentTypeMode = TYPE_MODE_PHONE_CALL
                startInForeground(intent, TYPE_MODE_PHONE_CALL)
            }
            ACTION_RESTORE_DATA_SYNC -> {
                currentTypeMode = TYPE_MODE_DATA_SYNC
                startInForeground(intent, TYPE_MODE_DATA_SYNC)
            }
            ACTION_STOP -> {
                stopForegroundCompat()
                stopSelf()
                return START_NOT_STICKY
            }
        }
        // NOT_STICKY: see process-kill caveat in the class doc. If the OS kills
        // us, we don't want Android to silently revive the service with a null
        // intent — that would leave us in foreground without a real session
        // backing it.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        stopForegroundCompat()
        super.onDestroy()
    }

    private fun startInForeground(intent: Intent?, typeMode: Int) {
        val title = intent?.getStringExtra(EXTRA_TITLE)
            ?: when (typeMode) {
                TYPE_MODE_PHONE_CALL -> DEFAULT_CALL_TITLE
                else -> DEFAULT_TITLE
            }
        val body = intent?.getStringExtra(EXTRA_BODY)
            ?: when (typeMode) {
                TYPE_MODE_PHONE_CALL -> DEFAULT_CALL_BODY
                else -> DEFAULT_BODY
            }
        val settingsLabel = intent?.getStringExtra(EXTRA_SETTINGS_LABEL)
            ?: DEFAULT_SETTINGS_LABEL

        val notification = buildNotification(typeMode, title, body, settingsLabel)
        // phoneCall/dataSync are available since API 29. Camera/microphone
        // types are available since API 30 and are required to preserve
        // while-in-use media access after the app is backgrounded. Android 14+
        // (UPSIDE_DOWN_CAKE) additionally requires the type to match a
        // <service android:foregroundServiceType=...> declaration in the
        // manifest, but the type constants themselves are valid as of Q.
        val serviceType: Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            when (typeMode) {
                TYPE_MODE_PHONE_CALL -> {
                    var callTypes = ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        callTypes = callTypes or
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                        val usesCamera = intent?.getBooleanExtra(
                            EXTRA_USE_CAMERA,
                            false,
                        ) ?: false
                        if (usesCamera) {
                            callTypes = callTypes or
                                ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
                        }
                    }
                    callTypes
                }
                else -> ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            }
        } else {
            0
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, serviceType)
        } else {
            @Suppress("DEPRECATION")
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(
        typeMode: Int,
        title: String,
        body: String,
        settingsLabel: String,
    ): Notification {
        val channelId = when (typeMode) {
            TYPE_MODE_PHONE_CALL -> CHANNEL_ID_CALL
            else -> CHANNEL_ID_RUNTIME
        }

        // Tapping the body opens MainActivity (brings the app back to front).
        val openAppIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            // Avoid spawning a fresh task — reuse the existing one so the
            // Flutter engine isn't double-attached.
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openAppPending = openAppIntent?.let {
            PendingIntent.getActivity(
                this,
                REQUEST_OPEN_APP,
                it,
                pendingFlagsImmutable(),
            )
        }

        // The "Hide / Settings" action routes the user to the system app-
        // notification settings, which is the only way to silence the
        // persistent service notification per Android UX guidelines.
        val settingsIntent = Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, packageName)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        val settingsPending = PendingIntent.getActivity(
            this,
            REQUEST_OPEN_SETTINGS,
            settingsIntent,
            pendingFlagsImmutable(),
        )

        val builder = NotificationCompat.Builder(this, channelId)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setPriority(
                if (typeMode == TYPE_MODE_PHONE_CALL) {
                    NotificationCompat.PRIORITY_HIGH
                } else {
                    NotificationCompat.PRIORITY_LOW
                },
            )
            .setCategory(
                if (typeMode == TYPE_MODE_PHONE_CALL) {
                    NotificationCompat.CATEGORY_CALL
                } else {
                    NotificationCompat.CATEGORY_SERVICE
                },
            )
            .addAction(
                NotificationCompat.Action.Builder(
                    /* icon = */ 0,
                    settingsLabel,
                    settingsPending,
                ).build(),
            )

        if (openAppPending != null) {
            builder.setContentIntent(openAppPending)
        }

        return builder.build()
    }

    private fun ensureChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Low-importance default channel. IMPORTANCE_LOW is below the heads-up
        // threshold and is silent, but stays visible in the status bar — exactly
        // what we want for the always-on dataSync state.
        if (nm.getNotificationChannel(CHANNEL_ID_RUNTIME) == null) {
            val runtime = NotificationChannel(
                CHANNEL_ID_RUNTIME,
                CHANNEL_NAME_RUNTIME,
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = CHANNEL_DESC_RUNTIME
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
            }
            nm.createNotificationChannel(runtime)
        }

        // Separate channel for the in-call elevation, so the user can mute the
        // dataSync banner without losing the (slightly louder) call indicator.
        // IMPORTANCE_DEFAULT keeps it from buzzing while still ranking higher
        // than the low-importance runtime banner.
        if (nm.getNotificationChannel(CHANNEL_ID_CALL) == null) {
            val call = NotificationChannel(
                CHANNEL_ID_CALL,
                CHANNEL_NAME_CALL,
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = CHANNEL_DESC_CALL
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
            }
            nm.createNotificationChannel(call)
        }
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun pendingFlagsImmutable(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
    }

    companion object {
        // Channel IDs — kept distinct from
        // `lib/notifications/notification_service.dart`'s channels
        // (`toxee_messages`, `toxee_friend_requests`, `toxee_missed_calls`).
        const val CHANNEL_ID_RUNTIME = "toxee_runtime"
        const val CHANNEL_ID_CALL = "toxee_runtime_call"

        private const val CHANNEL_NAME_RUNTIME = "Background connection"
        private const val CHANNEL_NAME_CALL = "Active call"
        private const val CHANNEL_DESC_RUNTIME =
            "Keeps Toxee connected so you can receive messages and calls in the background."
        private const val CHANNEL_DESC_CALL =
            "Shown while a Toxee call is in progress."

        // Distinct from the per-message / per-request notification IDs used in
        // notification_service.dart, which hash the conversation/peer ID and
        // are therefore guaranteed not to collide with this fixed ID.
        private const val NOTIFICATION_ID = 1001

        private const val REQUEST_OPEN_APP = 1
        private const val REQUEST_OPEN_SETTINGS = 2

        const val ACTION_START = "com.toxee.app.action.START_POLLING"
        const val ACTION_STOP = "com.toxee.app.action.STOP_POLLING"
        const val ACTION_ELEVATE_CALL = "com.toxee.app.action.ELEVATE_CALL"
        const val ACTION_RESTORE_DATA_SYNC = "com.toxee.app.action.RESTORE_DATA_SYNC"

        const val EXTRA_TITLE = "extra_title"
        const val EXTRA_BODY = "extra_body"
        const val EXTRA_SETTINGS_LABEL = "extra_settings_label"
        const val EXTRA_FOR_CALL = "extra_for_call"
        const val EXTRA_USE_CAMERA = "extra_use_camera"

        private const val TYPE_MODE_DATA_SYNC = 0
        private const val TYPE_MODE_PHONE_CALL = 1

        // English fallbacks if the Dart side never passes localized strings.
        // The expected path is for the Dart caller to pass localized values
        // through the intent extras above.
        private const val DEFAULT_TITLE = "Toxee is running"
        private const val DEFAULT_BODY =
            "Staying connected so you can receive messages and calls."
        private const val DEFAULT_CALL_TITLE = "Call in progress"
        private const val DEFAULT_CALL_BODY = "Toxee is keeping your call connected."
        private const val DEFAULT_SETTINGS_LABEL = "Settings"
    }
}
