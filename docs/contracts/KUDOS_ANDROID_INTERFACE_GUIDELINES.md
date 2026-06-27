# Kudos Android Interface Guidelines and Design Philosophy

This document consolidates the interface guidelines and design philosophy for the Android port of Kudos, the AO3 reader app.

It combines the project’s reader-first philosophy, the cross-platform SwiftUI-to-Material bridge, Apple HIG-derived product intent, and Material Design 3 / Android platform guidance.

This is a design reference for implementation agents. It should be read before UI refinement work.

---

## 1. Core Product Identity

Kudos is a reader-first AO3 companion.

It should help people:

- find works
- save works
- download works
- read comfortably
- resume reading
- manage a local library
- use AO3 account features respectfully
- preserve their data privately

The Android app should not be a literal translation of the Apple UI.

It should be the same product expressed through Android and Material Design 3.

The guiding principle is:

```text
Same product language, platform-native expression.
```

Or, more specifically:

```text
Apple app = behavior, hierarchy, and product intent reference.
Android app = Material Design 3 native expression of that same experience.
```

---

## 2. Core Android Design Principle

Kudos on Android should be:

```text
Reader-first in purpose.
Material-native in expression.
AO3-respecting in behavior.
Privacy-first by default.
Local-first in data ownership.
Information-dense without feeling cluttered.
Simple by design, powerful when needed.
```

The Android app should not look like:

- a SwiftUI clone
- a generic Android sample app
- a debug scaffold
- a WebView wrapper
- a sparse UI that hides AO3 metadata

It should feel like:

- a polished Android reading app
- calm and focused
- metadata-aware
- trustworthy
- AO3-respecting
- native to Material Design 3

---

## 3. Reader First

Every screen should serve reading.

The UI should reduce friction between:

- finding a work
- understanding a work
- saving/downloading a work
- opening a work
- continuing a work
- organizing a library
- returning to AO3 when needed

The Reader is the most important screen.

The reading surface should stay quiet, comfortable, and book-like. App chrome should appear when useful and get out of the way when reading.

Material Design should support reading, not compete with it.

---

## 4. Respect AO3

Kudos complements AO3. It does not replace AO3.

The app must clearly distinguish:

- local Kudos library actions
- AO3 account actions
- AO3 website fallback
- authenticated AO3 features
- read-only AO3 browsing
- user-initiated AO3 writes

Use UI hierarchy and labels to make those boundaries understandable.

Examples:

- local saved works belong in Library
- AO3 account lists belong in Account
- AO3 website links should use external-link affordances
- authenticated actions should be explicit and user-initiated
- WebView fallback should be clearly labeled as AO3 web content

No design should encourage aggressive crawling, hidden automation, repeated background writes, or behavior that stresses AO3 more than a respectful browser session.

---

## 5. Privacy First

Users are readers, not products.

The app should avoid:

- ads
- tracking
- telemetry
- behavioral profiling
- unnecessary analytics
- unnecessary account coupling

The interface should make privacy understandable through:

- clear login state
- clear logout action
- clear local/offline state
- clear mature-content privacy controls
- clear backup/import/export behavior
- clear explanation that AO3 password is not stored
- clear separation between local data and AO3 account data

The UI should never make users feel watched.

---

## 6. Local First

The Library is the heart of the app.

The Android UI should make local/offline state visible and trustworthy.

Use clear indicators for:

- saved
- downloaded
- favorite
- finished
- reading progress
- missing local EPUB
- backup-ready data

Network-backed features should feel secondary to local reading.

The app should prefer cached/local data first, and refresh only when needed or user-requested.

Library screens must work offline.

---

## 7. Simple by Design, Powerful When Needed

The default path should be calm and obvious.

Advanced features should exist, but they should not overwhelm casual reading.

Use progressive disclosure:

- overview first
- detail on tap
- advanced controls in sheets or dedicated screens
- secondary actions in overflow menus
- visible active filters
- clear empty/loading/error states

The user should not need to understand AO3 internals to read, save, or continue a work.

---

## 8. Information Dense, Not Cluttered

Kudos needs more metadata than a typical reading app.

AO3 works depend on metadata for safety, context, and discoverability.

A clean design that hides important AO3 information is a regression.

Work cards and Work Detail should preserve, where available:

- title
- author
- fandom
- rating
- warnings
- categories
- relationships
- characters
- freeform/additional tags
- summary
- language
- word count
- chapters
- completion state
- kudos
- comments
- hits
- bookmarks
- saved/downloaded/favorite/finished state
- last read/progress state

Material 3 should be used to organize this density:

- cards
- chips
- badges
- grouped metadata rows
- dividers
- section headers
- progressive disclosure
- bottom sheets
- canonical detail screens

Design goal:

```text
dense, not cramped
clean, not sparse
native, not generic
```

Do not make the Android UI sparse just because generic Material examples are sparse.

---

## 9. Platform-Native Android Expression

On Android, Kudos should feel like a first-class Android app.

Use:

- Jetpack Compose
- Material Design 3
- Android system back behavior
- Android edge-to-edge and window-inset handling
- `NavigationBar` on phones
- `NavigationRail` or adaptive navigation on larger screens
- `TopAppBar` / `LargeTopAppBar` where appropriate
- `ModalBottomSheet` for filters, sort, reader settings, and secondary controls
- Material cards, chips, dialogs, buttons, and surfaces
- Android share sheet
- Android document picker
- Android BiometricPrompt where needed
- Android accessibility conventions

Avoid copying:

- SwiftUI navigation chrome
- Apple tab/sidebar visuals
- SF Symbols as-is
- iOS sheet visuals
- iOS toolbar spacing
- iOS modal behavior where Android has a better convention
- Apple-specific translucency or visual effects
- iOS/macOS layout assumptions

The app should preserve Apple’s intent, not Apple’s chrome.

---

## 10. HIG-to-Material Translation Rule

Apple HIG guidance often means:

```text
Be clear, familiar, consistent, accessible, and native to the platform.
```

For Android, the platform changes.

Whenever Apple guidance says:

```text
Use familiar Apple platform conventions.
```

Android should read:

```text
Use familiar Android Material 3 platform conventions.
```

Whenever Apple guidance says:

```text
Keep navigation clear and top-level destinations stable.
```

Android should implement:

```text
NavigationBar on compact screens.
NavigationRail or adaptive navigation on larger screens.
Search as a global action, not a fifth peer tab.
```

Whenever Apple guidance says:

```text
Simple by design, powerful when needed.
```

Android keeps it unchanged.

That is a Kudos product principle, not an Apple-specific rule.

---

## 11. Material 3 Source Context

Material Design 3 should guide Android expression.

Relevant Material principles for Kudos:

- components should express hierarchy, state, and brand
- color roles should maintain accessible contrast
- cards should group content and actions about a single subject
- top app bars display screen identity, navigation, and screen actions
- navigation bars are appropriate for three to five top-level destinations on compact screens
- navigation rails are appropriate for larger screens
- adaptive navigation should respond to window size
- spacing, surfaces, typography, and motion should clarify structure rather than decorate it

Kudos should use Material Design 3 as a design system, not as generic sample-app styling.

---

## 12. Cross-Platform Identity

Android and Apple should feel like the same product, but not the same UI toolkit.

Preserve across platforms:

- reading-first structure
- AO3 red accent
- calm light/dark/sepia themes
- dense AO3 metadata
- local library semantics
- backup compatibility
- privacy model
- AO3-respecting behavior
- Work Detail consistency
- simple-by-default, powerful-when-needed philosophy

Adapt per platform:

- navigation patterns
- system controls
- modal behavior
- typography scale
- gestures
- icons
- menus
- search affordances
- adaptive layout conventions

The result should be one product with two native expressions.

---

## 13. Navigation Model

Top-level Android destinations:

```text
Home
Library
Browse
Account
```

Search is a global action, not a normal fifth tab.

Conceptual distinction:

```text
Home = current reading life
Library = local saved/offline works
Browse = AO3 exploration
Search = direct finding
Account = AO3 account state and app/account management
Reader = focused reading surface
Work Detail = canonical work information/actions
```

Phone layout:

- bottom `NavigationBar`
- global Search in top app bar, FAB, or dedicated search action
- Work Detail as a canonical destination
- Reader as focused full-screen destination

Tablet/foldable layout:

- `NavigationRail` or adaptive navigation
- optional list-detail layouts
- avoid stretching phone UI awkwardly
- preserve the same destination model

---

## 14. Progressive Disclosure Rules

Use these consistently:

1. Horizontal shelf = overview.
2. Section header/chevron = open full list.
3. Card tap = detail.
4. Overflow menu = secondary item actions.
5. Bottom sheet = filters/settings/sort/secondary controls.
6. Full screen = deep task or full list.
7. Dialog = confirmation or blocking decision only.

Avoid mixing multiple disclosure styles for the same type of action.

Do not use:

- “See all” in one section
- chevron in another
- random text links elsewhere
- unrelated overflow behavior for the same action type

Pick a pattern and keep it consistent.

---

## 15. Modality and Sheets

Use `ModalBottomSheet` for temporary contextual controls:

- search filters
- library filters
- sort options
- reader typography/settings
- add to user tags
- add to collection
- backup/import choices when simple

Use full-screen destinations for:

- Reader
- Work Detail
- full lists
- login/WebView flow
- complex account flows
- comments if the thread or form is complex

Use `AlertDialog` for:

- destructive confirmations
- blocking decisions
- serious errors requiring acknowledgement

Avoid stacking too many modals.

Preserve Android back behavior.

---

## 16. Component Mapping

| Apple / HIG concept | Android / Material 3 equivalent |
|---|---|
| Native Apple feel | Native Android Material 3 feel |
| Tab bar | `NavigationBar` on phones |
| Sidebar | `NavigationRail` / adaptive navigation |
| Navigation stack push | Navigation Compose destination |
| Toolbar action | Top app bar action |
| Sheet | `ModalBottomSheet` |
| Confirmation dialog | `AlertDialog` |
| Collection shelf | `LazyRow` |
| Table/list | `LazyColumn` |
| Grid collection | `LazyVerticalGrid` where useful |
| Card-like surface | Material `Card`, `ElevatedCard`, or filled surface |
| Disclosure chevron | trailing icon row/card |
| Pull-down menu | overflow/dropdown menu |
| Dynamic Type | Android system font scale |
| Face ID / Touch ID | `BiometricPrompt` / device credential |
| File importer/exporter | Storage Access Framework |
| ShareLink | Android share intent |
| WKWebView fallback | Android WebView fallback |

---

## 17. Material 3 Component Guidance

Use Material components intentionally:

- `Scaffold` for screen structure
- `TopAppBar` / `LargeTopAppBar` for screen identity
- `NavigationBar` for phone top-level navigation
- `NavigationRail` for larger screens
- `Card` / `ElevatedCard` for grouped work/category/status surfaces
- `AssistChip` for metadata
- `FilterChip` for active filters
- `SuggestionChip` for related tags/fandoms
- `ModalBottomSheet` for filters/settings/sort
- `AlertDialog` for confirmations
- `SnackbarHost` for lightweight feedback
- `FloatingActionButton` or top-bar action for Search where appropriate
- `LazyColumn` and `LazyRow` for scalable lists/shelves

Do not use Material components as decoration.

Use them to clarify:

- structure
- action
- hierarchy
- state
- navigation

---

## 18. Theme, Color, and Brand

AO3 red is the primary accent, not the entire visual system.

Use AO3 red for:

- active navigation
- primary action emphasis
- AO3 identity accents
- selected chips
- important icons
- Search/FAB emphasis where appropriate

Avoid flooding the UI with red.

Dark theme should be:

- rich
- comfortable
- readable
- calm
- not pure debug black everywhere

Sepia should feel like a reading mode, not a novelty color.

Use Material color roles for:

- surfaces
- surface variants
- primary/accent
- error
- success/status where needed
- readable content contrast

Do not rely on color alone to communicate state.

---

## 19. Typography

Use Material typography roles consistently.

Suggested hierarchy:

- screen titles: headline/display roles
- section headers: title roles
- work titles: title roles
- author/fandom metadata: body/label roles
- tags and metadata chips: label roles
- helper text: body small / label small
- reader text: reader-specific typography settings

Avoid arbitrary font sizes everywhere.

Support Android system font scale.

If metadata density breaks at larger font scales, reflow vertically or disclose progressively instead of hiding important fields.

---

## 20. Work Cards

Work cards are one of the most important components in the app.

They should be:

- compact
- readable
- metadata-rich
- visually calm
- consistent across screens
- accessible

A good full Material 3 work card should include, where available:

1. title
2. author
3. fandom
4. rating
5. warnings/categories
6. summary snippet or reading progress
7. key relationships/characters/freeform tags
8. words / chapters / kudos / comments / hits
9. saved/downloaded/favorite/finished indicators

Cards should not look like generic placeholders.

They should communicate:

```text
This is a readable AO3 work, with context, safety metadata, social metadata, and local state.
```

Home shelf cards can be more visual, but they should still belong to the same card family.

---

## 21. Work Detail

Work Detail must be canonical.

The same Work Detail design should work from:

- Home
- Library
- Browse
- Search
- AO3 Bookmarks
- History
- Subscriptions
- Marked for Later
- Reader end-of-work
- direct AO3 links

Work Detail should group information clearly:

- identity: title, author, fandom
- safety/context: rating, warnings, categories
- relationship metadata: relationships, characters, freeforms
- reading context: summary, words, chapters, completion
- social stats: kudos, comments, hits, bookmarks where available
- local state: saved, downloaded, favorite, finished
- actions: read, download, save, tag, collect, comments, kudos, open on AO3

Do not split Work Detail into inconsistent versions for local and remote works.

---

## 22. Home

Home is the reading dashboard.

It should help the user resume or discover reading quickly.

Recommended priorities:

1. Continue Reading / Reading Now
2. Recently Updated / Subscriptions
3. Favorites
4. Recently Opened
5. Recently Added

Use:

- clear top app bar
- horizontal shelves
- section headers with chevrons
- visual work cards
- useful empty states
- global Search affordance

Home should not feel like:

- settings
- a debug list
- a giant blank page
- a search result page

---

## 23. Library

Library is the user’s personal reading space.

It should prioritize:

- Continue Reading
- saved works
- downloaded/offline works
- favorites
- finished/unfinished
- reading history
- user tags
- collections
- filters
- sorts
- local search

Library must work offline.

Material 3 should make Library powerful without making it intimidating:

- filter chips
- sort sheets
- search within Library
- clear empty states
- downloaded/missing indicators
- readable saved-work cards
- stable sections

The Library is not just a list. It is the reader’s home base.

---

## 24. Browse

Browse is AO3 exploration.

It should feel native, not like a raw WebView dump.

Use:

- large category cards
- fandom metadata rows
- saved/recent indicators
- recently read fandom chips
- native category → fandom → works navigation
- WebView fallback only when native handling is unavailable

Browse should preserve AO3’s structure while making it easier to use on Android.

Browse is exploration. Search is direct finding.

---

## 25. Search

Search is a global action.

Search should support direct finding through:

- a prominent entry point
- search field
- filters
- sort controls
- metadata-rich result cards
- clear empty/loading/error states

Search result cards should share visual language with Library and Browse result cards.

Search should not be treated as a normal fifth top-level tab unless the product direction explicitly changes.

---

## 26. Account

Account should clearly separate:

- local Kudos state
- signed-in AO3 session
- AO3 account lists
- AO3 website destinations
- app settings/support/about

Recommended groups:

```text
AO3 Account
My AO3
On AO3
Kudos / App
```

The signed-in state should be obvious.

The app should explain:

- AO3 login is optional
- Kudos never stores the AO3 password
- the session stays on device
- account actions depend on AO3

External AO3 destinations should use external-link affordances.

---

## 27. Reader

The Reader is the core experience.

It should be quiet, customizable, and focused.

Use Material only where helpful:

- top controls
- bottom controls
- reader settings sheet
- progress controls
- dialogs
- snackbars
- error states
- end-of-work actions

The reading surface should preserve:

- light
- dark
- sepia
- font settings
- margin settings
- line-height settings
- scroll/paged mode where supported
- cross-platform progress fallback

Do not let app chrome dominate the reading experience.

---

## 28. Comments and Authenticated Actions

Authenticated AO3 actions should be explicit, user-initiated, and clearly separated from local actions.

Examples:

- Kudos
- Subscribe / unsubscribe
- Mark for Later
- AO3 Bookmark
- Comments

UI should clearly show:

- signed out / login required state
- action loading state
- success state
- validation/error state
- WebView fallback when native handling is unsafe

Do not fake success.

Do not make AO3 account actions look like local Library state.

---

## 29. Settings and Backup

Settings should be understandable and grouped.

Backup UI should clearly communicate:

- export
- import
- compatibility
- privacy/session exclusion
- success/failure states

Backup should not include AO3 session cookies or private auth data.

Settings and Backup should use Material list/card patterns, not debug controls.

---

## 30. Empty, Loading, and Error States

Every major screen should have product-aware states.

Required state types where relevant:

- loading
- empty
- no results
- offline/missing data
- auth required
- network error
- AO3 overload/capacity
- parser/fallback error
- missing EPUB
- backup success/failure

Bad:

```text
TODO
Placeholder
Error
```

Good:

```text
No saved works yet. Save or download works to build your offline Library.
```

State messages should be helpful, calm, and honest.

---

## 31. Accessibility

Accessibility is not optional.

Android must support:

- TalkBack
- system font scale
- sufficient contrast
- large touch targets
- meaningful content descriptions
- predictable focus order
- semantic roles where useful
- Android system gestures
- keyboard/mouse/focus support where relevant
- reduced-motion expectations where applicable
- readable layouts across screen sizes

Metadata density must not come at the expense of accessibility.

If a work card is too dense:

- stack metadata
- use chips wisely
- collapse secondary tags
- open detail on tap
- increase card height
- preserve critical warning/rating information

Do not simply hide important metadata.

---

## 32. Adaptive Layout

Android must be future-ready for different screen sizes.

Use:

- bottom navigation on compact screens
- navigation rail on medium/expanded screens where supported
- responsive padding
- list-detail patterns where useful
- cards/lists that scale gracefully

Good candidates for adaptive layouts:

- Library list + Work Detail
- Search results + Work Detail
- Browse category + fandom list
- Account list + selected section

Do not stretch phone UI awkwardly across tablets/foldables.

---

## 33. Consistency Rules

The following should share visual DNA:

- Home shelf cards
- Library saved-work cards
- Search result cards
- Browse result cards
- Account AO3 work-list cards
- Download queue cards
- Work Detail metadata groups
- empty states
- loading states
- error states
- settings/account rows

Consistency does not mean every card is identical.

It means users can recognize the same product logic everywhere.

Use:

- one shared work-card family
- one shared metadata chip style
- one shared section header pattern
- one shared empty-state pattern
- one shared loading/error pattern
- one canonical Work Detail route
- one saved/offline/favorite/finished state language

---

## 34. Visual Tone

Kudos should feel:

- calm
- focused
- readable
- warm
- trustworthy
- slightly literary
- metadata-aware
- respectful of AO3’s identity
- native to Android

Avoid:

- excessive empty space
- debug-placeholder styling
- generic sample-app Material UI
- low-contrast metadata
- random hardcoded colors
- inconsistent icons
- decorative chrome that reduces scanability
- huge cards with little information
- cramped controls
- hiding AO3 safety metadata
- WebView dumping where native UI exists

The app should feel like a carefully designed Android reading app, not a porting scaffold.

---

## 35. Anti-Patterns

Avoid:

- literal iOS visual clones
- generic Material sample-app UI
- overly sparse work cards
- debug placeholder text
- excessive empty space
- inconsistent icons
- hardcoded colors
- inaccessible low-contrast metadata
- hiding warning/rating metadata
- placing metadata outside cards inconsistently
- using a bottom navigation item as an action
- making Search a random fifth tab without explicit product decision
- raw WebView dumping where native UI exists
- custom gestures as the only path
- stacking sheets and dialogs
- auto-fetching AO3 in offline Library screens
- changing behavior during UI polish

---

## 36. Final Design Principle

Whenever there is a conflict between copying the Apple app and following Android conventions:

1. preserve the behavior
2. preserve the information hierarchy
3. preserve the product identity
4. choose the Material 3 expression

Do not copy SwiftUI.

Do not make a generic Android app.

Make Kudos feel like Kudos, rebuilt honestly for Android.
