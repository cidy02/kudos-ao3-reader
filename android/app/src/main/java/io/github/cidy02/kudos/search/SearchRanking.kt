package io.github.cidy02.kudos.search

import android.content.SharedPreferences
import io.github.cidy02.kudos.network.ao3.search.KudosStringStore
import io.github.cidy02.kudos.network.ao3.search.LoadedWorksRanker
import io.github.cidy02.kudos.network.ao3.search.LoadedWorksRanking
import io.github.cidy02.kudos.works.CanonicalWork
import java.time.LocalDate

internal data class RankedSearchRow(val work: CanonicalWork, val signal: String?)

/** Reorders the works already on screen. A new page is just a new list passed in. */
internal fun rankSearchWorks(
    works: List<CanonicalWork>,
    settings: LoadedWorksRanking,
    previousKudos: Map<Long, Int> = emptyMap(),
    now: LocalDate = LocalDate.now()
): List<RankedSearchRow> {
    val ranked = LoadedWorksRanker.rank(works.map { it.remote }, settings, previousKudos, now)
    val byId = LinkedHashMap<Long, CanonicalWork>()
    for (work in works) byId.putIfAbsent(work.remote.id, work)
    return ranked.map { entry ->
        val signal = if (settings.isActive && settings.showsSignal) entry.signal else null
        RankedSearchRow(byId.getValue(entry.work.id), signal)
    }
}

internal class SharedPreferencesKudosStringStore(
    private val preferences: SharedPreferences
) : KudosStringStore {
    override fun get(key: String): String? = preferences.getString(key, null)

    override fun set(key: String, value: String?) {
        val editor = preferences.edit()
        if (value == null) editor.remove(key) else editor.putString(key, value)
        editor.apply()
    }
}
