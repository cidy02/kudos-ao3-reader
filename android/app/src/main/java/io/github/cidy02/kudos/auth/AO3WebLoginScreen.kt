package io.github.cidy02.kudos.auth

import android.graphics.Bitmap
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
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
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.AO3Result
import kotlinx.coroutines.launch

@Composable
fun AO3WebLoginScreen(
    authRepository: AO3AuthRepository,
    onLoginComplete: () -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier
) {
    var loading by remember { mutableStateOf(true) }
    var message by remember {
        mutableStateOf("Log in on AO3's page below. Kudos never sees or stores your password.")
    }
    val scope = rememberCoroutineScope()
    var webViewRef by remember { mutableStateOf<WebView?>(null) }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("AO3 Login", style = MaterialTheme.typography.headlineSmall)
        Text(message, style = MaterialTheme.typography.bodyMedium)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = onCancel) {
                Text("Cancel")
            }
            Button(onClick = { webViewRef?.loadUrl(LoginUrl) }) {
                Text("Reload")
            }
            if (loading) CircularProgressIndicator()
        }
        AndroidView(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
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
                            return !request.url.host.orEmpty().endsWith(AO3Constants.WORKS_HOST)
                        }

                        override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
                            loading = true
                        }

                        override fun onPageFinished(view: WebView, url: String?) {
                            loading = false
                            view.evaluateJavascript(AO3WebLoginInspection.Script) { raw ->
                                val inspection = AO3WebLoginInspection.parseJavascriptResult(raw)
                                if (inspection.loggedIn && inspection.username != null) {
                                    scope.launch {
                                        when (authRepository.acceptWebLogin(inspection.username)) {
                                            is AO3Result.Success -> onLoginComplete()
                                            is AO3Result.Failure -> {
                                                message = "AO3 login was detected, but the session could not be captured."
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

private const val LoginUrl = "https://archiveofourown.org/users/login"
