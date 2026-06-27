package io.github.cidy02.kudos.web

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView

/**
 * Read-only AO3 WebView fallback for pages not yet native. AO3 https pages load
 * in-app; any other http(s) link is handed to an external browser; non-web schemes
 * are blocked. No JavaScript bridge / script injection is added. Android back walks
 * WebView history first. This is NOT the auth/login WebView (that lives in `auth/`).
 */
@Composable
fun AO3WebViewFallbackScreen(
    url: String,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    var loading by remember { mutableStateOf(true) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var currentTitle by remember { mutableStateOf(url) }
    var webView by remember { mutableStateOf<WebView?>(null) }

    // Never host a non-AO3 page in the in-app WebView.
    LaunchedEffect(url) {
        if (!AO3WebUrlPolicy.isAllowedInApp(url)) {
            openExternal(context, url)
            onBack()
        }
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
                Text(
                    text = currentTitle,
                    style = MaterialTheme.typography.titleSmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                TextButton(onClick = { openExternal(context, webView?.url ?: url) }) { Text("Browser") }
            }
        }

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
                    webViewClient = object : WebViewClient() {
                        override fun shouldOverrideUrlLoading(
                            view: WebView?,
                            request: WebResourceRequest?
                        ): Boolean {
                            val target = request?.url?.toString() ?: return false
                            return when (val decision = AO3WebUrlPolicy.classify(target)) {
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
                            url2?.let { currentTitle = it }
                        }

                        override fun onPageFinished(view: WebView?, url2: String?) {
                            loading = false
                            currentTitle = view?.title?.takeIf { it.isNotBlank() } ?: url2 ?: currentTitle
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
                    if (AO3WebUrlPolicy.isAllowedInApp(url)) loadUrl(url)
                }
            }
        )
    }
}

private fun openExternal(context: Context, url: String) {
    runCatching {
        context.startActivity(
            Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }
}
