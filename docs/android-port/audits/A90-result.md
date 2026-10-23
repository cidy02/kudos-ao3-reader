The read-only sandbox rejected writing `A90-result.md`. No files changed. Review results follow.

**1. `A90-series-session.patch`: four P2 findings**

Android paths below are relative to `android/app/src/main/java/io/github/cidy02/kudos/`.

1. **P2 — Restricted works now trigger new anonymous requests.** `network/ao3/series/AO3SeriesRepository.kt:59`, through `works/DownloadQueue.kt:162`.  
   Signed in, choose Download Whole Series for a series containing an undownloaded members-only work. The authenticated listing includes it; the queue accepts every summary and sends it through `WorkImporter.download`, which requests anonymous metadata and an anonymous EPUB. Previously that work was absent. These are new guest requests and avoidable failures. Apply the restricted-work guard already used by preservation.

2. **P2 — Session changes can leave Work Detail permanently busy.** `network/ao3/series/AO3SeriesRepository.kt:59`; affected caller: `works/WorkDetailScreen.kt:461`.  
   Change or refresh the session while Download Whole Series awaits its GET. `DefaultAO3AuthenticatedClient` throws `CancellationException` on the generation mismatch, bypassing both branches that clear `queuingSeries`. “Fetching series…” and disabled controls remain. Save for Later similarly rethrows cancellation past `runWorkAction` without clearing `working` (`WorkDetailScreen.kt:377`). Clear busy state in `finally` and handle session invalidation without retrying anonymously.

3. **P2 — Parsing and pagination can cross sessions.** `network/ao3/series/AO3SeriesRepository.kt:62`, with pagination at line 37.  
   Log out while the authenticated first page is being parsed on `Dispatchers.Default`, after the client’s generation check. No check follows parsing, so that signed-in page is accepted; the next page is fetched as a guest. Restricted works change pagination offsets, allowing public works to be skipped and producing a mixed-session result. Unlike `detailPage`, this path lacks the post-parse scope check supplied by `AO3PageCache`. Fence the entire listing operation to its opening session.

4. **P2 — Whole-series traversal becomes authenticated bulk scraping.** `network/ao3/series/AO3SeriesRepository.kt:59`, with the all-pages loop at line 36.  
   Signed in, preserve a multi-page series from Library or Work Detail. Every page now uses authentication automatically. This conflicts with the lane’s `docs/AO3_NETWORKING_POLICY.md:50`, which prohibits bulk scraping of logged-in pages and contains no series-preservation exception. Reconcile that scope before landing.

The branch itself selects one GET, adds no POST or retry wrapper, and retains the original signed-out route. A 403 or login redirect propagates without an anonymous fallback. Preservation stops before processing summaries on these failures.

The iOS comparison in the comment is inaccurate: the supplied iOS `AO3Client.swift:1302` and `:1317` call `getHTML`, which uses its anonymous session configuration.

**2. `A90-main.patch`: no additional findings**

The series hunk shares findings 1–4 above. No behavior regression identified in:

- `QueueTagEditContent`: state keys, validation, coroutine ownership, and edit/merge dismissal and confirmation callbacks retained.
- `QueueTagRemovalDialog`: pending-state clearing, removal, and reload ordering retained.
- `AddToCollectionContent`: `workId` keys/effect, immediate membership changes, collection ordering, and caller-owned write scope retained.
- `SaveSearchContent`: caller-owned name, scroll lifetime, Save eligibility, callbacks, and sheet configuration retained.
- `PreferenceHelpContent`: loading/error/success branches, scrolling, selectable text, retry/open callbacks, and dismissal retained.
- Challenge choices test tag: selection, list state, item identity, and dismissal unchanged.

Static review only; no Gradle, tests, runtime UI, sign-in, or AO3 access.

Counts: P1 0 | P2 4 | P3 0 | Total 4 unique findings | Additional UI findings 0.

Codex session ID: 01a16869-5b6e-7a42-8d74-4a0f467bc748
Resume in Codex: codex resume 01a16869-5b6e-7a42-8d74-4a0f467bc748
