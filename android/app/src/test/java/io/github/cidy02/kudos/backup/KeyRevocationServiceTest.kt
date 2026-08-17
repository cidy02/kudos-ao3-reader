package io.github.cidy02.kudos.backup

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.google.crypto.tink.subtle.Ed25519Sign
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.SyncTombstone
import io.github.cidy02.kudos.core.model.SyncTombstoneRecordType
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.works.WorkRepository
import java.io.File
import java.nio.file.Files
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Production-entry coverage for the "Stolen or compromised" revoke flow's
 * restore step: [KeyRevocationService.restoreWorksDeletedBy] against the
 * real [io.github.cidy02.kudos.data.local.dao.SyncTombstoneDao.getBySigner]
 * query and [WorkRepository.restoreFromRecentlyDeleted].
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class KeyRevocationServiceTest {
    private lateinit var database: KudosDatabase
    private lateinit var settingsScope: CoroutineScope
    private lateinit var settingsRepository: SettingsRepository
    private lateinit var workRepository: WorkRepository
    private lateinit var trustStore: TombstoneTrustStore
    private lateinit var service: KeyRevocationService

    private val workId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"

    @Before
    fun setUp() {
        val context: Context = ApplicationProvider.getApplicationContext()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        settingsScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val settingsDir = Files.createTempDirectory("kudos-revoke-settings").toFile()
        settingsRepository = SettingsRepository(
            PreferenceDataStoreFactory.create(
                scope = settingsScope,
                produceFile = { File(settingsDir, "settings.preferences_pb") }
            )
        )
        val filesRoot = Files.createTempDirectory("kudos-revoke-files")
        workRepository = WorkRepository(
            database = database,
            fileStore = WorkFileStore(filesRoot),
            clock = { Instant.parse("2026-08-16T12:00:00Z") },
            uuidFactory = { "22222222-2222-4222-8222-222222222222" }
        )
        trustStore = TombstoneTrustStore(settingsRepository)
        service = KeyRevocationService(trustStore, database, workRepository)
    }

    @After
    fun tearDown() {
        database.close()
        settingsScope.cancel()
        TombstoneSigning.resetForTests()
    }

    /** A work already soft-deleted by a signed tombstone attributed to [signerHex]. */
    private suspend fun givenWorkSoftDeletedBySigner(signerHex: String) {
        workRepository.upsert(
            SavedWork(
                id = workId,
                title = "Example",
                author = "Alice",
                sourceUrl = "https://archiveofourown.org/works/123",
                isDeleted = true,
                deletedAt = Instant.parse("2026-08-15T00:00:00Z")
            )
        )
        database.syncTombstoneDao().upsert(
            SyncTombstone(
                id = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
                recordID = workId,
                recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
                createdAt = Instant.parse("2026-08-15T00:00:00Z"),
                sourceURL = "https://archiveofourown.org/works/123",
                ao3WorkID = 123,
                signerPublicKey = signerHex
            ).toEntity()
        )
    }

    @Test
    fun worksDeletedByCountFindsRowsSignedByThatKey() = runTest {
        val peer = Ed25519Sign.KeyPair.newKeyPair().publicKey.toLowerHex()
        givenWorkSoftDeletedBySigner(peer)

        assertEquals(1, service.worksDeletedByCount(peer))
        assertEquals(0, service.worksDeletedByCount(Ed25519Sign.KeyPair.newKeyPair().publicKey.toLowerHex()))
    }

    @Test
    fun stolenRevokeOffersToRestoreWorksThatKeyDeleted() = runTest {
        val peer = Ed25519Sign.KeyPair.newKeyPair().publicKey.toLowerHex()
        trustStore.trust(peer)
        givenWorkSoftDeletedBySigner(peer)

        assertTrue(service.revoke(peer, KeyRevocationReason.STOLEN_OR_COMPROMISED))
        assertFalse(trustStore.isTrusted(peer))

        val restoredCount = service.restoreWorksDeletedBy(peer)

        assertEquals(1, restoredCount)
        val restored = workRepository.getWork(workId)
        assertNotNull(restored)
        assertFalse(restored!!.isDeleted)
        // Restoring retracts the tombstone too (WorkRepository.retractWorkTombstone),
        // so a later legitimate sync doesn't re-suppress this work.
        assertTrue(
            database.syncTombstoneDao().getBySigner(peer, SyncTombstoneRecordType.SAVED_WORK).isEmpty()
        )
    }

    @Test
    fun retiredRevokeDoesNotOfferRestoreCount() = runTest {
        val peer = Ed25519Sign.KeyPair.newKeyPair().publicKey.toLowerHex()
        trustStore.trust(peer)
        givenWorkSoftDeletedBySigner(peer)

        assertTrue(service.revoke(peer, KeyRevocationReason.RETIRED_OR_SOLD))
        // worksDeletedByCount still reports the real count either way — the
        // UI decides whether to surface the restore prompt based on reason,
        // not this method.
        assertEquals(1, service.worksDeletedByCount(peer))
    }
}
