package io.github.cidy02.kudos.network.ao3.search

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.OkHttpAO3Client
import io.github.cidy02.kudos.network.ao3.writing.trimWritingTag
import io.github.cidy02.kudos.network.ao3.writing.AO3CollectionOffer
import io.github.cidy02.kudos.network.ao3.writing.AO3CollectionAccess
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.contentOrNull
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

    /** One first-page read, only when a fandom-scoped picker is opened. */
    suspend fun popularTags(fandom: String, kind: String): AO3Result<List<String>> {
        if (kind !in setOf("character", "relationship", "freeform") || fandom.isBlank())
            return AO3Result.Success(emptyList())
        val url = AO3SearchUrlBuilder().buildFandomWorksUrl(fandom, AO3SearchFilters())
            ?: return AO3Result.Success(emptyList())
        return when (val result = client.get(url)) {
            is AO3Result.Failure -> result
            is AO3Result.Success -> kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
                AO3Result.Success(parsePopularTags(result.value.body, kind))
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
        internal fun parsePopularTags(html: String, kind: String): List<String> {
            val field = when (kind) {
                "character" -> "character_ids"
                "relationship" -> "relationship_ids"
                "freeform" -> "freeform_ids"
                else -> return emptyList()
            }
            val target = "include_work_search[$field][]"
            return org.jsoup.Jsoup.parse(html).select("input[type=checkbox]").mapNotNull { input ->
                if (input.attr("name") != target) return@mapNotNull null
                val parent = input.parent() ?: return@mapNotNull null
                val label = if (parent.tagName() == "label") parent else {
                    val id = input.id()
                    parent.select("label").firstOrNull { id.isNotEmpty() && it.attr("for") == id }
                }
                label?.text()?.replace(Regex("\\s*\\(\\d[\\d,]*\\)\\s*$"), "")?.trim()?.takeIf { it.isNotEmpty() }
            }.distinct()
        }

        /**
         * iOS `parseEditorAutocomplete`: name then id; absent metadata means canonical, count
         * unknown. Field by field, so one odd row (a numeric id, a quoted boolean) costs only itself.
         */
        internal fun parseEditorAutocomplete(body: String): List<AO3EditorTag> =
            Json.parseToJsonElement(body).jsonArray.mapNotNull { element ->
                val row = element as? kotlinx.serialization.json.JsonObject ?: return@mapNotNull null
                fun text(key: String) = (row[key] as? kotlinx.serialization.json.JsonPrimitive)?.contentOrNull
                val name = trimWritingTag(text("name") ?: text("id").orEmpty())
                if (name.isEmpty()) null else AO3EditorTag(name,
                    (text("canonical") ?: text("is_canonical"))?.toBooleanStrictOrNull() ?: true,
                    (text("work_count") ?: text("count"))?.toIntOrNull())
            }
    }
}

/** Transient autocomplete metadata; not a stored work or a backup field. */
data class AO3EditorTag(val name: String, val isCanonical: Boolean = true, val workCount: Int? = null)
