package com.toxee.app

import java.security.MessageDigest
import java.util.Collections
import java.util.concurrent.CountDownLatch
import kotlin.concurrent.thread
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class IncomingCallWindowLeaseStoreTest {
    @Test
    fun validLeaseIsCommittedBeforeGrant() {
        val storage = leaseStorage(callId = CALL_ID, nonce = NONCE, expiresAtEpochMs = 2000L)

        assertTrue(consume(storage))
        assertNoLease(storage)
        assertEquals(1, storage.commitCount)
    }

    @Test
    fun uppercaseNonceIsNormalizedBeforeValidation() {
        val storage = leaseStorage(callId = CALL_ID, nonce = NONCE, expiresAtEpochMs = 2000L)

        assertTrue(consume(storage, nonce = NONCE.uppercase()))
        assertNoLease(storage)
    }

    @Test
    fun expiryBoundaryFailsClosedAndClearsResidue() {
        val storage = leaseStorage(callId = CALL_ID, nonce = NONCE, expiresAtEpochMs = 1000L)

        assertFalse(consume(storage, nowEpochMs = 1000L))
        assertNoLease(storage)
    }

    @Test
    fun mismatchedNoncePreservesActiveLeaseAndDoesNotCommit() {
        val storage = leaseStorage(callId = CALL_ID, nonce = NONCE, expiresAtEpochMs = 2000L)

        assertFalse(consume(storage, nonce = OTHER_NONCE))
        assertActiveLease(storage)
        assertEquals(0, storage.commitCount)
    }

    @Test
    fun mismatchedCallIdentityPreservesActiveLeaseAndDoesNotCommit() {
        val storage = leaseStorage(callId = CALL_ID, nonce = NONCE, expiresAtEpochMs = 2000L)

        assertFalse(consume(storage, callId = "call-2"))
        assertActiveLease(storage)
        assertEquals(0, storage.commitCount)
    }

    @Test
    fun activeNonceDigestMismatchPreservesActiveLeaseAndDoesNotCommit() {
        val storage = leaseStorage(callId = CALL_ID, nonce = NONCE, expiresAtEpochMs = 2000L)

        assertFalse(consume(storage, activeNonceDigest = sha256Hex(OTHER_NONCE)))
        assertActiveLease(storage)
        assertEquals(0, storage.commitCount)
    }

    @Test
    fun nonceMustBeExactly64HexCharactersAndPreserveActiveLease() {
        val malformedNonces = listOf(
            NONCE.dropLast(1),
            NONCE + "0",
            NONCE.dropLast(1) + "g",
            NONCE.dropLast(1) + "\uFF26",
        )

        for (malformedNonce in malformedNonces) {
            val storage = leaseStorage(callId = CALL_ID, nonce = NONCE, expiresAtEpochMs = 2000L)
            assertFalse(consume(storage, nonce = malformedNonce))
            assertActiveLease(storage)
            assertEquals(0, storage.commitCount)
        }
    }

    @Test
    fun malformedStoredDigestsFailClosedAndClearResidue() {
        val malformedDigests = listOf(
            "0".repeat(63),
            "0".repeat(65),
            "0".repeat(63) + "g",
            "0".repeat(63) + "\uFF26",
        )

        for (malformedDigest in malformedDigests) {
            val nonceStorage = leaseStorage(CALL_ID, NONCE, 2000L).apply {
                put(IncomingCallWindowLeaseStore.NONCE_DIGEST_KEY, malformedDigest)
            }
            assertFalse(consume(nonceStorage))
            assertNoLease(nonceStorage)

            val callStorage = leaseStorage(CALL_ID, NONCE, 2000L).apply {
                put(IncomingCallWindowLeaseStore.CALL_ID_DIGEST_KEY, malformedDigest)
            }
            assertFalse(consume(callStorage))
            assertNoLease(callStorage)
        }
    }

    @Test
    fun blankControlAndOversizedCallIdentitiesPreserveActiveLease() {
        val malformedCallIds = listOf(
            "",
            "   ",
            "call\nid",
            "x".repeat(513),
        )

        for (malformedCallId in malformedCallIds) {
            val storage = leaseStorage(callId = CALL_ID, nonce = NONCE, expiresAtEpochMs = 2000L)
            assertFalse(consume(storage, callId = malformedCallId))
            assertActiveLease(storage)
            assertEquals(0, storage.commitCount)
        }
    }

    @Test
    fun hugeIncomingPayloadPreservesActiveLeaseWithoutHashingIt() {
        val storage = leaseStorage(callId = CALL_ID, nonce = NONCE, expiresAtEpochMs = 2000L)
        val payload = "incoming_call:${"x".repeat(100_000)}:$NONCE"

        assertFalse(consumePayload(storage, payload = payload))
        assertActiveLease(storage)
        assertEquals(0, storage.commitCount)
    }

    @Test
    fun malformedIncomingPayloadPreservesActiveLeaseAndDoesNotCommit() {
        val malformedPayloads = listOf(
            "incoming_call",
            "incoming_call:",
            "incoming_call:$CALL_ID",
            "incoming_call::$NONCE",
        )

        for (payload in malformedPayloads) {
            val storage = leaseStorage(callId = CALL_ID, nonce = NONCE, expiresAtEpochMs = 2000L)
            assertFalse(consumePayload(storage, payload = payload))
            assertActiveLease(storage)
            assertEquals(0, storage.commitCount)
        }
    }

    @Test
    fun bogusWellFormedPayloadLeavesLeaseIntactAndGenuinePayloadStillGrantsExactlyOnce() {
        val storage = leaseStorage(callId = CALL_ID, nonce = NONCE, expiresAtEpochMs = 2000L)

        assertFalse(consume(storage, callId = "call-2", nonce = OTHER_NONCE))
        assertActiveLease(storage)
        assertEquals(0, storage.commitCount)

        assertTrue(consume(storage))
        assertNoLease(storage)
        assertEquals(1, storage.commitCount)
    }

    @Test
    fun nonNotificationActionAndNonCallPayloadCannotGrantOrClearActiveLease() {
        val storage = leaseStorage(callId = CALL_ID, nonce = NONCE, expiresAtEpochMs = 2000L)
        val validPayload = payload(callId = CALL_ID, nonce = NONCE)

        assertFalse(consumePayload(storage, action = "android.intent.action.MAIN", payload = validPayload))
        assertActiveLease(storage)
        assertFalse(consumePayload(storage, payload = "c2c_peer"))
        assertActiveLease(storage)
        assertEquals(0, storage.commitCount)
    }

    @Test
    fun replayFailsAfterFirstConsume() {
        val storage = leaseStorage(callId = CALL_ID, nonce = NONCE, expiresAtEpochMs = 2000L)

        assertTrue(consume(storage))
        assertFalse(consume(storage))
        assertEquals(2, storage.commitCount)
    }

    @Test
    fun activeNonceDigestMatchStillCommitsBeforeGrant() {
        val storage = leaseStorage(callId = CALL_ID, nonce = NONCE, expiresAtEpochMs = 2000L)

        assertTrue(consume(storage, activeNonceDigest = sha256Hex(NONCE)))
        assertNoLease(storage)
        assertEquals(1, storage.commitCount)
    }

    @Test
    fun commitFailureFailsClosedWithoutGranting() {
        val storage = leaseStorage(
            callId = CALL_ID,
            nonce = NONCE,
            expiresAtEpochMs = 2000L,
            commitResult = false,
        )

        assertFalse(consume(storage))
        assertActiveLease(storage)
        assertEquals(1, storage.commitCount)
    }

    @Test
    fun concurrentConsumesGrantExactlyOnce() {
        val storage = leaseStorage(callId = CALL_ID, nonce = NONCE, expiresAtEpochMs = 2000L)
        val start = CountDownLatch(1)
        val results = Collections.synchronizedList(mutableListOf<Boolean>())
        val threads = List(8) {
            thread(start = true) {
                start.await()
                results.add(consume(storage))
            }
        }

        start.countDown()
        threads.forEach { it.join() }

        assertEquals(1, results.count { it })
        assertEquals(7, results.count { !it })
    }

    @Test
    fun startupClearsLeaseAtExpiryBoundary() {
        val storage = leaseStorage(callId = CALL_ID, nonce = NONCE, expiresAtEpochMs = 1000L)

        assertTrue(IncomingCallWindowLeaseStore.clearExpiredOrLegacyResidue(storage, 1000L))
        assertNoLease(storage)
    }

    @Test
    fun startupPreservesValidLease() {
        val storage = leaseStorage(callId = CALL_ID, nonce = NONCE, expiresAtEpochMs = 2000L)

        assertTrue(IncomingCallWindowLeaseStore.clearExpiredOrLegacyResidue(storage, 1000L))
        assertActiveLease(storage)
    }

    @Test
    fun startupClearsMalformedLeaseResidue() {
        val storage = leaseStorage(callId = CALL_ID, nonce = NONCE, expiresAtEpochMs = 2000L).apply {
            put(IncomingCallWindowLeaseStore.NONCE_DIGEST_KEY, "not-a-digest")
        }

        assertTrue(IncomingCallWindowLeaseStore.clearExpiredOrLegacyResidue(storage, 1000L))
        assertNoLease(storage)
    }

    @Test
    fun startupClearsInvalidExpiryResidue() {
        val storage = leaseStorage(callId = CALL_ID, nonce = NONCE, expiresAtEpochMs = 2000L).apply {
            put(IncomingCallWindowLeaseStore.EXPIRES_AT_EPOCH_MS_KEY, 0L)
        }

        assertTrue(IncomingCallWindowLeaseStore.clearExpiredOrLegacyResidue(storage, 1000L))
        assertNoLease(storage)
    }

    private fun consume(
        storage: FakeLeaseStorage,
        callId: String = CALL_ID,
        nonce: String = NONCE,
        activeNonceDigest: String? = null,
        nowEpochMs: Long = 1000L,
    ): Boolean {
        return consumePayload(
            storage = storage,
            payload = payload(callId = callId, nonce = nonce),
            activeNonceDigest = activeNonceDigest,
            nowEpochMs = nowEpochMs,
        )
    }

    private fun consumePayload(
        storage: FakeLeaseStorage,
        action: String? = IncomingCallWindowLeaseStore.FLUTTER_LOCAL_NOTIFICATIONS_SELECT_ACTION,
        payload: String?,
        activeNonceDigest: String? = null,
        nowEpochMs: Long = 1000L,
    ): Boolean {
        return IncomingCallWindowLeaseStore.consume(
            storage = storage,
            action = action,
            payload = payload,
            activeNonceDigest = activeNonceDigest,
            nowEpochMs = nowEpochMs,
        )
    }

    private fun payload(callId: String, nonce: String): String {
        return "incoming_call:$callId:$nonce"
    }

    private fun leaseStorage(
        callId: String,
        nonce: String,
        expiresAtEpochMs: Long,
        commitResult: Boolean = true,
    ): FakeLeaseStorage {
        return FakeLeaseStorage(
            mutableMapOf(
                IncomingCallWindowLeaseStore.NONCE_DIGEST_KEY to sha256Hex(nonce),
                IncomingCallWindowLeaseStore.EXPIRES_AT_EPOCH_MS_KEY to expiresAtEpochMs,
                IncomingCallWindowLeaseStore.CALL_ID_DIGEST_KEY to callIdentityDigest(callId),
            ),
            commitResult,
        )
    }

    private fun assertActiveLease(storage: FakeLeaseStorage) {
        assertEquals(sha256Hex(NONCE), storage.getString(IncomingCallWindowLeaseStore.NONCE_DIGEST_KEY))
        assertEquals(2000L, storage.getLong(IncomingCallWindowLeaseStore.EXPIRES_AT_EPOCH_MS_KEY))
        assertEquals(
            callIdentityDigest(CALL_ID),
            storage.getString(IncomingCallWindowLeaseStore.CALL_ID_DIGEST_KEY),
        )
    }

    private fun assertNoLease(storage: FakeLeaseStorage) {
        assertNull(storage.getString(IncomingCallWindowLeaseStore.NONCE_DIGEST_KEY))
        assertNull(storage.getLong(IncomingCallWindowLeaseStore.EXPIRES_AT_EPOCH_MS_KEY))
        assertNull(storage.getString(IncomingCallWindowLeaseStore.CALL_ID_DIGEST_KEY))
    }

    private fun callIdentityDigest(callId: String): String {
        return sha256Hex("toxee.incoming-call.v1:$callId")
    }

    private fun sha256Hex(value: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8))
        return digest.joinToString(separator = "") { byte -> "%02x".format(byte) }
    }

    private class FakeLeaseStorage(
        initialValues: MutableMap<String, Any>,
        private val commitResult: Boolean,
    ) : IncomingCallWindowLeaseStorage {
        private val values = Collections.synchronizedMap(initialValues)

        var commitCount = 0
            private set

        override fun contains(key: String): Boolean = values.containsKey(key)

        override fun getString(key: String): String? = values[key] as? String

        override fun getLong(key: String): Long? = values[key] as? Long

        override fun remove(keys: Collection<String>): Boolean {
            commitCount += 1
            if (!commitResult) return false
            keys.forEach { values.remove(it) }
            return true
        }

        fun put(key: String, value: Any) {
            values[key] = value
        }
    }

    private companion object {
        const val CALL_ID = "call-1"
        const val NONCE = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        const val OTHER_NONCE = "1123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    }
}
