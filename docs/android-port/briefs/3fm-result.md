# 3fm result — remaining A59 rows

Status: all four implementation items written, ready for Claude's build/test and UI gate.
Started with a clean tree on `android/agent-codex-3fm` at `38cd67b1`; branch and HEAD
are unchanged. Changes are deliberately uncommitted.

No commits, pushes, branch changes, sign-in, AO3 contact, TASKS.md edits, Room schema
changes, or backup-format changes. No helper scripts, stubs, or .orig files created.

## 1. Marked for Later — implemented

Confirmed at HEAD: grouping already worked, but every run called the ledger row.

- `android/app/src/main/java/io/github/cidy02/kudos/account/AccountWorksListScreen.kt:659`
  now renders the section policy through the existing `CompactWorkCovers`, with an
  Unmark button under each updated cover. Everything else and Downloaded keep the
  ledger and its download-size line. Existing cover privacy/reveal behavior is reused.
- `markedForLaterSections` at line 702 ports iOS's page order, nonempty runs,
  cover/ledger choice, and headers only on All.
- `MarkedForLaterRulesTest.allSplitsUpdatedAheadOfEverythingElse` and
  `.narrowedPillsAreOneList` port the named iOS assertions, including updated-and-
  downloaded overlap and empty runs.

## 2. Comment formatting tray — implemented

Confirmed at HEAD: `CommentFormattingTray` used flowing chips.

- `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentMarkup.kt:226`
  defines `CommentFormattingLayout`; the tray uses it at line 252 and lays out
  equal-width tile rows at line 287.
- Four columns through font scale **1.3**; two at **>1.3 and <1.8**; one at **1.8+**.
  This uses the app's existing >1.3 accessibility threshold. Scales 1.5/1.7 stand
  in for iOS accessibility1/2; 1.8 and above stand in for accessibility3+.
- Gap 7 dp, minimum tile height 58 dp, inner padding 6 dp horizontal / 8 dp vertical,
  glyph over name and literal tag, corner 11 dp. Text can grow/wrap. The heading-level
  chips stay separate, as on iOS. Tag insertion/dismissal behavior is preserved.
- `CommentFormattingLayoutTest.theTrayIsFourColumnsUntilAccessibilitySizes` ports
  iOS's constants/scales assertion. `CommentFormattingTrayScreenTest` checks actual
  text positions in the four-, two-, and one-column tray at scales 1, 1.5, 1.7, 1.8.

## 3. Tag canonical/count metadata — implemented

Confirmed at HEAD: the repository returned only names; the picker labeled every
suggestion canonical and had no count field.

- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/search/AO3TagAutocompleteRepository.kt:60`
  exposes structured editor suggestions using the existing request and URL builder.
  The parser at line 78 keeps `canonical` / `is_canonical`, `work_count` / `count`,
  name then id fallback, and iOS defaults (canonical true, unknown count).
- Existing search callers still receive names and keep their two-character gate.
  Writing keeps its one-character gate, debounce, cancellation and chosen filtering.
  `WritingTagsEditorState.kt:79` carries metadata through the read and cache.
- `WritingTagsEditorScreen.kt:194` shows the supplied canonical / Posts as typed badge
  and optional formatted count. No additional request or count lookup.
- Tests: `DemoTagAutocompleteTest.canonicalAndCountAreParsedWhenPresent`,
  `WritingTagsEditorStateTest.canonicalAndCountSurviveTheReadCacheAndChosenFiltering`,
  and `WritingTagsEditorScreenTest.suggestionRowsShowCanonicalOrPostsAsTypedAndTheSuppliedCount`.

## 4. Series identities / bookmark collections — implemented

Confirmed at HEAD: series creators were strings with account usernames kept separately;
exact pseud routes and bookmark collections were discarded.

- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/author/AO3AuthorParser.kt:192`
  retains creator identities with decoded account/pseud routes. Anonymous has no route.
  Shared `AO3AuthorRoute.fromUrl` in `AO3AuthorModels.kt:34` resolves only trusted AO3
  user links, rejecting foreign/lookalike hosts and orphan-account navigation.
- Series cards in `author/AuthorProfileComponents.kt` link each registered creator to
  the native author screen through `AuthorProfileScreen`, `SeriesWorksScreen`,
  `Routes.authorProfile(AO3AuthorRoute)` and `AppNavHost`. The series show-page metadata
  also keeps identities from its own HTML, so that shared card doesn't lose the route.
- `AO3AuthorParser.kt:233` keeps bookmark collections using iOS's selector.
  **The collection-display gap is not real on the current iOS reference**:
  `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/Authors/AuthorProfileComponents.swift:415`
  (`AO3BookmarkFootnote`) draws status, notes and tags, not collections. Android retains
  the parsed collections and matches that presentation; no invented collection chips.
- `AO3AuthorSeriesBlurbTest.parsesSeriesCreatorsAndBookmarkCollections` ports
  `AO3AuthorProfileTests.parsesSeriesAndBookmarkMetadata`; added route-boundary cases.
  Extended `AO3SeriesRepositoryTest` to assert the show-page pseud route.
  `SeriesCreatorScreenTest` checks the creator tap, the native route's pseud round-trip,
  and absence of an Anonymous author action.

## Verification and handoff

- `git diff --check`: passed after implementation and static review.
- Read changed code, callers, local fixtures, and the named iOS assertions/reference UI.
- **No Gradle/build/test execution**, as required by the brief. All added tests are
  unrun. No simulator/emulator visual verification; no visual correctness claim.
- Next: Claude runs Android compilation and the affected tests above, then the lane's
  full gate and screenshots for Marked for Later, the tray, tag metadata and creator taps.
- Bookmark collections intentionally have no extra visual treatment, matching iOS.
  The two read-only review findings below need separate follow-up.

## Second review — all ten requested commits, read-only

Static code review only; these are not runtime reproductions. No fixes were made for
these findings. Paths/lines below refer to this worktree's current files.

### F1 — P2: Inbox delete confirmation outlives its session

`android/app/src/main/java/io/github/cidy02/kudos/account/AccountInboxPane.kt:128`
keeps `pendingDelete` with unkeyed `remember`. Its Confirm callback at line 150 uses
current view-model state; `AccountInboxViewModel.kt:297` captures the current viewer
only when that callback starts the write. The generation fence added by `3138771b`
therefore protects the period after Confirm, but not the pending confirmation.

Reproduction to add: open a single-row Delete dialog in session A, sign out/relogin
(or replace the account) while it is open, load equivalent selectable rows, then
confirm the old dialog. The old item passes the id-only check at
`AccountInboxViewModel.kt:294`, and a POST can be constructed in the replacement
session using its form and the old item's checkbox. The same-account relogin case
can carry identical checkbox values. The dialog should be dismissed or bound to the
viewer that opened it, and that viewer must reach the dispatch fence. This is the
Inbox analogue of the History confirmation fixed in `127654f3`.

### F2 — P2: comment success can cross a session during draft storage

`android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsViewModel.kt:826`
checks the sending viewer, then line 827 suspends in `CommentDraftStore.clearVariants`
(DataStore `edit`; `network/ao3/comments/CommentDraftStore.kt:61`). After it resumes,
lines 828–838 change verification/message state and reload without another viewer
check. `syncViewer` doesn't cancel this submission coroutine.

Reproduction to add: hold that DataStore edit after a successful POST, change viewer
and let the new session's screen/composer open, then release it. The old continuation
can publish “Posted.” and reload the new viewer's comments; on a same-name relogin,
draft deletion is also only username-keyed. The guard added by `127654f3` handles a
session change before `posted` reaches the guard, but not this later suspension.
Recheck after storage before UI/cache/reload work; test with a held draft-store edit
and consider fencing the draft deletion inside its transaction as well.

### Commit coverage

| Commit | Static review result |
|---|---|
| `127654f3` | F2; History flag scoping, unknown chapter counts, and displayed Inbox filter selection otherwise look consistent with the intended assertions. |
| `cf6d1bcd` | No additional finding in Inbox-route session binding or removal of signed-in public fallback. |
| `8667d16a` | No additional finding in generation-qualified count keys or bookmark lower-bound handling. |
| `15897e0a` | No additional finding in shared markup transforms/link caret behavior. |
| `3138771b` | F1 is the confirmation-stage gap; post-tap dispatch fence and stale enrichment guard otherwise look consistent. |
| `24e02912` | No additional finding in emptied-page policy or real-size download label. |
| `c1e910e1` | No additional finding in chapter-range copy and its row wiring. |
| `7db6b987` | No additional finding in dashboard-derived count recording/display. |
| `8afbc2b4` | No additional finding in missing/unreadable dashboard groups or removal of count-only background reads. |
| `73039199` | No additional finding in signed-out Reply handling, known More-on-AO3 targets, or shared-markup assertions. |
