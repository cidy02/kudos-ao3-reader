package io.github.cidy02.kudos.account

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.BuildConfig

@Composable
fun AboutScreen(
    onReportBug: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val versionString = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("Kudos", style = MaterialTheme.typography.headlineSmall)
        Text(
            text = "Version $versionString",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = "A native Archive of Our Own reader for Android.",
            style = MaterialTheme.typography.bodyLarge
        )

        OutlinedButton(
            onClick = onReportBug,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Report a Bug")
        }

        HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))

        Text("License", style = MaterialTheme.typography.titleMedium)
        Text(
            text = "Kudos is free software, released under the GNU Affero General " +
                "Public License v3.0 (AGPL-3.0). You may use, study, share, and modify it under the " +
                "terms of that license.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))

        Text("Open-Source Components", style = MaterialTheme.typography.titleMedium)
        DependencyCredit(
            name = "Jsoup",
            license = "MIT License",
            detail = "HTML parsing for AO3 scraping.",
            url = "https://github.com/jhy/jsoup",
            onOpenUrl = { openUrl(context, it) }
        )
        DependencyCredit(
            name = "Readium Kotlin Toolkit",
            license = "BSD-3-Clause",
            detail = "The EPUB reading engine.",
            url = "https://github.com/readium/kotlin-toolkit",
            onOpenUrl = { openUrl(context, it) }
        )

        HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))

        Text("Disclaimer", style = MaterialTheme.typography.titleMedium)
        Text(
            text = "Kudos is an unofficial, open-source app and is not affiliated with " +
                "Archive of Our Own or the Organization for Transformative Works. " +
                "It reads AO3's public web pages — AO3 has no official API.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = "AO3 login uses AO3's real login page. Kudos never stores your password. " +
                "Session cookies stay on this device and are excluded from backups.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(4.dp))
        Text(
            text = "Source: github.com/cidy02/kudos-ao3-reader",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.clickable {
                openUrl(context, "https://github.com/cidy02/kudos-ao3-reader")
            }
        )
    }
}

@Composable
private fun DependencyCredit(
    name: String,
    license: String,
    detail: String,
    url: String,
    onOpenUrl: (String) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(name, style = MaterialTheme.typography.bodyMedium)
            Text(
                text = license,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Text(
            text = detail,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = url.removePrefix("https://"),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.clickable { onOpenUrl(url) }
        )
    }
}

private fun openUrl(context: android.content.Context, url: String) {
    runCatching {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    }
}
