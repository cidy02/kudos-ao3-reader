package io.github.cidy02.kudos.backup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
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

    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text("Paired devices", style = MaterialTheme.typography.titleMedium)
            Text(
                "Deletions only cross devices you've paired. A backup file can never add a trusted device.",
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            if (unknownSignerCount > 0) {
                // Count-only: no key list, no names, no Trust affordance here.
                // Its only action is opening this same pairing sheet.
                AssistChip(
                    onClick = { showSheet = true },
                    label = {
                        Text(
                            if (unknownSignerCount == 1) {
                                "1 deletion skipped from an unpaired device"
                            } else {
                                "$unknownSignerCount deletions skipped from an unpaired device"
                            }
                        )
                    }
                )
            }

            if (trustedDevices.isEmpty()) {
                Text(
                    "No other devices paired yet.",
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

            Button(onClick = { showSheet = true }) {
                Text("Pair a device")
            }

            status?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
            }
        }
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
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text(displayLabel, style = MaterialTheme.typography.bodyMedium)
                Text(
                    device.publicKeyHex.take(8) + "…",
                    fontFamily = FontFamily.Monospace,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                TextButton(onClick = { renaming = true }) { Text("Rename") }
                if (withinUndoWindow) {
                    TextButton(onClick = onUndo) { Text("Undo Trust") }
                } else {
                    TextButton(
                        onClick = onRevoke,
                        colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)
                    ) { Text("Revoke") }
                }
            }
        }
        if (renaming) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedTextField(
                    value = nameDraft,
                    onValueChange = { nameDraft = it },
                    modifier = Modifier.weight(1f),
                    singleLine = true,
                    label = { Text("Name this device") }
                )
                TextButton(onClick = {
                    onRename(nameDraft)
                    renaming = false
                }) { Text("Save") }
            }
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
            Text("Pair a device", style = MaterialTheme.typography.titleLarge)
            Text(
                "Scan this device's code from your other device. Kudos on Android never scans a code itself.",
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            if (justTrustedHex == null) {
                Button(
                    onClick = { showQr = !showQr },
                    enabled = deviceHex.isNotBlank(),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(if (showQr) "Hide my QR code" else "Show my QR code")
                }

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

                OutlinedButton(
                    onClick = {
                        clipboard.setText(AnnotatedString(PairingKeyCodec.encode(deviceHex)))
                    },
                    enabled = deviceHex.isNotBlank(),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Copy Key")
                }

                TextButton(onClick = { showAdvanced = !showAdvanced }) {
                    Text(if (showAdvanced) "Hide advanced" else "Advanced: paste a key manually")
                }

                if (showAdvanced) {
                    OutlinedTextField(
                        value = pasteText,
                        onValueChange = { pasteText = it; error = null },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        label = { Text("Other device's key") },
                        placeholder = { Text("kudos-pub-v1:… or 64-char hex") }
                    )
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(
                            checked = confirmedFromOwnDevice,
                            onCheckedChange = { confirmedFromOwnDevice = it }
                        )
                        Text("I got this key from my other device")
                    }
                    Button(
                        onClick = {
                            val hex = PairingKeyCodec.decode(pasteText)
                            if (hex == null) {
                                error = "Not a recognizable Kudos device key."
                                return@Button
                            }
                            scope.launch {
                                if (trustStore.trust(hex)) {
                                    justTrustedHex = hex
                                } else {
                                    error = "That key can't be trusted (it may be revoked)."
                                }
                            }
                        },
                        enabled = PairingTrustGate.canTrust(pasteText, confirmedFromOwnDevice),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text("Trust")
                    }
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
                Text("Trusted. Name this device so you recognize it later.")
                OutlinedTextField(
                    value = trustLabel,
                    onValueChange = { trustLabel = it },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    label = { Text("Device name") },
                    placeholder = { Text("e.g. Sam's iPhone") }
                )
                Button(
                    onClick = {
                        val hex = justTrustedHex ?: return@Button
                        scope.launch {
                            if (trustLabel.isNotBlank()) trustStore.rename(hex, trustLabel)
                            onTrusted()
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Done")
                }
            }
        }
    }
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
        title = { Text("Revoke ${device.label.ifBlank { "this device" }}?") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("Why are you removing this device?")
                Row(verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(
                        selected = reason == KeyRevocationReason.STOLEN_OR_COMPROMISED,
                        onClick = { reason = KeyRevocationReason.STOLEN_OR_COMPROMISED }
                    )
                    Text("Stolen or compromised")
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(
                        selected = reason == KeyRevocationReason.RETIRED_OR_SOLD,
                        onClick = { reason = KeyRevocationReason.RETIRED_OR_SOLD }
                    )
                    Text("Retired or sold")
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onConfirm(reason) },
                colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)
            ) { Text("Revoke") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        }
    )
}
