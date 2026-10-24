package io.github.cidy02.kudos.app

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ImportContacts
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Density
import io.github.cidy02.kudos.account.*
import io.github.cidy02.kudos.author.*
import io.github.cidy02.kudos.comments.ChapterPickerContent
import io.github.cidy02.kudos.comments.chapterPickerBookIcon
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.library.*
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorRepository
import io.github.cidy02.kudos.network.ao3.author.AO3UserStats
import io.github.cidy02.kudos.network.ao3.chapters.AO3ChapterRef
import io.github.cidy02.kudos.network.ao3.preferences.*
import io.github.cidy02.kudos.network.ao3.writing.recovery.WritingTextRecovery
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import io.github.cidy02.kudos.reader.ReaderSpeechSettingsContent
import io.github.cidy02.kudos.reader.speech.*
import io.github.cidy02.kudos.settings.*
import io.github.cidy02.kudos.ui.components.PageJumpContent
import io.github.cidy02.kudos.ui.subject.*
import io.github.cidy02.kudos.ui.theme.*
import io.github.cidy02.kudos.writing.*
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import java.text.DateFormat
import java.time.Instant
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** A98: inspect real content and theme-dependent paints; every read below is a fixture. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h2400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class BriefA98ContentTest {
    @get:Rule val compose = createComposeRule()
    @get:Rule val temporary = TemporaryFolder()
    private var mode by mutableStateOf(KudosThemeMode.Light)
    private var scale by mutableStateOf(1f)
    private lateinit var tokens: KudosTokens
    private lateinit var view: View
    private val themes = listOf(KudosThemeMode.Light, KudosThemeMode.Sepia, KudosThemeMode.Dark, KudosThemeMode.Oled)

    private fun show(content: @Composable () -> Unit) {
        compose.setContent {
            KudosTheme(mode, accentColorHex = "#7954B3") {
                tokens = LocalKudosTokens.current
                view = LocalView.current
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale),
                    LocalShellWashes provides remember { ShellWashes() }) {
                    Box(Modifier.fillMaxSize().background(tokens.background)) { content() }
                }
            }
        }
    }

    private fun layout(text: String): TextLayoutResult {
        val results = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText(text, useUnmergedTree = true)
            .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(results) }
        return results.single()
    }

    private fun assertPixel(expected: Color, point: Offset) {
        var actual = Color.Unspecified
        compose.runOnIdle {
            val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            view.draw(Canvas(bitmap))
            actual = Color(bitmap.getPixel(point.x.toInt(), point.y.toInt()))
            bitmap.recycle()
        }
        assertEquals(expected.red, actual.red, 0.012f)
        assertEquals(expected.green, actual.green, 0.012f)
        assertEquals(expected.blue, actual.blue, 0.012f)
    }

    @Test fun currentSpeedHasPrimaryInkNeutralFillAndRemainsDisabledInEveryThemeAndSize() {
        var rate by mutableStateOf(1f)
        show { ListeningSpeedPresets(rate) { rate = it } }
        for (theme in themes) for (fontScale in listOf(1f, 2f)) {
            compose.runOnIdle { mode = theme; scale = fontScale }
            val current = compose.onNodeWithText("1.0x (default)").assertIsNotEnabled()
            assertEquals(tokens.primaryInk, layout("1.0x (default)").layoutInput.style.color)
            val text = layout("1.0x (default)")
            assertFalse((0 until text.lineCount).any(text::isLineEllipsized))
            val bounds = current.fetchSemanticsNode().boundsInRoot
            assertPixel(tokens.glassFill(0.15).compositeOver(tokens.background), Offset(bounds.left + 4, bounds.center.y))
            assertEquals(tokens.scopePalette.accent, layout("0.9x").layoutInput.style.color)
        }
        compose.onNodeWithText("0.9x").performClick()
        compose.runOnIdle { assertEquals(0.9f, rate, 0f) }
        compose.onNodeWithText("0.9x").assertIsNotEnabled()
        compose.onNodeWithText("1.0x (default)").assertIsEnabled().performClick()
        compose.runOnIdle { assertEquals(1f, rate, 0f) }
    }

    @Test fun samplePickerUsesPrimaryInkNormallyAndAccentAtLargeTextOnBothListeningSurfaces() {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val store = PreferenceDataStoreFactory.create(scope = scope,
            produceFile = { temporary.root.resolve("listening.preferences_pb") })
        val repository = SettingsRepository(store)
        val service = SilentSpeechService()
        var inReader by mutableStateOf(false)
        try {
            show {
                if (inReader) ReaderSpeechSettingsContent({}, { frame ->
                    SettingsListeningContent(repository, service, false, VoicePackUi.fixed(false), frame)
                }) else SettingsListeningPage(repository, service)
            }
            for (reader in listOf(false, true)) for (theme in themes) for (fontScale in listOf(1f, 2f)) {
                compose.runOnIdle { inReader = reader; mode = theme; scale = fontScale }
                compose.onNodeWithText("Plain Narration").performScrollTo().assertIsDisplayed()
                assertEquals(if (fontScale == 1f) tokens.primaryInk else tokens.scopePalette.accent,
                    layout("Plain Narration").layoutInput.style.color)
                val text = layout("Plain Narration")
                assertFalse((0 until text.lineCount).any(text::isLineEllipsized))
                compose.onNodeWithText("1.0x (default)").performScrollTo().assertIsNotEnabled()
                assertEquals(tokens.primaryInk, layout("1.0x (default)").layoutInput.style.color)
            }
        } finally { scope.cancel() }
    }

    @Test fun jumpEndsUsePageInkAndOnlyStageTheChosenPage() {
        val picked = mutableListOf<Int>()
        var dismissed = false
        show { PageJumpContent(1, 3, { picked += it }, { dismissed = true },
            SubjectPalette.fromHue(0.47, tokens.theme)) }
        for (theme in themes) {
            compose.runOnIdle { mode = theme }
            compose.waitForIdle() // tokens is read below before layout() syncs; let the theme land first
            assertEquals(tokens.primaryInk, layout("Last (3)").layoutInput.style.color)
        }
        compose.onNodeWithText("Last (3)").performClick()
        compose.onNodeWithText("First page").assertIsEnabled()
        compose.runOnIdle { assertTrue(picked.isEmpty()); assertFalse(dismissed) }
        assertEquals(tokens.primaryInk, layout("First page").layoutInput.style.color)
        compose.onNodeWithContentDescription("Go to page 3").performClick()
        compose.runOnIdle { assertEquals(listOf(3), picked); assertTrue(dismissed) }
    }

    @Test fun libraryChoicesInheritTheSuppliedPaletteAndStillApplyLive() {
        var filters by mutableStateOf(LibraryFilterState())
        var sort by mutableStateOf(LibrarySort.Natural)
        var applied = false
        var pagePalette by mutableStateOf(false)
        show {
            LibraryFilterPanel(filters, sort, emptyList(), emptyList(), { filters = it }, { sort = it },
                { applied = true }, {}, {}, palette = if (pagePalette) SubjectPalette.fromHue(0.47, tokens.theme)
                    else tokens.scopePalette)
        }
        for (custom in listOf(false, true)) for (theme in themes) {
            compose.runOnIdle { mode = theme; pagePalette = custom }
            compose.waitForIdle() // expected reads tokens.theme: let the theme land first
            val expected = if (custom) SubjectPalette.fromHue(0.47, tokens.theme) else tokens.scopePalette
            assertEquals(expected.accent, layout("Default").layoutInput.style.color)
        }
        compose.onNodeWithText("Default").performClick()
        compose.onNodeWithText("Title", useUnmergedTree = true).performClick()
        compose.runOnIdle { assertEquals(LibrarySort.Title, sort) }
        compose.onNodeWithContentDescription("Done").performClick()
        compose.runOnIdle { assertTrue(applied) }
    }

    @Test fun challengeEditUsesTheTitlePaletteOrSlugFallbackAndPreservesKnownCountWithoutExtraReads() {
        val (auth, client, repository) = runBlocking { challengeEditSetup() }
        var title by mutableStateOf("Winter Exchange")
        show {
            AO3ChallengeSettingsEditScreen(client.slug, title, true, repository, client.writer(auth), {}, { _, _ -> }, {}, {},
                knownSignUpTotal = 4)
        }
        compose.waitUntil(20_000) { compose.onAllNodesWithText("Save changes").fetchSemanticsNodes().isNotEmpty() &&
            client.gets.size == client.openingReads.size }
        compose.onNodeWithText("Save changes").assertIsEnabled()
        for (name in listOf("Winter Exchange", "")) for (theme in themes) {
            compose.runOnIdle { title = name; mode = theme }
            val effective = name.ifEmpty { client.slug }
            compose.onNodeWithText("$effective · 4 sign-ups").assertExists()
            val expected = SubjectPalette.fromHue(HomeFacts.workHue(emptyList(), effective), tokens.theme)
            val bounds = compose.onNodeWithText("Save changes").fetchSemanticsNode().boundsInRoot
            assertPixel(expected.accent, Offset(bounds.left + 20, bounds.center.y))
        }
        assertEquals(client.openingReads, client.gets)
        assertTrue(client.sent.isEmpty())
    }

    @Test fun recoveryTimestampOmitsSecondsInDifferentLocalesAndKeepsTheCorrectInstant() {
        val oldLocale = Locale.getDefault()
        val oldZone = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("America/New_York"))
            val instant = Instant.parse("2026-10-23T02:57:49Z")
            val foundationSeconds = instant.epochSecond.toDouble() - 978_307_200
            for (locale in listOf(Locale.US, Locale.UK, Locale.JAPAN)) {
                Locale.setDefault(locale)
                val expected = DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date.from(instant))
                assertEquals(expected, recoveryDate(foundationSeconds))
                assertEquals("Seconds cannot affect the label", recoveryDate(foundationSeconds - 49), recoveryDate(foundationSeconds))
            }
        } finally { Locale.setDefault(oldLocale); TimeZone.setDefault(oldZone) }
    }

    @Test fun recoveryWarningFollowsTheSelectedCopiesOriginalDigestRatherThanItsEditedText() {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val store = WritingTextRecovery(temporary.newFolder().toPath())
        lateinit var session: WritingEditorSession
        show {
            val context = LocalContext.current
            session = remember { WritingEditorSession(WritingNativeTextField(context, "form"), "form", store,
                "Writer", "work:17", "content", scope, { 0L }, count = { 1 }) }
            WritingRecoverySheet(session, presentSheet = { _, content -> content() })
        }
        val warning = "The text on the form has changed since this copy began. Review the copy before restoring it."
        fun copy(original: String) = WritingTextRecovery.Copy(store.sessionURL(session.key),
            WritingTextRecovery.Entry("An edited recovery copy", WritingTextRecovery.digest(original), 0.0))
        try {
            runBlocking { session.opening.join(); session.selectRecovery(copy("older form")).join() }
            compose.onNodeWithText(warning).assertExists()
            runBlocking { session.selectRecovery(copy("form")).join() }
            compose.onNodeWithText(warning).assertDoesNotExist()
            compose.onNodeWithText("An edited recovery copy").assertExists()
        } finally { scope.cancel() }
    }

    @Test fun myWorksKeepsRealTotalsAndOrdersNewFilterSelectMore() {
        val setup = runBlocking { workFormSetup() }
        val source = FixtureSource { name -> io.github.cidy02.kudos.network.ao3.writing.workFixture(name).encodeToByteArray() }
        val demo = DemoWorkSaves()
        val client = object : AO3Client, AO3AuthenticatedClient {
            override fun username() = setup.auth.username()
            override fun sessionGeneration() = setup.auth.generation.value
            override suspend fun getAuthenticated(url: String) = get(url)
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
                val body = demo.answer(okhttp3.Request.Builder().url(url).build(), source, null)?.second
                    ?: DemoNetwork.webFixture(url.toHttpUrl(), source)?.decodeToString()
                    ?: error("Unbundled fixture: $url")
                return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(),
                    org.jsoup.Jsoup.parse(body).apply { select("img").remove() }.outerHtml()))
            }
            override suspend fun postAuthenticated(url: String, formFields: List<Pair<String, String>>,
                headers: Map<String, String>): AO3Result<AO3HttpResponse> = error("No writes expected")
        }
        val repository = AO3AuthorRepository(client, client, parseDispatcher = Dispatchers.Unconfined)
        val chrome = PushedShellChrome()
        show {
            CompositionLocalProvider(LocalPushedShellChrome provides chrome) {
                Column {
                    Row { chrome.trailingContent?.invoke(this) }
                    AuthorProfileScreen("AO3_Reader", initialTab = AuthorTab.Works, authorRepository = repository,
                        authRepository = setup.auth, onOpenAbout = {}, onOpenWork = {}, onNewWork = {})
                }
            }
        }
        compose.waitUntil(20_000) { compose.onAllNodesWithContentDescription("Select Works").fetchSemanticsNodes().isNotEmpty() }
        val bounds = listOf("New Work", "Sort and filter", "Select Works", "More").map {
            compose.onNodeWithContentDescription(it).assertIsDisplayed().fetchSemanticsNode().boundsInRoot
        }
        bounds.zipWithNext().forEach { (left, right) -> assertTrue(left.right <= right.left) }
        assertEquals("3 works · 248,400 words · 3,812 kudos", ownWorksLine("AO3_Reader", 3, AO3UserStats(wordCount = 248400, kudos = 3812)))
        assertEquals("AO3_Reader", ownWorksLine("AO3_Reader", null, AO3UserStats(wordCount = 248400)))
        assertEquals("1 work · AO3_Reader", ownWorksLine("AO3_Reader", 1, null))
    }

    @Test fun chapterRowsUseTheHollowOpenBookAndRemainSelectable() {
        assertEquals(Icons.Outlined.ImportContacts, chapterPickerBookIcon)
        val chapters = listOf(AO3ChapterRef(1L, 1, "1. Arrival"), AO3ChapterRef(2L, 2, "2. Departure"))
        var selected by mutableStateOf(chapters[0])
        show { ChapterPickerContent(chapters = chapters, selectedChapter = selected, isScopeAll = false,
            totalComments = 47, onSelectAll = {}, onSelectChapter = { selected = it }, palette = tokens.scopePalette) }
        compose.onNodeWithText(chapters[1].displayName).performClick()
        compose.runOnIdle { assertEquals(chapters[1], selected) }
    }

    @Test fun preferenceHelpTitleIsSemiboldWhileBodyRemainsRegularInEveryTheme() {
        val ref = AO3PreferenceHelpRef("Privacy", "https://archiveofourown.org/help/preferences")
        val content = AO3PreferenceHelpContent("Privacy", listOf(AO3PreferenceHelpEntry("Topic", "Help body")), "Footer", "")
        show { PreferenceHelpContent(ref, AO3Result.Success(content), {}, {}, {}) }
        for (theme in themes) {
            compose.runOnIdle { mode = theme }
            assertEquals(FontWeight.SemiBold, layout("Privacy").layoutInput.style.fontWeight)
            assertEquals(tokens.primaryInk, layout("Privacy").layoutInput.style.color)
            assertNotEquals(FontWeight.SemiBold, layout("Help body").layoutInput.style.fontWeight)
        }
    }

    private class SilentSpeechService : TTSService {
        override val status = MutableStateFlow(SpeechStatus.STOPPED)
        override val spokenText = MutableStateFlow("")
        override val availableVoices = MutableStateFlow(listOf(TTSVoice("0", "On device")))
        override suspend fun speak(text: String) = Unit
        override fun pause() = Unit
        override fun resume() = Unit
        override fun stop() = Unit
        override fun setVoice(id: String) = Unit
        override fun setRate(rate: Float) = Unit
        override fun setPitch(pitch: Float) = Unit
    }
}
