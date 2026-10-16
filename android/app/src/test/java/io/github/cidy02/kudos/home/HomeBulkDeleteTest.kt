package io.github.cidy02.kudos.home

import android.app.Application
import android.content.Context
import androidx.compose.foundation.layout.Column
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.works.WorkRepository
import java.nio.file.Files
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class)
class HomeBulkDeleteTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var database: KudosDatabase
    private lateinit var works: WorkRepository
    private val directory = Files.createTempDirectory("home-bulk-delete")

    @Before fun setUp() {
        database = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),
            KudosDatabase::class.java).allowMainThreadQueries().build()
        works = WorkRepository(database, WorkFileStore(directory))
    }

    @After fun tearDown() { database.close(); directory.toFile().deleteRecursively() }

    @Test fun oneWorkSelectedStillAsksWithConfirmationSettingOffAndCancelRetainsIt() {
        val work = runBlocking { works.upsert(SavedWork(title = "Keep me", author = "A", isSaved = true)) }
        val controller = HomeWorkController()
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                Column {
                    HomeBulkBar(listOf(work), controller, works, null, null, onDone = {})
                    HomeWorkDialogs(controller, works, null, confirmBeforeDelete = false, onDeleted = {})
                }
            }
        }
        compose.onNodeWithText("Delete").performClick()
        compose.onNodeWithText("Delete this work?").assertExists()
        assertFalse(runBlocking { works.getWork(work.id)!!.isDeleted })
        compose.onNodeWithText("Cancel").performClick()
        compose.onNodeWithText("Delete this work?").assertDoesNotExist()
        assertFalse(runBlocking { works.getWork(work.id)!!.isDeleted })
    }
}
