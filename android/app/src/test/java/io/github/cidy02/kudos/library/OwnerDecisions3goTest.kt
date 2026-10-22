package io.github.cidy02.kudos.library

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.ui.subject.ReaderTheme
import io.github.cidy02.kudos.ui.subject.ShellWash
import io.github.cidy02.kudos.ui.subject.ShellWashes
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import org.junit.Assert.*
import org.junit.Test

class OwnerDecisions3goTest {
    @Test fun recentlyDeletedKickerFollowsKeptRatherThanFilePresence() {
        val copy = SavedWork(title = "Copy", author = "A", sourceUrl = "https://archiveofourown.org/works/12",
            hasEpub = true, isSaved = false)
        assertEquals("Work", recentlyDeletedWorkKicker(copy))
        assertEquals("Downloaded work", recentlyDeletedWorkKicker(copy.copy(isSaved = true)))
        assertEquals("Downloaded work", recentlyDeletedWorkKicker(copy.copy(isKeptOffline = true)))
        assertEquals("Downloaded work", recentlyDeletedWorkKicker(copy.copy(sourceUrl = "file:///import.epub", hasAo3WorkId = false)))
        assertEquals("Work", recentlyDeletedWorkKicker(copy.copy(hasEpub = false, isSaved = true)))
    }

    @Test fun newestWashWinsUpdatesInPlaceAndClosingItRestoresThePreviousWash() {
        val washes = ShellWashes()
        val page = Any()
        val sheet = Any()
        fun wash(color: Color) = ShellWash(SubjectPalette.fromColor(color, ReaderTheme.Dark), 380.dp)
        val red = wash(Color.Red)
        val blue = wash(Color.Blue)
        val green = wash(Color.Green)
        washes.put(page, red)
        washes.put(sheet, blue)
        assertEquals(blue, washes.page)
        washes.put(page, green)
        assertEquals("recomposition does not reorder a page", blue, washes.page)
        washes.put(sheet, red)
        assertEquals(red, washes.page)
        washes.remove(sheet)
        assertEquals(green, washes.page)
        washes.remove(page)
        assertNull(washes.page)
    }
}
