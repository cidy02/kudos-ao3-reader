package io.github.cidy02.kudos.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.AO3AuthState
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.network.ao3.browse.FandomCatalogCache
import io.github.cidy02.kudos.ui.components.DestructiveConfirmation
import io.github.cidy02.kudos.ui.components.LogOutConfirmation
import io.github.cidy02.kudos.ui.subject.*
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

internal object PrivacyCopy {
    const val promiseTitle = "No ads or tracking, and no separate Kudos account"
    const val promise = "Kudos connects to AO3. After you approve a Voice Pack download, it also connects to the service providing the pack. Your library, reading positions, tags, collections, and AO3 sign-in stay on this device."
    const val stored = "The sizes shown are measured on this device. Browse keeps fandom and category lists so it opens faster; it rebuilds them when needed, and your device may remove them to free space."
    const val clear = "Each option asks before it clears anything and tells you what will change on this device. Your AO3 reading history is separate; clear it from History or turn it off in AO3 Preferences."
    const val session = "Your AO3 sign-in is kept only on this device and is never shared."
    const val voiceTitle = "Optional Voice Pack downloads stay separate from your reading data."
    const val voice = "Kudos never sends a work's text, spoken audio, your AO3 sign-in, saved works, reading history, usage information, or anything that identifies your account to the Voice Pack provider. The provider can see your IP address and basic details about the connection. Kudos tells you this before downloading a Voice Pack, and the installed voices stay on this device."
}

@Composable
fun PrivacyDataScreen(
    workRepository: WorkRepository?,
    fandomCatalogCache: FandomCatalogCache?,
    settings: KudosSettings,
    authRepository: AO3AuthRepository? = null,
    footprintScanner: LocalDataFootprintScanner? = null
) {
    ProvidePushedShellChrome()
    val tokens = LocalKudosTokens.current
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val cache = remember(fandomCatalogCache, context) {
        fandomCatalogCache ?: FandomCatalogCache(context.cacheDir.toPath())
    }
    val signedOut = remember { MutableStateFlow<AO3AuthState>(AO3AuthState.SignedOut) }
    val noNotice = remember { MutableStateFlow<String?>(null) }
    val auth by (authRepository?.state ?: signedOut).collectAsState()
    val notice by (authRepository?.noticeMessage ?: noNotice).collectAsState()
    val history by remember(workRepository) {
        workRepository?.observeHistoryOnlyWorks() ?: flowOf(emptyList())
    }.collectAsState(initial = null)
    val positions by remember(workRepository) {
        workRepository?.observePositionedWorks() ?: flowOf(emptyList())
    }.collectAsState(initial = null)
    val freeable by remember(workRepository) {
        workRepository?.observeFreeableCopies() ?: flowOf(emptyList())
    }.collectAsState(initial = null)
    var footprint by remember(footprintScanner) { mutableStateOf<LocalStorageFootprint?>(null) }
    var measurement by remember { mutableIntStateOf(0) }
    LaunchedEffect(footprintScanner, measurement) {
        footprint = footprintScanner?.measure()
    }
    var browseCacheCleared by remember { mutableStateOf(false) }
    var confirming by remember { mutableStateOf<String?>(null) }
    var confirmingLogout by remember { mutableStateOf(false) }
    fun bytes(value: Long?) = value?.let { LocalStorageFootprint.formatted(it) } ?: "—"
    fun count(value: Int?, noun: String) = value?.let { countLabel(it, noun) } ?: "—"

    SettingsPage(title = "Privacy", kicker = "AO3 Account › Settings",
        subtitle = "Your reading data stays on this device") {
        item {
            val mint = SubjectPalette.fromHue(SubjectHueSwatches.all.first { it.name == "Mint" }.hue, tokens.theme)
            val shape = RoundedCornerShape(16.dp)
            Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 14.dp)
                .background(mint.panelWash, shape).border(0.5.dp, mint.rowBorder, shape)
                .padding(horizontal = 18.dp, vertical = 16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(PrivacyCopy.promiseTitle, color = tokens.primaryInk, fontSize = 17.sp,
                    lineHeight = 23.sp, fontWeight = FontWeight.SemiBold)
                Text(PrivacyCopy.promise, color = tokens.secondaryInk, fontSize = 13.sp, lineHeight = 18.sp)
            }
        }
        item {
            PrivacySection("Stored on this device") {
                if (footprintScanner != null) {
                    // Like iOS, conditional rows stay absent until positive; always-visible
                    // figures show an em dash until the off-main scan finishes.
                    val rows = footprint?.sizeRows() ?: listOf("Downloaded works" to null,
                        "Draft recovery" to null, "Caches" to null)
                    rows.forEachIndexed { index, (label, value) ->
                        if (index > 0) SubjectRowSeparator()
                        PrivacyFigureRow(label, bytes(value))
                    }
                    SubjectRowSeparator()
                    PrivacyFigureRow("Reading positions", count(positions?.size, "work"))
                    SubjectRowSeparator()
                    PrivacyFigureRow("Local collections", footprint?.localCollections?.toString() ?: "—")
                    SubjectRowSeparator()
                    PrivacyFigureRow("Saved searches", footprint?.savedSearches?.toString() ?: "—")
                    SubjectRowSeparator()
                }
                PrivacyFigureRow("Search history", "Not recorded", monospaced = false)
            }
            PrivacyFootnote(PrivacyCopy.stored)
        }
        item {
            PrivacySection("Clear") {
                PrivacyFigureRow("Free up space", count(freeable?.size, "file"), destructive = true,
                    enabled = !freeable.isNullOrEmpty(), onClick = { confirming = "space" })
                SubjectRowSeparator()
                PrivacyFigureRow("Clear reading positions", count(positions?.size, "work"), destructive = true,
                    enabled = !positions.isNullOrEmpty(), onClick = { confirming = "positions" })
                SubjectRowSeparator()
                PrivacyFigureRow("Clear reading history", count(history?.size, "work"), destructive = true,
                    enabled = !history.isNullOrEmpty(), onClick = { confirming = "history" })
                SubjectRowSeparator()
                PrivacyFigureRow(if (browseCacheCleared) "Browse cache cleared" else "Clear browse cache",
                    if (footprintScanner != null) bytes(footprint?.cacheBytes) else null,
                    destructive = !browseCacheCleared, enabled = !browseCacheCleared,
                    onClick = { confirming = "browse" })
            }
            PrivacyFootnote(PrivacyCopy.clear)
        }
        item {
            PrivacySection("AO3 session") {
                val signedIn = auth as? AO3AuthState.SignedIn
                if (signedIn != null) {
                    PrivacyFigureRow("Signed in", signedIn.username, monospaced = false)
                    SubjectRowSeparator()
                    SettingsActionRow("Remove AO3 session", destructive = true, onClick = { confirmingLogout = true })
                } else {
                    PrivacyFigureRow("AO3 account", "Not signed in", monospaced = false)
                }
            }
            PrivacyFootnote(PrivacyCopy.session + (notice?.let { " $it" } ?: ""))
        }
        item {
            PrivacySection("Read Aloud downloads") {
                Column(Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(PrivacyCopy.voiceTitle, color = tokens.primaryInk, fontSize = 15.sp,
                        lineHeight = 21.sp, fontWeight = FontWeight.SemiBold)
                    Text(PrivacyCopy.voice, color = tokens.secondaryInk, fontSize = 12.5.sp, lineHeight = 18.sp)
                }
            }
        }
    }

    val confirmations = listOf(
        Triple("space", "Free Up Space?", "Removes the copies of works you've finished reading and didn't download, favourite or queue. Kudos gets them again from AO3 if you open them."),
        Triple("positions", "Clear Reading Positions?", "Clears your place in every work. Your works and their order in Continue Reading stay the same."),
        Triple("history", "Clear Reading History?", "Moves works that only remain in your reading history to Recently Deleted for 90 days. Your saved and downloaded works stay where they are, and you can download these works from AO3 again."),
        Triple("browse", "Clear Browse Cache?", "Removes saved fandom and category lists. Your reading, saved works, and downloads stay untouched; Browse rebuilds the lists next time you open it.")
    )
    for ((key, title, message) in confirmations) {
        DestructiveConfirmation(show = confirming == key, title = title, text = message,
            confirmText = when (key) {
                "space" -> "Free ${count(freeable?.size, "File")}"
                "positions" -> "Clear ${count(positions?.size, "Position")}"
                "history" -> "Clear ${count(history?.size, "Work")}"
                else -> if (footprintScanner != null) "Clear ${bytes(footprint?.cacheBytes)}" else "Clear"
            }, confirmBeforeDelete = settings.app.confirmBeforeDelete,
            onConfirm = {
                confirming = null
                scope.launch {
                    when (key) {
                        "space" -> workRepository?.freeFinishedCopies()
                        "positions" -> workRepository?.clearReadingPositions()
                        "history" -> workRepository?.softDeleteHistoryOnly()
                        else -> { cache.clear(); browseCacheCleared = true }
                    }
                    measurement++
                }
            }, onDismissRequest = { confirming = null })
    }
    LogOutConfirmation(show = confirmingLogout, onConfirm = {
        confirmingLogout = false
        scope.launch { authRepository?.logout() }
    }, onDismissRequest = { confirmingLogout = false })
}

@Composable
private fun PrivacySection(title: String, content: @Composable () -> Unit) {
    Column(Modifier.padding(top = 18.dp)) {
        CompositionLocalProvider(LocalTextStyle provides LocalTextStyle.current.copy(lineHeight = 15.sp)) {
            SectionRuleHeader(title)
        }
        Column(Modifier.padding(top = 8.dp).padding(horizontal = SubjectMetrics.accountGutter).subjectPanel()) {
            content()
        }
    }
}

@Composable
private fun PrivacyFootnote(text: String) {
    Text(text, color = LocalKudosTokens.current.secondaryInk, fontSize = 12.5.sp, lineHeight = 18.sp,
        modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 8.dp))
}

/** Short trailing facts let long labels wrap; AX stacks the entire fact without ellipsis. */
@Composable
private fun PrivacyFigureRow(label: String, value: String?, monospaced: Boolean = true,
    destructive: Boolean = false, enabled: Boolean = true, onClick: (() -> Unit)? = null
) {
    val tokens = LocalKudosTokens.current
    val color = when {
        !enabled -> tokens.secondaryInk.copy(alpha = 0.45f)
        destructive -> MaterialTheme.colorScheme.error
        else -> tokens.primaryInk
    }
    val stacked = isAccessibilityFontScale()
    CompositionLocalProvider(LocalKudosTokens provides tokens.copy(primaryInk = color)) {
        SubjectFormRow(label, modifier = Modifier.testTag("privacy-$label").semantics { if (!enabled) disabled() },
            value = if (stacked) value else null, valueMaxLines = Int.MAX_VALUE,
            showsDisclosure = enabled && onClick != null, onClick = onClick?.takeIf { enabled },
            trailing = if (stacked || value == null) null else {
                { Text(value, color = tokens.secondaryInk, fontSize = 14.5.sp, lineHeight = 20.sp,
                    fontFamily = if (monospaced) FontFamily.Monospace else FontFamily.Default) }
            })
    }
}

internal fun countLabel(count: Int, noun: String): String = "$count $noun${if (count == 1) "" else "s"}"
