# 3fq result — A63 action parity

Status: HANDOFF — 17 findings addressed in source; remaining findings listed below.
Lane `android/agent-codex-3fq`, starting and ending HEAD `07cabf69`;
initial worktree clean. No commits, pushes, branch switches, sign-in or AO3
contact. `TASKS.md` stays untouched per brief. No schema or backup-format changes.
All edits are uncommitted for Claude. **No build or tests have been run.**

## Scope

Confirm A63 findings at this HEAD against read-only iOS source, then address
F01, F30, F17, F12, F10, F05, F08, F20, F11 in order, followed by remaining
findings as time permits. Leave `comments/` and `account/AccountInboxPane.kt`
to Claude (F07/F16/F25/F31). Reuse 3fp's shared action controls.

## Changes and evidence

- F01 confirmed: Home shared the setting between single and selection deletion.
  `HomeWorkController.deletingSelection` now makes the bulk bar always ask,
  including a one-work selection; the single-work menu retains the setting.
- F30 confirmed: remote `SensitiveWorkRow` now finds local matches through a
  shared, remembered `WorkIdentityIndexInstance` supplied by `AppNavHost`.
  Hide-mode matches are excluded; Blur-mode matches use the local reveal gate,
  reader preparation and `LibraryWorkMenu` through `scopedWorkActions`.
- F17 confirmed: `RemoteWorkBulkActions.saveToLibrary` now awaits a readable EPUB
  before keeping the work. Existing files are reused; listing metadata needs no
  enrichment GET. The loop is sequential, propagates cancellation and stops on
  systemic failures rather than continuing through a block/outage.
- F12 confirmed: Search now uses shared `RemoteWorkSelectionActions`, which shows
  an Action Failed dialog and retains selection on failure/partial failure.
- F05 confirmed: the same shared host resolves selected metadata locally and
  opens `QueueMembershipDialog` / `AddSelectionToCollectionDialog`. All five
  callers (Search, fandom/tag works, author Works, author profile, series) use it.
  Sheets outlive a successful selection exit. No duplicate picker introduced.

- F10 confirmed: `SensitiveWorkRow`'s remote overload and Home/Account remote
  covers now share `RemoteWorkActionFrame`, `LibraryWorkMenu` and the existing
  scoped actions. Remote actions resolve without enrichment and offer Read,
  Comments, Download, Later, Queue, Finished, Collection and Work Details;
  existing saved matches expose Delete. Swipes use the existing `SwipeActionRow`.
  A newly localized work keeps its frame/picker state mounted.
- F08 confirmed: Search local rows now use `LocalActionableWorkRow` for reader,
  menu and swipes; selection still uses its original selectable row. Collection
  results reuse the extracted `CollectionCardMenu`, with an unconditional ask
  and the existing soft-delete path; the local match snapshot refreshes after it.
- F20 confirmed: Account paired rows and Compact covers use the same local
  reader/actions while retaining reveal gating and bookmark footnotes.
- F11 confirmed: app remote menus now follow iOS and omit Copy Link. The
  standalone/fallback remote menu's Copy Link writes the actual work URL to the
  Compose clipboard instead of doing nothing.
- F02/F03/F04 confirmed: Home now reuses `QueueMembershipDialog`,
  `AddSelectionToCollectionDialog` and `WorkBulkTagSheet`; its three limited
  private dialogs were removed. The importer is passed from Home for series
  preservation. This adds membership removal/create/series and all/some/none
  tag toggles using the existing implementations.
- F09 confirmed: saved-search deletion now calls `deleteSavedSearch` immediately,
  as iOS's `.onDelete` does; its extra confirmation is removed.
- F28 confirmed: Author Open on AO3 now uses the same pseud-aware dashboard URL
  as Share Profile (`AO3AuthorUrls.userDashboardUrl`).
- F29 confirmed: Account's More on AO3 now uses its existing full native page
  route (`native:more-on-ao3`), also used by its shortcut; the limited popup is removed.
- F06 confirmed: Search, fandom/tag works, author/profile/dashboard and series
  menus now mount shared `MatureWorkMenuItem`. It follows `hideMatureContent`,
  calls the existing `PrivacyGate.toggleRevealAll` (including device authentication),
  and exposes Show mature / Hide mature with the same session state as other screens.
- F32 confirmed: `FandomLetterIndex` now exposes an adjustable range and the current
  letter to TalkBack. Its steps contain only available letters; adjustment and
  touch use the same `pickLetter` handler, and clamp at either end.

Integration corrections found during static review:

- Search/Account remote-led list keys now use the stable AO3 work id, preserving
  a row's picker state when localization gives it a local UUID. Account paired
  rows keep the same shared frame through that transition; sparse enrichment is
  skipped for local matches. Shared local bookmark footnotes retain their status.
- Author selection explicitly renders selectable remote cards, so a local match
  cannot turn a selection tap into reader navigation. Tag taps select too.
- Remote frames wait for the initial local-library and privacy-setting snapshots
  before drawing names, avoiding an initial remote title ahead of the local blur.

These are source changes, not compilation/runtime or visual approval claims.

## iOS references checked

Read-only reference root: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`.
`UIComponents/WorkBulkActionBar.swift`, `RemoteWorkSelection.swift`,
`WorkBulkTagSheet.swift`; `Services/RemoteWorkBulkActions.swift`;
`Features/Library/WorkCardActions.swift` and `Collections.swift`;
`Features/Authors/AuthorDashboardSections.swift`, `AO3SeriesDetailView.swift`
and `AuthorProfileView.swift`; `Features/Search/SearchView.swift` and
`FandomListView.swift`; `Features/Browse/NativeBrowseView.swift`;
`Features/Account/AccountView.swift`; `Features/Privacy/MatureContent.swift`.

## Regression coverage written, not executed

Paths are under `android/app/src/test/java/io/github/cidy02/kudos/`.

- `home/HomeBulkDeleteTest.kt`: one selected work still asks with confirmations
  off; Cancel leaves the work active. Uses the actual Home bulk bar and dialogs.
- `works/WorkReadingCopyTest.kt`: bulk Download creates a kept physical EPUB,
  repeated Download reuses it and retains locator/favorite; missing-work partial
  failure continues, systemic failure stops, cancellation propagates without
  requesting later works; membership resolution has no requests and keeps no file.
- `ui/components/RemoteWorkActionsTest.kt`: matched Blur-mode row reveals before
  reading its local UUID; Hide mode leaves the remote listing unmatched; selection
  never routes a local match to the reader; remote Queue opens the shared picker
  through localization, creates and toggles membership; failed Download shows its
  error and retains selection; bulk Collection survives selection exit; Show/Hide
  mature uses the shared session gate. All clients are fakes.
- `ui/components/SensitiveWorkRowPrivacyTest.kt`: fallback Copy Link writes the URL.
- `browse/FandomLetterIndexTest.kt`: screen-reader adjustment skips unavailable
  letters and clamps at the ends.

## Verification and handoff

- `git diff --check`: passed. Branch and HEAD remain as dispatched.
- Cached Kotlin 2.3.21 compiler PSI parsed all 23 changed/new Kotlin files:
  `KOTLIN_PSI_PARSE files=23 errors=0`, exit 0. This is **syntax only**, not type
  checking, Compose compilation or tests. A preliminary JShell parser attempt
  timed out; a Java single-source invocation completed the check, and its temporary
  directory/source were removed automatically. No Gradle invocation or download.
- Reviewed all changed signature callers (`LibraryWorkMenu`, `HomeWorkDialogs`,
  `LedgerBookmark`, `AO3AuthorWorkCard`, remote `SensitiveWorkRow`) and migrated
  all five bulk hosts to `RemoteWorkSelectionActions`.
- Changed inventory contains Android production/tests and this report only.
  `TASKS.md`, `comments/`, `AccountInboxPane.kt`, Room entities/schema, backup
  formats, and iOS source are untouched. No helper scripts, stubs or `.orig` files.
- Gradle/build/tests and UI appearance/interaction remain unverified. Claude must
  compile the Android app/tests and run the regression classes above plus existing
  `SensitiveWorkRowLedgerTest`, Search/Account/author screen and membership suites.
  Check phone/tablet and TalkBack manually; human screenshots still gate approval.

## Stop point and remaining work

Stopped at this bounded, unbuilt batch. **Not addressed:** F14 (WebView EPUB import),
F13 (WebView controls), F18 (append pagination), F21 (exact page entry and Inbox
pager), F19 (dashboard fandom actions), F26 (author Expand All), F27 (dashboard
About), F22 (fandom-popular tag picker), F24 (extra collection-submit confirmation),
F23 (preferences result/retry presentation). None is dismissed as not worth fixing;
they still need confirmation at the then-current HEAD and implementation.

F07/F16/F25/F31 remain Claude's assigned Comments/Inbox work, untouched here.
F15 was withdrawn in A63 and was not changed. No port to the Apple worktree.

Next: Claude builds/tests this diff, visually checks shared menus and pickers,
blur → reveal → reader, author selection, Home Delete with confirmations off,
Download success/partial failure/cancellation, and TalkBack alphabet adjustment;
then resumes the remaining list at F14. No sign-in or live AO3 request was used
to verify any of this work.

## Part 2

Status: IN PROGRESS. Continuing on `android/agent-codex-3fq2` at `b5a21a66`
with an initially clean tree. Requested order: F14, F13, F18, F21, F19,
F26, F27, F22, F24, F23. User's current lane overrides the original brief's
branch name. No commits, pushes, branch switches, sign-in, AO3 contact or Gradle
invocations. `TASKS.md`, `comments/` and `account/AccountInboxPane.kt` remain
excluded. No Room schema or backup-format changes.

F14 confirmed in `AO3WebViewFallbackScreen`: no download listener/import route.
Investigating the existing paced downloader and local EPUB importer for reuse.

- F14 addressed: `AO3WebViewFallbackScreen` intercepts main-frame EPUB links and
  attaches a download listener; `WorkImporter.importWebEpub` uses the paced
  `AO3EpubDownloader.downloadUrl` then the existing metadata/dedup/revival importer.
  Download targets are restricted to HTTPS AO3 `/downloads/…/*.epub` URLs before
  any client call. No enrichment GET or background sweep. Screen exit cancels
  its coroutine and destroys the WebView. Result/error banners are transient.
- F13 addressed: address/search + Go, always-available Reload, local page Bookmark
  and immediate Done are wired in the WebView. `AppNavHost` supplies its existing
  bookmark DAO and importer; repeated bookmark saves preserve the stored id/date.
  Address submissions use the same URL policy as ordinary navigation.
- Added unexecuted coverage in `WorkLifecycleTest` (website import, dedup, flags,
  locator and file) and `AO3WebUrlPolicyTest` (download trust boundary and encoded
  address searches). iOS references: `BrowseView.swift`, `WebBrowser.swift`.

Continuing at F18. No compilation/runtime or visual approval claimed.

- F18 addressed: `AuthorProfileScreen.loadTab` appends Works/Series/Bookmarks
  by stable id for later pages and replaces on page-one resets. Existing
  selection remains over the accumulated works. `SeriesWorksScreen.load` does
  the same for series detail; both use `AuthorLoadMoreRow`, disabling duplicate
  taps and offering explicit retry without discarding earlier rows. No prefetch.
  Updated `AuthorProfileSortScreenTest` for Load More and added an unexecuted
  failure/retry/append regression using a fake client. iOS reference:
  `AuthorProfileContentSections.swift` (`AO3AuthorPaginationRows`).

Continuing at F21. The Inbox-specific portion remains outside this lane because
`AccountInboxPane.kt` is explicitly excluded.

- F21 shared-picker portion addressed: `PageScrubberSheet` adds exact numeric
  entry, range/overflow validation, keyboard Go and a scrollable keyboard-safe
  sheet. Typing/sliding only edits the draft; one Go selects one page. Added
  unexecuted `PaginationHintTest` coverage for page 2731/5000, invalid values and
  no request before Go. Inbox pager remains explicitly deferred to Claude.

- F19 addressed: Dashboard fandoms preview five, Expand/Collapse toggles the
  rest, and chips open AO3's exact fandom URL (including its user filter) through
  the existing website callback, matching iOS `AO3DashboardSections`. Added an
  unexecuted fake-client dashboard interaction test; expanding costs no read.

- F26 addressed: profile/dashboard More offers Expand/Collapse All and passes
  its state to every `AO3AuthorWorkCard` (including bookmark and own-work rows).
  Cards keep their existing individual disclosure behavior. Added an unexecuted
  menu/disclosure regression in `AuthorProfileSortScreenTest`. iOS reference:
  `AuthorProfileView.swift` and `AuthorDashboardSections.swift`.

- F27 addressed: Dashboard More → About now pushes `Routes.AuthorAbout`, which
  mounts the existing `AuthorProfileScreen` on `AuthorTab.About`. The route carries
  account/pseud identity, and Back uses the native stack. `onOpenAbout` is passed
  at all production/test callers of profile and dashboard screens. Added
  unexecuted tests for the dashboard callback and lazy About loading (no Works
  read). iOS reference: `AuthorProfileView.swift` dashboard destination.

Continuing at F22.

- F22 addressed: `FilterTagRow` receives fandom context through all
  `SearchFilterSheet` callers (Browse supplies its scoped fandoms). Opening a
  non-fandom picker reads the first fandom's first works page through the existing
  autocomplete repository/client and parses the requested include facet only.
  Blank-query content is labelled “Popular in …”; typed search and selected-tag
  cycles retain their existing behavior. Refine keeps its existing local-only
  contract. No fan-out, prefetch or request while cycling tags. Added unexecuted
  `AO3PopularTagsTest` and `FilterTagPickerPopularTest`. iOS references:
  `TagSelectField.swift`, `AO3Client.popularTags`.

- F24 addressed: Collection Items' toolbar Submit directly invokes the existing
  guarded `confirmSubmit` operation. The extra dialog and its UI-only guards are
  removed; staging, Discard, disabled/busy state and model double-submit/session
  fences remain. Existing `AO3CollectionItemsTest` / `AO3UserCollectionItemsTest`
  cover submission/refusal/double taps; this wiring removal adds no new logic.
  iOS reference: `AO3CollectionItemsView.swift` toolbar `submit()`.

Continuing at F23.

- F23 addressed: Preferences save results use an over-content Snackbar with an
  accessible live region and explicit dismiss. Success expires after three
  seconds; failure stays with a user-started Try Again wired to the same guarded
  save path. No automatic write retry. Failed saves retain edits, and edits made
  during a successful save stay dirty. Updated the prior expiry test for the
  overlay and added an unexecuted failure/retry/success-expiry interaction test
  in `Brief3caScreenTest`. iOS reference: `AO3PreferencesView.toastOverlay`.

All requested findings have source changes; F21's Inbox-only portion remains
excluded. Reviewing signatures, changed tests and static syntax now. Builds,
test execution, emulator interaction and visual approval remain for Claude.

Static review corrections: updated the existing `Brief3caScreenTest` author-page
retry flow to use Load More; added a real-navigation About/pseud round-trip test
in `RoutesNavigationTest`; added fake-client assertions that website downloads
refuse untrusted targets before transport, fetch the exact selected URL once,
and reject HTML. All of these tests remain unexecuted.
