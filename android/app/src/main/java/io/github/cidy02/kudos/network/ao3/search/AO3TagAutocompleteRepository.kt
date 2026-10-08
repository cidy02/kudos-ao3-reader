package io.github.cidy02.kudos.network.ao3.search

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.OkHttpAO3Client
import io.github.cidy02.kudos.network.ao3.writing.trimWritingTag
import io.github.cidy02.kudos.network.ao3.writing.AO3CollectionOffer
import io.github.cidy02.kudos.network.ao3.writing.AO3CollectionAccess
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

    /** Same autocomplete client/address builder, but AO3 posts the id (slug), not the display name. */
    suspend fun openCollections(term: String): AO3Result<List<AO3CollectionOffer>> {
        val trimmed = trimWritingTag(term)
        if (trimmed.isEmpty()) return AO3Result.Success(emptyList())
        return when (val result = client.get(autocompleteUrl("open_collection_names", trimmed))) {
            is AO3Result.Failure -> result
            is AO3Result.Success -> try {
                val rows = json.parseToJsonElement(result.value.body).jsonArray.mapNotNull { row ->
                    val id = row.jsonObject.getValue("id").jsonPrimitive
                    val display = row.jsonObject.getValue("name").jsonPrimitive
                    require(id.isString && display.isString) // iOS JSONDecoder's required String fields.
                    val name = trimWritingTag(id.content)
                    val title = display.content
                    if (name.isEmpty()) null else AO3CollectionOffer(name, title.removeSuffix(" ($name)"),
                        AO3CollectionAccess(isDescribed = false))
                }
                AO3Result.Success(rows)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                AO3Result.Failure(io.github.cidy02.kudos.network.ao3.AO3Error.Parse("Could not parse autocomplete response."))
            }
        }
    }

    private fun autocompleteUrl(kind: String, term: String) = AO3Constants.baseHttpUrl.newBuilder()
        .addPathSegment("autocomplete").addPathSegment(kind).addQueryParameter("term", term).build().toString()

    suspend fun autocomplete(kind: String, term: String, minimumTermLength: Int = 2): AO3Result<List<String>> {
        val trimmed = trimWritingTag(term)
        // Search filters retain their two-character gate; the writing picker, like iOS,
        // asks for any nonblank term. Both use this same address and parser.
        if (trimmed.isEmpty() || trimmed.length < minimumTermLength) return AO3Result.Success(emptyList())

        val url = autocompleteUrl(kind, trimmed)

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
