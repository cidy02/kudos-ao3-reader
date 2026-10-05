# Brief 3as — collection items moderation

**Landing note (Claude, 2026-10-05).** Landed as written; it compiled and passed first time.
Gate green (1,522 tests). Where this file says "the owner confirmed" or "the owner's
clarification", it was Claude's answer to Codex's question (it is in `DECISIONS.md`); the owner
has not been asked yet. The write was read against iOS's `updateCollectionItems` and
`collectionWriteVerdict` line by line and against `docs/AO3_NETWORKING_POLICY.md`: one fetch
for the form, then one POST per staged item, in order, never in parallel, never retried, the
first refusal stopping the rest. Seen on the emulator in airplane mode against the demo's local
answers, in Light and Dark: the screen, three changes staged, the confirmation, the first
accepted and gone from the tab, the second refused with "AO3 couldn't update that collection
item.", the third not sent and still staged. **Never run against AO3.**

Two things differ from iOS, both from Claude's wording and both kept for now: Android asks
"Submit N staged changes to AO3?" before sending (iOS sends on the tap), and Android reads the
list again after a refusal as well as after success (iOS only after success). Owner question 13.

The screen's Submit and Discard did not show at first. That was a fault in shared code, fixed
in its own commit: a pushed screen that is leaving wiped the top buttons of the screen that
replaced it.

**Found later the same day (Claude): the row leads to the wrong screen.** On iOS, Manage ›
Moderation opens the Moderation screen (`CollectionModerationView`: the review queue with
Approve and Reject, membership requests, the maintainers summary, reveal and anonymity), and
this items screen is reached from inside it ("Recently decided") and from the collections
list. Brief 3as called the items screen "the moderation screen", so Android opens it straight
from the row and has no Moderation screen. Brief 3aw builds it and moves the row.

Checked later the same day on the emulator: a switch and a removal staged, Keep, Discard, the
other three tabs, the second page, and going back and forward between the list, the collection
and this screen with each one's top buttons intact.

## iOS reference (read-only)

Read `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/Account/AO3CollectionItemsView.swift`, `AO3CollectionItemStaging.swift`, `AO3CollectionScreenDecisions.swift`, `AO3CollectionSessionReload.swift`, `Models/AO3CollectionDetailModels.swift`, `Services/AO3Client+Collections.swift`, and `Services/AO3CollectionActions.swift`.

- Header: “AO3 Account › Collections”, “Collection items”, collection title plus “1 needs a decision” / “N need a decision” (either approval awaiting), otherwise item count; page suffix when paginated.
- Four horizontal filters: “Awaiting collection” (collection default, omits status), “Awaiting you” (`unreviewed_by_user`), “Rejected” (`rejected_by_collection`), “Approved” (`approved`), then “Reset”. Declined is a model tab, deliberately absent from the screen. One section of item cards, no grouping by decision.
- Card: collection eyebrow, role, unsent-change dot, work title, “Approved by creator” and “Approved by moderators” with Awaiting / Approved / Rejected choices, then Unrevealed and Anonymous switches. Disabled served controls are facts (approval chip or On / Off), excluded from submission. Footer shows creator byline, “Remove from collection” / “Keep”, and date. No work-navigation tap is present.
- Staging changes the shown controls without sending. Restating the server values does not count. Removal replaces other edits, strikes the title, dims the card, hides settings, and says “This work will leave the collection when you submit your changes. It stays on AO3.” Keep cancels removal. Page/tab changes retain drafts; only current-page drafts count/submit. Discard clears all drafts.
- Toolbar words: “N staged”, “Submit”, “Discard”. Submit disabled with no pending changes or during submission. **There are no confirmations in this iOS screen**, including Remove and Discard.
- Loading spinner on an empty initial load; “Nothing in this tab.” for a recognized empty page; failure panel “Couldn't load collection items”, error text, “Try Again”; existing rows remain with an error on refresh/page failure. Signed out: “Log in to AO3 to manage collection items.” Session changes hide and clear old rows/drafts/paging/errors. No dedicated not-a-maintainer state: AO3 failures use the error panel, and editability comes from the served disabled controls.
- Paging fetches only the requested page. Tab changes replace rows and return to page 1; page changes retain previous rows until success and restore the displayed page on failure. Refresh fetches current page.

## Reference discrepancies resolved by the owner

The old survey/initial brief's combined-POST claim disagrees with iOS's actual code. **iOS wins**, as the owner confirmed: Android fetches the default collection-items page once for its token, action and method override, then sends one POST per current-page draft in ascending item-ID order (iOS `pendingDrafts` order). They are sequential, each taking the shared paced coordinator, never parallel/coalesced/retried. The first refusal/failure stops the loop. Session generation is fixed for the batch and checked after the form read, before each item, at the shared dispatch boundary after pacing, and after each response.

Owner note: **AO3's own form sends all items in one request; iOS deliberately does not.** This port preserves the per-item iOS behavior; it does not change either the AO3 form or iOS.

The reference has no confirmations. The owner's clarified instruction explicitly requires a confirmation: Android adds the collection page's existing `AlertDialog` presentation with “Submit staged changes?”, “Submit N staged change(s) to AO3?”, “Submit”, and “Cancel”. Discard and Remove/Keep stay local, immediate staging controls, as iOS implements them.

The reference refreshes after complete success, but its catch path does not refresh after partial failure. Per the owner's clarification, Android refreshes the selected tab/page after success **and after refusal/failure**, so earlier accepted writes are represented by the new server response. As on iOS, failed-submit drafts remain staged (their chips show those unsent choices, with the unsent-change marker); drafts now matching the refreshed response no longer count. Successful submission clears only sent drafts, retaining other pages' drafts.

## Networking policy

`docs/AO3_NETWORKING_POLICY.md` permits these reads as explicitly opened account/collection pages, under the “No background or bulk scraping” restriction. Request pacing, shared User-Agent, trusted-host allow-list, typed 403/404/429 and transient-only GET retries apply. No prefetch, crawling, polling or page read-ahead is needed. Writes fall under “Writes” and “What agents must NOT implement”: authenticated, generation-fenced at preparation and dispatch, paced, single shot with no retry/coalescing. No policy rule forbids the screen. No AO3 request or sign-in is performed during this implementation.

## Work log

Initial worktree clean; branch `android/agent-gemini-3as`. Per the brief: no TASKS.md edits, branch changes, commits, pushes, Gradle or Xcode runs. Backup and Room untouched.


## Implementation

- `account/AO3CollectionDetailScreen.kt` routes the maintainer's existing Manage → Moderation row to `Routes.AO3CollectionItems`; `AppNavHost.kt` supplies the same `collectionDetailRepository` and `writeRepository`. Other Manage actions keep their existing destinations.
- `network/ao3/account/AO3CollectionItems.kt` holds the iOS filter query values, row/form parser, immutable staging and `collectionItemParameters` encoding. Served meta/input CSRF, action and method override are retained; absent override falls back to `patch`, as iOS does. Explicitly disabled fields are filtered out. Removed items submit only `remove=1`.
- `AO3CollectionDetailRepository.getCollectionItems` performs authenticated, on-demand reads through its existing client. Its shared fetch now fences session expiry against the captured generation and parses off the UI thread. No caches, page walks or background jobs were added.
- `AO3WriteRepository.updateCollectionItems` reuses `AO3AuthenticatedClient.postAuthenticatedInSession` / `OkHttpAO3Client.postFormChecked` (brief 3an's path). Each POST is single shot, explicit-cookie, paced and coordinator-limited. A sent item finishes if the screen leaves; cancellation stops preparation of subsequent items. Error flashes are authoritative; success requires a success flash or redirect. Plain 2xx is unconfirmed and shows iOS's “AO3 replied but didn't confirm…” message; other unrecognised refusals use “AO3 couldn't update that collection item.”
- `AO3CollectionItemsState` owns current-page drafts, load generations and submission state. It guards duplicate confirms, retains server rows/page numbering on page failure, keeps off-page drafts, and never applies an old generation's read or write response. The composable creates new empty state immediately on session transitions, so stale private rows, forms, errors and drafts are not rendered.
- `AO3CollectionItemsScreen.kt` uses the subject header, collection panels/rows/separators, SubjectChip filters/status choices, shared refresh and pagination, and plain `ToolbarCircleButton` Submit/Discard controls. No Add operation exists in the reference, so there is no invented + action. Collection hues and theme tokens supply all new colours, including switches, dialogs and the shared pagination/refresh chrome. Roles, settings and footer stack/reflow at `isAccessibilityFontScale()`. Shared SubjectChip text now has an explicit 18sp line height; pagination gains an opt-in stacked layout and explicit text line heights.
- Forbidden/not-maintainer responses use the reference's existing failure/error wording (“AO3 denied access.” from Android's typed error); no new maintainer-status read is issued. Signed-out screens issue no reads. No work navigation is added to the item title, matching iOS.

## Local demo

`DemoNetwork.kt` intercepts Winter Exchange's items reads and each item POST before any socket call. `ao3_demo_collection_items.html` contains **original fictional filler only**: 13 items (4 awaiting collection, 3 awaiting creator, 3 rejected, 3 approved), disabled creator controls, editable moderator/flag/remove controls, roles, dates, flags, and an explicitly synthetic token. The interceptor filters the current state, returns only the requested three-item page, persists accepted decisions for later local reads and refuses item **42, “The Snowbound Post Office”** without modifying it. Missing fixtures and unknown writes remain terminal local failures. In-memory demo state resets when the app process restarts.

After Claude builds/installs the debug APK, restart with:

```sh
adb shell am force-stop io.github.cidy02.kudos
adb shell am start -n io.github.cidy02.kudos/.MainActivity --ez kudosDemoLibrary true --ez kudosDemoSignedIn true
```

This extra enables the existing fixture-only demo session; **do not sign in**. Navigate Account → Reading → Collections → Winter Exchange 2026 → Manage → Moderation. Stage Approved on “The Lantern Ledger” (41), “The Snowbound Post Office” (42), and “A Map of Warm Windows” (43), then Submit → Submit. Item 41 succeeds; 42 refuses; 43 is never sent. Refresh shows 41 absent from Awaiting collection and available in Approved; 42 remains awaiting with its draft, and the refusal is shown. Restart to reset, or use item 43/44 for successful approval/removal/flag changes and page 2 to check paging. Switch the four app themes and enlarge font scale for the visual gate.

## Verification and handoff

Added **13 offline tests** in `account/AO3CollectionItemsTest.kt` for fixture parsing, served token/override encoding and iOS field names, staging/disabled fields/off-page drafts/removal, malformed/login/untrusted/empty pages, one fresh form read, a changed served action/token/override at submit time, and ordered nonoverlapping per-item POSTs, double-confirm suppression, first-refusal termination and authoritative verification, zero POSTs on discard, on-demand tab/page loads, loading/empty/error/signed-out/not-maintainer states, stale initial/form reads, a session change after the first POST, and unconfirmed/transport failures without retry. Fakes terminate every request in memory.

Added `DemoNetworkBlockTest.winterItemsDemoServesEachFilterAndPageAndPersistsEveryLocalDecision` using the real local interceptor and bundled fixture with a downstream interceptor that throws if lookup falls through. It exercises all filters, page 2, token rejection, acceptance, refusal, removal, flag edits, and disabled creator-field rejection. It never reaches the network.

**Actually checked here:** real Kotlin/Compose/auth/client symbols and callers read; `git diff --check` passed; a Python standard-library HTML structure check passed for 13 unique IDs, 26 approval selects, 39 flag/remove checkboxes, 13 disabled creator controls and exactly one refusal marker. This is a fixture-structure check, not a Kotlin parser/test run.

**Claude still needs to run:** Android debug compilation and `:app:testDebugUnitTest` (at minimum `AO3CollectionItemsTest`, `DemoNetworkBlockTest`, existing write dispatch/unsubscribe tests, collection parser/list tests and navigation tests). No Gradle/Xcode/compiler/test suite or emulator was run here. Compilation, runtime test assertions, actual navigation, dialog interaction, theme rendering, large-font layout and screenshots remain unverified. Review partial-submit/refusal UX, retry-by-explicit-confirm only, and retained off-page drafts in the emulator. No live AO3 access is requested for those checks; live write verification remains the existing owner release gate.

No commits, pushes, branch changes, TASKS.md edits, backup-format changes, Room-schema changes, iOS edits, helper scripts, stubs or `.orig` files were made. All requested changes remain uncommitted in this worktree for Claude.
