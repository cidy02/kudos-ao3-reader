package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.works.detail.WorkCompletionStatus
import io.github.cidy02.kudos.works.detail.WorkStatRating
import io.github.cidy02.kudos.works.detail.WorkWarningStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkDetailLogicTest {

    @Test
    fun warningStatusClassification() {
        val none1 = WorkWarningStatus.from(emptyList())
        assertTrue(none1 is WorkWarningStatus.None)
        assertEquals("None", none1.figureText)

        val none2 = WorkWarningStatus.from(listOf("No Archive Warnings Apply"))
        assertTrue(none2 is WorkWarningStatus.None)
        assertEquals("None", none2.figureText)

        val undisclosed = WorkWarningStatus.from(listOf("Creator Chose Not To Use Archive Warnings"))
        assertTrue(undisclosed is WorkWarningStatus.Undisclosed)
        assertEquals("Undisclosed", undisclosed.figureText)

        val presentSingle = WorkWarningStatus.from(listOf("Major Character Death"))
        assertTrue(presentSingle is WorkWarningStatus.Present)
        assertEquals(1, (presentSingle as WorkWarningStatus.Present).count)
        assertEquals("1", presentSingle.figureText)

        val presentMultiple = WorkWarningStatus.from(listOf("Major Character Death", "Graphic Depictions Of Violence"))
        assertTrue(presentMultiple is WorkWarningStatus.Present)
        assertEquals(2, (presentMultiple as WorkWarningStatus.Present).count)
        assertEquals("2", presentMultiple.figureText)
    }

    @Test
    fun ratingLetterAndColor() {
        assertEquals("G", WorkStatRating.letter("General Audiences"))
        assertEquals("T", WorkStatRating.letter("Teen And Up Audiences"))
        assertEquals("M", WorkStatRating.letter("Mature"))
        assertEquals("E", WorkStatRating.letter("Explicit"))
        assertEquals("NR", WorkStatRating.letter("Not Rated"))
        assertEquals("—", WorkStatRating.letter(""))
        assertEquals("—", WorkStatRating.letter("   "))
        assertEquals("PG", WorkStatRating.letter("pg-13"))

        assertNotNull(WorkStatRating.color("General Audiences", isDark = false))
        assertNotNull(WorkStatRating.color("Teen And Up Audiences", isDark = true))
        assertNotNull(WorkStatRating.color("Teen And Up Audiences", isDark = false))
        assertNotNull(WorkStatRating.color("Mature", isDark = false))
        assertNotNull(WorkStatRating.color("Explicit", isDark = false))
        assertNotNull(WorkStatRating.color("Not Rated", isDark = false))
        assertNull(WorkStatRating.color("Unknown Rating", isDark = false))
    }

    @Test
    fun completionStatusClassification() {
        val complete = WorkCompletionStatus.from(true)
        assertEquals(WorkCompletionStatus.Complete, complete)
        assertEquals("Complete", complete.text)
        assertEquals("Complete", complete.shortText)

        val inProgress = WorkCompletionStatus.from(false)
        assertEquals(WorkCompletionStatus.InProgress, inProgress)
        assertEquals("In Progress", inProgress.text)
        assertEquals("WIP", inProgress.shortText)

        val unknown = WorkCompletionStatus.from(null)
        assertEquals(WorkCompletionStatus.Unknown, unknown)
        assertEquals("Unknown", unknown.text)
        assertEquals("Unknown", unknown.shortText)
    }
}
