package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.network.ao3.search.AO3TagAutocompleteRepository
import kotlinx.coroutines.runBlocking
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import org.junit.Assert.*
import org.junit.Test

class DemoTagAutocompleteTest {
    @Test fun canonicalAndCountAreParsedWhenPresent() {
        val tags = AO3TagAutocompleteRepository.parseEditorAutocomplete("""
            [{"id":"Hurt/Comfort","name":"Hurt/Comfort","canonical":true,"work_count":9001},
             {"id":"not a tag","name":"not a tag","canonical":false},
             {"id":"Alias","is_canonical":false,"count":0},
             {"name":"Names only"}]
        """.trimIndent())
        assertTrue(tags[0].isCanonical)
        assertEquals(9001, tags[0].workCount)
        assertFalse(tags[1].isCanonical)
        assertNull(tags[1].workCount)
        assertEquals("Alias", tags[2].name)
        assertFalse(tags[2].isCanonical)
        assertEquals(0, tags[2].workCount)
        assertTrue(tags[3].isCanonical)
        assertNull(tags[3].workCount)
    }

    @Test fun allFourAddressesShareLocalSeveralEmptyAndFailedAnswersWithoutSockets() = runBlocking {
        val http = OkHttpClient.Builder()
            .addInterceptor(DemoNetworkInterceptor(isActive = { true }, fixtures = { FixtureSource { null } }))
            .addInterceptor { throw AssertionError("Autocomplete demo attempted a socket") }.build()
        var reads = 0
        val local = object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
                reads++
                return http.newCall(Request.Builder().url(url).build()).execute().use { response ->
                    if (response.code == 403) AO3Result.Failure(AO3Error.Forbidden)
                    else AO3Result.Success(AO3HttpResponse(url, response.code, emptyMap(), response.body.string()))
                }
            }
        }
        val repository = AO3TagAutocompleteRepository(local)
        for (kind in listOf("fandom", "relationship", "character", "freeform")) {
            val result = repository.autocomplete(kind, "demo") as AO3Result.Success
            assertEquals(3, result.value.size)
            assertTrue(result.value.all { it.startsWith("Demo") })
            // The writing caller and search filters receive the very same answer.
            assertEquals(result.value, (repository.autocomplete(kind, "demo", minimumTermLength = 1) as AO3Result.Success).value)
            assertEquals(emptyList<String>(), (repository.autocomplete(kind, "none") as AO3Result.Success).value)
            assertEquals(AO3Result.Failure(AO3Error.Forbidden), repository.autocomplete(kind, "fail"))
        }
        assertEquals(16, reads)
        // Preserve the existing search picker gate; permit a single settled letter for writing.
        assertEquals(emptyList<String>(), (repository.autocomplete("freeform", "x") as AO3Result.Success).value)
        assertEquals(16, reads)
        repository.autocomplete("freeform", "x", minimumTermLength = 1)
        assertEquals(17, reads)
        repository.autocomplete("freeform", "")
        assertEquals(17, reads)
    }

    @Test fun sharedParserReturnsOnlyNamesAndNeverFetchesWorkCounts() = runBlocking {
        val urls = mutableListOf<String>()
        val client = object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
                urls.add(url)
                return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(),
                    """[{"id":"not the name","name":"A & 星","work_count":10,"canonical":false}]"""))
            }
        }
        val names = (AO3TagAutocompleteRepository(client).autocomplete("relationship", " A & 星 ") as AO3Result.Success).value
        assertEquals(listOf("A & 星"), names)
        assertEquals(1, urls.size)
        assertEquals("/autocomplete/relationship", urls.single().toHttpUrl().encodedPath)
        assertEquals("A & 星", urls.single().toHttpUrl().queryParameter("term"))
    }
}
