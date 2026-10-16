package io.github.cidy02.kudos.works.detail

import io.github.cidy02.kudos.core.model.SavedWork
import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

class WorkDetailPresentationTest {
    // WorkDetailPresentationTests.postRemovalActionRoutesByDeletionAndSource.
    @Test fun postRemovalActionRoutesByDeletionAndSource() {
        assertEquals(WorkDetailPresentation.PostRemovalAction.KeepLocal, WorkDetailPresentation.postRemovalAction(false, true))
        assertEquals(WorkDetailPresentation.PostRemovalAction.KeepLocal, WorkDetailPresentation.postRemovalAction(false, false))
        assertEquals(WorkDetailPresentation.PostRemovalAction.ShowRemote, WorkDetailPresentation.postRemovalAction(true, true))
        assertEquals(WorkDetailPresentation.PostRemovalAction.Dismiss, WorkDetailPresentation.postRemovalAction(true, false))
    }

    @Test fun summaryFromLocalRequiresAO3Identity() {
        val work = SavedWork(title = "T", author = "A", dateAdded = Instant.ofEpochMilli(1000))
        assertNull(WorkDetailPresentation.summaryFromLocal(work.copy(sourceUrl = "file:///tmp/x.epub")))
        assertEquals(99L, WorkDetailPresentation.summaryFromLocal(work.copy(ao3WorkID = 99))?.id)
        assertEquals(99L, WorkDetailPresentation.summaryFromLocal(work.copy(sourceUrl = "https://archiveofourown.org/works/99"))?.id)
    }

    @Test fun queueAndCollectionLabelsPluralize() {
        assertEquals("Add to Queue", WorkDetailPresentation.queueLabel(0))
        assertEquals("In 1 Queue", WorkDetailPresentation.queueLabel(1))
        assertEquals("In 2 Queues", WorkDetailPresentation.queueLabel(2))
        assertEquals("In 3 Queues", WorkDetailPresentation.queueLabel(3))
        assertEquals("Add to Collection", WorkDetailPresentation.collectionLabel(0))
        assertEquals("In 1 Collection", WorkDetailPresentation.collectionLabel(1))
        assertEquals("In 2 Collections", WorkDetailPresentation.collectionLabel(2))
    }
}
