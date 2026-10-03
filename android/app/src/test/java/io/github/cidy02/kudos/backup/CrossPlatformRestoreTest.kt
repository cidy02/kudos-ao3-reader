package io.github.cidy02.kudos.backup

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.FontFileStore
import io.github.cidy02.kudos.files.WorkFileStore
import java.io.ByteArrayInputStream
import java.io.File
import java.nio.file.Files
import java.time.Instant
import java.util.zip.ZipInputStream
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.decodeFromString
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class CrossPlatformRestoreTest {
    private lateinit var harness: Harness

    @Before
    fun setUp() {
        harness = Harness()
    }

    @After
    fun tearDown() {
        harness.close()
    }

    @Test
    fun iosGoldenRestoresThroughRepositoryAndAndroidRoundTripsEverySharedField() = runTest {
        val iosBytes = resourceBytes("cross-platform/ios-export.kudosbackup")
        assertDeviceLocalFieldsAreAbsent(iosBytes)
        val expected = BackupJson.decodeFromString<KudosBackupManifest>(
            resourceBytes("cross-platform/expected-values.json").toString(Charsets.UTF_8)
        )
        expected.tombstones.map { it.signerPublicKey }.filter { it.isNotBlank() }.forEach {
            harness.settings.trustTombstonePublicKey(it)
        }

        harness.repository.importV2ZipBytes(iosBytes)
        val importedPack = BackupImporter.importV2Zip(iosBytes)
        importedPack.epubFilesByWorkId.forEach { (workId, bytes) ->
            assertArrayEquals(bytes, Files.readAllBytes(harness.workFiles.workEpubPath(workId)))
        }

        val androidBytes = harness.repository.exportV2ZipBytes()
        assertDeviceLocalFieldsAreAbsent(androidBytes)
        val androidManifest = BackupImporter.importV2Zip(androidBytes).manifest
        assertEquals(canonical(expected), canonical(androidManifest))
        assertFalse(androidManifest.works.any { it.id.isBlank() })

        val androidFixture = fixturePath("KudosTests/Fixtures/cross-platform/android-export.kudosbackup")
        if (System.getProperty("kudos.writeGolden") == "true") {
            Files.createDirectories(androidFixture.parent)
            Files.write(androidFixture, androidBytes)
        } else {
            val committed = Files.readAllBytes(androidFixture)
            assertEquals(canonical(androidManifest), canonical(BackupImporter.importV2Zip(committed).manifest))
        }

        val roundTrip = Harness()
        try {
            expected.tombstones.map { it.signerPublicKey }.filter { it.isNotBlank() }.forEach {
                roundTrip.settings.trustTombstonePublicKey(it)
            }
            roundTrip.repository.importV2ZipBytes(androidBytes)
            val roundTripManifest = BackupImporter.importV2Zip(
                roundTrip.repository.exportV2ZipBytes()
            ).manifest
            assertEquals(canonical(expected), canonical(roundTripManifest))
            importedPack.epubFilesByWorkId.forEach { (workId, bytes) ->
                assertArrayEquals(bytes, Files.readAllBytes(roundTrip.workFiles.workEpubPath(workId)))
            }
        } finally {
            roundTrip.close()
        }
    }

    private fun canonical(manifest: KudosBackupManifest): KudosBackupManifest {
        val systemQueue = manifest.readingQueues.firstOrNull { it.kindRaw == "savedForLater" }
        val canonicalSystemId = "00000000-0000-0000-0000-000000000000"
        return manifest.copy(
            exportedAt = "",
            exportedBy = null,
            works = manifest.works.map {
                it.copy(
                    id = canonicalId(it.id),
                    permanentDeletionScheduledAt = null,
                    collectionIDs = emptyList(),
                    readiumLocatorPlatform = null,
                    readiumLocatorEngine = null,
                    readiumLocatorVersion = null
                )
            }.sortedBy { it.id },
            bookmarks = manifest.bookmarks.map {
                it.copy(id = it.id?.let(::canonicalId))
            }.sortedBy { it.id ?: it.urlString },
            fonts = manifest.fonts.sortedBy { it.fileName },
            collections = manifest.collections.map {
                it.copy(
                    id = canonicalId(it.id),
                    workIDs = it.workIDs.map(::canonicalId),
                    workOrderRaw = it.workOrderRaw?.split(',')?.joinToString(",", transform = ::canonicalId),
                    permanentDeletionScheduledAt = null
                )
            }.sortedBy { it.id },
            savedSearches = manifest.savedSearches.map {
                it.copy(id = canonicalId(it.id))
            }.sortedBy { it.id },
            readingQueues = manifest.readingQueues.map {
                it.copy(
                    id = if (it.kindRaw == "savedForLater") canonicalSystemId else canonicalId(it.id),
                    permanentDeletionScheduledAt = null
                )
            }.sortedBy { it.id },
            readingQueueMemberships = manifest.readingQueueMemberships.map {
                it.copy(
                    id = canonicalId(it.id),
                    queueID = if (canonicalId(it.queueID) == systemQueue?.id?.let(::canonicalId)) {
                        canonicalSystemId
                    } else {
                        canonicalId(it.queueID)
                    },
                    workID = canonicalId(it.workID)
                )
            }.sortedBy { it.id },
            annotations = manifest.annotations.map {
                it.copy(id = canonicalId(it.id), workID = canonicalId(it.workID))
            }.sortedBy { it.id },
            readingSessions = manifest.readingSessions.map {
                it.copy(id = canonicalId(it.id), workID = canonicalId(it.workID))
            }.sortedBy { it.id },
            readingFavorites = manifest.readingFavorites.map {
                it.copy(id = canonicalId(it.id))
            }.sortedBy { it.id },
            fandomReadWatermarks = manifest.fandomReadWatermarks.map {
                it.copy(id = canonicalId(it.id))
            }.sortedBy { it.id },
            tombstones = manifest.tombstones.map {
                it.copy(id = canonicalId(it.id), recordID = canonicalId(it.recordID))
            }.sortedBy { it.id },
            settings = manifest.settings.copy(readerFontID = "system")
        )
    }

    private fun canonicalId(value: String): String = BackupPaths.canonicalUuid(value)

    private fun assertDeviceLocalFieldsAreAbsent(archive: ByteArray) {
        val manifest = ZipInputStream(ByteArrayInputStream(archive)).use { zip ->
            generateSequence { zip.nextEntry }
                .first { it.name == BackupPaths.MANIFEST }
            zip.readBytes().toString(Charsets.UTF_8)
        }
        assertFalse(manifest.contains("\"freedAt\""))
        assertFalse(manifest.contains("\"authorIdentitiesJSON\""))
    }

    private fun resourceBytes(name: String): ByteArray {
        return checkNotNull(javaClass.classLoader?.getResourceAsStream(name)) {
            "Missing test resource $name. Regenerate with KUDOS_WRITE_GOLDEN=1."
        }.use { it.readBytes() }
    }

    private fun fixturePath(relative: String): java.nio.file.Path {
        var candidate = File(System.getProperty("user.dir")).absoluteFile
        while (!File(candidate, "KudosTests").isDirectory && candidate.parentFile != null) {
            candidate = candidate.parentFile
        }
        return candidate.toPath().resolve(relative)
    }

    private class Harness : AutoCloseable {
        private val context = ApplicationProvider.getApplicationContext<Context>()
        private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        private val root = Files.createTempDirectory("kudos-cross-platform")
        val database: KudosDatabase = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        val settings = SettingsRepository(
            PreferenceDataStoreFactory.create(
                scope = scope,
                produceFile = { root.resolve("settings.preferences_pb").toFile() }
            )
        )
        val workFiles = WorkFileStore(root)
        val repository = BackupRepository(
            database = database,
            workFileStore = workFiles,
            fontFileStore = FontFileStore(root),
            settingsRepository = settings,
            persistenceGate = PersistenceGate(),
            clock = { Instant.parse("2026-01-15T12:00:00Z") },
            appVersion = "cross-platform-test"
        )

        override fun close() {
            database.close()
            scope.cancel()
            root.toFile().deleteRecursively()
        }
    }
}
