package io.github.cidy02.kudos.network.ao3.search

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.OkHttpAO3Client
import io.github.cidy02.kudos.network.ao3.writing.trimWritingTag
import io.github.cidy02.kudos.network.ao3.writing.AO3CollectionOffer
import io.github.cidy02.kudos.network.ao3.writing.AO3CollectionAccess
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Live tag search via AO3's autocomplete endpoints.
 * Retains optional canonical/count metadata without making additional requests.
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

    suspend fun autocomplete(kind: String, term: String, minimumTermLength: Int = 2): AO3Result<List<String>> =
        when (val result = editorAutocomplete(kind, term, minimumTermLength)) {
            is AO3Result.Success -> AO3Result.Success(result.value.map { it.name })
            is AO3Result.Failure -> result
        }

    suspend fun editorAutocomplete(kind: String, term: String, minimumTermLength: Int = 1): AO3Result<List<AO3EditorTag>> {
        val trimmed = trimWritingTag(term)
        // Search keeps its two-character gate; writing asks for any nonblank term.
        if (trimmed.isEmpty() || trimmed.length < minimumTermLength) return AO3Result.Success(emptyList())
        return when (val result = client.get(autocompleteUrl(kind, trimmed))) {
            is AO3Result.Failure -> result
            is AO3Result.Success -> try {
                AO3Result.Success(parseEditorAutocomplete(result.value.body))
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                AO3Result.Failure(io.github.cidy02.kudos.network.ao3.AO3Error.Parse("Could not parse autocomplete response."))
            }
        }
    }

    companion object {
        /** iOS `parseEditorAutocomplete`: name then id; absent metadata means canonical, count unknown. */
        internal fun parseEditorAutocomplete(body: String): List<AO3EditorTag> =
            Json { ignoreUnknownKeys = true }.decodeFromString<List<TagRow>>(body).mapNotNull { row ->
                val name = trimWritingTag(row.name ?: row.id.orEmpty())
                if (name.isEmpty()) null else AO3EditorTag(name,
                    row.canonical ?: row.is_canonical ?: true, row.work_count ?: row.count)
            }
    }

    @Serializable
    private data class TagRow(
        val id: String? = null,
        val name: String? = null,
        val canonical: Boolean? = null,
        val is_canonical: Boolean? = null,
        val work_count: Int? = null,
        val count: Int? = null
    )
}

/** Transient autocomplete metadata; not a stored work or a backup field. */
data class AO3EditorTag(val name: String, val isCanonical: Boolean = true, val workCount: Int? = null)
