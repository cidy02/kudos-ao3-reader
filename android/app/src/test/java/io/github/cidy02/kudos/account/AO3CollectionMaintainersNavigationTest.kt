package io.github.cidy02.kudos.account

import android.app.Application
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import io.github.cidy02.kudos.app.Routes
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class AO3CollectionMaintainersNavigationTest {
    @get:Rule val compose = createComposeRule()

    @Test fun actualManageRowCallsNativeMaintainersDestinationAndNeverTheBrowserOrOtherActions() {
        val routes = mutableListOf<String>()
        compose.setContent {
            KudosTheme(themeMode = KudosThemeMode.Light) {
                CollectionManageRow("Maintainers", "https://archiveofourown.org/collections/winter_exchange/participants",
                    onOpenModeration = { error("Wrong moderation destination") },
                    onOpenSettings = { error("Wrong settings destination") },
                    onOpenMaintainers = { routes += Routes.ao3CollectionMaintainers("winter_exchange", "Winter Exchange 2026") },
                    onOpenWebFallback = { error("Maintainers opened the browser") })
            }
        }
        compose.onNodeWithText("Maintainers").performClick()
        compose.runOnIdle {
            assertEquals(listOf("ao3-collection-maintainers/winter_exchange?title=Winter%20Exchange%202026"), routes)
            assertEquals("Maintainers", Routes.titleFor(Routes.AO3CollectionMaintainers))
            assertTrue(Routes.hasSubjectHeader(routes.single()))
            assertTrue(Routes.hidesTabBar(routes.single()))
            assertEquals("ao3-collection-maintainers/a%2Fb?title=Snow%20%26%20Stars", Routes.ao3CollectionMaintainers("a/b", "Snow & Stars"))
        }
    }
}
