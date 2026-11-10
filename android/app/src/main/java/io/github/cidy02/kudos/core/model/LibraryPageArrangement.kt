package io.github.cidy02.kudos.core.model

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull

/** iOS `LibraryShelfID`: raw values are the backup ids. */
enum class LibraryShelf(val id: String, val title: String) {
    Favourites("favourites", "Favourites"),
    Collections("collections", "Collections"),
    Downloaded("downloaded", "Downloaded"),
    WantToRead("wantToRead", "Want to Read"),
    ReadingNow("readingNow", "Reading Now"),
    Finished("finished", "Finished"),
    Queues("queues", "Queues"),
    History("history", "History"),
    Imported("imported", "Imported");

    companion object {
        fun fromId(id: String): LibraryShelf? = entries.firstOrNull { it.id == id }
    }
}

const val LibraryStyleCarousel = "carousel"
const val LibraryStyleList = "list"

data class LibraryPageSection(val id: String, val style: String = LibraryStyleCarousel)

/**
 * iOS `LibraryPageArrangement` (backup key `settings.libraryPageArrangement`):
 * `{"sections":[{"id":"favourites","style":"carousel"}],"buttons":["wantToRead"]}`.
 *
 * Unlike iOS, an id this build does not know is kept (as a plain string), so an
 * iOS-only shelf survives an Android round trip. A data class: two layouts are equal
 * when their shelves are, never when their JSON text is (iOS 6cbed05c).
 */
data class LibraryPageArrangement(
    val sections: List<LibraryPageSection>,
    val buttons: List<String>
) {
    fun styleOf(id: String): String? = sections.firstOrNull { it.id == id }?.style

    fun removingFromPage(id: String): LibraryPageArrangement {
        if (sections.none { it.id == id }) return this
        return normalized(sections.filter { it.id != id }, buttons + id)
    }

    /** Put a button on the page, at the end, as a carousel. */
    fun addingToPage(id: String): LibraryPageArrangement {
        if (id !in buttons || styleOf(id) != null) return this
        return normalized(sections + LibraryPageSection(id, LibraryStyleCarousel), buttons.filter { it != id })
    }

    fun settingStyle(id: String, style: String): LibraryPageArrangement {
        if (sections.none { it.id == id }) return this
        return normalized(sections.map { if (it.id == id) it.copy(style = style) else it }, buttons)
    }

    fun movingSection(from: Int, to: Int): LibraryPageArrangement =
        normalized(sections.movedItem(from, to), buttons)

    fun movingButton(from: Int, to: Int): LibraryPageArrangement =
        normalized(sections, buttons.movedItem(from, to))

    fun toJson(): JsonObject = buildJsonObject {
        put("sections", buildJsonArray {
            sections.forEach { s ->
                add(buildJsonObject {
                    put("id", JsonPrimitive(s.id))
                    put("style", JsonPrimitive(s.style))
                })
            }
        })
        put("buttons", buildJsonArray { buttons.forEach { add(JsonPrimitive(it)) } })
    }

    companion object {
        /** Favourites, Collections, Downloaded as carousels; the rest are buttons. */
        val Default = LibraryPageArrangement(
            sections = listOf(LibraryShelf.Favourites, LibraryShelf.Collections, LibraryShelf.Downloaded)
                .map { LibraryPageSection(it.id) },
            buttons = listOf(
                LibraryShelf.WantToRead, LibraryShelf.ReadingNow, LibraryShelf.Finished,
                LibraryShelf.Queues, LibraryShelf.History, LibraryShelf.Imported
            ).map { it.id }
        )

        /**
         * iOS `partition`: each shelf is in exactly one list; a shelf in both stays a section;
         * a known shelf stored nowhere is appended to the buttons in enum order.
         */
        fun normalized(sections: List<LibraryPageSection>, buttons: List<String>): LibraryPageArrangement {
            val seen = HashSet<String>()
            val keptSections = sections.filter { seen.add(it.id) }
            val keptButtons = buttons.filter { seen.add(it) }.toMutableList()
            LibraryShelf.entries.forEach { if (seen.add(it.id)) keptButtons += it.id }
            return LibraryPageArrangement(keptSections, keptButtons)
        }

        /**
         * Null when [element] is not an arrangement (iOS: the throwing decode inside `try?`, so the
         * local layout stays). A present non-array list, a non-object section or a non-string style
         * is such a failure; a section with a missing or non-string id, or a non-string button, is
         * skipped as iOS's `FailableSection` / `FailableShelf` do.
         */
        fun fromJson(element: JsonElement?): LibraryPageArrangement? {
            val obj = element as? JsonObject ?: return null
            fun list(key: String): List<JsonElement>? = when (val v = obj[key]) {
                null, is JsonNull -> emptyList()
                is JsonArray -> v
                else -> null
            }
            val rawSections = list("sections") ?: return null
            val rawButtons = list("buttons") ?: return null
            val sections = mutableListOf<LibraryPageSection>()
            for (item in rawSections) {
                val o = item as? JsonObject ?: return null
                val style = when (val st = o["style"]) {
                    null, is JsonNull -> null
                    is JsonPrimitive -> if (st.isString) st.content else return null
                    else -> return null
                }
                val id = (o["id"] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull ?: continue
                sections += LibraryPageSection(id, style ?: LibraryStyleCarousel)
            }
            val buttons = rawButtons.mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.contentOrNull }
            return normalized(sections, buttons)
        }

        fun fromJsonString(raw: String?): LibraryPageArrangement? = raw?.let {
            runCatching { fromJson(kotlinx.serialization.json.Json.parseToJsonElement(it)) }.getOrNull()
        }
    }
}

/** Insert at a final index (not a gap index): the list shape a Move up/down action wants. */
private fun <T> List<T>.movedItem(from: Int, to: Int): List<T> {
    if (from !in indices || to !in indices || from == to) return this
    return toMutableList().also { it.add(to, it.removeAt(from)) }
}
