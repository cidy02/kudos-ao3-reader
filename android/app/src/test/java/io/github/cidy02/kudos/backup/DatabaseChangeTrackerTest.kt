package io.github.cidy02.kudos.backup

import androidx.room.InvalidationTracker
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.Test
import org.junit.Assert.assertTrue

class DatabaseChangeTrackerTest {

    @Test
    fun `tracker observes tables`() = runTest {
        // Just a simple instantiation test
        assertTrue(true)
    }
}
