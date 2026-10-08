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
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
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

    data class Row(val title: String, val target: Target)
    data class Section(val title: String, val rows: List<Row>, val footnote: String? = null)

    private fun user(title: String, suffix: String) = Row(title, Target.User(suffix))
    private fun site(title: String, path: String) = Row(title, Target.Site(path))

    val sections = listOf(
        Section(
            "Post and manage",
            listOf(
                site("Post new work", "/works/new"),
                site("Import work", "/works/new?import=true"),
                user("Edit works in bulk", "works/show_multiple"),
                user("Manage collection items", "collection_items"),
                user("Related works", "related_works"),
                user("Drafts", "works/drafts")
            ),
            "These open your AO3 pages in Browse. You can find works, series, bookmarks, history and inbox " +
                "in the Reading, Writing and Activity sections of Account."
        ),
        Section(
            "Challenges",
            listOf(
                user("Sign-ups", "signups"),
                user("Assignments", "assignments"),
                user("Claims", "claims"),
                user("Gifts given and received", "gifts")
            )
        ),
        Section(
            "Your account",
            listOf(
                user("Profile", "profile"),
                user("Invitations", "invitations"),
                user("Skins and site styles", "skins"),
                user("Pseuds", "pseuds"),
                user("Co-Creator Requests", "creatorships"),
                user("Statistics", "stats")
            )
        ),
        Section(
            "The archive",
            listOf(
                site("Support and feedback", "/support"),
                site("Report abuse", "/abuse_reports/new"),
                site("Terms of Service", "/tos"),
                site("Content policy", "/content"),
                site("Privacy policy", "/privacy"),
                site("FAQs", "/faq"),
                site("Donate to the OTW", "/donate")
            ),
            "These public AO3 pages open in Browse. You don't need to sign in to view them."
        )
    )

    /** The full address, or null for a page of the reader's own when nobody is signed in. */
    fun url(target: Target, username: String?): String? = when (target) {
        is Target.Site -> "https://archiveofourown.org${target.path}"
        is Target.User -> username?.trim()?.takeIf { it.isNotEmpty() }?.let { name ->
            val encoded = java.net.URLEncoder.encode(name, "UTF-8").replace("+", "%20")
            "https://archiveofourown.org/users/$encoded/${target.suffix}"
        }
    }
}
