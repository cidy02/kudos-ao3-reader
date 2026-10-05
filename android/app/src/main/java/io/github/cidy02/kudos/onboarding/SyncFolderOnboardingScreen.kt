package io.github.cidy02.kudos.onboarding

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.SyncProblem
import androidx.compose.material.icons.outlined.VerifiedUser
import androidx.compose.material.icons.outlined.WifiOff
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.app.KudosAppContainer
import io.github.cidy02.kudos.backup.SyncResult
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import kotlinx.coroutines.launch

@Composable
fun SyncFolderOnboardingScreen(
    container: KudosAppContainer,
    onFinished: (permanentlyDismissed: Boolean) -> Unit,
    modifier: Modifier = Modifier
) {
    val scope = rememberCoroutineScope()
    var dontRemindAgain by remember { mutableStateOf(false) }
    var isConnecting by remember { mutableStateOf(false) }
    var connectionError by remember { mutableStateOf<String?>(null) }
    androidx.activity.compose.BackHandler {
        if (!isConnecting) onFinished(dontRemindAgain)
    }

    val launcher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocumentTree()
    ) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        isConnecting = true
        connectionError = null
        
        scope.launch {
            try {
                container.syncRepository.connect(uri)
                when (val result = container.syncRepository.runSync()) {
                    is SyncResult.Error -> {
                        connectionError = result.message
                        return@launch
                    }
                    SyncResult.SkippedAlreadyRunning -> return@launch
                    is SyncResult.Success -> Unit
                }

                container.settingsRepository.setHasConfiguredSyncFolder(true)
                onFinished(false)
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                connectionError = e.localizedMessage ?: "Unknown error"
            } finally {
                isConnecting = false
            }
        }
    }

    SyncFolderOnboardingContent(
        dontRemindAgain = dontRemindAgain,
        onDontRemindAgainChange = { dontRemindAgain = it },
        isConnecting = isConnecting,
        connectionError = connectionError,
        onChooseFolder = { launcher.launch(null) },
        onNotNow = { onFinished(dontRemindAgain) },
        modifier = modifier
    )
}

@Composable
fun SyncFolderOnboardingContent(
    dontRemindAgain: Boolean,
    onDontRemindAgainChange: (Boolean) -> Unit,
    isConnecting: Boolean,
    connectionError: String?,
    onChooseFolder: () -> Unit,
    onNotNow: () -> Unit,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    OnboardingScaffold(modifier = modifier, content = {
        SyncFolderHeader()
        SyncFolderPoints(connectionError)
    }, footer = {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}
                .toggleable(
                    value = dontRemindAgain,
                    role = Role.Checkbox,
                    onValueChange = onDontRemindAgainChange
                )
        ) {
            Checkbox(
                checked = dontRemindAgain,
                onCheckedChange = null,
                colors = CheckboxDefaults.colors(
                    checkedColor = tokens.accent,
                    checkmarkColor = SubjectPalette.label(tokens.accent),
                    uncheckedColor = tokens.secondaryInk
                )
            )
            Text("Don't remind me again", style = MaterialTheme.typography.bodyMedium,
                color = tokens.primaryInk, lineHeight = 21.sp)
        }
        Button(
            onClick = onChooseFolder,
            modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = tokens.accent,
                contentColor = SubjectPalette.label(tokens.accent),
                disabledContainerColor = tokens.glassFill(0.12),
                disabledContentColor = tokens.secondaryInk
            ),
            enabled = !isConnecting
        ) {
            if (isConnecting) {
                CircularProgressIndicator(
                    modifier = Modifier.size(24.dp),
                    color = tokens.accent
                )
            } else {
                Text("Choose Sync Folder", style = MaterialTheme.typography.titleMedium, lineHeight = 24.sp)
            }
        }
        TextButton(onClick = onNotNow, enabled = !isConnecting,
            colors = ButtonDefaults.textButtonColors(contentColor = tokens.accent,
                disabledContentColor = tokens.secondaryInk)) {
            Text("Not Now", lineHeight = 20.sp)
        }
    })
}

@Composable
private fun SyncFolderHeader() {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Surface(
            shape = RoundedCornerShape(24.dp),
            color = LocalKudosTokens.current.glassFill(0.09),
            modifier = Modifier.size(108.dp)
        ) {
            Icon(
                imageVector = Icons.Outlined.Folder,
                contentDescription = null,
                modifier = Modifier.padding(24.dp),
                tint = LocalKudosTokens.current.accent
            )
        }
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = "Protect Your Library",
                style = MaterialTheme.typography.headlineLarge,
                color = LocalKudosTokens.current.primaryInk,
                lineHeight = 40.sp,
                textAlign = TextAlign.Center
            )
            Text(
                text = "Optional. You can set this up anytime in Settings",
                style = MaterialTheme.typography.titleSmall,
                lineHeight = 20.sp,
                color = LocalKudosTokens.current.secondaryInk,
                textAlign = TextAlign.Center
            )
        }
    }
}

@Composable
private fun SyncFolderPoints(error: String?) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(22.dp)
    ) {
        OnboardingPoint(
            icon = Icons.Outlined.Folder,
            title = "Choose a Folder",
            body = "Choose where Kudos keeps another copy of your library. " +
                "Use the system folder picker. If the folder belongs to a cloud storage app, " +
                "that app can keep it up to date on your devices."
        )
        OnboardingPoint(
            icon = Icons.Outlined.WifiOff,
            title = "Works Fully Offline",
            body = "You can use Kudos without an internet connection. If you skip this, " +
                "you can choose a folder later in Settings."
        )
        OnboardingPoint(
            icon = Icons.Outlined.SyncProblem,
            title = "Changes May Take Time",
            body = "Kudos saves the same kind of file as a backup in your folder. Updates " +
                "aren't instant."
        )
        OnboardingPoint(
            icon = Icons.Outlined.VerifiedUser,
            title = "Using More Than One Device?",
            body = "To let another device remove items from your library, pair it in Settings " +
                "→ Sync Folder → Deletion signing. Pairing takes a few seconds."
        )
        if (error != null) {
            OnboardingPoint(
                icon = Icons.Outlined.ErrorOutline,
                title = "Couldn't Connect",
                body = error
            )
        }
    }
}
