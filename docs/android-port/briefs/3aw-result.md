# Brief 3aw — collection Moderation hub

**Landing note (Claude, 2026-10-05).** Landed on top of brief 3av, which had changed the same
files: three conflicts resolved by hand (both routes kept; the items screen takes its scope's
default tab unless a caller names one; the shared send loop keeps the stricter token rule).
Gate green (1,599 tests). Every write was read against iOS (`approveCollectionItem`,
`rejectCollectionItem`, `acceptMember`, `declineMember`, `revealCollection`,
`unanonCollection`) and against `docs/AO3_NETWORKING_POLICY.md`: one request per tap, after
iOS's confirmation where iOS has one, a fresh token read first, the session checked on entry
and after each read, never retried. **Never run against AO3.**

Changed on landing:
- The patch gave two shared components (the page subtitle and the section header) explicit
  line heights, which would have tightened the spacing of every page in the app. Taken back
  out; only "more than two lines at the largest text sizes" was kept. Worth doing on its own,
  compared against iOS page by page.
- The demo's Moderation fixture also answered the collection's own page (`/profile`), changing
  that page's counts and breaking an existing test. It now answers only the address the
  Moderation screen reads.
- The screen test failed about one full run in three, as a list-layout crash ("Index 2, size
  2") or a screen stuck on "Loading moderation…". Not the app: Compose's test rule runs effects
  unconfined, so after the repository parsed off the main thread the load carried on there and
  wrote the screen's state mid-layout. `AO3CollectionDetailRepository` now takes its parsing
  dispatcher as a parameter (unchanged by default) and this test keeps it on the test thread.

A real hole the patch closed: **in the demo, the in-app browser could reach AO3.** The demo's
network block covers the app's own requests, and the browser page bypassed it. In the demo it
now serves bundled pages or a local "not found" and nothing else.

Seen on the emulator in airplane mode against the demo's local answers, in Light, Dark and at
double text size: the screen opened from Manage › Moderation; Approve (the row leaves); a
second Approve refused ("Failed to approve: AO3 couldn't update that collection item.", the
row stays); Reject behind its confirmation, cancelled once and then confirmed; Accept; Decline
behind its confirmation; Reveal now and Remove anonymity, each behind its own confirmation,
the summary rows changing and the two actions disappearing; "Recently decided" opening the
items screen on Approved; "Message creator" opening the work's comments with the composer up
and nothing sent. Not checked on the emulator: the maintainers rows (they open the browser
page until brief 3ay's screen lands), the queue's second page, a maintainer who is not the
owner (covered by tests in all four themes).

## iOS reference inventory (read before implementation)

Read-only reference: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/Challenges/CollectionModerationView.swift`, `Services/AO3Client+Collections.swift`, `Services/AO3CollectionActions.swift`, and `Models/AO3CollectionDetailModels.swift`.

Subject header: collection title (slug fallback), **Moderation**, then `1 work awaiting review` / `N works awaiting review`, with ` on this page · page P of T` when paged, then ` · 1 membership request` / ` · N membership requests`. No top actions.

In scroll order:

1. Dismissible action error, when present.
2. **Awaiting review**, count = this page's rows. Each panel: uppercase item type, work title, creator byline plus ` · submitted DATE` only when AO3 prints a date; **Approve**, **Reject**, **Message creator**. No invented tags or statistics. Message creator opens native work comments with the composer open. Pagination keeps just the requested queue page; a failure retains the old page and says `Couldn't load that page: ERROR`. After deciding the last row, load the same page if it wasn't the last, otherwise the previous page. Footnote: `AO3 doesn't send the creator a reason or email when you reject a work. The work stays on AO3 and only leaves this collection.`
3. Disclosure form row **Recently decided** / **Approved and rejected**, opens collection items on **Approved**.
4. **Membership requests**, count = requests. Each row: pseud, `Wants to join TITLE`, **Accept**, **Decline**. No dates or per-person work counts.
5. **Maintainers**, no header count. Disclosure rows **Owners and moderators** / maintainer count, **Invite a maintainer**; both open `CollectionMaintainersView`. Footnote: `This shows how many maintainers there are. Manage roles, invitations and the last-owner rule under Maintainers.`
6. **Reveal and anonymity**, no header count. **Works** / `Unrevealed until reveal` or `Revealed`; **Creators** / `Anonymous until reveal` or `Credited`. While anonymous: `Creators are hidden from everyone but maintainers.` Owner-only actions **Reveal now** while unrevealed, **Remove anonymity** while anonymous. Other maintainers still see every summary row and footnote. Reveal error is separate from the dismissible action error. Footnote: `Reveal and Remove anonymity are separate actions. You confirm each one, and neither can be undone in Kudos.`

Confirmations (exact text):

| Title | Message | Buttons |
|---|---|---|
| Reject this work? | This rejects “TITLE” from the collection. The work stays on AO3, and its creator receives no reason or email. | Reject; Cancel |
| Decline PSEUD? | This removes PSEUD's membership request. They will need to apply again. | Decline; Cancel |
| Reveal this collection? | Unrevealed works and their creators become visible to everyone. You can't undo this in Kudos. | Reveal; Cancel |
| Remove anonymity? | Creators become visible to everyone instead of only maintainers. You can't undo this in Kudos. | Remove Anonymity; Cancel |

Approve and Accept have **no confirmation**; neither do Message creator or the disclosure rows. Cancel sends nothing. Initial/refresh loading clears loaded data and says **Loading moderation…**. Failure: **Couldn't load moderation**, user-facing error, **Try Again**. Empty queue: **No works waiting for review** / **All submissions to this collection have been reviewed.** Empty requests: **No membership requests** / **Nobody is waiting to join TITLE.** Failed actions keep the row: `Failed to approve: ERROR`, `Failed to reject: ERROR`, `Failed to accept: ERROR`, `Failed to decline: ERROR`. Reveal errors show ERROR directly.

Signed-out opening uses the same failure panel with `AO3AuthenticatedRequestError.notAuthenticated`'s exact text: **Log in to AO3 before using this feature.** It has no special signed-out layout or login button. The action-layer not-signed-in error separately says **Log in to AO3 first.** Transport/HTTP errors are user-facing messages; AO3 refusals retain their own text.

Read `Services/UserFacingError.swift`, `Services/AO3AuthService.swift` and the `AO3Error` definition in `Models/AO3Models.swift` too. The hub preserves their equivalent error words: `AO3 refused the request (HTTP 403). Wait a while before trying again.`, `That work or page couldn't be found (it may be restricted).`, `AO3 is rate-limiting requests. Wait a moment and try again.`, `AO3 had a server problem (HTTP STATUS). Try again shortly.`, `AO3 returned an unexpected response (HTTP STATUS).`, `AO3's page format wasn't what the app expected.`, `Your AO3 session expired. Please log in again.`, `You're offline. Connect to the internet and try again.`, `AO3 took too long to answer. Try again.`, `Couldn't make a secure connection to AO3.`, and `Couldn't reach AO3. Check your connection and try again.` Android's existing typed overload state has no iOS enum equivalent and retains the shared `AO3 is busy. Try again shortly.` message. This screen's scoped mapping leaves other Android screens' error messages alone.

## Network contract

Policy permits explicitly opened, foreground collection reads and tap-triggered writes. No forbidden operation is needed. No sign-in or live AO3 access is performed here.

`collectionModeration` opening and refresh = **three sequential authenticated GETs**: `/collections/SLUG/items` (default Awaiting collection, page 1), `/collections/SLUG/participants`, `/collections/SLUG` (**show**, not profile). Each uses the existing paced/coordinated client. Queue paging = one items GET, `?page=P` beyond page 1; never participants/show or read-ahead.

Approve/Reject: fetch default items page once, take served **meta CSRF**, action and `_method` (patch fallback); one POST with authenticity_token, _method, and `collection_items[ID][collection_approval_status]=approved|rejected`. The list parser has an input fallback, but iOS `fetchCSRFPage` does not; shared Android item writes now require meta as iOS does. No reason/mail field. Accept/Decline: one participants GET, **meta CSRF**, one POST to `/collections/SLUG/participants/ID`: `_method=patch`, `collection_participant[participant_role]=Member` for Accept; `_method=delete` for Decline; both send authenticity_token.

Reveal/Remove anonymity: iOS actually makes **two edit-form GETs**, despite the actions file's general one-CSRF-page comment. First parses the entire form; clears only unrevealed/anonymous respectively; `updateCollection` GETs edit again for a fresh **meta CSRF**, then one POST retaining the first form's action, method and other encoded fields. Success reloads the hub (three GETs). **iOS code wins** over any one-read interpretation. No timestamps/reveal schedule are invented; state is the show page's two flags.

Item/member success: error flash first, then success flash, then bare 3xx, otherwise ordinary 2xx is unconfirmed; other status uses action fallback. Form success: error first; success flash or successfully-created/updated words; bare 3xx; served validation errors; otherwise unconfirmed. Refusals retain AO3's words. All writes check the opening session at entry, after reads, before dispatch (including shared pacing boundary), and after response; no retry, coalescing, or stale screen mutation.

## Work log

Clean starting tree on `android/agent-codex-3aw`. Read 3as/3at landing notes and networking policy, README, AGENTS, onboarding, architecture map, regression matrix and current task rows. User's brief overrides TASKS claims, commits, branch changes, and build instructions. No build/test/emulator claim.

## Implementation

- `account/AO3CollectionModerationScreen.kt` is the independent hub; `AO3CollectionModerationState.kt` owns its session-bound data, queue page, pending confirmation, error notices and single in-flight action. All action families share the duplicate-tap guard requested here (iOS has separate item/member/reveal guards). Refusals leave all loaded values unchanged; successful item/member decisions remove only the decided row. No refresh after refusal. Successful reveal reloads the three hub pages. Queue-page failures retain the displayed page; successful decisions emptying a paged queue fetch only its nearest page.
- `AO3CollectionDetailRepository.getModeration` makes the three iOS reads in order and stops on the first failure/session change. The existing authenticated client owns pacing, slots, GET coalescing and permitted transient retries. Paging reuses `getCollectionItems`; there is no cache, background task, extra permission probe, or prefetch.
- `network/ao3/account/AO3CollectionModeration.kt` parses participants with iOS's id/form-action, byline and selected-role selectors. Owner/Moderator count as maintainers, None as requests, Invited appears in neither count. The existing item parser now retains work id and the Work/Bookmark type needed by the hub. The Bookmark selector is iOS's `blockquote.bookmark`.
- `AO3WriteRepository.decideCollectionMember` implements Accept/Decline. `revealCollection` parses the full edit form and delegates its one modified flag to existing `saveCollection`, retaining its fresh-meta-token read, action, method and full field encoding. Item decisions reuse existing `updateCollectionItems` with exactly one draft. Shared item writes now explicitly require the meta token, correcting the parser-input fallback discrepancy with iOS `fetchCSRFPage`; a regression test covers it. Preparation respects coroutine cancellation; dispatch retains the 3an/3as/3at explicit-cookie, generation-fenced, single-shot path. A dispatched POST may finish after leaving, but no departed screen/session continuation installs it.
- Manage → Moderation now carries `viewerIsOwner` from the collection show, exactly the reference's owner hint. The hub's Recently decided passes `tab=approved` to the existing items screen; collection-list callers keep their default Awaiting collection. `Routes` registers the subject-header/tab-bar behavior and encodes title/slug arguments.
- **Android has no maintainers screen.** Owners and moderators and Invite a maintainer both open `/collections/SLUG/participants` through the existing browser fallback, as Manage → Maintainers does. No native roster/invitation UI or invitation write was built.
- Message creator opens the existing native Comments screen with a new optional `compose=true` route argument. `CommentsScreen.initialComposes` opens the existing composer; ordinary comments callers retain their existing behavior. No comments write fires from the hub tap.
- Drawing reuses SubjectHeaderBlock, SectionRuleHeader, SubjectFormRow, SettingsPanel/SettingsActionRow, separators, refresh and pagination. Review action capsules use subject/theme tokens, not Material chips/cards. Dialogs use the form's themed AlertDialog pattern. New text has explicit line heights; the reused shared section-header and subtitle text now do too, and subtitles reflow at accessibility font scales. Review actions wrap, membership content stacks, summary values reflow, pagination stacks. No top actions are registered. Light/Dark/Sepia/OLED use their tokens; visual correctness is **not yet verified**.

## Local demo and emulator paths

`DemoNetworkInterceptor` owns all mutable demo answers. Original new fictional assets are `ao3_demo_moderation_show.html` (Winter Exchange 2026, both flags on) and `ao3_demo_moderation_participants.html` (two maintainers, two requests, one invitation, synthetic meta CSRF). The existing original items fixture supplies four awaiting items split into **two requested pages** (three then one), plus the other item tabs. The demo edit response starts unrevealed and anonymous; later show/profile reads reflect the saved edit flags without changing the raw form fixture used by 3at tests.

The browser fallback previously bypassed the OkHttp demo block. `AO3WebViewFallbackScreen.shouldInterceptRequest` now terminates demo WebView pages/subresources locally via `DemoNetwork.webFixture`; unknown pages and writes return a local 404. Live-mode browser behavior is unchanged. The maintainer destination therefore also works without an AO3 request in demo mode. This browser page is a read-only snapshot of the bundled participants fixture, rather than a native maintainer editor; the native hub's refreshed requests use the mutable interceptor answers.

After Claude builds/installs the debug APK, put the emulator in airplane mode and restart:

```sh
adb shell am force-stop io.github.cidy02.kudos
adb shell am start -n io.github.cidy02.kudos/.MainActivity --ez kudosDemoLibrary true --ez kudosDemoSignedIn true
```

These extras create the existing **fixture-only session**. Never sign in.

- Account → Collections (in Reading) → Winter Exchange 2026 → Manage → Moderation opens the hub. Opening/refresh shows three queue rows, two membership requests, two maintainers, Unrevealed and Anonymous. No Submit/Discard top buttons belong to this screen.
- Approve **The Lantern Ledger** (41): one immediate accepted decision; row leaves. Approve **The Snowbound Post Office** (42): refusal `Failed to approve: AO3 couldn't update that collection item.`; row stays. Reject **A Map of Warm Windows** (43): exact native confirmation; Cancel sends nothing, Reject succeeds and removes it. Item 42 refuses rejection too.
- Restart to reset, then page 2: **Footprints at First Light** (44) is the remaining queue row. Approve it to exercise moving to the previous page after emptying the last page. Pagination does not refetch membership/show.
- Accept **mapfold**: immediate success; request disappears. Decline **emberpost**: exact native confirmation; Cancel leaves it; Decline removes it. Pull-to-refresh preserves those local server decisions.
- **Reveal now** → Reveal: works become Revealed; Anonymous remains on. **Remove anonymity** → Remove Anonymity: creators become Credited. Cancel either dialog leaves both states untouched. Each successful action reloads the hub from local responses.
- Recently decided opens **Collection items**, with **Approved** selected; 41 is available there after approving it. Both maintainer rows open the local participants browser page. Message creator opens native comments with its composer; cancel/back without sending a comment to verify the route.
- Restart resets the demo's local mutations. Claude should inspect all four themes and at double font scale, including dialog wrapping and the two action rows. Non-owner summary/control visibility is covered by the added screen/state tests; an emulator screenshot of that case remains pending.

## Verification and handoff

There are **28 new test methods** in the diff (25 across the three new test files, two navigation tests, one shared item-write regression). This is a source count, **not a passing-suite claim**.

Offline tests were added in:

- `account/AO3CollectionModerationTest.kt`: fixture parsing, ordered three-read opening/refresh, one-page paging, all action request bodies/addresses/headers, whole-form preservation and fresh meta CSRF, confirmations/Cancel, all six duplicate-tap guards, refusal/error precedence with unchanged local state and no refresh, unconfirmed/transport/redirect outcomes, stale opening/page/form/second-token reads and write responses, non-owner controls/guards, loading/empty/failure/signed-out states, nearest-page reload.
- `account/AO3CollectionModerationScreenTest.kt`: the real Manage row's callback opens the actual hub, Recently decided opens the actual items screen requesting Approved, themed rejection/Cancel, and non-owner summaries with absent owner actions in all four themes. Its small local screen host exercises the UI callbacks; production AppNavHost wiring was inspected, not run.
- `network/ao3/DemoCollectionModerationTest.kt`: the real interceptor's two pages, accepted/refused item decisions, membership acceptance/decline, both separate reveals, retained flags, and terminal browser fixture/missing-asset answers. A downstream interceptor throws before any socket dispatch.
- `app/RoutesNavigationTest.kt`: real NavController argument matching/encoding for the hub owner flag, Approved/default items tabs, and comments composer/default route.
- `account/AO3CollectionItemsTest.kt`: shared item writes reject an input-only token when the required meta token is missing.

**Actually checked here:** read the real Kotlin/Compose/auth/client symbols used and their callers; `git diff --check` passes; a Python standard-library HTML structure check confirms five unique participant IDs, two requests, two maintainers, synthetic meta token and both flags. A lightweight delimiter check found balanced edited/new Kotlin files; it is **not compilation**.

**Claude must run:** Android debug compilation and `:app:testDebugUnitTest`, including all tests above, existing collection form/items/write-dispatch/demo-block tests, and comments/navigation/chrome regressions. The shared token correction, comments route argument and line-height changes warrant those regression runs. Then emulator navigation, every action/Cancel/double tap, session transition, native comments composer, browser demo interception, nearest-page behavior, all four themes, enlarged text, and screenshots. No Gradle, Xcode, Kotlin compiler, test suite, emulator or live AO3 call was run here. All runtime/test/visual claims remain unverified until those checks.

No commits, pushes, branch changes, TASKS.md edits, iOS edits, backup-format or Room-schema changes, stubs, helper scripts or `.orig` files. Changes remain uncommitted in this worktree for Claude to build, test and commit.
