package io.github.cidy02.kudos.account

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.List
import androidx.compose.material.icons.outlined.BugReport
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.BuildConfig
import io.github.cidy02.kudos.settings.SettingsActionRow
import io.github.cidy02.kudos.settings.SettingsPage
import io.github.cidy02.kudos.settings.SettingsPanel
import io.github.cidy02.kudos.settings.SettingsSection
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens

/**
 * Version field for bug reports — mirrors iOS `AboutView.versionString`:
 * `1.0 (1) · abc1234` when a git SHA is available, otherwise `1.0 (1)`.
 * [gitCommitSha] is empty when the build wasn't from a git checkout (or git
 * was unavailable at configure time); never invent a placeholder SHA.
 */
internal fun bugReportVersionString(
    versionName: String,
    versionCode: Int,
    gitCommitSha: String
): String {
    val base = "$versionName ($versionCode)"
    val sha = gitCommitSha.trim()
    return if (sha.isNotEmpty()) "$base · $sha" else base
}

/**
 * Report a Bug (iOS `BugReportView`). Nothing is sent automatically: the reader writes the
 * report, sees exactly which app and system details go with it, and posts it as a prefilled
 * GitHub issue they can review and edit first.
 *
 * Opened from About it is a pushed page, and the shell's back button leaves it. Opened by a
 * shake it stands alone over the app, with nothing to leave by: [onCancel] is iOS's Cancel.
 */
@Composable
fun BugReportScreen(onCancel: (() -> Unit)? = null) {
    val context = LocalContext.current
    val tokens = LocalKudosTokens.current
    var summary by rememberSaveable { mutableStateOf("") }
    val versionString = bugReportVersionString(
        versionName = BuildConfig.VERSION_NAME,
        versionCode = BuildConfig.VERSION_CODE,
        gitCommitSha = BuildConfig.GIT_COMMIT_SHA
    )
    val systemInfo = "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT}); ${Build.MANUFACTURER} ${Build.MODEL}"

    SettingsPage(title = "Report a Bug") {
        item {
            SettingsPanel(Modifier.padding(top = 22.dp)) {
                Text(
                    text = "Found a bug? Describe what happened and Kudos will open a prefilled " +
                        "GitHub issue you can review and post. Nothing is sent automatically.",
                    modifier = Modifier.padding(horizontal = 13.dp, vertical = 12.dp),
                    color = tokens.secondaryInk,
                    fontSize = 13.sp,
                    lineHeight = 18.sp
                )
            }
        }
        item {
            SettingsSection(footnote = null, label = "What went wrong?") {
                BasicTextField(
                    value = summary,
                    onValueChange = { summary = it },
                    minLines = 4,
                    maxLines = 10,
                    textStyle = TextStyle(color = tokens.primaryInk, fontSize = 16.sp, lineHeight = 22.sp),
                    cursorBrush = SolidColor(tokens.accent),
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 13.dp, vertical = 12.dp),
                    decorationBox = { inner ->
                        Box(Modifier.fillMaxWidth()) {
                            if (summary.isEmpty()) {
                                Text(
                                    text = "What happened, and what did you expect instead?",
                                    color = tokens.secondaryInk,
                                    fontSize = 16.sp,
                                    lineHeight = 22.sp
                                )
                            }
                            inner()
                        }
                    }
                )
            }
        }
        item {
            SettingsSection(footnote = null, label = "Included with your report") {
                // Whole, however long: this is the list of what goes with the report.
                SubjectFormRow("App version", value = versionString, valueMaxLines = Int.MAX_VALUE)
                SubjectRowSeparator()
                SubjectFormRow("System", value = systemInfo, valueMaxLines = Int.MAX_VALUE)
                SubjectRowSeparator()
                Text(
                    text = "Only these app and system details are sent with your report. Nothing " +
                        "personal is included, and never your AO3 account.",
                    modifier = Modifier.padding(horizontal = 13.dp, vertical = 12.dp),
                    color = tokens.secondaryInk,
                    fontSize = 12.sp,
                    lineHeight = 16.sp
                )
            }
        }
        item {
            SettingsSection(
                footnote = "The AO3 team can't help with Kudos, so please don't contact them about it."
            ) {
                SettingsActionRow(
                    label = "Continue on GitHub",
                    icon = Icons.Outlined.BugReport,
                    enabled = summary.trim().isNotBlank(),
                    onClick = {
                        val body = """
                        **What happened?**
                        
                        ${summary.trim()}
                        
                        ---
                        - App: $versionString
                        - System: $systemInfo
                    """.trimIndent()
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/cidy02/kudos-ao3-reader/issues/new?title=Bug%20report&body=${Uri.encode(body)}"))
                        context.startActivity(intent)
                    }
                )
                SubjectRowSeparator()
                SettingsActionRow(
                    label = "Browse existing issues",
                    icon = Icons.AutoMirrored.Outlined.List,
                    onClick = {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/cidy02/kudos-ao3-reader/issues"))
                        context.startActivity(intent)
                    }
                )
            }
        }
        if (onCancel != null) {
            item {
                SettingsSection(footnote = null) {
                    SettingsActionRow(label = "Cancel", onClick = onCancel)
                }
            }
        }
    }
}
