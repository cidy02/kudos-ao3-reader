package io.github.cidy02.kudos.account

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** iOS `SubscriptionWatermarkTests`: a row with no chapter count is not a count of zero (A59). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class SubscriptionWatermarksTest {
    private val context = ApplicationProvider.getApplicationContext<Application>()
    private fun work(id: Long, chapters: String = "") =
        AO3WorkSummary(id, "Work $id", listOf("someone"), emptyList(), "", emptyList(), emptyList(), chapters = chapters)

    @Test fun anEmptyChaptersStringIsNotAFirstSight() {
        val marks = SubscriptionWatermarks.baseline(context, "first-sight", listOf(work(4), work(5, "3/3")))
        assertNull(marks[4])
        assertEquals(3, marks[5]?.postedChapterCount)
    }

    @Test fun markingSeenDoesNotReplaceACountWithAnUnknownOne() {
        SubscriptionWatermarks.baseline(context, "mark-seen", listOf(work(4, "12/20")))
        val after = SubscriptionWatermarks.markAllSeen(context, "mark-seen", listOf(work(4)))
        assertEquals(12, after[4]?.postedChapterCount)
        assertEquals(2, SubscriptionWatermarks.newChapterCount(work(4, "14/20"), after))
    }
}
