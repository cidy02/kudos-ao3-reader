package io.github.cidy02.kudos.web

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.material3.OutlinedTextField
import io.github.cidy02.kudos.network.ao3.displayMessage
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.DisposableEffect
import kotlinx.coroutines.launch
import kotlinx.coroutines.CancellationException
import io.github.cidy02.kudos.works.WorkImporter
import io.github.cidy02.kudos.works.WorkImportResult
import io.github.cidy02.kudos.network.ao3.work.AO3EpubDownloader
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import io.github.cidy02.kudos.core.model.AppThemeSetting
import io.github.cidy02.kudos.network.ao3.DemoNetwork
import io.github.cidy02.kudos.network.ao3.DemoNetworkRoutes
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/**
 * Read-only AO3 WebView fallback for pages not yet native. AO3 https pages load
 * in-app; any other http(s) link is handed to an external browser; non-web schemes
 * are blocked. Theme CSS is injected via `evaluateJavascript` for Dark/Sepia only
 * (Light leaves AO3's native skin untouched); there is no app↔page JavaScript
 * bridge. Android back walks WebView history first. This is NOT the auth/login
 * WebView (that lives in `auth/`).
 */
@Composable
fun AO3WebViewFallbackScreen(
    url: String,
    appTheme: AppThemeSetting,
    workImporter: WorkImporter,
    onBookmark: suspend (title: String, url: String) -> Unit,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var importing by remember { mutableStateOf(false) }
    var notice by remember { mutableStateOf<String?>(null) }
    val importDownload: (String) -> Unit = { target ->
        if (!importing && AO3EpubDownloader.isEpubDownload(target)) {
            importing = true
            scope.launch {
                try {
                    val result = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                        workImporter.importWebEpub(target)
                    }
                    notice = when (result) {
                        is WorkImportResult.Success -> "Saved “${result.work.title}” to Library"
                        is WorkImportResult.Failure -> "Couldn't save EPUB: ${result.error.displayMessage()}"
                    }
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (error: Exception) {
                    notice = error.message ?: "Couldn't save EPUB."
                } finally {
                    importing = false
                }
            }
        }
    }
    var address by remember(url) { mutableStateOf(url) }
    var bookmarking by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(true) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var currentTitle by remember { mutableStateOf(url) }
    var webView by remember { mutableStateOf<WebView?>(null) }

    LaunchedEffect(notice) {
        if (notice != null) {
            kotlinx.coroutines.delay(2500)
            notice = null
        }
    }
    DisposableEffect(webView) {
        val mounted = webView
        onDispose { mounted?.stopLoading(); mounted?.destroy() }
    }

    val currentImportDownload by rememberUpdatedState(importDownload)

    // Mirror KudosTheme: System → Dark or Light from the device setting.
    val systemDark = isSystemInDarkTheme()
    val resolvedTheme = when (appTheme) {
        AppThemeSetting.System -> if (systemDark) AppThemeSetting.Dark else AppThemeSetting.Light
        else -> appTheme
    }
    val currentTheme by rememberUpdatedState(resolvedTheme)

    // Never host a non-AO3 page in the in-app WebView.
    LaunchedEffect(url) {
        if (!AO3WebUrlPolicy.isAllowedInApp(url)) {
            openExternal(context, url)
            onBack()
        }
    }

    // Re-inject when the user changes theme live (iOS applyTheme parity).
    LaunchedEffect(resolvedTheme, webView) {
        val wv = webView ?: return@LaunchedEffect
        injectTheme(wv, resolvedTheme, wv.url)
    }

    BackHandler {
        val wv = webView
        if (wv != null && wv.canGoBack()) wv.goBack() else onBack()
    }

    Column(modifier = Modifier.fillMaxSize()) {
        Surface(color = MaterialTheme.colorScheme.surface) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                TextButton(onClick = {
                    val wv = webView
                    if (wv != null && wv.canGoBack()) wv.goBack() else onBack()
                }) { Text("Back") }
                Text(currentTitle, style = MaterialTheme.typography.titleSmall,
                    maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                TextButton(onClick = { openExternal(context, webView?.url ?: url) }) { Text("Browser") }
                TextButton(onClick = onBack) { Text("Done") }
            }
        }

        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            fun submitAddress() {
                val target = AO3WebUrlPolicy.addressUrl(address) ?: return
                when (val decision = AO3WebUrlPolicy.navigationVerdict(target, isMainFrame = true, isDemo = DemoNetwork.isActive)) {
                    WebNavDecision.Allow -> if (AO3EpubDownloader.isEpubDownload(target)) currentImportDownload(target)
                        else webView?.loadUrl(target)
                    is WebNavDecision.External -> openExternal(context, decision.url)
                    WebNavDecision.Block -> Unit
                }
            }
            OutlinedTextField(value = address, onValueChange = { address = it }, singleLine = true,
                label = { Text("Search AO3 or enter a URL") }, modifier = Modifier.weight(1f),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Go),
                keyboardActions = KeyboardActions(onGo = { submitAddress() }))
            TextButton(onClick = { submitAddress() }) { Text("Go") }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
            TextButton(onClick = { webView?.reload() }) { Text("Reload") }
            TextButton(enabled = !bookmarking && AO3WebUrlPolicy.isAllowedInApp(webView?.url.orEmpty()), onClick = {
                val pageUrl = webView?.url
                if (pageUrl != null && AO3WebUrlPolicy.isAllowedInApp(pageUrl)) {
                    val title = webView?.title?.takeIf { it.isNotBlank() } ?: pageUrl
                    bookmarking = true
                    scope.launch {
                        try {
                            onBookmark(title, pageUrl)
                            notice = "Bookmarked “$title”"
                        } catch (cancelled: CancellationException) {
                            throw cancelled
                        } catch (error: Exception) {
                            notice = error.message ?: "Couldn't bookmark this page."
                        } finally { bookmarking = false }
                    }
                }
            }) { Text("Add Bookmark") }
        }

        if (importing) Text("Saving EPUB…", modifier = Modifier.padding(16.dp))
        notice?.let { Text(it, modifier = Modifier.padding(16.dp)) }
        if (loading) {
            LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
        }

        errorMessage?.let { message ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = message,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.weight(1f)
                )
                TextButton(onClick = {
                    errorMessage = null
                    loading = true
                    webView?.reload()
                }) { Text("Retry") }
                TextButton(onClick = { openExternal(context, webView?.url ?: url) }) { Text("Browser") }
            }
        }

        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { ctx ->
                WebView(ctx).apply {
                    webView = this
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    setDownloadListener { target, _, _, _, _ -> currentImportDownload(target) }
                    webViewClient = object : WebViewClient() {
                        override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): WebResourceResponse? {
                            if (!DemoNetwork.isActive) return super.shouldInterceptRequest(view, request)
                            // WebView bypasses OkHttp. Demo reads/subresources must terminate locally too.
                            val target = request?.url?.toString()?.toHttpUrlOrNull()
                            val bytes = if (request?.method == "GET" && target != null && DemoNetworkRoutes.isAo3Host(target.host))
                                DemoNetwork.webFixture(target) else null
                            return WebResourceResponse("text/html", "UTF-8", if (bytes == null) 404 else 200,
                                if (bytes == null) "Local demo page unavailable" else "OK", emptyMap(),
                                (bytes ?: ByteArray(0)).inputStream())
                        }

                        override fun shouldOverrideUrlLoading(
                            view: WebView?,
                            request: WebResourceRequest?
                        ): Boolean {
                            val target = request?.url?.toString() ?: return false
                            if (request.isForMainFrame && request.method == "GET" && AO3EpubDownloader.isEpubDownload(target)) {
                                currentImportDownload(target)
                                return true
                            }
                            return when (val decision = AO3WebUrlPolicy.navigationVerdict(
                                target, isMainFrame = request.isForMainFrame, isDemo = DemoNetwork.isActive
                            )) {
                                WebNavDecision.Allow -> false
                                is WebNavDecision.External -> {
                                    openExternal(ctx, decision.url)
                                    true
                                }
                                WebNavDecision.Block -> true
                            }
                        }

                        override fun onPageStarted(view: WebView?, url2: String?, favicon: android.graphics.Bitmap?) {
                            loading = true
                            errorMessage = null
                            url2?.let { currentTitle = it; address = it }
                        }

                        override fun onPageFinished(view: WebView?, url2: String?) {
                            loading = false
                            url2?.let { address = it }
                            currentTitle = view?.title?.takeIf { it.isNotBlank() } ?: url2 ?: currentTitle
                            // Always evaluate (including Light / non-AO3 remove branch)
                            // so a prior kudos-app-theme tag is actively cleared when needed.
                            if (view != null) {
                                injectTheme(view, currentTheme, url2 ?: view.url)
                            }
                        }

                        override fun onReceivedError(
                            view: WebView?,
                            request: WebResourceRequest?,
                            error: WebResourceError?
                        ) {
                            if (request?.isForMainFrame == true) {
                                loading = false
                                errorMessage = "Couldn't load this AO3 page."
                            }
                        }
                    }
                    webChromeClient = object : WebChromeClient() {
                        override fun onProgressChanged(view: WebView?, newProgress: Int) {
                            loading = newProgress < 100
                        }
                    }
                    if (AO3EpubDownloader.isEpubDownload(url)) {
                        loading = false
                        currentImportDownload(url)
                    }
                    else if (AO3WebUrlPolicy.isAllowedInApp(url)) loadUrl(url)
                }
            }
        )
    }
}

private fun injectTheme(webView: WebView, theme: AppThemeSetting, pageUrl: String?) {
    webView.evaluateJavascript(
        BrowserThemeStyle.injectionScript(theme, pageUrl),
        null
    )
}

private fun openExternal(context: Context, url: String) {
    // All entry points (Browser, error fallback, address bar and page links) share this guard.
    if (!AO3WebUrlPolicy.mayOpenExternal(url, isDemo = DemoNetwork.isActive)) return
    runCatching {
        context.startActivity(
            Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }
}
