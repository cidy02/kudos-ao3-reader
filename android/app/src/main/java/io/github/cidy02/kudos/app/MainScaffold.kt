package io.github.cidy02.kudos.app

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.navigation.NavDestination
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.works.DownloadQueueBanner

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

    BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        val useNavigationRail = maxWidth >= 840.dp

        Scaffold(
            topBar = {
                if (!isReader) {
                    TopAppBar(
                        title = { Text(Routes.titleFor(currentRoute)) },
                        navigationIcon = {
                            if (!isTopLevel) {
                                IconButton(onClick = { navController.popBackStack() }) {
                                    Icon(
                                        imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                                        contentDescription = "Back"
                                    )
                                }
                            }
                        },
                        actions = {
                            if (currentRoute != Routes.Search) {
                                IconButton(
                                    onClick = {
                                        navController.navigate(Routes.Search) {
                                            launchSingleTop = true
                                        }
                                    }
                                ) {
                                    Icon(
                                        imageVector = Icons.Filled.Search,
                                        contentDescription = "Search"
                                    )
                                }
                            }
                            IconButton(onClick = onCycleTheme) {
                                Icon(
                                    imageVector = Icons.Outlined.Palette,
                                    contentDescription = "Theme: ${themeMode.label}"
                                )
                            }
                        }
                    )
                }
            },
            bottomBar = {
                if (!isReader && !useNavigationRail) {
                    TopLevelNavigationBar(
                        currentDestination = currentDestination,
                        onNavigate = { route -> navController.navigateTopLevel(route) }
                    )
                }
            }
        ) { innerPadding ->
            // Content + download-queue banner sit inside scaffold padding so the
            // banner stacks just above the bottom nav (Apple ContentView overlay).
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding)
            ) {
                Row(modifier = Modifier.fillMaxSize()) {
                    if (!isReader && useNavigationRail) {
                        TopLevelNavigationRail(
                            currentDestination = currentDestination,
                            onNavigate = { route -> navController.navigateTopLevel(route) }
                        )
                    }
                    AppNavHost(
                        container = container,
                        navController = navController,
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxSize()
                    )
                }
                if (!isReader) {
                    DownloadQueueBanner(
                        queue = container.downloadQueue,
                        modifier = Modifier.align(Alignment.BottomCenter)
                    )
                }
            }
        }
    }
}

@Composable
private fun TopLevelNavigationBar(
    currentDestination: NavDestination?,
    onNavigate: (String) -> Unit
) {
    NavigationBar {
        Routes.topLevelDestinations.forEach { destination ->
            val selected = currentDestination.isRouteSelected(destination.route)
            NavigationBarItem(
                selected = selected,
                onClick = { onNavigate(destination.route) },
                icon = {
                    Icon(
                        imageVector = if (selected) {
                            destination.selectedIcon
                        } else {
                            destination.unselectedIcon
                        },
                        contentDescription = destination.label
                    )
                },
                label = { Text(destination.label) }
            )
        }
    }
}

@Composable
private fun TopLevelNavigationRail(
    currentDestination: NavDestination?,
    onNavigate: (String) -> Unit
) {
    NavigationRail {
        Routes.topLevelDestinations.forEach { destination ->
            val selected = currentDestination.isRouteSelected(destination.route)
            NavigationRailItem(
                selected = selected,
                onClick = { onNavigate(destination.route) },
                icon = {
                    Icon(
                        imageVector = if (selected) {
                            destination.selectedIcon
                        } else {
                            destination.unselectedIcon
                        },
                        contentDescription = destination.label
                    )
                },
                label = { Text(destination.label) }
            )
        }
    }
}

private fun NavDestination?.isRouteSelected(route: String): Boolean {
    return this?.hierarchy?.any { it.route == route } == true
}

private fun NavHostController.navigateTopLevel(route: String) {
    navigate(route) {
        popUpTo(graph.findStartDestination().id) {
            saveState = true
        }
        launchSingleTop = true
        restoreState = true
    }
}
