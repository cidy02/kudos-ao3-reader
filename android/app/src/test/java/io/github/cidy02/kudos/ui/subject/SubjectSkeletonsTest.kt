package io.github.cidy02.kudos.ui.subject

import android.app.Application
import android.provider.Settings
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h2000dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SubjectSkeletonsTest {
    @get:Rule val compose = createComposeRule()

    @Test fun oneLoadingAnnouncementReplacesEveryDecorativeChild() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                SubjectSkeletonLoading("Loading works") {
                    Text("Pretend title must not be announced")
                    SubjectWorkRowSkeleton()
                }
            }
        }
        compose.onAllNodesWithContentDescription("Loading works").assertCountEquals(1)
        compose.onNodeWithContentDescription("Loading works").assertHasNoClickAction()
        compose.onNodeWithText("Pretend title must not be announced").assertDoesNotExist()
    }

    @Test fun textBlocksGrowAtTwoTimesTextAndStayInsideNarrowCardsInEveryTheme() {
        var theme by mutableStateOf(KudosThemeMode.Light)
        var fontScale by mutableFloatStateOf(1f)
        var height = 0
        var width = 0
        var available = 0
        compose.setContent {
            KudosTheme(theme) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale)) {
                    Box(Modifier.width(100.dp).onGloballyPositioned { available = it.size.width }) {
                        SubjectSkeletonLoading("Loading works") {
                            SubjectSkeletonBlock(17, 200, Modifier.onGloballyPositioned {
                                height = it.size.height
                                width = it.size.width
                            })
                        }
                    }
                }
            }
        }
        compose.waitForIdle()
        val originalHeight = height
        for (mode in listOf(KudosThemeMode.Light, KudosThemeMode.Dark, KudosThemeMode.Sepia, KudosThemeMode.Oled)) {
            compose.runOnIdle { theme = mode; fontScale = 2f }
            compose.waitForIdle()
            // Android 14 scales large text non-linearly (17sp at 2x is about 29sp), so not exactly double.
            assertTrue("$height vs $originalHeight", height * 2 >= originalHeight * 3)
            assertTrue(width <= available)
            compose.onAllNodesWithContentDescription("Loading works").assertCountEquals(1)
        }
    }

    @Test fun removeAnimationsStopsPulseIncludingWhenChangedWhileMounted() {
        val resolver = ApplicationProvider.getApplicationContext<Application>().contentResolver
        val oldScale = Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f)
        compose.mainClock.autoAdvance = false
        try {
            Settings.Global.putFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 0f)
            var alpha = 0f
            compose.setContent {
                alpha = subjectSkeletonAlpha()
                Text("alpha $alpha")
            }
            compose.waitForIdle()
            compose.mainClock.advanceTimeBy(500)
            compose.runOnIdle { assertEquals(0.85f, alpha, 0f) }
            compose.runOnIdle { Settings.Global.putFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) }
            compose.mainClock.advanceTimeByFrame()
            compose.waitForIdle()
            compose.mainClock.advanceTimeBy(300)
            var movingAlpha = 0f
            compose.runOnIdle { movingAlpha = alpha }
            compose.mainClock.advanceTimeBy(300)
            compose.runOnIdle { assertNotEquals(movingAlpha, alpha) }
            compose.runOnIdle { Settings.Global.putFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 0f) }
            compose.mainClock.advanceTimeByFrame()
            compose.waitForIdle()
            compose.mainClock.advanceTimeBy(2200)
            compose.runOnIdle { assertEquals(0.85f, alpha, 0f) }
        } finally {
            Settings.Global.putFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, oldScale)
        }
    }
}
