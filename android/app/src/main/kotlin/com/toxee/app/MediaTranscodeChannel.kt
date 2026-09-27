package com.toxee.app

import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * Converts outgoing media that desktop peers may not display (checklist M2).
 *
 * Channel name: `toxee/media_transcode`.
 *
 *  - `heicToJpeg({source, target})` — HEIC / HEIF to JPEG (quality 90).
 *    ImageDecoder applies the EXIF orientation; the new JPEG carries no EXIF,
 *    so no location leaves the device. Very large photos are scaled to a
 *    4096 px long edge so a low-memory phone does not run out decoding one.
 *    `UNSUPPORTED` before Android 9 (no HEIF decoder; such devices do not
 *    shoot HEIC either).
 */
class MediaTranscodeChannel {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun register(binaryMessenger: BinaryMessenger) {
        MethodChannel(binaryMessenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            if (call.method != "heicToJpeg") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val source = call.argument<String>("source")
            val target = call.argument<String>("target")
            if (source.isNullOrBlank() || target.isNullOrBlank()) {
                result.error("INVALID_ARGS", "source and target are required", null)
                return@setMethodCallHandler
            }
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
                result.error("UNSUPPORTED", "HEIF decoding needs Android 9", null)
                return@setMethodCallHandler
            }
            worker.execute {
                val error = try {
                    heicToJpeg(File(source), File(target))
                    null
                } catch (e: Exception) {
                    File(target).delete()
                    e.message ?: e.javaClass.simpleName
                } catch (e: OutOfMemoryError) {
                    File(target).delete()
                    "out of memory"
                }
                main.post {
                    if (error == null) result.success(null)
                    else result.error("FAILED", error, null)
                }
            }
        }
    }

    @androidx.annotation.RequiresApi(Build.VERSION_CODES.P)
    private fun heicToJpeg(source: File, target: File) {
        val bitmap = ImageDecoder.decodeBitmap(ImageDecoder.createSource(source)) { decoder, info, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            val longEdge = maxOf(info.size.width, info.size.height)
            if (longEdge > MAX_EDGE) {
                val scale = MAX_EDGE.toDouble() / longEdge
                decoder.setTargetSize(
                    (info.size.width * scale).toInt().coerceAtLeast(1),
                    (info.size.height * scale).toInt().coerceAtLeast(1),
                )
            }
        }
        try {
            FileOutputStream(target).use { out ->
                if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)) {
                    throw IllegalStateException("JPEG encoding failed")
                }
                out.fd.sync()
            }
        } finally {
            bitmap.recycle()
        }
    }

    companion object {
        const val CHANNEL_NAME = "toxee/media_transcode"
        private const val MAX_EDGE = 4096
    }
}
