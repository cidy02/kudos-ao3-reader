# A34 Audit Result: Codex's Cached AO3 Pages

## 1. Requests

**Stranger Profile (not own profile, not dashboard):**
- Dashboard read: `io.github.cidy02.kudos.author.AuthorProfileScreen.kt:198` vs `kudos-ao3-reader/Services/AO3AuthorProfileService.swift:590`
- Works tab read: `io.github.cidy02.kudos.author.AuthorProfileScreen.kt:205` vs `kudos-ao3-reader/Services/AO3AuthorProfileService.swift:664`

**Own Profile (from works/stranger perspective):**
- Dashboard read: `io.github.cidy02.kudos.author.AuthorProfileScreen.kt:198` vs `kudos-ao3-reader/Services/AO3AuthorProfileService.swift:590`
- Works tab read: `io.github.cidy02.kudos.author.AuthorProfileScreen.kt:205` vs `kudos-ao3-reader/Services/AO3AuthorProfileService.swift:664`
- User stats read: absent in Android vs `kudos-ao3-reader/Services/AO3AuthorProfileService.swift:337`

**Dashboard (My Dashboard view):**
- Dashboard read: `io.github.cidy02.kudos.author.AuthorProfileScreen.kt:198` vs `kudos-ao3-reader/Services/AO3AuthorProfileService.swift:590`
- User stats read: absent in Android vs `kudos-ao3-reader/Services/AO3AuthorProfileService.swift:337`

**Writes in the patch:**
None were introduced in the patch; the brief states Android author writes were handed off to the web.

## 2. Verdicts and failures

**Write Verdicts (Inbox write modified to clear cache):**
- Success condition: `error == null` at `io.github.cidy02.kudos.network.ao3.inbox.AO3InboxRepository.kt:85` vs `(200 ... 399).contains(status)` at `kudos-ao3-reader/Services/AO3AuthorProfileService.swift:946`
- Refusal message (inbox): `"AO3 couldn't update your Inbox."` at `io.github.cidy02.kudos.network.ao3.inbox.AO3InboxRepository.kt:83` vs `"AO3 didn't accept the \(form.kind.rawValue) action."` at `kudos-ao3-reader/Services/AO3AuthorProfileService.swift:925`

**Read Failures (Fallback to Stale Cache):**
- Handled errors: `error.allowsPageFallback()` at `io.github.cidy02.kudos.network.ao3.AO3PageCache.kt:81` vs `catch { ... }` at `kudos-ao3-reader/Services/AO3AuthorProfileService.swift:70`

## 3. Words on screen

- Cached banner text: `"Showing cached AO3 data"` at `io.github.cidy02.kudos.ui.components.CachedAO3DataRow.kt:23` vs `"Showing cached AO3 data"` at `kudos-ao3-reader/Features/Authors/AuthorProfileView.swift:101`

## 4. Second taps and stale answers

**Stops a second tap sending a second request:**
- Read cancellation: `loadJob?.cancel()` at `io.github.cidy02.kudos.account.AccountInboxViewModel.kt:111` vs `AO3RequestCoordinator.shared.withSlot` at `kudos-ao3-reader/Services/AO3Client+Authors.swift:192`
- Write guard: `if (state.isPerformingBulkAction) return` at `io.github.cidy02.kudos.account.AccountInboxViewModel.kt:280` vs `guard ... !isPerformingModeration else { return }` at `kudos-ao3-reader/Services/AO3AuthorProfileService.swift:439`

**Stops a late answer after sign-out/session change:**
- Read guard: `if (scope(auth) != viewerScope) throw CancellationException()` at `io.github.cidy02.kudos.network.ao3.AO3PageCache.kt:47` vs `guard isCurrent() else { throw CancellationError() }` at `kudos-ao3-reader/Services/AO3AuthorProfileService.swift:51`
- Write guard: `if (repository.viewerScope() != expectedViewer) return@launch` at `io.github.cidy02.kudos.account.AccountInboxViewModel.kt:295` vs `guard isCurrent(operation.expected, auth) else { return }` at `kudos-ao3-reader/Features/Account/AO3InboxModel.swift:458`

## 5. The cache

- Key structure: `Key(val url: String, val scope: Scope, val kind: Kind)` at `io.github.cidy02.kudos.network.ao3.AO3PageCache.kt:18` vs `struct Key { let url: URL; let authenticationScope: String }` at `kudos-ao3-reader/Services/AO3Client+Authors.swift:595`
- Lifetimes (fresh/stale): `5 * 60 * 1000L` / `24 * 60 * 60 * 1000L` at `io.github.cidy02.kudos.network.ao3.AO3PageCache.kt:13` vs `5 * 60` / `24 * 60 * 60` at `kudos-ao3-reader/Services/AO3Client+Authors.swift:607`
- Size limit: `128` at `io.github.cidy02.kudos.network.ao3.AO3PageCache.kt:14` vs `128` at `kudos-ao3-reader/Services/AO3Client+Authors.swift:608`
- Dashboard read usage: `pageCache.read` at `io.github.cidy02.kudos.network.ao3.author.AO3AuthorRepository.kt:57` vs `AO3AuthorProfileFetcher.page` at `kudos-ao3-reader/Services/AO3AuthorProfileService.swift:590`
- Inbox read usage: `pageCache.read` at `io.github.cidy02.kudos.network.ao3.inbox.AO3InboxRepository.kt:46` vs `AO3AuthorProfileFetcher.page` at `kudos-ao3-reader/Features/Account/AO3InboxModel.swift:129`
- Series read usage: `pageCache.read` at `io.github.cidy02.kudos.network.ao3.series.AO3SeriesRepository.kt:50` vs `AO3AuthorProfileFetcher.page` at `kudos-ao3-reader/Features/Authors/AO3SeriesDetailView.swift:242`
- Post-write removal (Inbox): `pageCache.removePages` at `io.github.cidy02.kudos.network.ao3.inbox.AO3InboxRepository.kt:89` vs `AO3AuthorProfileFetcher.invalidateInbox` at `kudos-ao3-reader/Features/Account/AO3InboxModel.swift:468`
- Failure fallback condition: `error.allowsPageFallback()` at `io.github.cidy02.kudos.network.ao3.AO3PageCache.kt:66` vs `catch { ... staleValue }` at `kudos-ao3-reader/Services/AO3AuthorProfileService.swift:70`

| # | Severity | Kotlin | Swift | Issue |
|---|---|---|---|---|
| 1 | P2 | `io.github.cidy02.kudos.author.AuthorProfileScreen.kt:198` | `kudos-ao3-reader/Services/AO3AuthorProfileService.swift:337` | iOS fetches userStatsURL for own profile/dashboard; Android does not make this request. |
| 2 | P2 | `io.github.cidy02.kudos.network.ao3.AO3PageCache.kt:81` | `kudos-ao3-reader/Services/AO3AuthorProfileService.swift:70` | iOS falls back to stale cache on 404/403 errors; Android drops the cache and fails. |

## Triage (Claude, 2026-10-10)

Both rows checked against the code on both sides. Neither is a fault in the 3ce patch.

1. **Real, but older than 3ce and not a fault: a missing feature, P3.** iOS's own profile
   reads `/users/<name>/stats` once when the reader opens their own profile
   (`AO3AuthorProfileService.loadOwnStats`, own account only, silent on failure) and shows
   the career figures in the hero (`AuthorProfileView.swift:348`). Android has no such read
   and shows no such figures. One read of the reader's own page on an explicit opening, so
   within the networking policy's rule for signed-in reads; the policy's sentence "Account
   Dashboard loads only its dashboard page" does not mention it and should. **To a small
   Codex brief** (the own profile's stats in the hero), not fixed here.
2. **Rejected: deliberate.** Android shows a kept page only after a failure that is not AO3's
   own answer (no connection, a timeout, 5xx, "AO3 is busy"), and never after a 403, a 404
   or a sign-in page: brief 3ce line 108, `AO3Error.allowsPageFallback`. iOS's `catch`
   takes every error, so iOS shows a day-old copy of a page AO3 now says is gone or
   forbidden. That is the difference to close, **on iOS**: listed under §5c item 6 in the
   Living Prompt as a small iOS fix with a test.

