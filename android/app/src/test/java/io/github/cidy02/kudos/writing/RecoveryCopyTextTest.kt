package io.github.cidy02.kudos.writing

import android.app.Application
import android.content.Intent
import androidx.compose.ui.platform.ClipboardManager
import androidx.compose.ui.text.AnnotatedString
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** A85: a recovery copy too long for the clipboard is shared as a file, not copied into a crash. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class RecoveryCopyTextTest {
    private class FakeClipboard : ClipboardManager {
        var stored: AnnotatedString? = null
        override fun getText(): AnnotatedString? = stored
        override fun setText(annotatedString: AnnotatedString) { stored = annotatedString }
    }

    @Test fun aShortCopyGoesToTheClipboardAndALongOneIsSharedAsAFile() {
        val app = RuntimeEnvironment.getApplication() as Application
        val clipboard = FakeClipboard()

        copyRecoveryText(app, clipboard, "Recovered paragraph.")
        assertEquals("Recovered paragraph.", clipboard.stored?.text)
        assertNull("nothing shared for a short copy", shadowOf(app).nextStartedActivity)

        copyRecoveryText(app, clipboard, "x".repeat(RECOVERY_CLIPBOARD_LIMIT + 1))
        assertEquals("the long copy never reached the clipboard", "Recovered paragraph.", clipboard.stored?.text)
        val shared = shadowOf(app).nextStartedActivity
        assertEquals(Intent.ACTION_CHOOSER, shared.action)
    }
}
