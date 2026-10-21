# Brief 3gg result

Branch: `android/agent-codex3-3gg`, dispatched at `d62e3d59`.

Scope: A69 screen differences in brief 3gg. iOS source: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (read-only).

Verification: no Gradle, builds, emulator, sign-in, AO3 requests, commits, pushes, branch switches, or TASKS.md edits. Claude owns build/test execution and visual verification. Tests below were added or extended but have not been executed. Static verification is recorded at the end.

## Items

### 1. Backup — fixed
- `android/app/src/main/java/io/github/cidy02/kudos/settings/SettingsChrome.kt:86` registers the Settings page with the pushed-shell lifecycle; `app/Routes.kt:360` recognizes Backup's subject header. One header, shell Back, no second title. All extra backup notes and Deletion signing are retained (owner question 9 remains open).
- iOS followed: `Settings/SettingsHubView.swift:116` (`SettingsPageForm`), `Settings/SettingsBackupPage.swift:83`.
- Test added: `android/app/src/test/java/io/github/cidy02/kudos/settings/Settings3ggParityTest.kt:27`; route-policy assertion extended in `app/NavigationRoutesTest.kt:58` (test root as above).

### 2. Settings sub-page wash — fixed
- `android/app/src/main/java/io/github/cidy02/kudos/settings/SettingsChrome.kt:81` uses iOS's plain form backdrop: Light grouped paper, Sepia paper, Dark #16161A, OLED black. `app/PushedShellChrome.kt:24` carries that plain background to `app/MainScaffold.kt:409` / `:617` for the scrolled chrome, avoiding a second seam. The hub keeps its existing wash.
- iOS followed: `Settings/SettingsHubView.swift:116` (`appThemedScroll`, no wash), `Settings/SettingsHeaderBlock.swift:8` (hub header), `UIComponents/AppThemeSurface.swift:12` and `Features/Reader/ReaderStyle.swift:124` (plain form colour, distinct from Dark cardBackdrop).
- Test added: `android/app/src/test/java/io/github/cidy02/kudos/settings/Settings3ggParityTest.kt:27` checks all four themes, plain-background chrome registration and cleanup, one title, and no registered wash.

### 3. Dashboard series wash — fixed
- `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileComponents.kt:436` uses the existing fandom palette's `cardWash`, with the existing border. Shared compact bookmark cards get the same iOS treatment. `author/AuthorProfileScreen.kt:853` also reuses the existing series tally formatter to retain iOS's word count and omit unknown counts rather than inventing 0 works (`AuthorDashboardSections.swift:249`).
- iOS followed: `Features/Authors/AuthorDashboardSections.swift:86` (`cardRow(tintHue:)`), `:260` (compact card).
- Test: none added for the brush-only change; Claude to inspect all four themes.

### 4. Marked for Later Unmark — fixed
- `android/app/src/main/java/io/github/cidy02/kudos/account/AccountWorksListScreen.kt:728` wraps the ledger body and its footer in one continuous card ground, as iOS does. Unmark remains reachable before revealing a blurred work; download notes remain visible as before.
- iOS followed: `Features/Bookmarks/AO3MarkedForLaterWorksBrowser.swift:353` (ledger row and footer). Compact cover-grid accessories intentionally remain below covers, as iOS `Features/Account/AccountComponents.swift:522` does.
- Test added: `android/app/src/test/java/io/github/cidy02/kudos/account/Brief3ggParityTest.kt:101` checks footer bounds inside the card and the Unmark callback.

### 5. Inbox — fixed
- `android/app/src/main/java/io/github/cidy02/kudos/account/AccountInboxPane.kt:811` uses a filled neutral Reply capsule, no filter badge, and the shared role badge at every text size. The accessibility-only branch had drawn every role itself, including User; the shared badge already suppresses User.
- iOS followed: `Features/Comments/CommentThreadRow.swift:298` (role visibility), `:332` (Reply capsule); `Features/Account/AccountInboxViews.swift:98` (unbadged filter), `:348` (accessible byline).
- Shared Reply component also fixes the same presentation on comment threads, matching iOS's shared control. Guest, Author and Me remain visible.
- Tests added: `android/app/src/test/java/io/github/cidy02/kudos/account/Brief3ggParityTest.kt:55` (all four themes, normal/double text, User hidden; Guest/Author/Me retained; Reply callback) and `:88` (Unread filter has no badge). Shared capsule: `comments/CommentThreadComponents.kt:1032`, with a minimum 44dp target and no fixed-height thread row clipping.

### 6. AO3 Preferences Account rows — fixed
- `android/app/src/main/java/io/github/cidy02/kudos/account/AO3PreferencesScreen.kt:521` orders and labels the seven known Account links: Edit profile, Manage pseuds, Change username/password/email, Blocked users, Muted users. URLs still come from the parsed page; unknown extra links stay after them. Real `blocked/users` and `muted/users` URLs now get their correct icons too.
- iOS followed: `Features/Account/AO3PreferencesView.swift:598`.
- Test added: `android/app/src/test/java/io/github/cidy02/kudos/account/Brief3ggParityTest.kt:37` checks order, wording, exact preserved URLs, real blocked/users and muted/users paths, and retained unknown links.

### 7. Sync Folder metadata — fixed (Android equivalent)
- `android/app/src/main/java/io/github/cidy02/kudos/settings/SettingsPages2.kt:619` now shows Metadata, Last Checked (once checked), and Check Metadata / Retry Metadata Prep with leading icons. Last Synced stays separate. Pairing details, errors, extra devices and skipped-deletion notes stay.
- iOS followed: `Settings/SettingsSyncFolderPage.swift:132`: Metadata and prep action are unconditional; Last Checked requires a migration attempt, Last Synced requires a sync. The earlier "not real" verdict is incorrect.
- Android does not have SwiftData's CloudKit prep migration: Room migrates its schema on open. `backup/BackupRepository.kt:48` checks the actual local sync manifest through `captureLibrarySnapshot` and `BackupValidator` under the existing persistence gate, without exporting EPUBs, writing data or accessing a folder/network. `backup/SyncMetadataCheck.kt:9` reports the real outcome and supports retry. Its process-local result survives navigation; a fresh process checks again on opening Sync Folder.
- Tests added: `android/app/src/test/java/io/github/cidy02/kudos/backup/SyncMetadataCheckTest.kt:12` / `:31` (success/failure/retry/cancellation and single-flight); `backup/BackupRepositorySafetyTest.kt:51` (real in-memory Room snapshot validation, malformed metadata fails, retry succeeds, rows/assets unchanged and no EPUB writes).

### 8. Reading Queues disabled stepper — fixed
- `android/app/src/main/java/io/github/cidy02/kudos/settings/SettingsPages2.kt:768` removes the second, whole-control opacity reduction. Disabled glyphs use the theme's secondary ink once, preserving the disabled click behavior and 2–25 bounds.
- iOS followed: `Settings/SettingsStoragePages.swift:122` (native disabled Stepper; no extra opacity modifier).
- Test added: `android/app/src/test/java/io/github/cidy02/kudos/settings/Settings3ggParityTest.kt:61` checks disabled clicks in four themes and both bounds after enabling. The disabled-colour choice uses existing secondary ink; iOS has no literal colour override on its native disabled Stepper. Visual contrast remains Claude's check.

### 9. History cover author — fixed for absent authors; explicit information retained
- iOS remote covers show a name only when `work.authors.first` is nonempty (`Features/Home/HomeCards.swift:218`); local covers show every nonempty author (`:55`). There is no rule excluding the literal name Anonymous.
- `android/app/src/main/java/io/github/cidy02/kudos/account/AccountWorksListScreen.kt:1674` no longer synthesizes Anonymous for a remote cover with no parsed authors. Explicit Anonymous and all local author names stay. Shared account covers follow the same rule.
- Test added: `android/app/src/test/java/io/github/cidy02/kudos/account/Brief3ggParityTest.kt:48` checks empty authors, a blank author, explicit Anonymous, and a named author. Extra author information is retained when real.

### 10. Saved Search deletion and tab bar — fixed
- iOS followed: `Features/Search/SearchView.swift:442` (`onDelete`, swipe deletion) and `:257` (explicitly hides tab bar).
- `android/app/src/main/java/io/github/cidy02/kudos/search/SearchScreen.kt:811` uses trailing swipe to delete instead of a permanent trash icon. Long-press menu and an accessibility custom action keep deletion reachable without a gesture. Existing repository deletion/tombstone behavior is unchanged. `app/Routes.kt:395` hides Search's tab bar; Back still returns to the prior tab.
- Tests added: `android/app/src/test/java/io/github/cidy02/kudos/search/SavedSearchDeletion3ggTest.kt:25` / `:42` cover tap-to-run, no permanent trash icon, long-press menu, trailing swipe, and the accessibility action. `app/NavigationRoutesTest.kt:83` gains Search's hidden-bar assertion.

### 11. Browse Jump Back In at largest text — not real in current code
- Both platforms render this section whenever ranked picks exist, independent of text scale. Android `browse/BrowseScreen.kt:178` always reserves the LazyColumn slot while ranking loads; `browse/BrowseCategoryPanels.kt:60` has no text-size gate. That existing reserved-slot fix prevents an initially empty ranking from dropping the section. No additional production change needed.
- iOS checked: `Features/Search/MediaBrowserView.swift:268`, `:304`.
- Test: existing `BrowseFixtureJumpBackInTest.fixtureListsRankTheThreeIosCards`; added `android/app/src/test/java/io/github/cidy02/kudos/browse/JumpBackInLargeText3ggTest.kt:26` for picks arriving after composition at double text size in four themes and opening the fandom. Claude must recapture the live Browse screen to distinguish old tile/state differences from any remaining runtime issue.

### 12. Own Works, Drafts, Subscriptions — mixed fixed / not real
- Own Works: `android/app/src/main/java/io/github/cidy02/kudos/author/AuthorProfileScreen.kt:939` now always draws Works + loaded count (or Your works + selected/loaded during selection). `author/OwnWorksControls.kt:80` and `author/AuthorProfileComponents.kt:195` put Android's Material action menu inside the card footer, removing its detached row above the card. All four actions remain reachable; the trailing swipe still opens them without writing.
- iOS checked: `Features/Authors/AuthorProfileContentSections.swift:348` (Works heading), `:391` (own-work swipe actions); `Features/Authors/AuthorDashboardSections.swift:234` (optional Kudos, Comments, Hits, Bookmarks cells). The four-cell figure strip is correct when all four values exist; missing fields are already omitted on Android. Keep Android's full metadata, word/kudos totals subtitle and menu as useful extra information. Do not turn complete data into the iPhone fixture's stub cards.
- Draft expiry pills and Created footer: **not real**. iOS `Features/Writing/WritingDraftsView.swift:175` / `:284` / `:321` explicitly draws both when a deletion date can be parsed, plus the expiring-this-week subtitle. Android's draft-specific fixtures exercise this. The iPhone tile is consistent with different/sparser fixture data, rather than a rule suppressing these fields. Keep expiry warnings and created dates.
- Subscriptions sections: **not real**. iOS `Features/Bookmarks/AO3SubscriptionsWorksBrowser.swift:32` names New since you last looked and All works and groups by the actual unseen-chapter state. Keep Android's hydrated stats, new-chapter ranges and Unsubscribe. The tile is consistent with sparse/unenriched data; no information removed.
- Tests added: `android/app/src/test/java/io/github/cidy02/kudos/author/OwnWorkCard3ggTest.kt:23` / `:43` check menu bounds inside the card, every action, all four figures and absent fields. `author/OwnWorksScreenTest.kt:234` now asserts the Works section outside selection. Existing `account/WritingDraftsScreenTest.kt:229`–`:233` theme/large-text coverage and subscription tests are retained; no production changes to those correct draft/subscription behaviours.

## Left for Claude

- Build/typecheck and run the Android tests; none have been run here. Test paths abbreviated after the first full path are relative to `android/app/src/test/java/io/github/cidy02/kudos/`.
- Inspect the revised pages in Dark, Light, Sepia, OLED and largest text. In particular: continuous Backup/Settings background at rest and after scrolling; dashboard fandom wash; Unmark inside its card including a blurred work; Reply capsule/roles; disabled stepper contrast; saved-search swipe and Back with the bar hidden; own-work menu inside its card.
- Re-capture Browse at largest text. There is no corresponding text-size suppression in current code; a runtime reproduction remains open if it still disappears with nonempty ranked picks.
- Owner question 9 stays open. Extra backup paragraphs, Deletion signing, paired-device/skipped-deletion information, real author names, own-work figures/metadata/totals/menu, draft expiry/creation information, and subscription details/actions are retained.

## Static verification

- `git diff --check`: passed.
- Kotlin PSI syntax parsing using the already-cached compiler (no Gradle, no app compilation, no test execution): 24 changed/new Kotlin files parsed, zero syntax errors. Duplicate-import scan also passed. This does not resolve types or verify Compose runtime behaviour.
- No commit, push, branch switch, sign-in, AO3 request, iOS-source edit, or TASKS.md edit. The changes remain uncommitted for Claude.
