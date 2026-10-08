package io.github.cidy02.kudos.writing

import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.search.AO3TagAutocompleteRepository
import io.github.cidy02.kudos.network.ao3.writing.AO3WorkForm
import io.github.cidy02.kudos.network.ao3.writing.trimWritingTag
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.Locale

internal enum class WritingTagKind(val title: String, val endpoint: String) {
    Fandom("Fandoms", "fandom"), Relationship("Relationships", "relationship"),
    Character("Characters", "character"), Freeform("Additional tags", "freeform");

    fun values(form: AO3WorkForm): List<String> = when (this) {
        Fandom -> form.fandoms
        Relationship -> form.relationships
        Character -> form.characters
        Freeform -> form.additionalTags
    }
}

internal const val WritingTagOffer = "AO3 offers its canonical tags as you type"
internal const val WritingTagFootnote = "AO3 suggests only its canonical tags and doesn't provide work counts here. " +
    "You can still post a tag exactly as you type it, which is how new tags are created."
internal const val WritingTagFailure = "Suggestions unavailable. You can still add a tag by name."
internal fun writingTagSubtitle(values: List<String>) = if (values.isEmpty()) WritingTagOffer
    else "${values.size} chosen · drag to reorder · $WritingTagOffer"
internal fun excludesWritingSuggestion(name: String, chosen: List<String>): Boolean {
    val trimmed = trimWritingTag(name)
    return trimmed.isNotEmpty() && chosen.any { it.equals(trimmed, ignoreCase = true) }
}

internal data class WritingTagSuggestions(val term: String = "", val names: List<String> = emptyList(), val error: String? = null)

/** One opening's debounce/cache. Owns no write client and never reads ahead. */
internal class WritingTagsEditorState(
    val kind: WritingTagKind,
    private val repository: AO3TagAutocompleteRepository?,
    private val scope: CoroutineScope,
    private val values: () -> List<String>,
    private val onValues: (List<String>) -> Unit,
    private val onRecorded: (String) -> Unit = {}
) {
    private val mutable = MutableStateFlow(WritingTagSuggestions())
    val state = mutable.asStateFlow()
    private val cache = mutableMapOf<String, List<String>>()
    private var request: Job? = null
    private var active = true

    fun type(term: String) {
        if (!active || term == state.value.term) return
        request?.cancel()
        mutable.value = state.value.copy(term = term, error = null)
        val trimmed = trimWritingTag(term)
        val key = trimmed.lowercase(Locale.ROOT)
        if (key.isEmpty()) {
            mutable.value = state.value.copy(names = emptyList())
            return
        }
        cache[key]?.let { cached ->
            mutable.value = state.value.copy(names = cached.filterNot { excludesWritingSuggestion(it, values()) })
            return
        }
        if (repository == null) return
        request = scope.launch {
            try {
                delay(300)
                val result = repository.autocomplete(kind.endpoint, trimmed, minimumTermLength = 1)
                currentCoroutineContext().ensureActive()
                if (!active || state.value.term != term) return@launch
                when (result) {
                    is AO3Result.Success -> {
                        val names = result.value.map(::trimWritingTag).filter(String::isNotEmpty)
                        cache[key] = names
                        mutable.value = state.value.copy(names = names.filterNot { excludesWritingSuggestion(it, values()) })
                    }
                    is AO3Result.Failure -> mutable.value = state.value.copy(names = emptyList(), error = WritingTagFailure)
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                currentCoroutineContext().ensureActive()
                if (active && state.value.term == term) mutable.value = state.value.copy(names = emptyList(), error = WritingTagFailure)
            }
        }
    }

    fun suggestions(): List<String> = state.value.names
    fun typedTerm(): String? = trimWritingTag(state.value.term).takeIf { name ->
        name.isNotEmpty() && !excludesWritingSuggestion(name, state.value.names + values())
    }

    fun add(name: String = state.value.term) {
        if (!active) return
        val trimmed = trimWritingTag(name)
        val chosen = values()
        if (trimmed.isEmpty() || trimmed in chosen) return // Exact uniqueness; no-op keeps the field.
        onValues(chosen + trimmed)
        type("")
        onRecorded(trimmed)
    }
    fun remove(name: String) { if (active) onValues(values().filterNot { it == name }) }
    fun move(name: String, target: String) {
        if (!active || name == target) return
        val next = values().toMutableList()
        val from = next.indexOf(name)
        if (from < 0) return
        val last = next.lastOrNull() == target && from < next.indexOf(target)
        next.removeAt(from)
        if (last) next.add(name) else next.add(next.indexOf(target).takeIf { it >= 0 } ?: next.size, name)
        onValues(next)
    }
    fun step(name: String, later: Boolean) {
        if (!active) return
        val next = values().toMutableList()
        val from = next.indexOf(name)
        val to = from + if (later) 1 else -1
        if (from < 0 || to !in next.indices) return
        val swap = next[to]; next[to] = name; next[from] = swap
        onValues(next)
    }
    fun close() { active = false; request?.cancel() }
}
