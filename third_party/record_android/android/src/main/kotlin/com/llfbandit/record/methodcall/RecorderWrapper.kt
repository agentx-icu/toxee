package com.llfbandit.record.methodcall

import android.app.Activity
import android.content.Context
import com.llfbandit.record.record.recorder.AudioRecorder
import com.llfbandit.record.record.RecordConfig
import com.llfbandit.record.record.bluetooth.BluetoothScoListener
import com.llfbandit.record.record.recorder.IRecorder
import com.llfbandit.record.record.recorder.MediaRecorder
import com.llfbandit.record.record.stream.RecorderRecordStreamHandler
import com.llfbandit.record.record.stream.RecorderStateStreamHandler
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

internal class RecorderWrapper(
    private val context: Context,
    recorderId: String,
    messenger: BinaryMessenger
): BluetoothScoListener {
    companion object {
        const val EVENTS_STATE_CHANNEL = "com.llfbandit.record/events/"
        const val EVENTS_RECORD_CHANNEL = "com.llfbandit.record/eventsRecord/"
    }

    private var eventChannel: EventChannel?
    private val recorderStateStreamHandler = RecorderStateStreamHandler()
    private var eventRecordChannel: EventChannel?
    private val recorderRecordStreamHandler = RecorderRecordStreamHandler()
    private var recorder: IRecorder? = null

    init {
        eventChannel = EventChannel(messenger, EVENTS_STATE_CHANNEL + recorderId)
        eventChannel?.setStreamHandler(recorderStateStreamHandler)
        eventRecordChannel = EventChannel(messenger, EVENTS_RECORD_CHANNEL + recorderId)
        eventRecordChannel?.setStreamHandler(recorderRecordStreamHandler)
    }

    fun setActivity(activity: Activity?) {
        recorderStateStreamHandler.setActivity(activity)
        recorderRecordStreamHandler.setActivity(activity)
    }

    fun startRecordingToFile(config: RecordConfig, result: MethodChannel.Result) {
        startRecording(config, result)
    }

    fun startRecordingToStream(config: RecordConfig, result: MethodChannel.Result) {
        if (config.useLegacy) {
            throw Exception("Unsupported feature from legacy recorder.")
        }
        startRecording(config, result)
    }

    fun dispose() {
        try {
            recorder?.dispose()
        } catch (ignored: Exception) {
        } finally {
            recorder = null
        }

        eventChannel?.setStreamHandler(null)
        eventChannel = null

        eventRecordChannel?.setStreamHandler(null)
        eventRecordChannel = null
    }

    fun pause(result: MethodChannel.Result) {
        try {
            recorder?.pause()
            result.success(null)
        } catch (e: Exception) {
            result.error("record", e.message, e.cause)
        }
    }

    fun isPaused(result: MethodChannel.Result) {
        result.success(recorder?.isPaused ?: false)
    }

    fun isRecording(result: MethodChannel.Result) {
        result.success(recorder?.isRecording ?: false)
    }

    fun getAmplitude(result: MethodChannel.Result) {
        if (recorder != null) {
            val amps = recorder!!.getAmplitude()
            val amp: MutableMap<String, Any> = HashMap()
            amp["current"] = amps[0]
            amp["max"] = amps[1]
            result.success(amp)
        } else {
            result.success(null)
        }
    }

    fun resume(result: MethodChannel.Result) {
        try {
            recorder?.resume()
            result.success(null)
        } catch (e: Exception) {
            result.error("record", e.message, e.cause)
        }
    }

    // toxee patch: a stop() reply can race another reply to the SAME result
    // (encoder-thread teardown vs an earlier synchronous path) — the second
    // result.success threw IllegalStateException "Reply already submitted" on
    // the encoder thread and killed the whole app (observed live during call
    // teardown on an Android emulator; reproduced with a per-lambda guard, so
    // the duplicate does not come from this lambda alone). Wrap the WHOLE
    // result: the first reply wins, later ones are logged and swallowed.
    private class IdempotentResult(
        private val inner: MethodChannel.Result
    ) : MethodChannel.Result {
        private val replied = java.util.concurrent.atomic.AtomicBoolean(false)
        private fun once(what: String, block: () -> Unit) {
            if (replied.compareAndSet(false, true)) {
                block()
            } else {
                android.util.Log.w(
                    "record",
                    "duplicate reply suppressed ($what)",
                    Throwable()
                )
            }
        }
        override fun success(res: Any?) = once("success") { inner.success(res) }
        override fun error(code: String, msg: String?, details: Any?) =
            once("error") { inner.error(code, msg, details) }
        override fun notImplemented() = once("notImplemented") { inner.notImplemented() }
    }

    fun stop(rawResult: MethodChannel.Result) {
        val result = IdempotentResult(rawResult)
        try {
            if (recorder == null) {
                result.success(null)
            } else {
                recorder?.stop(fun(path) = result.success(path))
            }
        } catch (e: Exception) {
            result.error("record", e.message, e.cause)
        }
    }

    fun cancel(result: MethodChannel.Result) {
        try {
            recorder?.cancel()
            result.success(null)
        } catch (e: Exception) {
            result.error("record", e.message, e.cause)
        }
    }

    private fun startRecording(config: RecordConfig, result: MethodChannel.Result) {
        try {
            if (recorder == null) {
                recorder = createRecorder(config)
                start(config, result)
            } else if (recorder!!.isRecording) {
                recorder!!.stop(fun(_) = start(config, result))
            } else {
                start(config, result)
            }
        } catch (e: Exception) {
            result.error("record", e.message, e.cause)
        }
    }

    private fun createRecorder(config: RecordConfig): IRecorder {
        if (config.useLegacy) {
            return MediaRecorder(context, recorderStateStreamHandler)
        }

        return AudioRecorder(
            recorderStateStreamHandler,
            recorderRecordStreamHandler,
            context
        )
    }

    private fun start(config: RecordConfig, result: MethodChannel.Result) {
        recorder!!.start(config)
        result.success(null)
    }

    ///////////////////////////////////////////////////////////
    // BluetoothScoListener
    ///////////////////////////////////////////////////////////
    override fun onBlScoConnected() {
    }

    override fun onBlScoDisconnected() {
    }
}