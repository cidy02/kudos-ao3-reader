package io.github.cidy02.kudos.backup

import android.app.Application
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h2400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ImportBackupChoicesTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun replaceIsOfferedWhenABookmarkWouldBeRemovedAndNotOnlyWhenThereAreWorks() {
        show(preview(localWorkCount = 0, hasReplaceableRecords = true))
        compose.onNodeWithText("Replace Library…").assertExists()
        compose.onNodeWithText("Merge adds works that are not already here. It does not delete local works or apply unsigned deletion claims from the file.").assertDoesNotExist()
        compose.onNodeWithText("Restore from Backup").assertDoesNotExist()
    }

    @Test
    fun anEmptyLibraryOffersMergeWithTheSameExplanation() {
        show(preview(localWorkCount = 0, hasReplaceableRecords = false))
        compose.onNodeWithText("Merge").assertExists()
        compose.onNodeWithText("Restore from Backup").assertDoesNotExist()
        compose.onNodeWithText("Merge keeps everything already on this device and adds anything you don't have from the backup. It removes nothing.").assertExists()
        compose.onNodeWithText("Replace Library…").assertDoesNotExist()
    }

    @Test
    fun farFewerWorksShowsOnlyWhileReplaceIsBeingReviewed() {
        show(
            preview(
                localWorkCount = 40,
                fileWorkCount = 30,
                willAdd = 2,
                willRemove = 20,
                inBoth = 28,
                hasReplaceableRecords = true
            )
        )
        compose.onNodeWithText(FAR_FEWER).assertDoesNotExist()
        compose.onNodeWithText("Replace Library…").performClick()
        compose.onNodeWithText(FAR_FEWER).assertExists()
    }

    @Test
    fun aSmallerFileThatIsNotALargeRemovalDoesNotWarnOnReview() {
        show(
            preview(
                localWorkCount = 100,
                fileWorkCount = 10,
                willAdd = 0,
                willRemove = 19,
                inBoth = 10,
                hasReplaceableRecords = true
            )
        )
        compose.onNodeWithText("Replace Library…").performClick()
        compose.onNodeWithText(FAR_FEWER).assertDoesNotExist()
    }

    private var reviewing by mutableStateOf(false)

    private fun show(preview: BackupImportPreview) {
        reviewing = false
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                Box(Modifier.fillMaxSize()) {
                    ImportBackupChoices(
                        pending = PendingBackupImport(
                            bytes = byteArrayOf(),
                            preview = preview,
                            manifest = KudosBackupManifest(
                                version = BackupVersion.CURRENT,
                                exportedAt = "2026-10-20T00:00:00Z"
                            ),
                            syncEnabled = false
                        ),
                        reviewingReplace = reviewing,
                        acknowledgeRemoval = false,
                        pauseSync = true,
                        replaceEnabled = false,
                        onReviewingReplace = { reviewing = it },
                        onAcknowledgeRemoval = {},
                        onPauseSync = {},
                        onDismiss = {},
                        onMerge = {},
                        onReplace = {}
                    )
                }
            }
        }
    }

    private fun preview(
        localWorkCount: Int,
        fileWorkCount: Int = 0,
        willAdd: Int = 0,
        willRemove: Int = 0,
        inBoth: Int = 0,
        hasReplaceableRecords: Boolean
    ) = BackupImportPreview(
        localWorkCount = localWorkCount,
        fileWorkCount = fileWorkCount,
        willAdd = willAdd,
        willRemove = willRemove,
        inBoth = inBoth,
        hasReplaceableRecords = hasReplaceableRecords
    )

    private companion object {
        const val FAR_FEWER = "This backup has far fewer works than your current library."
    }
}
