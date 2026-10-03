package io.github.cidy02.kudos.app

import androidx.activity.compose.LocalOnBackPressedDispatcherOwner
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.EaseInOut
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import io.github.cidy02.kudos.home.HomeShellChrome
import io.github.cidy02.kudos.home.HomeToolbarActions
import io.github.cidy02.kudos.library.LibraryShellChrome
import io.github.cidy02.kudos.library.LibraryToolbarActions
import io.github.cidy02.kudos.ui.subject.GlassCircleButton
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton
import io.github.cidy02.kudos.ui.subject.withOpacity
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.works.DownloadQueueBanner

private val ShellBarButton = 56.dp
private val ShellBarMargin = 10.dp
private val ShellBarClearance = ShellBarButton + ShellBarMargin
private val ShellTitleReserve = 52.dp
private val ShellGearReserve = 48.dp
private val ChromeMotion = tween<Float>(durationMillis = 220, easing = EaseInOut)
private val ChromeDpMotion = tween<Dp>(durationMillis = 220, easing = EaseInOut)

class ShellOverlayState {
    var hidesTabBar by mutableStateOf(false)
}

val LocalShellOverlayState = staticCompositionLocalOf { ShellOverlayState() }

// Chrome policy: Search is its own shell root, in a circle beside the four tabs.
// Theme cycling stays on Account and Settings. Pushed screens hide the floating bar.

@Composable
fun MainScaffold(
    container: KudosAppContainer,
    themeMode: KudosThemeMode,
    onCycleTheme: () -> Unit
) {
    val navController = rememberNavController()
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = backStackEntry?.destination?.route
    val shell = Routes.isShellRoot(currentRoute)
    val reader = currentRoute == Routes.Reader
    val shellTitle = Routes.shellTitle(currentRoute)
    val chrome = remember { ShellChromeState() }
    val homeChrome = remember { HomeShellChrome() }
    val libraryChrome = remember { LibraryShellChrome() }
    val pushedChrome = remember { PushedShellChrome() }
    val onHome = currentRoute == Routes.Home
    val onLibrary = currentRoute == Routes.Library
    val homeSelecting = onHome && homeChrome.hideTabBar
    val librarySelecting = onLibrary && libraryChrome.hideTabBar
    val overlay = remember { ShellOverlayState() }
    val pushedSelecting = pushedChrome.mounted && pushedChrome.hideTabBar
    val selectionHidesBar = homeSelecting || librarySelecting || overlay.hidesTabBar || pushedSelecting
    val showTabBar = !Routes.hidesTabBar(currentRoute) && !selectionHidesBar

    val hasSubjectHeader = pushedChrome.hasSubjectHeader ?: Routes.hasSubjectHeader(currentRoute)
    val isPushedSubject = !shell && !reader && hasSubjectHeader

    val activeRoute = if (reader) null else currentRoute
    val chromeHidden = chrome.isHidden(activeRoute)
    val bridge = remember { ShellScrollBridge() }
    bridge.route = activeRoute
    bridge.density = LocalDensity.current.density
    val connection = remember(chrome) {
        object : NestedScrollConnection {
            override fun onPostScroll(
                consumed: Offset,
                available: Offset,
                source: NestedScrollSource
            ): Offset {
                // SideEffect scrolls are inset and layout changes, not a finger.
                if (source == NestedScrollSource.SideEffect) return Offset.Zero
                val route = bridge.route ?: return Offset.Zero
                chrome.onNestedScroll(route, consumed.y, available.y, bridge.density)
                return Offset.Zero
            }
        }
    }

    val tokens = LocalKudosTokens.current
    val insets = WindowInsets.systemBars.asPaddingValues()
    val reserveTarget = when {
        shell && shellTitle != null && !chromeHidden -> ShellTitleReserve
        shell && currentRoute == Routes.Account && !chromeHidden -> ShellGearReserve
        else -> 0.dp
    }
    val reserve by animateDpAsState(reserveTarget, ChromeDpMotion, label = "chromeReserve")
    val topPad = when {
        shell -> insets.calculateTopPadding() + reserve
        reader -> insets.calculateTopPadding()
        else -> 0.dp
    }
    val bottomPad = insets.calculateBottomPadding() + if (showTabBar) ShellBarClearance else 0.dp
    val page = if (shell) tokens.background else MaterialTheme.colorScheme.background

    val backDispatcher = LocalOnBackPressedDispatcherOwner.current?.onBackPressedDispatcher
    val performBack: () -> Unit = {
        if (pushedChrome.onBack != null) {
            pushedChrome.onBack?.invoke()
        } else {
            backDispatcher?.onBackPressed() ?: navController.popBackStack()
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(page)
            .nestedScroll(connection)
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            if (!shell && !reader && !hasSubjectHeader) {
                PushedTopBar(
                    title = pushedChrome.customTitle ?: Routes.titleFor(currentRoute),
                    showTheme = currentRoute == Routes.Settings,
                    themeMode = themeMode,
                    onBack = performBack,
                    onCycleTheme = onCycleTheme,
                    trailingActions = pushedChrome.trailingContent
                )
            }
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .padding(top = topPad, bottom = bottomPad)
            ) {
                CompositionLocalProvider(
                    LocalShellOverlayState provides overlay,
                    LocalPushedShellChrome provides pushedChrome
                ) {
                    AppNavHost(
                        container = container,
                        navController = navController,
                        modifier = Modifier.fillMaxSize(),
                        shellChrome = homeChrome,
                        libraryChrome = libraryChrome
                    )
                }
            }
        }

        if (shell && shellTitle != null) {
            val titleText = when {
                onHome -> homeChrome.selectionTitle ?: shellTitle
                onLibrary -> libraryChrome.selectionTitle ?: shellTitle
                else -> shellTitle
            }
            val titleEnd = when {
                onHome && homeSelecting -> 200.dp
                onHome -> 96.dp
                onLibrary && librarySelecting -> 160.dp
                onLibrary -> 144.dp
                else -> 0.dp
            }
            AnimatedVisibility(
                visible = !chromeHidden,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .windowInsetsPadding(WindowInsets.systemBars.only(WindowInsetsSides.Top))
                    .padding(start = 20.dp, top = 4.dp, end = 20.dp),
                enter = fadeIn(ChromeMotion),
                exit = fadeOut(ChromeMotion)
            ) {
                Text(
                    text = titleText,
                    modifier = Modifier.padding(end = titleEnd),
                    color = tokens.primaryInk,
                    fontSize = 34.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }

        if (onHome && homeChrome.mounted) {
            AnimatedVisibility(
                visible = !chromeHidden,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .windowInsetsPadding(WindowInsets.systemBars.only(WindowInsetsSides.Top))
                    .padding(top = 6.dp, end = 8.dp),
                enter = fadeIn(ChromeMotion),
                exit = fadeOut(ChromeMotion)
            ) {
                HomeToolbarActions(homeChrome)
            }
        }

        if (onLibrary && libraryChrome.mounted) {
            AnimatedVisibility(
                visible = !chromeHidden,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .windowInsetsPadding(WindowInsets.systemBars.only(WindowInsetsSides.Top))
                    .padding(top = 6.dp, end = 8.dp),
                enter = fadeIn(ChromeMotion),
                exit = fadeOut(ChromeMotion)
            ) {
                LibraryToolbarActions(libraryChrome)
            }
        }

        if (shell && currentRoute == Routes.Account) {
            AnimatedVisibility(
                visible = !chromeHidden,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .windowInsetsPadding(WindowInsets.systemBars.only(WindowInsetsSides.Top))
                    .padding(top = 6.dp, end = 8.dp),
                enter = fadeIn(ChromeMotion),
                exit = fadeOut(ChromeMotion)
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    ToolbarCircleButton(
                        onClick = onCycleTheme,
                        accessibilityName = "Theme: ${themeMode.label}"
                    ) {
                        Icon(Icons.Outlined.Palette, contentDescription = null)
                    }
                    ToolbarCircleButton(
                        onClick = {
                            navController.navigate(Routes.Settings) { launchSingleTop = true }
                        },
                        accessibilityName = "Settings"
                    ) {
                        Icon(Icons.Outlined.Settings, contentDescription = null)
                    }
                }
            }
        }

        if (isPushedSubject) {
            AnimatedVisibility(
                visible = !chromeHidden,
                modifier = Modifier
                    .fillMaxWidth()
                    .align(Alignment.TopCenter)
                    .windowInsetsPadding(WindowInsets.systemBars.only(WindowInsetsSides.Top))
                    .padding(start = 8.dp, end = 8.dp, top = 6.dp),
                enter = fadeIn(ChromeMotion),
                exit = fadeOut(ChromeMotion)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    ToolbarCircleButton(
                        onClick = performBack,
                        accessibilityName = "Back"
                    ) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                    if (pushedChrome.customTitle != null) {
                        Text(
                            text = pushedChrome.customTitle.orEmpty(),
                            color = tokens.primaryInk,
                            fontSize = 17.sp,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.padding(start = 12.dp)
                        )
                    }
                    Spacer(modifier = Modifier.weight(1f))
                    if (pushedChrome.trailingContent != null) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            pushedChrome.trailingContent?.invoke(this)
                        }
                    }
                }
            }
        }

        DownloadQueueBanner(
            queue = container.downloadQueue,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = bottomPad)
        )

        if (showTabBar) {
            FloatingTabBar(
                currentRoute = currentRoute,
                minimized = chromeHidden,
                onNavigate = { route -> navController.navigateShellRoot(route) },
                modifier = Modifier.align(Alignment.BottomCenter)
            )
        }
    }
}

@Composable
private fun PushedTopBar(
    title: String,
    showTheme: Boolean,
    themeMode: KudosThemeMode,
    onBack: () -> Unit,
    onCycleTheme: () -> Unit,
    trailingActions: (@Composable RowScope.() -> Unit)? = null
) {
    val tokens = LocalKudosTokens.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .windowInsetsPadding(WindowInsets.systemBars.only(WindowInsetsSides.Top))
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            ToolbarCircleButton(onClick = onBack, accessibilityName = "Back") {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
            }
            Text(
                text = title,
                modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = 12.dp),
                color = tokens.primaryInk,
                fontSize = 20.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            if (showTheme) {
                ToolbarCircleButton(
                    onClick = onCycleTheme,
                    accessibilityName = "Theme: ${themeMode.label}"
                ) {
                    Icon(Icons.Outlined.Palette, contentDescription = null)
                }
            }
            if (trailingActions != null) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    trailingActions()
                }
            }
        }
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(0.5.dp)
                .background(tokens.separator)
        )
    }
}

@Composable
private fun FloatingTabBar(
    currentRoute: String?,
    minimized: Boolean,
    onNavigate: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    val searchSelected = currentRoute == Routes.Search
    val selectedTab = Routes.topLevelDestinations.firstOrNull { destination ->
        currentRoute == destination.route
    }
    Row(
        modifier = modifier
            .fillMaxWidth()
            .windowInsetsPadding(WindowInsets.systemBars.only(WindowInsetsSides.Bottom))
            .padding(start = 12.dp, end = 12.dp, bottom = ShellBarMargin),
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (!minimized) {
            TabCapsule(
                currentRoute = currentRoute,
                onNavigate = onNavigate,
                modifier = Modifier.weight(1f)
            )
        } else if (selectedTab != null) {
            ShellGlassCircle(
                onClick = { onNavigate(selectedTab.route) },
                name = selectedTab.label,
                selected = true,
                icon = selectedTab.selectedIcon,
                diameter = 44.dp
            )
        }
        ShellGlassCircle(
            onClick = { onNavigate(Routes.Search) },
            name = "Search",
            selected = searchSelected,
            icon = Icons.Filled.Search,
            diameter = ShellBarButton
        )
    }
}

@Composable
private fun TabCapsule(
    currentRoute: String?,
    onNavigate: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val shape = RoundedCornerShape(percent = 50)
    Row(
        modifier = modifier
            .height(ShellBarButton)
            .clip(shape)
            .background(tokens.glassFill(), shape)
            .border(0.5.dp, tokens.glassStroke(), shape)
            .padding(4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Routes.topLevelDestinations.forEach { destination ->
            val selected = currentRoute == destination.route
            val tint = if (selected) tokens.accent else tokens.primaryInk
            Column(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .clip(shape)
                    .background(if (selected) tokens.accent.withOpacity(0.18) else Color.Transparent)
                    .clickable(role = Role.Tab, onClick = { onNavigate(destination.route) })
                    .semantics(mergeDescendants = true) { this.selected = selected },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Icon(
                    imageVector = if (selected) destination.selectedIcon else destination.unselectedIcon,
                    contentDescription = null,
                    tint = tint,
                    modifier = Modifier.size(20.dp)
                )
                Text(
                    text = destination.label,
                    color = if (selected) tokens.accent else tokens.secondaryInk,
                    fontSize = 11.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

@Composable
private fun ShellGlassCircle(
    onClick: () -> Unit,
    name: String,
    selected: Boolean,
    icon: ImageVector,
    diameter: Dp,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val fill = if (selected) tokens.accent.withOpacity(0.30) else tokens.glassFill()
    val stroke = if (selected) tokens.accent.withOpacity(0.60) else tokens.glassStroke()
    Box(
        modifier
            .size(diameter)
            .semantics {
                role = Role.Button
                this.selected = selected
                contentDescription = name
            }
            .clip(CircleShape)
            .background(fill, CircleShape)
            .border(0.5.dp, stroke, CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = if (selected) tokens.accent else tokens.primaryInk,
            modifier = Modifier.size(if (diameter < 50.dp) 20.dp else 24.dp)
        )
    }
}

private class ShellScrollBridge {
    var route: String? = null
    var density: Float = 1f
}

private fun NavHostController.navigateShellRoot(route: String) {
    navigate(route) {
        popUpTo(graph.findStartDestination().id) {
            saveState = true
        }
        launchSingleTop = true
        restoreState = true
    }
}
