package io.github.cidy02.kudos.auth

import android.graphics.Bitmap
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.DemoNetwork
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun AO3WebLoginScreen(
    authRepository: AO3AuthRepository?,
    onLoginComplete: () -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier,
    demo: Boolean = false
) {
    val largeType = isAccessibilityFontScale()
    val tokens = LocalKudosTokens.current
    val networkAllowed = loginNetworkAllowed(demo, DemoNetwork.isActive)
    var loading by remember { mutableStateOf(networkAllowed) }
    var message by remember {
        mutableStateOf(DefaultMessage)
    }
    val scope = rememberCoroutineScope()
    var webViewRef by remember { mutableStateOf<WebView?>(null) }
    var timeoutJob by remember { mutableStateOf<Job?>(null) }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // The native host supplies the login title.
        Text(
            text = message,
            style = MaterialTheme.typography.bodyMedium,
            lineHeight = 21.sp,
            color = tokens.secondaryInk
        )
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = onCancel,
                border = BorderStroke(1.dp, tokens.accent),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = tokens.accent)) {
                Text("Cancel", lineHeight = 20.sp)
            }
            Button(onClick = { if (networkAllowed) webViewRef?.loadUrl(LoginUrl) },
                colors = ButtonDefaults.buttonColors(containerColor = tokens.accent,
                    contentColor = SubjectPalette.label(tokens.accent))) {
                Text("Reload", lineHeight = 20.sp)
            }
            if (loading) CircularProgressIndicator(color = tokens.accent)
        }
        if (networkAllowed) AndroidView(
            modifier = Modifier
                .fillMaxWidth()
                .then(if (largeType) Modifier.height(600.dp) else Modifier.weight(1f)),
            factory = { context ->
                WebView(context).apply {
                    webViewRef = this
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    webViewClient = object : WebViewClient() {
                        override fun shouldOverrideUrlLoading(
                            view: WebView,
                            request: WebResourceRequest
                        ): Boolean {
                            return !AO3StoredCookie.isAO3Domain(request.url.host.orEmpty())
                        }

                        override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
                            loading = true
                            message = DefaultMessage
                            timeoutJob?.cancel()
                            timeoutJob = scope.launch {
                                delay(PageLoadTimeoutMs)
                                if (loading) {
                                    message = StallMessage
                                }
                            }
                        }

                        override fun onPageFinished(view: WebView, url: String?) {
                            timeoutJob?.cancel()
                            timeoutJob = null
                            loading = false
                            view.evaluateJavascript(AO3WebLoginInspection.Script) { raw ->
                                val inspection = AO3WebLoginInspection.parseJavascriptResult(raw)
                                if (inspection.loggedIn && inspection.username != null) {
                                    scope.launch {
                                        when (requireNotNull(authRepository).acceptWebLogin(inspection.username)) {
                                            is AO3Result.Success -> onLoginComplete()
                                            is AO3Result.Failure -> {
                                                message = "AO3 logged in, but its session cookie could not be captured."
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    loadUrl(LoginUrl)
                }
            },
            update = {}
        )
    }

    DisposableEffect(Unit) {
        onDispose {
            timeoutJob?.cancel()
            timeoutJob = null
            webViewRef?.stopLoading()
            webViewRef = null
        }
    }
}

data class AO3WebLoginInspection(
    val loggedIn: Boolean,
    val username: String?
) {
    companion object {
        const val Script: String = """
            (function() {
              var loggedIn = document.body && document.body.classList.contains('logged-in');
              loggedIn = loggedIn || !!document.querySelector('a[href="/users/logout"], form[action="/users/logout"]');
              var username = null;
              var links = document.querySelectorAll('#greeting a[href^="/users/"]');
              for (var i = 0; i < links.length; i++) {
                var href = links[i].getAttribute('href') || '';
                if (href.indexOf('/users/') === 0 && href.indexOf('/users/login') !== 0 && href.indexOf('/users/logout') !== 0) {
                  username = decodeURIComponent(href.substring('/users/'.length).split('/')[0]);
                  break;
                }
              }
              return JSON.stringify({ loggedIn: loggedIn, username: username });
            })();
        """

        fun parseJavascriptResult(raw: String?): AO3WebLoginInspection {
            if (raw.isNullOrBlank() || raw == "null") return AO3WebLoginInspection(false, null)
            val payload = raw.trim()
                .removeSurrounding("\"")
                .replace("\\\\\"", "\"")
                .replace("\\\"", "\"")
            val loggedIn = Regex(""""loggedIn"\s*:\s*true""").containsMatchIn(payload)
            val username = Regex(""""username"\s*:\s*"([^"]+)"""")
                .find(payload)
                ?.groupValues
                ?.getOrNull(1)
                ?.takeIf { it.isNotBlank() && it != "null" }
            return AO3WebLoginInspection(loggedIn = loggedIn, username = username)
        }
    }
}

private const val DefaultMessage = "Let's finish logging in on AO3's page below."
private const val StallMessage = "This is taking a while - try Reload, or check your connection."
private const val PageLoadTimeoutMs = 25_000L
private const val LoginUrl = "https://archiveofourown.org/users/login"

