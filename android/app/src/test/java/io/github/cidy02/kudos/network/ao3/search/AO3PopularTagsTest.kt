package io.github.cidy02.kudos.network.ao3.search

import io.github.cidy02.kudos.network.ao3.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.*
import org.junit.Test

class AO3PopularTagsTest {
    @Test fun parsesOnlyIncludedKindAndStripsOnlyTheTrailingNumericCount() {
        val html = """
            <label><input type="checkbox" name="include_work_search[character_ids][]">Luke (Young) (1,234)</label>
            <label><input type="checkbox" name="include_work_search[character_ids][]">Luke (Young) (1,234)</label>
            <label><input type="checkbox" name="exclude_work_search[character_ids][]">Excluded (8)</label>
            <label><input type="checkbox" name="include_work_search[freeform_ids][]">Fluff (22)</label>
            <div><input id="leia" type="checkbox" name="include_work_search[character_ids][]"><label for="leia">Leia (42)</label></div>
        """.trimIndent()
        assertEquals(listOf("Luke (Young)", "Leia"), AO3TagAutocompleteRepository.parsePopularTags(html, "character"))
        assertEquals(listOf("Fluff"), AO3TagAutocompleteRepository.parsePopularTags(html, "freeform"))
        assertEquals(emptyList<String>(), AO3TagAutocompleteRepository.parsePopularTags(html, "fandom"))
    }

    @Test fun oneFandomPageReadIsScopedEscapedAndCancellable() = runBlocking {
        val urls = mutableListOf<String>()
        var cancel = false
        val client = object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
                urls += url
                if (cancel) throw CancellationException("Closed picker")
                return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(),
                    "<label><input type='checkbox' name='include_work_search[relationship_ids][]'>A/B (9)</label>"))
            }
        }
        val repository = AO3TagAutocompleteRepository(client)
        assertEquals(listOf("A/B"), (repository.popularTags("A/B & C", "relationship") as AO3Result.Success).value)
        assertEquals(1, urls.size)
        assertTrue(urls.single().toHttpUrl().encodedPath.contains("A*s*B"))
        repository.popularTags("A/B & C", "fandom")
        repository.popularTags("", "character")
        assertEquals(1, urls.size)
        cancel = true
        try { repository.popularTags("A/B & C", "character"); fail("Cancellation must propagate") }
        catch (_: CancellationException) { }
    }
}
