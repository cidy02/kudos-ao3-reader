package io.github.cidy02.kudos.account

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Article
import androidx.compose.material.icons.automirrored.outlined.Assignment
import androidx.compose.material.icons.automirrored.outlined.CallSplit
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.outlined.Badge
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.CardGiftcard
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.CollectionsBookmark
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Drafts
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.Flag
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.PanTool
import androidx.compose.material.icons.outlined.People
import androidx.compose.material.icons.outlined.PersonAdd
import androidx.compose.material.icons.outlined.QuestionAnswer
import androidx.compose.material.icons.outlined.ReportProblem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.LocalSubjectPalette
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.ui.subject.subjectScreenWash

@Composable
fun AccountMoreOnAO3Screen(
    username: String?,
    onOpenWeb: (String) -> Unit
) {
    val chrome = LocalPushedShellChrome.current
    LaunchedEffect(Unit) {
        chrome.customTitle = null
        chrome.hasSubjectHeader = true
    }

    val palette = LocalSubjectPalette.current

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .subjectScreenWash(palette),
        contentPadding = PaddingValues(bottom = 20.dp)
    ) {
        item {
            // Below the status bar and the shell's floating back row, as the Settings hub does.
            Spacer(Modifier.height(WindowInsets.systemBars.asPaddingValues().calculateTopPadding() + 56.dp))
            SubjectHeaderBlock(
                kicker = "AO3 Account",
                title = "More on AO3",
                subtitle = "Opens on AO3 in Browse",
                palette = palette,
                gutter = SubjectMetrics.accountGutter
            )
        }

        MoreOnAO3.sections.forEach { section ->
            item(key = section.title) {
                Column(modifier = Modifier.padding(top = 18.dp)) {
                    SectionRuleHeader(section.title)
                    Column(
                        modifier = Modifier
                            .padding(top = 8.dp)
                            .padding(horizontal = SubjectMetrics.accountGutter)
                            .subjectPanel()
                    ) {
                        section.rows.forEachIndexed { index, row ->
                            if (index > 0) SubjectRowSeparator()
                            SubjectFormRow(
                                label = row.title,
                                // iOS's glyph in the accent before each row; Android's had none.
                                leadingIcon = row.icon,
                                showsDisclosure = true,
                                // A page of the reader's own has no address when signed out:
                                // the row does nothing, as on iOS.
                                onClick = { MoreOnAO3.url(row.target, username)?.let(onOpenWeb) }
                            )
                        }
                    }
                    section.footnote?.let { note ->
                        Text(
                            text = note,
                            style = MaterialTheme.typography.bodySmall,
                            color = LocalKudosTokens.current.secondaryInk,
                            modifier = Modifier
                                .padding(horizontal = SubjectMetrics.accountGutter)
                                .padding(top = 8.dp)
                        )
                    }
                }
            }
        }
    }
}

/**
 * iOS `AccountMoreOnAO3View` (artboard 1aa): the sections, rows and addresses, in its order.
 *
 * Each row used to hand the browser a bare path ("collections", "works/new"). The browser
 * keeps to AO3's own https addresses, refused it, and closed: **no row on this screen opened
 * anything.** The rows were also a different set from iOS's. Now every row has iOS's title
 * and a full address: a page of the reader's own (`/users/<name>/<suffix>`) or a site-wide
 * one, as `AccountExternalNavCard.Target` has it.
 */
internal object MoreOnAO3 {
    sealed interface Target {
        data class User(val suffix: String) : Target
        data class Site(val path: String) : Target
    }

    data class Row(val title: String, val target: Target, val icon: ImageVector)
    data class Section(val title: String, val rows: List<Row>, val footnote: String? = null)

    private fun user(title: String, suffix: String, icon: ImageVector) = Row(title, Target.User(suffix), icon)
    private fun site(title: String, path: String, icon: ImageVector) = Row(title, Target.Site(path), icon)

    val sections = listOf(
        Section(
            "Post and manage",
            listOf(
                site("Post new work", "/works/new", Icons.Outlined.Edit),
                site("Import work", "/works/new?import=true", Icons.Outlined.FileDownload),
                user("Edit works in bulk", "works/show_multiple", Icons.Outlined.Checklist),
                user("Manage collection items", "collection_items", Icons.Outlined.CollectionsBookmark),
                user("Related works", "related_works", Icons.AutoMirrored.Outlined.CallSplit),
                user("Drafts", "works/drafts", Icons.Outlined.Drafts)
            ),
            "These open your AO3 pages in Browse. You can find works, series, bookmarks, history and inbox " +
                "in the Reading, Writing and Activity sections of Account."
        ),
        Section(
            "Challenges",
            listOf(
                user("Sign-ups", "signups", Icons.Outlined.EditNote),
                user("Assignments", "assignments", Icons.AutoMirrored.Outlined.Assignment),
                user("Claims", "claims", Icons.Outlined.Flag),
                user("Gifts given and received", "gifts", Icons.Outlined.CardGiftcard)
            )
        ),
        Section(
            "Your account",
            listOf(
                user("Profile", "profile", Icons.Outlined.Badge),
                user("Invitations", "invitations", Icons.Outlined.Email),
                user("Skins and site styles", "skins", Icons.Outlined.Palette),
                user("Pseuds", "pseuds", Icons.Outlined.People),
                user("Co-Creator Requests", "creatorships", Icons.Outlined.PersonAdd),
                user("Statistics", "stats", Icons.Outlined.BarChart)
            )
        ),
        Section(
            "The archive",
            listOf(
                site("Support and feedback", "/support", Icons.AutoMirrored.Outlined.HelpOutline),
                site("Report abuse", "/abuse_reports/new", Icons.Outlined.ReportProblem),
                site("Terms of Service", "/tos", Icons.Outlined.Description),
                site("Content policy", "/content", Icons.AutoMirrored.Outlined.Article),
                site("Privacy policy", "/privacy", Icons.Outlined.PanTool),
                site("FAQs", "/faq", Icons.Outlined.QuestionAnswer),
                site("Donate to the OTW", "/donate", Icons.Outlined.FavoriteBorder)
            ),
            "These public AO3 pages open in Browse. You don't need to sign in to view them."
        )
    )

    /** The full address, or null for a page of the reader's own when nobody is signed in. */
    fun url(target: Target, username: String?): String? = when (target) {
        // As iOS's `siteWideURL` and `userURL`: one slash before a path, none after the account's root.
        is Target.Site -> "https://archiveofourown.org/${target.path.removePrefix("/")}"
        is Target.User -> username?.trim()?.takeIf { it.isNotEmpty() }?.let { name ->
            val encoded = java.net.URLEncoder.encode(name, "UTF-8").replace("+", "%20")
            "https://archiveofourown.org/users/$encoded" + target.suffix.takeIf { it.isNotEmpty() }?.let { "/$it" }.orEmpty()
        }
    }
}
