package io.github.cidy02.kudos.reader.readium

import android.graphics.Rect
import android.view.ActionMode
import android.view.Menu
import android.view.MenuInflater
import android.view.MenuItem
import android.view.View
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.R
import java.lang.reflect.Proxy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** No WebView or publication: recording callbacks and a fake Menu exercise the seam. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ReaderSelectionActionModeCallbackTest {
    @Test
    fun createAppendsIosLabelsAfterTheOriginalItemsAndPrepareDoesNotDuplicateThem() {
        val calls = mutableListOf<String>()
        val original = RecordingCallback(calls)
        val menu = FakeMenu()
        val mode = RecordingMode(menu.menu, calls)
        val wrapped = wrapper(original, calls)

        assertTrue(wrapped.onCreateActionMode(mode, menu.menu))
        assertEquals(listOf("Copy", "Share", "Highlight", "Add Note"), menu.titles())
        repeat(3) { assertFalse(wrapped.onPrepareActionMode(mode, menu.menu)) }
        assertEquals(listOf("Copy", "Share", "Highlight", "Add Note"), menu.titles())
        assertEquals(listOf("create", "prepare", "prepare", "prepare"), calls)
    }

    @Test
    fun prepareReaddsItemsWhenTheOriginalClearsAndRebuildsItsMenu() {
        val calls = mutableListOf<String>()
        val original = RecordingCallback(calls).apply { rebuildOnPrepare = true }
        val menu = FakeMenu()
        val mode = RecordingMode(menu.menu, calls)
        val wrapped = wrapper(original, calls)

        wrapped.onCreateActionMode(mode, menu.menu)
        repeat(3) {
            assertTrue(wrapped.onPrepareActionMode(mode, menu.menu))
            assertEquals(listOf("Copy", "Share", "Highlight", "Add Note"), menu.titles())
        }
        assertEquals(listOf("create", "prepare", "prepare", "prepare"), calls)
    }

    @Test
    fun eachCustomItemCallsItsRecordingEntryPointThenFinishesWithoutCallingTheOriginalClick() {
        for ((id, name) in listOf(R.id.reader_selection_highlight to "highlight",
            R.id.reader_selection_add_note to "note")) {
            val calls = mutableListOf<String>()
            val menu = FakeMenu()
            val mode = RecordingMode(menu.menu, calls)
            val wrapped = wrapper(RecordingCallback(calls), calls)
            wrapped.onCreateActionMode(mode, menu.menu)

            assertTrue(wrapped.onActionItemClicked(mode, menu.menu.findItem(id)!!))
            assertEquals(listOf("create", name, "finish"), calls)
            assertEquals(1, mode.finishes)
        }
    }

    @Test
    fun anAsynchronousSelectionReadCompletesBeforeTheModeFinishes() {
        val calls = mutableListOf<String>()
        val menu = FakeMenu()
        val mode = RecordingMode(menu.menu, calls)
        var complete: (() -> Unit)? = null
        val wrapped = ReaderSelectionActionModeCallback(
            RecordingCallback(calls),
            onHighlight = { done -> calls += "read selection"; complete = done },
            onAddNote = { error("Wrong entry point") }
        )
        wrapped.onCreateActionMode(mode, menu.menu)
        val item = menu.menu.findItem(R.id.reader_selection_highlight)!!
        assertTrue(wrapped.onActionItemClicked(mode, item))
        assertTrue(wrapped.onActionItemClicked(mode, item))
        assertEquals(listOf("create", "read selection"), calls)
        assertEquals(0, mode.finishes)

        complete!!()
        complete!!()
        assertEquals(listOf("create", "read selection", "finish"), calls)
        assertEquals(1, mode.finishes)
    }

    @Test
    fun nativeClicksAndDestroyReachTheOriginalAndPreserveItsReturnValue() {
        val calls = mutableListOf<String>()
        val original = RecordingCallback(calls).apply { clickResult = false; prepareResult = true }
        val menu = FakeMenu()
        val mode = RecordingMode(menu.menu, calls)
        val wrapped = wrapper(original, calls)
        wrapped.onCreateActionMode(mode, menu.menu)
        assertTrue(wrapped.onPrepareActionMode(mode, menu.menu))
        val copy = menu.menu.findItem(android.R.id.copy)!!
        assertFalse(wrapped.onActionItemClicked(mode, copy))
        original.clickResult = true
        assertTrue(wrapped.onActionItemClicked(mode, copy))
        wrapped.onDestroyActionMode(mode)
        assertEquals(listOf("create", "prepare", "click:Copy", "click:Copy", "destroy"), calls)
        assertSame(mode, original.lastMode)
        assertSame(copy, original.lastClickedItem)
        assertEquals(0, mode.finishes)
    }

    @Test
    fun floatingToolbarRectIsDelegatedToCallback2AndPlainCallbacksUseViewBounds() {
        val calls = mutableListOf<String>()
        val original = RecordingCallback(calls)
        val mode = RecordingMode(FakeMenu().menu, calls)
        val view = View(ApplicationProvider.getApplicationContext()).apply { layout(0, 0, 80, 40) }
        val rect = Rect()
        wrapper(original, calls).onGetContentRect(mode, view, rect)
        assertEquals(Rect(10, 20, 30, 40), rect)
        assertEquals(listOf("rect"), calls)
        assertSame(view, original.lastView)

        val plain = object : ActionMode.Callback by original {}
        wrapper(plain, calls).onGetContentRect(mode, view, rect)
        assertEquals(Rect(0, 0, 80, 40), rect)
        assertEquals(listOf("rect"), calls)
    }

    @Test
    fun nonFloatingModesAndNonWebViewOriginsAreReturnedUntouched() {
        val original = RecordingCallback(mutableListOf())
        val fail: (() -> Unit) -> Unit = { error("Must not dispatch") }
        assertSame(original, wrapReaderSelectionActionMode(
            original, ActionMode.TYPE_PRIMARY, true, fail, fail
        ))
        assertSame(original, wrapReaderSelectionActionMode(
            original, ActionMode.TYPE_FLOATING, false, fail, fail
        ))
        assertTrue(wrapReaderSelectionActionMode(
            original, ActionMode.TYPE_FLOATING, true, fail, fail
        ) is ReaderSelectionActionModeCallback)
    }

    /**
     * The WebView's Copy cannot be found by android.R.id.copy (its id is Chromium's), so the rule
     * is "the native menu holds something", not "it holds Copy". Seen on the emulator: with the
     * Copy rule, the real menu never got the two actions.
     */
    @Test
    fun anyNativeItemBringsTheTwoActionsAndAnEmptyNativeMenuBringsNone() {
        val calls = mutableListOf<String>()
        val original = RecordingCallback(calls).apply { hasSelection = false; rebuildOnPrepare = true }
        val menu = FakeMenu()
        val mode = RecordingMode(menu.menu, calls)
        val wrapped = wrapper(original, calls)
        assertTrue(wrapped.onCreateActionMode(mode, menu.menu))
        // One native item whose id is not android.R.id.copy, as every item of a real WebView's.
        assertEquals(listOf("Paste", "Highlight", "Add Note"), menu.titles())
        original.rebuildOnPrepare = false
        menu.menu.clear()
        wrapped.onPrepareActionMode(mode, menu.menu)
        assertEquals(emptyList<String>(), menu.titles())
    }

    @Test
    fun rejectingSelectionDoesNotAddItemsAndDestroyDoesNotFinishAPendingReadAgain() {
        val calls = mutableListOf<String>()
        val original = RecordingCallback(calls).apply { createResult = false }
        val menu = FakeMenu()
        val mode = RecordingMode(menu.menu, calls)
        var complete: (() -> Unit)? = null
        val wrapped = ReaderSelectionActionModeCallback(original,
            onHighlight = { complete = it }, onAddNote = { error("Wrong entry point") })
        assertFalse(wrapped.onCreateActionMode(mode, menu.menu))
        assertEquals(emptyList<String>(), menu.titles())

        original.createResult = true
        assertTrue(wrapped.onCreateActionMode(mode, menu.menu))
        assertTrue(wrapped.onActionItemClicked(mode, menu.menu.findItem(R.id.reader_selection_highlight)!!))
        wrapped.onDestroyActionMode(mode)
        complete!!()
        assertEquals(0, mode.finishes)
        assertEquals(listOf("create", "create", "destroy"), calls)
    }

    @Test
    fun anEnhancementFailureRemovesPartialAdditionsAndLeavesNativeCopyWorking() {
        val calls = mutableListOf<String>()
        val original = RecordingCallback(calls)
        val menu = FakeMenu().apply { failingAddId = R.id.reader_selection_add_note }
        val mode = RecordingMode(menu.menu, calls)
        val wrapped = wrapper(original, calls)

        assertTrue(wrapped.onCreateActionMode(mode, menu.menu))
        assertEquals(listOf("Copy", "Share"), menu.titles())
        assertFalse(wrapped.onPrepareActionMode(mode, menu.menu))
        assertTrue(wrapped.onActionItemClicked(mode, menu.menu.findItem(android.R.id.copy)!!))
        assertEquals(listOf("create", "prepare", "click:Copy"), calls)
        assertEquals(0, mode.finishes)
    }

    @Test
    fun aCustomDispatchFailureFallsBackToTheOriginalCallback() {
        val calls = mutableListOf<String>()
        val menu = FakeMenu()
        val mode = RecordingMode(menu.menu, calls)
        val wrapped = ReaderSelectionActionModeCallback(RecordingCallback(calls),
            onHighlight = { throw IllegalStateException("Optional action failed") },
            onAddNote = { error("Wrong entry point") })
        wrapped.onCreateActionMode(mode, menu.menu)
        assertTrue(wrapped.onActionItemClicked(mode, menu.menu.findItem(R.id.reader_selection_highlight)!!))
        assertEquals(listOf("Copy", "Share"), menu.titles())
        assertTrue(wrapped.onActionItemClicked(mode, menu.menu.findItem(android.R.id.copy)!!))
        assertEquals(listOf("create", "click:Highlight", "click:Copy"), calls)
        assertEquals(0, mode.finishes)
    }

    private fun wrapper(original: ActionMode.Callback, calls: MutableList<String>) =
        ReaderSelectionActionModeCallback(original,
            onHighlight = { complete -> calls += "highlight"; complete() },
            onAddNote = { complete -> calls += "note"; complete() })

    private class RecordingCallback(private val calls: MutableList<String>) : ActionMode.Callback2() {
        var createResult = true
        var prepareResult = false
        var clickResult = true
        var rebuildOnPrepare = false
        var hasSelection = true
        var lastMode: ActionMode? = null
        var lastClickedItem: MenuItem? = null
        var lastView: View? = null

        private fun populate(menu: Menu) {
            if (!hasSelection) {
                menu.add(Menu.NONE, android.R.id.paste, 0, "Paste")
                return
            }
            menu.add(Menu.NONE, android.R.id.copy, 0, "Copy")
            menu.add(Menu.NONE, android.R.id.shareText, Menu.CATEGORY_SYSTEM or 7, "Share")
        }

        override fun onCreateActionMode(mode: ActionMode, menu: Menu): Boolean {
            calls += "create"
            lastMode = mode
            if (createResult) populate(menu)
            return createResult
        }

        override fun onPrepareActionMode(mode: ActionMode, menu: Menu): Boolean {
            calls += "prepare"
            lastMode = mode
            if (rebuildOnPrepare) { menu.clear(); populate(menu) }
            return prepareResult
        }

        override fun onActionItemClicked(mode: ActionMode, item: MenuItem): Boolean {
            calls += "click:${item.title}"
            lastMode = mode
            lastClickedItem = item
            return clickResult
        }

        override fun onDestroyActionMode(mode: ActionMode) { calls += "destroy"; lastMode = mode }

        override fun onGetContentRect(mode: ActionMode, view: View, outRect: Rect) {
            calls += "rect"
            lastMode = mode
            lastView = view
            outRect.set(10, 20, 30, 40)
        }
    }

    private class RecordingMode(private val backingMenu: Menu, private val calls: MutableList<String>) : ActionMode() {
        var finishes = 0
        override fun finish() { finishes++; calls += "finish" }
        override fun getMenu(): Menu = backingMenu
        override fun getMenuInflater(): MenuInflater = error("Unused")
        override fun invalidate() = Unit
        override fun getCustomView(): View? = null
        override fun setCustomView(view: View?) = Unit
        override fun getTitle(): CharSequence = ""
        override fun setTitle(title: CharSequence?) = Unit
        override fun setTitle(resId: Int) = Unit
        override fun getSubtitle(): CharSequence = ""
        override fun setSubtitle(subtitle: CharSequence?) = Unit
        override fun setSubtitle(resId: Int) = Unit
    }

    /** Only implements the menu operations used by the wrapper and recording original. */
    private class FakeMenu {
        private data class Item(val id: Int, val order: Int, val title: CharSequence, val proxy: MenuItem)
        private val items = mutableListOf<Item>()
        var failingAddId: Int? = null
        val menu: Menu = Proxy.newProxyInstance(Menu::class.java.classLoader, arrayOf(Menu::class.java)) {
            _, method, args ->
            when (method.name) {
                "add" -> {
                    val id = args!![1] as Int
                    check(id != failingAddId) { "Optional menu insertion failed" }
                    val order = args[2] as Int
                    val title = args[3] as CharSequence
                    val item = Proxy.newProxyInstance(MenuItem::class.java.classLoader,
                        arrayOf(MenuItem::class.java)) { _, getter, _ ->
                        when (getter.name) {
                            "getItemId" -> id
                            "getOrder" -> order
                            "getTitle" -> title
                            else -> error("Unexpected MenuItem operation: ${getter.name}")
                        }
                    } as MenuItem
                    items += Item(id, order, title, item)
                    // Android's category order, read from the cached SDK's MenuBuilder.
                    val categoryOrder = listOf(1, 4, 5, 3, 2, 0)
                    items.sortBy { (categoryOrder[it.order ushr 16] shl 16) or (it.order and 0xffff) }
                    item
                }
                "findItem" -> items.firstOrNull { it.id == args!![0] as Int }?.proxy
                "removeItem" -> { items.removeAll { it.id == args!![0] as Int }; null }
                "clear" -> { items.clear(); null }
                "size" -> items.size
                "getItem" -> items[args!![0] as Int].proxy
                else -> error("Unexpected Menu operation: ${method.name}")
            }
        } as Menu

        fun titles(): List<String> = items.map { it.title.toString() }
    }
}
