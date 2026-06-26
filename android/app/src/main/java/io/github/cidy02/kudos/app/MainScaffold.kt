package io.github.cidy02.kudos.app

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import io.github.cidy02.kudos.ui.theme.KudosThemeMode

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScaffold(
    container: KudosAppContainer,
    themeMode: KudosThemeMode,
    onCycleTheme: () -> Unit
) {
    val navController = rememberNavController()
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = backStackEntry?.destination
    val currentRoute = currentDestination?.route
    val isTopLevel = Routes.topLevelDestinations.any { it.route == currentRoute }
    val isReader = currentRoute == Routes.Reader

    Scaffold(
        topBar = {
            if (!isReader) {
                TopAppBar(
                    title = { Text(Routes.titleFor(currentRoute)) },
                    navigationIcon = {
                        if (!isTopLevel) {
                            TextButton(onClick = { navController.popBackStack() }) {
                                Text("Back")
                            }
                        }
                    },
                    actions = {
                        TextButton(onClick = { navController.navigate(Routes.Search) }) {
                            Text("Search")
                        }
                        TextButton(onClick = onCycleTheme) {
                            Text(themeMode.label)
                        }
                    }
                )
            }
        },
        bottomBar = {
            if (!isReader) {
                NavigationBar {
                    Routes.topLevelDestinations.forEach { destination ->
                        val selected = currentDestination?.hierarchy?.any {
                            it.route == destination.route
                        } == true

                        NavigationBarItem(
                            selected = selected,
                            onClick = {
                                navController.navigate(destination.route) {
                                    popUpTo(navController.graph.findStartDestination().id) {
                                        saveState = true
                                    }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            icon = { Text(destination.iconLabel) },
                            label = { Text(destination.label) }
                        )
                    }
                }
            }
        }
    ) { innerPadding ->
        AppNavHost(
            container = container,
            navController = navController,
            modifier = Modifier.padding(innerPadding)
        )
    }
}
