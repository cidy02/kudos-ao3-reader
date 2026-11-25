package io.github.cidy02.kudos.backup

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.BackupSettings
import io.github.cidy02.kudos.core.model.CoverArtPreference
import io.github.cidy02.kudos.core.model.CoverArtResolution
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.toDomain
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.FontFileStore
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.works.WorkMetadataMerger
import io.github.cidy02.kudos.works.WorkRepository
import java.io.ByteArrayInputStream
import java.io.File
import java.nio.file.Files
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.zip.ZipInputStream
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A-573 / port of every case in iOS `KudosTests/CoverArtPreferenceTests.swift`, plus Android
 * global-setting backup, Room round-trip, clamping/malformed-stamp safety, and non-interference
 * with reading/refreshing/favouriting.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class CoverArtBackupTest {
    private val workId = "11111111-1111-4111-8111-111111111111"
    private val added = Instant.parse("2026-01-10T12:00:00Z")
    private val exportClock = added

    private class TestDevice(
        val db: KudosDatabase,
        val workRepo: WorkRepository,
        val backupRepo: BackupRepository,
        val settingsRepo: SettingsRepository,
        private val scope: CoroutineScope,
        private val root: File
    ) : AutoCloseable {
        override fun close() {
            db.close()
            scope.cancel()
            root.deleteRecursively()
        }
    }

    private fun makeDevice(
        prefix: String,
        clock: () -> Instant = { exportClock }
    ): TestDevice {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val root = Files.createTempDirectory(prefix).toFile()
        val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val db = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        val settings = SettingsRepository(
            PreferenceDataStoreFactory.create(
                scope = scope,
                produceFile = { File(root, "settings.preferences_pb") }
            )
        )
        val workFileStore = WorkFileStore(root.toPath())
        val fontFileStore = FontFileStore(root.toPath())
        val workRepo = WorkRepository(
            database = db,
            fileStore = workFileStore,
            clock = clock
        )
        val backupRepo = BackupRepository(
            database = db,
            workFileStore = workFileStore,
            fontFileStore = fontFileStore,
            settingsRepository = settings,
            persistenceGate = PersistenceGate(),
            clock = clock,
            appVersion = "test"
        )
        return TestDevice(db, workRepo, backupRepo, settings, scope, root)
    }

    private fun manifestBytesFromZip(zipBytes: ByteArray): ByteArray {
        ZipInputStream(ByteArrayInputStream(zipBytes)).use { zip ->
            var entry = zip.nextEntry
            while (entry != null) {
                if (entry.name == BackupPaths.MANIFEST) return zip.readBytes()
                entry = zip.nextEntry
            }
        }
        error("manifest.json missing from backup zip")
    }

    private fun manifestJsonFromZip(zipBytes: ByteArray): JsonObject =
        Json.parseToJsonElement(manifestBytesFromZip(zipBytes).toString(Charsets.UTF_8)).jsonObject

    private fun strippedCoverPreferencePackage(zipBytes: ByteArray): KudosBackupPackage {
        val root = manifestJsonFromZip(zipBytes)
        val works = root.getValue("works").jsonArray.map { element ->
            JsonObject(element.jsonObject.filterKeys { it != "coverArtPreference" })
        }
        val modified = JsonObject(root + ("works" to JsonArray(works)))
        val bytes = BackupJson.encodeToString(JsonObject.serializer(), modified).toByteArray(Charsets.UTF_8)
        return KudosBackupPackage(manifest = BackupValidator.decodeManifest(bytes))
    }

    @Test
    fun useEmbeddedCoverArtDefaultsTrueOmitsWhenUnchosenAndAbsentArchiveNeverClears() = runTest {
        val dir = Files.createTempDirectory("kudos-cover-setting-test").toFile()
        val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        try {
            val repo = SettingsRepository(
                PreferenceDataStoreFactory.create(
                    scope = scope,
                    produceFile = { File(dir, "settings.preferences_pb") }
                )
            )
            // Unchosen default: true in memory, omitted in JSON.
            assertTrue(repo.snapshot().app.useEmbeddedCoverArt)
            assertNull(repo.snapshot().app.storedUseEmbeddedCoverArt)
            val unchosenJson = BackupJson.encodeToString(
                BackupSettings.fromSettings(repo.snapshot()).toBackupSettingsPayload()
            )
            assertFalse(unchosenJson.contains("useEmbeddedCoverArt"))

            // Toggling off persists false, marks sync pending, and exports key.
            repo.updateUseEmbeddedCoverArt(false)
            assertFalse(repo.snapshot().app.useEmbeddedCoverArt)
            assertEquals(false, repo.snapshot().app.storedUseEmbeddedCoverArt)
            assertTrue(repo.snapshot().sync.hasPendingChanges)
            val disabledJson = BackupJson.encodeToString(
                BackupSettings.fromSettings(repo.snapshot()).toBackupSettingsPayload()
            )
            val decoded = BackupJson.decodeFromString<BackupSettingsPayload>(disabledJson)
            assertEquals(false, decoded.useEmbeddedCoverArt)

            // Restore with absent key leaves local preference untouched.
            repo.replaceAll(BackupSettings(useEmbeddedCoverArt = null).toSettings())
            assertFalse(repo.snapshot().app.useEmbeddedCoverArt)

            // Restore with explicit true applies it.
            repo.replaceAll(BackupSettings(useEmbeddedCoverArt = true).toSettings())
            assertTrue(repo.snapshot().app.useEmbeddedCoverArt)
            assertEquals(true, repo.snapshot().app.storedUseEmbeddedCoverArt)
        } finally {
            scope.cancel()
            dir.deleteRecursively()
        }
    }

    // MARK: Ported from iOS KudosTests/CoverArtPreferenceTests.swift

    @Test
    fun resolutionIsOverrideThenGlobalThenHasArt() {
        for (global in listOf(true, false)) {
            for (hasArt in listOf(true, false)) {
                assertFalse(CoverArtResolution.shouldUseEmbeddedArt(global, "generated", hasArt))
                assertEquals(hasArt, CoverArtResolution.shouldUseEmbeddedArt(global, "embedded", hasArt))
                for (follows in listOf(null, CoverArtPreference.FOLLOW_RAW, "sepia-photo")) {
                    assertEquals(
                        global && hasArt,
                        CoverArtResolution.shouldUseEmbeddedArt(global, follows, hasArt)
                    )
                }
            }
        }
    }

    @Test
    fun anUnknownValueIsKeptThroughBackupAndUntouchedBySelectingFollow() = runTest {
        val stamp = Instant.ofEpochSecond(5_000)
        makeDevice("kudos-cover-unk-src").use { source ->
            makeDevice("kudos-cover-unk-dst").use { fresh ->
                source.db.workDao().upsert(
                    sampleWork(preferenceRaw = "sepia-photo", changedAt = stamp).toEntity()
                )
                val zip = source.backupRepo.exportV2ZipBytes()
                fresh.backupRepo.importV2ZipBytes(zip, mode = BackupImportMode.REPLACE_LIBRARY)

                val restored = checkNotNull(fresh.db.workDao().getById(workId)?.toDomain())
                assertEquals("sepia-photo", restored.coverArtPreferenceRaw)
                assertEquals(stamp, restored.coverArtPreferenceChangedAt)

                // Selecting the already-selected "Follow Settings" must not write.
                fresh.workRepo.updateCoverArtPreference(workId, CoverArtPreference.FollowSettings)
                val afterFollow = checkNotNull(fresh.db.workDao().getById(workId)?.toDomain())
                assertEquals("sepia-photo", afterFollow.coverArtPreferenceRaw)
                assertEquals(stamp, afterFollow.coverArtPreferenceChangedAt)
            }
        }
    }

    @Test
    fun aReadersEditStampsItsOwnClockMonotonically() = runTest {
        val now = Instant.now().truncatedTo(ChronoUnit.MILLIS)
        val ahead = now.plusSeconds(600) // a clock that ran fast on an earlier edit
        makeDevice("kudos-cover-mono", clock = { now }).use { device ->
            device.db.workDao().upsert(
                sampleWork(preferenceRaw = null, changedAt = ahead, lastModifiedAt = now).toEntity()
            )
            device.workRepo.updateCoverArtPreference(workId, CoverArtPreference.Generated)
            val afterGenerated = checkNotNull(device.db.workDao().getById(workId)?.toDomain())
            assertEquals("generated", afterGenerated.coverArtPreferenceRaw)
            val first = checkNotNull(afterGenerated.coverArtPreferenceChangedAt)
            assertFalse(first.isBefore(ahead.plusMillis(1)))

            // Same option: no write.
            device.workRepo.updateCoverArtPreference(workId, CoverArtPreference.Generated)
            val afterRepeat = checkNotNull(device.db.workDao().getById(workId)?.toDomain())
            assertEquals(first, afterRepeat.coverArtPreferenceChangedAt)

            // Reset to Follow Settings writes "follow" and advances stamp.
            device.workRepo.updateCoverArtPreference(workId, CoverArtPreference.FollowSettings)
            val afterReset = checkNotNull(device.db.workDao().getById(workId)?.toDomain())
            assertEquals(CoverArtPreference.FOLLOW_RAW, afterReset.coverArtPreferenceRaw)
            val resetStamp = checkNotNull(afterReset.coverArtPreferenceChangedAt)
            assertTrue(resetStamp.isAfter(first))

            // Tapping Follow Settings again after reset writes nothing.
            device.workRepo.updateCoverArtPreference(workId, CoverArtPreference.FollowSettings)
            val afterSecondFollow = checkNotNull(device.db.workDao().getById(workId)?.toDomain())
            assertEquals(CoverArtPreference.FOLLOW_RAW, afterSecondFollow.coverArtPreferenceRaw)
            assertEquals(resetStamp, afterSecondFollow.coverArtPreferenceChangedAt)

            // Untouched work tapping Follow Settings stays null/null with no write.
            val untouchedId = "22222222-2222-4222-8222-222222222222"
            val earlier = now.minusSeconds(300)
            device.db.workDao().upsert(
                sampleWork(id = untouchedId, preferenceRaw = null, changedAt = null, lastModifiedAt = earlier).toEntity()
            )
            device.workRepo.updateCoverArtPreference(untouchedId, CoverArtPreference.FollowSettings)
            val untouched = checkNotNull(device.db.workDao().getById(untouchedId)?.toDomain())
            assertNull(untouched.coverArtPreferenceRaw)
            assertNull(untouched.coverArtPreferenceChangedAt)
            assertEquals(earlier, untouched.lastModifiedAt)
        }
    }

    @Test
    fun bothKeysDecodeFromJSONAndAreOmittedForAWorkWithoutAChoice() = runTest {
        val stamp = Instant.ofEpochSecond(5_000)
        makeDevice("kudos-cover-json-chosen").use { chosenDevice ->
            chosenDevice.db.workDao().upsert(
                sampleWork(preferenceRaw = "embedded", changedAt = stamp).toEntity()
            )
            val chosenZip = chosenDevice.backupRepo.exportV2ZipBytes()
            val entry = manifestJsonFromZip(chosenZip).getValue("works").jsonArray.single().jsonObject
            assertEquals("embedded", entry["coverArtPreference"]?.jsonPrimitive?.content)
            assertNotNull(entry["coverArtPreferenceChangedAt"])

            val decoded = BackupValidator.decodeManifest(manifestBytesFromZip(chosenZip)).works.single()
            assertEquals("embedded", decoded.coverArtPreference)
            assertEquals(stamp, BackupValidator.parseClampedOptionalInstant(decoded.coverArtPreferenceChangedAt))

            makeDevice("kudos-cover-json-restore").use { fresh ->
                fresh.backupRepo.importV2ZipBytes(chosenZip, mode = BackupImportMode.REPLACE_LIBRARY)
                val restored = checkNotNull(fresh.db.workDao().getById(workId)?.toDomain())
                assertEquals("embedded", restored.coverArtPreferenceRaw)
                assertEquals(stamp, restored.coverArtPreferenceChangedAt)
            }
        }

        makeDevice("kudos-cover-json-follow").use { followDevice ->
            followDevice.db.workDao().upsert(
                sampleWork(preferenceRaw = null, changedAt = null).toEntity()
            )
            val followZip = followDevice.backupRepo.exportV2ZipBytes()
            val followEntry = manifestJsonFromZip(followZip).getValue("works").jsonArray.single().jsonObject
            assertNull(followEntry["coverArtPreference"])
            assertNull(followEntry["coverArtPreferenceChangedAt"])
        }
    }

    @Test
    fun anArchiveWithoutTheKeyNeverClearsALocalChoice() = runTest {
        val remoteStamp = Instant.ofEpochSecond(9_000)
        val localStamp = Instant.ofEpochSecond(1_000)
        val stripped = makeDevice("kudos-cover-strip-remote").use { remote ->
            remote.db.workDao().upsert(
                sampleWork(
                    preferenceRaw = "generated",
                    changedAt = remoteStamp,
                    lastModifiedAt = remoteStamp
                ).toEntity()
            )
            strippedCoverPreferencePackage(remote.backupRepo.exportV2ZipBytes())
        }
        assertNull(stripped.manifest.works.single().coverArtPreference)

        for (mode in listOf(BackupImportMode.RECONCILE, BackupImportMode.REPLACE_LIBRARY, BackupImportMode.MERGE)) {
            makeDevice("kudos-cover-strip-local-${mode.name}").use { local ->
                local.db.workDao().upsert(
                    sampleWork(
                        preferenceRaw = "embedded",
                        changedAt = localStamp,
                        lastModifiedAt = localStamp
                    ).toEntity()
                )
                local.backupRepo.importPackage(stripped, mode = mode)
                val mine = checkNotNull(local.db.workDao().getById(workId)?.toDomain())
                assertEquals("mode=$mode", "embedded", mine.coverArtPreferenceRaw)
                assertEquals("mode=$mode", localStamp, mine.coverArtPreferenceChangedAt)
            }
        }
    }

    /** The review's scenario: this copy was only read (newer lastModifiedAt, no choice). */
    @Test
    fun aPeersChoiceSurvivesALocalCopyWithANewerWorkClockButNoChoice() = runTest {
        val peerStamp = Instant.ofEpochSecond(500)
        val archive = makeDevice("kudos-cover-peer-remote").use { remote ->
            remote.db.workDao().upsert(
                sampleWork(
                    preferenceRaw = "generated",
                    changedAt = peerStamp,
                    lastModifiedAt = peerStamp
                ).toEntity()
            )
            remote.backupRepo.exportV2ZipBytes()
        }
        makeDevice("kudos-cover-peer-local").use { local ->
            local.db.workDao().upsert(
                sampleWork(
                    preferenceRaw = null,
                    changedAt = null,
                    lastModifiedAt = Instant.ofEpochSecond(9_000)
                ).toEntity()
            )
            local.backupRepo.importV2ZipBytes(archive, mode = BackupImportMode.RECONCILE)
            val read = checkNotNull(local.db.workDao().getById(workId)?.toDomain())
            assertEquals("generated", read.coverArtPreferenceRaw)
            assertEquals(peerStamp, read.coverArtPreferenceChangedAt)
        }
    }

    @Test
    fun theNewerStampWinsEitherWayRound() = runTest {
        val newerArchive = makeDevice("kudos-cover-newer-remote").use { remote ->
            remote.db.workDao().upsert(
                sampleWork(
                    preferenceRaw = "generated",
                    changedAt = Instant.ofEpochSecond(9_000),
                    lastModifiedAt = Instant.ofEpochSecond(1)
                ).toEntity()
            )
            remote.backupRepo.exportV2ZipBytes()
        }
        makeDevice("kudos-cover-stale-local").use { stale ->
            stale.db.workDao().upsert(
                sampleWork(
                    preferenceRaw = "embedded",
                    changedAt = Instant.ofEpochSecond(1_000),
                    lastModifiedAt = Instant.ofEpochSecond(9_999)
                ).toEntity()
            )
            stale.backupRepo.importV2ZipBytes(newerArchive, mode = BackupImportMode.RECONCILE)
            val old = checkNotNull(stale.db.workDao().getById(workId)?.toDomain())
            assertEquals("generated", old.coverArtPreferenceRaw)
            assertEquals(Instant.ofEpochSecond(9_000), old.coverArtPreferenceChangedAt)
        }

        val olderArchive = makeDevice("kudos-cover-older-remote").use { remoteOlder ->
            remoteOlder.db.workDao().upsert(
                sampleWork(
                    preferenceRaw = "generated",
                    changedAt = Instant.ofEpochSecond(1_000),
                    lastModifiedAt = Instant.ofEpochSecond(9_999)
                ).toEntity()
            )
            remoteOlder.backupRepo.exportV2ZipBytes()
        }
        makeDevice("kudos-cover-fresher-local").use { fresher ->
            fresher.db.workDao().upsert(
                sampleWork(
                    preferenceRaw = "embedded",
                    changedAt = Instant.ofEpochSecond(9_000),
                    lastModifiedAt = Instant.ofEpochSecond(1)
                ).toEntity()
            )
            fresher.backupRepo.importV2ZipBytes(olderArchive, mode = BackupImportMode.RECONCILE)
            val mine = checkNotNull(fresher.db.workDao().getById(workId)?.toDomain())
            assertEquals("embedded", mine.coverArtPreferenceRaw)
            assertEquals(Instant.ofEpochSecond(9_000), mine.coverArtPreferenceChangedAt)
        }
    }

    @Test
    fun aResetToFollowWithANewerStampReachesOtherDevices() = runTest {
        val resetArchive = makeDevice("kudos-cover-reset-remote").use { remote ->
            remote.db.workDao().upsert(
                sampleWork(
                    preferenceRaw = CoverArtPreference.FOLLOW_RAW,
                    changedAt = Instant.ofEpochSecond(9_000),
                    lastModifiedAt = Instant.ofEpochSecond(1_000)
                ).toEntity()
            )
            remote.backupRepo.exportV2ZipBytes()
        }
        makeDevice("kudos-cover-reset-other").use { other ->
            other.db.workDao().upsert(
                sampleWork(
                    preferenceRaw = "generated",
                    changedAt = Instant.ofEpochSecond(1_000),
                    lastModifiedAt = Instant.ofEpochSecond(9_999)
                ).toEntity()
            )
            other.backupRepo.importV2ZipBytes(resetArchive, mode = BackupImportMode.RECONCILE)
            val theirs = checkNotNull(other.db.workDao().getById(workId)?.toDomain())
            assertEquals(CoverArtPreference.FOLLOW_RAW, theirs.coverArtPreferenceRaw)
            assertEquals(Instant.ofEpochSecond(9_000), theirs.coverArtPreferenceChangedAt)
            assertTrue(
                CoverArtResolution.wantsEmbeddedArt(
                    globalUseEmbeddedCoverArt = true,
                    workPreferenceRaw = theirs.coverArtPreferenceRaw
                )
            )
        }
    }

    /**
     * A device whose clock ran 10 minutes fast edited first; the later edit on a correct clock
     * still gets a newer stamp locally (monotonic) and so wins there and after sync.
     */
    @Test
    fun clockSkewWithinTheAllowedWindowStillLetsTheLatestEditWin() = runTest {
        val now = Instant.now().truncatedTo(ChronoUnit.MILLIS)
        val fastAhead = now.plusSeconds(600)
        makeDevice("kudos-cover-skew-fast", clock = { now }).use { fastDevice ->
            makeDevice("kudos-cover-skew-phone", clock = { now }).use { phone ->
                fastDevice.db.workDao().upsert(
                    sampleWork(
                        preferenceRaw = "generated",
                        changedAt = fastAhead,
                        lastModifiedAt = now
                    ).toEntity()
                )
                val archive = fastDevice.backupRepo.exportV2ZipBytes()

                phone.db.workDao().upsert(
                    sampleWork(preferenceRaw = null, changedAt = null, lastModifiedAt = now).toEntity()
                )
                phone.backupRepo.importV2ZipBytes(archive, mode = BackupImportMode.RECONCILE)
                val synced = checkNotNull(phone.db.workDao().getById(workId)?.toDomain())
                assertEquals("generated", synced.coverArtPreferenceRaw)
                assertEquals(fastAhead, synced.coverArtPreferenceChangedAt)

                // Later in real time on a normal clock, monotonic stamp moves past fastAhead.
                phone.workRepo.updateCoverArtPreference(workId, CoverArtPreference.Embedded)
                val edited = checkNotNull(phone.db.workDao().getById(workId)?.toDomain())
                assertEquals("embedded", edited.coverArtPreferenceRaw)
                assertTrue(checkNotNull(edited.coverArtPreferenceChangedAt).isAfter(fastAhead))

                val back = phone.backupRepo.exportV2ZipBytes()
                fastDevice.backupRepo.importV2ZipBytes(back, mode = BackupImportMode.RECONCILE)
                val fastAfter = checkNotNull(fastDevice.db.workDao().getById(workId)?.toDomain())
                assertEquals("embedded", fastAfter.coverArtPreferenceRaw)
                assertEquals(edited.coverArtPreferenceChangedAt, fastAfter.coverArtPreferenceChangedAt)
            }
        }
    }

    @Test
    fun readingRefreshingAndFavouritingNeverTouchCoverArtPreferenceOrStamp() = runTest {
        val stamp = Instant.ofEpochSecond(2_000)
        makeDevice("kudos-cover-untouched", clock = { added.plusSeconds(500) }).use { device ->
            val seeded = sampleWork(preferenceRaw = "generated", changedAt = stamp, lastModifiedAt = added)
            device.db.workDao().upsert(seeded.toEntity())

            device.workRepo.setFavorite(workId, true)
            device.workRepo.noteOpened(workId, added.plusSeconds(600))
            val current = checkNotNull(device.workRepo.getWork(workId))
            val refreshed = WorkMetadataMerger(clock = { added.plusSeconds(700) }).merge(
                summary = null,
                canonical = null,
                existing = current,
                markSaved = true
            )
            device.workRepo.upsert(refreshed)

            val after = checkNotNull(device.workRepo.getWork(workId))
            assertTrue(after.isFavorite)
            assertEquals("generated", after.coverArtPreferenceRaw)
            assertEquals(stamp, after.coverArtPreferenceChangedAt)
        }
    }

    @Test
    fun farFutureStampIsClampedAndMalformedStampLosesToStampedLocal() = runTest {
        val now = Instant.parse("2026-11-24T12:00:00.000Z")
        assertEquals(
            now.plus(24, ChronoUnit.HOURS),
            BackupValidator.parseClampedOptionalInstant("2099-01-01T00:00:00.000Z", now)
        )
        assertNull(BackupValidator.parseClampedOptionalInstant("not-a-date", now))

        val localStamp = Instant.ofEpochSecond(1_000)
        val rawManifest = makeDevice("kudos-cover-bad-stamp-src").use { remote ->
            remote.db.workDao().upsert(
                sampleWork(preferenceRaw = "generated", changedAt = Instant.ofEpochSecond(9_000)).toEntity()
            )
            val root = manifestJsonFromZip(remote.backupRepo.exportV2ZipBytes())
            val works = root.getValue("works").jsonArray.map { element ->
                JsonObject(element.jsonObject + ("coverArtPreferenceChangedAt" to JsonPrimitive("not-a-date")))
            }
            val modified = JsonObject(root + ("works" to JsonArray(works)))
            BackupValidator.decodeManifest(
                BackupJson.encodeToString(JsonObject.serializer(), modified).toByteArray(Charsets.UTF_8)
            )
        }

        makeDevice("kudos-cover-bad-stamp-dst").use { local ->
            local.db.workDao().upsert(
                sampleWork(preferenceRaw = "embedded", changedAt = localStamp).toEntity()
            )
            local.backupRepo.importPackage(
                KudosBackupPackage(manifest = rawManifest),
                mode = BackupImportMode.RECONCILE
            )
            val kept = checkNotNull(local.db.workDao().getById(workId)?.toDomain())
            assertEquals("embedded", kept.coverArtPreferenceRaw)
            assertEquals(localStamp, kept.coverArtPreferenceChangedAt)
        }
    }

    @Test
    fun fullZipBackupRoundTripsGlobalSettingAndPerWorkCoverPreferences() = runTest {
        val stampGen = Instant.ofEpochSecond(4_000)
        val stampEmb = Instant.ofEpochSecond(5_000)
        val stampFollow = Instant.ofEpochSecond(6_000)
        val stampUnk = Instant.ofEpochSecond(7_000)
        makeDevice("kudos-cover-zip-src", clock = { added.plusSeconds(300) }).use { source ->
            makeDevice("kudos-cover-zip-dst", clock = { added.plusSeconds(300) }).use { target ->
                source.settingsRepo.updateUseEmbeddedCoverArt(false)
                val idGen = "11111111-1111-4111-8111-111111111111"
                val idEmb = "22222222-2222-4222-8222-222222222222"
                val idNil = "33333333-3333-4333-8333-333333333333"
                val idFollow = "44444444-4444-4444-8444-444444444444"
                val idUnk = "55555555-5555-4555-8555-555555555555"
                source.db.workDao().upsertAll(
                    listOf(
                        sampleWork("generated", id = idGen, changedAt = stampGen).toEntity(),
                        sampleWork("embedded", id = idEmb, changedAt = stampEmb).toEntity(),
                        sampleWork(null, id = idNil, changedAt = null).toEntity(),
                        sampleWork(CoverArtPreference.FOLLOW_RAW, id = idFollow, changedAt = stampFollow).toEntity(),
                        sampleWork("future-choice", id = idUnk, changedAt = stampUnk).toEntity()
                    )
                )

                val zipBytes = source.backupRepo.exportV2ZipBytes()
                target.backupRepo.importV2ZipBytes(zipBytes)

                assertFalse(target.settingsRepo.snapshot().app.useEmbeddedCoverArt)
                val gen = checkNotNull(target.db.workDao().getById(idGen)?.toDomain())
                assertEquals("generated", gen.coverArtPreferenceRaw)
                assertEquals(stampGen, gen.coverArtPreferenceChangedAt)

                val emb = checkNotNull(target.db.workDao().getById(idEmb)?.toDomain())
                assertEquals("embedded", emb.coverArtPreferenceRaw)
                assertEquals(stampEmb, emb.coverArtPreferenceChangedAt)

                val nilWork = checkNotNull(target.db.workDao().getById(idNil)?.toDomain())
                assertNull(nilWork.coverArtPreferenceRaw)
                assertNull(nilWork.coverArtPreferenceChangedAt)

                val follow = checkNotNull(target.db.workDao().getById(idFollow)?.toDomain())
                assertEquals(CoverArtPreference.FOLLOW_RAW, follow.coverArtPreferenceRaw)
                assertEquals(stampFollow, follow.coverArtPreferenceChangedAt)

                val unk = checkNotNull(target.db.workDao().getById(idUnk)?.toDomain())
                assertEquals("future-choice", unk.coverArtPreferenceRaw)
                assertEquals(stampUnk, unk.coverArtPreferenceChangedAt)
            }
        }
    }

    private fun sampleWork(
        preferenceRaw: String?,
        id: String = workId,
        changedAt: Instant? = null,
        lastModifiedAt: Instant = added
    ): SavedWork = SavedWork(
        id = id,
        title = "Cover Fixture",
        author = "Author",
        dateAdded = Instant.ofEpochSecond(1),
        hasEpub = false,
        lastModifiedAt = lastModifiedAt,
        coverArtPreferenceRaw = preferenceRaw,
        coverArtPreferenceChangedAt = changedAt
    )
}
