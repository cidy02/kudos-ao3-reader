package io.github.cidy02.kudos.backup

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.google.crypto.tink.subtle.Ed25519Sign
import io.github.cidy02.kudos.core.model.Bookmark
import io.github.cidy02.kudos.core.model.CustomFont
import io.github.cidy02.kudos.core.model.ReadingAnnotation
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.ReadingQueueMembership
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.core.model.SavedSearch
import io.github.cidy02.kudos.core.model.SyncTombstone
import io.github.cidy02.kudos.core.model.SyncTombstoneRecordType
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.ReadingSessionEntity
import io.github.cidy02.kudos.data.local.entity.ReadingFavoriteEntity
import io.github.cidy02.kudos.data.local.entity.FandomReadWatermarkEntity
import io.github.cidy02.kudos.data.local.entity.toDomain
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.FontFileStore
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.works.converters.EpubBuilder
import java.io.File
import java.nio.file.Files
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertArrayEquals
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
    fun aSessionCreatedAfterSnapshotCaptureSurvivesTheApply() = runTest {
        val captured = ReadingSessionEntity(
            id = SWEPT_SEARCH, workID = WORK_K, startedAt = Instant.parse(EARLIER),
            endedAt = Instant.parse(EARLIER), lastModifiedAt = Instant.parse(EARLIER)
        )
        val changedTarget = captured.copy(id = TOMBSTONE_ID)
        database.readingLogDao().upsertSession(captured)
        database.readingLogDao().upsertSession(changedTarget)
        val snapshot = backupRepository.captureLibrarySnapshot().copy(tombstones =
            listOf(SWEPT_SEARCH, TOMBSTONE_ID).map { id -> SyncTombstone(
                id = id, recordID = id, recordTypeRaw = SyncTombstoneRecordType.READING_SESSION,
                createdAt = Instant.parse(LATER), lastModifiedAt = Instant.parse(LATER)
            ) })
        val merge = BackupMergeService.merge(snapshot, KudosBackupPackage(KudosBackupManifest(
            version = BackupVersion.CURRENT, exportedAt = "2026-06-26T12:00:00Z")))
        val late = captured.copy(id = PEER_ROW, lastModifiedAt = CLOCK)
        val changed = changedTarget.copy(lastModifiedAt = CLOCK)
        database.readingLogDao().upsertSession(late)
        database.readingLogDao().upsertSession(changed)
        backupRepository.applyMergeResult(merge)
        val held = database.readingLogDao().getAllSessions().associateBy { it.id }
        assertNull(held[SWEPT_SEARCH])
        assertEquals(late, held[PEER_ROW])
        assertEquals(changed, held[TOMBSTONE_ID])
    }

    @Test
    fun aFavoriteCreatedAfterSnapshotCaptureSurvivesTheApply() = runTest {
        val captured = ReadingFavoriteEntity(
            id = SWEPT_SEARCH, kindRaw = "fandom", targetKey = "A fandom",
            createdAt = Instant.parse(EARLIER), lastModifiedAt = Instant.parse(EARLIER)
        )
        val changedTarget = captured.copy(id = TOMBSTONE_ID)
        database.readingLogDao().upsertFavorite(captured)
        database.readingLogDao().upsertFavorite(changedTarget)
        val snapshot = backupRepository.captureLibrarySnapshot().copy(tombstones =
            listOf(SWEPT_SEARCH, TOMBSTONE_ID).map { id -> SyncTombstone(
                id = id, recordID = id, recordTypeRaw = SyncTombstoneRecordType.READING_FAVORITE,
                createdAt = Instant.parse(LATER), lastModifiedAt = Instant.parse(LATER)
            ) })
        val merge = BackupMergeService.merge(snapshot, KudosBackupPackage(KudosBackupManifest(
            version = BackupVersion.CURRENT, exportedAt = "2026-06-26T12:00:00Z")))
        val late = captured.copy(id = PEER_ROW, lastModifiedAt = CLOCK)
        val changed = changedTarget.copy(lastModifiedAt = CLOCK)
        database.readingLogDao().upsertFavorite(late)
        database.readingLogDao().upsertFavorite(changed)
        backupRepository.applyMergeResult(merge)
        val held = database.readingLogDao().getAllFavorites().associateBy { it.id }
        assertNull(held[SWEPT_SEARCH])
        assertEquals(late, held[PEER_ROW])
        assertEquals(changed, held[TOMBSTONE_ID])
    }

    @Test
    fun aWatermarkCreatedAfterSnapshotCaptureSurvivesTheApply() = runTest {
        val captured = FandomReadWatermarkEntity(
            id = SWEPT_SEARCH, fandomName = "A fandom", lastVisitedAt = Instant.parse(EARLIER),
            lastModifiedAt = Instant.parse(EARLIER)
        )
        val changedTarget = captured.copy(id = TOMBSTONE_ID)
        database.readingLogDao().upsertWatermark(captured)
        database.readingLogDao().upsertWatermark(changedTarget)
        val snapshot = backupRepository.captureLibrarySnapshot().copy(tombstones =
            listOf(SWEPT_SEARCH, TOMBSTONE_ID).map { id -> SyncTombstone(
                id = id, recordID = id, recordTypeRaw = SyncTombstoneRecordType.FANDOM_READ_WATERMARK,
                createdAt = Instant.parse(LATER), lastModifiedAt = Instant.parse(LATER)
            ) })
        val merge = BackupMergeService.merge(snapshot, KudosBackupPackage(KudosBackupManifest(
            version = BackupVersion.CURRENT, exportedAt = "2026-06-26T12:00:00Z")))
        val late = captured.copy(id = PEER_ROW, lastModifiedAt = CLOCK)
        val changed = changedTarget.copy(lastModifiedAt = CLOCK)
        database.readingLogDao().upsertWatermark(late)
        database.readingLogDao().upsertWatermark(changed)
        backupRepository.applyMergeResult(merge)
        val held = database.readingLogDao().getAllWatermarks().associateBy { it.id }
        assertNull(held[SWEPT_SEARCH])
        assertEquals(late, held[PEER_ROW])
        assertEquals(changed, held[TOMBSTONE_ID])
    }

    @Test
    fun aWorkCreatedAfterCaptureSurvivesReplaceWhileAnOmittedCapturedWorkIsRecoverable() = runTest {
        val captured = SavedWork(id = WORK_K, title = "Omitted", author = "Author", dateAdded = CLOCK, hasEpub = false)
        database.workDao().upsert(captured.toEntity())
        val merge = capturedReplace()
        val late = captured.copy(id = PEER_ROW, title = "Made while merging")
        database.workDao().upsert(late.toEntity())
        backupRepository.applyMergeResult(merge)
        assertEquals(late, database.workDao().getById(late.id)?.toDomain())
        val removed = database.workDao().getById(captured.id)!!
        assertTrue(removed.isDeleted)
        assertEquals(CLOCK, removed.deletedAt)
        assertEquals(CLOCK.plus(WorkRepository.RECOVERY_WINDOW), removed.permanentDeletionScheduledAt)
    }

    @Test
    fun aBookmarkCreatedOrChangedAfterCaptureSurvivesReplace() = runTest {
        val captured = Bookmark(id = SWEPT_SEARCH, title = "Omitted", urlString = "https://example.org/one", dateAdded = CLOCK)
        val changedTarget = captured.copy(id = TOMBSTONE_ID, urlString = "https://example.org/two")
        database.bookmarkDao().upsert(captured.toEntity())
        database.bookmarkDao().upsert(changedTarget.toEntity())
        val merge = capturedReplace()
        val late = captured.copy(id = PEER_ROW, urlString = "https://example.org/late")
        val changed = changedTarget.copy(title = "Edited while merging")
        database.bookmarkDao().upsert(late.toEntity())
        database.bookmarkDao().upsert(changed.toEntity())
        backupRepository.applyMergeResult(merge)
        assertNull(database.bookmarkDao().getById(captured.id))
        assertEquals(late, database.bookmarkDao().getById(late.id)?.toDomain())
        assertEquals(changed, database.bookmarkDao().getById(changed.id)?.toDomain())
        assertOnlyUneditedOmissionIsStored(merge, SyncTombstoneRecordType.BOOKMARK, captured.id, changed.id)
        reconcileEmptyArchive()
        assertEquals(changed, database.bookmarkDao().getById(changed.id)?.toDomain())
        assertNull(database.bookmarkDao().getById(captured.id))
    }

    @Test
    fun aSearchCreatedOrChangedAfterCaptureSurvivesReplace() = runTest {
        val captured = SavedSearch(id = SWEPT_SEARCH, name = "Omitted", dateAdded = CLOCK)
        val changedTarget = captured.copy(id = TOMBSTONE_ID)
        database.savedSearchDao().upsert(captured.toEntity())
        database.savedSearchDao().upsert(changedTarget.toEntity())
        val merge = capturedReplace()
        val late = captured.copy(id = PEER_ROW, name = "Made while merging")
        val changed = changedTarget.copy(name = "Edited while merging", filtersJson = "{\"query\":\"new\"}")
        database.savedSearchDao().upsert(late.toEntity())
        database.savedSearchDao().upsert(changed.toEntity())
        backupRepository.applyMergeResult(merge)
        assertNull(database.savedSearchDao().getById(captured.id))
        assertEquals(late, database.savedSearchDao().getById(late.id)?.toDomain())
        assertEquals(changed, database.savedSearchDao().getById(changed.id)?.toDomain())
        assertOnlyUneditedOmissionIsStored(merge, SyncTombstoneRecordType.SAVED_SEARCH, captured.id, changed.id)
        reconcileEmptyArchive()
        assertEquals(changed, database.savedSearchDao().getById(changed.id)?.toDomain())
        assertNull(database.savedSearchDao().getById(captured.id))
    }

    @Test
    fun aCollectionCreatedAfterCaptureSurvivesReplaceWhileAnOmittedCapturedCollectionIsRecoverable() = runTest {
        val captured = WorkCollection(id = SWEPT_SEARCH, name = "Omitted", dateAdded = CLOCK)
        database.collectionDao().upsert(captured.toEntity())
        val merge = capturedReplace()
        val late = captured.copy(id = PEER_ROW, name = "Made while merging")
        database.collectionDao().upsert(late.toEntity())
        backupRepository.applyMergeResult(merge)
        assertEquals(late.toEntity(), database.collectionDao().getById(late.id))
        val removed = database.collectionDao().getById(captured.id)!!
        assertTrue(removed.isDeleted)
        assertEquals(CLOCK, removed.deletedAt)
        assertEquals(CLOCK.plus(WorkRepository.RECOVERY_WINDOW), removed.permanentDeletionScheduledAt)
    }

    @Test
    fun aCustomQueueCreatedAfterCaptureSurvivesReplaceWhileAnOmittedCapturedQueueIsRecoverable() = runTest {
        val captured = ReadingQueue(id = SWEPT_SEARCH, name = "Omitted", dateCreated = CLOCK)
        database.readingQueueDao().upsertQueue(captured.toEntity())
        val merge = capturedReplace()
        val late = captured.copy(id = PEER_ROW, name = "Made while merging")
        database.readingQueueDao().upsertQueue(late.toEntity())
        backupRepository.applyMergeResult(merge)
        assertEquals(late.toEntity(), database.readingQueueDao().getQueueById(late.id))
        val removed = database.readingQueueDao().getQueueById(captured.id)!!
        assertTrue(removed.isDeleted)
        assertEquals(CLOCK, removed.deletedAt)
        assertEquals(CLOCK.plus(WorkRepository.RECOVERY_WINDOW), removed.permanentDeletionScheduledAt)
    }

    @Test
    fun anAnnotationCreatedAfterCaptureSurvivesReplaceWhileAnOmittedCapturedAnnotationIsMarked() = runTest {
        database.workDao().upsert(SavedWork(id = WORK_K, title = "Work", author = "Author", hasEpub = false).toEntity())
        val captured = ReadingAnnotation(id = SWEPT_SEARCH, workID = WORK_K, kindRaw = "highlight", createdAt = CLOCK)
        database.annotationDao().upsert(captured.toEntity())
        val merge = capturedReplace()
        val late = captured.copy(id = PEER_ROW, kindRaw = "note", note = "Made while merging")
        database.annotationDao().upsert(late.toEntity())
        backupRepository.applyMergeResult(merge)
        assertEquals(late.toEntity(), database.annotationDao().getById(late.id))
        assertEquals(captured.copy(isPendingDeletion = true, deletedAt = CLOCK).toEntity(),
            database.annotationDao().getById(captured.id))
    }

    @Test
    fun aWorkPreservedBetweenMergeAndApplyKeepsItsBytes() = runTest {
        // Replace's forced archive preference must also yield to a new reader edit.
        for (mode in listOf(BackupImportMode.RECONCILE, BackupImportMode.REPLACE_LIBRARY)) {
            seedAssetWork()
            val merge = plannedAssetMerge(mode)
            val held = database.workDao().getById(WORK_K)!!
            database.workDao().upsert(held.copy(epubPreservationStatusRaw = "preserved",
                preservedAt = CLOCK.minusSeconds(10), lastModifiedAt = CLOCK.minusSeconds(10)))

            val summary = backupRepository.applyMergeResult(merge)

            assertArrayEquals(LOCAL_EPUB, Files.readAllBytes(workFileStore.workEpubPath(WORK_K)))
            assertTrue(database.workDao().getById(WORK_K)!!.hasEpub)
            assertFalse(database.workDao().getById(WORK_K)!!.remoteEpubPending)
            assertEquals(1, summary.concurrentRowsDeferred)
            assertTrue(summary.toUserMessage().contains("import again to take the backup's"))
        }
    }

    @Test
    fun aDownloadRemovedBetweenMergeAndApplyStaysRemovedAndIsStillOwed() = runTest {
        for (mode in listOf(BackupImportMode.RECONCILE, BackupImportMode.REPLACE_LIBRARY)) {
            seedAssetWork()
            val merge = plannedAssetMerge(mode)
            workRepository.deleteLocalEpub(WORK_K)

            val summary = backupRepository.applyMergeResult(merge)

            assertFalse(workFileStore.workEpubExists(WORK_K))
            val held = database.workDao().getById(WORK_K)!!
            assertFalse(held.hasEpub)
            assertTrue(held.remoteEpubPending)
            assertTrue(held.toDomain().toBackupWork().hasEPUB)
            assertEquals(1, summary.concurrentRowsDeferred)
        }
    }

    @Test
    fun aWorkDeletedBetweenMergeAndApplyGetsNeitherEpubNorOriginalNorRecord() = runTest {
        for (mode in listOf(BackupImportMode.RECONCILE, BackupImportMode.REPLACE_LIBRARY)) {
            seedAssetWork()
            val merge = plannedAssetMerge(mode)
            workRepository.hardDelete(WORK_K)

            val summary = backupRepository.applyMergeResult(merge, incomingOriginals())

            assertNull(database.workDao().getById(WORK_K))
            assertFalse(workFileStore.workEpubExists(WORK_K))
            assertNull(workFileStore.originalFile(WORK_K))
            assertFalse(workFileStore.conversionRecordExists(WORK_K))
            assertTrue(summary.concurrentRowsDeferred > 0)
        }
    }

    @Test
    fun aWorkSoftDeletedBetweenMergeAndApplyKeepsItsOldBytesAndGetsNoOriginal() = runTest {
        seedAssetWork()
        val merge = plannedAssetMerge(BackupImportMode.RECONCILE)
        workRepository.softDelete(WORK_K)

        backupRepository.applyMergeResult(merge, incomingOriginals())

        assertTrue(database.workDao().getById(WORK_K)!!.isDeleted)
        assertArrayEquals(LOCAL_EPUB, Files.readAllBytes(workFileStore.workEpubPath(WORK_K)))
        assertNull(workFileStore.originalFile(WORK_K))
        assertFalse(workFileStore.conversionRecordExists(WORK_K))
    }

    @Test
    fun anUntouchedWorkStillReceivesItsPlannedBytesAndOriginalRecord() = runTest {
        for (mode in listOf(BackupImportMode.RECONCILE, BackupImportMode.REPLACE_LIBRARY, BackupImportMode.MERGE)) {
            // File Merge fills gaps only, as in iOS.
            seedAssetWork(hasFile = mode != BackupImportMode.MERGE)
            val merge = plannedAssetMerge(mode)

            val summary = backupRepository.applyMergeResult(merge, incomingOriginals())

            assertArrayEquals(INCOMING_EPUB, Files.readAllBytes(workFileStore.workEpubPath(WORK_K)))
            val held = database.workDao().getById(WORK_K)!!
            assertTrue(held.hasEpub)
            assertFalse(held.remoteEpubPending)
            assertArrayEquals(ORIGINAL, Files.readAllBytes(workFileStore.originalFile(WORK_K)!!))
            assertArrayEquals(RECORD, workFileStore.readConversionRecord(WORK_K))
            assertEquals(0, summary.concurrentRowsDeferred)
            workFileStore.deleteOriginal(WORK_K)
        }
    }

    @Test
    fun anUntouchedQueuedWorkDoesNotRejectItsOwnPreservationNormalization() = runTest {
        seedAssetWork()
        val queue = ReadingQueue(id = PEER_ROW, name = "Queue", dateCreated = CLOCK.minusSeconds(100))
        database.readingQueueDao().upsertQueue(queue.toEntity())
        database.readingQueueDao().upsertMembership(ReadingQueueMembership(
            id = SWEPT_SEARCH, queueID = queue.id, workID = WORK_K, queuedAt = queue.dateCreated
        ).toEntity())
        val merge = plannedAssetMerge(BackupImportMode.RECONCILE)
        assertEquals("preserved", merge.snapshot.works.single().epubPreservationStatusRaw)

        val summary = backupRepository.applyMergeResult(merge)

        assertArrayEquals(INCOMING_EPUB, Files.readAllBytes(workFileStore.workEpubPath(WORK_K)))
        assertEquals("preserved", database.workDao().getById(WORK_K)!!.epubPreservationStatusRaw)
        assertEquals(0, summary.concurrentRowsDeferred)
    }

    @Test
    fun anOriginalInstalledMeanwhileIsKeptAndNeverGetsTheOtherOriginalsRecord() = runTest {
        seedAssetWork()
        val merge = plannedAssetMerge(BackupImportMode.RECONCILE)
        val readerOriginal = "Reader's PDF".toByteArray()
        workFileStore.writeOriginal(WORK_K, "pdf", readerOriginal)

        val summary = backupRepository.applyMergeResult(merge, incomingOriginals())

        assertArrayEquals(readerOriginal, Files.readAllBytes(workFileStore.originalFile(WORK_K)!!))
        assertTrue(workFileStore.originalFile(WORK_K)!!.fileName.toString().endsWith(".pdf"))
        assertFalse(workFileStore.conversionRecordExists(WORK_K))
        assertTrue(summary.concurrentRowsDeferred > 0)
    }

    @Test
    fun aFontDeletedBetweenMergeAndApplyGetsNoOrphanBytes() = runTest {
        val font = CustomFont(id = PEER_ROW, name = "Missing file", fileName = "reader.ttf", dateAdded = CLOCK)
        database.customFontDao().upsert(font.toEntity())
        val pack = KudosBackupPackage(KudosBackupManifest(version = BackupVersion.CURRENT,
            exportedAt = CLOCK.toString(), fonts = listOf(BackupFont("Backup", font.fileName, CLOCK.toString()))),
            fontFilesByFileName = mapOf(font.fileName to byteArrayOf(1, 2, 3)))
        val merge = BackupMergeService.merge(backupRepository.captureLibrarySnapshot(), pack, now = CLOCK)
        assertTrue(font.fileName in merge.fontFilesToWriteByFileName)
        database.customFontDao().deleteById(font.id)

        val summary = backupRepository.applyMergeResult(merge)

        assertNull(database.customFontDao().getById(font.id))
        assertFalse(workFileStore.fontExists(font.fileName))
        assertTrue(summary.concurrentRowsDeferred > 0)
    }

    @Test
    fun aNewWorkStillGetsItsIncomingFileInEveryImportMode() = runTest {
        for (mode in BackupImportMode.entries) {
            database.workDao().deleteById(WORK_K)
            workFileStore.deleteWorkEpub(WORK_K)
            val merge = plannedAssetMerge(mode)

            val summary = backupRepository.applyMergeResult(merge)

            assertArrayEquals(INCOMING_EPUB, Files.readAllBytes(workFileStore.workEpubPath(WORK_K)))
            assertTrue(database.workDao().getById(WORK_K)!!.hasEpub)
            assertFalse(database.workDao().getById(WORK_K)!!.remoteEpubPending)
            assertEquals(0, summary.concurrentRowsDeferred)
        }
    }

    @Test
    fun aNewerLocalFileInstalledMeanwhileIsKept() = runTest {
        seedAssetWork(hasFile = false)
        val merge = plannedAssetMerge(BackupImportMode.RECONCILE)
        workFileStore.writeWorkEpub(WORK_K, LOCAL_EPUB)
        database.workDao().upsert(database.workDao().getById(WORK_K)!!.copy(
            hasEpub = true, lastModifiedAt = CLOCK.plusSeconds(1)
        ))

        val summary = backupRepository.applyMergeResult(merge)

        assertArrayEquals(LOCAL_EPUB, Files.readAllBytes(workFileStore.workEpubPath(WORK_K)))
        assertTrue(database.workDao().getById(WORK_K)!!.hasEpub)
        assertTrue(summary.concurrentRowsDeferred > 0)
    }

    @Test
    fun aMissingFilesPromiseClearedMeanwhileIsKeptPendingWithoutInstalling() = runTest {
        seedAssetWork(hasFile = false)
        database.workDao().upsert(database.workDao().getById(WORK_K)!!.copy(remoteEpubPending = true))
        val merge = plannedAssetMerge(BackupImportMode.RECONCILE)
        workRepository.deleteLocalEpub(WORK_K)

        backupRepository.applyMergeResult(merge)

        assertFalse(workFileStore.workEpubExists(WORK_K))
        assertFalse(database.workDao().getById(WORK_K)!!.hasEpub)
        assertTrue(database.workDao().getById(WORK_K)!!.remoteEpubPending)
    }

    @Test
    fun anOriginalAndRecordRemovedMeanwhileAreNotRecreated() = runTest {
        seedAssetWork()
        workFileStore.writeOriginal(WORK_K, "html", ORIGINAL)
        workFileStore.writeConversionRecord(WORK_K, RECORD)
        val merge = plannedAssetMerge(BackupImportMode.RECONCILE)
        workFileStore.deleteOriginal(WORK_K)

        val summary = backupRepository.applyMergeResult(merge, incomingOriginals())

        assertNull(workFileStore.originalFile(WORK_K))
        assertFalse(workFileStore.conversionRecordExists(WORK_K))
        assertTrue(summary.concurrentRowsDeferred > 0)
    }

    private suspend fun seedAssetWork(hasFile: Boolean = true) {
        val work = SavedWork(id = WORK_K, title = "Local", author = "Author",
            sourceUrl = "https://archiveofourown.org/works/4242", dateAdded = CLOCK.minusSeconds(100),
            lastModifiedAt = CLOCK.minusSeconds(100), hasEpub = hasFile)
        database.workDao().upsert(work.toEntity())
        if (hasFile) workFileStore.writeWorkEpub(WORK_K, LOCAL_EPUB) else workFileStore.deleteWorkEpub(WORK_K)
    }

    private suspend fun plannedAssetMerge(mode: BackupImportMode): BackupMergeResult {
        val pack = KudosBackupPackage(KudosBackupManifest(version = BackupVersion.CURRENT,
            exportedAt = CLOCK.toString(), works = listOf(BackupWork(
                id = WORK_K, title = "Backup", author = "Author",
                sourceURL = "https://archiveofourown.org/works/4242", dateAdded = EARLIER,
                lastModifiedAt = CLOCK.toString(), hasEPUB = true
            ))), epubFilesByWorkId = mapOf(WORK_K to INCOMING_EPUB))
        return BackupMergeService.merge(backupRepository.captureLibrarySnapshot(), pack, mode, now = CLOCK)
            .also { assertTrue(WORK_K in it.epubFilesToWriteByWorkId) }
    }

    private fun incomingOriginals(): Map<String, ByteArray> = mapOf(
        BackupPaths.iosOriginalFileName(WORK_K, "html") to ORIGINAL,
        BackupPaths.iosConversionRecordFileName(WORK_K) to RECORD
    )

    private suspend fun capturedReplace(): BackupMergeResult = BackupMergeService.merge(
        backupRepository.captureLibrarySnapshot(),
        KudosBackupPackage(KudosBackupManifest(version = BackupVersion.CURRENT, exportedAt = CLOCK.toString())),
        mode = BackupImportMode.REPLACE_LIBRARY,
        now = CLOCK
    )

    private suspend fun assertOnlyUneditedOmissionIsStored(
        merge: BackupMergeResult, type: String, removedId: String, keptId: String
    ) {
        val expected = merge.snapshot.tombstones.single { it.recordTypeRaw == type && it.recordID == removedId }
        assertTrue(expected.id in merge.replaceOmissionTombstoneIds)
        val stored = database.syncTombstoneDao().getAll().map { it.toDomain() }
        assertEquals(expected, stored.single { it.recordTypeRaw == type && it.recordID == removedId })
        assertFalse(stored.any { it.recordTypeRaw == type && it.recordID == keptId })
    }

    private suspend fun reconcileEmptyArchive() {
        val next = BackupMergeService.merge(backupRepository.captureLibrarySnapshot(),
            KudosBackupPackage(KudosBackupManifest(version = BackupVersion.CURRENT, exportedAt = CLOCK.toString())),
            now = CLOCK)
        backupRepository.applyMergeResult(next)
    }

    @Test
    fun replaceCancelsOnlyItsOwnOmissionNotAnArchivedOrPreviouslyStoredDeletion() = runTest {
        val search = SavedSearch(id = SWEPT_SEARCH, name = "Edited search", dateAdded = Instant.parse(EARLIER))
        database.savedSearchDao().upsert(search.toEntity())
        val peer = Ed25519Sign.KeyPair.newKeyPair()
        val pub = peer.publicKey.toLowerHex()
        val incoming = signedTypedTombstone(search.id, SyncTombstoneRecordType.SAVED_SEARCH,
            peer.privateKey, pub, tombstoneId = PEER_ROW)
        val local = SyncTombstone(id = TOMBSTONE_ID, recordID = search.id,
            recordTypeRaw = SyncTombstoneRecordType.SAVED_SEARCH,
            createdAt = Instant.parse(EARLIER), lastModifiedAt = Instant.parse(EARLIER))
        database.syncTombstoneDao().upsert(local.toEntity())
        val captured = backupRepository.captureLibrarySnapshot()
        val merge = BackupMergeService.merge(captured, KudosBackupPackage(KudosBackupManifest(
            version = BackupVersion.CURRENT, exportedAt = CLOCK.toString(), tombstones = listOf(incoming))),
            mode = BackupImportMode.REPLACE_LIBRARY, now = CLOCK, trustedPublicKeys = setOf(pub))
        val adopted = merge.snapshot.tombstones.single { it.signerPublicKey == pub }
        assertFalse(adopted.id in merge.replaceOmissionTombstoneIds)
        assertFalse(local.id in merge.replaceOmissionTombstoneIds)
        val edited = search.copy(name = "Changed while replacing", filtersJson = "{\"query\":\"reader\"}")
        database.savedSearchDao().upsert(edited.toEntity())
        backupRepository.applyMergeResult(merge)
        assertEquals(edited, database.savedSearchDao().getById(search.id)?.toDomain())
        val stored = database.syncTombstoneDao().getAll().map { it.toDomain() }
        assertEquals(setOf(local, adopted), stored.toSet())
        assertTrue(TombstoneSigning.verify(stored.single { it.signerPublicKey == pub }))
    }

    @Test
    fun changedReadingLogOmissionsKeepTheirRowsWithoutPoisoningTheNextReconcile() = runTest {
        val early = Instant.parse(EARLIER)
        val session = ReadingSessionEntity(id = SWEPT_SEARCH, workID = WORK_K,
            startedAt = early, endedAt = early, lastModifiedAt = early)
        val favorite = ReadingFavoriteEntity(id = SWEPT_SEARCH, kindRaw = "fandom", targetKey = "A fandom",
            createdAt = early, lastModifiedAt = early)
        val watermark = FandomReadWatermarkEntity(id = SWEPT_SEARCH, fandomName = "A fandom",
            lastVisitedAt = early, lastModifiedAt = early)
        database.readingLogDao().upsertSession(session)
        database.readingLogDao().upsertSession(session.copy(id = TOMBSTONE_ID))
        database.readingLogDao().upsertFavorite(favorite)
        database.readingLogDao().upsertFavorite(favorite.copy(id = TOMBSTONE_ID, targetKey = "Another fandom"))
        database.readingLogDao().upsertWatermark(watermark)
        database.readingLogDao().upsertWatermark(watermark.copy(id = TOMBSTONE_ID, fandomName = "Another fandom"))
        val merge = capturedReplace()
        val changedSession = session.copy(durationSeconds = 42.0, lastModifiedAt = CLOCK)
        val changedFavorite = favorite.copy(displayName = "Edited", lastModifiedAt = CLOCK)
        val changedWatermark = watermark.copy(lastVisitedAt = CLOCK, lastModifiedAt = CLOCK)
        database.readingLogDao().upsertSession(changedSession)
        database.readingLogDao().upsertFavorite(changedFavorite)
        database.readingLogDao().upsertWatermark(changedWatermark)
        backupRepository.applyMergeResult(merge)
        listOf(SyncTombstoneRecordType.READING_SESSION, SyncTombstoneRecordType.READING_FAVORITE,
            SyncTombstoneRecordType.FANDOM_READ_WATERMARK).forEach { type ->
            assertOnlyUneditedOmissionIsStored(merge, type, TOMBSTONE_ID, SWEPT_SEARCH)
        }
        reconcileEmptyArchive()
        assertEquals(listOf(changedSession), database.readingLogDao().getAllSessions())
        assertEquals(listOf(changedFavorite), database.readingLogDao().getAllFavorites())
        assertEquals(listOf(changedWatermark), database.readingLogDao().getAllWatermarks())
    }

    @Test
    fun keptRowsEditedDuringReconcileSurviveAndUntouchedRowsTakeTheArchive() = runTest {
        assertKeptRowEdits(BackupImportMode.RECONCILE)
    }

    @Test
    fun keptRowsEditedDuringReplaceSurviveAndUntouchedRowsTakeTheArchive() = runTest {
        assertKeptRowEdits(BackupImportMode.REPLACE_LIBRARY)
    }

    @Test
    fun keptRowsEditedDuringFileMergeSurviveWithoutChangingItsAddOnlyRules() = runTest {
        assertKeptRowEdits(BackupImportMode.MERGE)
    }

    @Test
    fun aConcurrentEditWinsAnEqualArchiveClockWithoutDroppingIndependentFills() = runTest {
        assertKeptRowEdits(BackupImportMode.RECONCILE, archiveTime = CLOCK)
    }

    /** Each kind has an edited row and an untouched control in the same import. */
    private suspend fun assertKeptRowEdits(mode: BackupImportMode, archiveTime: Instant = Instant.parse(LATER)) {
        val early = Instant.parse(EARLIER)
        val work = SavedWork(id = WORK_K, title = "Captured", author = "Author", dateAdded = early,
            lastModifiedAt = early, progressModifiedAt = early, lastReadDate = early,
            lastSpineIndex = 1, lastScrollFraction = 0.1, hasEpub = false)
        val controlWork = work.copy(id = PEER_ROW)
        val collection = WorkCollection(id = SWEPT_SEARCH, name = "Captured collection", dateAdded = early,
            lastModifiedAt = early)
        val controlCollection = collection.copy(id = TOMBSTONE_ID, name = "Control collection")
        val annotation = ReadingAnnotation(id = SWEPT_SEARCH, workID = WORK_K, kindRaw = "note",
            note = "Captured note", createdAt = early, lastModifiedAt = early)
        val controlAnnotation = annotation.copy(id = TOMBSTONE_ID, workID = PEER_ROW)
        val search = SavedSearch(id = SWEPT_SEARCH, name = "Captured search", dateAdded = early,
            filtersJson = "{\"query\":\"captured\"}")
        val controlSearch = search.copy(id = TOMBSTONE_ID, name = "Control search")
        val queue = ReadingQueue(id = PEER_ROW, name = "Queue", dateCreated = early, dateUpdated = early)
        val membership = ReadingQueueMembership(id = SWEPT_SEARCH, queueID = queue.id, workID = WORK_K,
            queuedAt = early, lastModifiedAt = early, sortOrderInQueue = 1)
        val controlMembership = membership.copy(id = TOMBSTONE_ID, workID = PEER_ROW)
        listOf(work, controlWork).forEach { database.workDao().upsert(it.toEntity()) }
        listOf(collection, controlCollection).forEach { database.collectionDao().upsert(it.toEntity()) }
        listOf(annotation, controlAnnotation).forEach { database.annotationDao().upsert(it.toEntity()) }
        listOf(search, controlSearch).forEach { database.savedSearchDao().upsert(it.toEntity()) }
        database.readingQueueDao().upsertQueue(queue.toEntity())
        listOf(membership, controlMembership).forEach { database.readingQueueDao().upsertMembership(it.toEntity()) }
        val captured = backupRepository.captureLibrarySnapshot()
        val incoming = captured.copy(
            works = captured.works.map { it.copy(title = "Archive title", lastModifiedAt = archiveTime,
                lastSpineIndex = 3, lastScrollFraction = 0.3, lastReadDate = archiveTime, progressModifiedAt = archiveTime) },
            collections = captured.collections.map { it.copy(name = "Archive ${it.id}", lastModifiedAt = archiveTime,
                hue = 0.4) },
            annotations = captured.annotations.map { it.copy(note = "Archive note", lastModifiedAt = archiveTime) },
            savedSearches = captured.savedSearches.map { it.copy(filtersJson = "{\"query\":\"archive\"}", dateAdded = archiveTime) },
            readingQueueMemberships = captured.readingQueueMemberships.map {
                it.copy(sortOrderInQueue = 3, note = "Archive membership note", lastModifiedAt = archiveTime)
            }
        )
        val merge = BackupMergeService.merge(captured, KudosBackupPackage(incoming.toV2Manifest(CLOCK)), mode, now = CLOCK)
        // Progress-only save: metadata lastModifiedAt deliberately stays at capture.
        val editedWork = work.copy(lastSpineIndex = 8, lastScrollFraction = 0.8,
            lastReadDate = CLOCK, progressModifiedAt = CLOCK)
        val editedCollection = collection.copy(name = "Reader's collection", lastModifiedAt = CLOCK)
        val editedAnnotation = annotation.copy(note = "Reader's note", lastModifiedAt = CLOCK)
        val editedSearch = search.copy(filtersJson = "{\"query\":\"reader\"}")
        val editedMembership = membership.copy(sortOrderInQueue = 8, lastModifiedAt = CLOCK)
        database.workDao().upsert(editedWork.toEntity())
        database.collectionDao().upsert(editedCollection.toEntity())
        database.annotationDao().upsert(editedAnnotation.toEntity())
        database.savedSearchDao().upsert(editedSearch.toEntity())
        database.readingQueueDao().upsertMembership(editedMembership.toEntity())
        val summary = backupRepository.applyMergeResult(merge)

        val heldWork = database.workDao().getById(WORK_K)!!.toDomain()
        assertEquals(8, heldWork.lastSpineIndex)
        assertEquals(0.8, heldWork.lastScrollFraction, 0.0)
        assertEquals(CLOCK, heldWork.progressModifiedAt)
        // Re-merge also keeps independent archive metadata, rather than skipping the work.
        assertEquals(if (mode == BackupImportMode.MERGE) "Captured" else "Archive title", heldWork.title)
        assertEquals("Reader's collection", database.collectionDao().getById(SWEPT_SEARCH)!!.name)
        // The local-wins collection merge still takes a missing archive color.
        assertEquals(0.4, database.collectionDao().getById(SWEPT_SEARCH)!!.hue!!, 0.0)
        assertEquals("Reader's note", database.annotationDao().getById(SWEPT_SEARCH)!!.note)
        assertEquals(editedSearch.filtersJson, database.savedSearchDao().getById(SWEPT_SEARCH)!!.filtersJson)
        assertEquals(8, database.readingQueueDao().getMembershipById(SWEPT_SEARCH)!!.sortOrderInQueue)
        val addOnly = mode == BackupImportMode.MERGE
        assertEquals(if (addOnly) 1 else 3, database.workDao().getById(PEER_ROW)!!.lastSpineIndex)
        assertEquals(if (addOnly) "Control collection" else "Archive $TOMBSTONE_ID",
            database.collectionDao().getById(TOMBSTONE_ID)!!.name)
        assertEquals(if (addOnly) "Captured note" else "Archive note", database.annotationDao().getById(TOMBSTONE_ID)!!.note)
        // iOS and the existing merge overwrite unedited saved searches even in File Merge.
        assertEquals("{\"query\":\"archive\"}", database.savedSearchDao().getById(TOMBSTONE_ID)!!.filtersJson)
        assertEquals(if (addOnly) 1 else 3, database.readingQueueDao().getMembershipById(TOMBSTONE_ID)!!.sortOrderInQueue)
        assertEquals(2, database.workDao().getAllIncludingDeleted().size)
        assertEquals(2, database.collectionDao().getAllIncludingDeleted().size)
        assertEquals(2, database.annotationDao().getAll().size)
        assertEquals(2, database.savedSearchDao().getAll().size)
        assertEquals(2, database.readingQueueDao().getAllMemberships().size)
        assertEquals(1, database.readingQueueDao().getAllQueues().size)
        assertEquals(5, summary.concurrentRowsChanged)
        assertEquals(if (archiveTime == CLOCK) 5 else 1, summary.concurrentRowsDeferred)
        assertTrue(summary.toUserMessage().contains("kept your version; import again"))
    }

    @Test
    fun progressSavedOnTheSameClockTickDuringReplaceCannotMoveBack() = runTest {
        val work = SavedWork(id = WORK_K, title = "Work", author = "Author", hasEpub = false,
            dateAdded = CLOCK, lastModifiedAt = CLOCK, lastReadDate = CLOCK,
            progressModifiedAt = CLOCK, lastSpineIndex = 1, lastScrollFraction = 0.1)
        database.workDao().upsert(work.toEntity())
        val captured = backupRepository.captureLibrarySnapshot()
        val archive = captured.copy(works = listOf(work.copy(lastSpineIndex = 2, lastScrollFraction = 0.2)))
        val merge = BackupMergeService.merge(captured, KudosBackupPackage(archive.toV2Manifest(CLOCK)),
            mode = BackupImportMode.REPLACE_LIBRARY, now = CLOCK)
        val edited = work.copy(lastSpineIndex = 9, lastScrollFraction = 0.9,
            readiumLocator = "{\"href\":\"chapter.xhtml\",\"locations\":{\"totalProgression\":0.9}}")
        database.workDao().upsert(edited.toEntity())
        backupRepository.applyMergeResult(merge)
        val held = database.workDao().getById(WORK_K)!!.toDomain()
        assertEquals(9, held.lastSpineIndex)
        assertEquals(0.9, held.lastScrollFraction, 0.0)
        assertEquals(edited.readiumLocator, held.readiumLocator)
        assertEquals(1, database.workDao().getAllIncludingDeleted().size)
    }

    @Test
    fun keptClocklessLinkAndFontNamesAreProtectedWithoutInventingAnEditClock() = runTest {
        val link = Bookmark(id = SWEPT_SEARCH, title = "Captured link", urlString = "https://example.org/link",
            dateAdded = Instant.parse(EARLIER))
        val font = CustomFont(id = TOMBSTONE_ID, name = "Captured font", fileName = "Existing.ttf",
            dateAdded = Instant.parse(EARLIER))
        database.bookmarkDao().upsert(link.toEntity())
        database.customFontDao().upsert(font.toEntity())
        val captured = backupRepository.captureLibrarySnapshot()
        val incoming = captured.copy(bookmarks = listOf(link.copy(title = "Archive link", dateAdded = Instant.parse(LATER))))
        val merge = BackupMergeService.merge(captured, KudosBackupPackage(incoming.toV2Manifest(CLOCK)), now = CLOCK)
        val editedLink = link.copy(title = "Reader link")
        val editedFont = font.copy(name = "Reader font")
        database.bookmarkDao().upsert(editedLink.toEntity())
        database.customFontDao().upsert(editedFont.toEntity())
        val summary = backupRepository.applyMergeResult(merge)
        assertEquals(listOf(editedLink.toEntity()), database.bookmarkDao().getAll())
        assertEquals(listOf(editedFont.toEntity()), database.customFontDao().getAll())
        assertEquals(2, summary.concurrentRowsDeferred)
    }

    @Test
    fun replaceKeepsAMembershipCreatedOrReorderedSinceCaptureButRemovesAnUntouchedOmission() = runTest {
        val early = Instant.parse(EARLIER)
        val works = listOf(WORK_K, PEER_ROW, TOMBSTONE_ID).map {
            SavedWork(id = it, title = "Work", author = "Author", hasEpub = false, dateAdded = early)
        }
        works.forEach { database.workDao().upsert(it.toEntity()) }
        val queue = ReadingQueue(id = WORK_K, name = "Queue", dateCreated = early)
        database.readingQueueDao().upsertQueue(queue.toEntity())
        val membership = ReadingQueueMembership(id = SWEPT_SEARCH, queueID = queue.id, workID = WORK_K,
            queuedAt = early, lastModifiedAt = early)
        val untouched = membership.copy(id = TOMBSTONE_ID, workID = TOMBSTONE_ID)
        database.readingQueueDao().upsertMembership(membership.toEntity())
        database.readingQueueDao().upsertMembership(untouched.toEntity())
        val captured = backupRepository.captureLibrarySnapshot()
        val incoming = captured.copy(readingQueueMemberships = emptyList())
        val merge = BackupMergeService.merge(captured, KudosBackupPackage(incoming.toV2Manifest(CLOCK)),
            mode = BackupImportMode.REPLACE_LIBRARY, now = CLOCK)
        val reordered = membership.copy(sortOrderInQueue = 9, lastModifiedAt = CLOCK)
        val created = membership.copy(id = PEER_ROW, workID = PEER_ROW, queuedAt = CLOCK, lastModifiedAt = CLOCK)
        database.readingQueueDao().upsertMembership(reordered.toEntity())
        database.readingQueueDao().upsertMembership(created.toEntity())
        backupRepository.applyMergeResult(merge)
        assertEquals(setOf(reordered.toEntity(), created.toEntity()), database.readingQueueDao().getAllMemberships().toSet())
        assertNull(database.readingQueueDao().getMembershipById(untouched.id))
    }

    @Test
    fun remergeUsesCapturedWorkIdentityWhenTwoArchiveIdsResolveToOneEditedLocalWork() = runTest {
        val early = Instant.parse(EARLIER)
        // A work is matched by the AO3 number in its address, not by the `ao3WorkID` field alone.
        val work = SavedWork(id = WORK_K, title = "Captured", author = "Author", hasEpub = false,
            sourceUrl = "https://archiveofourown.org/works/42",
            ao3WorkID = 42, dateAdded = early, lastModifiedAt = early,
            lastReadDate = early, progressModifiedAt = early, lastSpineIndex = 1)
        database.workDao().upsert(work.toEntity())
        val captured = backupRepository.captureLibrarySnapshot()
        val archiveWork = work.copy(id = PEER_ROW, title = "Archive", lastModifiedAt = Instant.parse(LATER))
        val manifest = captured.toV2Manifest(CLOCK).copy(works = listOf(
            archiveWork.toBackupWork(), archiveWork.copy(id = TOMBSTONE_ID).toBackupWork()
        ))
        val merge = BackupMergeService.merge(captured, KudosBackupPackage(manifest), now = CLOCK)
        assertEquals(setOf(WORK_K), merge.workIdRemap.values.toSet())
        val edited = work.copy(sourceUrl = "https://archiveofourown.org/works/43",
            ao3WorkID = 43, lastModifiedAt = CLOCK, lastSpineIndex = 9,
            lastReadDate = CLOCK, progressModifiedAt = CLOCK)
        database.workDao().upsert(edited.toEntity())
        backupRepository.applyMergeResult(merge)
        val stored = database.workDao().getAllIncludingDeleted().single().toDomain()
        assertEquals(WORK_K, stored.id)
        assertEquals(43, stored.ao3WorkID)
        assertEquals(9, stored.lastSpineIndex)
        assertNull(database.workDao().getById(PEER_ROW))
        assertNull(database.workDao().getById(TOMBSTONE_ID))
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
        private val LOCAL_EPUB = EpubBuilder.buildEpub("Local", "<p>Local bytes.</p>")
        private val INCOMING_EPUB = EpubBuilder.buildEpub("Incoming", "<p>Incoming bytes.</p>")
        private val ORIGINAL = "<p>Incoming original</p>".toByteArray()
        private val RECORD = "{\"converterVersion\":1}".toByteArray()
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
