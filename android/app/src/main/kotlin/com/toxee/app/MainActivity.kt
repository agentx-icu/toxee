package com.toxee.app

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import android.provider.MediaStore
import android.content.ContentValues
import android.os.Build
import java.io.File

class MainActivity : FlutterActivity() {
    private var callAudioChannel: CallAudioChannel? = null
    private var runtimeForegroundChannel: RuntimeForegroundChannel? = null
    private var qrSaveChannel: MethodChannel? = null

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
                try {
                    val source = File(path)
                    if (!source.exists()) {
                        result.error("NOT_FOUND", "Image file not found", null)
                        return@setMethodCallHandler
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
                        return@setMethodCallHandler
                    }
                    resolver.openOutputStream(uri)?.use { output ->
                        source.inputStream().use { input -> input.copyTo(output) }
                    } ?: run {
                        result.error("OPEN_FAILED", "Could not open gallery item", null)
                        return@setMethodCallHandler
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
        }
    }

    override fun onDestroy() {
        callAudioChannel?.dispose()
        callAudioChannel = null
        runtimeForegroundChannel = null
        qrSaveChannel?.setMethodCallHandler(null)
        qrSaveChannel = null
        super.onDestroy()
    }
}
