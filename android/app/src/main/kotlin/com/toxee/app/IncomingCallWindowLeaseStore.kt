package com.toxee.app

import java.security.MessageDigest
import java.util.Locale

interface IncomingCallWindowLeaseStorage {
    fun contains(key: String): Boolean
    fun getString(key: String): String?
    fun getLong(key: String): Long?
    fun remove(keys: Collection<String>): Boolean
}

object IncomingCallWindowLeaseStore {
    const val FLUTTER_SHARED_PREFERENCES_NAME = "FlutterSharedPreferences"
    const val FLUTTER_LOCAL_NOTIFICATIONS_SELECT_ACTION = "SELECT_NOTIFICATION"
    const val LEGACY_RAW_TOKEN_KEY = "flutter.toxee_incoming_call_window_token"
    const val NONCE_DIGEST_KEY = "flutter.toxee_incoming_call_window_nonce_sha256"
    const val EXPIRES_AT_EPOCH_MS_KEY =
        "flutter.toxee_incoming_call_window_expires_at_epoch_ms"
    const val CALL_ID_DIGEST_KEY =
        "flutter.toxee_incoming_call_window_call_id_sha256"

    private val leaseKeys = listOf(
        NONCE_DIGEST_KEY,
        EXPIRES_AT_EPOCH_MS_KEY,
        CALL_ID_DIGEST_KEY,
    )
    private val allKeys = listOf(LEGACY_RAW_TOKEN_KEY) + leaseKeys

    @Synchronized
    fun consume(
        storage: IncomingCallWindowLeaseStorage,
        action: String?,
        payload: String?,
        activeNonceDigest: String? = null,
        nowEpochMs: Long,
    ): Boolean {
        return when (
            IncomingCallWindowLeaseValidator.evaluate(
                action = action,
                payload = payload,
                storedNonceDigest = storage.getString(NONCE_DIGEST_KEY),
                expiresAtEpochMs = storage.getLong(EXPIRES_AT_EPOCH_MS_KEY),
                storedCallIdDigest = storage.getString(CALL_ID_DIGEST_KEY),
                activeNonceDigest = activeNonceDigest,
                nowEpochMs = nowEpochMs,
            )
        ) {
            IncomingCallWindowLeaseDecision.ignore -> false
            IncomingCallWindowLeaseDecision.rejectAndClear -> {
                clearAll(storage)
                false
            }
            IncomingCallWindowLeaseDecision.grantAfterClear -> clearAll(storage)
        }
    }

    @Synchronized
    fun clearAll(storage: IncomingCallWindowLeaseStorage): Boolean {
        return storage.remove(allKeys)
    }

    @Synchronized
    fun clearExpiredOrLegacyResidue(
        storage: IncomingCallWindowLeaseStorage,
        nowEpochMs: Long,
    ): Boolean {
        val hasLeaseResidue = leaseKeys.any(storage::contains)
        if (!hasLeaseResidue) return true

        val leaseIsCurrentAndWellFormed = IncomingCallWindowLeaseValidator.isStoredLeaseCurrentAndWellFormed(
            storedNonceDigest = storage.getString(NONCE_DIGEST_KEY),
            expiresAtEpochMs = storage.getLong(EXPIRES_AT_EPOCH_MS_KEY),
            storedCallIdDigest = storage.getString(CALL_ID_DIGEST_KEY),
            nowEpochMs = nowEpochMs,
        )
        return if (leaseIsCurrentAndWellFormed) {
            true
        } else {
            clearAll(storage)
        }
    }
}

private enum class IncomingCallWindowLeaseDecision {
    ignore,
    rejectAndClear,
    grantAfterClear,
}

private object IncomingCallWindowLeaseValidator {
    private const val INCOMING_CALL_PAYLOAD_NAME = "incoming_call"
    private const val INCOMING_CALL_PAYLOAD_PREFIX = "$INCOMING_CALL_PAYLOAD_NAME:"
    private const val CALL_ID_DIGEST_PREFIX = "toxee.incoming-call.v1:"
    private const val NONCE_HEX_LENGTH = 64
    private const val SHA256_HEX_LENGTH = 64
    private const val MAX_CALL_ID_LENGTH = 512
    private const val MAX_PAYLOAD_LENGTH =
        INCOMING_CALL_PAYLOAD_PREFIX.length + MAX_CALL_ID_LENGTH + 1 + NONCE_HEX_LENGTH

    fun evaluate(
        action: String?,
        payload: String?,
        storedNonceDigest: String?,
        expiresAtEpochMs: Long?,
        storedCallIdDigest: String?,
        activeNonceDigest: String?,
        nowEpochMs: Long,
    ): IncomingCallWindowLeaseDecision {
        if (action != IncomingCallWindowLeaseStore.FLUTTER_LOCAL_NOTIFICATIONS_SELECT_ACTION) {
            return IncomingCallWindowLeaseDecision.ignore
        }
        if (!isIncomingCallPath(payload)) {
            return IncomingCallWindowLeaseDecision.ignore
        }

        if (expiresAtEpochMs == null || expiresAtEpochMs <= 0L || nowEpochMs >= expiresAtEpochMs) {
            return IncomingCallWindowLeaseDecision.rejectAndClear
        }
        val expectedNonceDigest = decodeSha256Digest(storedNonceDigest)
            ?: return IncomingCallWindowLeaseDecision.rejectAndClear
        val expectedCallIdDigest = decodeSha256Digest(storedCallIdDigest)
            ?: return IncomingCallWindowLeaseDecision.rejectAndClear

        val parsedPayload = parsePayload(payload)
            ?: return IncomingCallWindowLeaseDecision.ignore

        val normalizedNonce = parsedPayload.nonce.lowercase(Locale.ROOT)
        val nonceDigest = sha256(normalizedNonce)
        val activeDigest = if (activeNonceDigest == null) {
            null
        } else {
            decodeSha256Digest(activeNonceDigest)
                ?: return IncomingCallWindowLeaseDecision.ignore
        }
        if (activeDigest != null && !MessageDigest.isEqual(activeDigest, nonceDigest)) {
            return IncomingCallWindowLeaseDecision.ignore
        }

        val callIdDigest = callDigest(parsedPayload.callId)
        val nonceMatches = MessageDigest.isEqual(expectedNonceDigest, nonceDigest)
        val callIdMatches = MessageDigest.isEqual(expectedCallIdDigest, callIdDigest)
        return if (nonceMatches && callIdMatches) {
            IncomingCallWindowLeaseDecision.grantAfterClear
        } else {
            IncomingCallWindowLeaseDecision.ignore
        }
    }

    fun isStoredLeaseCurrentAndWellFormed(
        storedNonceDigest: String?,
        expiresAtEpochMs: Long?,
        storedCallIdDigest: String?,
        nowEpochMs: Long,
    ): Boolean {
        return expiresAtEpochMs != null &&
            expiresAtEpochMs > 0L &&
            nowEpochMs < expiresAtEpochMs &&
            decodeSha256Digest(storedNonceDigest) != null &&
            decodeSha256Digest(storedCallIdDigest) != null
    }

    private fun isIncomingCallPath(payload: String?): Boolean {
        return payload == INCOMING_CALL_PAYLOAD_NAME ||
            payload?.startsWith(INCOMING_CALL_PAYLOAD_PREFIX) == true
    }

    private fun parsePayload(payload: String?): IncomingCallWindowPayload? {
        if (payload == null || payload.length > MAX_PAYLOAD_LENGTH) return null
        if (!payload.startsWith(INCOMING_CALL_PAYLOAD_PREFIX)) return null

        val body = payload.substring(INCOMING_CALL_PAYLOAD_PREFIX.length)
        val separator = body.lastIndexOf(':')
        if (separator <= 0 || separator == body.length - 1) return null
        val callId = body.substring(0, separator)
        val nonce = body.substring(separator + 1)
        if (callId.isBlank() || callId.length > MAX_CALL_ID_LENGTH) return null
        if (callId.any { Character.isISOControl(it.code) }) return null
        if (nonce.length != NONCE_HEX_LENGTH || nonce.any { !it.isAsciiHexDigit() }) {
            return null
        }
        return IncomingCallWindowPayload(callId = callId, nonce = nonce)
    }

    private fun decodeSha256Digest(value: String?): ByteArray? {
        if (value == null || value.length != SHA256_HEX_LENGTH) return null
        val bytes = ByteArray(SHA256_HEX_LENGTH / 2)
        for (index in bytes.indices) {
            val highCharacter = value[index * 2]
            val lowCharacter = value[index * 2 + 1]
            if (!highCharacter.isAsciiHexDigit() || !lowCharacter.isAsciiHexDigit()) return null
            val high = highCharacter.digitToInt(16)
            val low = lowCharacter.digitToInt(16)
            bytes[index] = ((high shl 4) or low).toByte()
        }
        return bytes
    }

    private fun Char.isAsciiHexDigit(): Boolean {
        return this in '0'..'9' || this in 'a'..'f' || this in 'A'..'F'
    }

    private fun sha256(value: String): ByteArray {
        return MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8))
    }

    private fun callDigest(callId: String): ByteArray {
        return MessageDigest.getInstance("SHA-256")
            .digest("$CALL_ID_DIGEST_PREFIX$callId".toByteArray(Charsets.UTF_8))
    }

    private data class IncomingCallWindowPayload(
        val callId: String,
        val nonce: String,
    )
}
