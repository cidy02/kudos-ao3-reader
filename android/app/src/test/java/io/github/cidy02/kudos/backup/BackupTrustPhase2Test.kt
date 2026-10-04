package io.github.cidy02.kudos.backup

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.google.crypto.tink.subtle.Ed25519Sign
import io.github.cidy02.kudos.core.model.SavedSearch
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

    // --- Keysync v1 pairing UI: count-only unknown-signer badge (D9b) ---

    @Test
    fun importPackageRecordsUnknownSignerTombstoneIdForTheCountOnlyBadge() = runTest {
        val peer = Ed25519Sign.KeyPair.newKeyPair()
        val pub = peer.publicKey.toLowerHex()

        backupRepository.importPackage(
            packageWithSignedTombstone(peer.privateKey, pub, workId = WORK_K, ao3WorkId = 4242)
        )

        val pending = settingsRepository.unknownSignerTombstoneIdsSnapshot()
        assertEquals(1, pending.size)
        assertTrue(pending.contains(BackupPaths.normalizeIdForComparison(TOMBSTONE_ID)))
        assertEquals(1, TombstoneTrustStore(settingsRepository).unknownSignerCount())
    }

    @Test
    fun importPackageClearsUnknownSignerIdOnceSignerBecomesTrusted() = runTest {
        val peer = Ed25519Sign.KeyPair.newKeyPair()
        val pub = peer.publicKey.toLowerHex()

        backupRepository.importPackage(
            packageWithSignedTombstone(peer.privateKey, pub, workId = WORK_K, ao3WorkId = 4242)
        )
        assertEquals(1, settingsRepository.unknownSignerTombstoneIdsSnapshot().size)

        TombstoneTrustStore(settingsRepository).trust(pub)
        // Re-syncing the same tombstone now adopts it — the badge self-heals.
        backupRepository.importPackage(
            packageWithSignedTombstone(peer.privateKey, pub, workId = WORK_K, ao3WorkId = 4242)
        )

        assertTrue(settingsRepository.unknownSignerTombstoneIdsSnapshot().isEmpty())
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
    fun importPackageMergeDoesNotResurrectBookmarkOrSavedSearchSuppressedByIncomingTrustedTombstone() =
        runTest {
            val peer = Ed25519Sign.KeyPair.newKeyPair()
            val pub = peer.publicKey.toLowerHex()
            TombstoneTrustStore(settingsRepository).trust(pub)

            val bookmarkId = "77777777-7777-4777-8777-777777777777"
            val searchId = "55555555-5555-4555-8555-555555555555"
            val bookmarkTomb = signedTypedTombstone(
                recordId = bookmarkId,
                recordType = SyncTombstoneRecordType.BOOKMARK,
                privateKey = peer.privateKey,
                publicKeyHex = pub,
                tombstoneId = "aaaa1111-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
            )
            val searchTomb = signedTypedTombstone(
                recordId = searchId,
                recordType = SyncTombstoneRecordType.SAVED_SEARCH,
                privateKey = peer.privateKey,
                publicKeyHex = pub,
                tombstoneId = "bbbb2222-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
            )

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
                        bookmarks = listOf(
                            BackupBookmark(
                                title = "Peer deleted",
                                urlString = "https://example.com/deleted",
                                dateAdded = "2026-01-01T00:00:00Z",
                                id = bookmarkId
                            )
                        ),
                        savedSearches = listOf(
                            BackupSavedSearch(
                                id = searchId,
                                name = "Peer deleted search",
                                dateAdded = "2026-01-01T00:00:00Z"
                            )
                        ),
                        tombstones = listOf(bookmarkTomb, searchTomb),
                        settings = BackupSettingsPayload()
                    )
                ),
                BackupImportMode.MERGE
            )

            assertTrue(database.bookmarkDao().getAll().none { it.id == bookmarkId })
            assertNull(database.savedSearchDao().getById(searchId))
            val stored = database.syncTombstoneDao().getAll()
            assertTrue(
                stored.any {
                    it.recordTypeRaw == SyncTombstoneRecordType.BOOKMARK &&
                        it.recordID == bookmarkId
                }
            )
            assertTrue(
                stored.any {
                    it.recordTypeRaw == SyncTombstoneRecordType.SAVED_SEARCH &&
                        it.recordID == searchId
                }
            )
        }

    // iOS `NewestTombstoneWinsTests`: a record deleted twice stays deleted for as long as the
    // later deletion says.

    @Test
    fun aSnapshotBetweenTheTwoDeletionsCannotResurrectTheWork() = runTest {
        val (key, pub) = trustedPeer()
        seedOwnWorkTombstone(at = EARLIER)
        // The peer's later deletion of the same work arrives under a row id of its own.
        importTombstone(peerWorkTombstone(at = LATER, rowId = PEER_ROW, key = key, pub = pub))

        // A snapshot from between the two deletions still lists the work.
        backupRepository.importPackage(
            KudosBackupPackage(
                manifest = KudosBackupManifest(
                    version = BackupVersion.CURRENT,
                    exportedAt = BETWEEN,
                    exportedBy = BackupExportedBy(
                        platform = "ios",
                        appVersion = "test",
                        schemaVersion = BackupVersion.CURRENT
                    ),
                    works = listOf(
                        BackupWork(
                            id = WORK_K,
                            title = "Deleted twice",
                            author = "Author",
                            sourceURL = "https://archiveofourown.org/works/4242",
                            dateAdded = EARLIER,
                            isSaved = true,
                            hasEPUB = false,
                            lastModifiedAt = BETWEEN,
                            ao3WorkID = 4242
                        )
                    ),
                    settings = BackupSettingsPayload()
                )
            )
        )

        assertNull(database.workDao().getById(WORK_K))
    }

    @Test
    fun aLaterDeletionOfTheSameRecordReplacesTheEarlierRow() = runTest {
        // The same row id: what iOS publishes after it has taken the later deletion into its row.
        val (key, pub) = trustedPeer()
        seedOwnWorkTombstone(at = EARLIER)

        importTombstone(peerWorkTombstone(at = LATER, rowId = TOMBSTONE_ID, key = key, pub = pub))

        val stored = database.syncTombstoneDao().getAll().single()
        assertEquals(Instant.parse(LATER), stored.lastModifiedAt)
        assertEquals(pub, stored.signerPublicKey)
    }

    @Test
    fun aLaterSameRowCannotChangeTheSignedWorkIdentity() = runTest {
        val (key, pub) = trustedPeer()
        seedOwnWorkTombstone(at = EARLIER)
        val changedIdentity = TombstoneSigning.signWithRawKey(
            SyncTombstone(
                id = TOMBSTONE_ID,
                recordID = WORK_K,
                recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
                createdAt = Instant.parse(LATER),
                lastModifiedAt = Instant.parse(LATER),
                ao3WorkID = 9999,
                sourceURL = "https://archiveofourown.org/works/9999"
            ), key, pub
        ).toBackupTombstone()
        importTombstone(changedIdentity)
        val held = database.syncTombstoneDao().getAll().single()
        assertEquals(4242, held.ao3WorkID)
        assertEquals("https://archiveofourown.org/works/4242", held.sourceURL)
        assertEquals(Instant.parse(EARLIER), held.lastModifiedAt)
    }

    @Test
    fun anOlderIncomingTombstoneLeavesTheLaterOneAlone() = runTest {
        val (key, pub) = trustedPeer()
        seedOwnWorkTombstone(at = LATER)

        importTombstone(peerWorkTombstone(at = EARLIER, rowId = TOMBSTONE_ID, key = key, pub = pub))

        // Still this device's own, later row: the import signs it with this device's key.
        val stored = database.syncTombstoneDao().getAll().single()
        assertEquals(Instant.parse(LATER), stored.lastModifiedAt)
        assertFalse(stored.signerPublicKey == pub)
    }

    private suspend fun trustedPeer(): Pair<ByteArray, String> {
        val peer = Ed25519Sign.KeyPair.newKeyPair()
        val pub = peer.publicKey.toLowerHex()
        TombstoneTrustStore(settingsRepository).trust(pub)
        return peer.privateKey to pub
    }

    /** This device's own deletion of [WORK_K], under [TOMBSTONE_ID]. */
    private suspend fun seedOwnWorkTombstone(at: String) {
        database.syncTombstoneDao().upsert(
            SyncTombstone(
                id = TOMBSTONE_ID,
                recordID = WORK_K,
                recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
                createdAt = Instant.parse(at),
                lastModifiedAt = Instant.parse(at),
                sourceURL = "https://archiveofourown.org/works/4242",
                ao3WorkID = 4242,
                deletionReason = "workDeleted"
            ).toEntity()
        )
    }

    private fun peerWorkTombstone(at: String, rowId: String, key: ByteArray, pub: String): BackupTombstone {
        val unsigned = BackupTombstone(
            id = rowId,
            recordID = WORK_K,
            recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
            createdAt = at,
            lastModifiedAt = at,
            sourceURL = "https://archiveofourown.org/works/4242",
            ao3WorkID = 4242
        )
        val signed = TombstoneSigning.signWithRawKey(
            unsigned.copy(signerPublicKey = pub).toSyncTombstone(),
            key,
            pub
        )
        return unsigned.copy(signerPublicKey = signed.signerPublicKey, signature = signed.signature)
    }

    private suspend fun importTombstone(tombstone: BackupTombstone) {
        backupRepository.importPackage(
            KudosBackupPackage(
                manifest = KudosBackupManifest(
                    version = BackupVersion.CURRENT,
                    exportedAt = "2026-06-26T12:00:00Z",
                    exportedBy = BackupExportedBy(
                        platform = "ios",
                        appVersion = "test",
                        schemaVersion = BackupVersion.CURRENT
                    ),
                    tombstones = listOf(tombstone),
                    settings = BackupSettingsPayload()
                )
            )
        )
    }

    // iOS `TombstoneSweepsExistingRecordsTests`: a deletion has to remove the copy a device
    // still holds, or the two devices disagree for ever.

    @Test
    fun aTrustedTombstoneRemovesASearchThisDeviceStillHas() = runTest {
        // The peer's snapshot does not list the search (it deleted it) and carries the tombstone.
        mergePeerSearchDeletion(localSearchAddedAt = "2025-06-01T00:00:00Z")

        assertNull(database.savedSearchDao().getById(SWEPT_SEARCH))
    }

    @Test
    fun aSearchMadeAfterTheDeletionSurvives() = runTest {
        // Newer than the tombstone: a search the reader made since, which it must not eat.
        mergePeerSearchDeletion(localSearchAddedAt = "2026-03-01T00:00:00Z")

        assertNotNull(database.savedSearchDao().getById(SWEPT_SEARCH))
    }

    @Test
    fun aSearchCreatedAfterSnapshotCaptureSurvivesTheApply() = runTest {
        val captured = SavedSearch(id = SWEPT_SEARCH, name = "Deleted search", dateAdded = Instant.parse(EARLIER))
        database.savedSearchDao().upsert(captured.toEntity())
        val snapshot = backupRepository.captureLibrarySnapshot().copy(
            tombstones = listOf(SyncTombstone(
                id = TOMBSTONE_ID,
                recordID = SWEPT_SEARCH,
                recordTypeRaw = SyncTombstoneRecordType.SAVED_SEARCH,
                createdAt = Instant.parse(LATER),
                lastModifiedAt = Instant.parse(LATER)
            ))
        )
        val merge = BackupMergeService.merge(snapshot, KudosBackupPackage(KudosBackupManifest(
            version = BackupVersion.CURRENT, exportedAt = "2026-06-26T12:00:00Z"
        )))
        val late = SavedSearch(id = PEER_ROW, name = "Saved while merging", dateAdded = CLOCK)
        database.savedSearchDao().upsert(late.toEntity())
        backupRepository.applyMergeResult(merge)
        assertNull(database.savedSearchDao().getById(SWEPT_SEARCH))
        assertEquals(late, database.savedSearchDao().getById(PEER_ROW)?.toDomain())
    }

    @Test
    fun replaceLibraryDoesNotSweepExistingSearches() = runTest {
        // The archive holds the search and a tombstone for it. Replace bypasses tombstones, or
        // a repeated identical replace deletes what the first one put back.
        mergePeerSearchDeletion(
            localSearchAddedAt = "2025-06-01T00:00:00Z",
            mode = BackupImportMode.REPLACE_LIBRARY,
            archivedSearches = listOf(
                BackupSavedSearch(id = SWEPT_SEARCH, name = "Shared search", dateAdded = "2025-06-01T00:00:00Z")
            )
        )

        assertNotNull(database.savedSearchDao().getById(SWEPT_SEARCH))
    }

    /** A local search, then a trusted peer's snapshot carrying a tombstone for it (2026-01-01). */
    private suspend fun mergePeerSearchDeletion(
        localSearchAddedAt: String,
        mode: BackupImportMode = BackupImportMode.MERGE,
        archivedSearches: List<BackupSavedSearch> = emptyList()
    ) {
        val peer = Ed25519Sign.KeyPair.newKeyPair()
        val pub = peer.publicKey.toLowerHex()
        TombstoneTrustStore(settingsRepository).trust(pub)
        database.savedSearchDao().upsert(
            SavedSearch(
                id = SWEPT_SEARCH,
                name = "Shared search",
                dateAdded = Instant.parse(localSearchAddedAt)
            ).toEntity()
        )
        backupRepository.importPackage(
            KudosBackupPackage(
                manifest = KudosBackupManifest(
                    version = BackupVersion.CURRENT,
                    exportedAt = "2026-06-26T12:00:00Z",
                    exportedBy = BackupExportedBy(
                        platform = "ios",
                        appVersion = "test",
                        schemaVersion = BackupVersion.CURRENT
                    ),
                    savedSearches = archivedSearches,
                    tombstones = listOf(
                        signedTypedTombstone(
                            recordId = SWEPT_SEARCH,
                            recordType = SyncTombstoneRecordType.SAVED_SEARCH,
                            privateKey = peer.privateKey,
                            publicKeyHex = pub,
                            tombstoneId = "cccc3333-cccc-4ccc-8ccc-cccccccccccc"
                        )
                    ),
                    settings = BackupSettingsPayload()
                )
            ),
            mode
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

    private fun signedTypedTombstone(
        recordId: String,
        recordType: String,
        privateKey: ByteArray,
        publicKeyHex: String,
        tombstoneId: String
    ): BackupTombstone {
        val created = "2026-01-01T00:00:00Z"
        val unsigned = BackupTombstone(
            id = tombstoneId,
            recordID = recordId,
            recordTypeRaw = recordType,
            createdAt = created,
            lastModifiedAt = created
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
        private const val SWEPT_SEARCH = "66666666-6666-4666-8666-666666666666"
        private const val PEER_ROW = "44444444-4444-4444-8444-444444444444"
        private const val EARLIER = "2026-01-01T00:00:00Z"
        private const val BETWEEN = "2026-02-01T00:00:00Z"
        private const val LATER = "2026-03-01T00:00:00Z"
        private const val TOMBSTONE_ID = "33333333-3333-4333-8333-333333333333"
    }
}
