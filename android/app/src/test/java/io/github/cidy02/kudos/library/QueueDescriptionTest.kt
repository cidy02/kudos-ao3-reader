package io.github.cidy02.kudos.library

import android.app.Application
import android.content.Context
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performTextInput
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import kotlinx.coroutines.runBlocking
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** A queue's description is kept as it is typed, without the field ever losing focus (3dy). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h2400dp")
class QueueDescriptionTest {
    @get:Rule val compose = createComposeRule()
    private val database = Room.inMemoryDatabaseBuilder(
        ApplicationProvider.getApplicationContext<Context>(), KudosDatabase::class.java
    ).allowMainThreadQueries().build()

    // No @After close: it runs before the compose rule disposes the screen, whose reload can
    // still be reading. The database is in memory.

    @Test fun typedDescriptionIsSavedBeforeTheFieldLosesFocus() {
        val repository = ReadingQueueRepository(database)
        val queue = runBlocking { repository.createQueue("Neon reread") }
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                CompositionLocalProvider(LocalPushedShellChrome provides PushedShellChrome()) {
                    QueueSettingsScreen(queue.id, repository)
                }
            }
        }
        compose.waitUntil(5_000) {
            compose.onAllNodes(androidx.compose.ui.test.hasContentDescription("Description"))
                .fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithContentDescription("Description").performTextInput("Night bus reads")
        compose.waitUntil(5_000) { runBlocking { repository.getQueue(queue.id)?.notes } == "Night bus reads" }
    }
}
