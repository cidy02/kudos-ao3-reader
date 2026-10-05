package io.github.cidy02.kudos.reader.readium

import android.content.Context
import android.graphics.Rect
import android.view.ActionMode
import android.view.Menu
import android.view.MenuItem
import android.view.View
import android.webkit.WebView
import android.widget.FrameLayout
import io.github.cidy02.kudos.R

/** Keeps WebView's own selection callback, including Copy and text-processing actions. */
internal class ReaderSelectionContainer(
    context: Context,
    private val onHighlight: (() -> Unit) -> Unit,
    private val onAddNote: (() -> Unit) -> Unit
) : FrameLayout(context) {
    override fun startActionModeForChild(
        originalView: View,
        callback: ActionMode.Callback,
        type: Int
    ): ActionMode? {
        val wrapped = wrapReaderSelectionActionMode(
            callback, type, originalView is WebView, onHighlight, onAddNote
        )
        return try {
            super.startActionModeForChild(originalView, wrapped, type)
        } catch (error: RuntimeException) {
            if (wrapped === callback) throw error
            super.startActionModeForChild(originalView, callback, type)
        }
    }

    // The untyped overload is TYPE_PRIMARY, so it must pass through unchanged.
    override fun startActionModeForChild(originalView: View, callback: ActionMode.Callback): ActionMode? =
        super.startActionModeForChild(originalView, callback)
}

/** The boolean lets unit tests exercise the filter without constructing a WebView. */
internal fun wrapReaderSelectionActionMode(
    original: ActionMode.Callback,
    type: Int,
    isNavigatorWebView: Boolean,
    onHighlight: (() -> Unit) -> Unit,
    onAddNote: (() -> Unit) -> Unit
): ActionMode.Callback {
    if (type != ActionMode.TYPE_FLOATING || !isNavigatorWebView) return original
    return ReaderSelectionActionModeCallback(original, onHighlight, onAddNote)
}

internal class ReaderSelectionActionModeCallback(
    private val original: ActionMode.Callback,
    // Completion runs after Readium's asynchronous selection read, before dismissal.
    private val onHighlight: (() -> Unit) -> Unit,
    private val onAddNote: (() -> Unit) -> Unit
) : ActionMode.Callback2() {
    private var customActionsEnabled = true
    private var selectionActionPending = false
    private var destroyed = false

    override fun onCreateActionMode(mode: ActionMode, menu: Menu): Boolean {
        val created = original.onCreateActionMode(mode, menu)
        if (created) addActions(menu)
        return created
    }

    override fun onPrepareActionMode(mode: ActionMode, menu: Menu): Boolean {
        val changed = original.onPrepareActionMode(mode, menu)
        // Chromium can clear/rebuild its menu here, not only on creation.
        return addActions(menu) || changed
    }

    private fun addActions(menu: Menu): Boolean {
        if (!customActionsEnabled || destroyed) return false
        return try {
            // The rule is "the native menu holds something", not "it holds Copy": the WebView's
            // Copy has Chromium's id, not android.R.id.copy, and looking for that id meant
            // nothing was ever added on a device. A book's page has no field to put a caret
            // in, so a floating menu there is over selected text; and with nothing selected
            // either action does nothing.
            val hasNativeItem = (0 until menu.size()).any {
                val id = menu.getItem(it).itemId
                id != R.id.reader_selection_highlight && id != R.id.reader_selection_add_note
            }
            if (!hasNativeItem) {
                val hadActions = menu.findItem(R.id.reader_selection_highlight) != null ||
                    menu.findItem(R.id.reader_selection_add_note) != null
                removeActions(menu)
                return hadActions
            }
            var added = false
            if (menu.findItem(R.id.reader_selection_highlight) == null) {
                // CATEGORY_SYSTEM sorts last in Android's menu category ordering.
                menu.add(Menu.NONE, R.id.reader_selection_highlight,
                    Menu.CATEGORY_SYSTEM or 0xfffe, "Highlight")
                added = true
            }
            if (menu.findItem(R.id.reader_selection_add_note) == null) {
                menu.add(Menu.NONE, R.id.reader_selection_add_note,
                    Menu.CATEGORY_SYSTEM or 0xffff, "Add Note")
                added = true
            }
            added
        } catch (_: RuntimeException) {
            // An optional action must never break the original menu or Copy.
            customActionsEnabled = false
            removeActions(menu)
            false
        }
    }

    private fun removeActions(menu: Menu) {
        runCatching { menu.removeItem(R.id.reader_selection_highlight) }
        runCatching { menu.removeItem(R.id.reader_selection_add_note) }
    }

    override fun onActionItemClicked(mode: ActionMode, item: MenuItem): Boolean {
        val action = when (item.itemId) {
            R.id.reader_selection_highlight -> onHighlight
            R.id.reader_selection_add_note -> onAddNote
            else -> return original.onActionItemClicked(mode, item)
        }
        if (!customActionsEnabled || destroyed) return original.onActionItemClicked(mode, item)
        if (selectionActionPending) return true
        return try {
            selectionActionPending = true
            var completed = false
            action {
                if (!completed) {
                    completed = true
                    if (!destroyed) mode.finish()
                }
            }
            true
        } catch (_: RuntimeException) {
            customActionsEnabled = false
            selectionActionPending = false
            removeActions(mode.menu)
            original.onActionItemClicked(mode, item)
        }
    }

    override fun onDestroyActionMode(mode: ActionMode) {
        destroyed = true
        original.onDestroyActionMode(mode)
    }

    override fun onGetContentRect(mode: ActionMode, view: View, outRect: Rect) {
        val callback2 = original as? ActionMode.Callback2
        if (callback2 != null) {
            callback2.onGetContentRect(mode, view, outRect)
        } else {
            super.onGetContentRect(mode, view, outRect)
        }
    }
}
