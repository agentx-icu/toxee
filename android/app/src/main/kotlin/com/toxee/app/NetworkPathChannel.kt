package com.toxee.app

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/**
 * Reports the device's DEFAULT network path to Dart so the Tox session can be
 * re-bootstrapped after a Wi-Fi <-> cellular handover or an address change
 * (checklist N1; Dart side: lib/util/network_change_rebootstrapper.dart).
 *
 * Channel: `toxee/network_path` (EventChannel). Each event is
 * `{available: Boolean, identity: String?}`; `identity` combines the default
 * network's handle, its transports and its link addresses, so a new default
 * network AND a new address on the same one both change it. Dart only compares
 * identities for equality and ignores the first snapshot.
 *
 * Uses `registerDefaultNetworkCallback` (API 24+). API 23 (minSdk) has no
 * default-network callback: there every INTERNET-network event re-reads
 * `activeNetwork` (the default network) and reports that instead.
 */
class NetworkPathChannel(
    private val context: Context,
) : EventChannel.StreamHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var defaultNetwork: Network? = null
    private var capabilities: NetworkCapabilities? = null
    private var linkProperties: LinkProperties? = null
    private var lastSent: Pair<Boolean, String?>? = null

    fun register(binaryMessenger: BinaryMessenger) {
        EventChannel(binaryMessenger, CHANNEL_NAME).setStreamHandler(this)
    }

    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink,
    ) {
        sink = events
        lastSent = null
        val cm = context.getSystemService(ConnectivityManager::class.java) ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            listenApi23(cm)
            return
        }
        val cb =
            object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) =
                    post {
                        if (network != defaultNetwork) {
                            capabilities = null
                            linkProperties = null
                        }
                        defaultNetwork = network
                        emit()
                    }

                override fun onCapabilitiesChanged(
                    network: Network,
                    networkCapabilities: NetworkCapabilities,
                ) = post {
                    if (network == defaultNetwork) {
                        capabilities = networkCapabilities
                        emit()
                    }
                }

                override fun onLinkPropertiesChanged(
                    network: Network,
                    lp: LinkProperties,
                ) = post {
                    if (network == defaultNetwork) {
                        linkProperties = lp
                        emit()
                    }
                }

                override fun onLost(network: Network) =
                    post {
                        if (network == defaultNetwork) {
                            defaultNetwork = null
                            capabilities = null
                            linkProperties = null
                            emit()
                        }
                    }
            }
        try {
            cm.registerDefaultNetworkCallback(cb)
            callback = cb
            // The callback delivers the current default network (if any)
            // right away; report "no network" when there is none so Dart gets
            // its first snapshot either way.
            if (cm.activeNetwork == null) post { emit() }
        } catch (e: RuntimeException) {
            // SecurityException without ACCESS_NETWORK_STATE, or the per-app
            // callback limit: degrade to "no watcher" (resume refresh only).
            callback = null
        }
    }

    /** API 23: follow `activeNetwork` on every INTERNET-network change. */
    private fun listenApi23(cm: ConnectivityManager) {
        val refresh = {
            post {
                val network = cm.activeNetwork
                defaultNetwork = network
                capabilities = network?.let { cm.getNetworkCapabilities(it) }
                linkProperties = network?.let { cm.getLinkProperties(it) }
                emit()
            }
        }
        val cb =
            object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) = refresh()

                override fun onLost(network: Network) = refresh()

                override fun onCapabilitiesChanged(
                    network: Network,
                    networkCapabilities: NetworkCapabilities,
                ) = refresh()

                override fun onLinkPropertiesChanged(
                    network: Network,
                    lp: LinkProperties,
                ) = refresh()
            }
        try {
            val request =
                NetworkRequest
                    .Builder()
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .build()
            cm.registerNetworkCallback(request, cb)
            callback = cb
            refresh()
        } catch (e: RuntimeException) {
            callback = null
        }
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        val cb = callback ?: return
        callback = null
        try {
            context.getSystemService(ConnectivityManager::class.java)?.unregisterNetworkCallback(cb)
        } catch (_: RuntimeException) {
        }
        defaultNetwork = null
        capabilities = null
        linkProperties = null
    }

    private fun post(block: () -> Unit) {
        mainHandler.post(block)
    }

    private fun identity(): String? {
        val network = defaultNetwork ?: return null
        val transports =
            capabilities?.let { caps ->
                TRANSPORTS.filter { (id, _) -> caps.hasTransport(id) }.joinToString("+") { it.second }
            } ?: "?"
        val addresses =
            linkProperties
                ?.linkAddresses
                ?.map { it.address.hostAddress ?: "" }
                ?.sorted()
                ?.joinToString(",") ?: ""
        return "$network|$transports|$addresses"
    }

    private fun emit() {
        val events = sink ?: return
        val available = defaultNetwork != null
        // A new default network arrives as onAvailable, then its capabilities,
        // then its link properties. Report it once all three are known, so the
        // burst is ONE identity (otherwise the first snapshot after listening
        // would be followed by a spurious "change").
        if (available && (capabilities == null || linkProperties == null)) return
        val id = if (available) identity() else null
        val snapshot = Pair(available, id)
        if (snapshot == lastSent) return
        lastSent = snapshot
        events.success(mapOf("available" to available, "identity" to id))
    }

    companion object {
        const val CHANNEL_NAME = "toxee/network_path"

        private val TRANSPORTS =
            listOf(
                NetworkCapabilities.TRANSPORT_WIFI to "wifi",
                NetworkCapabilities.TRANSPORT_CELLULAR to "cellular",
                NetworkCapabilities.TRANSPORT_ETHERNET to "ethernet",
                NetworkCapabilities.TRANSPORT_VPN to "vpn",
                NetworkCapabilities.TRANSPORT_BLUETOOTH to "bluetooth",
            )
    }
}
