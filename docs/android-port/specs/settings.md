# Settings (1ab), Privacy (1ac), and More on AO3 (1aa) Specification

This specification documents the Settings, Privacy, and More on AO3 screens for the Android port. The iOS codebase is the source of truth.

## 1. Screen Tree

The root of the Settings hierarchy is `SettingsHubView` (`SettingsRoute`), which presents a grouped form.

**Root:** Settings Hub (`SettingsHubView.swift`)
**Groups & Routes:**
- **Reading:** Appearance, Font, Reader, Listening (iOS only).
- **Downloads & Storage:** Downloads, Preservation, Reading Queues.
- **Library & Sync:** Library, Backup, Sync Folder, Import.
- **Account & Privacy:** AO3 Account (`.account`), Privacy (`.privacySettings`).
- **About:** About (`.about`).

**Reachable from Settings Hub:**
- `PrivacyDataView` (Privacy and local data, artboard 1ac): Pushed from the Privacy/About section.
- `AboutView` (About): Pushed from About, presents `LegalNoticesView` as a destination.
- `AccountMoreOnAO3View` (More on AO3, artboard 1aa): Reached from the Account hub, opening external links in the app's Browse web view.

## 2. Components

### Kotlin Components (from `1a-result.md`)
The design system has been ported to Android under `io.github.cidy02.kudos.ui.subject`:
- `Modifier.subjectPanel`: Replaces iOS `subjectPanel()` (14dp radius, panel fill with glass stroke).
- `Modifier.subjectScreenWash`: Replaces iOS `.subjectScreenWash(palette:)` (default 380.dp wash height).
- `SubjectHeaderBlock`, `SectionRuleHeader`, `SubjectRowSeparator` keep their names.
- `KudosTokens.accent`, `LocalSubjectPalette` handle theming.
- The `SubjectFormRow` is **not ported** (`1a-result.md`) and will need an Android equivalent or porting.

### Layout, Sizes, and Paddings
- **Gutters & Paddings:**
  - Standard account gutter: `SubjectMetrics.accountGutter` (used via `gutter` on panels, e.g., `PrivacyDataView.swift:189`).
  - Flush elements: `selfGuttered` is `0` (`PrivacyDataView.swift:192`), used for headers that provide their own padding.
  - Page body rows: Panels use `.pageBodyRow(top: 8, gutter: gutter)` while headers use `top: 18` or `top: 20` (`AccountMoreOnAO3View.swift:92-118`).
- **Fonts (Privacy Screen Promise Panel):**
  - Title: `@ScaledMetric(relativeTo: .headline) private var promiseTitleSize = 17` (`PrivacyDataView.swift:35`).
  - Body: `@ScaledMetric(relativeTo: .body) private var promiseBodySize = 13` (`PrivacyDataView.swift:36`).
  - Footnote: `12.5` pt, secondary colour (`PrivacyDataView.swift:233`).
- **Colours and Opacities:**
  - Account Palette: `theme.scopePalette` (app accent hue) (`PrivacyDataView.swift:195`).
  - Promise Palette: Uses the "Mint" hue (`PrivacyDataView.swift:199`). Panel wash fill, and a `0.5` pt stroke border (`PrivacyDataView.swift:229-234`).

## 3. Data

### Queries and Limits
In `PrivacyDataView.swift:42-48`:
- **Works:** `@Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }) private var works: [SavedWork]`. Soft-deleted works are excluded so clearing does not reach the recently deleted queue.
- **Collections:** `@Query(filter: #Predicate<WorkCollection> { !$0.isPendingDeletion }) private var collections: [WorkCollection]`.
- **Saved Searches:** `@Query private var savedSearches: [SavedSearch]`.

### Sizes and Measurement
- `LocalDataFootprintScanner.measure` scans disk usage for cache and reading copies dynamically. Sizes are resolved via `await measure()`.
- "Freeable downloads" filters `works` where they have no EPUB but aren't protected. "Reading positions" filters works with reading progress.

## 4. Interactions

### Navigation & Gestures
- **Toolbar & Navigation Bar:** 
  - On iOS, `SettingsHubView` hides the standard navigation bar chrome (`.hidesNavigationBarChrome()`) because the header names the page (`SettingsHubView.swift:115`).
  - `SettingsHubView` hides the floating tab bar (`.hidesFloatingTabBar()`).
- **Pull-to-refresh:** `PrivacyDataView` uses `.refreshable { await measure() }` to rescan disk usage (`PrivacyDataView.swift:117`).
- **Confirmation Dialogs (`PrivacyDataView`):** 
  - Destructive confirmations for "Clear Reading History?", "Free Up Space?", "Clear Reading Positions?", and "Clear Browse Cache?".
  - Each action runs the corresponding `LocalDataClearing` operation and then rescans storage size.

### Web Links (`AccountMoreOnAO3View`)
- Rows like `AccountExternalNavCard` open in the internal Browse view.
- Paths are validated against `AO3ArchivePage` and `AO3MoreOnAO3Route` constants (e.g. `importWork = "/works/new?import=true"`, `editWorksInBulk = "works/show_multiple"`).

## 5. Strings

### Settings Hub (`SettingsRoute.swift`)
- `"Reading"`, `"Downloads & Storage"`, `"Library & Sync"`, `"Account & Privacy"`, `"About"`.
- `"Appearance"`, `"Font"`, `"Reader"`, `"Downloads"`, `"Preservation"`, `"Reading Queues"`, `"Library"`, `"Backup"`, `"Sync Folder"`, `"Import"`, `"AO3 Account"`, `"Privacy"`, `"Privacy and local data"`.

### Privacy Screen (`PrivacyDataView.swift`)
- **Header:** Kicker: `"AO3 Account › Settings"`, Title: `"Privacy"`, Subtitle: `"Your reading data stays on this device"`.
- **Promise Panel:** 
  - `"No ads or tracking, and no separate Kudos account"`
  - `"Kudos connects to AO3. After you approve a Voice Pack download, it also connects to the service providing the pack. Your library, reading positions, tags, collections, and AO3 sign-in stay on this device."`
- **Stored Panel:** `"Stored on this device"`, `"Reading copies"`, `"Caches"`, `"Reading positions"`, `"Local collections"`, `"Saved searches"`, `"Search history"`, `"Not recorded"`.
- **Clear Panel:** `"Free up space"`, `"Clear reading positions"`, `"Clear reading history"`, `"Clear browse cache"`.
- **Footnotes:**
  - `"The sizes shown are measured on this device. Browse keeps fandom and category lists so it opens faster; it rebuilds them when needed, and your device may remove them to free space."`
  - `"Each option asks before it clears anything and tells you what will change on this device. Your AO3 reading history is separate; clear it from History or turn it off in AO3 Preferences."`

### More on AO3 (`AccountMoreOnAO3View.swift`)
- **Header:** Kicker: `"AO3 Account"`, Title: `"More on AO3"`, Subtitle: `"Opens on AO3 in Browse"`.
- **Sections:** `"Post and manage"`, `"Challenges"`, `"Your account"`, `"The archive"`.
- **Footnotes:** `"These open your AO3 pages in Browse. You can find works, series, bookmarks, history and inbox in the Reading, Writing and Activity sections of Account."`

### Backup Import (`BackupImportSheet.swift`)
- `"Merge keeps everything already on this device and adds anything you don't have from the backup. It removes nothing."`
- `"Replace makes this device match the backup. Your works, reading positions, notes, collections, and queues change to match it, and anything missing from the backup is removed. You will confirm before it starts, and Kudos saves a copy of your current library first."`

## 6. Owner Decisions

- **Backup Import Sheet:**
  - `BackupImportSheet.swift:145`: "The owner's call: one sheet that presents the decision, and alerts kept for destructive confirmation only." The Replace functionality is a two-step flow in the same sheet rather than distinct ones.
- **Privacy Screen Figures:**
  - `PrivacyDataView.swift`: "Why the figures are measured rather than described... a privacy page is the one page where being asked to take a claim on trust is the wrong ask, and the spec agrees: 1ac prints 412 MB, 318 works, 6, and lets you clear each."
- **Privacy Screen Exclusions:**
  - The spec omits Voice Pack and AO3 session row, but the owner elected to keep them because `AGENTS.md` treats dropping metadata as a regression (`PrivacyDataView.swift:21`).
  - Search history has no clear button; the row states `"Not recorded"` instead of offering a clear function because Kudos doesn't store a search history log (`PrivacyDataView.swift:25`).
  - Promise panel wording deliberately keeps the Voice Pack exception instead of an over-claimed absolute privacy guarantee (`PrivacyDataView.swift:213`).
- **More on AO3 Exclusions:**
  - Fannish next of kin is purposefully absent because there is no user route for it in the archive (`AccountMoreOnAO3View.swift:197`).
  - Figures are omitted beside bulk edit, collection items, and related works, as they are not cached and the screen shouldn't fetch AO3 specifically for them (`AccountMoreOnAO3View.swift:133`).

## 7. Android Gaps

According to `1a-result.md` and codebase observations:
- **`SubjectFormRow` is not ported.** The Privacy and Settings screens rely heavily on `SubjectFormRow` (e.g. for "Stored on this device" counts, settings rows). An Android equivalent needs to be built.
- **No text auto-shrink** exists natively in Compose for the components used, which may affect long strings in rows.
- **Dynamic Type scaling cap** is not applied to stat strips, which may require manual bounding on Android.
- `SettingsHubView` hides iOS-specific `NavigationBarChrome`. Android will need to adjust its `Scaffold` or top bar to mimic this header-driven design without duplicating the page title.
- The Voice Pack section refers to the iOS "Read Aloud" feature. Android's TTS implementation and settings footprint might differ, although the privacy commitments remain the same.
