package io.github.cidy02.kudos.account

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.outlined.BugReport
import androidx.compose.material.icons.outlined.Code
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.BuildConfig
import io.github.cidy02.kudos.settings.SettingsActionRow
import io.github.cidy02.kudos.settings.SettingsPage
import io.github.cidy02.kudos.settings.SettingsPanel
import io.github.cidy02.kudos.settings.SettingsSection
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens

/**
 * Settings › About (iOS `AboutView`): the app's identity, its license, the open-source
 * components it is built on, where to send feedback, and the AO3 disclaimer.
 */
@Composable
fun AboutScreen(onReportBug: () -> Unit) {
    val context = LocalContext.current
    val tokens = LocalKudosTokens.current

    SettingsPage(title = "About") {
        item {
            SettingsPanel(Modifier.padding(top = 22.dp)) {
                Column(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 13.dp, vertical = 18.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Icon(
                        imageVector = Icons.Filled.Book,
                        contentDescription = null,
                        tint = tokens.accent,
                        modifier = Modifier.size(42.dp)
                    )
                    Text("Kudos", color = tokens.primaryInk, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                    Text(
                        // The same string a bug report carries: with the commit, on a build
                        // that knows it (iOS `AboutView.versionString`).
                        text = "Version " + bugReportVersionString(
                            versionName = BuildConfig.VERSION_NAME,
                            versionCode = BuildConfig.VERSION_CODE,
                            gitCommitSha = BuildConfig.GIT_COMMIT_SHA
                        ),
                        color = tokens.secondaryInk,
                        fontSize = 13.sp
                    )
                    Text(
                        text = "Read and save Archive of Our Own works on your Android devices.",
                        color = tokens.secondaryInk,
                        fontSize = 15.sp,
                        textAlign = TextAlign.Center
                    )
                }
            }
        }
        item {
            SettingsSection(footnote = null, label = "License") {
                Text(
                    text = buildAnnotatedString {
                        append("Kudos is free to use, study, share, and change under the ")
                        withStyle(SpanStyle(fontWeight = FontWeight.Bold)) {
                            append("GNU Affero General Public License v3.0 (AGPL-3.0)")
                        }
                        append(".")
                    },
                    modifier = Modifier.padding(horizontal = 13.dp, vertical = 12.dp),
                    color = tokens.primaryInk,
                    fontSize = 16.sp,
                    lineHeight = 22.sp
                )
            }
        }
        item {
            SettingsSection(footnote = null, label = "Open-Source Components") {
                CreditRow(
                    name = "Jsoup",
                    license = "MIT License",
                    detail = "Reads AO3 pages so Kudos can show works.",
                    url = "https://github.com/jhy/jsoup"
                )
                SubjectRowSeparator()
                CreditRow(
                    name = "Readium Kotlin Toolkit",
                    license = "BSD-3-Clause",
                    detail = "Displays downloaded works in the reader.",
                    url = "https://github.com/readium/kotlin-toolkit"
                )
                SubjectRowSeparator()
                CreditRow(
                    name = "ao3_api",
                    license = "Reference",
                    detail = "Helped guide how Kudos reads AO3 pages.",
                    url = "https://github.com/ArmindoFlores/ao3_api"
                )
            }
        }
        item {
            SettingsSection(footnote = null, label = "Help & Feedback") {
                SettingsActionRow(label = "Report a Bug", onClick = onReportBug, icon = Icons.Outlined.BugReport)
                SubjectRowSeparator()
                SettingsActionRow(
                    label = "View on GitHub",
                    onClick = { openUrl(context, REPOSITORY) },
                    icon = Icons.Outlined.Code
                )
            }
        }
        item {
            SettingsSection(footnote = null, label = "Disclaimer") {
                Text(
                    text = "Kudos is an unofficial personal project. It isn't affiliated with or " +
                        "endorsed by the Organization for Transformative Works or Archive of Our " +
                        "Own. AO3 doesn't provide an official way for apps to read its pages, " +
                        "so Kudos reads the same public pages you can visit.",
                    modifier = Modifier.padding(horizontal = 13.dp, vertical = 12.dp),
                    color = tokens.secondaryInk,
                    fontSize = 13.sp,
                    lineHeight = 18.sp
                )
            }
        }
    }
}

@Composable
private fun CreditRow(name: String, license: String, detail: String, url: String) {
    val context = LocalContext.current
    val tokens = LocalKudosTokens.current
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 13.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp)
    ) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = name,
                modifier = Modifier.weight(1f),
                color = tokens.primaryInk,
                fontSize = 16.sp,
                fontWeight = FontWeight.Medium
            )
            Text(license, color = tokens.secondaryInk, fontSize = 12.sp)
        }
        Text(detail, color = tokens.secondaryInk, fontSize = 12.sp, lineHeight = 16.sp)
        Text(
            text = url.removePrefix("https://"),
            modifier = Modifier.clickable { openUrl(context, url) },
            color = tokens.accent,
            fontSize = 12.sp
        )
    }
}

private const val REPOSITORY = "https://github.com/cidy02/kudos-ao3-reader"

private fun openUrl(context: android.content.Context, url: String) {
    runCatching {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    }
}
