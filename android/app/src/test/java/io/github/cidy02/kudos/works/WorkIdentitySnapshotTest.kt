package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.core.model.SavedWork
import org.junit.Assert.assertEquals
import org.junit.Test

/** iOS `WorkIdentityIndex`: a stored AO3 work ID identifies a work that has no URL (A52). */
class WorkIdentitySnapshotTest {
    @Test fun aStoredAO3IdFindsAWorkWithNoURL() {
        val local = SavedWork(id = "aaaaaaaa-0000-0000-0000-000000000001", title = "Local", author = "A", sourceUrl = "", ao3WorkID = 5150)
        val index = WorkIdentityIndex.snapshot(listOf(local))

        assertEquals(local, index.existingWork(ao3WorkId = 5150L, sourceUrl = "", recordId = "bbbbbbbb-0000-0000-0000-000000000002"))
    }
}
