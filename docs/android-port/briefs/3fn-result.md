# 3fn result

Status: implementation and three read-only reviews complete; ready for Claude's build/test and UI verification.
Base and final HEAD: `android/agent-codex-3fn` at `b14ba746`; initial tree clean.
Changes are intentionally uncommitted.

Restrictions observed: no commits, pushes, branch switches, sign-in, AO3 traffic,
TASKS.md edits, Room schema changes, backup-format changes, helper scripts or `.orig` files.
The iOS worktree was read only. No Gradle, test suite, emulator or device checks ran.

## Part 1 — A58 leftovers, in requested order

### 1. #7 — Read Aloud media timing: implemented

Confirmed at HEAD: `ReaderSpeechController.publishPlaybackState` used
`PLAYBACK_POSITION_UNKNOWN`; `updateMetadata` supplied no duration.

- Added `reader/ReaderTimeEstimate.kt`, porting iOS's 68.75 seconds per position
  at 1x speech, inverse-rate scaling, unknown-total handling and remaining-count clamps.
- `ReaderScreen` supplies the publication position count and live navigator position;
  `ReaderSpeechController` publishes milliseconds of duration and elapsed time.
  Playback speed is 1 while playing and 0 while paused: the estimated duration
  already includes the speech-rate multiplier.
- `ReaderPlaybackClock` keeps elapsed time continuous between navigator samples
  and paragraph boundaries, freezes it while paused, and rescales it on a rate
  change. New playback and navigator samples reset its anchor. This is needed
  because Android's paragraph queue does not emit iOS's per-utterance locators.
- Added `ReaderTimeEstimateTest`: iOS assertions from
  `KudosTests/ReaderTimeEstimateTests.swift:86` onward (pace, inverse rates,
  duration/elapsed, unknown totals, stale remaining count, faster duration), plus
  pause/resume, paragraph-boundary continuity and rate-change clock assertions.

Limits: timing remains a position-based estimate, not measured speech duration.
The existing paragraph skip controls have no precise Readium speech locator;
verify their system time display, pause/resume, rate changes and lock-screen
controls on a device. The silent-reading position-card formula is unchanged.

### 2. #12 — Complete-sentence chunking: implemented

Confirmed: only paragraph-packing `TextChunker.chunk` existed; its punctuation
split separated honorifics/abbreviations when paragraphs exceeded the size limit.

- Added `sentenceChunks` independently of the default paragraph API, as iOS does.
- Protected English titles, initials and dotted abbreviations; retained terminal
  punctuation and closing quotation marks. Clause splitting now uses iOS's
  comma/semicolon/colon/em-dash rules only when the sentence exceeds the limit.
- Ported the iOS `TextChunkerTests.swift` sentence/comma/honorific/abbreviation,
  default packing and oversized-sentence assertions to `TextChunkerTest`; added
  carriage-return, closing-quote and ellipsis cases.
- Existing engine callers retain the default paragraph API, as before. No new
  regex flags or character classes were introduced.

Limit: the boundary scanner protects the tested English abbreviations; it does
not claim to reproduce Apple's NaturalLanguage tokenizer in every language.

### 3. #11 — Semantic author notes: implemented

Confirmed: TXT/PDF `paragraphsWithAuthorNotes` and HTML's note-container rewrite
produced an author-note aside with no `epub:type`.

- Both conversion paths now produce `epub:type="note"`; the HTML safelist keeps it.
- `EpubBuilder` declares `xmlns:epub="http://www.idpf.org/2007/ops"` on content
  XHTML so the added attribute has a bound namespace.
- Extended `TxtPdfAuthorNoteConversionTest` with the exact aside assertion from
  iOS `AuthorNoteDetectorTests.swift:194`, plus EPUB semantic/namespace assertions;
  extended `AuthorNoteMarkupTest` for sanitized HTML. Existing grouping/order
  assertions remain in place.

### 4. #19 — Bounded prose loading skeleton: implemented

Confirmed: `ReaderPageSkeleton` budgeted lines from screen height, clamped its
line count to 8–18, and shortened interior lines.

- Budgets from the actual `BoxWithConstraints` height, excluding content padding.
- Ported iOS's heading/line/paragraph dimensions and paragraph fill arithmetic;
  paragraphs have full-width interior lines and a short final line.
- Clips the nonempty fallback for tiny containers. The former visible caption
  is replaced by the existing accessibility message, matching iOS's prose-only
  page placeholder.
- Added `ReaderPageSkeletonTest`, porting all four assertions from iOS
  `ReaderPageSkeletonTests.swift:23`: bounded heights, tall-page fill,
  prose-shaped endings and a nonempty tiny-height fallback.

No visual correctness claim: inspect short embedded, phone and tall/tablet
containers, including system-bar insets, on the emulator/device.

### 5. #16 — Shared Dark base: implemented with iOS's card-backdrop exception

Confirmed three separate values: reader #16161A, Material base #191817, and
subject card backdrop #0B0B0D.

**Before editing**, announced the colour impact: Material Dark backgrounds and
base surfaces (unwashed screens/panels, including System mode when dark) change
from #191817 to #16161A; the reader already has that colour. Elevated surfaces
remain distinct. iOS deliberately retains #0B0B0D for washed-card backgrounds
(`UIComponents/AppThemeSurface.swift:70`), so Android's matching subject backdrop
is preserved rather than flattened into the base token.

`ui/theme/Color.kt` now owns the shared `SurfaceDark`; the reader's Dark
`backgroundColor()` reuses it, and Material already uses it for background and
surface. Extended `ThemeTest` with the shared-token, exact-colour, nonblack,
elevated-surface and true-black OLED assertions from iOS `ReaderThemeTests.swift`.

## Part 2 — read-only second reviews

Paths below beginning `android/` are relative to this worktree. iOS paths are
relative to `/Users/cidy02/kudos-ios-polish`. Findings describe HEAD, after reading
the named commits and their current callers/shared transport. No write code was
changed. These are static findings, with proposed offline regression cases;
none was exercised against AO3.

### Findings shared by the reviewed writes

**F1 — P1: a 307/308 can dispatch the POST a second time outside the single-shot
write fence.**

`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3RedirectCookieRelayInterceptor.kt:55`
retains method and body for 307/308, and `:38` calls `chain.proceed` again.
All three reviewed writes reach this interceptor through
`writes/AO3AuthenticatedClient.kt:62` and `AO3Client.kt:226` (both under the same
`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/` directory).
The generation check runs before the original call at `AO3Client.kt:205`, not
before redirected sends. A POST answered with `307 Location: <same endpoint>`
therefore sends its body again; if the session changes while the first response
is pending, the follow-up still uses the first request's explicit cookie.
An off-AO3 307 strips Cookie at interceptor `:86` but still forwards the POST
body. This concerns a second POST, not cancelling an already dispatched first
POST (which policy permits to finish).

This is inherited shared transport behavior, not newly introduced by the three
feature commits. The policy's no-retry/one-POST guarantee is consequently not
end-to-end, despite `AO3RetryPolicy.kt:19` rejecting explicit POST retries and
`AO3Client.kt:97` disabling OkHttp connection retries. Fix in the shared redirect
boundary: refuse method-preserving write redirects (do not weaken the fence or
blindly classify the rejected redirect as success). Suggested offline tests:
307/308 on each destructive write yields one received POST, including a session
change before the redirect and an untrusted redirect destination.

iOS comparison: `Services/AO3RedirectCookieRelay.swift:36` accepts Foundation's
redirect request after changing its Cookie header, with no method/generation
veto. That static seam also deserves review; iOS parity alone does not establish
compliance with the stricter one-POST rule. No iOS transport behavior was run.

**F2 — P2: author subscription/moderation accepts a bare redirect without AO3's
success notice.**

`android/app/src/main/java/io/github/cidy02/kudos/network/ao3/writes/AO3WriteRepository.kt:1260`
returns success for every 300–399 response, even with an empty body and no
notice. A 302 without a usable Location (which the interceptor returns at
`AO3RedirectCookieRelayInterceptor.kt:47`) is a concrete path to that verdict.
Both `submitAuthorSubscription` (`AO3WriteRepository.kt:1109`) and
`submitAuthorModeration` (`:1157`) use this classifier, so they can say
Subscribed/Unsubscribed/Blocked/Muted without the notice required by the brief.
A flashless final 200 is correctly unconfirmed.

Suggested fix: distinguish author action confirmation from the explicit History
notice-or-redirect exception. Add offline tests for bare 302/307/308 and
flashless 200, along with genuine success/error notices, through both author APIs.
The iOS equivalent is weaker still: `Services/AO3AuthorProfileService.swift:970`
accepts any 200–399 without an error flash. Record that parity gap rather than
copying its verdict. History's redirect allowance is expressly documented in the
binding policy and in iOS's `Services/AO3WriteActions.swift:313`; it is not counted
as F2 for Clear History.

### 6. `a5c14a94` — Subscribe and Unsubscribe

Findings: **F1 and F2** above.

Verified static safeguards: `AuthorProfileScreen.kt:271` (under
`android/app/src/main/java/io/github/cidy02/kudos/author/`) synchronously claims
subscriptionBusy before launching; unsubscribe is staged behind the confirmation
at `:554`. Repository `AO3WriteRepository.kt:1103` checks the tap's generation;
`:1112` preserves the served fields except for a fresh token from the referer.
`indexWrite` at `:1228` reads that page, checks generation after the GET at `:1232`,
and `postOnce` dispatches once at repository level at `:1247`. Stale responses
cannot report success at `:1249`; the UI also fences result handling at
`AuthorProfileScreen.kt:287`. Success invalidates same-scope dashboards and
reloads the header (`:292`).

iOS `Services/AO3AuthorProfileService.swift:418` / `:912` uses its scraped form
and shared action fence. Android's fresh token GET is the documented platform
variation. `AuthorSubscriptionWriteTest` covers served fields, fresh token,
stale generation before/during GET and unconfirmed 200, but not F1/F2.

### 7. `b8bc9aed` — Mute and Block

Findings: **F1 and F2** above.

Verified static safeguards: `AuthorProfileScreen.kt:319` starts the confirm-page
GET on a tap; `AO3WriteRepository.kt:1123` checks session before it, `:1134`
checks afterward, and `:1136` reports AO3's error before parsing a form.
`AO3WriteFormParser.kt:178` extracts heading, notice, button labels, token,
action and fields. `AuthorProfileScreen.kt:568` presents the confirmation and
`:579` submits only on Yes; pending forms reset with route/session at `:168`.
The send at `AO3WriteRepository.kt:1157` posts that form without another GET;
`:1150` and the shared dispatch boundary check generation. The UI result fence
is `AuthorProfileScreen.kt:335`.

iOS `Services/AO3AuthorProfileService.swift:439` / `:466` / `:925` has the same
GET → native confirmation → form POST sequence. Its submit snapshot solves a
SwiftUI dismissal-order issue; Android's click closure already holds `form`.
`AuthorModerationTest` covers parse/undo/refusal, GET-only preparation, stale
submission generation, one repository POST and flashless 200, but not F1/F2.

### 8. `c2442cd6` — Clear History

Finding: **F1** above. No additional History-specific defect established.

`android/app/src/main/java/io/github/cidy02/kudos/account/AccountWorksListScreen.kt:238`
requires destructive confirmation; `SubscriptionUnsubscribeState.kt:43` claims
busy before suspending, checks its opening session, and checks again before
mutating the list at `:48`. `AO3WriteRepository.kt:1207` captures the session,
`:1215` requests `/readings/confirm_clear`, and the single repository POST sends
only the fresh meta token to `/readings/clear`. Shared `indexWrite`/dispatch
checks fence a session change during token fetch/pacing. Error/overload pages
fail; flashless 200 is unconfirmed. Success empties the local list at
`AccountWorksListScreen.kt:246`, without a follow-up History read. Confirmation
and cleared state reset with the session at `:170` and `:175`.

iOS `Services/AO3WriteActions.swift:280` and `:313` have the same fields and
notice-or-redirect verdict, as expressly permitted by the binding policy.
`AO3HistoryDeleteTest` covers request shape and no-token/error/unconfirmed
responses; a dedicated Clear History session-change-during-GET/pacing test and
F1 redirect test remain valuable coverage gaps, not separately established bugs.

## Verification and handoff

- `git diff --check`: passed after implementation and repeated at handoff.
- Read the changed code/callers and the named iOS assertions; inspected all three
  write paths and their shared auth, retry, response and redirect code.
- No compilation or executed unit/UI tests. No claim that the new Compose layout
  or MediaSession behavior has been seen on screen.
- Claude: run the Android compile/test gate, especially `ReaderTimeEstimateTest`,
  `TextChunkerTest`, `ReaderPageSkeletonTest`, `ThemeTest`,
  `AuthorNoteMarkupTest`, `TxtPdfAuthorNoteConversionTest`, and existing
  `ReadiumSettingsAdapterTest` / converter regressions. Then visually inspect
  skeleton bounds and Dark surfaces and check media time/rate/pause on-device.
- Decide and fix review findings F1/F2 in a separate authorized write/transport
  change; all Part 2 code remains read only in this patch.
