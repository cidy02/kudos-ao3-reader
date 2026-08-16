package io.github.cidy02.kudos.backup

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.google.crypto.tink.subtle.Ed25519Sign
import io.github.cidy02.kudos.core.model.SyncTombstone
import io.github.cidy02.kudos.core.model.SyncTombstoneRecordType
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.toDomain
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.FontFileStore
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
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Production-entry Phase 2 coverage: [BackupRepository.importPackage] and
 * identity-aware [WorkRepository.retractWorkTombstone].
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class BackupTrustPhase2Test {
    private lateinit var context: Context
    private lateinit var database: KudosDatabase
    private lateinit var settingsScope: CoroutineScope
    private lateinit var settingsRepository: SettingsRepository
    private lateinit var workFileStore: WorkFileStore
    private lateinit var backupRepository: BackupRepository
    private lateinit var workRepository: WorkRepository

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        settingsScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val settingsDir = Files.createTempDirectory("kudos-p2-settings").toFile()
        settingsRepository = SettingsRepository(
            PreferenceDataStoreFactory.create(
                scope = settingsScope,
                produceFile = { File(settingsDir, "settings.preferences_pb") }
            )
        )
        val filesRoot = Files.createTempDirectory("kudos-p2-files")
        workFileStore = WorkFileStore(filesRoot)
        backupRepository = BackupRepository(
            database = database,
            workFileStore = workFileStore,
            fontFileStore = FontFileStore(filesRoot),
            settingsRepository = settingsRepository,
            persistenceGate = PersistenceGate(),
            clock = { CLOCK },
            uuidFactory = { "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb" },
            appVersion = "test"
        )
        workRepository = WorkRepository(
            database = database,
            fileStore = workFileStore,
            clock = { CLOCK },
            uuidFactory = { "22222222-2222-4222-8222-222222222222" }
        )
    }

    @After
    fun tearDown() {
        database.close()
        settingsScope.cancel()
        TombstoneSigning.resetForTests()
    }

    @Test
    fun importPackageAdoptsTrustedSignedTombstoneAndSuppressesWork() = runTest {
        val peer = Ed25519Sign.KeyPair.newKeyPair()
        val pub = peer.publicKey.toLowerHex()
        TombstoneTrustStore(settingsRepository).trust(pub)

        val summary = backupRepository.importPackage(
            packageWithSignedTombstone(peer.privateKey, pub, workId = WORK_K, ao3WorkId = 4242)
        )

        assertEquals(0, summary.worksCreated)
        assertEquals(1, summary.worksSuppressed)
        assertNull(database.workDao().getById(WORK_K))
        val stored = database.syncTombstoneDao().getAll()
        assertEquals(1, stored.size)
        assertEquals(pub, stored.single().signerPublicKey)
        assertTrue(stored.single().signature.isNotEmpty())
    }

    @Test
    fun importPackageDropsUntrustedValidSignature() = runTest {
        val peer = Ed25519Sign.KeyPair.newKeyPair()
        val pub = peer.publicKey.toLowerHex()

        val summary = backupRepository.importPackage(
            packageWithSignedTombstone(peer.privateKey, pub, workId = WORK_K, ao3WorkId = 4242)
        )

        assertEquals(1, summary.worksCreated)
        assertEquals(0, summary.worksSuppressed)
        assertNotNull(database.workDao().getById(WORK_K))
        assertTrue(database.syncTombstoneDao().getAll().isEmpty())
        assertFalse(TombstoneTrustStore(settingsRepository).isTrusted(pub))
        assertTrue(settingsRepository.trustedTombstonePublicKeysSnapshot().isEmpty())
    }

    @Test
    fun importPackageDropsForgedSignature() = runTest {
        val peer = Ed25519Sign.KeyPair.newKeyPair()
        val pub = peer.publicKey.toLowerHex()
        TombstoneTrustStore(settingsRepository).trust(pub)
        val valid = signedBackupTombstoneFor(
            recordId = WORK_K,
            ao3WorkId = 4242,
            privateKey = peer.privateKey,
            publicKeyHex = pub
        )
        val forged = valid.copy(
            signature = valid.signature.dropLast(1) + if (valid.signature.last() == '0') '1' else '0'
        )

        val summary = backupRepository.importPackage(
            packageWithWorkAndTombstone(WORK_K, "Should still insert", forged)
        )

        assertEquals(1, summary.worksCreated)
        assertEquals(0, summary.worksSuppressed)
        assertNotNull(database.workDao().getById(WORK_K))
        assertTrue(database.syncTombstoneDao().getAll().isEmpty())
    }

    @Test
    fun importPackageDoesNotAddIncomingSignerToTrustStore() = runTest {
        val peer = Ed25519Sign.KeyPair.newKeyPair()
        val pub = peer.publicKey.toLowerHex()
        assertTrue(settingsRepository.trustedTombstonePublicKeysSnapshot().isEmpty())

        backupRepository.importPackage(
            packageWithSignedTombstone(peer.privateKey, pub, workId = WORK_K, ao3WorkId = 4242)
        )

        assertTrue(
            "file import must not write the trust store",
            settingsRepository.trustedTombstonePublicKeysSnapshot().isEmpty()
        )
        assertFalse(TombstoneTrustStore(settingsRepository).isTrusted(pub))
    }

    @Test
    fun importPackageReSignsLocalUnsignedTombstonesOnce() = runTest {
        database.syncTombstoneDao().upsert(
            SyncTombstone(
                id = TOMBSTONE_ID,
                recordID = WORK_K,
                recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
                createdAt = CLOCK,
                lastModifiedAt = CLOCK,
                sourceURL = "https://archiveofourown.org/works/4242",
                ao3WorkID = 4242,
                deletionReason = "workDeleted"
            ).toEntity()
        )
        assertTrue(database.syncTombstoneDao().getAll().single().signature.isEmpty())

        backupRepository.importPackage(
            packageWithWorkAndTombstone(
                workId = WORK_K,
                title = "Should stay suppressed",
                tombstone = BackupTombstone(
                    id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                    recordID = "ffffffff-ffff-4fff-8fff-ffffffffffff",
                    recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
                    createdAt = "2026-01-01T00:00:00Z",
                    lastModifiedAt = "2026-01-01T00:00:00Z"
                )
            )
        )

        val local = database.syncTombstoneDao().getAll().single { it.id == TOMBSTONE_ID }
        assertTrue(local.signerPublicKey.isNotEmpty())
        assertTrue(local.signature.isNotEmpty())
        assertTrue(TombstoneSigning.verify(local.toDomain()))
        assertTrue(settingsRepository.isTombstoneMigrationComplete())
        assertTrue(database.syncTombstoneDao().getAll().none { it.id == "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" })
    }

    @Test
    fun importPackagePinsAdoptedTombstoneLastModifiedAtToSignedCreatedAt() = runTest {
        val peer = Ed25519Sign.KeyPair.newKeyPair()
        val pub = peer.publicKey.toLowerHex()
        TombstoneTrustStore(settingsRepository).trust(pub)

        val created = "2026-01-01T00:00:00Z"
        val forgedLastModified = "2099-01-01T00:00:00Z"
        val signed = signedBackupTombstoneFor(
            recordId = WORK_K,
            ao3WorkId = 4242,
            privateKey = peer.privateKey,
            publicKeyHex = pub
        ).copy(lastModifiedAt = forgedLastModified)

        backupRepository.importPackage(
            KudosBackupPackage(
                manifest = KudosBackupManifest(
                    version = BackupVersion.CURRENT,
                    exportedAt = "2026-06-26T12:00:00Z",
                    exportedBy = BackupExportedBy(
                        platform = "android",
                        appVersion = "test",
                        schemaVersion = BackupVersion.CURRENT
                    ),
                    tombstones = listOf(signed),
                    settings = BackupSettingsPayload()
                )
            )
        )

        val stored = database.syncTombstoneDao().getAll().single()
        assertEquals(
            "Adopted lastModifiedAt must be pinned to the signed createdAt",
            Instant.parse(created),
            stored.lastModifiedAt
        )
        assertEquals(Instant.parse(created), stored.createdAt)

        val later = backupRepository.importPackage(
            packageWithWorkAndTombstone(
                workId = WORK_K,
                title = "Re-saved after delete",
                tombstone = BackupTombstone(
                    id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                    recordID = WORK_K,
                    recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
                    createdAt = created,
                    lastModifiedAt = "2026-03-01T00:00:00Z",
                    sourceURL = "https://archiveofourown.org/works/4242",
                    ao3WorkID = 4242
                )
            ).let { pack ->
                pack.copy(
                    manifest = pack.manifest.copy(
                        works = pack.manifest.works.map {
                            it.copy(lastModifiedAt = "2026-03-01T00:00:00Z")
                        },
                        tombstones = emptyList()
                    )
                )
            }
        )

        assertEquals(
            "Forged unsigned lastModifiedAt must not permanently suppress a later snapshot",
            0,
            later.worksSuppressed
        )
        assertEquals(1, later.worksCreated)
        assertNotNull(database.workDao().getById(WORK_K))
    }

    @Test
    fun replaceLibraryLoadsWorkEvenWhenFileCarriesTrustedTombstoneForIt() = runTest {
        val peer = Ed25519Sign.KeyPair.newKeyPair()
        val pub = peer.publicKey.toLowerHex()
        TombstoneTrustStore(settingsRepository).trust(pub)

        val summary = backupRepository.importPackage(
            packageWithSignedTombstone(peer.privateKey, pub, workId = WORK_K, ao3WorkId = 4242),
            BackupImportMode.REPLACE_LIBRARY
        )

        assertEquals(
            "Replace must ignore suppressors so a work present in the snapshot loads",
            0,
            summary.worksSuppressed
        )
        assertEquals(1, summary.worksCreated)
        assertNotNull(
            "Replace snapshot work must be present even when the file also carries a trusted tombstone for it",
            database.workDao().getById(WORK_K)
        )
    }

    @Test
    fun importPackageDoesNotOverwriteLocalTombstoneRowByUnsignedId() = runTest {
        val peer = Ed25519Sign.KeyPair.newKeyPair()
        val pub = peer.publicKey.toLowerHex()
        TombstoneTrustStore(settingsRepository).trust(pub)

        val localRecord = WORK_K
        database.syncTombstoneDao().upsert(
            SyncTombstone(
                id = TOMBSTONE_ID,
                recordID = localRecord,
                recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
                createdAt = CLOCK,
                lastModifiedAt = CLOCK,
                sourceURL = "https://archiveofourown.org/works/4242",
                ao3WorkID = 4242,
                deletionReason = "workDeleted"
            ).toEntity()
        )

        val incoming = signedBackupTombstoneFor(
            recordId = "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
            ao3WorkId = 9999,
            privateKey = peer.privateKey,
            publicKeyHex = pub
        ).copy(id = TOMBSTONE_ID)

        val summary = backupRepository.importPackage(
            packageWithWorkAndTombstone(WORK_K, "Must stay suppressed", incoming).let { pack ->
                pack.copy(
                    manifest = pack.manifest.copy(
                        works = pack.manifest.works.map {
                            it.copy(
                                sourceURL = "https://archiveofourown.org/works/4242",
                                ao3WorkID = 4242,
                                lastModifiedAt = "2026-01-01T00:00:00Z"
                            )
                        }
                    )
                )
            }
        )

        val stored = database.syncTombstoneDao().getAll().single { it.id == TOMBSTONE_ID }
        assertEquals(
            "incoming signed tombstone must not overwrite a local row by unsigned id",
            localRecord,
            stored.recordID
        )
        assertEquals(4242, stored.ao3WorkID)
        assertEquals(0, summary.worksCreated)
        assertEquals(1, summary.worksSuppressed)
        assertNull(
            "local tombstone must still suppress the work it was minted for",
            database.workDao().getById(WORK_K)
        )
    }

    @Test
    fun retractWorkTombstoneMatchesAo3AndCanonicalUrl() = runTest {
        val otherRecord = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
        database.syncTombstoneDao().upsert(
            SyncTombstone(
                id = TOMBSTONE_ID,
                recordID = otherRecord,
                recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
                createdAt = CLOCK,
                lastModifiedAt = CLOCK,
                sourceURL = "https://archiveofourown.org/works/123",
                ao3WorkID = 123,
                deletionReason = "workDeleted"
            ).toEntity()
        )

        workRepository.retractWorkTombstone(
            recordId = WORK_K,
            ao3WorkId = 123,
            sourceUrl = "https://www.archiveofourown.org/works/123/chapters/9"
        )

        assertTrue(
            "retract by ao3 / canonical URL must delete the savedWork tombstone",
            database.syncTombstoneDao().getAll().isEmpty()
        )
    }

    @Test
    fun retractWorkTombstoneMatchesCanonicalUrlWhenAo3Missing() = runTest {
        database.syncTombstoneDao().upsert(
            SyncTombstone(
                id = TOMBSTONE_ID,
                recordID = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
                recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
                createdAt = CLOCK,
                lastModifiedAt = CLOCK,
                sourceURL = "https://archiveofourown.org/works/999",
                ao3WorkID = null,
                deletionReason = "workDeleted"
            ).toEntity()
        )

        workRepository.retractWorkTombstone(
            recordId = WORK_K,
            sourceUrl = "https://archiveofourown.org/works/999"
        )

        assertTrue(database.syncTombstoneDao().getAll().isEmpty())
    }

    private fun packageWithSignedTombstone(
        privateKey: ByteArray,
        publicKeyHex: String,
        workId: String,
        ao3WorkId: Int
    ): KudosBackupPackage {
        return packageWithWorkAndTombstone(
            workId,
            "Should be suppressed",
            signedBackupTombstoneFor(workId, ao3WorkId, privateKey, publicKeyHex)
        )
    }

    private fun signedBackupTombstoneFor(
        recordId: String,
        ao3WorkId: Int,
        privateKey: ByteArray,
        publicKeyHex: String
    ): BackupTombstone {
        val created = "2026-01-01T00:00:00Z"
        val unsigned = BackupTombstone(
            id = TOMBSTONE_ID,
            recordID = recordId,
            recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
            createdAt = created,
            lastModifiedAt = created,
            sourceURL = "https://archiveofourown.org/works/$ao3WorkId",
            ao3WorkID = ao3WorkId
        )
        val signed = TombstoneSigning.signWithRawKey(
            unsigned.copy(signerPublicKey = publicKeyHex).toSyncTombstone(),
            privateKey,
            publicKeyHex
        )
        return unsigned.copy(
            signerPublicKey = signed.signerPublicKey,
            signature = signed.signature
        )
    }

    private fun packageWithWorkAndTombstone(
        workId: String,
        title: String,
        tombstone: BackupTombstone
    ): KudosBackupPackage {
        val created = "2026-01-01T00:00:00Z"
        return KudosBackupPackage(
            manifest = KudosBackupManifest(
                version = BackupVersion.CURRENT,
                exportedAt = "2026-06-26T12:00:00Z",
                exportedBy = BackupExportedBy(
                    platform = "android",
                    appVersion = "test",
                    schemaVersion = BackupVersion.CURRENT
                ),
                works = listOf(
                    BackupWork(
                        id = workId,
                        title = title,
                        author = "Author",
                        sourceURL = "https://archiveofourown.org/works/${tombstone.ao3WorkID}",
                        dateAdded = created,
                        isSaved = true,
                        hasEPUB = true,
                        lastModifiedAt = created,
                        ao3WorkID = tombstone.ao3WorkID
                    )
                ),
                tombstones = listOf(tombstone),
                settings = BackupSettingsPayload()
            ),
            epubFilesByWorkId = mapOf(workId to "epub".toByteArray())
        )
    }

    companion object {
        private val CLOCK: Instant = Instant.parse("2026-06-26T12:00:00Z")
        private const val WORK_K = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        private const val TOMBSTONE_ID = "33333333-3333-4333-8333-333333333333"
    }
}
