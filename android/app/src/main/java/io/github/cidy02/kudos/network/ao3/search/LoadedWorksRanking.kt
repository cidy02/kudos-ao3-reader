package io.github.cidy02.kudos.network.ao3.search

import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.ResolverStyle
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.max

/**
 * T-473. Orders works from the figures already printed on each loaded blurb.
 * Ranking never asks AO3 for another page: whatever is loaded is what is ranked.
 * Rank Top 100 is intentionally not here; it fetches pages.
 */
enum class LoadedWorksRank(val storageKey: String, val title: String, val subtitle: String) {
    AO3_ORDER("ao3Order", "AO3\u2019s Order", "As AO3 sent them"),
    KUDOS_PER_HIT_ADJUSTED(
        "kudosPerHitAdjusted",
        "Kudos per Hit, Adjusted",
        "Against loaded works of similar length and age"
    ),
    SAVES_PER_KUDOS("savesPerKudos", "Saves per Kudos", "Public bookmarks \u00F7 kudos"),
    COMMENTS_PER_KUDOS("commentsPerKudos", "Comments per Kudos", "Comments \u00F7 kudos"),
    MOMENTUM("momentum", "Momentum", "Kudos gained since you last saw each work"),
    KUDOS_PER_THOUSAND_WORDS(
        "kudosPerThousandWords",
        "Kudos per 1,000 Words",
        "Kudos \u00F7 word count \u00D7 1,000"
    );

    companion object {
        fun fromStorage(raw: String): LoadedWorksRank? = entries.firstOrNull { it.storageKey == raw }
    }
}

enum class LoadedWorksRankOrder(val storageKey: String, val title: String) {
    HIGHEST_FIRST("highestFirst", "Highest First"),
    LOWEST_FIRST("lowestFirst", "Lowest First");

    companion object {
        fun fromStorage(raw: String): LoadedWorksRankOrder? = entries.firstOrNull { it.storageKey == raw }
    }
}

/**
 * Sort By's ranking choices. They ride along with [AO3SearchFilters] so a saved search
 * keeps them, and none of them is sent to AO3. At the defaults the saved JSON omits them,
 * so an older saved search still decodes.
 */
data class LoadedWorksRanking(
    val rank: LoadedWorksRank = LoadedWorksRank.AO3_ORDER,
    val order: LoadedWorksRankOrder = LoadedWorksRankOrder.HIGHEST_FIRST,
    val ranksCautiously: Boolean = true,
    val setsAsideUnusual: Boolean = true,
    val showsSignal: Boolean = true
) {
    val isActive: Boolean get() = rank != LoadedWorksRank.AO3_ORDER

    /**
     * Leaving AO3's order puts AO3's own direction back to the column's natural one,
     * and seeds the minimum-hits cut-off when no hits range is set. That cut-off is
     * `work_search[hits]` and takes effect when the search next runs.
     */
    fun select(newRank: LoadedWorksRank, filters: AO3SearchFilters): AO3SearchFilters {
        if (newRank == rank) return filters
        var next = filters
        if (!isActive && newRank != LoadedWorksRank.AO3_ORDER) {
            next = next.copy(sortDirection = next.sort.naturalDirection)
            if (next.hitsFrom.isBlank() && next.hitsTo.isBlank()) {
                next = next.copy(hitsFrom = DEFAULT_MINIMUM_HITS)
            }
        }
        return next.copy(loadedWorksRanking = copy(rank = newRank))
    }

    companion object {
        const val DEFAULT_MINIMUM_HITS = "500"
    }
}

data class RankedWork(
    val work: AO3WorkSummary,
    val score: Double?,
    val isSetAside: Boolean,
    val signal: String?
)

/** One Ways to Find preset: AO3's own parameters, not a local reorder. */
enum class SearchWaysToFind(
    val title: String,
    val subtitle: String,
    val queryNote: String
) {
    READER_FAVOURITES(
        "Reader Favourites",
        "Most kudos on AO3, at least 1,000 hits",
        "hits over 1,000"
    ),
    NEW_AND_LOVED(
        "New and Loved",
        "Updated in the last 6 months, most kudos first",
        "updated in the last 6 months"
    ),
    HIDDEN_GEMS(
        "Hidden Gems",
        "300 to 5,000 hits, most kudos first",
        "hits 300 to 5,000"
    ),
    ACTIVE_WIPS(
        "Active WIPs",
        "In progress, updated in the last 60 days, latest first",
        "in progress, updated in the last 60 days"
    );

    fun isApplied(filters: AO3SearchFilters): Boolean = when (this) {
        READER_FAVOURITES ->
            filters.sort == AO3SearchSort.KUDOS && filters.hitsFrom == "1000" && filters.hitsTo.isEmpty()
        NEW_AND_LOVED -> filters.sort == AO3SearchSort.KUDOS && filters.updated == AO3Updated.SIX_MONTHS
        HIDDEN_GEMS ->
            filters.sort == AO3SearchSort.KUDOS && filters.hitsFrom == "300" && filters.hitsTo == "5000"
        ACTIVE_WIPS ->
            filters.sort == AO3SearchSort.DATE_UPDATED &&
                filters.completion == AO3Completion.IN_PROGRESS &&
                filters.dateFrom != null
    }

    private fun clear(filters: AO3SearchFilters, defaultSort: AO3SearchSort): AO3SearchFilters {
        val cleared = when (this) {
            READER_FAVOURITES, HIDDEN_GEMS -> filters.copy(hitsFrom = "", hitsTo = "")
            NEW_AND_LOVED -> filters.copy(updated = AO3Updated.ANY)
            ACTIVE_WIPS -> filters.copy(completion = AO3Completion.ANY, dateFrom = null)
        }
        return cleared.copy(sort = defaultSort, sortDirection = defaultSort.naturalDirection)
    }

    companion object {
        const val ACTIVE_WINDOW_DAYS = 60

        fun applied(filters: AO3SearchFilters): SearchWaysToFind? = entries.firstOrNull { it.isApplied(filters) }

        fun toggle(
            preset: SearchWaysToFind,
            filters: AO3SearchFilters,
            defaultSort: AO3SearchSort = AO3SearchSort.RELEVANCE,
            now: LocalDate = LocalDate.now()
        ): AO3SearchFilters {
            val wasOn = preset.isApplied(filters)
            var next = filters
            for (applied in entries) {
                if (applied.isApplied(filters)) next = applied.clear(next, defaultSort)
            }
            if (wasOn) return next
            next = when (preset) {
                READER_FAVOURITES -> next.copy(hitsFrom = "1000", hitsTo = "", sort = AO3SearchSort.KUDOS)
                NEW_AND_LOVED -> next.copy(updated = AO3Updated.SIX_MONTHS, sort = AO3SearchSort.KUDOS)
                HIDDEN_GEMS -> next.copy(hitsFrom = "300", hitsTo = "5000", sort = AO3SearchSort.KUDOS)
                ACTIVE_WIPS -> next.copy(
                    completion = AO3Completion.IN_PROGRESS,
                    dateFrom = now.minusDays(ACTIVE_WINDOW_DAYS.toLong()),
                    sort = AO3SearchSort.DATE_UPDATED
                )
            }
            return next.copy(sortDirection = next.sort.naturalDirection)
        }

        /** "" is off. A hits value set somewhere else is offered too, in numeric order. */
        fun minimumHitsOptions(current: String): List<String> {
            val options = listOf("", "100", "300", "500", "1000", "5000")
            val trimmed = current.trim()
            if (trimmed in options) return options
            return (options + trimmed).sortedBy { it.toIntOrNull() ?: 0 }
        }

        fun minimumHitsTitle(value: String): String {
            val hits = value.trim().toIntOrNull() ?: return "Off"
            return "${groupedInteger(hits)} hits"
        }
    }
}

object SearchSortBySummary {
    fun value(filters: AO3SearchFilters, ranking: LoadedWorksRanking? = filters.loadedWorksRanking): String {
        if (ranking != null && ranking.isActive) return ranking.rank.title
        return SearchWaysToFind.applied(filters)?.title ?: filters.sort.title
    }
}

object SearchSortDirections {
    fun forSort(sort: AO3SearchSort): List<AO3SortDirection> =
        if (sort.naturalDirection == AO3SortDirection.ASCENDING) {
            listOf(AO3SortDirection.ASCENDING, AO3SortDirection.DESCENDING)
        } else {
            listOf(AO3SortDirection.DESCENDING, AO3SortDirection.ASCENDING)
        }

    fun title(direction: AO3SortDirection, sort: AO3SearchSort): String = when (sort) {
        AO3SearchSort.CREATOR, AO3SearchSort.TITLE ->
            if (direction == AO3SortDirection.ASCENDING) "A to Z" else "Z to A"
        AO3SearchSort.DATE_UPDATED, AO3SearchSort.DATE_POSTED ->
            if (direction == AO3SortDirection.DESCENDING) "Newest First" else "Oldest First"
        else -> if (direction == AO3SortDirection.DESCENDING) "Highest First" else "Lowest First"
    }
}

object LoadedWorksRanker {
    const val CAUTIOUS_PSEUDO_HITS = 500.0
    const val MINIMUM_GROUP_SIZE = 3
    const val UNUSUAL_KUDOS_FLOOR = 1_000

    /**
     * Works with a figure come first, highest or lowest as asked; ties keep AO3's order.
     * Works with no figure follow in AO3's order, then set-aside works, also in AO3's order.
     */
    fun rank(
        works: List<AO3WorkSummary>,
        settings: LoadedWorksRanking,
        previousKudos: Map<Long, Int> = emptyMap(),
        now: LocalDate = LocalDate.now()
    ): List<RankedWork> {
        if (!settings.isActive) {
            return works.map { RankedWork(it, score = null, isSetAside = false, signal = null) }
        }
        val figures = works.map { Figures(it, now) }
        val setAside = figures.map { settings.setsAsideUnusual && isUnusual(it) }
        val raw = works.indices.map { index ->
            if (settings.rank == LoadedWorksRank.MOMENTUM) {
                momentum(figures[index].kudos, previousKudos[works[index].id])
            } else {
                rawFigure(settings.rank, figures[index])
            }
        }
        val priors = priors(settings.rank, figures, raw, setAside)
        val entries = works.indices.map { index ->
            val value = raw[index]
            val prior = priors[index]
            val shrunk = value?.let { own ->
                if (settings.ranksCautiously && prior != null) {
                    shrink(own, prior, figures[index].hits)
                } else {
                    own
                }
            }
            val score: Double?
            val shown: Double?
            if (settings.rank == LoadedWorksRank.KUDOS_PER_HIT_ADJUSTED) {
                if (prior != null && prior > 0.0) {
                    score = shrunk?.let { it / prior }
                    shown = value?.let { it / prior }
                } else {
                    score = null
                    shown = null
                }
            } else {
                score = shrunk
                shown = value
            }
            IndexedRank(
                index,
                RankedWork(
                    work = works[index],
                    score = score,
                    isSetAside = setAside[index],
                    signal = signal(
                        settings.rank,
                        shown,
                        setAside[index],
                        previousKudos[works[index].id] != null
                    )
                )
            )
        }
        val highestFirst = settings.order == LoadedWorksRankOrder.HIGHEST_FIRST
        val ranked = entries
            .filter { !it.entry.isSetAside && it.entry.score != null }
            .sortedWith { lhs, rhs ->
                val left = lhs.entry.score ?: 0.0
                val right = rhs.entry.score ?: 0.0
                val byScore = if (highestFirst) right.compareTo(left) else left.compareTo(right)
                if (byScore != 0) byScore else lhs.index.compareTo(rhs.index)
            }
            .map { it.entry }
        val unscored = entries.filter { !it.entry.isSetAside && it.entry.score == null }.map { it.entry }
        val aside = entries.filter { it.entry.isSetAside }.map { it.entry }
        return ranked + unscored + aside
    }

    class Figures(work: AO3WorkSummary, now: LocalDate) {
        val kudos: Int?
        val hits: Int?
        val comments: Int?
        val bookmarks: Int?
        val words: Int?
        val lengthGroup: Int?
        val ageGroup: Int?

        init {
            val isFullBlurb = work.wordCount != null
            fun count(value: Int?): Int? = value ?: if (isFullBlurb) 0 else null
            kudos = count(work.kudos)
            hits = count(work.hits)
            comments = count(work.comments)
            bookmarks = count(work.bookmarks)
            words = work.wordCount
            lengthGroup = lengthGroup(work.wordCount)
            ageGroup = ageGroup(blurbDate(work.updatedDate), now)
        }
    }

    fun lengthGroup(words: Int?): Int? {
        words ?: return null
        return if (words < 10_000) 0 else if (words < 50_000) 1 else 2
    }

    /** Updated within a year, within three, and older. Days are calendar days. */
    fun ageGroup(updated: LocalDate?, now: LocalDate): Int? {
        updated ?: return null
        val days = ChronoUnit.DAYS.between(updated, now)
        return if (days < 365) 0 else if (days < 3 * 365) 1 else 2
    }

    fun isUnusual(figures: Figures): Boolean {
        val kudos = figures.kudos ?: return false
        val hits = figures.hits
        if (hits != null && kudos > hits) return true
        val bookmarks = figures.bookmarks
        if (kudos >= UNUSUAL_KUDOS_FLOOR && bookmarks != null && bookmarks * 100 < kudos) return true
        return false
    }

    /** A zero or unknown denominator is unranked, never infinite. */
    fun rawFigure(rank: LoadedWorksRank, figures: Figures): Double? {
        fun ratio(numerator: Int?, denominator: Int?, scale: Double = 1.0): Double? {
            if (numerator == null || denominator == null || denominator <= 0) return null
            return numerator.toDouble() / (denominator.toDouble() / scale)
        }
        return when (rank) {
            LoadedWorksRank.AO3_ORDER, LoadedWorksRank.MOMENTUM -> null
            LoadedWorksRank.KUDOS_PER_HIT_ADJUSTED -> ratio(figures.kudos, figures.hits)
            LoadedWorksRank.SAVES_PER_KUDOS -> ratio(figures.bookmarks, figures.kudos)
            LoadedWorksRank.COMMENTS_PER_KUDOS -> ratio(figures.comments, figures.kudos)
            LoadedWorksRank.KUDOS_PER_THOUSAND_WORDS -> ratio(figures.kudos, figures.words, 1_000.0)
        }
    }

    fun momentum(kudos: Int?, previous: Int?): Double? {
        if (kudos == null || previous == null) return null
        return max(0, kudos - previous).toDouble()
    }

    fun shrink(value: Double, prior: Double, hits: Int?): Double {
        val evidence = max(0, hits ?: 0).toDouble()
        return (evidence * value + CAUTIOUS_PSEUDO_HITS * prior) / (evidence + CAUTIOUS_PSEUDO_HITS)
    }

    fun median(values: List<Double>): Double? {
        if (values.isEmpty()) return null
        val sorted = values.sorted()
        val middle = sorted.size / 2
        return if (sorted.size % 2 == 0) (sorted[middle - 1] + sorted[middle]) / 2.0 else sorted[middle]
    }

    fun signal(rank: LoadedWorksRank, shown: Double?, setAside: Boolean, hasPrevious: Boolean): String? {
        if (setAside) return "Unusual stats, set aside"
        return when (rank) {
            LoadedWorksRank.AO3_ORDER -> null
            LoadedWorksRank.MOMENTUM -> {
                if (!hasPrevious || shown == null) "First time in your results"
                else if (shown > 0.0) "+${groupedInteger(shown.toInt())} kudos since you last saw it"
                else "No new kudos since you last saw it"
            }
            LoadedWorksRank.KUDOS_PER_HIT_ADJUSTED,
            LoadedWorksRank.SAVES_PER_KUDOS,
            LoadedWorksRank.COMMENTS_PER_KUDOS,
            LoadedWorksRank.KUDOS_PER_THOUSAND_WORDS -> {
                if (shown == null) "Not enough figures to rank"
                else when (rank) {
                    LoadedWorksRank.KUDOS_PER_HIT_ADJUSTED -> "${decimal(shown)}\u00D7 typical kudos per hit"
                    LoadedWorksRank.SAVES_PER_KUDOS -> "${decimal(shown * 100)} saves per 100 kudos"
                    LoadedWorksRank.COMMENTS_PER_KUDOS -> "${decimal(shown * 100)} comments per 100 kudos"
                    else -> "${decimal(shown)} kudos per 1,000 words"
                }
            }
        }
    }

    private data class IndexedRank(val index: Int, val entry: RankedWork)

    private data class Group(val length: Int?, val age: Int?)

    private fun priors(
        rank: LoadedWorksRank,
        figures: List<Figures>,
        raw: List<Double?>,
        setAside: List<Boolean>
    ): List<Double?> {
        if (rank == LoadedWorksRank.MOMENTUM) return List(figures.size) { null }
        val eligible = figures.indices.filter { raw[it] != null && !setAside[it] }
        val overall = median(eligible.mapNotNull { raw[it] })
        if (rank != LoadedWorksRank.KUDOS_PER_HIT_ADJUSTED) return List(figures.size) { overall }
        val byGroup = mutableMapOf<Group, MutableList<Double>>()
        val byLength = mutableMapOf<Int?, MutableList<Double>>()
        for (index in eligible) {
            val value = raw[index] ?: continue
            val figure = figures[index]
            byGroup.getOrPut(Group(figure.lengthGroup, figure.ageGroup)) { mutableListOf() }.add(value)
            byLength.getOrPut(figure.lengthGroup) { mutableListOf() }.add(value)
        }
        return figures.map { figure ->
            val group = byGroup[Group(figure.lengthGroup, figure.ageGroup)].orEmpty()
            if (group.size >= MINIMUM_GROUP_SIZE) return@map median(group)
            val length = byLength[figure.lengthGroup].orEmpty()
            if (length.size >= MINIMUM_GROUP_SIZE) median(length) else overall
        }
    }

    private fun decimal(value: Double): String {
        val digits = if (value < 10.0) 1 else 0
        val format = java.text.DecimalFormat("#,##0", java.text.DecimalFormatSymbols.getInstance(Locale.US)).apply {
            minimumFractionDigits = digits
            maximumFractionDigits = digits
            roundingMode = java.math.RoundingMode.HALF_UP
        }
        return format.format(value)
    }

    companion object {
        private val blurbDates = listOf("uuuu-MM-dd", "dd MMM uuuu").map {
            DateTimeFormatter.ofPattern(it, Locale.US).withResolverStyle(ResolverStyle.STRICT)
        }

        fun blurbDate(raw: String): LocalDate? {
            if (raw.isBlank()) return null
            for (parser in blurbDates) {
                val parsed = runCatching { LocalDate.parse(raw.trim(), parser) }.getOrNull()
                if (parsed != null) return parsed
            }
            return null
        }
    }
}

/** Kudos a work had the last time it appeared in search results. */
@kotlinx.serialization.Serializable
data class SeenKudos(val kudos: Int, val seenAtMillis: Long)

interface KudosStringStore {
    fun get(key: String): String?
    fun set(key: String, value: String?)
}

class MemoryKudosStringStore : KudosStringStore {
    private val values = mutableMapOf<String, String>()
    override fun get(key: String): String? = values[key]
    override fun set(key: String, value: String?) {
        if (value == null) values.remove(key) else values[key] = value
    }
}

/**
 * Momentum's baseline for one search session. The first sighting this session keeps
 * the stored kudos; a later page of the same session does not move that baseline.
 */
class KudosSightings {
    var previousKudos: Map<Long, Int> = emptyMap()
        private set
    private val checked = mutableSetOf<Long>()

    fun record(
        works: List<AO3WorkSummary>,
        stored: Map<Long, SeenKudos>,
        now: LocalDate = LocalDate.now(),
        nowMillis: Long = System.currentTimeMillis()
    ): Map<Long, SeenKudos> {
        val updated = stored.toMutableMap()
        for (work in works) {
            val kudos = LoadedWorksRanker.Figures(work, now).kudos ?: continue
            if (checked.add(work.id)) {
                val earlier = stored[work.id]
                if (earlier != null) previousKudos = previousKudos + (work.id to earlier.kudos)
            }
            updated[work.id] = SeenKudos(kudos, nowMillis)
        }
        return updated
    }
}

/**
 * Momentum's record. Losing it only means every work starts again at
 * "First time in your results". Not part of a saved search or a backup.
 */
object LastSeenKudosStore {
    const val KEY = "ao3.search.lastSeenKudos"
    const val PREFS_NAME = "ao3.search.lastSeenKudos"
    const val ENTRY_LIMIT = 1_000

    private val json = kotlinx.serialization.json.Json { ignoreUnknownKeys = true }

    fun load(from: KudosStringStore): Map<Long, SeenKudos> {
        val raw = from.get(KEY) ?: return emptyMap()
        val decoded = runCatching { json.decodeFromString<Map<String, SeenKudos>>(raw) }.getOrNull() ?: return emptyMap()
        return decoded.mapNotNull { (key, value) -> key.toLongOrNull()?.let { it to value } }.toMap()
    }

    fun save(entries: Map<Long, SeenKudos>, to: KudosStringStore) {
        val payload = bound(entries).entries.associate { it.key.toString() to it.value }
        val encoded = runCatching { json.encodeToString(payload) }.getOrNull() ?: return
        to.set(KEY, encoded)
    }

    fun bound(entries: Map<Long, SeenKudos>): Map<Long, SeenKudos> {
        if (entries.size <= ENTRY_LIMIT) return entries
        return entries.entries
            .sortedByDescending { it.value.seenAtMillis }
            .take(ENTRY_LIMIT)
            .associate { it.key to it.value }
    }
}

internal fun groupedInteger(value: Int): String =
    java.text.NumberFormat.getIntegerInstance(Locale.US).format(value)
