# Kudos — Android Material Design Translation of Apple HIG Principles

This document translates the existing Kudos Apple HIG guidance into Android and Material Design 3 terms using official Apple Human Interface Guidelines, official Material Design 3 guidance, and Android Developers Jetpack Compose guidance.

The purpose is not to make Android imitate iOS. The purpose is to preserve the Apple app’s product intent — clarity, hierarchy, progressive disclosure, readable density, privacy, and native platform feel — while expressing that intent through Material Design 3 and Android platform conventions.

---

## Official Source Context

This translation uses the following official guidance as design context:

### Apple Human Interface Guidelines

Apple’s Human Interface Guidelines describe best practices for creating high-quality experiences on Apple platforms. For Kudos, the relevant ideas are:

- Design should feel native to the platform.
- Navigation should be clear and consistent.
- Top-level navigation should be reserved for top-level destinations, not ordinary actions.
- Layout should respect safe areas and readable content boundaries.
- Modality should be used for focused tasks that temporarily require a separate mode.
- Sheets are appropriate for simple tasks that people complete before returning to the parent view.
- Accessibility should prioritize simple, intuitive actions and familiar system behaviors.

### Material Design 3 and Android Developers

Material Design 3 is Google’s current design system for building Android interfaces. For Kudos, the relevant ideas are:

- Material components should express hierarchy, state, and brand.
- Color roles should maintain accessible pairings between surface and content.
- Cards should group content and actions about a single subject.
- Top app bars should display screen identity, navigation, and screen actions.
- Navigation bars are appropriate for three to five equal top-level destinations on compact screens.
- Navigation rails are appropriate for top-level destinations on larger screens.
- Adaptive navigation should switch between navigation bar and navigation rail depending on window size.
- Android Compose apps should support adaptive layouts, list-detail patterns, and different screen sizes.
- Material spacing, surfaces, typography, and components should make structure clearer rather than add decoration.

---

## Core Translation Rule

```text
Apple HIG goal:
Simple, familiar, clear, native Apple UI.

Android Material 3 goal:
Simple, familiar, clear, native Android UI.
```

The translation rule for Kudos is:

```text
Preserve the Apple app’s behavior, hierarchy, and product intent.
Express it through Material Design 3 and Android platform conventions.
```

Kudos Android should feel like the same product, not the same toolkit.

---

## 1. Platform Nativeness

### Apple-side intent

The Apple app follows HIG to feel like a first-class Apple app.

### Android translation

The Android app must feel like a first-class Android app.

Use:

- Jetpack Compose
- Material Design 3
- Android system back behavior
- Android edge-to-edge and window-inset handling
- Material navigation components
- Material cards, chips, sheets, dialogs, and app bars
- Android accessibility conventions
- Android document picker/share sheet/biometric patterns

Avoid copying:

- SwiftUI navigation chrome
- Apple tab/sidebar visuals
- SF Symbols as-is
- iOS sheets as literal visual copies
- iOS toolbar spacing
- iOS/macOS visual effects
- Apple-specific layout assumptions

### Kudos rule

The Apple app is the reference for behavior and information hierarchy. Material 3 is the reference for Android expression.

---

## 2. Layout and Visual Hierarchy

### Apple-side intent

Apple HIG emphasizes clear layout, readable content, consistent hierarchy, and safe-area-aware design.

### Material 3 translation

Use Android layout structure intentionally:

- `Scaffold` for screen structure
- `TopAppBar` / `LargeTopAppBar` for screen title and actions
- `LazyColumn` for vertical content
- `LazyRow` for shelves and horizontal overviews
- `NavigationBar` for compact phones
- `NavigationRail` for larger screens
- adaptive layouts for tablets/foldables
- Material surfaces/cards for grouped content
- typography roles for hierarchy
- consistent spacing between sections
- clear content padding that respects system bars and touch comfort

### Kudos rule

Every screen should have a clear primary purpose:

- Home: return to reading
- Library: manage saved/offline works
- Browse: explore AO3 structure natively
- Search: directly find works
- Account: AO3 session and account lists
- Reader: read without distraction

---

## 3. Navigation

### Apple-side intent

Apple tab bars are for top-level app sections, not ordinary actions. Navigation should help people understand where they are and move predictably.

### Material 3 translation

Use Android top-level navigation correctly:

Phone:

```text
NavigationBar:
- Home
- Library
- Browse
- Account
```

Larger screens:

```text
NavigationRail or adaptive navigation suite:
- Home
- Library
- Browse
- Account
```

Global Search:

```text
Search is a global action, not a fifth peer tab.
```

Search may be:

- a top app bar action
- a prominent FAB/docked search action
- a dedicated Search destination launched from anywhere

### Kudos rule

Do not bury Search, but do not make it visually compete with the four core destinations.

```text
Home = current reading life
Library = local saved/offline works
Browse = AO3 exploration
Account = AO3 account state
Search = global action for direct finding
```

---

## 4. Adaptive Navigation

### Apple-side intent

The Apple app can use tab bars, sidebars, and split views depending on platform.

### Android translation

Use Material adaptive navigation:

- compact width: bottom `NavigationBar`
- medium/expanded width: `NavigationRail`
- tablet/foldable: list-detail or supporting-pane layouts where useful
- preserve the same destination model across size classes

### Kudos rule

On phone, keep bottom navigation.

On tablet/foldable, use navigation rail and consider:

- Library list + Work Detail
- Search results + Work Detail
- Browse category + fandom list
- Account list + selected account section

Do not stretch phone UI awkwardly across large screens.

---

## 5. Progressive Disclosure

### Apple-side intent

The Apple HIG-derived plan uses simple defaults and reveals complexity only when needed.

### Material 3 translation

Use:

- section headers with trailing chevrons
- card tap → detail
- overflow menu → secondary item actions
- `ModalBottomSheet` → filters, sorting, reader settings, secondary controls
- `AlertDialog` → destructive confirmation or blocking decisions
- full screen → deep tasks or full lists
- chips → visible active filters and quick refinements

### Kudos rule

Default screens should be simple. Advanced capabilities should be nearby but not overwhelming.

Examples:

- Home shows shelves; chevrons open full lists.
- Library shows search/sort/filter; advanced filters live in a bottom sheet.
- Reader shows text first; settings appear only when requested.
- Work Detail shows primary actions first; secondary actions are grouped.

---

## 6. Modality and Sheets

### Apple-side intent

Apple modality presents a separate focused mode and sheets are useful for small tasks before returning to the parent view.

### Material 3 translation

On Android:

- use `ModalBottomSheet` for temporary, contextual controls
- use full-screen destinations for deep flows
- use `AlertDialog` for confirmation
- avoid stacking too many modals
- preserve Android back behavior

### Kudos rule

Good uses of sheets:

- Search filters
- Library filters
- Sort options
- Reader typography/settings
- Add to user tags
- Add to collection
- Small backup/import choices

Avoid using sheets for:

- full Work Detail
- full Reader
- complex account flows
- login screens that need WebView context

---

## 7. Cards and Content Surfaces

### Apple-side intent

The Apple plan uses cards/collections for glanceable content and lists for detailed browsing.

### Material 3 translation

Material cards are for content and actions about one subject. Use card families intentionally:

- compact work cards for search/library/account lists
- visual work cards for Home shelves
- category cards for Browse
- grouped list cards for Account and Settings
- status cards for empty/error/loading states

### Kudos rule

A work card is not a generic card. It must carry AO3 meaning.

A good Material 3 work card should include enough of:

1. title
2. author
3. fandom
4. rating
5. warnings/categories
6. relationships/characters/freeforms
7. summary snippet or reading progress
8. words / chapters / kudos / comments / hits
9. saved/downloaded/favorite/finished indicators

Design target:

```text
dense, not cramped
clean, not sparse
Material-native, not generic
```

---

## 8. Lists, Shelves, and Detail Screens

### Apple-side intent

The Apple HIG translation uses horizontal collections for overviews and vertical lists for deeper browsing.

### Material 3 translation

Use:

- `LazyRow` for Home shelves and glanceable horizontal groups
- `LazyColumn` for full lists and text-heavy browsing
- `LazyVerticalGrid` only where visual scanning is actually useful
- canonical detail destinations for Work Detail
- list-detail adaptive layouts on larger screens

### Kudos rule

Use horizontal shelves for:

- Continue Reading
- Subscriptions
- Recently Updated
- Favorites
- Recently Opened
- Recently Added

Use vertical lists for:

- full Library
- Search results
- Account lists
- History
- Bookmarks
- Marked for Later
- Subscriptions
- fandom/tag work results
- download queue

---

## 9. Color, Brand, and Dark Theme

### Apple-side intent

The Apple design uses brand identity and readable visual hierarchy without sacrificing accessibility.

### Material 3 translation

Use Material color roles to communicate:

- hierarchy
- state
- interaction
- brand

For Kudos:

- AO3 red is the primary accent
- dark surfaces should be comfortable, not debug-black everywhere
- sepia should feel like a reading mode
- success/warning/error states should not rely on color alone
- text contrast must remain readable
- accent should guide attention, not overwhelm content

### Kudos rule

Do not paint the whole app AO3 red. Use red for:

- active navigation
- primary action emphasis
- AO3 identity accents
- important icons
- selected chips
- FAB/search action

Use neutral dark surfaces for reading calm.

---

## 10. Typography

### Apple-side intent

The Apple plan values readability, hierarchy, and Dynamic Type.

### Material 3 translation

Use Material typography roles:

- screen titles: display/headline roles
- section headers: title roles
- work titles: title/label hierarchy
- metadata: body/label roles
- helper text: body small/label small
- reader text: reader-specific typography settings, not generic app body text

### Kudos rule

Do not use arbitrary font sizes everywhere.

Do not make metadata unreadable.

Support Android font scale. If metadata density breaks at large font scale, reflow vertically or disclose progressively instead of hiding important fields.

---

## 11. Accessibility

### Apple-side intent

Apple HIG says accessible interfaces empower everyone and emphasizes simple, intuitive, familiar interactions.

### Material 3 translation

Android must support:

- TalkBack
- system font scale
- large touch targets
- semantic content descriptions
- predictable focus order
- sufficient contrast
- Android system gestures
- keyboard/mouse/focus support where relevant
- reduced-motion expectations
- adaptive layouts for different screen sizes

### Kudos rule

Accessibility cannot be sacrificed for metadata density.

If a work card is too dense:

- stack metadata
- use chips wisely
- collapse secondary tags
- open detail on tap
- preserve important warning/rating information

Do not hide critical AO3 safety metadata.

---

## 12. Familiar System Behavior

### Apple-side intent

Apple HIG encourages familiar system gestures and behaviors over custom interactions people must learn.

### Material 3 translation

Use Android conventions:

- system back
- predictive back where supported
- standard scroll behavior
- standard bottom navigation
- standard top app bars
- standard sheets/dialogs
- standard share/document intents
- standard WebView login fallback
- standard biometric prompt

### Kudos rule

Avoid clever custom controls for ordinary tasks.

Use custom UI only where the reading experience truly benefits.

---

## 13. Search

### Apple-side intent

Search is important, global, and should not be confused with Browse.

### Material 3 translation

Use:

- top app bar search action
- search screen with field and filters
- `SearchBar` if appropriate
- filter bottom sheet
- result cards matching Library/Search visual language
- clear loading/error/empty states

### Kudos rule

Search behavior must match Apple/AO3 semantics exactly, but the Android UI should be Material-native.

Search is direct finding. Browse is exploration.

---

## 14. Home

### Apple-side intent

Home is a dashboard: glanceable shelves and quick return to reading.

### Material 3 translation

Home should use:

- clear top app bar
- horizontal shelves
- section headers with chevrons
- visual work cards
- empty-state cards
- a prominent search affordance
- bottom navigation

Recommended section order:

1. Continue Reading / Reading Now
2. Subscriptions / Recently Updated
3. Favorites
4. Recently Opened
5. Recently Added

### Kudos rule

Home is not a settings page and not a search result page. It should help the user resume or discover reading quickly.

---

## 15. Library

### Apple-side intent

Library is the local saved reading space.

### Material 3 translation

Library should use:

- local search
- filter chips
- sort sheet
- saved-work cards
- user tag chips/cards
- collection cards
- empty states
- downloaded/missing indicators
- progress/last-read indicators

### Kudos rule

Library must work offline.

Do not call AO3 just to populate Library.

Library should feel like the user’s personal reading space, not a database table.

---

## 16. Browse

### Apple-side intent

Browse should be native AO3 discovery, not just a WebView.

### Material 3 translation

Browse should use:

- category cards
- fandom metadata rows
- recently read chips
- search/filter affordances
- native category → fandom → works navigation
- WebView fallback only when native handling is unavailable

### Kudos rule

Browse is exploration.

It should preserve AO3 structure while making it easier to use on Android.

---

## 17. Account

### Apple-side intent

Account centralizes AO3 session state, account lists, AO3 web destinations, settings, and app info.

### Material 3 translation

Account should use:

- signed-in/signed-out status card
- clear login/logout actions
- grouped Material list cards
- external-link affordances
- privacy helper text
- settings/about/support group

Recommended groups:

```text
AO3 Account
My AO3
On AO3
Kudos / App
```

### Kudos rule

Account must clearly separate:

- local Kudos data
- AO3 session state
- AO3 account lists
- AO3 website links
- app settings/support

---

## 18. Reader

### Apple-side intent

Reader is the core experience and should be quiet, customizable, and focused.

### Material 3 translation

Reader should use Material only for:

- top controls
- bottom controls
- settings sheet
- progress controls
- snackbars
- dialogs
- error states

The reading surface itself should stay quiet.

### Kudos rule

Reader settings should support:

- light
- dark
- sepia
- font size
- margins
- line height
- scroll/paged mode where supported
- cross-platform progress fallback

Do not let app chrome dominate the reading surface.

---

## 19. Component Mapping

| Apple/HIG concept | Android/Material 3 equivalent |
|---|---|
| Native Apple feel | Native Android Material 3 feel |
| Tab bar | `NavigationBar` on phones |
| Sidebar | `NavigationRail` / adaptive navigation |
| Navigation stack | Navigation Compose destination |
| Toolbar action | Top app bar action |
| Sheet | `ModalBottomSheet` |
| Confirmation | `AlertDialog` |
| Collection shelf | `LazyRow` |
| Table/list | `LazyColumn` |
| Card-like surface | Material `Card` / `ElevatedCard` / filled surface |
| Disclosure chevron | trailing icon row/card |
| Pull-down menu | overflow/menu |
| Dynamic Type | Android font scale |
| Face ID prompt | `BiometricPrompt` / device credential |
| File importer/exporter | Storage Access Framework |
| ShareLink | Android share intent |

---

## 20. Anti-Patterns

Avoid:

- literal iOS visual clones
- generic sample-app Material UI
- overly sparse work cards
- debug placeholder text
- excessive empty space
- inconsistent icons
- hardcoded colors
- inaccessible low-contrast metadata
- hiding warning/rating metadata
- placing metadata outside cards inconsistently
- using a bottom navigation item as an action
- WebView dumping where native UI exists
- custom gestures as the only path
- stacking sheets and dialogs
- auto-fetching AO3 in offline Library screens

---

## 21. Final HIG-to-Material Rule

Whenever Apple HIG guidance says:

```text
Use familiar Apple platform conventions.
```

Android should read:

```text
Use familiar Android Material 3 platform conventions.
```

Whenever Apple HIG guidance says:

```text
Keep navigation clear and top-level destinations stable.
```

Android should implement:

```text
NavigationBar on compact screens.
NavigationRail/adaptive navigation on larger screens.
Search as a global action, not a fifth peer tab.
```

Whenever Apple HIG guidance says:

```text
Simple by design, powerful when needed.
```

Android keeps it unchanged:

```text
Simple by design, powerful when needed.
```

That principle belongs to Kudos, not to any one platform.

---

## Required Instruction for Remaining Android Prompts

Add this line to every remaining Android implementation or UI prompt:

```md
Read `docs/contracts/ANDROID_MATERIAL_HIG_TRANSLATION.md` and `docs/contracts/CROSS_PLATFORM_UI_BRIDGE.md`. Preserve the Apple app’s HIG-derived hierarchy, native-platform clarity, accessibility, and progressive disclosure, but express the UI through Android Material Design 3 and Jetpack Compose conventions.
```

---

## Recommended File Path

Add this document to the repo as:

```text
docs/contracts/ANDROID_MATERIAL_HIG_TRANSLATION.md
```

---

## Source Notes

Official source pages consulted for this translation include:

- Apple Human Interface Guidelines overview
- Apple HIG Accessibility
- Apple HIG Layout
- Apple HIG Tab Bars
- Apple HIG Toolbars
- Apple HIG Modality
- Apple HIG Sheets
- Apple HIG Menus
- Apple HIG Sidebars
- Material Design 3 overview
- Material Design 3 Color
- Material Design 3 Color Roles
- Material Design 3 Cards
- Material Design 3 Top App Bars
- Material Design 3 Navigation Bar
- Material Design 3 Layout / Breakpoints / Spacing
- Material Design 3 Color Contrast
- Android Developers Compose NavigationBar
- Android Developers Compose NavigationRail
- Android Developers Compose adaptive navigation
- Android Developers Compose adaptive apps
