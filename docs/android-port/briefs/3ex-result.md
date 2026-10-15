# 3ex result

Changes remain uncommitted on `android/agent-codex-3ex`, based on `e44f64d6`.

- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3RequestCoalescer.kt`:
  each entry now owns its operation job and waiter count. Register before starting;
  unregister in a cancellation-proof `finally`; the last waiter removes the entry
  and cancels its job. Completed results cannot attract new callers, and an older
  entry's cleanup cannot remove its replacement. A cancelled operation scope also
  completes the waiting result even if its lazy job never started.
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3PageCache.kt`:
  `bypassCache` wraps only `fetch` in the new `AO3UncoalescedRead` coroutine context.
  The coalescer runs such an operation directly in the caller, without joining or
  registering it. Chose “bypassing reads never coalesce”: two shared implementation
  points cover author, series-detail and Inbox repositories, through public and
  authenticated GETs, without changing their interfaces, headers or individual
  fetch closures. Ordinary concurrent GETs still share by URL and headers.
- `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3Client.kt`:
  check cancellation before each HTTP attempt and again after pacing, before
  dispatch. Existing pacing intervals, concurrency limits, retry rules and write
  paths remain intact; POSTs never enter the coalescer.
- `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/AO3NetworkingCoreTest.kt`:
  added five tests; existing coalescing test bodies are unchanged.
  - `lastWaiterLeavingCancelsTheOperationBeforeItsFetch`: two joined waiters;
    cancelling the first leaves the operation alive, cancelling the second stops
    it before fetching, evicts it, and allows a new request on that key.
  - `cancellingOneWaiterLeavesTheSharedOperationForTheOther`: the remaining waiter
    receives the shared answer from exactly one fetch, then the entry is evicted.
  - `lastWaiterLeavingDuringPacingPreventsDispatch`: actual client/coordinator,
    paused before dispatch; cancelling both waiters cancels pacing and sends zero
    MockWebServer requests, including after releasing the pacing gate.
  - `lastWaiterLeavingDuringBackoffPreventsRetry`: after one local HTTP 500,
    cancelling the sole waiter cancels backoff and prevents the second request.
  - `bypassingPageReadDoesNotJoinAnOrdinaryGetStartedBeforeRemoval`: holds an
    ordinary GET response, removes the page, and starts a bypassing cache read of
    the same URL/headers. The latter makes its own local request, returns and
    caches the post-write body before the first response is released; that first
    GET still returns its earlier body without replacing the fresh cache entry.

Checked by source review of the shared client, coordinator, cache and repository
fetch paths; `git diff --check` passes. Gradle, compilation, JUnit/Robolectric and
device/background behavior were not run, per the brief. Claude still needs to
build and run the networking/cache suites, including the unchanged existing
coalescing tests. No sign-in, AO3 contact, commit, push, branch switch, task-board
edit, schema or backup-format change was performed.
