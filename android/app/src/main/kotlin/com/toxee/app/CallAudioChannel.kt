package com.toxee.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class CallAudioChannel(
    private val context: Context,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val audioManager =
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var eventSink: EventChannel.EventSink? = null
    private var preferredRouteId: String? = null
    private var receiverRegistered = false
    private var audioSessionActive = false

    private val audioFocusChangeListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        val type =
            when (focusChange) {
                AudioManager.AUDIOFOCUS_GAIN -> "focusGained"
                AudioManager.AUDIOFOCUS_LOSS,
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK,
                -> "focusLost"

                else -> "state"
            }
        emit(type)
    }

    private var audioFocusRequest: AudioFocusRequest? = null

    private val noisyReceiver =
        object : BroadcastReceiver() {
            override fun onReceive(
                context: Context?,
                intent: Intent?,
            ) {
                if (AudioManager.ACTION_AUDIO_BECOMING_NOISY == intent?.action) {
                    emit("noisy")
                }
            }
        }

    private val deviceCallback =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            object : AudioDeviceCallback() {
                override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) {
                    emit("routeChanged")
                }

                override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
                    emit("routeChanged")
                }
            }
        } else {
            null
        }

    fun register(binaryMessenger: BinaryMessenger) {
        MethodChannel(binaryMessenger, "toxee/call_audio").setMethodCallHandler(this)
        EventChannel(binaryMessenger, "toxee/call_audio_events").setStreamHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "activateSession" -> {
                val preferSpeaker = call.argument<Boolean>("preferSpeaker") ?: false
                activateSession(preferSpeaker)
                result.success(makeState())
            }

            "deactivateSession" -> {
                deactivateSession()
                result.success(makeState())
            }

            "getState" -> result.success(makeState())

            "setRoute" -> {
                val routeId = call.argument<String>("routeId")
                setRoute(routeId)
                result.success(makeState())
            }

            else -> result.notImplemented()
        }
    }

    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink,
    ) {
        eventSink = events
        emit("state")
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun activateSession(preferSpeaker: Boolean) {
        audioSessionActive = true
        requestAudioFocus()
        registerReceivers()
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        if (preferredRouteId == null) {
            preferredRouteId = if (preferSpeaker) "speaker" else "earpiece"
        }
        applyPreferredRoute()
    }

    private fun deactivateSession() {
        audioSessionActive = false
        unregisterReceivers()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.clearCommunicationDevice()
        }
        audioManager.isSpeakerphoneOn = false
        if (audioManager.isBluetoothScoOn) {
            audioManager.stopBluetoothSco()
            audioManager.isBluetoothScoOn = false
        }
        abandonAudioFocus()
        audioManager.mode = AudioManager.MODE_NORMAL
    }

    private fun requestAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request =
                AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build(),
                    )
                    .setOnAudioFocusChangeListener(audioFocusChangeListener)
                    .build()
            audioFocusRequest = request
            audioManager.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                audioFocusChangeListener,
                AudioManager.STREAM_VOICE_CALL,
                AudioManager.AUDIOFOCUS_GAIN,
            )
        }
    }

    private fun abandonAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
            audioFocusRequest = null
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(audioFocusChangeListener)
        }
    }

    private fun registerReceivers() {
        if (receiverRegistered) return
        receiverRegistered = true
        context.registerReceiver(
            noisyReceiver,
            IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY),
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            deviceCallback?.let { audioManager.registerAudioDeviceCallback(it, null) }
        }
    }

    private fun unregisterReceivers() {
        if (!receiverRegistered) return
        receiverRegistered = false
        runCatching { context.unregisterReceiver(noisyReceiver) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            deviceCallback?.let { audioManager.unregisterAudioDeviceCallback(it) }
        }
    }

    private fun setRoute(routeId: String?) {
        preferredRouteId = routeId
        applyPreferredRoute()
        emit("routeChanged")
    }

    private fun applyPreferredRoute() {
        when (preferredRouteId) {
            "speaker" -> routeToSpeaker()
            "earpiece" -> routeToEarpiece()
            null -> routeToEarpiece()
            else -> routeToDevice(preferredRouteId!!)
        }
    }

    private fun routeToSpeaker() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            findSpeakerDevice()?.let {
                audioManager.setCommunicationDevice(it)
            }
        }
        audioManager.isSpeakerphoneOn = true
    }

    private fun routeToEarpiece() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.clearCommunicationDevice()
            findEarpieceDevice()?.let {
                audioManager.setCommunicationDevice(it)
            }
        }
        audioManager.isSpeakerphoneOn = false
        if (audioManager.isBluetoothScoOn) {
            audioManager.stopBluetoothSco()
            audioManager.isBluetoothScoOn = false
        }
    }

    private fun routeToDevice(routeId: String) {
        val device = availableOutputDevices().firstOrNull { routeIdForDevice(it) == routeId }
        if (device == null) {
            routeToEarpiece()
            return
        }

        when (classifyDevice(device)) {
            "bluetooth" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    audioManager.setCommunicationDevice(device)
                } else {
                    @Suppress("DEPRECATION")
                    audioManager.startBluetoothSco()
                    audioManager.isBluetoothScoOn = true
                }
                audioManager.isSpeakerphoneOn = false
            }

            "wired" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    audioManager.setCommunicationDevice(device)
                }
                audioManager.isSpeakerphoneOn = false
            }

            "speaker" -> routeToSpeaker()
            else -> routeToEarpiece()
        }
    }

    fun dispose() {
        unregisterReceivers()
        abandonAudioFocus()
    }

    private fun emit(type: String) {
        val sink = eventSink ?: return
        sink.success(
            mapOf(
                "type" to type,
                "state" to makeState(),
            ),
        )
    }

    private fun makeState(): Map<String, Any?> {
        val selectedRouteId = currentRouteId()
        val routes = mutableListOf<Map<String, Any?>>()

        if (hasEarpiece()) {
            routes += route(
                id = "earpiece",
                kind = "earpiece",
                label = "Earpiece",
                selected = selectedRouteId == "earpiece",
            )
        }

        routes += route(
            id = "speaker",
            kind = "speaker",
            label = "Speaker",
            selected = selectedRouteId == "speaker",
        )

        availableOutputDevices()
            .filter { classifyDevice(it) == "bluetooth" || classifyDevice(it) == "wired" }
            .forEach { device ->
                routes += route(
                    id = routeIdForDevice(device),
                    kind = classifyDevice(device),
                    label = device.productName?.toString() ?: defaultLabelForDevice(device),
                    selected = selectedRouteId == routeIdForDevice(device),
                )
            }

        return mapOf(
            "sessionActive" to audioSessionActive,
            "selectedRouteId" to selectedRouteId,
            "routes" to routes.distinctBy { it["id"] },
        )
    }

    private fun route(
        id: String,
        kind: String,
        label: String,
        selected: Boolean,
    ): Map<String, Any?> =
        mapOf(
            "id" to id,
            "kind" to kind,
            "label" to label,
            "selected" to selected,
        )

    private fun availableOutputDevices(): List<AudioDeviceInfo> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return emptyList()
        }
        return audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).toList()
    }

    private fun currentRouteId(): String? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.communicationDevice?.let { device ->
                return routeIdForDevice(device)
            }
        }
        if (audioManager.isSpeakerphoneOn) {
            return "speaker"
        }
        availableOutputDevices().firstOrNull { classifyDevice(it) == "wired" }?.let {
            return routeIdForDevice(it)
        }
        if (audioManager.isBluetoothScoOn) {
            availableOutputDevices().firstOrNull { classifyDevice(it) == "bluetooth" }?.let {
                return routeIdForDevice(it)
            }
        }
        return if (hasEarpiece()) "earpiece" else "speaker"
    }

    private fun classifyDevice(device: AudioDeviceInfo): String =
        when (device.type) {
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "earpiece"
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speaker"
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            -> "bluetooth"

            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_USB_DEVICE,
            -> "wired"

            else -> "unknown"
        }

    private fun routeIdForDevice(device: AudioDeviceInfo): String =
        when (classifyDevice(device)) {
            "speaker" -> "speaker"
            "earpiece" -> "earpiece"
            else -> "device:${device.id}"
        }

    private fun defaultLabelForDevice(device: AudioDeviceInfo): String =
        when (classifyDevice(device)) {
            "bluetooth" -> "Bluetooth"
            "wired" -> "Headphones"
            "speaker" -> "Speaker"
            "earpiece" -> "Earpiece"
            else -> "Audio route"
        }

    private fun findSpeakerDevice(): AudioDeviceInfo? =
        availableOutputDevices().firstOrNull {
            it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
        }

    private fun findEarpieceDevice(): AudioDeviceInfo? =
        availableOutputDevices().firstOrNull {
            it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
        }

    private fun hasEarpiece(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return findEarpieceDevice() != null
        }
        return context.packageManager.hasSystemFeature("android.hardware.telephony")
    }
}
