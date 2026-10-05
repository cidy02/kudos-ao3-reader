package io.github.cidy02.kudos.support

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.BuildConfig
import io.github.cidy02.kudos.settings.SettingsGroupLabel
import io.github.cidy02.kudos.settings.SettingsPanel
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens

data class ChangelogEntry(val version: String, val notes: String)

/** Bundled, newest first. Add a paragraph with the release's version here. No fetch. */
object Changelog {
    val entries = listOf(
        ChangelogEntry(
            version = "0.2.1",
            notes = "Welcome to Kudos — a native Android reader for Archive of Our Own."
        )
    )
    val currentVersion: String get() = BuildConfig.VERSION_NAME

    fun unseenEntries(lastSeen: String?, currentVersion: String, entries: List<ChangelogEntry>): List<ChangelogEntry> {
        if (lastSeen == null || lastSeen == currentVersion) return emptyList()
        val index = entries.indexOfFirst { it.version == lastSeen }
        return if (index < 0) entries else entries.take(index)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WhatsNewSheet(entries: List<ChangelogEntry>, onDone: () -> Unit, onDismiss: () -> Unit) {
    val tokens = LocalKudosTokens.current
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        scrimColor = Color.Black.copy(alpha = 0.32f),
        containerColor = tokens.theme.cardBackdrop,
        contentColor = tokens.primaryInk,
        dragHandle = { BottomSheetDefaults.DragHandle(color = tokens.secondaryInk) }
    ) {
        WhatsNewContent(entries, onDone)
    }
}

@Composable
fun WhatsNewContent(entries: List<ChangelogEntry>, onDone: () -> Unit, modifier: Modifier = Modifier) {
    val tokens = LocalKudosTokens.current
    Column(modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            verticalAlignment = androidx.compose.ui.Alignment.CenterVertically
        ) {
            Text("What's New", color = tokens.primaryInk, fontSize = 20.sp, lineHeight = 28.sp,
                modifier = Modifier.weight(1f))
            IconButton(onClick = onDone,
                colors = IconButtonDefaults.iconButtonColors(contentColor = tokens.accent)) {
                Icon(Icons.Filled.Check, contentDescription = "Done")
            }
        }
        entries.forEach { entry ->
            Column(Modifier.padding(top = 22.dp)) {
                SettingsGroupLabel("Version ${entry.version}")
                SettingsPanel {
                    Text(entry.notes, color = tokens.primaryInk, fontSize = 14.sp, lineHeight = 21.sp,
                        modifier = Modifier.padding(13.dp))
                }
            }
        }
    }
}
