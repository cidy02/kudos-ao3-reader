package io.github.cidy02.kudos.works

import android.app.Application
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import io.github.cidy02.kudos.core.model.CoverArtPreference
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.settings.SettingsAppearancePage
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.works.detail.WORK_DETAIL_COVER_SECTION_TAG
import io.github.cidy02.kudos.works.detail.WorkDetailCoverSection
import java.nio.file.Files
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h2200dp")
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

    @After
    fun tearDown() {
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
}
