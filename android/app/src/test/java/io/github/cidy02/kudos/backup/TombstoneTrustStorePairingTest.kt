package io.github.cidy02.kudos.backup

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.test.core.app.ApplicationProvider
import com.google.crypto.tink.subtle.Ed25519Sign
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import java.io.File
import java.nio.file.Files
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Production-entry coverage for the keysync v1 pairing UI's trust-store
 * plumbing: [TombstoneTrustStore] revoke/rename/undo/denylist. Not covered
 * by [io.github.cidy02.kudos.backup.BackupTrustPhase2Test], which only
 * exercises trust()/isTrusted() as they existed before this unit.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class TombstoneTrustStorePairingTest {
    private lateinit var settingsScope: CoroutineScope
    private lateinit var settingsRepository: SettingsRepository
    private var now: Instant = Instant.parse("2026-08-16T12:00:00Z")

    @Before
    fun setUp() {
        val context: Context = ApplicationProvider.getApplicationContext()
        settingsScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val settingsDir = Files.createTempDirectory("kudos-pairing-settings").toFile()
        settingsRepository = SettingsRepository(
            PreferenceDataStoreFactory.create(
                scope = settingsScope,
                produceFile = { File(settingsDir, "settings.preferences_pb") }
            )
        )
    }

    @After
    fun tearDown() {
        settingsScope.cancel()
        TombstoneSigning.resetForTests()
    }

    private fun store(clock: () -> Instant = { now }) = TombstoneTrustStore(settingsRepository, clock)

    private fun peerHex(): String = Ed25519Sign.KeyPair.newKeyPair().publicKey.toLowerHex()

    @Test
    fun trustRecordsALabelAndATrustedAtTimestamp() = runTest {
        val hex = peerHex()
        assertTrue(store().trust(hex, label = "Sam's iPhone"))

        val devices = store().trustedDevices()
        assertEquals(1, devices.size)
        assertEquals(hex, devices.single().publicKeyHex)
        assertEquals("Sam's iPhone", devices.single().label)
        assertEquals(now, devices.single().trustedAt)
    }

    @Test
    fun trustDefaultsToABlankLabelNeverPrefilledFromTheWirePayload() = runTest {
        // Even if a "label"-shaped string rode along in the pasted text, only
        // the codec-parsed hex reaches trust() — the label param is separate
        // and the UI never forwards wire text into it.
        val hex = peerHex()
        assertTrue(store().trust(hex))
        assertEquals("", store().trustedDevices().single().label)
    }

    @Test
    fun renameSetsTheLocalLabelAfterTrusting() = runTest {
        val hex = peerHex()
        val trustStore = store()
        trustStore.trust(hex)
        trustStore.rename(hex, "Kitchen tablet")
        assertEquals("Kitchen tablet", trustStore.trustedDevices().single().label)
    }

    @Test
    fun revokeRetiredRemovesTrustButAllowsReTrusting() = runTest {
        val hex = peerHex()
        val trustStore = store()
        trustStore.trust(hex)

        assertTrue(trustStore.revoke(hex, KeyRevocationReason.RETIRED_OR_SOLD))
        assertFalse(trustStore.isTrusted(hex))
        assertTrue(trustStore.trustedDevices().isEmpty())

        // Retired/sold is not hostile — the same key can be paired again later
        // (e.g. the device was reset and given to someone else).
        assertTrue(trustStore.trust(hex))
        assertTrue(trustStore.isTrusted(hex))
    }

    @Test
    fun revokeStolenDenylistsTheKeySoItCanNeverBeReTrusted() = runTest {
        val hex = peerHex()
        val trustStore = store()
        trustStore.trust(hex)

        assertTrue(trustStore.revoke(hex, KeyRevocationReason.STOLEN_OR_COMPROMISED))
        assertFalse(trustStore.isTrusted(hex))

        // D9(a)-equivalent revoke-denylist: a re-paste of the exact same key
        // must not silently re-trust it.
        assertFalse(trustStore.trust(hex))
        assertFalse(trustStore.isTrusted(hex))
        assertTrue(trustStore.trustedDevices().isEmpty())
    }

    @Test
    fun trustRefusesTheDevicesOwnKey() = runTest {
        val pair = Ed25519Sign.KeyPair.newKeyPair()
        TombstoneSigning.initializeWithRawKeyPair(
            rawPrivateKey = pair.privateKey,
            rawPublicKey = pair.publicKey
        )
        val own = TombstoneSigning.publicKeyHex()
        assertFalse(store().trust(own))
        assertTrue(store().trustedDevices().isEmpty())
    }

    @Test
    fun undoTrustWithinTheWindowRevertsToUntrusted() = runTest {
        val hex = peerHex()
        val trustStore = store()
        trustStore.trust(hex)

        val within = now.plus(Duration.ofHours(23))
        assertTrue(trustStore.undoTrust(hex, now = within))
        assertFalse(trustStore.isTrusted(hex))
        assertTrue(trustStore.trustedDevices().isEmpty())
    }

    @Test
    fun undoTrustOutsideTheWindowDoesNothing() = runTest {
        val hex = peerHex()
        val trustStore = store()
        trustStore.trust(hex)

        val after = now.plus(Duration.ofHours(25))
        assertFalse(trustStore.undoTrust(hex, now = after))
        assertTrue(trustStore.isTrusted(hex))
        assertEquals(1, trustStore.trustedDevices().size)
    }

    @Test
    fun unknownSignerCountReflectsThePendingSet() = runTest {
        assertEquals(0, store().unknownSignerCount())
        settingsRepository.recordUnknownSignerTombstoneIds(
            newIds = setOf("a", "b"),
            adoptedIds = emptySet()
        )
        assertEquals(2, store().unknownSignerCount())
        settingsRepository.recordUnknownSignerTombstoneIds(
            newIds = emptySet(),
            adoptedIds = setOf("a")
        )
        assertEquals(1, store().unknownSignerCount())
    }
}
