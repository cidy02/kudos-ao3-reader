package io.github.cidy02.kudos.app

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import io.github.cidy02.kudos.core.model.ReadingAnnotation
import io.github.cidy02.kudos.reader.ReaderNoteEditor
import io.github.cidy02.kudos.network.ao3.AO3PageCache
import io.github.cidy02.kudos.network.ao3.DemoNetwork
import io.github.cidy02.kudos.network.ao3.writing.recovery.WritingTextRecovery
import io.github.cidy02.kudos.ui.components.DestructiveConfirmation
import io.github.cidy02.kudos.ui.components.LogOutConfirmation
import io.github.cidy02.kudos.ui.subject.*
import io.github.cidy02.kudos.ui.theme.*
import io.github.cidy02.kudos.writing.*
import kotlinx.coroutines.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import kotlin.math.abs

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h1400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class Parity3hhDestructiveTest {
    @get:Rule val compose = createComposeRule()
    @get:Rule val temporary = TemporaryFolder()
    private var mode by mutableStateOf(KudosThemeMode.Light)
    private var visible by mutableStateOf(true)
    private lateinit var tokens: KudosTokens
    private lateinit var view: View
    private val themes = listOf(KudosThemeMode.Light, KudosThemeMode.Sepia, KudosThemeMode.Dark, KudosThemeMode.Oled)
    private fun expected(theme: KudosThemeMode): Color = when (theme) {
        KudosThemeMode.Dark, KudosThemeMode.Oled -> Color(0xFFFF4245)
        else -> Color(0xFFFF383C)
    }

    @Before fun setUp() {
        DemoNetwork.resetForTests()
        AO3PageCache.shared.clear()
        DebugShotRequests.clear()
    }

    @After fun tearDown() {
        compose.runOnIdle { visible = false }
        compose.waitForIdle()
        DebugShotRequests.clear()
        DemoNetwork.resetForTests()
        AO3PageCache.shared.clear()
    }

    private fun show(content: @Composable () -> Unit) {
        compose.setContent { if (visible) KudosTheme(mode, accentColorHex = "#008577") {
            tokens = LocalKudosTokens.current
            view = LocalView.current
            content()
        } }
    }

    private fun textColor(label: String): Color {
        val layouts = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText(label, useUnmergedTree = true)
            .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        return layouts.single().layoutInput.style.color
    }

    @Test fun tokensAndMaterialErrorsUseSystemRedInEveryThemeEvenUnderASubjectTint() {
        var materialError = Color.Unspecified
        var onError = Color.Unspecified
        var subjectError = Color.Unspecified
        var subjectDestructive = Color.Unspecified
        show {
            materialError = MaterialTheme.colorScheme.error
            onError = MaterialTheme.colorScheme.onError
            SubjectPaletteTheme(SubjectPalette.fromColor(Color(0xFF733AB5), tokens.theme)) {
                subjectError = MaterialTheme.colorScheme.error
                subjectDestructive = LocalKudosTokens.current.destructive
            }
        }
        for (theme in themes) {
            compose.runOnIdle { mode = theme }
            compose.waitForIdle()
            val red = expected(theme)
            assertEquals("Token in $theme", red, tokens.destructive)
            assertEquals(red, tokens.theme.destructive)
            assertEquals("Material error in $theme", red, materialError)
            assertEquals(SubjectPalette.label(red), onError)
            assertEquals("Subject Material error in $theme", red, subjectError)
            assertEquals("Subject token in $theme", red, subjectDestructive)
        }
    }

    @Test fun subjectDeleteAndLogOutConfirmationsKeepRedInEveryTheme() {
        var logout by mutableStateOf(false)
        lateinit var palette: SubjectPalette
        show {
            palette = SubjectPalette.fromColor(Color(0xFF733AB5), tokens.theme)
            SubjectPaletteTheme(palette) {
                if (logout) LogOutConfirmation(true, {}, {})
                else DestructiveConfirmation(true, "Delete collection?", "Works stay in your Library.",
                    confirmBeforeDelete = true, onConfirm = {}, onDismissRequest = {}, palette = palette)
            }
        }
        for (theme in themes) {
            compose.runOnIdle { mode = theme; logout = false }
            compose.waitForIdle()
            assertEquals(expected(theme), textColor("Delete"))
            assertEquals(palette.accent, textColor("Cancel"))
            compose.runOnIdle { logout = true }
            compose.waitForIdle()
            assertEquals(expected(theme), textColor("Log Out"))
        }
    }

    @Test fun readerNoteDeleteDoesNotOverrideSystemRedWithTheAppRed() {
        show { ReaderNoteEditor(ReadingAnnotation(workID = "local", selectedText = "Quoted words"), {}, {}, {}, {}) }
        for (theme in themes) {
            compose.runOnIdle { mode = theme }
            compose.waitForIdle()
            assertEquals(expected(theme), textColor("Delete Highlight"))
        }
    }

    @Test fun recoveryDeleteTextActuallyPaintsSystemRedInAllFourThemes() {
        val store = WritingTextRecovery(temporary.newFolder().toPath())
        val key = store.fileURL("Writer", "work:17", "content")
        store.save("Recovered text", "Original", store.sessionURL(key))
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        try {
            show {
                val context = androidx.compose.ui.platform.LocalContext.current
                val session = remember { WritingEditorSession(WritingNativeTextField(context, "Original"), "Original", store,
                    "Writer", "work:17", "content", scope, android.os.SystemClock::uptimeMillis) }
                WritingRecoverySheet(session, presentSheet = { ground, content ->
                    Surface(color = ground, modifier = Modifier.fillMaxWidth()) { content() }
                })
            }
            compose.waitUntil(15_000) { compose.onAllNodesWithText("Delete this local copy").fetchSemanticsNodes().isNotEmpty() }
            for (theme in themes) {
                compose.runOnIdle { mode = theme }
                compose.waitForIdle()
                val label = "Delete this local copy"
                val bounds = compose.onNodeWithText(label, useUnmergedTree = true).assertIsDisplayed().fetchSemanticsNode().boundsInRoot
                val red = expected(theme)
                assertEquals("Recovery text style in $theme", red, textColor(label))
                var matchingPixels = 0
                compose.runOnIdle {
                    val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
                    view.draw(Canvas(bitmap))
                    for (y in bounds.top.toInt() until bounds.bottom.toInt()) {
                        for (x in bounds.left.toInt() until bounds.right.toInt()) {
                            val pixel = Color(bitmap.getPixel(x, y))
                            if (maxOf(abs(pixel.red - red.red), abs(pixel.green - red.green), abs(pixel.blue - red.blue)) < 0.012f) matchingPixels++
                        }
                    }
                    bitmap.recycle()
                }
                assertTrue("Recovery Delete paints system red in $theme", matchingPixels > 5)
            }
            // Colour inspection never invokes a recovery action.
            assertEquals(1, store.copies(key).size)
        } finally { scope.cancel() }
    }
}
