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
    val workCount: Int? = null,
    val savedCount: Int = 0,
    val recentFandoms: List<String> = emptyList()
)

object CategoryStatsCalculator {
    private const val RecentLimit = 3

    fun stats(
        category: AO3MediaCategory,
        fandomList: List<AO3Fandom>?,
        library: List<SavedWork>
    ): CategoryStats {
        // Prefer full list for name matching; fall back to featured tags while loading.
        val names = fandomList?.map { it.name }
            ?: category.featuredFandoms
        val nameSet = names.map { it.lowercase(Locale.US) }.toSet()

        fun inCategory(work: SavedWork): Boolean =
            work.workFandoms.any { nameSet.contains(it.lowercase(Locale.US)) }

        val recent = linkedSetOf<String>()
        val seen = mutableSetOf<String>()
        library
            .asSequence()
            .filter { it.hasBeenRead }
            .sortedByDescending { it.dateAdded }
            .forEach { work ->
                for (fandom in work.workFandoms) {
                    val key = fandom.lowercase(Locale.US)
                    if (key in nameSet && seen.add(key)) {
                        recent += fandom
                        if (recent.size >= RecentLimit) return@forEach
                    }
                }
            }

        return CategoryStats(
            fandomCount = fandomList?.size,
            workCount = fandomList?.sumOf { it.workCount ?: 0 }?.takeIf { it > 0 },
            savedCount = library.count(::inCategory),
            recentFandoms = recent.toList()
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

private val SavedWork.hasBeenRead: Boolean
    get() = isFinished || lastSpineIndex > 0 || lastReadDate != null ||
        !readiumLocator.isNullOrBlank() || lastScrollFraction > 0.0
