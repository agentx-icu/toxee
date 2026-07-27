package com.toxee.app

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private var callAudioChannel: CallAudioChannel? = null
    private var runtimeForegroundChannel: RuntimeForegroundChannel? = null
    private var qrSaveChannel: MethodChannel? = null
    private var incomingCallWindowChannel: MethodChannel? = null
    private var pendingQrSaveResult: MethodChannel.Result? = null
    private var pendingQrSavePath: String? = null
    private var activeIncomingCallWindowNonceDigest: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        clearExpiredIncomingCallWindowResidue()
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
                        val nonceDigest = sha256Hex(token)
                        val storedNonceDigest = incomingCallWindowStorage()
                            .getString(IncomingCallWindowLeaseStore.NONCE_DIGEST_KEY)
                        if (!constantTimeEquals(nonceDigest, storedNonceDigest)) {
                            clearIncomingCallWindowState()
                            result.error(
                                "LEASE_MISMATCH",
                                "Incoming-call window lease digest mismatch",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        activeIncomingCallWindowNonceDigest = nonceDigest
                        result.success(null)
                    }
                    "clearIncomingCallWindow" -> {
                        if (clearIncomingCallWindowState()) {
                            result.success(null)
                        } else {
                            result.error(
                                "CLEAR_FAILED",
                                "Could not clear incoming-call window lease",
                                null,
                            )
                        }
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
        val payload = intent?.getStringExtra(FLUTTER_LOCAL_NOTIFICATIONS_PAYLOAD_EXTRA)
        val granted = IncomingCallWindowLeaseStore.consume(
            storage = incomingCallWindowStorage(),
            action = intent?.action,
            payload = payload,
            activeNonceDigest = activeIncomingCallWindowNonceDigest,
            nowEpochMs = System.currentTimeMillis(),
        )
        if (granted) {
            activeIncomingCallWindowNonceDigest = null
        }
        return granted
    }

    private fun clearIncomingCallWindowState(): Boolean {
        activeIncomingCallWindowNonceDigest = null
        val cleared = IncomingCallWindowLeaseStore.clearAll(incomingCallWindowStorage())
        setIncomingCallLockScreenEnabled(false)
        return cleared
    }

    private fun clearExpiredIncomingCallWindowResidue() {
        IncomingCallWindowLeaseStore.clearExpiredOrLegacyResidue(
            incomingCallWindowStorage(),
            System.currentTimeMillis(),
        )
    }

    private fun incomingCallWindowStorage() = SharedPreferencesIncomingCallWindowLeaseStorage(
        applicationContext.getSharedPreferences(
            IncomingCallWindowLeaseStore.FLUTTER_SHARED_PREFERENCES_NAME,
            Context.MODE_PRIVATE,
        ),
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

    private fun sha256Hex(value: String): String =
        sha256Hex(value.toByteArray(Charsets.UTF_8))

    private fun sha256Hex(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        val chars = CharArray(digest.size * 2)
        for (index in digest.indices) {
            val value = digest[index].toInt() and 0xff
            chars[index * 2] = HEX_CHARS[value ushr 4]
            chars[index * 2 + 1] = HEX_CHARS[value and 0x0f]
        }
        return String(chars)
    }

    private fun constantTimeEquals(left: String?, right: String?): Boolean {
        if (left == null || right == null) return false
        return MessageDigest.isEqual(
            left.toByteArray(Charsets.UTF_8),
            right.toByteArray(Charsets.UTF_8),
        )
    }

    private class SharedPreferencesIncomingCallWindowLeaseStorage(
        private val prefs: SharedPreferences,
    ) : IncomingCallWindowLeaseStorage {
        override fun contains(key: String): Boolean = prefs.contains(key)

        override fun getString(key: String): String? {
            return try {
                prefs.getString(key, null)
            } catch (_: ClassCastException) {
                null
            }
        }

        override fun getLong(key: String): Long? {
            if (!prefs.contains(key)) return null
            return try {
                prefs.getLong(key, 0L)
            } catch (_: ClassCastException) {
                null
            }
        }

        override fun remove(keys: Collection<String>): Boolean {
            val editor = prefs.edit()
            for (key in keys) {
                editor.remove(key)
            }
            return editor.commit()
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
        const val FLUTTER_LOCAL_NOTIFICATIONS_PAYLOAD_EXTRA = "payload"
        const val INCOMING_CALL_WINDOW_TOKEN_ARG = "token"
        val HEX_CHARS = "0123456789abcdef".toCharArray()
    }
}
