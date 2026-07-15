# AO3_NETWORKING_POLICY.md

AO3 has no API; Kudos scrapes public HTML. Respectful access is a hard product requirement — community trust is the whole ballgame. Confirmed as of 2026-07-10.

## The rules (all implemented — keep them true)

| Rule | Implementation |
|---|---|
| One identifiable User-Agent, with contact | `AO3RequestDefaults.userAgent` (`AO3AuthService.swift`): browser-like base + `KudosReader/<version> (+https://github.com/cidy02/kudos-ao3-reader)`. **Single-sourced** — per-request headers override session defaults, so a second definition forks the app's identity. |
| Request pacing | `AO3Client.pace()`: slot-claiming, ≥0.6s between request **starts**, covering all four touchpoints (GET / auth GET / write POST / EPUB download), retries included. Actors are reentrant — the actor alone does NOT serialize. |
| Concurrency cap | `AO3RequestCoordinator` (3 slots) wraps fan-out callers (fandom catalog, metadata refresh). Cancellation-aware FIFO. |
| Coalescing | `RequestCoalescer` — anonymous GETs by URL (`fetchData`), authenticated GETs by URL+Cookie (`authenticatedHTML`). De-duplicator, not a cache. |
| 429 | Typed `AO3Error.rateLimited(retryAfter:)`; retried with backoff honoring `Retry-After`; on writes it is surfaced to the user, never auto-retried. |
| Retry policy | `withRetry`: max 2 retries, exponential 0.5s→1s→2s; ONLY transient failures (5xx, 429, transport drop). 404/403/other-4xx/parse never retried. |
| 403 | `AO3Error.forbidden`, never retried (hammering a CDN block prolongs it). |
| 404 | `AO3Error.notFound` → callers mark `ao3Unavailable`, keep local data. |
| Writes | `submitWrite` is single-shot: never retried, never coalesced (double-kudos/comment risk). CSRF via `authenticatedPageHTML`. |
| Refresh throttles | Tag enrichment: `needsAO3Refresh` + 24h attempt cooldown (`lastTagRefreshAttemptAt`). Update checks: WIP-only, 6h per-work (`lastUpdateCheck`, stamped on failure too). Foreground folder-sync: 60s gate. |
| Batch behavior | Strictly sequential: `DownloadQueue` one at a time; series preservation sleeps 2s/work (`preservationRequestPauseNanos`), cancellable; Browse bulk actions resolve one-by-one and cancel on view exit. |
| Local-first | Every enrichment path checks local state first; the search index is built from local data only; `existingWork` pre-checks avoid re-downloads. |
| Cancellation | `Task.sleep`/URLSession propagate `CancellationError`; coordinator wakes cancelled waiters; batch loops stop (never count cancellations as failures). |
| Author profiles | Fetch only after an explicit byline/profile tap. Dashboard + selected Works tab load first; Series/Bookmarks/About and later pages load on demand. `AO3AuthorPageCache` is capped at 128 entries, uses a 5-minute TTL keyed by full URL and authentication scope, and keeps at most 24 hours of same-scope stale fallback; stale data never crosses accounts or hides session expiry. Scope/tab changes cancel superseded loads. Block/mute: GET AO3's confirm page once, native confirm dialog, single-shot POST of that form (never open the web form, never retry writes). |
| Inbox metadata | Only after the user visibly opens Activity › Inbox, hydrate the unique work ids on that rendered page so creator badges and the work-summary destination are accurate. Local/profile/auth-scoped cache data wins first; unresolved ids load strictly sequentially through `AO3RequestCoordinator` + `AO3Client` pacing. The view owns cancellation, the cache is capped at 128 and isolated by account **and session generation** (a same-username relogin never reuses private HTML/forms), and a systemic error stops the batch. Never prefetch Inbox from Overview, follow pagination, or poll in the background. |

## Parser fragility assumptions

- All parsing is SwiftSoup over live HTML, ported from `ao3_api` selectors (`AO3Client.swift` header). Assume AO3 markup can change: parse failures must degrade to `AO3Error.parse`/empty results and **never** mutate or delete local records.
- Logged-in/username detection selectors are duplicated between `LiveAO3SessionValidator` (SwiftSoup) and `AO3WebLoginCoordinator.inspectPage()` (in-page JS) — change both or neither (`AO3AuthService.swift:101` note).
- Locked/restricted works return empty tag groups on a 200 — treated as "keep EPUB tags, retry after cooldown", not as an error.
- Author index parsers distinguish recognized empty AO3 lists from unrecognized markup; parser drift is an error/retry state, never a fabricated empty profile.
- Comment and chapter-index parsers likewise require AO3's authoritative
  `#comments_placeholder` + direct `ol.thread` / `ol.chapter.index` landmarks.
  Only a present, structurally empty container is empty; login/interstitial or
  missing/unexpected markup throws instead of fabricating "No Comments Yet."

## What agents must NOT implement

- No parallel request fan-out outside `AO3RequestCoordinator.withSlot`; no bypassing `AO3Client` with raw `URLSession` calls to AO3 (the auth validator's single launch request is the one sanctioned exception).
- No retry loops around writes; no auto-retry UI for kudos/comments.
- No background polling beyond the existing BGTask folder-sync refresh; no periodic full-library metadata sweeps.
- No background or bulk scraping of logged-in pages. Authenticated reads are limited to the user's own account lists, pages opened through explicit profile/work navigation, and the bounded visible-page Inbox metadata hydration documented above; no crawling/archiving features.
- No removal/weakening of: pacing, cooldowns, Retry-After honoring, or the contact UA.
- Never delete/modify local works in any network error path (grep-audited invariant — keep it grep-clean: no `softDelete`/`hardDelete` reachable from a `catch`).

## Still unverified (be honest about it)

- Write actions (`AO3WriteActions`) have never been exercised against a live AO3 session — a release gate item, not an agent task.
- Real-device background-refresh scheduling (BGTask) — simulator-verified registration only.
