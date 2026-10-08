package io.github.cidy02.kudos.writing

import android.app.Activity
import android.app.Application
import android.graphics.Color
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class WritingNativeTextFieldTests {
    @Test fun nativeEditorPreservesSourceSelectionUndoAndRecovery() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val original = "<p class='keep'>Hello 👩🏽‍💻 &amp; 世界</p>\n<custom>keep</custom>"
        val editor = WritingNativeTextField(activity, original)
        activity.setContentView(editor.view)
        editor.view.requestFocus()
        var edits = 0
        editor.onEdited = { edits++ }
        editor.setAppearance(Color.BLACK, 23f)
        editor.commitComposition()
        assertEquals(original, editor.takeText())
        assertNull(editor.takeCheckpoint())
        val selected = "👩🏽‍💻 &amp; 世界"
        val start = original.indexOf(selected)
        editor.view.setSelection(start, start + selected.length)
        editor.insert("strong")
        val edited = original.replace(selected, "<strong>$selected</strong>")
        assertEquals(edited, editor.takeText())
        assertEquals(selected, editor.view.text.substring(editor.view.selectionStart, editor.view.selectionEnd))
        assertTrue(edits > 0)
        assertEquals(edited, editor.takeCheckpoint())
        assertNull(editor.takeCheckpoint())
        editor.undo()
        assertEquals(original, editor.takeText())
        assertEquals(original, editor.takeCheckpoint())
        editor.redo()
        assertEquals(edited, editor.takeText())
        editor.setText("<table><tr><td>Recovered</td></tr></table>")
        assertEquals("<table><tr><td>Recovered</td></tr></table>", editor.takeCheckpoint())
        editor.undo()
        assertEquals(edited, editor.takeText())
        editor.view.setSelection(edited.length)
        val input = editor.view.onCreateInputConnection(EditorInfo())!!
        input.setComposingText("に", 1)
        input.setComposingText("日本", 1)
        editor.commitComposition()
        assertEquals(-1, BaseInputConnection.getComposingSpanStart(editor.view.text))
        assertEquals(edited + "日本", editor.takeCheckpoint())
        activity.finish()
    }

    @Test fun idleSnapshotDoesNotCommitAnIMEComposition() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val editor = WritingNativeTextField(activity, "before ")
        activity.setContentView(editor.view)
        editor.view.requestFocus(); editor.view.setSelection(editor.view.text.length)
        val input = editor.view.onCreateInputConnection(EditorInfo())!!
        input.setComposingText("日本", 1)
        assertEquals("before 日本", editor.takeCheckpoint())
        assertTrue(BaseInputConnection.getComposingSpanStart(editor.view.text) >= 0)
        editor.commitComposition()
        assertEquals(-1, BaseInputConnection.getComposingSpanStart(editor.view.text))
        activity.finish()
    }

    @Test fun typingThenDeletingSkipsAWriteAndToolbarCommandsAreSeparateUndoSteps() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val editor = WritingNativeTextField(activity, "word")
        activity.setContentView(editor.view)
        editor.view.text.append("x"); editor.view.text.delete(4, 5)
        assertNull(editor.takeCheckpoint())
        editor.view.setSelection(0, 4)
        editor.insert("strong"); editor.insert("em")
        assertEquals("<strong><em>word</em></strong>", editor.takeText())
        editor.undo(); assertEquals("<strong>word</strong>", editor.takeText())
        editor.undo(); assertEquals("word", editor.takeText())
        activity.finish()
    }
}
