package io.github.cidy02.kudos.account

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import io.github.cidy02.kudos.KudosApplication
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.AO3AuthState
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
@org.robolectric.annotation.Config(sdk = [34])
class AccountScreenCrashTest {

    @get:Rule val composeTestRule = createComposeRule()

    @Test
    fun testAccountScreen() = kotlinx.coroutines.test.runTest {
        val app = ApplicationProvider.getApplicationContext<KudosApplication>()
        val container = app.container
        
        composeTestRule.setContent {
            AccountScreen(
                authRepository = container.authRepository,
                listRepository = container.accountListRepository,
                workRepository = container.workRepository,
                authorRepository = container.authorRepository,
                countsCache = container.accountListCountsCache,
                inboxRepository = container.inboxRepository,
                commentRepository = container.commentRepository,
                onLogin = {},
                onOpenList = {},
                onOpenBackup = {},
                onOpenSettings = {}
            )
        }
        
        // Let it render Overview
        composeTestRule.waitForIdle()
        
        // Switch to Activity
        composeTestRule.onNodeWithText("Activity").performClick()
        composeTestRule.waitForIdle()
        
        // Wait for it to render Activity tab content
        composeTestRule.onNodeWithText("History").assertExists()
    }
}
