package io.github.cidy02.kudos.writing

import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.AO3URLResolver
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import io.github.cidy02.kudos.network.ao3.UserFacingError
import io.github.cidy02.kudos.network.ao3.chapters.AO3ChapterIndexParser
import io.github.cidy02.kudos.network.ao3.chapters.AO3ChapterRef
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class WritingChaptersState(
    private val workID: Long,
    private val client: AO3AuthenticatedClient,
    private val auth: AO3AuthRepository,
    private val scope: CoroutineScope
) {
    data class State(
        val chapters: List<AO3ChapterRef>? = null,
        val errorMessage: String? = null,
        val loadedGeneration: Int? = null,
        val loadedReload: Int = 0
    )

    private val _state = MutableStateFlow(State())
    val state = _state.asStateFlow()

    private var reloadCount = 0
    private var job: Job? = null

    init {
        load()
    }

    fun reload() {
        reloadCount++
        load()
    }

    private fun load() {
        job?.cancel()
        job = scope.launch {
            val generation = auth.sessionGeneration
            val currentReload = reloadCount
            
            val currentState = _state.value
            if (currentState.loadedGeneration == generation && currentState.loadedReload == currentReload) return@launch
            
            if (currentState.loadedGeneration != generation) {
                _state.value = currentState.copy(chapters = null)
            }
            _state.value = _state.value.copy(errorMessage = null)
            
            val url = AO3URLResolver.canonicalWorkUrl(workID).trimEnd('/') + "/navigate"
            
            when (val response = client.getAuthenticated(url)) {
                is AO3Result.Success -> {
                    val parsed = withContext(Dispatchers.Default) {
                        AO3ChapterIndexParser.parse(response.value.body)
                    }
                    if (generation == auth.sessionGeneration) {
                        _state.value = _state.value.copy(
                            chapters = parsed,
                            loadedGeneration = generation,
                            loadedReload = currentReload
                        )
                    }
                }
                is AO3Result.Failure -> {
                    if (generation == auth.sessionGeneration) {
                        _state.value = _state.value.copy(
                            errorMessage = if (_state.value.chapters == null) UserFacingError.message(response.error) else _state.value.errorMessage,
                            loadedGeneration = generation,
                            loadedReload = currentReload
                        )
                    }
                }
            }
        }
    }
}
