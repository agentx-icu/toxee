package com.toxee.app

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var callAudioChannel: CallAudioChannel? = null
    private var runtimeForegroundChannel: RuntimeForegroundChannel? = null
    private var qrSaveChannel: MethodChannel? = null
    private var incomingCallWindowChannel: MethodChannel? = null
    private var pendingQrSaveResult: MethodChannel.Result? = null
    private var pendingQrSavePath: String? = null
    private var activeIncomingCallWindowToken: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        updateIncomingCallLockScreen(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        updateIncomingCallLockScreen(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        callAudioChannel = CallAudioChannel(this).also {
            it.register(flutterEngine.dartExecutor.binaryMessenger)
        }
        runtimeForegroundChannel = RuntimeForegroundChannel(applicationContext).also {
            it.register(flutterEngine.dartExecutor.binaryMessenger)
        }
        qrSaveChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "toxee/qr_save").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method != "saveImageToGallery") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "Expected readable image path", null)
                    return@setMethodCallHandler
                }

                val needsLegacyPermission =
                    Build.VERSION.SDK_INT <= Build.VERSION_CODES.P &&
                        checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
                        PackageManager.PERMISSION_GRANTED
                if (needsLegacyPermission) {
                    if (pendingQrSaveResult != null) {
                        result.error(
                            "SAVE_IN_PROGRESS",
                            "Another QR image is waiting for storage permission",
                            null,
                        )
                        return@setMethodCallHandler
                    }
                    pendingQrSavePath = path
                    pendingQrSaveResult = result
                    requestPermissions(
                        arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                        QR_SAVE_PERMISSION_REQUEST,
                    )
                    return@setMethodCallHandler
                }

                saveImageToGallery(path, result)
            }
        }
        incomingCallWindowChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "toxee/incoming_call_window",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "armIncomingCallWindow" -> {
                        val token = call.argument<String>(INCOMING_CALL_WINDOW_TOKEN_ARG)
                        if (token.isNullOrBlank()) {
                            result.error(
                                "INVALID_ARGS",
                                "Expected a non-empty incoming-call window token",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        activeIncomingCallWindowToken = token
                        incomingCallWindowPrefs()
                            .edit()
                            .putString(INCOMING_CALL_WINDOW_TOKEN_PREF_KEY, token)
                            .apply()
                        result.success(null)
                    }
                    "clearIncomingCallWindow" -> {
                        clearIncomingCallWindowState()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun updateIncomingCallLockScreen(intent: Intent?) {
        setIncomingCallLockScreenEnabled(isIncomingCallNotificationIntent(intent))
    }

    private fun isIncomingCallNotificationIntent(intent: Intent?): Boolean {
        if (intent?.action != FLUTTER_LOCAL_NOTIFICATIONS_SELECT_ACTION) return false
        val payload = intent.getStringExtra(FLUTTER_LOCAL_NOTIFICATIONS_PAYLOAD_EXTRA)
        val token = incomingCallWindowTokenFromPayload(payload) ?: return false
        return token == activeIncomingCallWindowToken ||
            token == incomingCallWindowPrefs().getString(INCOMING_CALL_WINDOW_TOKEN_PREF_KEY, null)
    }

    private fun incomingCallWindowTokenFromPayload(payload: String?): String? {
        if (payload == null || !payload.startsWith(INCOMING_CALL_PAYLOAD_PREFIX)) return null
        val separator = payload.lastIndexOf(':')
        if (separator <= INCOMING_CALL_PAYLOAD_PREFIX.length) return null
        return payload.substring(separator + 1).takeIf { it.isNotBlank() }
    }

    private fun clearIncomingCallWindowState() {
        activeIncomingCallWindowToken = null
        incomingCallWindowPrefs()
            .edit()
            .remove(INCOMING_CALL_WINDOW_TOKEN_PREF_KEY)
            .apply()
        setIncomingCallLockScreenEnabled(false)
    }

    private fun incomingCallWindowPrefs() = applicationContext.getSharedPreferences(
        FLUTTER_SHARED_PREFERENCES_NAME,
        Context.MODE_PRIVATE,
    )

    private fun setIncomingCallLockScreenEnabled(enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(enabled)
            setTurnScreenOn(enabled)
            return
        }

        @Suppress("DEPRECATION")
        val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
        if (enabled) {
            window.addFlags(flags)
        } else {
            window.clearFlags(flags)
        }
    }

    private fun saveImageToGallery(path: String, result: MethodChannel.Result) {
        try {
            val source = File(path)
            if (!source.exists()) {
                result.error("NOT_FOUND", "Image file not found", null)
                return
            }
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, source.name)
                put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Toxee")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
            }
            val resolver = applicationContext.contentResolver
            val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            if (uri == null) {
                result.error("INSERT_FAILED", "Could not create gallery item", null)
                return
            }
            resolver.openOutputStream(uri)?.use { output ->
                source.inputStream().use { input -> input.copyTo(output) }
            } ?: run {
                result.error("OPEN_FAILED", "Could not open gallery item", null)
                return
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            }
            result.success(uri.toString())
        } catch (e: Exception) {
            result.error("SAVE_FAILED", e.message, null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != QR_SAVE_PERMISSION_REQUEST) return

        val result = pendingQrSaveResult
        val path = pendingQrSavePath
        pendingQrSaveResult = null
        pendingQrSavePath = null
        if (result == null || path == null) return

        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            saveImageToGallery(path, result)
        } else {
            result.error(
                "PERMISSION_DENIED",
                "Storage permission is required to save images on Android 6-9",
                null,
            )
        }
    }

    override fun onDestroy() {
        callAudioChannel?.dispose()
        callAudioChannel = null
        runtimeForegroundChannel = null
        pendingQrSaveResult?.error(
            "ACTIVITY_DESTROYED",
            "QR save was interrupted",
            null,
        )
        pendingQrSaveResult = null
        pendingQrSavePath = null
        qrSaveChannel?.setMethodCallHandler(null)
        qrSaveChannel = null
        incomingCallWindowChannel?.setMethodCallHandler(null)
        incomingCallWindowChannel = null
        super.onDestroy()
    }

    private companion object {
        const val QR_SAVE_PERMISSION_REQUEST = 0x7172
        const val FLUTTER_LOCAL_NOTIFICATIONS_SELECT_ACTION = "SELECT_NOTIFICATION"
        const val FLUTTER_LOCAL_NOTIFICATIONS_PAYLOAD_EXTRA = "payload"
        const val INCOMING_CALL_PAYLOAD_PREFIX = "incoming_call:"
        const val INCOMING_CALL_WINDOW_TOKEN_ARG = "token"
        const val FLUTTER_SHARED_PREFERENCES_NAME = "FlutterSharedPreferences"
        const val INCOMING_CALL_WINDOW_TOKEN_PREF_KEY =
            "flutter.toxee_incoming_call_window_token"
    }
}
