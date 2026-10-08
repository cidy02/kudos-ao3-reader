package io.github.cidy02.kudos.network.ao3.search

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.OkHttpAO3Client
import io.github.cidy02.kudos.network.ao3.writing.trimWritingTag
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Live tag search via AO3's autocomplete endpoints.
 * Returns canonical tag strings for the given term and category.
 */
class AO3TagAutocompleteRepository(
    private val client: AO3Client = OkHttpAO3Client()
) {
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun autocomplete(kind: String, term: String, minimumTermLength: Int = 2): AO3Result<List<String>> {
        val trimmed = trimWritingTag(term)
        // Search filters retain their two-character gate; the writing picker, like iOS,
        // asks for any nonblank term. Both use this same address and parser.
        if (trimmed.isEmpty() || trimmed.length < minimumTermLength) return AO3Result.Success(emptyList())

        val url = AO3Constants.baseHttpUrl.newBuilder()
            .addPathSegment("autocomplete")
            .addPathSegment(kind)
            .addQueryParameter("term", trimmed)
            .build()
            .toString()

        return when (val result = client.get(url)) {
            is AO3Result.Failure -> result
            is AO3Result.Success -> {
                runCatching {
                    val root = json.parseToJsonElement(result.value.body).jsonArray
                    val tags = root.mapNotNull { 
                        it.jsonObject["name"]?.jsonPrimitive?.content 
                    }
                    AO3Result.Success(tags)
                }.getOrElse { 
                    if (it is CancellationException) throw it
                    AO3Result.Failure(io.github.cidy02.kudos.network.ao3.AO3Error.Parse("Could not parse autocomplete response."))
                }
            }
        }
    }
}
