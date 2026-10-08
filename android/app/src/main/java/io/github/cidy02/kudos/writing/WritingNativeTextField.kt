package io.github.cidy02.kudos.writing

import android.content.Context
import android.graphics.Typeface
import android.os.Build
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import java.text.Normalizer

/**
 * A native, plain-text HTML buffer. Inserting tags never parses or normalizes
 * existing markup; the platform text system owns selection, IME and undo.
 *
 * An edit callback only increments revision and notifies the scheduler. Android's
 * own Editable/undo/layout work is separate and must pass B1/B6 on a device.
 * Keep all widget-specific operations here so the gate can replace this one file.
 */
class WritingNativeTextField(context: Context, initialText: String) {
    private val density = context.resources.displayMetrics.density
    val view = EditText(context).apply {
        background = null
        gravity = Gravity.TOP or Gravity.START
        inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
        typeface = Typeface.create("serif", Typeface.NORMAL)
        setText(initialText)
        setSelection(0)
        contentDescription = "HTML text"
        isVerticalScrollBarEnabled = true
        // Recovery owns persistence. Do not serialize a second chapter into saved view state.
        isSaveEnabled = false
        setPadding(dp(12), dp(16), dp(12), dp(16))
        setLineSpacing(0f, 1.35f)
    }
    var onEdited: (() -> Unit)? = null
    private var revision = 0L
    private var checkpointedRevision = 0L
    private var checkpointedText = initialText
    private var appearance: Pair<Int, Float>? = null

    init {
        view.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = Unit
            override fun afterTextChanged(s: Editable?) { revision++; onEdited?.invoke() }
        })
    }

    private fun dp(value: Int): Int = (value * density).toInt()

    fun setAppearance(color: Int, fontSizePx: Float) {
        if (appearance == (color to fontSizePx)) return
        appearance = color to fontSizePx
        view.setTextColor(color)
        view.highlightColor = (color and 0x00ffffff) or (0x33 shl 24)
        if (Build.VERSION.SDK_INT >= 29) {
            view.textCursorDrawable?.mutate()?.setTint(color)
            view.textSelectHandle?.mutate()?.setTint(color)
            view.textSelectHandleLeft?.mutate()?.setTint(color)
            view.textSelectHandleRight?.mutate()?.setTint(color)
        }
        view.setTextSize(TypedValue.COMPLEX_UNIT_PX, fontSizePx)
    }

    fun takeText(): String = view.text.toString()

    fun takeCheckpoint(): String? {
        if (revision == checkpointedRevision) return null
        checkpointedRevision = revision
        val value = takeText()
        if (Normalizer.normalize(value, Normalizer.Form.NFC) ==
            Normalizer.normalize(checkpointedText, Normalizer.Form.NFC)) return null
        checkpointedText = value
        return value
    }

    /** Explicit commands only. Idle/background/memory snapshots never finish composing text. */
    fun commitComposition() {
        view.onCreateInputConnection(EditorInfo())?.finishComposingText()
    }

    fun insert(tag: String, link: String = "") {
        commitComposition()
        val start = minOf(view.selectionStart, view.selectionEnd).coerceAtLeast(0)
        val end = maxOf(view.selectionStart, view.selectionEnd).coerceAtLeast(start)
        val insertion = WritingMarkup.insertion(tag, view.text, start, end, link) ?: return
        // Outside a batch: Editor's UndoInputFilter makes this one separate undoable change.
        view.text.replace(start, end, insertion.text)
        view.setSelection(start + insertion.contentOffset, start + insertion.contentOffset + insertion.contentLength)
        view.requestFocus()
        view.post { view.bringPointIntoView(view.selectionEnd) }
    }

    /** Set text is an undoable replacement, including Restore. Never call EditText.setText here. */
    fun setText(value: String) {
        commitComposition()
        view.text.replace(0, view.text.length, value)
        view.setSelection(value.length)
        view.post { view.bringPointIntoView(view.selectionEnd) }
    }

    fun undo() { commitComposition(); view.onTextContextMenuItem(android.R.id.undo) }
    fun redo() { commitComposition(); view.onTextContextMenuItem(android.R.id.redo) }
    fun pastePlainText() { commitComposition(); view.onTextContextMenuItem(android.R.id.pasteAsPlainText) }

    fun endEditing() {
        (view.context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager)
            .hideSoftInputFromWindow(view.windowToken, 0)
        view.clearFocus()
    }

    fun showEditing(editing: Boolean) {
        view.alpha = if (editing) 1f else 0f
        view.isEnabled = editing
        view.importantForAccessibility = if (editing) View.IMPORTANT_FOR_ACCESSIBILITY_AUTO
            else View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
    }
}
