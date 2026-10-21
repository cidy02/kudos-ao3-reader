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
import androidx.compose.foundation.text.KeyboardActions
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
import androidx.compose.ui.text.input.ImeAction
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

    fun submit() {
        if (!networkAllowed || loading || username.isBlank() || password.isBlank()) return
        loading = true
        message = null
        pendingSubmit = true
        submitTimestamp = System.currentTimeMillis()
        webViewRef?.loadUrl(LoginUrl)
    }

    // iOS parity: 25s timeout for login submission (Item 7 note).
    LaunchedEffect(loading, submitTimestamp) {
        if (!loading || submitTimestamp == 0L) return@LaunchedEffect
        kotlinx.coroutines.delay(25_000)
        if (loading) {
            loading = false
            useWebFallback = true
            message = FallbackPrompt
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

    DisposableEffect(Unit) {
        onDispose {
            webViewRef?.stopLoading()
            webViewRef = null
            password = ""
        }
    }

    if (useWebFallback) {
        Column(modifier = modifier.fillMaxSize().background(tokens.background)
            .then(headerInset)
            .then(if (largeType) Modifier.verticalScroll(rememberScrollState()) else Modifier)) {
            LoginHeader(onCancel)
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("Using alternative login method…", style = MaterialTheme.typography.titleMedium,
                    lineHeight = 22.sp, color = tokens.primaryInk)
                Text(message ?: FallbackPrompt, style = MaterialTheme.typography.bodySmall,
                    lineHeight = 18.sp, color = tokens.secondaryInk)
            }
            AO3WebLoginScreen(
                authRepository = authRepository,
                onLoginComplete = { password = ""; onLoginComplete() },
                onCancel = onCancel,
                demo = !networkAllowed,
                modifier = if (largeType) Modifier.fillMaxWidth() else Modifier.weight(1f),
                hostShowsPrompt = true
            )
            TextButton(
                colors = ButtonDefaults.textButtonColors(contentColor = tokens.accentInk),
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
                LoginField("Password", password, { password = it }, !loading, secure = true,
                    imeAction = ImeAction.Go, onGo = ::submit)
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
            onClick = ::submit
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
                    colors = ButtonDefaults.textButtonColors(contentColor = tokens.accentInk)
                ) {
                    Icon(Icons.Outlined.PersonAdd, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("Create an AO3 account", lineHeight = 22.sp)
                }
                SubjectRowSeparator()
                TextButton(
                    onClick = { if (networkAllowed) onOpenAO3(PasswordResetUrl) },
                    colors = ButtonDefaults.textButtonColors(contentColor = tokens.accentInk)
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
            colors = ButtonDefaults.textButtonColors(contentColor = tokens.accentInk),
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
                            }
                        }

                        override fun onPageFinished(view: WebView, url: String?) {
                            if (pendingSubmit && url?.contains("/users/login") == true) {
                                pendingSubmit = false
                                view.evaluateJavascript(AO3NativeLoginScript.fill(username.trim(), password)) { result ->
                                    if (!AO3NativeLoginScript.submitted(result)) {
                                        loading = false
                                        useWebFallback = true
                                        message = FallbackPrompt
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
                                            }
                                        }
                                    }
                                } else if (loading && inspection.errorMessage != null) {
                                    loading = false
                                    message = inspection.errorMessage
                                } else if (loading && AO3NativeLoginScript.requiresFallback(inspection)) {
                                    // No AO3 error to explain the result: let its visible page handle it.
                                    pendingSubmit = false
                                    loading = false
                                    useWebFallback = true
                                    message = FallbackPrompt
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
            colors = ButtonDefaults.textButtonColors(contentColor = tokens.accentInk)) {
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
internal fun LoginField(label: String, value: String, onValueChange: (String) -> Unit,
    enabled: Boolean, secure: Boolean = false,
    imeAction: ImeAction = ImeAction.Next, onGo: () -> Unit = {}) {
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
                imeAction = imeAction,
                keyboardType = if (secure) KeyboardType.Password else KeyboardType.Text
            ),
            keyboardActions = KeyboardActions(onGo = { if (enabled) onGo() }),
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = label }
        )
    }
}

private const val FallbackPrompt = "Let's finish logging in on AO3's page below."
private const val SignUpUrl = "https://archiveofourown.org/users/new"
private const val PasswordResetUrl = "https://archiveofourown.org/users/password/new"
