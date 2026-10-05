# Brief 3an — subscriptions unsubscribe

**Landing note (Claude, 2026-10-05).** Landed as written, less one import in a test that did
not compile. Gate green (1,482 tests). The write was read against iOS's
`AO3WriteActions.unsubscribe` step by step and against `docs/AO3_NETWORKING_POLICY.md`: the
address comes from the row AO3 served, a fresh token is fetched once, one POST is sent through
the paced client, the client never retries a POST, the row leaves the list only when AO3's
answer confirms it, and nothing is sent without a confirmed tap. Seen on the emulator against
the demo's local answers, in airplane mode: a work unsubscribed and gone from the list, a
second work refused with "Couldn't unsubscribe" and still listed, and the demo's series
unsubscribed to a true empty state, each after its confirmation. **Never run against AO3:**
like iOS's write actions, it waits on a signed-in check on a real phone.
One change reaches further than this page: a signed-in page read that finishes after the
account has changed is now dropped instead of returned (`AO3AuthenticatedClient`).

Implementation ready for Claude’s build/test review. Android-only, on the existing `android/agent-gemini-3an` branch. No builds, sign-in, AO3 contact, commits, pushes, branch switches or TASKS edits are authorized here.

## Reference takes precedence

Read the reference in `/Users/cidy02/kudos-ios-polish/` without changing it. The brief's description differs from the actual code:

- `AO3WriteActions.unsubscribe(path:page:)` uses the **action captured from the displayed row**, GETs the **Works** index at the supplied page for a fresh general CSRF token (also for Series/Authors), and sends `_method=delete`. It does not re-find the row's form on that fresh page. If the row is already gone, it still POSTs the captured action and uses AO3's response; absence alone is not success. This port follows iOS, rather than the brief's fresh-row-form requirement.
- `AO3AccountWorksList.unsubscribe` removes the work and action after confirmation, then `reloadIfPageEmptied` loads the preceding page only if a later page became empty. It **does not delete the watermark**. This port keeps the watermark as iOS does, rather than forgetting the new-chapter count as requested in the brief.
- Named rows have trailing destructive Unsubscribe (`AO3NamedSubscriptionsList.rowLink`), confirmation “Unsubscribe?” / “Unsubscribe” and ““<name>” will be removed from your AO3 subscriptions. You will stop getting update emails for it.” Works keep their existing, different confirmation. iOS uses a post-success named tombstone to suppress older GETs; Android invalidates older loads and updates the loaded rows directly, without a hidden set.
- `readingsWriteResult`: an error flash wins; a nonempty `.flash.comment_notice, .flash.notice` or a 3xx confirms; a flashless 2xx does not. Alert title is “Couldn't unsubscribe”. Unconfirmed detail is “AO3 replied but didn't confirm the change went through. Check on AO3 before trying again.”

## Networking policy

`docs/AO3_NETWORKING_POLICY.md` permits this user-confirmed account write. Relevant rules: identifiable shared UA, trusted hosts, shared pacing/coordinator, CSRF through authenticated page HTML, single-shot/non-coalesced writes, 429 surfaced without write retry, stale-session rejection before dispatch (including after pacing), and no background/bulk authenticated scraping or polling. No rule forbids the flow. One fresh visible-account-index GET and at most one POST per confirmation; no automatic write retry.

Android today: `DefaultAO3AuthenticatedClient` resolves explicit cookie headers; `OkHttpAO3Client.postForm` uses the shared coordinator and POST-disabled retry policy. `Call.await` cancels its call when the caller coroutine is cancelled. This flow wraps only the confirmed POST in `NonCancellable` (including its existing pacing wait). Screen-owned preparation GETs remain cancellable. `postAuthenticatedInSession` captures explicit cookies and `postFormChecked` checks the preparing generation after the shared coordinator’s pacing, immediately before the call. A stale generation cancels queued dispatch; once sent the call finishes. Screen cancellation and session changes discard its result. The app container supplies the same `ao3Client` to account lists, authenticated GETs and POSTs; no second HTTP client/path was added.

## Implementation

- `AO3AccountParser.parseSubscriptionsPage` now retains each Works row’s adjacent-dd action in `AO3SearchPage.unsubscribePaths`. Named parsing adds `AO3NamedSubscription.unsubscribePath`. No action is synthesized from a work, series or user id; missing/blank adjacent actions leave rows without a write control. These are transient remote page values, not Room or backup records.
- `AO3WriteRepository.unsubscribe(path,page)` uses the existing authenticated client, form encoder, headers and coordinator. Fresh-token parsing reuses `AO3WriteFormParser.parseAuthenticityToken(metaOnly=true)` to match iOS’s `parseCSRFToken` (meta only; other write callers retain their existing input-first behavior). Response classification requires iOS’s flash/redirect evidence, and rejects error flashes and overload pages.
- `SubscriptionUnsubscribeState.confirm` is invoked only from `SubscriptionsBrowser`’s destructive confirmation. One screen-wide in-flight guard blocks duplicate or parallel row writes; the chosen `SubjectChip` says “Unsubscribing…” and all unsubscribe chips disable until it finishes. Cancel/staging/loading/navigation have no write entry point. Error title/detail/OK follow iOS. The existing `DestructiveConfirmation` accepts an optional subject palette; this page supplies it so its dialog uses the page’s tokens rather than default Material colors. Other callers keep their prior defaults.
- The fake `unsubscribedIds` and every reader of it are deleted. `AccountListViewModel.removeSubscription` removes the actual loaded work and its action only after confirmed success. An emptied later page loads the preceding page; page one stays empty without an extra GET. Named success calls `NamedSubscriptionsLoader.removeSubscription`, removes the loaded row, invalidates older refresh results, and changes to the preceding page only when its visible later page emptied. No automatic whole-index reload or batch write. Moving to another named scope never changes its page from an old continuation; a Works success can still update its retained Works page after a tab switch.
- Same-page refresh keeps loaded rows while it is pending, so a successful write can remove the row and invalidate that older load. Account page reads, ViewModel publication, confirmed-write results, pending dialogs and named loaders are generation-fenced. Visible composition calls `ensureSessionLoaded` after session changes; no background session observer starts account GETs. `AccountListRepository.load` and the default authenticated GET also guard expiry so old reads cannot expire a replacement account.
- `SubscriptionWatermarks` is unchanged, following the actual iOS Works caller. No local saved work, EPUB, Room schema or backup format changes.

## Local demo

Launch the debug app with the existing `--ez kudosDemoLibrary true --ez kudosDemoSignedIn true` extras, then Account → Subscriptions. This is the existing fixture identity, not a real sign-in. Never use the login screen or a live account for this review.

| Tab | Row | Confirmed local response |
| --- | --- | --- |
| Works | A Study in Pink | Success; row goes away |
| Works | Another Fic | Failure; row stays; “Couldn't unsubscribe” alert |
| Works | Paper Cranes | Success |
| Series | My Series | Success; empty Series list |
| Authors | someuser | Success |
| Authors | seriesauthor | Failure; row stays; same alert |

`DemoNetworkInterceptor` answers member POSTs locally: known success ids 1/3/4/5, explicit failures 2/6, unknown ids or invalid token/method also fail locally. The three bundled subscription indexes have a demo CSRF meta and delete-form fields. Successful POSTs change the interceptor’s simulated server state: later index reads omit the matching dt/dd, including tab switches and revisits. No demo write falls through to a socket. Force-stop/relaunch resets that process-local server state. Works keeps its existing three-page fixture; named demo pages have one page. Multi-page retreat is supplied by tests.

## Tests written (not run)

- `AO3IndexUnsubscribeTest`: work/series/user actions come from their served adjacent form, not ids; fresh Works-index meta token overrides another row’s token; exact `_method=delete`, token, CSRF header and referer; one POST; missing displayed form never borrows a neighbor’s action; already-gone fresh row still POSTs its captured action as iOS does; flash/3xx success, flashless 200/error/422/429/transport failure, untrusted actions and missing tokens.
- `AO3UnsubscribeDispatchTest`: session changes inside the real shared pacing wait; no POST dispatch. Its terminal OkHttp application interceptor never calls `proceed`, so even an erroneous dispatch cannot reach the network.
- `SubscriptionUnsubscribeStateTest`: no write on construction/list load, duplicate guard with a held POST, success removes the named row and reports an emptied later page, failure preserves the list and carries iOS’s unconfirmed detail, session changes during GET or POST discard results, screen exit does not cancel the sent POST, and an older held refresh cannot restore a confirmed removal. Terminal in-memory client only.
- `SubscriptionsWorksRemovalTest`: the actual ViewModel with an in-memory Room database and terminal client removes the work/action, loads the preceding page exactly once, and leaves page one empty without another read. No schema changes.
- `NamedSubscriptionsBrowserTest`: real Compose staging/Cancel never POST, exact named/Works confirmations, named later-page success retreats, author failure keeps the row and shows “Couldn't unsubscribe”, Works busy control disables and removes only after AO3’s held local success. Existing named-tab/navigation/refresh tests remain.
- `DemoNetworkBlockTest.demoUnsubscribeSuccessChangesSubsequentIndexesAndFailureKeepsTheRow`: actual bundled indexes and local POST handler, invalid token, success/failure for all scopes, unknown member rejected; terminal interceptor refuses every network fallback.

Passed here: `git diff --check`; read real repository/auth/client/coordinator/form/page/ViewModel/navigation/component symbols; inspected cached Material3 `AlertDialogDefaults` and Compose test matcher/assertion signatures with `javap`; inline HTML fixture checks; checked that `TASKS.md` and branch are unchanged. These are static checks, **not compilation or executable Kotlin test results**. No Gradle/Xcode, sign-in, AO3 contact, commit, push, branch switch, stub, helper script or `.orig` file was used/created.

Claude must run from `android/`:

```sh
./gradlew :app:assembleDebug
./gradlew :app:testDebugUnitTest \
  --tests 'io.github.cidy02.kudos.network.ao3.writes.*' \
  --tests 'io.github.cidy02.kudos.network.ao3.account.*' \
  --tests 'io.github.cidy02.kudos.account.Subscription*Test' \
  --tests 'io.github.cidy02.kudos.account.NamedSubscriptions*Test' \
  --tests 'io.github.cidy02.kudos.network.ao3.DemoNetworkBlockTest'
./gradlew :app:testDebugUnitTest
```

Every compilation, parser, coroutine, Room, Compose and emulator behavior claim needs those runs. Manual fixture-only review: all demo successes/failures above, confirmation/Cancel, busy controls, navigation away during a POST, tab switching/revisiting, Works Updated/Mark All as Seen, Light/Dark/large text, and last-row page retreat (tests supply the multi-page scenario). No visual correctness or live AO3 success is claimed; live writes remain outside this brief.
