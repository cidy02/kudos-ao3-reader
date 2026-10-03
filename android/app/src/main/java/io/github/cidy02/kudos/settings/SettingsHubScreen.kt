package io.github.cidy02.kudos.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.AO3AuthState
import io.github.cidy02.kudos.core.model.AppThemeSetting
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.LocalSubjectPalette
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import io.github.cidy02.kudos.BuildConfig

@Composable
fun SettingsHubScreen(
    navController: NavController,
    settings: KudosSettings,
    authRepository: AO3AuthRepository?
) {
    val chrome = LocalPushedShellChrome.current
    LaunchedEffect(Unit) {
        chrome.customTitle = null
        chrome.hasSubjectHeader = true
    }

    val palette = LocalSubjectPalette.current
    val authState by (authRepository?.state ?: kotlinx.coroutines.flow.flowOf(AO3AuthState.SignedOut)).collectAsState(initial = AO3AuthState.SignedOut)

    val fontName = "System" // We don't have direct access to font name string without repo, but it's ok for hub
    val themeMatched = settings.reader.matchAppReaderTheme
    val appTheme = settings.app.appTheme.name
    val readerTheme = settings.reader.readerTheme.storageValue.replaceFirstChar { it.uppercase() }
    val themeString = if (themeMatched) appTheme else "$appTheme, $readerTheme reader"
    
    val readingMode = settings.reader.readerMode.name
    
    val keepWorks = settings.app.keepsWorksYouRead
    val downloadsString = if (keepWorks) "Keep what you read" else "Manual"
    
    val accountString = when (authState) {
        is AO3AuthState.SignedIn -> (authState as AO3AuthState.SignedIn).username
        AO3AuthState.Restoring -> "Checking…"
        else -> "Not signed in"
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .subjectScreenWash(palette),
        contentPadding = PaddingValues(bottom = 20.dp)
    ) {
        item {
            SubjectHeaderBlock(
                kicker = "",
                title = "Settings",
                subtitle = null,
                palette = palette,
                gutter = SubjectMetrics.accountGutter,
                modifier = Modifier.padding(top = 20.dp)
            )
        }

        item {
            Column(modifier = Modifier.padding(top = 22.dp)) {
                SectionRuleHeader("Reading")
                Column(
                    modifier = Modifier
                        .padding(top = 10.dp)
                        .padding(horizontal = SubjectMetrics.accountGutter)
                        .subjectPanel()
                ) {
                    SubjectFormRow("Appearance", value = themeString, showsDisclosure = true, onClick = { navController.navigate("appearance") })
                    SubjectRowSeparator()
                    SubjectFormRow("Font", value = fontName, showsDisclosure = true, onClick = { navController.navigate("font") })
                    SubjectRowSeparator()
                    SubjectFormRow("Reader", value = readingMode, showsDisclosure = true, onClick = { navController.navigate("reader") })
                }
            }
        }

        item {
            Column(modifier = Modifier.padding(top = 22.dp)) {
                SectionRuleHeader("Downloads & Storage")
                Column(
                    modifier = Modifier
                        .padding(top = 10.dp)
                        .padding(horizontal = SubjectMetrics.accountGutter)
                        .subjectPanel()
                ) {
                    SubjectFormRow("Downloads", value = downloadsString, showsDisclosure = true, onClick = { navController.navigate("downloads") })
                    SubjectRowSeparator()
                    SubjectFormRow("Reading Queues", value = "Ask first", showsDisclosure = true, onClick = { navController.navigate("reading_queues") })
                }
            }
        }

        item {
            Column(modifier = Modifier.padding(top = 22.dp)) {
                SectionRuleHeader("Library & Sync")
                Column(
                    modifier = Modifier
                        .padding(top = 10.dp)
                        .padding(horizontal = SubjectMetrics.accountGutter)
                        .subjectPanel()
                ) {
                    SubjectFormRow("Library", showsDisclosure = true, onClick = { navController.navigate("library") })
                    SubjectRowSeparator()
                    SubjectFormRow("Folder Sync", value = if (settings.sync.isEnabled) "On" else "Off", showsDisclosure = true, onClick = { navController.navigate("folder_sync") })
                    SubjectRowSeparator()
                    SubjectFormRow("Backup", showsDisclosure = true, onClick = { navController.navigate("backup") })
                }
            }
        }

        item {
            Column(modifier = Modifier.padding(top = 22.dp)) {
                SectionRuleHeader("Account & Privacy")
                Column(
                    modifier = Modifier
                        .padding(top = 10.dp)
                        .padding(horizontal = SubjectMetrics.accountGutter)
                        .subjectPanel()
                ) {
                    SubjectFormRow("AO3 Account", value = accountString, showsDisclosure = true, onClick = { navController.navigate("account") })
                    SubjectRowSeparator()
                    SubjectFormRow("Privacy", value = "Off", showsDisclosure = true, onClick = { navController.navigate("privacy_settings") })
                }
            }
        }

        item {
            Column(modifier = Modifier.padding(top = 22.dp)) {
                SectionRuleHeader("About")
                Column(
                    modifier = Modifier
                        .padding(top = 10.dp)
                        .padding(horizontal = SubjectMetrics.accountGutter)
                        .subjectPanel()
                ) {
                    SubjectFormRow("About", value = BuildConfig.VERSION_NAME, showsDisclosure = true, onClick = { navController.navigate("about") })
                }
            }
        }
    }
}
