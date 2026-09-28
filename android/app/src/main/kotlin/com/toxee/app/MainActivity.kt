package com.toxee.app

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
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
    private var pendingGallerySave: GallerySaveRequest? = null
    private var activeIncomingCallWindowNonceDigest: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Claim before anything consumes this launch: a second instance (see
        // SessionOwnerChannel) must neither take the one-shot incoming-call
        // lease nor start a session. Its intent goes to the owner instead.
        val owner = SessionOwnerChannel.claimOrOwner(this)
        super.onCreate(savedInstanceState)
        if (owner != null) {
            SessionOwnerChannel.handOver(this, owner, intent)
            return
        }
        clearExpiredIncomingCallWindowResidue()
        updateIncomingCallLockScreen(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        updateIncomingCallLockScreen(intent)
    }

    /** An intent that reached a second instance, delivered to this owner. */
    fun receiveHandedOverIntent(handedOver: Intent) {
        setIntent(handedOver)
        onNewIntent(handedOver)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        callAudioChannel = CallAudioChannel(this).also {
            it.register(flutterEngine.dartExecutor.binaryMessenger)
        }
        runtimeForegroundChannel = RuntimeForegroundChannel(applicationContext).also {
            it.register(flutterEngine.dartExecutor.binaryMessenger)
        }
        NotificationAccessChannel(applicationContext)
            .register(flutterEngine.dartExecutor.binaryMessenger)
        SessionOwnerChannel(this).register(flutterEngine.dartExecutor.binaryMessenger)
        MediaTranscodeChannel(applicationContext).register(flutterEngine.dartExecutor.binaryMessenger)
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
                val mimeType = call.argument<String>("mimeType") ?: "image/png"
                if (!mimeType.startsWith("image/") && !mimeType.startsWith("video/")) {
                    result.error("INVALID_ARGS", "Not an image or video: $mimeType", null)
                    return@setMethodCallHandler
                }
                val request = GallerySaveRequest(
                    path,
                    mimeType,
                    call.argument<String>("displayName"),
                )

                val needsLegacyPermission =
                    Build.VERSION.SDK_INT <= Build.VERSION_CODES.P &&
                        checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
                        PackageManager.PERMISSION_GRANTED
                if (needsLegacyPermission) {
                    if (pendingQrSaveResult != null) {
                        result.error(
                            "SAVE_IN_PROGRESS",
                            "Another save is waiting for storage permission",
                            null,
                        )
                        return@setMethodCallHandler
                    }
                    pendingGallerySave = request
                    pendingQrSaveResult = result
                    requestPermissions(
                        arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                        QR_SAVE_PERMISSION_REQUEST,
                    )
                    return@setMethodCallHandler
                }

                saveToGallery(request, result)
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
                    // Debug builds only: lets the real-UI harness exercise the
                    // covering-activity close without a live incoming call.
                    "debugCloseCoveringActivities" -> {
                        val debuggable = applicationInfo.flags and
                            android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0
                        if (!debuggable) {
                            result.notImplemented()
                        } else {
                            val closed = pendingResultRequests.size
                            closeCoveringActivities()
                            result.success(closed)
                        }
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
        val incomingCall = isIncomingCallNotificationIntent(intent)
        setIncomingCallLockScreenEnabled(incomingCall)
        if (incomingCall) closeCoveringActivities()
    }

    /**
     * Request codes of activities this one started for a result and that
     * have not answered yet — a document picker, the camera, a SAF dialog.
     * They sit above this activity in its task.
     */
    private val pendingResultRequests = mutableSetOf<Int>()

    override fun startActivityForResult(intent: Intent, requestCode: Int, options: Bundle?) {
        if (requestCode >= 0) pendingResultRequests.add(requestCode)
        super.startActivityForResult(intent, requestCode, options)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        pendingResultRequests.remove(requestCode)
        super.onActivityResult(requestCode, resultCode, data)
    }

    /**
     * An incoming call must not ring under a picker (checklist L7a): with a
     * document picker open, the call intent even reaches a second instance,
     * which hands it here and brings this task forward — still under the
     * picker. Close what this activity opened for a result; each reports
     * RESULT_CANCELED to the plugin that asked, like a user's Back.
     */
    private fun closeCoveringActivities() {
        for (requestCode in pendingResultRequests.toList()) finishActivity(requestCode)
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

    /** A file to add to the photo library: an image or a video. */
    private data class GallerySaveRequest(
        val path: String,
        val mimeType: String,
        val displayName: String?,
    )

    /**
     * Copies [request] into MediaStore (Pictures/Toxee or Movies/Toxee). The
     * item stays pending until the copy is complete; any failure deletes it,
     * so a half-written item never shows up in the gallery.
     */
    private fun saveToGallery(request: GallerySaveRequest, result: MethodChannel.Result) {
        val source = File(request.path)
        if (!source.exists()) {
            result.error("NOT_FOUND", "Media file not found", null)
            return
        }
        val isVideo = request.mimeType.startsWith("video/")
        val collection = if (isVideo) {
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }
        val scoped = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, request.displayName ?: source.name)
            put(MediaStore.MediaColumns.MIME_TYPE, request.mimeType)
            if (scoped) {
                val dir = if (isVideo) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES
                put(MediaStore.MediaColumns.RELATIVE_PATH, "$dir/Toxee")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }
        val resolver = applicationContext.contentResolver
        var uri: android.net.Uri? = null
        try {
            uri = resolver.insert(collection, values)
                ?: throw IllegalStateException("Could not create gallery item")
            val output = resolver.openOutputStream(uri)
                ?: throw IllegalStateException("Could not open gallery item")
            output.use { out -> source.inputStream().use { it.copyTo(out) } }
            if (scoped) {
                val published = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                if (resolver.update(uri, published, null, null) != 1) {
                    throw IllegalStateException("Could not publish gallery item")
                }
            }
            result.success(uri.toString())
        } catch (e: Exception) {
            uri?.let {
                try {
                    resolver.delete(it, null, null)
                } catch (_: Exception) {
                    // Best effort: the pending item expires on its own.
                }
            }
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
        val request = pendingGallerySave
        pendingQrSaveResult = null
        pendingGallerySave = null
        if (result == null || request == null) return

        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            saveToGallery(request, result)
        } else {
            result.error(
                "PERMISSION_DENIED",
                "Storage permission is required to save to the gallery on Android 6-9",
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
        pendingGallerySave = null
        qrSaveChannel?.setMethodCallHandler(null)
        qrSaveChannel = null
        incomingCallWindowChannel?.setMethodCallHandler(null)
        incomingCallWindowChannel = null
        SessionOwnerChannel.release(this)
        super.onDestroy()
    }

    private companion object {
        const val QR_SAVE_PERMISSION_REQUEST = 0x7172
        const val FLUTTER_LOCAL_NOTIFICATIONS_PAYLOAD_EXTRA = "payload"
        const val INCOMING_CALL_WINDOW_TOKEN_ARG = "token"
        val HEX_CHARS = "0123456789abcdef".toCharArray()
    }
}
