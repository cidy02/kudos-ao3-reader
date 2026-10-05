package io.github.cidy02.kudos.comments

import io.github.cidy02.kudos.network.ao3.AO3Error
import org.junit.Assert.assertEquals
import org.junit.Test

class CommentsReadErrorMessagesTest {
    @Test
    fun readerCommentsDestinationUsesIosAccessAndOfflineWords() {
        assertEquals("Log in to AO3 to do that.", commentsReadErrorMessage(AO3Error.AuthenticationRequired))
        assertEquals("AO3 declined the request. The work may be restricted to logged-in users.",
            commentsReadErrorMessage(AO3Error.Forbidden))
        assertEquals("AO3 couldn't find these comments — the work may be hidden or deleted.",
            commentsReadErrorMessage(AO3Error.NotFound))
        assertEquals("AO3 is asking for a pause. Please try again in a moment.",
            commentsReadErrorMessage(AO3Error.RateLimited(null)))
        assertEquals("You're offline. Comments will load when you're back online.",
            commentsReadErrorMessage(AO3Error.Network("offline", offline = true)))
    }
}
