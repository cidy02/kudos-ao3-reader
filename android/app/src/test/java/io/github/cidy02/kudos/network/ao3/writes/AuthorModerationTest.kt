package io.github.cidy02.kudos.network.ao3.writes

import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorModerationKind
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorWebAction
import java.io.File
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Mute and Block on an author's page: AO3's confirm page read on the tap, its form sent once. */
class AuthorModerationTest {
    private fun fixture(name: String): String = listOf("src/debug/assets", "app/src/debug/assets", "android/app/src/debug/assets")
        .map { File(it, "fixtures/$name.html") }.first { it.exists() }.readText()

    private class Session(private val page: String) : AO3AuthenticatedClient {
        var name: String? = "reader"
        var generation = 1
        val gets = mutableListOf<String>()
        val posts = mutableListOf<Triple<String, List<Pair<String, String>>, Map<String, String>>>()
        var reply = "<div class='flash notice'>You have blocked the user Avery_Archive.</div>"
        override fun username() = name
        override fun sessionGeneration(): Int = generation
        override suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse> {
            gets += url
            return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), page))
        }
        override suspend fun postAuthenticated(
            url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>
        ): AO3Result<AO3HttpResponse> {
            posts += Triple(url, formFields, headers)
            return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), reply))
        }
    }

    private val blockPage = "https://archiveofourown.org/users/Avery_Archive/blocked/confirm"
    private val block = AO3AuthorWebAction("Block", blockPage, AO3AuthorWebAction.Kind.Block)
    private val mute = AO3AuthorWebAction("Mute", "https://archiveofourown.org/users/Avery_Archive/muted/confirm",
        AO3AuthorWebAction.Kind.Mute)
    private val parser = AO3WriteFormParser()

    @Test fun theConfirmPageIsReadAsAO3WroteIt() {
        val form = parser.parseAuthorModerationForm(fixture("ao3_author_confirm_block"), blockPage,
            AO3AuthorWebAction.Kind.Block, "Avery_Archive")!!
        assertEquals(AO3AuthorModerationKind.Block, form.kind)
        assertEquals("Block Avery_Archive", form.title)
        assertEquals("Yes, Block User", form.submitLabel)
        assertEquals("Cancel", form.cancelLabel)
        assertEquals("https://archiveofourown.org/users/me/blocked/users?blocked_id=Avery_Archive", form.actionUrl)
        assertEquals(listOf("authenticity_token" to "moderation-csrf-token", "blocked_id" to "Avery_Archive",
            "commit" to "Yes, Block User"), form.fields)
        assertEquals("moderation-csrf-token", form.csrfToken)
        // AO3's notice, its two lists kept as lists.
        val paragraphs = form.message.split("\n\n")
        assertEquals("Are you sure you want to block Avery_Archive? Blocking a user prevents them from:", paragraphs[0])
        assertEquals(3, paragraphs[1].lines().size)
        assertTrue(paragraphs[1].lines().all { it.startsWith("• ") })
        assertEquals("Blocking a user will not:", paragraphs[2])
        assertTrue(paragraphs.last().startsWith("To hide a user's works"))
    }

    @Test fun anUndoIsKnownByItsFormAndAPageWithoutTheFormGivesNone() {
        val unmute = parser.parseAuthorModerationForm(fixture("ao3_author_confirm_unmute"), mute.url,
            AO3AuthorWebAction.Kind.Mute, "Avery_Archive")!!
        assertEquals(AO3AuthorModerationKind.Unmute, unmute.kind)
        assertTrue(unmute.kind.isUndo)
        assertEquals("Yes, Unmute User", unmute.submitLabel)
        assertTrue("_method" to "delete" in unmute.fields)
        assertEquals(AO3AuthorModerationKind.Mute, parser.parseAuthorModerationForm(fixture("ao3_author_confirm_mute"),
            mute.url, AO3AuthorWebAction.Kind.Mute, "Avery_Archive")!!.kind)

        assertNull(parser.parseAuthorModerationForm("<meta name='csrf-token' content='t'><form action='/x'></form>",
            blockPage, AO3AuthorWebAction.Kind.Block, "Avery_Archive"))
        assertNull("only a mute or a block has such a page", parser.parseAuthorModerationForm(
            fixture("ao3_author_confirm_block"), blockPage, AO3AuthorWebAction.Kind.Profile, "Avery_Archive"))
    }

    @Test fun theTapReadsThePageOnceAndChangesNothing() = runTest {
        val session = Session(fixture("ao3_author_confirm_block"))
        val form = (AO3WriteRepository(session).loadAuthorModerationForm(block, "Avery_Archive", 1) as AO3Result.Success).value
        assertEquals(AO3AuthorModerationKind.Block, form.kind)
        assertEquals(listOf(blockPage), session.gets)
        assertTrue(session.posts.isEmpty())
    }

    @Test fun aO3sRefusalOnThePageIsWhatIsReported() = runTest {
        val session = Session(fixture("ao3_author_confirm_block_rejected"))
        val result = AO3WriteRepository(session).loadAuthorModerationForm(block, "Avery_Archive", 1)
        assertEquals(AO3Error.Validation("Sorry, you can't block an official user."), (result as AO3Result.Failure).error)
    }

    @Test fun anotherSessionASignedOutReaderOrAnotherSiteAsksNothing() = runTest {
        val session = Session(fixture("ao3_author_confirm_block"))
        val writes = AO3WriteRepository(session)
        try { writes.loadAuthorModerationForm(block, "Avery_Archive", 2); fail("another session's tap must stop") }
        catch (_: CancellationException) { }
        session.name = null
        assertEquals(AO3Error.AuthenticationRequired,
            (writes.loadAuthorModerationForm(block, "Avery_Archive", 1) as AO3Result.Failure).error)
        session.name = "reader"
        assertTrue((writes.loadAuthorModerationForm(block.copy(url = "https://example.org/users/x/blocked/confirm"),
            "Avery_Archive", 1) as AO3Result.Failure).error is AO3Error.Validation)
        assertTrue((writes.loadAuthorModerationForm(block.copy(kind = AO3AuthorWebAction.Kind.Profile),
            "Avery_Archive", 1) as AO3Result.Failure).error is AO3Error.Validation)
        assertEquals(emptyList<String>(), session.gets)
    }

    @Test fun confirmingSendsThePagesOwnFormOnceWithoutReadingAgain() = runTest {
        val session = Session(fixture("ao3_author_confirm_block"))
        val writes = AO3WriteRepository(session)
        val form = (writes.loadAuthorModerationForm(block, "Avery_Archive", 1) as AO3Result.Success).value
        val result = writes.submitAuthorModeration(form, 1)
        assertEquals("Blocked.", (result as AO3Result.Success).value.message)
        assertEquals(AO3WriteActionKind.Moderation, result.value.kind)
        assertEquals("the page read on the tap is the only read", listOf(blockPage), session.gets)
        val (url, fields, headers) = session.posts.single()
        assertEquals(form.actionUrl, url)
        assertEquals(form.fields, fields)
        assertEquals(blockPage, headers["Referer"])
    }

    @Test fun aFormFromAnotherSessionIsNotSentAndAnUnconfirmedReplyIsNotASuccess() = runTest {
        val session = Session(fixture("ao3_author_confirm_unmute"))
        val writes = AO3WriteRepository(session)
        val form = (writes.loadAuthorModerationForm(mute, "Avery_Archive", 1) as AO3Result.Success).value
        try { writes.submitAuthorModeration(form, 2); fail("another session's form must not be sent") }
        catch (_: CancellationException) { }
        assertTrue(session.posts.isEmpty())

        session.reply = "<html><body>Something else.</body></html>"
        assertTrue(writes.submitAuthorModeration(form, 1) is AO3Result.Failure)
        assertEquals("one POST, never a second", 1, session.posts.size)
        assertFalse(session.posts.single().second.any { it.first == "muted_id" })

        session.reply = "<div class='flash notice'>You have unmuted the user Avery_Archive.</div>"
        assertEquals("Unmuted.", (writes.submitAuthorModeration(form, 1) as AO3Result.Success).value.message)
    }
}
