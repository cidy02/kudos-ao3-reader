package io.github.cidy02.kudos.writing

import io.github.cidy02.kudos.app.Routes
import io.github.cidy02.kudos.ui.subject.DebugRoutes
import org.junit.Assert.*
import org.junit.Test

class WritingEditorRoutesTest {
    @Test fun debugEntrancesUsePushedChromeAndHideTheTabBar() {
        assertEquals(Routes.WritingEditorDemo, DebugRoutes.WRITING_EDITOR.removePrefix(DebugRoutes.NAV_PREFIX))
        assertEquals(Routes.WritingEditorFixture, DebugRoutes.WRITING_EDITOR_FIXTURE.removePrefix(DebugRoutes.NAV_PREFIX))
        for (route in listOf(Routes.WritingEditorDemo, Routes.WritingEditorFixture)) {
            assertTrue(Routes.hasSubjectHeader(route))
            assertTrue(Routes.hidesTabBar(route))
            assertEquals("Chapter text", Routes.titleFor(route))
        }
    }
}
