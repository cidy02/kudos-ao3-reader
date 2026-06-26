package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary

sealed interface WorkDetailSource {
    data class LocalWork(val workId: String) : WorkDetailSource
    data class RemoteSummary(val summary: AO3WorkSummary) : WorkDetailSource
    data class RemoteUrl(val url: String) : WorkDetailSource
    data class Ao3WorkId(val workId: Long) : WorkDetailSource
}
