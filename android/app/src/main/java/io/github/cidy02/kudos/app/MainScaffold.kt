package io.github.cidy02.kudos.app

import androidx.compose.material3.ShortNavigationBar
import androidx.compose.material3.ShortNavigationBarItem
import androidx.compose.material3.ShortNavigationBarItemDefaults
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.layout.onSizeChanged
import io.github.cidy02.kudos.ui.subject.AccentContainerOpacity
import io.github.cidy02.kudos.ui.subject.LocalShellWashes
import io.github.cidy02.kudos.ui.subject.subjectWash
import androidx.compose.runtime.collectAsState
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import androidx.activity.compose.LocalOnBackPressedDispatcherOwner
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.EaseInOut
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.windowInsetsPadding
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Density
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
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton
import io.github.cidy02.kudos.search.LocalTagSearch
import io.github.cidy02.kudos.search.SearchTagRequests
import io.github.cidy02.kudos.ui.subject.withOpacity
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.works.DownloadQueueBanner

/** Material's short navigation bar, until it has been measured. */
private val ShellBarHeight = 64.dp
/** The top chrome row: 6dp, a 48dp icon button, 6dp. */
private val TopChromeHeight = 60.dp
private val TopChromeFadeEdge = 16.dp
private val ShellTitleReserve = 56.dp
private val ShellGearReserve = 54.dp
private val ChromeMotion = tween<Float>(durationMillis = 220, easing = EaseInOut)
private val ChromeDpMotion = tween<Dp>(durationMillis = 220, easing = EaseInOut)

class ShellOverlayState {
    var hidesTabBar by mutableStateOf(false)
}

val LocalShellOverlayState = staticCompositionLocalOf { ShellOverlayState() }

/**
 * Search's Back, once filter history and the results screen are exhausted.
 * The shell returns to the last non-Search tab.
 */
val LocalSearchExit = staticCompositionLocalOf<(() -> Unit)?> { null }

// Chrome policy: Search is its own shell root, the fifth destination in the navigation bar.
// Theme cycling stays on Account and Settings. Pushed screens hide the navigation bar.

@Composable
fun MainScaffold(
    container: KudosAppContainer,
    themeMode: KudosThemeMode,
    onCycleTheme: () -> Unit,
    startRoute: String? = null,
    /** Raised by one each time something above the shell asks for the Library tab. */
    showLibraryRequest: Int = 0
) {
    val navController = rememberNavController()
    androidx.compose.runtime.LaunchedEffect(showLibraryRequest) {
        if (showLibraryRequest > 0) navController.navigateShellRoot(Routes.Library)
    }
    // Debug launch extra `kudosDebugRoute nav:<route>` opens a screen directly (like iOS -KudosDebugRoute).
    androidx.compose.runtime.LaunchedEffect(startRoute) {
        startRoute?.let { navController.navigate(it) }
    }
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
    var searchReturnTab by remember { mutableStateOf(Routes.Home) }
    // The destination a pushed page was opened from stays marked in the navigation bar.
    var lastRoot by remember { mutableStateOf(Routes.Home) }
    SideEffect {
        if (Routes.isTopLevel(currentRoute)) searchReturnTab = currentRoute ?: Routes.Home
        if (Routes.isShellRoot(currentRoute)) lastRoot = currentRoute ?: Routes.Home
    }
    val pushedSelecting = pushedChrome.mounted && pushedChrome.hideTabBar
    val selectionHidesBar = homeSelecting || librarySelecting || overlay.hidesTabBar || pushedSelecting
    val showTabBar = !Routes.hidesTabBar(currentRoute) && !selectionHidesBar

    val hasSubjectHeader = pushedChrome.hasSubjectHeader ?: Routes.hasSubjectHeader(currentRoute)
    val isPushedSubject = !shell && !reader && hasSubjectHeader

    val activeRoute = if (reader) null else currentRoute
    // A screen that takes over inside one route (an editor opened from a scrolled form) must start
    // with its buttons showing: the row its predecessor scrolled away otherwise stayed away.
    val pushedHolder = pushedChrome.holder
    LaunchedEffect(pushedHolder) { if (pushedHolder != null) activeRoute?.let(chrome::reveal) }
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
    // The reader is not padded: it owns the whole window and keeps clear of the bars itself, so
    // its page colour, not the app's, is what shows behind them (iOS's reader is full bleed).
    val topPad = when {
        shell -> insets.calculateTopPadding() + reserve
        else -> 0.dp
    }
    // The bar is measured (its labels grow with the text size); it includes the system inset.
    val density = LocalDensity.current
    var barHeight by remember { mutableStateOf(0.dp) }
    val bottomPad = when {
        reader -> 0.dp
        !showTabBar -> insets.calculateBottomPadding()
        barHeight > 0.dp -> barHeight
        else -> insets.calculateBottomPadding() + ShellBarHeight
    }
    val page = if (shell) tokens.background else MaterialTheme.colorScheme.background

    val backDispatcher = LocalOnBackPressedDispatcherOwner.current?.onBackPressedDispatcher
    val performBack: () -> Unit = {
        if (pushedChrome.onBack != null) {
            pushedChrome.onBack?.invoke()
        } else {
            backDispatcher?.onBackPressed() ?: navController.popBackStack()
        }
    }

    // Home and Library wash in their hero's colour (owner, 2026-10-03; iOS does the same).
    // Account washes in the app accent while signed in (iOS AccountView, artboard 1m vs 1n).
    val washHue = when {
        onHome -> homeChrome.washHue
        onLibrary -> libraryChrome.washHue
        else -> null
    }
    val authState by container.authRepository.state.collectAsState()
    val scopePalette = io.github.cidy02.kudos.ui.subject.LocalSubjectPalette.current
    val heroPalette = washHue?.let { io.github.cidy02.kudos.ui.subject.SubjectPalette.fromHue(it, tokens.theme) }
    val washModifier = when {
        heroPalette != null ->
            Modifier.subjectScreenWash(heroPalette)
        currentRoute == Routes.Account && authState is io.github.cidy02.kudos.auth.AO3AuthState.SignedIn ->
            Modifier.subjectScreenWash(scopePalette)
        else -> Modifier
    }
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(page)
            .then(washModifier)
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
                // Under a hero wash the page's controls take the hero's colour too, as iOS's
                // `heroWash` does through `screenTint` (owner, 2026-10-03). The shell's own
                // chrome and tab bar sit outside this and keep the app accent, as on iOS.
                val scheme = MaterialTheme.colorScheme
                CompositionLocalProvider(
                    LocalShellOverlayState provides overlay,
                    LocalPushedShellChrome provides pushedChrome,
                    LocalSearchExit provides { navController.navigateShellRoot(searchReturnTab) },
                    LocalTagSearch provides { field, value ->
                        SearchTagRequests.request(
                            field = field,
                            value = value,
                            isFreshTabJump = currentRoute != Routes.Search
                        )
                        navController.navigateShellRoot(Routes.Search)
                    },
                    LocalKudosTokens provides (heroPalette?.let { tokens.copy(accent = it.tint) } ?: tokens),
                    io.github.cidy02.kudos.ui.subject.LocalSubjectPalette provides (heroPalette ?: scopePalette)
                ) {
                    MaterialTheme(colorScheme = heroPalette?.let { scheme.copy(primary = it.tint) } ?: scheme) {
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
        }

        if (shell && shellTitle != null) {
            val titleText = when {
                onHome -> homeChrome.selectionTitle ?: shellTitle
                onLibrary -> libraryChrome.selectionTitle ?: shellTitle
                else -> shellTitle
            }
            val titleEnd = when {
                onHome && homeSelecting -> 200.dp
                onHome -> 108.dp
                onLibrary && librarySelecting -> 160.dp
                onLibrary -> 160.dp
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
                ToolbarCircleButton(
                    onClick = {
                        navController.navigate(Routes.Settings) { launchSingleTop = true }
                    },
                    accessibilityName = "Settings",
                    isAccented = true
                ) {
                    Icon(Icons.Outlined.Settings, contentDescription = null)
                }
            }
        }

        if (isPushedSubject) {
            // Plain icon buttons cannot be read with a list running under them. While one does,
            // the top of the screen is painted again in the page's own wash. With the buttons
            // scrolled away the same ground stays under the status bar alone, so the clock is
            // never drawn over a line of text.
            val fadeHeight by animateDpAsState(
                insets.calculateTopPadding() + if (chromeHidden) 0.dp else TopChromeHeight,
                ChromeDpMotion,
                label = "topChromeFade"
            )
            AnimatedVisibility(
                visible = chrome.isScrolled(activeRoute),
                modifier = Modifier.align(Alignment.TopCenter),
                enter = fadeIn(ChromeMotion),
                exit = fadeOut(ChromeMotion)
            ) {
                TopChromeFade(fadeHeight)
            }
            AnimatedVisibility(
                visible = !chromeHidden,
                modifier = Modifier
                    .fillMaxWidth()
                    .align(Alignment.TopCenter)
                    .windowInsetsPadding(WindowInsets.systemBars.only(WindowInsetsSides.Top))
                    .padding(start = 4.dp, end = 4.dp, top = 6.dp),
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
            ShellNavigationBar(
                currentRoute = if (shell) currentRoute else lastRoot,
                onNavigate = { route -> navController.navigateShellRoot(route) },
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .onSizeChanged { barHeight = with(density) { it.height.toDp() } }
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
                .padding(horizontal = 4.dp, vertical = 6.dp),
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

/**
 * The tab bar, drawn the Android way: Material 3's navigation bar across the bottom edge, where
 * iOS floats a glass capsule with a Search circle beside it (owner, 2026-10-04: one product on
 * both platforms, but Android is not to look like a copy of iOS). Search is the fifth
 * destination; it is a shell root on both. The bar stays put when a list scrolls.
 */
@Composable
private fun ShellNavigationBar(
    currentRoute: String?,
    onNavigate: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    // The selected tab is an accent-tinted pill under a glyph that reads on it in every theme
    // (the bare accent, AO3 red by default, does not on Dark: owner question 2).
    val onAccent = io.github.cidy02.kudos.ui.subject.LocalSubjectPalette.current.accentOnFill
    val colors = ShortNavigationBarItemDefaults.colors(
        selectedIconColor = onAccent,
        selectedTextColor = onAccent,
        selectedIndicatorColor = tokens.accent.withOpacity(AccentContainerOpacity),
        unselectedIconColor = tokens.secondaryInk,
        unselectedTextColor = tokens.secondaryInk
    )
    // Five labels do not fit across a phone at the largest text sizes: they stop growing at 1.3x.
    val density = LocalDensity.current
    CompositionLocalProvider(
        LocalDensity provides Density(density.density, minOf(density.fontScale, 1.3f))
    ) {
    ShortNavigationBar(
        modifier = modifier,
        // Material's "surface container": the page colour, one step raised.
        containerColor = tokens.glassFill(0.08).compositeOver(tokens.background),
        contentColor = tokens.primaryInk
    ) {
        Routes.topLevelDestinations.forEach { destination ->
            val selected = currentRoute == destination.route
            ShortNavigationBarItem(
                selected = selected,
                onClick = { onNavigate(destination.route) },
                icon = {
                    Icon(
                        imageVector = if (selected) destination.selectedIcon else destination.unselectedIcon,
                        contentDescription = null
                    )
                },
                label = { Text(destination.label, maxLines = 1) },
                colors = colors
            )
        }
        ShortNavigationBarItem(
            selected = currentRoute == Routes.Search,
            onClick = { onNavigate(Routes.Search) },
            icon = { Icon(Icons.Filled.Search, contentDescription = null) },
            label = { Text("Search", maxLines = 1) },
            colors = colors
        )
    }
    }
}

/**
 * The top [height] of the screen painted again in the page's own wash, fading out over a last
 * 16dp: Material's top bar that turns solid when a list runs under it, in the page's colour.
 */
@Composable
private fun TopChromeFade(height: Dp) {
    val tokens = LocalKudosTokens.current
    val wash = LocalShellWashes.current.page
    Box(
        Modifier
            .fillMaxWidth()
            .height(height + TopChromeFadeEdge)
            .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
            .drawWithContent {
                drawContent()
                val solid = 1f - TopChromeFadeEdge.toPx() / size.height
                drawRect(
                    Brush.verticalGradient(0f to Color.Black, solid to Color.Black, 1f to Color.Transparent),
                    blendMode = BlendMode.DstIn
                )
            }
            .clipToBounds()
            .then(wash?.let { Modifier.subjectWash(it.palette, it.height) } ?: Modifier.background(tokens.background))
    )
}

private class ShellScrollBridge {
    var route: String? = null
    var density: Float = 1f
}

internal fun NavHostController.navigateShellRoot(route: String) {
    navigate(route) {
        popUpTo(graph.findStartDestination().id) {
            saveState = true
        }
        launchSingleTop = true
        restoreState = true
    }
}
