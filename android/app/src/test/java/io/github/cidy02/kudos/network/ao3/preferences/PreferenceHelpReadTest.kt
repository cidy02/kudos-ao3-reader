package io.github.cidy02.kudos.network.ao3.preferences

import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Brief 3cj: a "?" on AO3 Preferences reads one AO3 help page, and nothing else. */
class PreferenceHelpReadTest {
    private class Client(private val page: AO3Result<AO3HttpResponse>) : AO3AuthenticatedClient {
        val gets = mutableListOf<String>()
        override fun username() = "reader"
        override fun sessionGeneration(): Int = 1
        override suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse> { gets += url; return page }
        override suspend fun postAuthenticated(
            url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>
        ): AO3Result<AO3HttpResponse> = error("help is read, never sent")
    }

    private val help = "https://archiveofourown.org/help/preferences_privacy"
    private fun page(body: String) = AO3Result.Success(AO3HttpResponse(help, 200, emptyMap(), body))

    @Test fun theTapReadsThatPageOnce() = runTest {
        val client = Client(page("<div id='main'><h4>Privacy Preferences</h4><dl id='help'><dt>A</dt><dd>B</dd></dl></div>"))
        val result = AO3PreferencesRepository(client).loadHelp(AO3PreferenceHelpRef("Privacy Preferences", help))
        assertEquals(listOf(AO3PreferenceHelpEntry("A", "B")), (result as AO3Result.Success).value.entries)
        assertEquals(listOf(help), client.gets)
    }

    @Test fun anAddressThatIsNotAnAO3HelpPageIsNotRead() = runTest {
        val client = Client(page("<div id='main'><p>x</p></div>"))
        val repository = AO3PreferencesRepository(client)
        for (url in listOf("https://example.org/help/preferences_privacy", "https://archiveofourown.org/users/reader/preferences",
            "https://archiveofourown.org/works?x=/help/")) {
            val result = repository.loadHelp(AO3PreferenceHelpRef("x", url))
            assertTrue(url, (result as AO3Result.Failure).error is AO3Error.Validation)
        }
        assertEquals(emptyList<String>(), client.gets)
    }

    @Test fun aFailedReadAndAnUnreadablePageAreFailuresToShow() = runTest {
        val down = Client(AO3Result.Failure(AO3Error.NotFound))
        assertEquals(AO3Error.NotFound,
            (AO3PreferencesRepository(down).loadHelp(AO3PreferenceHelpRef("x", help)) as AO3Result.Failure).error)
        val empty = Client(page("<div id='main'></div>"))
        assertTrue((AO3PreferencesRepository(empty).loadHelp(AO3PreferenceHelpRef("x", help)) as AO3Result.Failure).error
            is AO3Error.Parse)
    }
}
