package io.github.cidy02.kudos.browse

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.network.ao3.browse.AO3Fandom
import io.github.cidy02.kudos.works.WorkSearchIndex
import java.text.Collator
import java.util.Locale

/**
 * Sibling tags that share a parsed display title inside one media category.
 * Port of iOS `FandomFamily`. Identity stays on the raw AO3 names.
 */
data class FandomFamily(
    val id: String,
    val parsedTitle: String,
    val members: List<Member>,
    val summedWorkCount: Int,
    val exactWorkCount: Int? = null
) {
    val showsApproximateCount: Boolean
        get() = exactWorkCount == null && members.size > 1

    val displayedWorkCount: Int
        get() = exactWorkCount ?: summedWorkCount

    /** Raw original tag names, in member order. A family tap includes these. */
    val includedFilterNames: List<String>
        get() = members.map { it.originalName }

    val memberCount: Int
        get() = members.size

    fun searchHaystack(): String {
        val parts = ArrayList<String>(members.size * 3 + 1)
        parts += parsedTitle
        for (member in members) {
            parts += member.originalName
            parts += member.qualifierDisplay
            parts.addAll(member.aliases)
        }
        return WorkSearchIndex.normalize(parts.joinToString(" "))
    }

    data class Member(
        val fandom: AO3Fandom,
        val displayName: FandomName,
        val aliases: List<String>,
        val qualifierDisplay: String,
        val workCount: Int,
        val isRPF: Boolean,
        val isAllMediaTypes: Boolean,
        val isRelatedFandoms: Boolean
    ) {
        val originalName: String
            get() = fandom.name

        companion object {
            fun from(fandom: AO3Fandom): Member {
                val aliases = FandomDisplayName.aliasSegments(fandom.name)
                val primary = FandomDisplayName.primarySegment(fandom.name)
                val split = FandomDisplayName.split(primary)
                val kinds = split.parts.map { it.kind }.toSet()
                return Member(
                    fandom = fandom,
                    displayName = FandomName(
                        original = fandom.name,
                        title = split.title,
                        parts = split.parts
                    ),
                    aliases = aliases,
                    qualifierDisplay = qualifierDisplay(split.parts, split.title),
                    workCount = fandom.workCount ?: 0,
                    isRPF = FandomQualifierKind.Rpf in kinds,
                    isAllMediaTypes = FandomQualifierKind.AllMediaTypes in kinds,
                    isRelatedFandoms = FandomQualifierKind.RelatedFandoms in kinds
                )
            }
        }
    }

    companion object {
        /** A character AO3 tag names do not contain, so a join cannot collide. */
        const val ID_SEPARATOR = "\u001E"

        fun id(originalNames: List<String>): String =
            originalNames.sortedWith(::compareNames).joinToString(ID_SEPARATOR)

        fun of(
            parsedTitle: String,
            members: List<Member>,
            exactWorkCount: Int? = null
        ): FandomFamily = fromMembers(parsedTitle, members, exactWorkCount)

        fun grouped(fandoms: List<AO3Fandom>): List<FandomFamily> {
            val buckets = LinkedHashMap<String, MutableList<Member>>()
            val seen = HashSet<String>()
            for (fandom in fandoms) {
                if (!seen.add(fandom.name)) continue
                val member = Member.from(fandom)
                buckets.getOrPut(member.displayName.title) { ArrayList() }.add(member)
            }
            return buckets.map { (title, members) ->
                fromMembers(title, members)
            }.sortedWith(::compareFamiliesByTitle)
        }

        /** Group variants off: every raw tag is its own row, titled by its display segment. */
        fun ungrouped(fandoms: List<AO3Fandom>): List<FandomFamily> {
            val seen = HashSet<String>()
            return fandoms.mapNotNull { fandom ->
                if (!seen.add(fandom.name)) return@mapNotNull null
                val member = Member.from(fandom)
                fromMembers(member.displayName.title, listOf(member))
            }
        }

        fun sorted(families: List<FandomFamily>, by: FandomFamilySort): List<FandomFamily> =
            when (by) {
                FandomFamilySort.Alphabetical -> families.sortedWith(::compareFamiliesByTitle)
                FandomFamilySort.FamilyTotal -> families.sortedWith { left, right ->
                    val count = right.summedWorkCount.compareTo(left.summedWorkCount)
                    if (count != 0) count else compareFamiliesByTitle(left, right)
                }
            }

        /** First Latin letter of the parsed title, else `#`. */
        fun letterGroup(title: String): String {
            val first = title.firstOrNull { !it.isWhitespace() } ?: return "#"
            val upper = first.uppercaseChar()
            return if (upper in 'A'..'Z') upper.toString() else "#"
        }

        /**
         * Bucket by letter, not by consecutive run, so accented titles that map to
         * `#` do not split the hash section. [families] should already be A–Z.
         */
        fun letterSections(families: List<FandomFamily>): List<LetterSection> {
            val order = ArrayList<String>()
            val buckets = LinkedHashMap<String, MutableList<FandomFamily>>()
            for (family in families) {
                val letter = letterGroup(family.parsedTitle)
                if (buckets[letter] == null) order += letter
                buckets.getOrPut(letter) { ArrayList() }.add(family)
            }
            return order.map { letter -> LetterSection(letter, buckets[letter].orEmpty()) }
        }

        private fun fromMembers(
            title: String,
            members: List<Member>,
            exactWorkCount: Int? = null
        ): FandomFamily {
            val ordered = sortedMembers(members)
            return FandomFamily(
                id = id(ordered.map { it.originalName }),
                parsedTitle = title,
                members = ordered,
                summedWorkCount = ordered.sumOf { it.workCount },
                exactWorkCount = exactWorkCount
            )
        }

        private fun sortedMembers(members: List<Member>): List<Member> =
            members.sortedWith { left, right ->
                val count = right.workCount.compareTo(left.workCount)
                if (count != 0) return@sortedWith count
                val qualifier = compareNames(left.qualifierDisplay, right.qualifierDisplay)
                if (qualifier != 0) qualifier else compareNames(left.originalName, right.originalName)
            }

        private fun compareFamiliesByTitle(left: FandomFamily, right: FandomFamily): Int {
            val title = compareNames(left.parsedTitle, right.parsedTitle)
            return if (title != 0) title else compareNames(left.id, right.id)
        }
    }

    data class LetterSection(val letter: String, val families: List<FandomFamily>)
}

enum class FandomFamilySort {
    Alphabetical,
    FamilyTotal
}

private val nameCollator: Collator = Collator.getInstance(Locale.US).apply {
    strength = Collator.PRIMARY
    decomposition = Collator.CANONICAL_DECOMPOSITION
}

private fun compareNames(left: String, right: String): Int =
    (nameCollator.clone() as Collator).compare(left, right)

/** Qualifier as a member-row label, with AO3's delimiter stripped. */
fun qualifierDisplay(parts: List<FandomQualifier>, fallback: String): String {
    val joined = parts.map { it.displayLabel() }.filter { it.isNotEmpty() }.joinToString(" ")
    return joined.ifEmpty { fallback }
}

fun FandomQualifier.displayLabel(): String {
    var text = text.trim()
    if (text.startsWith("- ")) text = text.drop(2)
    if (text.startsWith("& ")) text = text.drop(2)
    if (text.startsWith("and ", ignoreCase = true)) text = text.drop(4)
    val wrapped = (text.startsWith("(") && text.endsWith(")")) ||
        (text.startsWith("（") && text.endsWith("）"))
    if (wrapped && text.length >= 2) text = text.substring(1, text.length - 1)
    return text.trim()
}

/** The tally under the fandom list header (1al, 1an). */
object FandomListTally {
    fun text(
        totalTags: Int,
        families: Int?,
        shownTags: Int,
        isFiltered: Boolean,
        sort: FandomFamilySort
    ): String {
        val order = when (sort) {
            FandomFamilySort.Alphabetical -> "A–Z"
            FandomFamilySort.FamilyTotal -> "most works"
        }
        val tags = if (totalTags == 1) "tag" else "tags"
        if (isFiltered) {
            return "${groupedCount(shownTags)} of ${groupedCount(totalTags)} $tags · $order"
        }
        if (families == null) return "${groupedCount(totalTags)} $tags · $order"
        val fandomWord = if (families == 1) "fandom" else "fandoms"
        return "${groupedCount(totalTags)} $tags in ${groupedCount(families)} $fandomWord · $order"
    }
}

fun groupedCount(value: Int): String = "%,d".format(Locale.US, value)

enum class MinimumWorks(val raw: Int, val title: String) {
    Any(0, "Any"),
    Ten(10, "10+"),
    Hundred(100, "100+"),
    Thousand(1_000, "1,000+")
}

data class FandomListFilterOptions(
    val minimumWorks: MinimumWorks = MinimumWorks.Any,
    val hideRPF: Boolean = false,
    val hideAllMediaTypes: Boolean = false,
    val hideRelatedFandoms: Boolean = false,
    val favouritedOnly: Boolean = false,
    val downloadsOnly: Boolean = false,
    val multiTagOnly: Boolean = false
) {
    val hasActiveFilters: Boolean
        get() = minimumWorks != MinimumWorks.Any ||
            hideRPF || hideAllMediaTypes || hideRelatedFandoms ||
            favouritedOnly || downloadsOnly || multiTagOnly

    val activeFilterCount: Int
        get() = listOf(
            minimumWorks != MinimumWorks.Any,
            hideRPF,
            hideAllMediaTypes,
            hideRelatedFandoms,
            favouritedOnly,
            downloadsOnly,
            multiTagOnly
        ).count { it }

    /** "More than one tag" would empty an ungrouped list, so turning grouping off clears it. */
    fun groupsVariantsChanged(isOn: Boolean): FandomListFilterOptions =
        if (isOn) this else copy(multiTagOnly = false)
}

/** Favourite and downloaded tag names from the local library. */
data class FandomLibraryIndex(
    val favouriteNamesLowercased: Set<String>,
    val downloadCountsByNameLowercased: Map<String, Int>
) {
    fun isFavourited(originalName: String): Boolean =
        originalName.lowercase(Locale.US) in favouriteNamesLowercased

    fun downloadCount(originalName: String): Int =
        downloadCountsByNameLowercased[originalName.lowercase(Locale.US)] ?: 0

    fun hasDownload(originalName: String): Boolean = downloadCount(originalName) > 0

    companion object {
        val empty = FandomLibraryIndex(emptySet(), emptyMap())

        fun from(works: List<SavedWork>): FandomLibraryIndex {
            val favourites = HashSet<String>()
            val downloads = HashMap<String, Int>()
            for (work in works) {
                val names = work.workFandoms.map { it.lowercase(Locale.US) }.toSet()
                if (work.isFavorite) favourites += names
                if (work.isDownloaded) {
                    for (name in names) downloads[name] = (downloads[name] ?: 0) + 1
                }
            }
            return FandomLibraryIndex(favourites, downloads)
        }
    }
}

data class FandomFamilyFilterTallies(
    val rpfTags: Int,
    val allMediaTypesTags: Int,
    val relatedFandomsTags: Int,
    val favouritedTags: Int,
    val downloadTags: Int,
    val multiTagFamilies: Int,
    val memberWorkCounts: List<Int>
) {
    fun tagsBelowMinimumWorks(minimum: MinimumWorks): Int {
        if (minimum == MinimumWorks.Any) return 0
        return memberWorkCounts.count { it < minimum.raw }
    }
}

object FandomFamilyFilters {
    fun apply(
        families: List<FandomFamily>,
        options: FandomListFilterOptions,
        library: FandomLibraryIndex = FandomLibraryIndex.empty
    ): List<FandomFamily> = families.mapNotNull { family ->
        val kept = family.members.filter { matches(it, options, library) }
        if (kept.isEmpty()) return@mapNotNull null
        if (options.multiTagOnly && kept.size < 2) return@mapNotNull null
        val exact = if (kept.size == family.members.size) family.exactWorkCount else null
        FandomFamily.of(family.parsedTitle, kept, exact)
    }

    fun tagCount(families: List<FandomFamily>): Int = families.sumOf { it.memberCount }

    fun tallies(
        families: List<FandomFamily>,
        library: FandomLibraryIndex = FandomLibraryIndex.empty
    ): FandomFamilyFilterTallies {
        var rpf = 0
        var allMedia = 0
        var related = 0
        var favourited = 0
        var downloads = 0
        var multi = 0
        val works = ArrayList<Int>()
        for (family in families) {
            if (family.memberCount > 1) multi += 1
            for (member in family.members) {
                if (member.isRPF) rpf += 1
                if (member.isAllMediaTypes) allMedia += 1
                if (member.isRelatedFandoms) related += 1
                if (library.isFavourited(member.originalName)) favourited += 1
                if (library.hasDownload(member.originalName)) downloads += 1
                works += member.workCount
            }
        }
        return FandomFamilyFilterTallies(
            rpfTags = rpf,
            allMediaTypesTags = allMedia,
            relatedFandomsTags = related,
            favouritedTags = favourited,
            downloadTags = downloads,
            multiTagFamilies = multi,
            memberWorkCounts = works
        )
    }

    private fun matches(
        member: FandomFamily.Member,
        options: FandomListFilterOptions,
        library: FandomLibraryIndex
    ): Boolean {
        if (member.workCount < options.minimumWorks.raw) return false
        if (options.hideRPF && member.isRPF) return false
        if (options.hideAllMediaTypes && member.isAllMediaTypes) return false
        if (options.hideRelatedFandoms && member.isRelatedFandoms) return false
        if (options.favouritedOnly && !library.isFavourited(member.originalName)) return false
        if (options.downloadsOnly && !library.hasDownload(member.originalName)) return false
        return true
    }
}
