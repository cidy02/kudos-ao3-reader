package io.github.cidy02.kudos.browse

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** iOS `FandomScriptTests` (A58 #20). */
class FandomScriptTest {
    @Test fun latinAndCyrillicTakeItalicOtherScriptsAndMixedNamesStayUpright() {
        for (name in listOf("Boku no Hero Academia", "Shingeki no Kyojin", "Bangtan Boys", "Hellaverse",
            "Otbleski Eterny", "Отблески Этерны")) assertTrue(name, FandomScript.hasItalicForm(name))
        for (name in listOf("僕のヒーローアカデミア", "原神", "방탄소년단", "文豪ストレイドッグス",
            "บรรยากาศรัก เดอะซีรีส์", "魔道祖师", "文豪ストレイドッグス Bungou Stray Dogs"))
            assertFalse(name, FandomScript.hasItalicForm(name))
    }
}
