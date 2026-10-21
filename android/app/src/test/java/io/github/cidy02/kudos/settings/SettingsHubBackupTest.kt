package io.github.cidy02.kudos.settings

import android.app.Application
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Settings › Backup opens the exporter in one tap. It does not push a second Backup page. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h4000dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SettingsHubBackupTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun backupRowOpensTheExporterAndDoesNotPushASecondPage() {
        val opened = mutableIntStateOf(0)
        val route = mutableStateOf("hub")
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                CompositionLocalProvider(LocalPushedShellChrome provides remember { PushedShellChrome() }) {
                    val nav = rememberNavController()
                    val entry by nav.currentBackStackEntryAsState()
                    route.value = entry?.destination?.route ?: "hub"
                    NavHost(navController = nav, startDestination = "hub") {
                        composable("hub") {
                            SettingsHubScreen(
                                navController = nav,
                                settings = KudosSettings.Defaults,
                                authRepository = null,
                                onOpenBackup = { opened.intValue += 1 }
                            )
                        }
                        // The old second page. A tap that still navigates here fails the route check.
                        composable("backup") { }
                    }
                }
            }
        }
        compose.onNodeWithText("Backup").performClick()
        compose.waitForIdle()
        assertEquals(1, opened.intValue)
        assertEquals("hub", route.value)
    }
}
