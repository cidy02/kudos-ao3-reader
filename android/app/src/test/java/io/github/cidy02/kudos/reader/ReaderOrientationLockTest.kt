package io.github.cidy02.kudos.reader

import android.app.Activity
import android.app.Application
import android.content.pm.ActivityInfo
import android.view.Surface
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.compose.LocalLifecycleOwner
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowDisplay

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h900dp-port")
class ReaderOrientationLockTest {
    @get:Rule val compose = createComposeRule()

    private val dataStore = object : DataStore<Preferences> {
        override val data = MutableStateFlow(emptyPreferences())
        override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences =
            transform(data.value).also { data.value = it }
    }
    private val repository = SettingsRepository(dataStore)

    private lateinit var activity: Activity
    private var reading by mutableStateOf(false)
    private var session by mutableIntStateOf(1)

    private fun mountHost(lifecycleOwner: LifecycleOwner? = null) {
        compose.setContent {
            activity = LocalContext.current as Activity
            val content: @Composable () -> Unit = {
                if (reading) {
                    key(session) {
                        val lock = rememberReaderOrientationLock(repository)
                        MaterialTheme {
                            ReaderFanMenu(
                                isOpen = true,
                                onOpenChange = {},
                                pills = emptyList(),
                                roundActions = listOf(readerRotationLockAction(lock))
                            )
                        }
                    }
                }
            }
            if (lifecycleOwner != null) {
                CompositionLocalProvider(LocalLifecycleOwner provides lifecycleOwner, content = content)
            } else {
                content()
            }
        }
        compose.waitForIdle()
    }

    @Test
    fun fromDisplayCoversAllFourOrientationsForPortraitAndLandscapeNaturalDevices() {
        // Portrait-natural phone: ROTATION_0/180 are portrait, ROTATION_90/270 are landscape.
        assertEquals(ReaderLockedOrientation.Portrait, ReaderLockedOrientation.fromDisplay(Surface.ROTATION_0, false))
        assertEquals(ReaderLockedOrientation.Landscape, ReaderLockedOrientation.fromDisplay(Surface.ROTATION_90, true))
        assertEquals(ReaderLockedOrientation.ReversePortrait, ReaderLockedOrientation.fromDisplay(Surface.ROTATION_180, false))
        assertEquals(ReaderLockedOrientation.ReverseLandscape, ReaderLockedOrientation.fromDisplay(Surface.ROTATION_270, true))

        // Landscape-natural tablet: ROTATION_0/180 are landscape, ROTATION_90/270 are portrait.
        assertEquals(ReaderLockedOrientation.Landscape, ReaderLockedOrientation.fromDisplay(Surface.ROTATION_0, true))
        assertEquals(ReaderLockedOrientation.ReversePortrait, ReaderLockedOrientation.fromDisplay(Surface.ROTATION_90, false))
        assertEquals(ReaderLockedOrientation.ReverseLandscape, ReaderLockedOrientation.fromDisplay(Surface.ROTATION_180, true))
        assertEquals(ReaderLockedOrientation.Portrait, ReaderLockedOrientation.fromDisplay(Surface.ROTATION_270, false))

        // None of the saved orientations may ever map to SCREEN_ORIENTATION_LOCKED or UNSPECIFIED.
        ReaderLockedOrientation.entries.forEach { entry ->
            assertNotEquals(ActivityInfo.SCREEN_ORIENTATION_LOCKED, entry.activityInfoOrientation)
            assertNotEquals(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED, entry.activityInfoOrientation)
        }
    }

    @Test
    fun lockPersistsConcreteOrientationAcrossLeaveAndReopenAndUnlockIsRemembered() {
        mountHost()
        Shadows.shadowOf(ShadowDisplay.getDefaultDisplay()).setRotation(Surface.ROTATION_180)

        // Open reader #1 unlocked.
        compose.runOnIdle { reading = true }
        compose.waitForIdle()
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED, activity.requestedOrientation)
        compose.onNodeWithContentDescription("Lock rotation").assertExists()

        // Lock while upside-down portrait -> saves concrete ReversePortrait (not SCREEN_ORIENTATION_LOCKED).
        compose.onNodeWithContentDescription("Lock rotation").performClick()
        compose.waitUntil(5_000) {
            runBlocking { repository.readerOrientationLock.first() } == ReaderLockedOrientation.ReversePortrait
        }
        compose.waitForIdle()
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_REVERSE_PORTRAIT, activity.requestedOrientation)
        assertNotEquals(ActivityInfo.SCREEN_ORIENTATION_LOCKED, activity.requestedOrientation)
        compose.onNodeWithContentDescription("Unlock rotation").assertIsSelected()

        // Leave reader #1 -> restores UNSPECIFIED for the rest of the app, keeps setting ON.
        compose.runOnIdle { reading = false }
        compose.waitForIdle()
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED, activity.requestedOrientation)
        assertEquals(
            ReaderLockedOrientation.ReversePortrait,
            runBlocking { repository.readerOrientationLock.first() }
        )

        // Turn the device right-side up while outside the reader.
        Shadows.shadowOf(ShadowDisplay.getDefaultDisplay()).setRotation(Surface.ROTATION_0)
        assertEquals(ReaderLockedOrientation.Portrait, ReaderLockedOrientation.currentOf(activity))

        // Open reader #2 -> pins the saved ReversePortrait (not current Portrait) and button reads locked.
        compose.runOnIdle { session++; reading = true }
        compose.waitForIdle()
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_REVERSE_PORTRAIT, activity.requestedOrientation)
        compose.onNodeWithContentDescription("Unlock rotation").assertIsSelected()

        // Unlock -> saves OFF and restores UNSPECIFIED.
        compose.onNodeWithContentDescription("Unlock rotation").performClick()
        compose.waitUntil(5_000) { runBlocking { repository.readerOrientationLock.first() } == null }
        compose.waitForIdle()
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED, activity.requestedOrientation)
        compose.onNodeWithContentDescription("Lock rotation").assertExists()
        compose.onNodeWithContentDescription("Unlock rotation").assertDoesNotExist()

        // Leave and open reader #3 -> unlock is remembered.
        compose.runOnIdle { reading = false }
        compose.waitForIdle()
        compose.runOnIdle { session++; reading = true }
        compose.waitForIdle()
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED, activity.requestedOrientation)
        compose.onNodeWithContentDescription("Lock rotation").assertExists()
        assertNull(runBlocking { repository.readerOrientationLock.first() })
    }

    @Test
    @Config(qualifiers = "w800dp-h400dp-land")
    fun landscapeLockPinsLandscapeAndReverseLandscapeAcrossSessions() {
        mountHost()
        Shadows.shadowOf(ShadowDisplay.getDefaultDisplay()).setRotation(Surface.ROTATION_90)

        compose.runOnIdle { reading = true }
        compose.waitForIdle()
        compose.onNodeWithContentDescription("Lock rotation").performClick()
        compose.waitUntil(5_000) {
            runBlocking { repository.readerOrientationLock.first() } == ReaderLockedOrientation.Landscape
        }
        compose.waitForIdle()
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE, activity.requestedOrientation)

        // Leave reader, flip to reverse landscape, reopen -> still pins saved Landscape.
        compose.runOnIdle { reading = false }
        compose.waitForIdle()
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED, activity.requestedOrientation)
        Shadows.shadowOf(ShadowDisplay.getDefaultDisplay()).setRotation(Surface.ROTATION_270)
        assertEquals(ReaderLockedOrientation.ReverseLandscape, ReaderLockedOrientation.currentOf(activity))

        compose.runOnIdle { session++; reading = true }
        compose.waitForIdle()
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE, activity.requestedOrientation)

        // Unlock then re-lock at ROTATION_270 -> saves and pins ReverseLandscape.
        compose.onNodeWithContentDescription("Unlock rotation").performClick()
        compose.waitUntil(5_000) { runBlocking { repository.readerOrientationLock.first() } == null }
        compose.waitForIdle()
        compose.onNodeWithContentDescription("Lock rotation").performClick()
        compose.waitUntil(5_000) {
            runBlocking { repository.readerOrientationLock.first() } == ReaderLockedOrientation.ReverseLandscape
        }
        compose.waitForIdle()
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE, activity.requestedOrientation)

        compose.runOnIdle { reading = false }
        compose.waitForIdle()
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED, activity.requestedOrientation)
        assertEquals(
            ReaderLockedOrientation.ReverseLandscape,
            runBlocking { repository.readerOrientationLock.first() }
        )
    }

    @Test
    fun openingWithPersistedLandscapeLockPinsLandscapeEvenOnPortraitDisplay() {
        runBlocking { repository.updateReaderOrientationLock(ReaderLockedOrientation.Landscape) }
        mountHost()
        Shadows.shadowOf(ShadowDisplay.getDefaultDisplay()).setRotation(Surface.ROTATION_0)

        compose.runOnIdle { reading = true }
        compose.waitForIdle()
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE, activity.requestedOrientation)
        compose.onNodeWithContentDescription("Unlock rotation").assertIsSelected()

        compose.runOnIdle { reading = false }
        compose.waitForIdle()
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED, activity.requestedOrientation)
        assertEquals(
            ReaderLockedOrientation.Landscape,
            runBlocking { repository.readerOrientationLock.first() }
        )
    }

    @Test
    fun stoppedReaderRestoresUnspecifiedAndReappliesSavedLockOnStart() {
        runBlocking { repository.updateReaderOrientationLock(ReaderLockedOrientation.Landscape) }
        val owner = object : LifecycleOwner {
            override val lifecycle = LifecycleRegistry.createUnsafe(this).apply {
                currentState = Lifecycle.State.RESUMED
            }
        }
        mountHost(lifecycleOwner = owner)

        compose.runOnIdle { reading = true }
        compose.waitForIdle()
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE, activity.requestedOrientation)

        // Translucent overlay (ON_PAUSE -> STARTED) keeps the reader pinned.
        compose.runOnIdle { owner.lifecycle.currentState = Lifecycle.State.STARTED }
        compose.waitForIdle()
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE, activity.requestedOrientation)

        // Covered by another screen (ON_STOP -> CREATED) restores free rotation without clearing the setting.
        compose.runOnIdle { owner.lifecycle.currentState = Lifecycle.State.CREATED }
        compose.waitForIdle()
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED, activity.requestedOrientation)
        assertEquals(
            ReaderLockedOrientation.Landscape,
            runBlocking { repository.readerOrientationLock.first() }
        )

        // Returning to the reader re-pins the saved orientation.
        compose.runOnIdle { owner.lifecycle.currentState = Lifecycle.State.RESUMED }
        compose.waitForIdle()
        assertEquals(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE, activity.requestedOrientation)
    }
}
