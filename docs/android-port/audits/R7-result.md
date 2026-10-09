# R7: Top Chrome Hide/Reveal Audit

## Part 1: Android, as built

1. **What exactly hides and what stays:**
   - **Tab's root screen:** The title text (`AnimatedVisibility` around `Text`) and top-right actions (`HomeToolbarActions` / `LibraryToolbarActions` / Settings button) hide. `app/MainScaffold.kt:306-375`. The tab bar stays put (`showTabBar` ignores scrolling). `app/MainScaffold.kt:156, 444`. The top chrome's fading wash ground (`TopChromeFade`) stays visible while the list is scrolled. `app/MainScaffold.kt:388-394`.
   - **Pushed screen:** The Back button, custom title, and `trailingContent` actions hide. `app/MainScaffold.kt:396-434`. The status bar's wash ground (`TopChromeFade`) stays.

2. **What drives it:**
   - **Scroll signal:** `NestedScrollConnection.onPostScroll` reads `consumed.y` and `available.y` from the compose list. `app/MainScaffold.kt:172-184`.
   - **Threshold and distance:** `fromTop <= 44f` forces it visible. Moving down more than `1f` hides it. Moving up more than `6f` reveals it. `app/ScrollAwayTopChrome.kt:17-21`.
   - **Animation and duration:** `tween<Float>(durationMillis = 220, easing = EaseInOut)`. `app/MainScaffold.kt:98`.
   - **At the top of a list:** `availableYPx > 1f` sets `atTop = true`, forcing `fromTop = 0f` and making it visible. `app/ScrollAwayTopChrome.kt:82, 57, 17`.
   - **At its end:** Handled as a normal delta; pushing past the bottom yields no scroll delta, causing no change.
   - **Short list that does not scroll:** Emits no nested scroll events, so chrome remains visible.
   - **On a fling:** Emits sequential scroll events, feeding into the same delta logic seamlessly.

3. **What brings the chrome back without scrolling:**
   - **A screen taking over the row (`holder`, `reveal`):** `app/MainScaffold.kt:165` (`LaunchedEffect(pushedHolder) { if (pushedHolder != null) activeRoute?.let(chrome::reveal) }`).
   - **A tab change:** `app/MainScaffold.kt:166` (`val chromeHidden = chrome.isHidden(activeRoute)`). The route string changes, looking up a fresh state in the map. `app/ScrollAwayTopChrome.kt:40`.
   - **A dialog, sheet, keyboard, selection mode, search field focus, refresh:** Android lacks explicit programmatic reveals for these outside of relying on the natural `availableYPx > 1f` (at top) scroll behavior when layout shifts or a user pulls to refresh.

4. **Which screens opt out, and how:**
   - Screens opt out by setting `hasSubjectHeader = false` inside `PushedShellChrome` (or `Routes.hasSubjectHeader` returning false). When false, `MainScaffold` renders a static `PushedTopBar` outside the scroll-aware block. `app/MainScaffold.kt:158, 246`.

5. **Accessibility:**
   - **Screen reader and keyboard users:** Hidden chrome is fully removed from the layout tree via `AnimatedVisibility(visible = !chromeHidden)`, making it unreachable. `app/MainScaffold.kt:396`.
   - **Reduce Motion:** Android relies on the OS-level animation scaling to handle the `tween` duration; there is no explicit `ReduceMotion` override inside the scroll logic.

6. **Traps from `DECISIONS.md` (and code comments):**
   - **"2026-10-07 · The shell shows its top row again whenever a different screen takes it over."**
     *Gist:* A screen that replaces another inside one route inherited a hidden row and left the user with no Back or Done button. The shell now forces the row back into view when the holder changes.
   - **"2026-10-05 · The page's own colour stays under the status bar on a scrolled page."**
     *Gist:* With the top buttons scrolled away, text ran under the clock. The wash-coloured ground behind the buttons now shrinks to the status bar's height instead of vanishing entirely.
   - **Comment in `ScrollAwayTopChrome.kt:11`:**
     *Gist:* Direction must use raw delta, not inset-adjusted values. An inset-based reading treats the bar's own hide as a scroll, toggling the bar forever at the bottom of a list.

---

## Part 2: iOS, where it would go

1. **How the tab bar is drawn today:**
   - **By platform:** On iOS, a standard `TabView` with `.tabViewStyle(.sidebarAdaptable)`. On macOS, a `NavigationSplitView` with a `List` sidebar. `App/ContentView.swift:115, 135, 151`.
   - **What hides it:** The reader naturally covers it, sheets cover it natively, and the browser tracks its own `tabBarHidden` state via scroll observation (`Features/Browse/WebBrowser.swift:288`).

2. **How a screen's top row is drawn:**
   - **iPhone/iPad:** System navigation bar (`.navigationTitle`) with large inline titles. `UIComponents/TabDashboardShell.swift:42`. Shrinks automatically on scroll natively.
   - **Mac:** Sidebar and detail view toolbar.
   - **Custom floating row:** `UIComponents/ScrollAwayChrome.swift` provides a custom modifier for scroll-away chrome.

3. **Every list screen that would need to report its scroll position:**
   - `List`: 88
   - `ScrollView`: 38
   - `UIViewRepresentable`: 4
   - `LazyVStack`: 1

4. **iOS 18 features & deployment target:**
   - **Deployment target:** `IPHONEOS_DEPLOYMENT_TARGET = 26.5;` (`AO3_App_OpenSource.xcodeproj/project.pbxproj:599`). This target (iOS 26.5 in the codebase's timeframe) fully allows iOS 18 features.
   - **Which the code already uses:** 
     - `.tabBarMinimizeBehavior(.onScrollDown)` (`App/ContentView.swift:145`)
     - `.toolbarVisibility(..., for: .navigationBar)` (`UIComponents/ScrollAwayChrome.swift:18`)
     - `.onScrollGeometryChange(for: Position.self)` (`UIComponents/ScrollAwayChrome.swift:33`)

5. **The smallest plan:**
   - **Shared state:** `AppRouter` is the natural home for a shared `@Observable` property (e.g., `isChromeHidden`) since it outlives route transitions and can reset its state on `.selection` changes.
   - **Modifier:** Each scrollable view uses the existing `.scrollAwayTopChrome(isHidden: $router.isChromeHidden)` modifier.
   - **Traps applied:** 
     - *Inherited hidden row:* The shared state must be reset (`isChromeHidden = false`) during `NavigationStack` pushes or sheet presentations to prevent missing Back buttons.
     - *Text under clock:* The `HeroWash` or `SubjectScreen` must extend its background to `.ignoresSafeArea(.container, edges: .top)` so text doesn't clash with the status bar.
     - *Inset loop:* `.onScrollGeometryChange` must map purely off `geometry.contentOffset.y` differences, avoiding `contentInsets.top`, which the existing `ScrollAwayChrome.swift` already accounts for.
