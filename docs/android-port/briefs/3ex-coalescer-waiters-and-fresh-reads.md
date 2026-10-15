# Brief 3ex: the shared GET coalescer: last waiter leaving, and reads that must not join (A37 F3, A51 F4)

Rules (binding): work only in this worktree (`~/kudos-agent-codex`, branch
`android/agent-codex-3ex`, at the lane's `e44f64d6`); don't commit, push, or switch branches;
never sign in and never contact archiveofourown.org; no stub files; no helper scripts or
`.orig` files left behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room
schema. Your sandbox can't run Gradle: Claude builds, tests and commits afterwards, so make
what you write compile by reading the code around it. End with a short note,
`docs/android-port/briefs/3ex-result.md`: what you changed, file by file, what each test proves,
and what you could not check. The networking policy is binding: `docs/AO3_NETWORKING_POLICY.md`
(pacing never weakened; a write only on a tap, once).

## Two findings of yours, both in `network/ao3/AO3RequestCoalescer.kt` and its callers

1. **A51 F4.** `coalesce` runs the shared operation in its own scope; a caller cancelled while
   waiting (the Favorites › Authors round when the app goes to the background, 3ej) stops
   waiting, but the operation goes on: it can still take its pacing slot, send its GET, or
   start a retry, after nobody wants it. Make the operation end when its **last** waiter has
   left (count the waiters; a waiter that leaves and is the last cancels the operation; a
   waiter that arrives while it runs joins it as now). An operation whose request was already
   sent may finish; nothing new may start for nobody.
2. **A37 F3.** After a write, `AO3PageCache` removes the pages it changed and the opener reads
   them again with `bypassCache = true`. That read can join a GET of the same page begun
   **before** the write (same URL and headers), and take its pre-write answer, which the cache
   then installs as fresh. Give such a read a way not to join an operation that began before
   it (for example: a read that bypasses the cache never joins; or the coalescing key carries
   an epoch the page cache advances when it removes that page). Choose the smallest change
   that reaches every repository's fetch without editing each one by hand, if you can; say
   which you chose and why.

Keep: identical concurrent reads that are both ordinary still share one request (that is the
point of the coalescer, and its tests say so). Writes never pass through it.

## Tests (Robolectric or plain JUnit, in the style of `AO3NetworkingCoreTest`)

- Two waiters on one key; cancel both before the operation's request starts: it never runs
  its fetch. Cancel one: the other still gets the answer.
- A bypassing read started after an ordinary read of the same page is in flight does not
  receive that earlier read's answer (it makes its own request).
- The existing coalescing tests still pass unchanged.
