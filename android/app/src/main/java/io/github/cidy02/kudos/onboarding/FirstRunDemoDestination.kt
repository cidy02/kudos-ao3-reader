package io.github.cidy02.kudos.onboarding

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import io.github.cidy02.kudos.auth.AO3NativeLoginScreen
import io.github.cidy02.kudos.support.Changelog
import io.github.cidy02.kudos.support.WhatsNewSheet
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens

/** Review-only routing: no repository, picker, authentication or flag writes. */
@Composable
fun FirstRunDemoDestination(screen: FirstRunDemoScreen, onClose: () -> Unit) {
    BackHandler(onBack = onClose)
    when (screen) {
        FirstRunDemoScreen.Welcome -> WelcomeScreen(onContinue = onClose, onBack = onClose)
        FirstRunDemoScreen.SyncOnboarding -> {
            var dontRemind by remember { mutableStateOf(false) }
            SyncFolderOnboardingContent(
                dontRemindAgain = dontRemind,
                onDontRemindAgainChange = { dontRemind = it },
                isConnecting = false,
                connectionError = null,
                onChooseFolder = {},
                onNotNow = onClose
            )
        }
        FirstRunDemoScreen.WhatsNew -> {
            Box(Modifier.fillMaxSize().background(LocalKudosTokens.current.background)) {
                WhatsNewSheet(Changelog.entries, onDone = onClose, onDismiss = onClose)
            }
        }
        FirstRunDemoScreen.Login -> AO3NativeLoginScreen(
            authRepository = null,
            onLoginComplete = {},
            onCancel = onClose,
            demo = true
        )
    }
}
