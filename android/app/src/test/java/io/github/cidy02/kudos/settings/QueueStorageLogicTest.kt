package io.github.cidy02.kudos.settings

import io.github.cidy02.kudos.core.model.SavedWork
import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.UUID

class QueueStorageLogicTest {
    @Test
    fun testGroupingLogic() {
        val work1 = SavedWork(
            id = UUID.randomUUID().toString(),
            title = "Work 1",
            author = "Author 1",
            isQueuedForLater = true,
            isSaved = true,
            hasEpub = true
        )
        val work2 = SavedWork(
            id = UUID.randomUUID().toString(),
            title = "Work 2",
            author = "Author 2",
            isQueuedForLater = true,
            isSaved = false,
            isFavorite = false,
            hasEpub = true
        )
        val work3 = SavedWork(
            id = UUID.randomUUID().toString(),
            title = "Work 3",
            author = "Author 3",
            isQueuedForLater = true,
            hasEpub = false
        )
        val work4 = SavedWork(
            id = UUID.randomUUID().toString(),
            title = "Work 4",
            author = "Author 4",
            isQueuedForLater = false,
            hasEpub = true
        )
        
        val works = listOf(work1, work2, work3, work4)
        
        val queued = QueueStorageLogic.queuedWorks(works)
        assertEquals(3, queued.size)
        
        val queueOnly = QueueStorageLogic.queueOnlyWorks(queued)
        assertEquals(2, queueOnly.size) // work2 and work3 (wait, work3 has isSaved=false, so it is queue only)
        
        // work1 exists, work2 does not exist, work3 has no epub, work4 not queued
        val preserved = QueueStorageLogic.preservedWorks(queued) { id ->
            id == work1.id || id == work3.id // fileExists returns true for work1 and work3
        }
        
        assertEquals(1, preserved.size) // Only work1 is queued, hasEpub=true, and exists
        assertEquals(work1.id, preserved[0].id)
    }
}
