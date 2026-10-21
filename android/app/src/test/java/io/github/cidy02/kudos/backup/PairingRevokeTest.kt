package io.github.cidy02.kudos.backup

import android.app.Application
import android.content.Context
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.google.crypto.tink.subtle.Ed25519Sign
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.SyncTombstone
import io.github.cidy02.kudos.core.model.SyncTombstoneRecordType
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.works.WorkRepository
import java.io.File
import java.nio.file.Files
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The pairing card's two taps. Clearing the badge and revoking a device go
 * through this screen; a service test alone would stay green if the tap put
 * the old behavior back.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h2400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class PairingRevokeTest {
    @get:Rule val compose = createComposeRule()

    private lateinit var database: KudosDatabase
    private lateinit var settingsScope: CoroutineScope
    private lateinit var settingsRepository: SettingsRepository
    private lateinit var workRepository: WorkRepository
    private lateinit var trustStore: TombstoneTrustStore

    private val workId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    private val peer = Ed25519Sign.KeyPair.newKeyPair().publicKey.toLowerHex()

    @Before
    fun setUp() {
        val context: Context = ApplicationProvider.getApplicationContext()
        database = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        settingsScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val settingsDir = Files.createTempDirectory("kudos-pairing-ui-settings").toFile()
        settingsRepository = SettingsRepository(
            PreferenceDataStoreFactory.create(
                scope = settingsScope,
                produceFile = { File(settingsDir, "settings.preferences_pb") }
            )
        )
        val filesRoot = Files.createTempDirectory("kudos-pairing-ui-files")
        workRepository = WorkRepository(
            database = database,
            fileStore = WorkFileStore(filesRoot),
            clock = { Instant.parse("2026-08-16T12:00:00Z") }
        )
        // The row compares trustedAt with Instant.now(). Epoch is outside the undo window,
        // so the row offers Revoke. The store's clock is not the one the row uses.
        trustStore = TombstoneTrustStore(settingsRepository) { Instant.EPOCH }
        TombstoneSigning.publicKeyHex()
        runBlocking {
            assertTrue(trustStore.trust(peer, "Other phone"))
            workRepository.upsert(
                SavedWork(
                    id = workId,
                    title = "Example",
                    author = "Alice",
                    sourceUrl = "https://archiveofourown.org/works/123",
                    isDeleted = true,
                    deletedAt = Instant.parse("2026-08-15T00:00:00Z")
                )
            )
            database.syncTombstoneDao().upsert(
                SyncTombstone(
                    id = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
                    recordID = workId,
                    recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
                    createdAt = Instant.parse("2026-08-15T00:00:00Z"),
                    sourceURL = "https://archiveofourown.org/works/123",
                    ao3WorkID = 123,
                    signerPublicKey = peer
                ).toEntity()
            )
            settingsRepository.recordUnknownSignerTombstoneIds(setOf(workId), emptySet())
        }
    }

    @After
    fun tearDown() {
        database.close()
        settingsScope.cancel()
        TombstoneSigning.resetForTests()
    }

    @Test
    fun revokeLeavesTheWorkDeletedAndTheSkippedDeletionTapClearsTheCount() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                Box(Modifier.fillMaxSize()) {
                    PairingCard(settingsRepository, database, workRepository)
                }
            }
        }
        compose.waitUntil(timeoutMillis = 5_000) {
            compose.onAllNodesWithText("Revoke").fetchSemanticsNodes().isNotEmpty() &&
                compose.onAllNodesWithText("1 deletion skipped from an unpaired device")
                    .fetchSemanticsNodes().isNotEmpty()
        }

        compose.onNodeWithText("Revoke").performClick()
        compose.onNodeWithTag("confirmRevoke").performClick()
        compose.waitUntil(timeoutMillis = 5_000) {
            compose.onAllNodesWithText("Revoked that device.").fetchSemanticsNodes().isNotEmpty()
        }

        assertFalse(runBlocking { trustStore.isTrusted(peer) })
        val kept = runBlocking { workRepository.getWork(workId) }
        assertNotNull(kept)
        assertTrue(kept!!.isDeleted)
        assertTrue(
            runBlocking {
                database.syncTombstoneDao()
                    .getBySigner(peer, SyncTombstoneRecordType.SAVED_WORK)
                    .isNotEmpty()
            }
        )
        compose.onNodeWithText("Restored", substring = true).assertDoesNotExist()

        compose.onNodeWithText("1 deletion skipped from an unpaired device").performClick()
        compose.waitUntil(timeoutMillis = 5_000) {
            compose.waitForIdle()
            runBlocking { settingsRepository.unknownSignerTombstoneIdsSnapshot().isEmpty() }
        }
    }
}
