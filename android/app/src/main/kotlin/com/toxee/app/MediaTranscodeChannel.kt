package com.toxee.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
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
 *  - `probeVideo({source})` — the video codec as the same four-char codes
 *    the Apple side reports ("hvc1" HEVC, "avc1" H.264), null if unreadable.
 *    MediaExtractor reads the content, so the name needs no extension.
 *  - `transcodeToH264({id, source, target})` — H.264 / AAC MP4 with Media3
 *    Transformer (its encoder fallback lowers the resolution where a phone
 *    cannot encode the original). Reports `progress({id, progress})` every
 *    0.25 s; the output is checked to really be H.264 before success.
 *  - `cancelTranscode({id})` — the transcode then fails with CANCELLED.
 *
 * Transformer lives on its own looper thread: it needs one looper for all
 * of its calls, and `cancel()` waits for codec teardown, which must not
 * freeze Flutter's main thread. Channel replies go back on the main thread.
 */
@androidx.annotation.OptIn(markerClass = [UnstableApi::class])
class MediaTranscodeChannel(private val context: Context) {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /** Transformer's looper; [running] and [cancelHooks] are touched only here. */
    private val transformerThread = HandlerThread("toxee-media-transcode").apply { start() }
    private val transformerHandler = Handler(transformerThread.looper)
    private val running = mutableMapOf<String, Transformer>()

    /** Finishes a running transcode as CANCELLED. */
    private val cancelHooks = mutableMapOf<String, () -> Unit>()
    private lateinit var channel: MethodChannel

    fun register(binaryMessenger: BinaryMessenger) {
        channel = MethodChannel(binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler { call, result ->
            val source = call.argument<String>("source")
            val target = call.argument<String>("target")
            val id = call.argument<String>("id")
            when (call.method) {
                "heicToJpeg" -> {
                    if (source.isNullOrBlank() || target.isNullOrBlank()) {
                        return@setMethodCallHandler badArgs(result)
                    }
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
                        result.error("UNSUPPORTED", "HEIF decoding needs Android 9", null)
                        return@setMethodCallHandler
                    }
                    background(result) { heicToJpeg(File(source), File(target)) }
                }
                "probeVideo" -> {
                    if (source.isNullOrBlank()) return@setMethodCallHandler badArgs(result)
                    worker.execute {
                        val codec = videoCodec(source)
                        main.post { result.success(codec) }
                    }
                }
                "transcodeToH264" -> {
                    if (source.isNullOrBlank() || target.isNullOrBlank() || id.isNullOrBlank()) {
                        return@setMethodCallHandler badArgs(result)
                    }
                    transcode(id, source, target, result)
                }
                "cancelTranscode" -> {
                    // Transformer.cancel() notifies no listener: the pending
                    // transcode is finished here, as CANCELLED.
                    id?.let { key ->
                        transformerHandler.post {
                            running[key]?.cancel()
                            cancelHooks[key]?.invoke()
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun badArgs(result: MethodChannel.Result) =
        result.error("INVALID_ARGS", "missing arguments", null)

    private fun background(result: MethodChannel.Result, work: () -> Unit) {
        worker.execute {
            val error = try {
                work()
                null
            } catch (e: Exception) {
                e.message ?: e.javaClass.simpleName
            } catch (e: OutOfMemoryError) {
                "out of memory"
            }
            main.post {
                if (error == null) result.success(null) else result.error("FAILED", error, null)
            }
        }
    }

    // ------------------------------------------------------------------
    // HEIC -> JPEG
    // ------------------------------------------------------------------

    @androidx.annotation.RequiresApi(Build.VERSION_CODES.P)
    private fun heicToJpeg(source: File, target: File) {
        try {
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
        } catch (e: Throwable) {
            target.delete()
            throw e
        }
    }

    // ------------------------------------------------------------------
    // HEVC -> H.264
    // ------------------------------------------------------------------

    /** Track MIME types as the four-char codes Dart expects. */
    private fun videoCodec(path: String): String? {
        val mime = trackMime(path, "video/") ?: return null
        return when (mime) {
            MediaFormat.MIMETYPE_VIDEO_HEVC -> "hvc1"
            MediaFormat.MIMETYPE_VIDEO_AVC -> "avc1"
            else -> mime
        }
    }

    private fun trackMime(path: String, prefix: String): String? {
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(path)
            (0 until extractor.trackCount)
                .mapNotNull { extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME) }
                .firstOrNull { it.startsWith(prefix) }
        } catch (e: Exception) {
            null
        } finally {
            extractor.release()
        }
    }

    /**
     * True when [path]'s video track holds a real frame and a duration: an
     * export can "complete" with an empty track (seen with a one-frame
     * screen recording), and a black nothing must not be sent.
     */
    private fun hasVideoSamples(path: String): Boolean {
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(path)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true
            } ?: return false
            val format = extractor.getTrackFormat(track)
            val duration = if (format.containsKey(MediaFormat.KEY_DURATION)) {
                format.getLong(MediaFormat.KEY_DURATION)
            } else {
                0L
            }
            extractor.selectTrack(track)
            val buffer = java.nio.ByteBuffer.allocate(4 * 1024 * 1024)
            duration > 0 && extractor.readSampleData(buffer, 0) > 0
        } catch (e: Exception) {
            false
        } finally {
            extractor.release()
        }
    }

    private fun transcode(id: String, source: String, target: String, result: MethodChannel.Result) {
        worker.execute {
            val hasAudio = trackMime(source, "audio/") != null
            transformerHandler.post { startTranscode(id, source, target, hasAudio, result) }
        }
    }

    /** On the transformer looper. */
    private fun startTranscode(
        id: String,
        source: String,
        target: String,
        hasAudio: Boolean,
        result: MethodChannel.Result,
    ) {
        var progressTask: Runnable? = null
        var finished = false
        var reported = false // a listener callback arrived
        fun finish(error: Pair<String, String?>?) {
            if (finished) return // e.g. a cancel racing the completion check
            finished = true
            Log.i(TAG, "transcode $id finished: ${error ?: "ok"}")
            progressTask?.let { transformerHandler.removeCallbacks(it) }
            running.remove(id)
            cancelHooks.remove(id)
            if (error != null) File(target).delete()
            main.post {
                if (error == null) result.success(null) else result.error(error.first, error.second, null)
            }
        }
        val transformer = Transformer.Builder(context)
            .setLooper(transformerThread.looper)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    reported = true
                    Log.i(TAG, "transcode $id completed")
                    // The request is a promise, not a proof: check what came out.
                    worker.execute {
                        val video = trackMime(target, "video/")
                        val audio = trackMime(target, "audio/")
                        val codecs = video == MimeTypes.VIDEO_H264 &&
                            (!hasAudio || audio == MimeTypes.AUDIO_AAC)
                        val frames = hasVideoSamples(target)
                        transformerHandler.post {
                            finish(
                                when {
                                    !codecs -> "FAILED" to "unexpected output: $video / $audio"
                                    !frames -> "FAILED" to "the converted video has no frames"
                                    else -> null
                                },
                            )
                        }
                    }
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException,
                ) {
                    reported = true
                    Log.w(TAG, "transcode $id error", exportException)
                    finish("FAILED" to (exportException.message ?: "export failed"))
                }
            })
            .build()
        running[id] = transformer
        cancelHooks[id] = { finish("CANCELLED" to null) }
        val holder = ProgressHolder()
        var idlePolls = 0
        progressTask = object : Runnable {
            override fun run() {
                if (running[id] !== transformer) return
                when (transformer.getProgress(holder)) {
                    Transformer.PROGRESS_STATE_AVAILABLE -> {
                        idlePolls = 0
                        val progress = holder.progress / 100.0
                        main.post {
                            channel.invokeMethod("progress", mapOf("id" to id, "progress" to progress))
                        }
                    }
                    Transformer.PROGRESS_STATE_NOT_STARTED -> {
                        // Idle with no listener callback. Normally the callback
                        // follows shortly (the export is marked ended before its
                        // teardown finishes), so this waits generously; only an
                        // export that never reports is failed, so the progress
                        // dialog cannot wait forever.
                        if (!reported && ++idlePolls >= WATCHDOG_POLLS) {
                            Log.w(TAG, "transcode $id ended without a result")
                            finish("FAILED" to "the export ended without a result")
                            return
                        }
                    }
                    else -> idlePolls = 0
                }
                transformerHandler.postDelayed(this, 250)
            }
        }
        try {
            File(target).delete()
            transformer.start(
                EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(File(source)))).build(),
                target,
            )
            transformerHandler.postDelayed(progressTask, 250)
            Log.i(TAG, "transcode $id started")
        } catch (e: Exception) {
            finish("FAILED" to (e.message ?: "cannot export this video"))
        }
    }

    companion object {
        const val CHANNEL_NAME = "toxee/media_transcode"
        private const val TAG = "MediaTranscode"
        /** 30 s of an idle transformer that never reported. */
        private const val WATCHDOG_POLLS = 120
        private const val MAX_EDGE = 4096
    }
}
