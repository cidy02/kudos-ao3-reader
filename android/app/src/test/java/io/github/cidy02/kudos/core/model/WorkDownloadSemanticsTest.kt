package io.github.cidy02.kudos.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkDownloadSemanticsTest {
    @Test
    fun downloadedMeansAFileTheReaderChoseToKeep() {
        assertFalse(WorkDownloadSemantics.isDownloaded(true, false, false, true))
        assertTrue(WorkDownloadSemantics.isDownloaded(true, true, false, true))
        assertTrue(WorkDownloadSemantics.isDownloaded(true, false, true, true))
        assertTrue(WorkDownloadSemantics.isDownloaded(true, false, false, false))
        assertFalse(WorkDownloadSemantics.isDownloaded(false, true, true, false))
    }

    @Test
    fun actionsMatchIosKeepRules() {
        assertEquals(
            WorkDownloadAction.Download,
            WorkDownloadSemantics.action(true, false, true, null)
        )
        assertEquals(
            WorkDownloadAction.Download,
            WorkDownloadSemantics.action(false, false, true, null)
        )
        assertEquals(
            WorkDownloadAction.RemoveDownload,
            WorkDownloadSemantics.action(true, true, true, null)
        )
        assertEquals(
            WorkDownloadAction.KeptBy("Weekend"),
            WorkDownloadSemantics.action(true, true, true, "Weekend")
        )
        assertNull(WorkDownloadSemantics.action(true, true, false, null))
        assertNull(WorkDownloadSemantics.action(false, false, false, null))
    }
}
