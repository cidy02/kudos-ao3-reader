package io.github.cidy02.kudos.library

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import io.github.cidy02.kudos.backup.BackupJson
import io.github.cidy02.kudos.backup.BackupSettingsPayload
import io.github.cidy02.kudos.backup.toBackupSettingsPayload
import io.github.cidy02.kudos.backup.toCoreBackupSettings
import io.github.cidy02.kudos.core.model.BackupSettings
import io.github.cidy02.kudos.core.model.LibraryPageArrangement
import io.github.cidy02.kudos.core.model.LibraryPageSection
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class LibraryPageArrangementTest {
    @get:Rule val tmp: TemporaryFolder = TemporaryFolder.builder().assureDeletion().build()

    // Shape of iOS `LibraryPageArrangement.encode`: sections [{id,style}], buttons [id].
    private val iosJson = """{"sections":[{"id":"downloaded","style":"list"},{"id":"favourites","style":"carousel"}],
        "buttons":["wantToRead","readingNow","finished","queues","history","imported","collections"]}"""

    private fun payload(arrangement: String?): BackupSettingsPayload = BackupJson.decodeFromString(
        "{" + (arrangement?.let { "\"libraryPageArrangement\":$it" } ?: "") + "}"
    )

    private fun repo() = SettingsRepository(
        PreferenceDataStoreFactory.create(produceFile = { File(tmp.root, "t.preferences_pb") })
    )

    @Test fun iosShapedValueRoundTripsThroughImportAndExportUnchanged() = runTest {
        val repo = repo()
        repo.replaceAll(payload(iosJson).toCoreBackupSettings().toSettings())
        val exported = BackupSettings.fromSettings(repo.settings.first()).toBackupSettingsPayload()
        assertEquals(Json.parseToJsonElement(iosJson), exported.libraryPageArrangement)
    }

    @Test fun absentKeyLeavesTheLocalLayout() = runTest {
        val repo = repo()
        val local = LibraryPageArrangement.Default.settingStyle("downloaded", "list")
        repo.updateLibraryPageArrangement(local)
        repo.replaceAll(payload(null).toCoreBackupSettings().toSettings())
        assertEquals(local, repo.settings.first().app.libraryPageArrangement)
    }

    @Test fun malformedValueDecodesAsNullAndLeavesTheLocalLayout() = runTest {
        assertNull(payload("\"nope\"").toCoreBackupSettings().libraryPageArrangement)
        val repo = repo()
        val local = LibraryPageArrangement.Default.removingFromPage("favourites")
        repo.updateLibraryPageArrangement(local)
        repo.replaceAll(payload("\"nope\"").toCoreBackupSettings().toSettings())
        assertEquals(local, repo.settings.first().app.libraryPageArrangement)
    }

    @Test fun unknownShelfIdSurvivesTheRoundTrip() = runTest {
        val json = """{"sections":[{"id":"iosOnly","style":"list"},{"id":"favourites","style":"carousel"}],"buttons":["wantToRead"]}"""
        val repo = repo()
        repo.replaceAll(payload(json).toCoreBackupSettings().toSettings())
        val out = repo.settings.first().app.libraryPageArrangement!!
        assertEquals(LibraryPageSection("iosOnly", "list"), out.sections.first())
        val exported = BackupSettings.fromSettings(repo.settings.first()).toBackupSettingsPayload()
        val sections = (exported.libraryPageArrangement as JsonObject)["sections"].toString()
        assertTrue(sections.contains("iosOnly"))
    }

    @Test fun absentLocalValueIsOmittedOnExport() {
        assertNull(BackupSettings().toBackupSettingsPayload().libraryPageArrangement)
    }

    @Test fun layoutsAreEqualByShelvesNotJsonBytes() {
        val a = LibraryPageArrangement.fromJsonString("""{"sections":[],"buttons":["finished"]}""")
        val b = LibraryPageArrangement.fromJsonString("""{ "buttons":["finished"], "sections":[] }""")
        assertEquals(a, b)
    }

    @Test fun missingShelvesAreRepairedOntoButtons() {
        val a = LibraryPageArrangement.fromJsonString("""{"sections":[{"id":"favourites","style":"list"}],"buttons":[]}""")!!
        assertEquals(8, a.buttons.size)
        assertEquals("collections", a.buttons.first())
    }

    @Test fun addRemoveStyleAndMove() {
        val d = LibraryPageArrangement.Default
        val added = d.addingToPage("finished")
        assertEquals("carousel", added.styleOf("finished"))
        assertTrue("finished" !in added.buttons)
        val removed = added.removingFromPage("favourites")
        assertEquals("favourites", removed.buttons.last())
        assertEquals("list", d.settingStyle("downloaded", "list").styleOf("downloaded"))
        assertEquals(listOf("collections", "downloaded", "favourites"),
            d.movingSection(0, 2).sections.map { it.id })
        assertEquals(d, d.movingSection(0, 9))
    }

    @Test fun updateMarksFolderSyncDirty() = runTest {
        val repo = repo()
        repo.updateLibraryPageArrangement(LibraryPageArrangement.Default)
        assertTrue(repo.settings.first().sync.hasPendingChanges)
    }
}
