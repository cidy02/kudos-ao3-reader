# Brief 3fn: A58's deferred reader items, then three owed write reviews

Rules (binding): work only in this worktree (`~/kudos-agent-codex`, branch
`android/agent-codex-3fn`, at the lane's HEAD named in the dispatch); don't commit, push, or
switch branches; never sign in and never contact archiveofourown.org; no stub files; no helper
scripts or `.orig` files left behind; **don't edit `TASKS.md`**. No Room schema or
backup-format change (stop and say so if one seems needed). Your sandbox can't run Gradle:
Claude builds, tests and commits, so make what you write compile (`SavedWork` needs an
`author`; give test works a fixed millisecond `dateAdded`). **Write your result file early
and keep it current**: `docs/android-port/briefs/3fn-result.md`. Binding:
`docs/AO3_NETWORKING_POLICY.md`. **New lesson:** the JVM tests accept regex syntax Android's
ICU engine rejects (a Unicode-class flag crashed the composer on a device); write no regex
flags or classes beyond what Android's `java.util.regex` documents.

## Part 1: A58's deferred items (your `docs/android-port/audits/A58-result.md`)

For each: confirm against the code at HEAD, then fix it as iOS does
(`/Users/cidy02/kudos-ios-polish/`, read-only) with a test porting the iOS assertion, or say
why it isn't worth it. In this order; stop where you run out of time and say where.

1. **#7** system media controls get elapsed and duration estimates for Read Aloud, rate-aware
   (`ReaderTimeEstimateTests`).
2. **#12** the complete-sentence chunking rules with abbreviation protection (`TextChunkerTests`).
3. **#11** converted note asides keep `epub:type="note"` (`AuthorNoteDetectorTests`).
4. **#19** the loading skeleton: bounded prose-shaped paragraphs that fill the area without
   overflowing a short one (`ReaderPageSkeletonTests`).
5. **#16** one Dark background token shared by the reader and the app (`ReaderThemeTests`);
   say which surfaces would change colour before changing any.

## Part 2: read-only second reviews (findings into the result file with `path:line`)

Each is a write to AO3 that Claude landed alone. Check it against the binding policy (one
user-triggered POST, never retried, success only on AO3's notice, fenced to the session that
started it, nothing sent after a session change) and against iOS's equivalent.

6. `a5c14a94`: Subscribe and Unsubscribe on an author's page.
7. `b8bc9aed`: Mute and Block on an author's page (two-step confirm pages).
8. `c2442cd6`: Clear History.
