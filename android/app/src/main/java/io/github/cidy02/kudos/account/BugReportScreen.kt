package io.github.cidy02.kudos.account

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BugReport
import androidx.compose.material.icons.outlined.List
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.BuildConfig

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

@Composable
fun BugReportScreen(
    onBack: () -> Unit
) {
    val context = LocalContext.current
    var summary by remember { mutableStateOf("") }
    val versionString = bugReportVersionString(
        versionName = BuildConfig.VERSION_NAME,
        versionCode = BuildConfig.VERSION_CODE,
        gitCommitSha = BuildConfig.GIT_COMMIT_SHA
    )
    val systemInfo = "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT}); ${Build.MANUFACTURER} ${Build.MODEL}"

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text("Report a Bug", style = MaterialTheme.typography.headlineSmall)
        Text(
            text = "Found a bug? Describe what happened and Kudos will open a prefilled GitHub issue you can review and post. Nothing is sent automatically.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        OutlinedTextField(
            value = summary,
            onValueChange = { summary = it },
            label = { Text("What went wrong?") },
            placeholder = { Text("What happened, and what did you expect instead?") },
            minLines = 4,
            modifier = Modifier.fillMaxWidth()
        )

        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("Included with your report", style = MaterialTheme.typography.titleSmall)
            ReportInfoRow(label = "App version", value = versionString)
            ReportInfoRow(label = "System", value = systemInfo)
            Text(
                text = "Only these app and system details are attached — no personal data, and never your AO3 account.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        HorizontalDivider()

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Button(
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
                },
                enabled = summary.trim().isNotBlank(),
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(Icons.Outlined.BugReport, contentDescription = null)
                Text("Continue on GitHub", modifier = Modifier.padding(start = 8.dp))
            }

            OutlinedButton(
                onClick = {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/cidy02/kudos-ao3-reader/issues"))
                    context.startActivity(intent)
                },
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(Icons.Outlined.List, contentDescription = null)
                Text("Browse existing issues", modifier = Modifier.padding(start = 8.dp))
            }

            TextButton(onClick = onBack, modifier = Modifier.fillMaxWidth()) {
                Text("Cancel")
            }
        }

        Text(
            text = "Please don't contact the AO3 team about Kudos — they can't provide support for this app.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 8.dp)
        )
    }
}

@Composable
private fun ReportInfoRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, style = MaterialTheme.typography.bodyMedium)
        Text(value, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
