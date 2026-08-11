package io.github.cidy02.kudos.ui.components

import androidx.compose.foundation.layout.BoxScope
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import kotlinx.coroutines.launch

/**
 * The app's single pull-to-refresh pattern (iOS `CancellableRefresh`).
 *
 * Every refreshable surface goes through this rather than wiring
 * [PullToRefreshBox] by hand, so the spinner lifecycle and the cancellation
 * rule stay identical everywhere.
 *
 * **Cancellation.** [onRefresh] runs in `rememberCoroutineScope`, which Compose
 * cancels when this composable leaves composition — i.e. as soon as the user
 * navigates away. That is the Android analogue of iOS cancelling the refresh
 * task on tab change: a refresh that walks a whole Library or Reading Queue
 * must not keep firing sequential AO3 requests invisibly after the user has
 * moved on. A refresh launched into `viewModelScope` would survive navigation
 * and do exactly that, which is why the scope here is deliberately the
 * composition's and not the ViewModel's.
 *
 * Re-entry is guarded, so a second pull while one is in flight is ignored
 * rather than starting a parallel scrape.
 */
@Composable
fun KudosRefreshBox(
    onRefresh: suspend () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit
) {
    var refreshing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    PullToRefreshBox(
        isRefreshing = refreshing,
        onRefresh = {
            if (!refreshing) {
                refreshing = true
                scope.launch {
                    try {
                        onRefresh()
                    } finally {
                        refreshing = false
                    }
                }
            }
        },
        modifier = modifier,
        content = content
    )
}
