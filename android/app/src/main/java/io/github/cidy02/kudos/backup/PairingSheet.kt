package io.github.cidy02.kudos.backup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.foundation.Image
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.settings.SettingsActionRow
import io.github.cidy02.kudos.settings.SettingsSection
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectToggle
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.works.WorkRepository
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.launch

/**
 * Keysync v1 pairing entry point, shown in the Backup screen. Android's
 * pairing role is QR-generate-only (iOS scans — a sibling unit); this device
 * never scans a code itself.
 */
@Composable
fun PairingCard(
    settingsRepository: SettingsRepository,
    database: KudosDatabase,
    workRepository: WorkRepository
) {
    val tokens = LocalKudosTokens.current
    MaterialTheme(
        colorScheme = MaterialTheme.colorScheme.copy(
            primary = tokens.accent,
            onSurface = tokens.primaryInk,
            onSurfaceVariant = tokens.secondaryInk,
            surface = tokens.background,
            surfaceContainerLow = tokens.background
        )
    ) {
        PairingContent(settingsRepository, database, workRepository)
    }
}

@Composable
private fun PairingContent(
    settingsRepository: SettingsRepository,
    database: KudosDatabase,
    workRepository: WorkRepository
) {
    val trustStore = remember { TombstoneTrustStore(settingsRepository) }
    val revocationService = remember {
        KeyRevocationService(trustStore, database, workRepository)
    }
    val scope = rememberCoroutineScope()

    var showSheet by remember { mutableStateOf(false) }
    var trustedDevices by remember { mutableStateOf<List<TrustedDevice>>(emptyList()) }
    var unknownSignerCount by remember { mutableStateOf(0) }
    var revokeTarget by remember { mutableStateOf<TrustedDevice?>(null) }
    var status by remember { mutableStateOf<String?>(null) }

    // Re-read whenever the underlying trust set changes — trust()/revoke()
    // both write TrustedTombstonePublicKeys, so this Flow is the refresh signal.
    val trustedHexes by settingsRepository.trustedTombstonePublicKeys.collectAsState(initial = emptySet())
    LaunchedEffect(trustedHexes) {
        trustedDevices = trustStore.trustedDevices()
    }
    val unknownSignerIds by settingsRepository.unknownSignerTombstoneIds.collectAsState(initial = emptySet())
    LaunchedEffect(unknownSignerIds) {
        unknownSignerCount = unknownSignerIds.size
    }

    val deviceKey = remember {
        runCatching { TombstoneSigning.publicKeyHex() }.getOrDefault("")
    }.ifBlank { "Unavailable" }
    val pairingContent: @Composable ColumnScope.() -> Unit = {
        Text(
            "This device",
            modifier = Modifier.padding(horizontal = 13.dp),
            color = LocalKudosTokens.current.primaryInk,
            fontSize = 16.sp
        )
        SelectionContainer(modifier = Modifier.padding(horizontal = 13.dp)) {
            Text(
                text = deviceKey,
                fontFamily = FontFamily.Monospace,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        SubjectRowSeparator()

        if (unknownSignerCount > 0) {
            val label = if (unknownSignerCount == 1) {
                "1 deletion skipped from an unpaired device"
            } else {
                "$unknownSignerCount deletions skipped from an unpaired device"
            }
            SettingsActionRow(label = label, onClick = { showSheet = true })
        }

        if (trustedDevices.isEmpty()) {
            Text(
                "No other devices paired yet.",
                modifier = Modifier.padding(horizontal = 13.dp),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            trustedDevices.forEach { device ->
                TrustedDeviceRow(
                    device = device,
                    onRename = { newLabel ->
                        scope.launch {
                            trustStore.rename(device.publicKeyHex, newLabel)
                            trustedDevices = trustStore.trustedDevices()
                        }
                    },
                    onUndo = {
                        scope.launch {
                            if (trustStore.undoTrust(device.publicKeyHex)) {
                                trustedDevices = trustStore.trustedDevices()
                                status = "Undid trust for that device."
                            }
                        }
                    },
                    onRevoke = { revokeTarget = device }
                )
            }
        }

        SubjectRowSeparator()
        SettingsActionRow(label = "Pair a Device", onClick = { showSheet = true })
        status?.let {
            Text(
                it,
                modifier = Modifier.padding(horizontal = 13.dp),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.primary
            )
        }
    }
    SettingsSection(
        label = "Deletion signing",
        // Android has no automatic Apple-account trust: two devices take each other's
        // deletions only once each has paired the other.
        footnote = "Kudos checks that deletions came from one of your devices. Pair each of your " +
            "other devices here, and pair this one on each of them: scan its QR code or " +
            "share its pairing code. Deletions from a device that is not paired are " +
            "ignored. A backup file can never mark a device as trusted."
    ) {
        Column(
            modifier = Modifier.padding(vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            content = pairingContent
        )
    }

    if (showSheet) {
        PairingBottomSheet(
            trustStore = trustStore,
            onDismiss = { showSheet = false },
            onTrusted = {
                scope.launch { trustedDevices = trustStore.trustedDevices() }
                showSheet = false
            }
        )
    }

    revokeTarget?.let { target ->
        RevokeDeviceDialog(
            device = target,
            onDismiss = { revokeTarget = null },
            onConfirm = { reason ->
                scope.launch {
                    revocationService.revoke(target.publicKeyHex, reason)
                    trustedDevices = trustStore.trustedDevices()
                    if (reason == KeyRevocationReason.STOLEN_OR_COMPROMISED) {
                        val restored = revocationService.restoreWorksDeletedBy(target.publicKeyHex)
                        status = if (restored > 0) {
                            "Revoked. Restored $restored work(s) that device had deleted."
                        } else {
                            "Revoked that device."
                        }
                    } else {
                        status = "Revoked that device."
                    }
                }
                revokeTarget = null
            }
        )
    }
}

@Composable
private fun TrustedDeviceRow(
    device: TrustedDevice,
    onRename: (String) -> Unit,
    onUndo: () -> Unit,
    onRevoke: () -> Unit
) {
    var renaming by remember(device.publicKeyHex) { mutableStateOf(false) }
    var nameDraft by remember(device.publicKeyHex) { mutableStateOf(device.label) }
    val withinUndoWindow = Duration.between(device.trustedAt, Instant.now()) <= Duration.ofHours(24)
    val displayLabel = device.label.ifBlank { "Unnamed device" }

    Column(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(horizontal = 13.dp)) {
            Text(displayLabel, style = MaterialTheme.typography.bodyMedium)
            Text(
                device.publicKeyHex.take(8) + "…",
                fontFamily = FontFamily.Monospace,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        SettingsActionRow(label = "Rename", onClick = { renaming = true })
        if (withinUndoWindow) {
            SettingsActionRow(label = "Undo Trust", onClick = onUndo)
        } else {
            SettingsActionRow(label = "Revoke", onClick = onRevoke, destructive = true)
        }
        if (renaming) {
            // No text-input primitive exists in the settings chrome yet.
            OutlinedTextField(
                value = nameDraft,
                onValueChange = { nameDraft = it },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 13.dp).padding(top = 4.dp),
                singleLine = true,
                label = { Text("Name this device") }
            )
            SettingsActionRow(label = "Save", onClick = {
                onRename(nameDraft)
                renaming = false
            })
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PairingBottomSheet(
    trustStore: TombstoneTrustStore,
    onDismiss: () -> Unit,
    onTrusted: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val clipboard = LocalClipboardManager.current
    val scope = rememberCoroutineScope()

    var deviceHex by remember { mutableStateOf("") }
    var showQr by remember { mutableStateOf(false) }
    var showAdvanced by remember { mutableStateOf(false) }
    var pasteText by remember { mutableStateOf("") }
    var confirmedFromOwnDevice by remember { mutableStateOf(false) }
    var trustLabel by remember { mutableStateOf("") }
    var justTrustedHex by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        deviceHex = TombstoneSigning.publicKeyHex()
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            modifier = Modifier
                .padding(horizontal = 20.dp)
                .padding(bottom = 24.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    "Pair a Device",
                    style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier.weight(1f)
                )
                TextButton(onClick = onDismiss) { Text("Close") }
            }
            Text(
                "Scan this device's code from your other device. Kudos on Android never scans a code itself.",
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            if (justTrustedHex == null) {
                PairingAction(
                    label = if (showQr) "Hide My QR Code" else "Show My QR Code",
                    onClick = { showQr = !showQr },
                    enabled = deviceHex.isNotBlank()
                )

                if (showQr && deviceHex.isNotBlank()) {
                    val payload = PairingKeyCodec.encode(deviceHex)
                    val bitmap = remember(deviceHex) { QrCodeGenerator.encode(payload) }
                    Image(
                        bitmap = bitmap.asImageBitmap(),
                        contentDescription = "QR code of this device's public key",
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(220.dp)
                    )
                }

                PairingAction(
                    label = "Copy My Key",
                    onClick = {
                        clipboard.setText(AnnotatedString(PairingKeyCodec.encode(deviceHex)))
                    },
                    enabled = deviceHex.isNotBlank()
                )

                PairingAction(
                    label = "Advanced: paste a key manually",
                    onClick = { showAdvanced = !showAdvanced }
                )

                if (showAdvanced) {
                    OutlinedTextField(
                        value = pasteText,
                        onValueChange = { pasteText = it; error = null },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        label = { Text("Other device's key") },
                        placeholder = { Text("kudos-pub-v1:… or 64-char hex") }
                    )
                    SubjectFormRow(
                        label = "I got this key from my other device",
                        modifier = Modifier.subjectPanel(),
                        trailing = {
                            SubjectToggle(
                                checked = confirmedFromOwnDevice,
                                onCheckedChange = { confirmedFromOwnDevice = it },
                                contentDescription = "I got this key from my other device"
                            )
                        }
                    )

                    PairingAction(
                        label = "Trust",
                        onClick = {
                            val hex = PairingKeyCodec.decode(pasteText)
                            if (hex == null) {
                                error = "Not a recognizable Kudos device key."
                                return@PairingAction
                            }
                            scope.launch {
                                if (trustStore.trust(hex)) {
                                    justTrustedHex = hex
                                } else {
                                    error = "That key can't be trusted (it may be revoked)."
                                }
                            }
                        },
                        enabled = PairingTrustGate.canTrust(pasteText, confirmedFromOwnDevice)
                    )
                    error?.let {
                        Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                    }
                }

                SelectionContainer {
                    Text(
                        deviceHex.ifBlank { "Generating…" },
                        fontFamily = FontFamily.Monospace,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            } else {
                // Trusted just now — name it locally. Never pre-filled from
                // the QR/pasted payload; the field starts blank.
                Text(
                    "This device is now trusted. Give it a name you will recognize later."
                )
                OutlinedTextField(
                    value = trustLabel,
                    onValueChange = { trustLabel = it },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    label = { Text("Device name") },
                    placeholder = { Text("e.g. Sam's iPhone") }
                )
                PairingAction(
                    label = "Done",
                    onClick = {
                        val hex = justTrustedHex ?: return@PairingAction
                        scope.launch {
                            if (trustLabel.isNotBlank()) trustStore.rename(hex, trustLabel)
                            onTrusted()
                        }
                    }
                )
            }
        }
    }
}

/** Pairing actions share the settings form chrome on both pages. */
@Composable
private fun PairingAction(
    label: String,
    onClick: () -> Unit,
    enabled: Boolean = true
) {
    SettingsActionRow(
        label = label,
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier.subjectPanel()
    )
}

@Composable
private fun RevokeDeviceDialog(
    device: TrustedDevice,
    onDismiss: () -> Unit,
    onConfirm: (KeyRevocationReason) -> Unit
) {
    // Stolen/compromised is the default-selected, safe-lazy option.
    var reason by remember { mutableStateOf(KeyRevocationReason.STOLEN_OR_COMPROMISED) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text("Revoke ${device.label.ifBlank { "this device" }}?", color = LocalKudosTokens.current.primaryInk)
        },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text("Why are you removing this device?", color = LocalKudosTokens.current.primaryInk)
                Column(Modifier.subjectPanel()) {
                    SubjectFormRow(
                        label = "Stolen or compromised",
                        trailing = {
                            RadioButton(
                                selected = reason == KeyRevocationReason.STOLEN_OR_COMPROMISED,
                                onClick = { reason = KeyRevocationReason.STOLEN_OR_COMPROMISED }
                            )
                        }
                    )
                    SubjectRowSeparator()
                    SubjectFormRow(
                        label = "Retired or sold",
                        trailing = {
                            RadioButton(
                                selected = reason == KeyRevocationReason.RETIRED_OR_SOLD,
                                onClick = { reason = KeyRevocationReason.RETIRED_OR_SOLD }
                            )
                        }
                    )
                }
            }
        },
        confirmButton = {
            SettingsActionRow(label = "Revoke", onClick = { onConfirm(reason) }, destructive = true)
        },
        dismissButton = {
            SettingsActionRow(label = "Cancel", onClick = onDismiss)
        }
    )
}
