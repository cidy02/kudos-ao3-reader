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

        item {
            Column(modifier = Modifier.padding(top = 18.dp)) {
                SectionRuleHeader("Post and manage")
                Column(
                    modifier = Modifier
                        .padding(top = 8.dp)
                        .padding(horizontal = SubjectMetrics.accountGutter)
                        .subjectPanel()
                ) {
                    AccountExternalNavCard("Post new work", "works/new", onOpenWeb)
                    SubjectRowSeparator()
                    AccountExternalNavCard("Import work", "works/new?import=true", onOpenWeb)
                    SubjectRowSeparator()
                    AccountExternalNavCard("Edit works in bulk", "works/show_multiple", onOpenWeb)
                    SubjectRowSeparator()
                    AccountExternalNavCard("New series", "series/new", onOpenWeb)
                    SubjectRowSeparator()
                    AccountExternalNavCard("Manage collections", "collections", onOpenWeb)
                }
                Text(
                    text = "These open your AO3 pages in Browse. You can find works, series, bookmarks, history and inbox in the Reading, Writing and Activity sections of Account.",
                    style = MaterialTheme.typography.bodySmall,
                    color = LocalKudosTokens.current.secondaryInk,
                    modifier = Modifier
                        .padding(horizontal = SubjectMetrics.accountGutter)
                        .padding(top = 8.dp)
                )
            }
        }

        item {
            Column(modifier = Modifier.padding(top = 18.dp)) {
                SectionRuleHeader("Challenges")
                Column(
                    modifier = Modifier
                        .padding(top = 8.dp)
                        .padding(horizontal = SubjectMetrics.accountGutter)
                        .subjectPanel()
                ) {
                    AccountExternalNavCard("Gift exchange", "collections/list_challenges?challenge_type=gift_exchange", onOpenWeb)
                    SubjectRowSeparator()
                    AccountExternalNavCard("Prompt meme", "collections/list_challenges?challenge_type=prompt_meme", onOpenWeb)
                    SubjectRowSeparator()
                    AccountExternalNavCard("My sign-ups", "signups", onOpenWeb)
                    SubjectRowSeparator()
                    AccountExternalNavCard("My assignments", "assignments", onOpenWeb)
                    SubjectRowSeparator()
                    AccountExternalNavCard("My claims", "claims", onOpenWeb)
                }
            }
        }

        item {
            Column(modifier = Modifier.padding(top = 18.dp)) {
                SectionRuleHeader("Your account")
                Column(
                    modifier = Modifier
                        .padding(top = 8.dp)
                        .padding(horizontal = SubjectMetrics.accountGutter)
                        .subjectPanel()
                ) {
                    AccountExternalNavCard("Edit profile", "profile/edit", onOpenWeb)
                    SubjectRowSeparator()
                    AccountExternalNavCard("Manage pseuds", "pseuds", onOpenWeb)
                    SubjectRowSeparator()
                    AccountExternalNavCard("Change username", "change_username", onOpenWeb)
                    SubjectRowSeparator()
                    AccountExternalNavCard("Change password", "change_password", onOpenWeb)
                    SubjectRowSeparator()
                    AccountExternalNavCard("Change email", "change_email", onOpenWeb)
                    SubjectRowSeparator()
                    AccountExternalNavCard("Blocked users", "blocked/users", onOpenWeb)
                    SubjectRowSeparator()
                    AccountExternalNavCard("Muted users", "muted/users", onOpenWeb)
                }
            }
        }

        item {
            Column(modifier = Modifier.padding(top = 18.dp)) {
                SectionRuleHeader("The archive")
                Column(
                    modifier = Modifier
                        .padding(top = 8.dp)
                        .padding(horizontal = SubjectMetrics.accountGutter)
                        .subjectPanel()
                ) {
                    AccountExternalNavCard("Support and feedback", "support", onOpenWeb)
                    SubjectRowSeparator()
                    AccountExternalNavCard("Report abuse", "abuse_reports/new", onOpenWeb)
                    SubjectRowSeparator()
                    AccountExternalNavCard("Terms of Service", "tos", onOpenWeb)
                    SubjectRowSeparator()
                    AccountExternalNavCard("Content policy", "content", onOpenWeb)
                    SubjectRowSeparator()
                    AccountExternalNavCard("Privacy policy", "privacy", onOpenWeb)
                    SubjectRowSeparator()
                    AccountExternalNavCard("FAQs", "faq", onOpenWeb)
                    SubjectRowSeparator()
                    AccountExternalNavCard("Donate to the OTW", "donate", onOpenWeb)
                }
            }
        }
    }
}

@Composable
private fun AccountExternalNavCard(
    title: String,
    path: String,
    onOpenWeb: (String) -> Unit
) {
    SubjectFormRow(
        label = title,
        showsDisclosure = true,
        onClick = { onOpenWeb(path) }
    )
}
