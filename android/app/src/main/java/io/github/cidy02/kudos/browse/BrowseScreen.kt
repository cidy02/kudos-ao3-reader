package io.github.cidy02.kudos.browse

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.data.local.dao.ReadingLogDao
import io.github.cidy02.kudos.data.local.entity.FandomReadWatermarkEntity
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseRepository
import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseUrls
import io.github.cidy02.kudos.network.ao3.browse.AO3Fandom
import io.github.cidy02.kudos.network.ao3.browse.AO3MediaCategory
import io.github.cidy02.kudos.network.ao3.displayMessage
import io.github.cidy02.kudos.ui.components.EmptyStateCard
import io.github.cidy02.kudos.ui.components.GlassFieldBar
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext

private data class BrowseDerived(
    val stats: Map<String, CategoryStats> = emptyMap(),
    val jumpBackIn: List<JumpBackIn.Pick> = emptyList()
)

@Composable
fun BrowseScreen(
    onOpenCategory: (AO3MediaCategory) -> Unit,
    onOpenWebFallback: (String) -> Unit,
    onOpenFandom: (String) -> Unit = {},
    workRepository: WorkRepository? = null,
    readingLogDao: ReadingLogDao? = null,
    repository: AO3BrowseRepository = remember { AO3BrowseRepository() }
) {
    var state by remember { mutableStateOf<BrowseCategoriesState>(BrowseCategoriesState.Loading) }
    var fandomLists by remember { mutableStateOf<Map<String, List<AO3Fandom>>>(emptyMap()) }
    var addressQuery by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    val libraryFlow = remember(workRepository) {
        workRepository?.observeLibraryWorks() ?: flowOf(emptyList())
    }
    val library by libraryFlow.collectAsState(initial = emptyList())
    val watermarkFlow = remember(readingLogDao) {
        readingLogDao?.observeWatermarks() ?: flowOf(emptyList())
    }
    val watermarks by watermarkFlow.collectAsState(initial = emptyList())
    val categories = (state as? BrowseCategoriesState.Loaded)?.categories.orEmpty()
    // `produceState` restarted on every fandom-list arrival and cancelled the
    // assignment, so the screen stayed on the first featured-only result.
    // `collect` finishes each pass; snapshotFlow keeps only the newest inputs.
    var derived by remember { mutableStateOf(BrowseDerived()) }
    LaunchedEffect(Unit) {
        snapshotFlow {
            BrowseInputs(
                categories = (state as? BrowseCategoriesState.Loaded)?.categories.orEmpty(),
                lists = fandomLists,
                library = library,
                watermarks = watermarks
            )
        }.collect { tick ->
            if (tick.categories.isEmpty()) {
                derived = BrowseDerived()
                return@collect
            }
            val snapshots = tick.library.map { it.toBrowseSnapshot() }
            val visits = tick.watermarks.map { JumpBackIn.Visit(it.fandomName, it.lastVisitedAt) }
            derived = withContext(Dispatchers.Default) {
                val inputs = tick.categories.map { category ->
                    val list = tick.lists[category.name]
                    CategoryStatsInput(
                        id = category.name,
                        fandoms = list ?: category.featuredFandoms.map { AO3Fandom(name = it) },
                        hasFullList = list != null
                    )
                }
                BrowseDerived(
                    stats = CategoryStatsCalculator.computeStats(inputs, snapshots),
                    jumpBackIn = CategoryStatsCalculator.rankJumpBackIn(inputs, snapshots, visits)
                )
            }
        }
    }

    suspend fun loadNow() {
        state = BrowseCategoriesState.Loading
        fandomLists = emptyMap()
        when (val result = repository.categories()) {
            is AO3Result.Success -> {
                state = BrowseCategoriesState.Loaded(result.value)
                prefetchFandomLists(repository, result.value) { name, list ->
                    fandomLists = fandomLists + (name to list)
                }
            }
            is AO3Result.Failure -> {
                state = BrowseCategoriesState.Error(result.error.displayMessage())
            }
        }
    }

    fun load() { scope.launch { loadNow() } }

    fun openFandom(name: String) {
        // The visit write lives in the caller's scope. This screen's scope is
        // cancelled as soon as navigation leaves Browse, which dropped the insert
        // and, when it raced the caller's write, inserted a second watermark row.
        onOpenFandom(name)
    }

    LaunchedEffect(Unit) { loadNow() }

    KudosRefreshBox(onRefresh = { loadNow() }, modifier = Modifier.fillMaxSize()) {
        Column(modifier = Modifier.fillMaxSize()) {
            GlassFieldBar(
                text = addressQuery,
                onTextChange = { addressQuery = it },
                placeholder = "Search AO3 or enter a URL",
                imeAction = ImeAction.Go,
                onSubmit = {
                    if (addressQuery.isNotBlank()) {
                        onOpenWebFallback(addressQuery)
                        addressQuery = ""
                    }
                },
                leading = {
                    Icon(
                        imageVector = Icons.Outlined.Search,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp)
            )

            when (val current = state) {
                BrowseCategoriesState.Loading -> LoadingStateCard("Loading AO3 media categories")
                is BrowseCategoriesState.Error -> Column(
                    modifier = Modifier.padding(horizontal = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(18.dp)
                ) {
                    JumpBackInSection(derived.jumpBackIn, categories, ::openFandom)
                    BrowseErrorBlock(
                        message = current.message,
                        onRetry = ::load,
                        onWebFallback = { onOpenWebFallback(AO3BrowseUrls.mediaIndexUrl()) },
                        title = "Couldn't load fandoms",
                        retryLabel = "Try Again"
                    )
                }
                is BrowseCategoriesState.Loaded -> {
                    if (current.categories.isEmpty()) {
                        EmptyStateCard(
                            title = "No fandom categories",
                            message = "AO3 did not return any fandom categories."
                        )
                    } else {
                        LazyColumn(
                            modifier = Modifier.fillMaxWidth(),
                            contentPadding = PaddingValues(bottom = 24.dp)
                        ) {
                            // Always reserve the slot. Adding it only once picks
                            // exist meant a list built while ranking was still
                            // empty never gained the carousel. Spacing lives on
                            // the children so an empty slot adds no gap.
                            item(key = "jump-back-in") {
                                val picks = derived.jumpBackIn
                                if (picks.isNotEmpty()) {
                                    JumpBackInSection(
                                        picks = picks,
                                        categories = current.categories,
                                        onOpenFandom = ::openFandom,
                                        modifier = Modifier.padding(bottom = 18.dp)
                                    )
                                }
                            }
                            items(current.categories, key = { it.name }) { category ->
                                CategoryPanel(
                                    category = category,
                                    stats = derived.stats[category.name] ?: CategoryStats(),
                                    onOpen = { onOpenCategory(category) },
                                    onOpenFandom = ::openFandom,
                                    modifier = Modifier.padding(bottom = 18.dp)
                                )
                            }
                            item(key = "open-website") {
                                OpenAo3WebsiteRow(
                                    modifier = Modifier.padding(bottom = 18.dp)
                                ) {
                                    onOpenWebFallback(AO3BrowseUrls.mediaIndexUrl())
                                }
                            }
                            item(key = "instructions") { BrowseInstructions() }
                        }
                    }
                }
            }
        }
    }
}

/**
 * Prefetch each category's fandom index for card stats. Bounded so we stay polite
 * to AO3. Invokes [onLoaded] as each category lands so cards fill in progressively.
 */
private suspend fun prefetchFandomLists(
    repository: AO3BrowseRepository,
    categories: List<AO3MediaCategory>,
    onLoaded: (String, List<AO3Fandom>) -> Unit
) {
    if (categories.isEmpty()) return
    val gate = Semaphore(permits = 2)
    val emitLock = Mutex()
    coroutineScope {
        categories.map { category ->
            async {
                gate.withPermit {
                    when (val result = repository.fandoms(category)) {
                        is AO3Result.Success -> {
                            emitLock.withLock { onLoaded(category.name, result.value) }
                        }
                        is AO3Result.Failure -> Unit
                    }
                }
            }
        }.awaitAll()
    }
}

private data class BrowseInputs(
    val categories: List<AO3MediaCategory>,
    val lists: Map<String, List<AO3Fandom>>,
    val library: List<SavedWork>,
    val watermarks: List<FandomReadWatermarkEntity>
)

private sealed interface BrowseCategoriesState {
    data object Loading : BrowseCategoriesState
    data class Loaded(val categories: List<AO3MediaCategory>) : BrowseCategoriesState
    data class Error(val message: String) : BrowseCategoriesState
}
