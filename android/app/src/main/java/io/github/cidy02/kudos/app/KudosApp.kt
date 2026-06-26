package io.github.cidy02.kudos.app

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode

@Composable
fun KudosApp(container: KudosAppContainer) {
    var themeMode by remember { mutableStateOf(KudosThemeMode.System) }

    KudosTheme(themeMode = themeMode) {
        MainScaffold(
            container = container,
            themeMode = themeMode,
            onCycleTheme = { themeMode = themeMode.next() }
        )
    }
}
