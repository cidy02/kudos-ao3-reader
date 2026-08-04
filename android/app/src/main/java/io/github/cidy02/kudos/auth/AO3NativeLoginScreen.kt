package io.github.cidy02.kudos.auth

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import io.github.cidy02.kudos.network.ao3.AO3Result
import kotlinx.coroutines.launch

/**
 * Native username/password login with a hidden WebView that submits AO3's own
 * form over HTTPS. Visible WebView is a fallback ("alternative method").
 * Port of iOS `AO3LoginView` defaults.
 *
 * Credentials are never written to disk — only AO3 session cookies after a
 * successful login (encrypted via [EncryptedFileAO3SessionStore]).
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun AO3NativeLoginScreen(
    authRepository: AO3AuthRepository,
    onLoginComplete: () -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier
) {
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var message by remember {
        mutableStateOf("Sign in with your AO3 account. Your password is sent only to AO3 over HTTPS.")
    }
    var loading by remember { mutableStateOf(false) }
    var useWebFallback by remember { mutableStateOf(false) }
    var webViewRef by remember { mutableStateOf<WebView?>(null) }
    var pendingSubmit by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    if (useWebFallback) {
        Column(modifier = modifier.fillMaxSize()) {
            Text(
                text = "Using alternative method — log in on AO3's page.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(16.dp)
            )
            AO3WebLoginScreen(
                authRepository = authRepository,
                onLoginComplete = onLoginComplete,
                onCancel = onCancel,
                modifier = Modifier.weight(1f)
            )
            TextButton(
                onClick = { useWebFallback = false },
                modifier = Modifier.padding(16.dp)
            ) {
                Text("Back to username/password")
            }
        }
        return
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        OutlinedTextField(
            value = username,
            onValueChange = { username = it },
            label = { Text("Username or email") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            enabled = !loading
        )
        OutlinedTextField(
            value = password,
            onValueChange = { password = it },
            label = { Text("Password") },
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            modifier = Modifier.fillMaxWidth(),
            enabled = !loading
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = onCancel, enabled = !loading) { Text("Cancel") }
            Button(
                enabled = !loading && username.isNotBlank() && password.isNotBlank(),
                onClick = {
                    loading = true
                    message = "Signing in…"
                    pendingSubmit = true
                    // Reload login page then inject credentials into AO3's form.
                    webViewRef?.loadUrl(LoginUrl)
                }
            ) {
                if (loading) CircularProgressIndicator(modifier = Modifier.height(18.dp))
                else Text("Sign in")
            }
        }
        TextButton(onClick = { useWebFallback = true }, enabled = !loading) {
            Text("Use alternative method")
        }

        // Hidden off-screen WebView — always HTTPS archiveofourown.org.
        AndroidView(
            modifier = Modifier
                .fillMaxWidth()
                .height(1.dp),
            factory = { context ->
                WebView(context).apply {
                    webViewRef = this
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    webViewClient = object : WebViewClient() {
                        override fun onPageFinished(view: WebView, url: String?) {
                            if (pendingSubmit && url?.contains("/users/login") == true) {
                                pendingSubmit = false
                                val userJs = jsonEscape(username.trim())
                                val passJs = jsonEscape(password)
                                // Only fill on https://archiveofourown.org
                                val script = """
                                    (function() {
                                      if (location.protocol !== 'https:' ||
                                          location.hostname !== 'archiveofourown.org') {
                                        return JSON.stringify({ok:false, reason:'bad-host'});
                                      }
                                      var form = document.querySelector('form#new_user, form[action*="/users/login"]');
                                      if (!form) return JSON.stringify({ok:false, reason:'no-form'});
                                      var u = form.querySelector('input[name="user[login]"]');
                                      var p = form.querySelector('input[name="user[password]"]');
                                      if (!u || !p) return JSON.stringify({ok:false, reason:'no-fields'});
                                      u.value = "$userJs";
                                      p.value = "$passJs";
                                      form.submit();
                                      return JSON.stringify({ok:true});
                                    })();
                                """.trimIndent()
                                view.evaluateJavascript(script) { result ->
                                    if (result?.contains("\"ok\":false") == true ||
                                        result?.contains("ok\":false") == true
                                    ) {
                                        loading = false
                                        message = "Couldn't find AO3's login form. Try the alternative method."
                                        password = ""
                                    }
                                }
                                return
                            }
                            // After submit, inspect session like web login.
                            view.evaluateJavascript(AO3WebLoginInspection.Script) { raw ->
                                val inspection = AO3WebLoginInspection.parseJavascriptResult(raw)
                                if (inspection.loggedIn && inspection.username != null) {
                                    scope.launch {
                                        when (authRepository.acceptWebLogin(inspection.username)) {
                                            is AO3Result.Success -> {
                                                password = ""
                                                onLoginComplete()
                                            }
                                            is AO3Result.Failure -> {
                                                loading = false
                                                message = "Signed in on AO3, but the session could not be saved."
                                                password = ""
                                            }
                                        }
                                    }
                                } else if (url?.contains("/users/login") != true && loading) {
                                    // Still navigating after submit — wait.
                                } else if (!pendingSubmit && loading &&
                                    url?.contains("/users/login") == true
                                ) {
                                    // Failed login landed back on login page.
                                    loading = false
                                    message = "Login failed. Check your username and password."
                                    password = ""
                                }
                            }
                        }

                        override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                            // Keep loading flag true during navigation after submit.
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
            password = ""
        }
    }
}

private fun jsonEscape(value: String): String {
    return value
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
}

private const val LoginUrl = "https://archiveofourown.org/users/login"
