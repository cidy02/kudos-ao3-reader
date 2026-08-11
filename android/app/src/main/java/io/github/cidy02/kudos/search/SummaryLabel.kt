package io.github.cidy02.kudos.search

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.MenuBook
import androidx.compose.material.icons.outlined.People
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Sell
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.ui.graphics.vector.ImageVector
import io.github.cidy02.kudos.network.ao3.search.AO3ResultSummary

/**
 * One chip on the results card.
 *
 * AO3 groups tags by category in its own markup (`h5.fandoms`, `ul.tags
 * li.characters`, …) and the blurb parser already reads that, so the category is
 * known for free — it just wasn't shown anywhere the categories are *mixed*, which
 * the card is. The glyph carries what used to be spelled out ("Fandom: Naruto"), so
 * the chip gets its width back for the tag itself.
 */
data class SummaryLabel(
    val text: String,
    /**
     * The tag category's glyph, for the entries that *are* tags. Null for facets like
     * a rating or the sort, which are not tag categories and would be given a
     * misleading one.
     */
    val icon: ImageVector? = null
) {
    companion object {
        val fandomIcon: ImageVector = Icons.Outlined.MenuBook
        val characterIcon: ImageVector = Icons.Outlined.Person
        val relationshipIcon: ImageVector = Icons.Outlined.People
        val freeformIcon: ImageVector = Icons.Outlined.Sell
        val warningIcon: ImageVector = Icons.Outlined.WarningAmber

        /**
         * The count line's glyph — a page, matching the Works sections elsewhere in
         * the app. Deliberately not [fandomIcon]: on the Search card a fandom chip
         * can sit one line below the count, and two different things must not share
         * an icon inside one card.
         */
        val worksIcon: ImageVector = Icons.Outlined.Description

        /** The glyph for a results list's own subject. */
        fun iconFor(category: AO3ResultSummary.SubjectCategory?): ImageVector? = when (category) {
            AO3ResultSummary.SubjectCategory.FANDOM -> fandomIcon
            AO3ResultSummary.SubjectCategory.CHARACTER -> characterIcon
            AO3ResultSummary.SubjectCategory.RELATIONSHIP -> relationshipIcon
            AO3ResultSummary.SubjectCategory.FREEFORM -> freeformIcon
            null -> null
        }
    }
}
