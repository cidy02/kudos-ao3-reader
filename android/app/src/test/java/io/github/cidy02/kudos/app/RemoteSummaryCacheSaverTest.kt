package io.github.cidy02.kudos.app

import androidx.compose.runtime.saveable.SaverScope
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import org.junit.Assert.*
import org.junit.Test

class RemoteSummaryCacheSaverTest {
    private fun work(id: Long) = AO3WorkSummary(id, "Work $id \u661f", listOf("A", "B"), listOf("Fandom"), "Teen And Up Audiences",
        listOf("No Archive Warnings Apply"), listOf("F/F"), summary = "A \"quoted\" summary.", wordCount = 12_345,
        chapters = "14/24", kudos = 1_200, isComplete = false, isRestricted = true, updatedDate = "09 Jul 2026")

    @Test fun theNewestEightComeBackWhole() {
        val cache = (1L..10L).associateWithTo(mutableMapOf()) { work(it) }
        val saved = with(RemoteSummaryCacheSaver) { SaverScope { true }.save(cache) }!!
        val back = RemoteSummaryCacheSaver.restore(saved)!!
        assertEquals((3L..10L).toList(), back.keys.toList())
        assertEquals(work(10), back[10])
    }

    @Test fun whatCannotBeReadIsAnEmptyCacheNotACrash() {
        assertTrue(RemoteSummaryCacheSaver.restore("not json")!!.isEmpty())
    }
}
