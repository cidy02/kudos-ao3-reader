package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.network.ao3.chapters.AO3ChapterIndexRepository
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Audit A28-4: the chapter index was always read without the session, so a work only registered
 * users may see refused it and the reader's comments button stayed on "All comments".
 */
class AO3ChapterIndexRepositoryTest {
    private val page = AO3HttpResponse("https://archiveofourown.org/works/123/navigate", 200, emptyMap(),
        "<ol class='chapter index group'><li><a href='/works/123/chapters/1001'>1. One</a></li>" +
            "<li><a href='/works/123/chapters/1002'>2. Two</a></li></ol>")

    private class Anonymous(private val answer: AO3Result<AO3HttpResponse>) : AO3Client {
        var reads = 0
        override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> { reads++; return answer }
    }
    private class Session(var name: String?, var generation: Int, var answer: AO3Result<AO3HttpResponse>) : AO3AuthenticatedClient {
        val reads = mutableListOf<String>()
        override fun username() = name
        override fun sessionGeneration() = generation
        override suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse> { reads += url; return answer }
        override suspend fun postAuthenticated(url: String, formFields: List<Pair<String, String>>,
            headers: Map<String, String>): AO3Result<AO3HttpResponse> = error("The index never writes")
    }

    @Test
    fun `a signed-in reader's index is read once in their session and never without it`() = runBlocking<Unit> {
        val anonymous = Anonymous(AO3Result.Failure(AO3Error.AuthenticationRequired))
        val session = Session("alice", 4, AO3Result.Success(page))
        val repository = AO3ChapterIndexRepository(anonymous, session)

        assertEquals(1002L, repository.chapterForPosition(123, 2)?.chapterId)
        assertEquals(1001L, repository.chapterForPosition(123, 1)?.chapterId)
        assertEquals(listOf("https://archiveofourown.org/works/123/navigate"), session.reads)
        assertEquals(0, anonymous.reads)

        // A refusal is the answer: it is not asked again without the session.
        session.generation = 5
        session.answer = AO3Result.Failure(AO3Error.Forbidden)
        assertNull(repository.chapterForPosition(123, 2))
        assertEquals(2, session.reads.size)
        assertEquals(0, anonymous.reads)
    }

    @Test
    fun `what one session was shown is not served to the next, nor to a signed-out reader`() = runBlocking<Unit> {
        val anonymous = Anonymous(AO3Result.Failure(AO3Error.AuthenticationRequired))
        val session = Session("alice", 4, AO3Result.Success(page))
        val repository = AO3ChapterIndexRepository(anonymous, session)
        assertEquals(2, (repository.chapters(123) as AO3Result.Success).value.size)

        session.name = null // signed out: one read without a session, and its refusal stands
        assertEquals(AO3Result.Failure(AO3Error.AuthenticationRequired), repository.chapters(123))
        assertEquals(1, anonymous.reads)
        assertEquals(1, session.reads.size)

        session.name = "bob"; session.generation = 6 // another account reads for itself
        assertEquals(2, (repository.chapters(123) as AO3Result.Success).value.size)
        assertEquals(2, session.reads.size)
    }
}
