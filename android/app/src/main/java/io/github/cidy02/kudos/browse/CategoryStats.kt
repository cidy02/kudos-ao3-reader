package io.github.cidy02.kudos.browse

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Book
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.LocalMovies
import androidx.compose.material.icons.outlined.MusicNote
import androidx.compose.material.icons.outlined.People
import androidx.compose.material.icons.outlined.SportsEsports
import androidx.compose.material.icons.outlined.Tag
import androidx.compose.material.icons.outlined.TheaterComedy
import androidx.compose.material.icons.outlined.Tv
import androidx.compose.ui.graphics.vector.ImageVector
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.browse.AO3Fandom
import io.github.cidy02.kudos.network.ao3.browse.AO3MediaCategory
import java.util.Locale
import kotlin.math.ln
import kotlin.math.pow

/**
 * Per-category enrichment for Browse cards — mirrors Apple [MediaBrowserView]
 * [CategoryStats]: fandom/work counts when the full list is available, local
 * saved count, and recently-read fandom chips.
 */
data class CategoryStats(
    /** null while the category's full fandom list is still loading. */
    val fandomCount: Int? = null,
    /** Fandoms once disambiguations are merged. The counts line prefers this. */
    val familyCount: Int? = null,
    val workCount: Int? = null,
    /** True when [workCount] sums per-tag counts and can double-count a work. */
    val isApproximateWorkCount: Boolean = false,
    /** Kept copies on this device, not works fetched only to read. */
    val savedCount: Int = 0,
    val recentFandoms: List<String> = emptyList(),
    /** Biggest families, at most twelve. A chip searches [ClusterFandom.names]. */
    val clusterFandoms: List<ClusterFandom> = emptyList()
) {
    data class ClusterFandom(
        val id: String,
        val names: List<String>,
        val title: String,
        val workCount: Int,
        val isApproximate: Boolean
    )
}

/** One category's inputs for the off-main stats pass. */
data class CategoryStatsInput(
    val id: String,
    val fandoms: List<AO3Fandom>,
    val hasFullList: Boolean
)

object CategoryStatsCalculator {
    /** How many "recently read" chips a category card shows. */
    const val RECENT_LIMIT = 5

    /** Chips before the rest collapse into "+N more". */
    const val CLUSTER_LIMIT = 12

    fun stats(
        category: AO3MediaCategory,
        fandomList: List<AO3Fandom>?,
        library: List<SavedWork>
    ): CategoryStats {
        val input = CategoryStatsInput(
            id = category.name,
            fandoms = fandomList ?: category.featuredFandoms.map { AO3Fandom(name = it) },
            hasFullList = fandomList != null
        )
        return computeStats(listOf(input), library.map { it.toBrowseSnapshot() })[category.name]
            ?: CategoryStats()
    }

    /**
     * iOS `MediaBrowserView.computeStats`. Downloaded counts are kept copies.
     * Recent chips follow last-read, then date added. The cluster is the twelve
     * biggest families once the full list is in.
     */
    fun computeStats(
        inputs: List<CategoryStatsInput>,
        works: List<LibraryWorkSnapshot>
    ): Map<String, CategoryStats> {
        val readWorks = works.filter { it.hasBeenRead }.sortedByDescending { it.recency }
        val result = LinkedHashMap<String, CategoryStats>(inputs.size)
        for (input in inputs) {
            val nameSet = input.fandoms.map { it.name.lowercase(Locale.US) }.toSet()
            var savedCount = 0
            for (work in works) {
                if (work.isOnDevice && work.fandomsLower.any { it in nameSet }) savedCount += 1
            }
            val recent = ArrayList<String>()
            val seen = HashSet<String>()
            for (work in readWorks) {
                for (index in work.fandomsLower.indices) {
                    val key = work.fandomsLower[index]
                    if (key in nameSet && seen.add(key)) {
                        recent += work.fandomsDisplay[index]
                    }
                }
                if (recent.size >= RECENT_LIMIT) break
            }
            val families = if (input.hasFullList) FandomFamily.grouped(input.fandoms) else emptyList()
            val cluster = families
                .sortedByDescending { it.summedWorkCount }
                .take(CLUSTER_LIMIT)
                .map { family ->
                    CategoryStats.ClusterFandom(
                        id = family.id,
                        names = family.includedFilterNames,
                        title = family.parsedTitle,
                        workCount = family.summedWorkCount,
                        isApproximate = family.showsApproximateCount
                    )
                }
            val summed = if (input.hasFullList) input.fandoms.sumOf { it.workCount ?: 0 } else null
            result[input.id] = CategoryStats(
                fandomCount = if (input.hasFullList) input.fandoms.size else null,
                familyCount = if (input.hasFullList) families.size else null,
                workCount = summed,
                isApproximateWorkCount = input.hasFullList,
                savedCount = savedCount,
                recentFandoms = recent.take(RECENT_LIMIT),
                clusterFandoms = cluster
            )
        }
        return result
    }

    /**
     * Maps read and visited fandoms onto the first category that lists them,
     * then ranks by the latest visit or read. Work counts come from the whole
     * list, not just the twelve cluster chips.
     */
    fun rankJumpBackIn(
        inputs: List<CategoryStatsInput>,
        works: List<LibraryWorkSnapshot>,
        visits: List<JumpBackIn.Visit> = emptyList(),
        limit: Int = JumpBackIn.LIMIT
    ): List<JumpBackIn.Pick> {
        val wanted = works.asSequence()
            .filter { it.hasBeenRead }
            .flatMap { it.fandomsLower.asSequence() }
            .toMutableSet()
        visits.mapTo(wanted) { it.fandom.lowercase(Locale.US) }
        if (wanted.isEmpty()) return emptyList()
        val categoryByFandom = HashMap<String, String>()
        val workCountByFandom = HashMap<String, Int>()
        for (input in inputs) {
            for (fandom in input.fandoms) {
                val lower = fandom.name.lowercase(Locale.US)
                if (lower !in wanted || categoryByFandom.containsKey(lower)) continue
                categoryByFandom[lower] = input.id
                fandom.workCount?.let { workCountByFandom[lower] = it }
            }
        }
        return JumpBackIn.fandoms(
            works = works,
            visits = visits,
            categoryFor = { categoryByFandom[it] },
            workCountFor = { workCountByFandom[it] },
            limit = limit
        )
    }

    /** Representative icon for an AO3 media category name (Apple SF Symbol map). */
    fun iconFor(categoryName: String): ImageVector = when (categoryName) {
        "Anime & Manga" -> Icons.Outlined.AutoAwesome
        "Books & Literature" -> Icons.AutoMirrored.Outlined.MenuBook
        "Cartoons & Comics & Graphic Novels" -> Icons.Outlined.Book
        "Celebrities & Real People" -> Icons.Outlined.People
        "Movies" -> Icons.Outlined.LocalMovies
        "Music & Bands" -> Icons.Outlined.MusicNote
        "Other Media" -> Icons.Outlined.GridView
        "Theater" -> Icons.Outlined.TheaterComedy
        "TV Shows" -> Icons.Outlined.Tv
        "Video Games" -> Icons.Outlined.SportsEsports
        "Uncategorized Fandoms" -> Icons.Outlined.Folder
        else -> Icons.Outlined.Tag
    }

    /** Compact count like iOS `1.2M` / `4,979`. */
    fun formatCount(value: Int): String {
        if (value < 1_000) return "%,d".format(Locale.US, value)
        val exp = (ln(value.toDouble()) / ln(1000.0)).toInt().coerceAtMost(2)
        val divisor = 1000.0.pow(exp)
        val scaled = value / divisor
        val suffix = when (exp) {
            1 -> "K"
            2 -> "M"
            else -> ""
        }
        val formatted = if (scaled >= 100 || exp == 0) {
            scaled.toInt().toString()
        } else {
            String.format(Locale.US, "%.1f", scaled).trimEnd('0').trimEnd('.')
        }
        return "$formatted$suffix"
    }

    fun formatWorksEstimate(value: Int): String = "~${formatCount(value)} works"
}
