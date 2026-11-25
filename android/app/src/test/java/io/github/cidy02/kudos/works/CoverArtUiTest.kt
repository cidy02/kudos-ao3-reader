package io.github.cidy02.kudos.works

import android.app.Application
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.CoverArtPreference
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.home.HomeResumeHero
import io.github.cidy02.kudos.library.ReadingQueueRepository
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.work.AO3EpubDownloader
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataRepository
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.settings.SettingsAppearancePage
import io.github.cidy02.kudos.ui.components.LocalUseEmbeddedCoverArt
import io.github.cidy02.kudos.ui.subject.SubjectWorkCoverCard
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.works.detail.WORK_DETAIL_COVER_SECTION_TAG
import io.github.cidy02.kudos.works.detail.WorkDetailCoverSection
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.file.Files
import java.time.Instant
import java.util.UUID
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h2200dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class CoverArtUiTest {
    @get:Rule val compose = createComposeRule()
    private val root = Files.createTempDirectory("kudos-cover-ui")
    private val storeScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val repository = SettingsRepository(
        PreferenceDataStoreFactory.create(
            scope = storeScope,
            produceFile = { root.resolve("settings.preferences_pb").toFile() }
        )
    )
    private val createdFiles = mutableListOf<File>()

    @After
    fun tearDown() {
        createdFiles.forEach { it.delete() }
        storeScope.cancel()
        root.toFile().deleteRecursively()
    }

    @Test
    fun appearancePageShowsAndPersistsUseEmbeddedCoverArtSwitch() {
        compose.setContent {
            val current = produceState(KudosSettings.Defaults) {
                repository.settings.collect { value = it }
            }.value
            KudosTheme(KudosThemeMode.Light) {
                SettingsAppearancePage(repository, current)
            }
        }
        compose.onNodeWithText("Covers").performScrollTo().assertExists()
        compose.onNodeWithContentDescription("Use art from the work when there is some")
            .performScrollTo()
            .assertIsOn()
            .performClick()

        compose.waitUntil(5_000) { !runBlocking { repository.snapshot().app.useEmbeddedCoverArt } }
        assertFalse(runBlocking { repository.snapshot().app.useEmbeddedCoverArt })
        compose.onNodeWithContentDescription("Use art from the work when there is some")
            .assertIsOff()
    }

    @Test
    fun appearancePageCoversSectionScalesTo200PercentInDarkAndAllThemes() {
        val themeState = mutableStateOf(KudosThemeMode.Dark)
        val footnote = "When this is off, every work shows its generated cover. A work's own page can choose for that work."
        compose.setContent {
            val density = LocalDensity.current
            val current = produceState(KudosSettings.Defaults) {
                repository.settings.collect { value = it }
            }.value
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2.0f)) {
                KudosTheme(themeState.value) {
                    SettingsAppearancePage(repository, current)
                }
            }
        }

        // In Dark theme at 200% font scale, Covers switch is reachable, clickable, and persists.
        compose.onNodeWithText("Covers").performScrollTo().assertExists()
        compose.onNodeWithContentDescription("Use art from the work when there is some")
            .performScrollTo()
            .assertIsOn()
            .performClick()
        compose.waitUntil(5_000) { !runBlocking { repository.snapshot().app.useEmbeddedCoverArt } }
        compose.onNodeWithContentDescription("Use art from the work when there is some")
            .assertIsOff()
            .performClick()
        compose.waitUntil(5_000) { runBlocking { repository.snapshot().app.useEmbeddedCoverArt } }
        compose.onNodeWithContentDescription("Use art from the work when there is some").assertIsOn()

        // Verify label and footnote render without overflow at 200% font scale across all four themes.
        for (theme in listOf(KudosThemeMode.Dark, KudosThemeMode.Oled, KudosThemeMode.Sepia, KudosThemeMode.Light)) {
            themeState.value = theme
            compose.waitForIdle()
            for (copy in listOf("Use art from the work when there is some", footnote)) {
                val layouts = mutableListOf<TextLayoutResult>()
                compose.onNodeWithText(copy, useUnmergedTree = true)
                    .performScrollTo()
                    .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
                assertTrue("Expected text layout for '$copy' in $theme", layouts.isNotEmpty())
                layouts.forEach { result ->
                    assertFalse("'$copy' overflowed height in $theme at 200%", result.didOverflowHeight)
                    assertFalse("'$copy' exceeded maxLines in $theme at 200%", result.multiParagraph.didExceedMaxLines)
                }
            }
        }
    }

    @Test
    fun workDetailScreenGuardsCoverSectionOnEmbeddedArtAndUpdatesCoverLive() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val db = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        try {
            val fileStore = WorkFileStore(context.filesDir.toPath())
            val workClock = Instant.parse("2026-01-10T12:00:00Z")
            val editClock = Instant.parse("2026-01-10T12:05:00Z")
            val workRepo = WorkRepository(database = db, fileStore = fileStore, clock = { editClock })
            val queueRepo = ReadingQueueRepository(database = db)
            val importer = WorkImporter(
                workRepository = workRepo,
                metadataRepository = AO3WorkMetadataRepository(client = unusedAo3Client),
                downloader = AO3EpubDownloader(client = unusedAo3Client),
                fileStore = fileStore,
                cacheDir = root.toFile()
            )
            val downloadQueue = DownloadQueue(
                workImporter = importer,
                workRepository = workRepo,
                scope = storeScope
            )
            val writeRepo = AO3WriteRepository(client = unusedAuthClient)

            val plainWorkId = UUID.randomUUID().toString()
            val artWorkId = UUID.randomUUID().toString()
            val plainEpub = writeFixtureEpub(fileStore.workEpubPath(plainWorkId).toFile(), includeCoverArt = false)
            val artEpub = writeFixtureEpub(fileStore.workEpubPath(artWorkId).toFile(), includeCoverArt = true)
            createdFiles += plainEpub
            createdFiles += artEpub

            runBlocking {
                db.workDao().upsertAll(
                    listOf(
                        SavedWork(
                            id = plainWorkId,
                            title = "Plain Work Without Art",
                            author = "Author One",
                            sourceUrl = "",
                            dateAdded = workClock,
                            hasEpub = true,
                            lastModifiedAt = workClock
                        ).toEntity(),
                        SavedWork(
                            id = artWorkId,
                            title = "Illustrated Work",
                            author = "Author Two",
                            sourceUrl = "",
                            dateAdded = workClock,
                            hasEpub = true,
                            lastModifiedAt = workClock
                        ).toEntity()
                    )
                )
            }

            val sourceState = mutableStateOf<WorkDetailSource>(WorkDetailSource.LocalWork(plainWorkId))
            compose.setContent {
                val current = produceState(KudosSettings.Defaults) {
                    repository.settings.collect { value = it }
                }.value
                CompositionLocalProvider(LocalUseEmbeddedCoverArt provides current.app.useEmbeddedCoverArt) {
                    KudosTheme(KudosThemeMode.Light) {
                        WorkDetailScreen(
                            source = sourceState.value,
                            workRepository = workRepo,
                            workImporter = importer,
                            downloadQueue = downloadQueue,
                            writeRepository = writeRepo,
                            readingQueueRepository = queueRepo,
                            settingsRepository = repository,
                            onLogin = {},
                            onOpenComments = {},
                            onOpenReader = {}
                        )
                    }
                }
            }

            // 1. Work WITHOUT embedded art: once loaded & scanned, Cover section and photo cover stay hidden.
            compose.waitUntil(5_000) {
                compose.onAllNodesWithText("Plain Work Without Art").fetchSemanticsNodes().isNotEmpty() &&
                    EmbeddedCoverArtLoader.shared(context).peekHasArt(plainEpub) == false
            }
            compose.waitForIdle()
            compose.onNodeWithTag(WORK_DETAIL_COVER_SECTION_TAG).assertDoesNotExist()
            compose.onNodeWithTag(EMBEDDED_COVER_ART_IMAGE_TAG, useUnmergedTree = true).assertDoesNotExist()

            // 2. Work WITH embedded art: Cover section appears and Resume card renders embedded cover art.
            sourceState.value = WorkDetailSource.LocalWork(artWorkId)
            compose.waitUntil(5_000) {
                compose.onAllNodesWithTag(WORK_DETAIL_COVER_SECTION_TAG).fetchSemanticsNodes().isNotEmpty() &&
                    compose.onAllNodesWithTag(EMBEDDED_COVER_ART_IMAGE_TAG, useUnmergedTree = true)
                        .fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithContentDescription("Cover: Follow Settings, Currently Work's Art")
                .performScrollTo()
                .assertIsSelected()

            // 3. Tapping "Generated" persists choice without moving lastModifiedAt and hides Resume card photo live.
            compose.onNodeWithContentDescription("Cover: Generated")
                .performScrollTo()
                .performClick()
            compose.waitUntil(5_000) {
                runBlocking { workRepo.getWork(artWorkId)?.coverArtPreferenceRaw } == "generated" &&
                    compose.onAllNodesWithTag(EMBEDDED_COVER_ART_IMAGE_TAG, useUnmergedTree = true)
                        .fetchSemanticsNodes().isEmpty()
            }
            val afterGenerated = checkNotNull(runBlocking { workRepo.getWork(artWorkId) })
            assertEquals("generated", afterGenerated.coverArtPreferenceRaw)
            assertNotNull(afterGenerated.coverArtPreferenceChangedAt)
            assertEquals(workClock, afterGenerated.lastModifiedAt)
            compose.onNodeWithTag(WORK_DETAIL_COVER_SECTION_TAG).assertExists()
            compose.onNodeWithContentDescription("Cover: Generated").assertIsSelected()

            // 4. Tapping "Work's Art" restores photo live, and survives toggling global setting off.
            compose.onNodeWithContentDescription("Cover: Work's Art")
                .performScrollTo()
                .performClick()
            compose.waitUntil(5_000) {
                runBlocking { workRepo.getWork(artWorkId)?.coverArtPreferenceRaw } == "embedded" &&
                    compose.onAllNodesWithTag(EMBEDDED_COVER_ART_IMAGE_TAG, useUnmergedTree = true)
                        .fetchSemanticsNodes().isNotEmpty()
            }
            runBlocking { repository.updateUseEmbeddedCoverArt(false) }
            compose.waitUntil(5_000) {
                compose.onAllNodesWithText("Currently Generated", useUnmergedTree = true)
                    .fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithTag(EMBEDDED_COVER_ART_IMAGE_TAG, useUnmergedTree = true).assertExists()

            // 5. Tapping "Follow Settings" writes "follow" and hides photo live (global is now off).
            compose.onNodeWithContentDescription("Cover: Follow Settings, Currently Generated")
                .performScrollTo()
                .performClick()
            compose.waitUntil(5_000) {
                runBlocking { workRepo.getWork(artWorkId)?.coverArtPreferenceRaw } == CoverArtPreference.FOLLOW_RAW &&
                    compose.onAllNodesWithTag(EMBEDDED_COVER_ART_IMAGE_TAG, useUnmergedTree = true)
                        .fetchSemanticsNodes().isEmpty()
            }
        } finally {
            db.close()
        }
    }

    @Test
    fun coverCardsReactToGlobalTogglePerWorkChoiceAndObscuredState() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val fileStore = WorkFileStore(context.filesDir.toPath())
        val workId = UUID.randomUUID().toString()
        val epub = writeFixtureEpub(fileStore.workEpubPath(workId).toFile(), includeCoverArt = true)
        createdFiles += epub

        val globalArt = mutableStateOf(true)
        val obscured = mutableStateOf(false)
        val workState = mutableStateOf(
            SavedWork(
                id = workId,
                title = "Card Cover Work",
                author = "Card Author",
                workFandoms = listOf("Fandom"),
                hasEpub = true,
                coverArtPreferenceRaw = null
            )
        )

        compose.setContent {
            CompositionLocalProvider(LocalUseEmbeddedCoverArt provides globalArt.value) {
                KudosTheme(KudosThemeMode.Light) {
                    Column {
                        SubjectWorkCoverCard(
                            work = workState.value,
                            obscured = obscured.value,
                            downloadFraction = null
                        )
                        HomeResumeHero(
                            work = workState.value,
                            downloadFraction = null,
                            obscured = obscured.value,
                            isSelecting = false,
                            isSelected = false
                        )
                    }
                }
            }
        }

        // Default: global on + follow -> both SubjectWorkCoverCard and HomeResumeHero show embedded art.
        compose.waitUntil(5_000) {
            compose.onAllNodesWithTag(EMBEDDED_COVER_ART_IMAGE_TAG, useUnmergedTree = true)
                .fetchSemanticsNodes().size == 2
        }

        // Global off + follow -> both cards switch to generated covers.
        globalArt.value = false
        compose.waitForIdle()
        compose.onAllNodesWithTag(EMBEDDED_COVER_ART_IMAGE_TAG, useUnmergedTree = true).assertCountEquals(0)

        // Per-work "embedded" overrides global off -> both cards show embedded art again.
        workState.value = workState.value.copy(coverArtPreferenceRaw = "embedded")
        compose.waitUntil(5_000) {
            compose.onAllNodesWithTag(EMBEDDED_COVER_ART_IMAGE_TAG, useUnmergedTree = true)
                .fetchSemanticsNodes().size == 2
        }

        // Obscured mature card never displays embedded cover art even with "embedded" override.
        obscured.value = true
        compose.waitForIdle()
        compose.onAllNodesWithTag(EMBEDDED_COVER_ART_IMAGE_TAG, useUnmergedTree = true).assertCountEquals(0)

        // Unobscured + global on + per-work "generated" -> both cards stay on generated covers.
        obscured.value = false
        globalArt.value = true
        workState.value = workState.value.copy(coverArtPreferenceRaw = "generated")
        compose.waitForIdle()
        compose.onAllNodesWithTag(EMBEDDED_COVER_ART_IMAGE_TAG, useUnmergedTree = true).assertCountEquals(0)
    }

    @Test
    fun workDetailCoverSectionSelectsOptionsShowsEffectiveSettingAndScalesToAx5InAllThemes() {
        var latestSelection = CoverArtPreference.FollowSettings
        val themeState = mutableStateOf(KudosThemeMode.Light)
        val globalState = mutableStateOf(true)
        compose.setContent {
            val density = LocalDensity.current
            var selected by remember { mutableStateOf(CoverArtPreference.FollowSettings) }
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2.5f)) {
                KudosTheme(themeState.value) {
                    WorkDetailCoverSection(
                        selected = selected,
                        globalUseEmbeddedCoverArt = globalState.value,
                        onSelect = {
                            selected = it
                            latestSelection = it
                        }
                    )
                }
            }
        }

        compose.onNodeWithTag(WORK_DETAIL_COVER_SECTION_TAG).assertExists()
        compose.onNodeWithContentDescription("Cover: Follow Settings, Currently Work's Art")
            .assertExists()
            .assertIsSelected()
        compose.onNodeWithContentDescription("Cover: Work's Art").assertIsNotSelected()
        compose.onNodeWithContentDescription("Cover: Generated").assertIsNotSelected()

        // Selecting Generated updates selection immediately.
        compose.onNodeWithContentDescription("Cover: Generated").performClick()
        assertEquals(CoverArtPreference.Generated, latestSelection)
        compose.onNodeWithContentDescription("Cover: Generated").assertIsSelected()

        // Changing global setting updates Follow Settings effective subtitle.
        globalState.value = false
        compose.waitForIdle()
        compose.onNodeWithContentDescription("Cover: Follow Settings, Currently Generated")
            .assertExists()
            .performClick()
        assertEquals(CoverArtPreference.FollowSettings, latestSelection)
        compose.onNodeWithContentDescription("Cover: Follow Settings, Currently Generated")
            .assertIsSelected()

        // Verify all four themes render cleanly at 2.5x font scale with zero text overflow.
        for (theme in listOf(KudosThemeMode.Light, KudosThemeMode.Sepia, KudosThemeMode.Dark, KudosThemeMode.Oled)) {
            themeState.value = theme
            compose.waitForIdle()
            for (label in listOf("Follow Settings", "Currently Generated", "Work's Art", "Generated")) {
                val layouts = mutableListOf<TextLayoutResult>()
                compose.onNodeWithText(label, useUnmergedTree = true)
                    .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
                assertTrue("Expected text layout for $label in $theme", layouts.isNotEmpty())
                layouts.forEach { result ->
                    assertFalse("$label overflowed height in $theme", result.didOverflowHeight)
                    assertFalse("$label exceeded maxLines in $theme", result.multiParagraph.didExceedMaxLines)
                }
            }
        }
    }

    private val unusedAo3Client = object : AO3Client {
        override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> =
            AO3Result.Failure(AO3Error.Network("Unused in CoverArtUiTest"))
    }

    private val unusedAuthClient = object : AO3AuthenticatedClient {
        override fun username(): String? = null
        override suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse> =
            AO3Result.Failure(AO3Error.Network("Unused in CoverArtUiTest"))

        override suspend fun postAuthenticated(
            url: String,
            formFields: List<Pair<String, String>>,
            headers: Map<String, String>
        ): AO3Result<AO3HttpResponse> = AO3Result.Failure(AO3Error.Network("Unused in CoverArtUiTest"))
    }

    private fun writeFixtureEpub(destination: File, includeCoverArt: Boolean): File {
        destination.parentFile?.mkdirs()
        val frontBody = if (includeCoverArt) """<img src="cover.png" alt="Cover"/>""" else "<p>Preface</p>"
        val entries = linkedMapOf<String, Any>(
            "META-INF/container.xml" to """
                <?xml version="1.0" encoding="UTF-8"?>
                <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
                    <rootfiles>
                        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
                    </rootfiles>
                </container>
            """.trimIndent(),
            "OEBPS/content.opf" to """
                <?xml version="1.0" encoding="UTF-8"?>
                <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uid">
                    <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Fixture</dc:title></metadata>
                    <manifest>
                        <item id="front" href="front.xhtml" media-type="application/xhtml+xml"/>
                        <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
                    </manifest>
                    <spine>
                        <itemref idref="front"/>
                        <itemref idref="ch1"/>
                    </spine>
                </package>
            """.trimIndent(),
            "OEBPS/front.xhtml" to """
                <?xml version="1.0" encoding="UTF-8"?>
                <html xmlns="http://www.w3.org/1999/xhtml"><body>$frontBody</body></html>
            """.trimIndent(),
            "OEBPS/ch1.xhtml" to """
                <?xml version="1.0" encoding="UTF-8"?>
                <html xmlns="http://www.w3.org/1999/xhtml"><body><p>Chapter 1</p></body></html>
            """.trimIndent()
        )
        if (includeCoverArt) {
            val bitmap = Bitmap.createBitmap(400, 600, Bitmap.Config.ARGB_8888)
            Canvas(bitmap).drawColor(Color.rgb(40, 120, 180))
            val out = ByteArrayOutputStream()
            assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, out))
            bitmap.recycle()
            entries["OEBPS/cover.png"] = out.toByteArray()
        }
        ZipOutputStream(destination.outputStream()).use { zip ->
            entries.forEach { (name, payload) ->
                zip.putNextEntry(ZipEntry(name))
                when (payload) {
                    is ByteArray -> zip.write(payload)
                    is String -> zip.write(payload.toByteArray(Charsets.UTF_8))
                }
                zip.closeEntry()
            }
        }
        return destination
    }
}
