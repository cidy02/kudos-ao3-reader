package io.github.cidy02.kudos.auth

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.Login
import androidx.compose.material.icons.outlined.PersonAdd
import androidx.compose.material.icons.outlined.PersonOutline
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.DemoNetwork
import io.github.cidy02.kudos.settings.SettingsFootnote
import io.github.cidy02.kudos.settings.SettingsPanel
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale
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
    authRepository: AO3AuthRepository?,
    onLoginComplete: () -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier,
    onOpenAO3: (String) -> Unit = {},
    demo: Boolean = false
) {
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var message by remember { mutableStateOf<String?>(null) }
    val networkAllowed = loginNetworkAllowed(demo, DemoNetwork.isActive)
    val tokens = LocalKudosTokens.current
    val largeType = isAccessibilityFontScale()
    var loading by remember { mutableStateOf(false) }
    var useWebFallback by remember { mutableStateOf(false) }
    var webViewRef by remember { mutableStateOf<WebView?>(null) }
    var pendingSubmit by remember { mutableStateOf(false) }
    var submitTimestamp by remember { mutableStateOf(0L) }
    val scope = rememberCoroutineScope()

    // iOS parity: 25s timeout for login submission (Item 7 note).
    LaunchedEffect(loading, submitTimestamp) {
        if (!loading || submitTimestamp == 0L) return@LaunchedEffect
        kotlinx.coroutines.delay(25_000)
        if (loading) {
            loading = false
            useWebFallback = true
            message = FallbackPrompt
            password = ""
        }
    }

    if (!demo) {
        // The shell's single-line bar would truncate this title at large type.
        // Keep its Android Back affordance and let this page lay out its own header.
        ProvidePushedShellChrome(hasSubjectHeader = true, onBack = onCancel)
    }
    val headerInset = if (demo) Modifier.safeDrawingPadding() else Modifier.padding(
        top = WindowInsets.systemBars.asPaddingValues().calculateTopPadding() + 56.dp
    )

    if (useWebFallback) {
        Column(modifier = modifier.fillMaxSize().background(tokens.background)
            .then(headerInset)
            .then(if (largeType) Modifier.verticalScroll(rememberScrollState()) else Modifier)) {
            LoginHeader(onCancel)
            Text(
                text = "Using alternative login method…",
                style = MaterialTheme.typography.titleMedium,
                lineHeight = 21.sp,
                color = tokens.secondaryInk,
                modifier = Modifier.padding(16.dp)
            )
            AO3WebLoginScreen(
                authRepository = authRepository,
                onLoginComplete = onLoginComplete,
                onCancel = onCancel,
                demo = !networkAllowed,
                modifier = if (largeType) Modifier.fillMaxWidth() else Modifier.weight(1f)
            )
            TextButton(
                colors = ButtonDefaults.textButtonColors(contentColor = tokens.accent),
                onClick = { useWebFallback = false },
                modifier = Modifier.padding(16.dp)
            ) {
                Text("Back to username/password", lineHeight = 20.sp)
            }
        }
        return
    }

    Column(
        modifier = modifier.fillMaxSize().background(tokens.background)
            .then(headerInset)
            .imePadding().verticalScroll(rememberScrollState()).padding(vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(22.dp)
    ) {
        LoginHeader(onCancel)
        Column {
            Row(Modifier.padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Outlined.PersonOutline, contentDescription = null, tint = tokens.secondaryInk)
                Text("AO3 Account", color = tokens.secondaryInk, fontSize = 15.sp, lineHeight = 21.sp)
            }
            Spacer(Modifier.height(8.dp))
            SettingsPanel {
                LoginField("Username or email", username, { username = it }, !loading)
                SubjectRowSeparator()
                LoginField("Password", password, { password = it }, !loading, secure = true)
            }
            SettingsFootnote("Kudos submits these credentials only to AO3's official login page. " +
                "Your password is never saved.")
        }
        message?.let { error ->
            SettingsPanel {
                Row(Modifier.padding(13.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    val errorColor = SubjectPalette.fromHue(0.0, tokens.theme).accent
                    Icon(Icons.Outlined.ErrorOutline, contentDescription = null, tint = errorColor)
                    Text(error, color = errorColor, lineHeight = 21.sp)
                }
            }
        }
        Button(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = tokens.accent,
                contentColor = SubjectPalette.label(tokens.accent),
                disabledContainerColor = tokens.glassFill(0.12),
                disabledContentColor = tokens.secondaryInk
            ),
            enabled = !loading && username.isNotBlank() && password.isNotBlank(),
            onClick = {
                if (networkAllowed) {
                    loading = true
                    message = null
                    pendingSubmit = true
                    submitTimestamp = System.currentTimeMillis()
                    // Existing login attempt mechanics.
                    webViewRef?.loadUrl(LoginUrl)
                }
            }
        ) {
            if (loading) {
                CircularProgressIndicator(modifier = Modifier.size(18.dp), color = tokens.primaryInk)
                Spacer(Modifier.width(8.dp))
            }
            if (!loading) {
                Icon(Icons.Outlined.Login, contentDescription = null)
                Spacer(Modifier.width(8.dp))
            }
            Text(if (loading) "Logging In…" else "Log In", lineHeight = 22.sp)
        }
        Column {
            SettingsPanel {
                TextButton(
                    onClick = { if (networkAllowed) onOpenAO3(SignUpUrl) },
                    colors = ButtonDefaults.textButtonColors(contentColor = tokens.accent)
                ) {
                    Icon(Icons.Outlined.PersonAdd, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("Create an AO3 account", lineHeight = 22.sp)
                }
                SubjectRowSeparator()
                TextButton(
                    onClick = { if (networkAllowed) onOpenAO3(PasswordResetUrl) },
                    colors = ButtonDefaults.textButtonColors(contentColor = tokens.accent)
                ) {
                    Icon(Icons.Outlined.Key, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("Forgot your password?", lineHeight = 22.sp)
                }
            }
            SettingsFootnote("These open AO3 in the Browse tab. Come back here to log in afterwards.")
        }
        // Keep the existing explicit fallback entry; it changes no requests.
        TextButton(onClick = { useWebFallback = true },
            colors = ButtonDefaults.textButtonColors(contentColor = tokens.accent),
            modifier = Modifier.padding(horizontal = 16.dp)) {
            Text("Use alternative method", lineHeight = 22.sp)
        }

        // Hidden off-screen WebView — always HTTPS archiveofourown.org.
        if (networkAllowed) AndroidView(
            modifier = Modifier
                .fillMaxWidth()
                .height(1.dp),
            factory = { context ->
                WebView(context).apply {
                    webViewRef = this
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    webViewClient = object : WebViewClient() {
                        override fun onReceivedError(
                            view: WebView?,
                            request: android.webkit.WebResourceRequest?,
                            error: android.webkit.WebResourceError?
                        ) {
                            if (loading && request?.isForMainFrame == true) {
                                loading = false
                                message = "AO3 could not load. Check your connection and try again."
                                password = ""
                            }
                        }

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
                                        // Not iOS's words here: iOS moves to AO3's page by itself
                                        // at this point and Android does not, so "below" would
                                        // point at nothing.
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
                                        when (requireNotNull(authRepository).acceptWebLogin(inspection.username)) {
                                            is AO3Result.Success -> {
                                                password = ""
                                                onLoginComplete()
                                            }
                                            is AO3Result.Failure -> {
                                                loading = false
                                                message = "AO3 logged in, but the session could not be saved securely."
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

/** The demo never mounts WebView (which bypasses the OkHttp demo interceptor). */
internal fun loginNetworkAllowed(demo: Boolean, demoNetworkActive: Boolean): Boolean =
    !demo && !demoNetworkActive

@Composable
private fun LoginHeader(onCancel: () -> Unit) {
    val tokens = LocalKudosTokens.current
    val cancel: @Composable () -> Unit = {
        TextButton(onClick = onCancel,
            colors = ButtonDefaults.textButtonColors(contentColor = tokens.accent)) {
            Text("Cancel", lineHeight = 20.sp)
        }
    }
    if (isAccessibilityFontScale()) {
        Column(Modifier.padding(horizontal = 16.dp)) {
            Text("Log In to AO3", color = tokens.primaryInk, fontSize = 22.sp, lineHeight = 30.sp)
            cancel()
        }
    } else {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            Text("Log In to AO3", color = tokens.primaryInk, fontSize = 22.sp, lineHeight = 30.sp,
                modifier = Modifier.weight(1f))
            cancel()
        }
    }
}

@Composable
private fun LoginField(label: String, value: String, onValueChange: (String) -> Unit,
    enabled: Boolean, secure: Boolean = false) {
    val tokens = LocalKudosTokens.current
    Column(Modifier.fillMaxWidth().padding(13.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(label, color = tokens.secondaryInk, fontSize = 14.sp, lineHeight = 20.sp)
        BasicTextField(
            value = value, onValueChange = onValueChange, enabled = enabled, singleLine = true,
            textStyle = TextStyle(color = tokens.primaryInk, fontSize = 16.sp, lineHeight = 22.sp),
            cursorBrush = SolidColor(tokens.accent),
            visualTransformation = if (secure) PasswordVisualTransformation() else VisualTransformation.None,
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.None,
                autoCorrectEnabled = false,
                keyboardType = if (secure) KeyboardType.Password else KeyboardType.Text
            ),
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = label }
        )
    }
}

private const val FallbackPrompt = "Let's finish logging in on AO3's page below."
private const val SignUpUrl = "https://archiveofourown.org/users/new"
private const val PasswordResetUrl = "https://archiveofourown.org/users/password/new"
