# Brief 3bk — Claim and Release

## iOS writes read again, line by line

Read-only reference: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/Challenges/PromptMemeView.swift` (`promptActionRow`, `promptActionButton`, `claim`, `release`, `loadPrompts`), `Services/AO3ChallengeActions.swift` (`claimPrompt`, `releasePrompt`, `throwIfChallengeWriteFailed`), `Services/AO3WriteActions.swift` (`fetchCSRFPage`, `writeRequest`), `Services/AO3CollectionActions.swift` (`collectionWriteVerdict`), `Models/AO3ChallengeModels.swift` (`AO3ChallengeURL`). Read both 3bi and 3bg including their landing notes and the networking policy before implementation.

Controls follow the served prompt state, without an owner gate: own claim (`claimedByCurrentUser`, parsed Drop Claim ID) shows **Claimed by you** at left and **Release** at right. Otherwise `canClaim` shows **Claim** at right, even if other people claimed it. Otherwise a claimed prompt shows browser-only **Fill it**. iOS wins over the brief's narrower “unclaimed prompt”: multiple claims are allowed. No New prompt is added in this brief. Claim is an accent capsule with on-accent text; Release is accent text on accent at .14. Labels are 12.5pt semibold; action row has 2pt top padding, button horizontal padding 14pt and nominal height 34pt, spacing 6pt. The selected button retains its word with a small spinner; all three kinds of card control disable whenever `promptInFlight != nil`. Cards remain unchanged while waiting. Errors clear when another action starts.

Claim: sign-in guard → authenticated GET `/collections/SLUG/requests` (page 1, even when viewing another page), read fresh `meta[name=csrf-token]` → single POST `/collections/SLUG/claims`. Ordered fields: `authenticity_token=TOKEN` from that meta, `prompt_id=String(prompt.id)` from the served numeric claim-form query. No `_method`, commit, extra form fields or query copied to the POST.

Release: own `claimID` required by the view; sign-in guard → authenticated GET `/collections/SLUG/claims?for_user=true`, fresh meta token → single POST `/collections/SLUG/claims/ID`. Ordered fields: `_method=delete`, `authenticity_token=TOKEN`; ID comes from the served Drop Claim link. No prompt ID or extra fields.

Both use existing authenticated Cookie and single-sourced User-Agent; POST headers are `Content-Type: application/x-www-form-urlencoded; charset=UTF-8`, `X-CSRF-Token: TOKEN`, `Referer: TOKEN_PAGE`. `ajax: false`: no `X-Requested-With` or Ajax Accept. Existing authenticated client/session-generation fence and trusted-host redirect relay own dispatch. Neither POST is retried or coalesced. This brief adds no retry around either token GET; the existing shared GET policy retains its permitted transient transport retries.

The actual iOS verdict (quoted from `AO3AuthService.collectionWriteVerdict`) is:

```swift
if let error = AO3Client.writeErrorMessage(in: body) {
    return .rejected(error)
}
if AO3Client.writeSuccessMessage(in: body) != nil { return nil }
if (300...399).contains(status) { return nil }
guard (200...299).contains(status) else {
    return .rejected(fallback)
}
return .unconfirmed
```

Thus AO3 error text wins even over a notice/redirect. A success flash or bare 3xx confirms; a bare 2xx does not. Non-2xx without AO3 text uses **AO3 couldn't claim that prompt.** / **AO3 couldn't release that prompt.** Screen prefixes are exactly **Couldn't claim that prompt: REASON** / **Couldn't release that prompt: REASON**, in a dismissible warning panel. Signed out: **Log in to AO3 first.** Missing meta token: **Couldn't prepare the request. Try again, or open the work on AO3.** (the executed helper throws `AO3WriteError.noCSRFToken`, not the unused challenge-specific variant). Unconfirmed: **AO3 replied but didn't confirm the change went through. Check on AO3 before trying again.** Transport/token-read errors propagate their existing user-facing reason. No success sentence is shown.

On confirmation the view calls `loadPrompts(page: currentPage)`: one GET of the current listing to obtain authoritative claim state/counts, retaining the old cards while loading and on reload failure. Then it clears the in-flight flag. On refusal it does no reload, retains the card, displays the prefixed reason, clears the flag. Schedule is best effort and remembers an attempt before reading: only an owner, only without a known date, once per opening/refresh. The current iOS `readsSchedule` and 3bi landing note now agree; page changes and action reloads never repeat a missing/failed date lookup.

## Policy basis for each write

Claim and Release each follow the policy's **Writes** rule: an explicit reader tap prepares a fresh authenticated CSRF page then submits one session-fenced POST, never retried/coalesced. The **Host allow-list** rule requires `AO3RedirectCookieRelay.isTrustedUrl` for page-derived action/link addresses and existing shared client dispatch; no new HTTP client. Their two token pages and the one success-only current-page reload are foreground, bounded reads for the selected collection under **What agents must NOT implement**'s explicit-navigation allowance. No settings read to a non-owner, background read, page walk or write on navigation/refresh.

## Decided without asking

- Extend existing Prompt Meme URLs/parser, write repository, state, screen and demo interceptor; wire the container's existing write repository. In-memory only, no Room or backup change.
- Reuse Summer's two original page fixtures. Add fresh-token meta markup to them and a complete local claims-page answer in the demo implementation. Local Claim success = Lanterns after closing (701); refusal = anonymous bottled-weather prompt (704); Release success = A borrowed constellation (claim 801) or the locally created claim. No extra fixture files/dependencies.
- Use token capsule controls with the iOS 34dp nominal fill inside a 44dp minimum hit target, and natural wrapping/height at accessibility scale. Add a computed `KudosTokens.errorInk` (existing AO3 red for Light/Sepia, brighter red for Dark/OLED) for the dismissible iOS warning; no Material error default or settings/persistence change. Preserve existing page/filter/metadata layout and pushed shell chrome.

## Open questions

- Sparing concurrency choice: disable card actions during a listing load too, and refuse page/refresh loads while a write plus its confirmation reload is in flight. iOS disables actions for `promptInFlight` and pages for listing loading; these extra guards prevent overlapping stale-page actions/refreshes and send fewer reads. Local filter changes remain available. No blocking question. iOS controls follow AO3's `canClaim`, including already-claimed prompts; follow iOS. Keep the footnote's available Claim/Release sentence, omit its New prompt sentence until that separate brief.

## Implementation

- `AO3WriteRepository.claimPrompt` / `releasePrompt` share a small preparation helper and the existing `collectionWriteVerdict`, `writeHeaders`, `postAuthenticatedInSession` path. Meta-only token, exact iOS fields/order/referers, one POST, no verification read in the write repository itself.
- `AO3PromptMemeParser` accepts page-derived Claim/Drop Claim addresses only through `AO3RedirectCookieRelay.isTrustedUrl`; the endpoints are constructed from the selected collection and numeric IDs like iOS, never posted to a captured foreign address. No additional page read to decide control visibility.
- `AO3PromptMemeState.changeClaim` takes the currently loaded row, validates the served action, sets the shared busy ID before suspending, retains its data, and reloads only `data.currentPage` on confirmation. Owner date attempt/known-date state is retained across that reload; refusal makes no listing read. Screen disposal cancels preparation/reload; an already-dispatched single POST completes through the existing NonCancellable write path without publishing to the departed/session-replaced screen. Failed confirmation reload retains the old page and its existing page-load warning; it never resends a POST.
- `AO3PromptMemeScreen` draws exclusively from collected state, retains `ProvidePushedShellChrome`, metadata, panels, filters and page bar. Custom token capsules show Claim/Release and the selected spinner. Own claim text and Release share the iOS row normally, stack at accessibility size. Error text wraps, uses explicit 18sp line height, and dismisses without a request. Every added label has explicit line height. Available Claim/Release footnote sentence restored; New prompt/editor remain outside this brief. AppNavHost passes `container.writeRepository`.
- `DemoNetworkInterceptor` owns Summer's mutable local claim server. It reads the existing original fixtures, accepts only the two exact form shapes, returns notices/refusal HTML, changes served listing markup after success, and resets with a fresh interceptor/process. Missing fixtures/unknown pages/claims stay terminal local answers. No new fixture files or helper scripts.

## Demo taps (for Claude, not executed here)

Launch the fixture-only signed-in demo in airplane mode with the existing extras `kudosDemoLibrary=true`, `kudosDemoSignedIn=true`, `kudosDebugRoute=nav:ao3-prompt-meme/summer_meme?title=Summer%20Prompt%20Meme` (participant: no date read). Or open **Collections → Summer Prompt Meme → Manage → Prompts** (owner: the existing schedule reads once).

1. **All → Lanterns after closing → Claim**: local notice confirms, then the same page reloads; that card shows **Claimed by you / Release**, and its unclaimed count drops.
2. The anonymous **A market stall sells bottled weather… → Claim** (already claimed by two others): local refusal **Couldn't claim that prompt: This prompt is closed to new claims.**; card/counts stay unchanged. Dismiss the warning with its close control; no request.
3. **A borrowed constellation → Release**: local confirmation, same page reload; own claim disappears and **Claim** becomes available. The locally claimed Lanterns card can also be released.
4. **Next Page → The orchard beyond the timetable → Claim**: token read is page 1 as on iOS; success reload is page 2 only. Relaunch to restore all original fixture claim states.

## Offline tests written; Claude must run them

- `AO3PromptMemeWritesTest`: recording shared authenticated client asserts both URLs, each ordered field, meta rather than input token, header sources and one token GET/one POST. Exercises success flash, bare redirect, AO3 refusal/error precedence, unconfirmed 2xx, fallback refusal, failed token read, missing meta, signed out, exact iOS feedback, unchanged cards, busy guards, success-only current-page reload for owner/participant with known/missing dates, failed reload, no POST on opening/page/refresh, foreign/insecure controls, cancellation/session replacement. Terminal OkHttp interceptors verify actual form encoding, Content-Type/UA/Cookie/CSRF/Referer/non-Ajax headers, no retry on 429/503 and the pacing/session fence. Every terminal interceptor returns or throws before a socket can be reached; pure clients never make HTTP calls.
- Existing `AO3PromptMemeTest` stays the parser/read/schedule suite, now receiving a write repository backed by a recording fake that throws if navigation writes unexpectedly. Shared fake supplies held POST/reload gates for the new tests.
- `AO3PromptMemeScreenTest`: keeps its tall window, NATIVE graphics and 15-second waits. New held Claim and Release checks cover spinner, unchanged cards, disabled other controls, and replacement after reload; refusal/dismiss checks preserve own card and exact sentence. Existing four-theme 2× font cases now inspect Claim, Release and warning layouts with `!didOverflowHeight` and nonellipsized last line. Row tags scope repeated Claim/Release labels. Existing navigation/filter/page checks still prove zero POSTs; their old assertion that Claim/Release do not exist is removed.
- `DemoPromptMemeTest`: terminal fixture interceptor checks local Claim success/refusal, Release success, new listing markup on both pages, missing assets, and process/interceptor reset. Existing initial native/browser fixture equivalence checks remain.

## Verification and handoff

Static symbol/call-site review against the real iOS and Android declarations completed; `git diff --check` passes. Initial tree was clean on `android/agent-gemini-3bk`; all edits remain uncommitted in this worktree. No Gradle/Xcode, network, sign-in, commit, push, branch change or TASKS edit. No helper script, .orig, schema, backup or iOS reference edit.

**Needs Claude's run:** compile debug/release Android and test sources; execute the three Prompt Meme account suites plus `DemoPromptMemeTest` (then the normal Android gate); verify read/POST counts, verdicts, pending-action guards, session cancellation and wire assertions at runtime. Run the airplane-mode demo taps above and screenshot Light/Dark/Sepia/OLED at normal and accessibility font size. All execution/visual claims remain unverified here; no test-pass or visual correctness claim. Live AO3 writes remain unexercised as in the reference and 3bg landing; this task never contacts AO3.

**Landing note (Claude, 2026-10-08).** Landed with one change. Gate green (1,952 tests); it
compiled and passed first time.

**Both requests were read against iOS's code line by line** (`AO3ChallengeActions.swift`
`claimPrompt` and `releasePrompt`):

- Claim: one fresh read of the collection's requests page for its token, then one POST to
  `/collections/<name>/claims` with `authenticity_token` and `prompt_id`.
- Release: one fresh read of `/collections/<name>/claims?for_user=true` for its token, then
  one POST to `/collections/<name>/claims/<claim>` with `_method=delete` and
  `authenticity_token`.
- Neither is retried. Both addresses are built by the app, so they are AO3's own. After a
  success the current page is read once more, as iOS, and the close date is not asked for
  with it. The verdict is the one the collection writes share, with iOS's two fallback
  sentences.

**Changed on landing.** Codex added a colour token (`KudosTokens.errorInk`) for the refusal
sentence. The screen uses the red the tag set screen already uses for a refusal, and the
shared tokens are untouched.

Seen on the emulator in airplane mode against the demo's local answers (Dark): Claim on
"Lanterns after closing" (the header goes to "0 unclaimed", the card to "Claimed by you" with
Release); Release on it (back to "1 unclaimed" and Claim); Claim on the anonymous prompt,
which the local answer refuses (the card and counts stay). **Not seen: the refusal's
sentence**, which is drawn above the list and was off screen with the card.

**A fault in both apps, found here:** a refused Claim or Release shows its sentence under the
header, above the cards (iOS `PromptMemeView.swift:126`, the same on Android). When the card
is further down the list the reader taps and sees nothing happen. To fix on both: bring the
sentence into view, or draw it at the card. In §5c of the Living Prompt.

**Never run against AO3**, like iOS's own two writes.
