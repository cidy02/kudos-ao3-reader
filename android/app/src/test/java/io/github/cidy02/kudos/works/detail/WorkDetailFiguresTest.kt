package io.github.cidy02.kudos.works.detail

import io.github.cidy02.kudos.core.model.SavedWork
import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

class WorkDetailFiguresTest {
    // WorkOriginTests preservation assertions; no persisted fields added.
    @Test fun lastCopyRequiresAnEpub() {
        val work = SavedWork(title = "Deleted Fic", author = "A", dateAdded = Instant.ofEpochMilli(1000), ao3Unavailable = true)
        assertEquals("Last Copy", work.preservationBadge)
        assertEquals("Unavailable", work.copy(hasEpub = false).preservationBadge)
        assertNull(work.copy(ao3Unavailable = false).preservationBadge)
        assertNull(work.copy(ao3Unavailable = false, hasEpub = false).preservationBadge)
    }

    // BrowseAndWorkDetailRulesTests.workDetailPrefersTheFresherRemoteFigure.
    @Test fun fresherRemoteFiguresWinIncludingPrintedZero() {
        assertEquals(500, WorkDetailFigures.preferred(412, 500))
        assertEquals(412, WorkDetailFigures.preferred(412, null))
        assertNull(WorkDetailFigures.preferred(0, null))
        assertNull(WorkDetailFigures.preferred(null, null))
        assertEquals(0, WorkDetailFigures.preferred(0, 0))
        assertEquals(0, WorkDetailFigures.preferred(412, 0))
    }
}

class WorkCompletionImportTest {
    // WorkStatLabelTests.savedWorkCompletionStatusIsUnknownOnlyForNonAO3ImportsWithoutAStatedStatus.
    @Test fun nonAO3ImportsDoNotInventAnUnfinishedStatus() {
        val work = SavedWork(title = "Import", author = "A", dateAdded = Instant.ofEpochMilli(1000))
        assertNull(work.knownCompletion)
        assertEquals(WorkCompletionStatus.Unknown, WorkCompletionStatus.from(work.knownCompletion))
        assertEquals("Unknown", io.github.cidy02.kudos.ui.components.completionStatText(work.knownCompletion))
        assertEquals(false, work.copy(ao3WorkID = 123).knownCompletion)
        assertEquals(true, work.copy(ao3WorkID = 123, isComplete = true).knownCompletion)
        assertEquals(true, work.copy(isComplete = true).knownCompletion)
        assertEquals(false, work.copy(sourceUrl = "https://archiveofourown.org/works/123").knownCompletion)
        assertNull(work.copy(sourceUrl = "https://www.fanfiction.net/s/123/1/").knownCompletion)
    }
}
