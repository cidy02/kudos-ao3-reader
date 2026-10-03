# Brief 3p: Home and Library take ~30 s to appear

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. No network
except Gradle's offline cache. Leave changes uncommitted. Build and test, and iterate until green:
`cd android && JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ANDROID_HOME=$HOME/Library/Android/sdk ./gradlew :app:assembleDebug :app:testDebugUnitTest --offline --console=plain -q`
Use **emulator-5554 only** (Claude verifies on emulator-5556).

## The bug
With the demo library (about 16 works), launching to Home takes about 32 s on the emulator.
`am start` reports about 18 s (including the debug seed), and then "Loading your library…" shows
for about 14 s more. Library's first load is similar. iOS shows the same library instantly. The
owner expects the same behaviour on both platforms.

## Find the cause, measure, fix
Measure first: add temporary timing logs (`android.util.Log` / `SystemClock.elapsedRealtime()`) or use
`adb shell am start -W` plus logcat, and record where the time goes. Likely suspects, to verify
rather than assume:
- `WorkRepository.decorate(...)` (from Phase 2c) computing keep-state per work with its own queries.
- `LibraryRepository.observeSnapshot()` calling `workRepository.collectionsForWork(work.id)` and user tags
  **per work** inside a Flow (N+1), re-run on every emission.
- `savedForLaterWorkIds()` and other queries inside `combine` blocks that rerun on every
  database change.
- The debug demo seed using `runBlocking` on the main thread in `MainActivity` (debug only, but
  it inflates the measurement): move it off the main thread, show the UI immediately, and let
  Flows update.
- Flows recomputing on every write while the seed runs (hundreds of emissions).

Fix with batched queries (one query for all collection memberships, tags and keep-state, then map
in memory), `distinctUntilChanged`, and moving work to `Dispatchers.IO` / `Default`, keeping
behaviour identical. **Don't change any shelf rule or data semantics**: the existing unit tests must
keep passing unchanged, including `DemoLibraryTest.demoLibraryShelfCountsMatchIos`.

Target: a normal (non-demo) launch shows Home with data in under 1 s on the emulator, and a demo
launch shows the UI at once, populated within about 2 s. Write
`docs/android-port/briefs/3p-result.md` with before and after timings and what each change saved.
Remove the temporary timing logs before you finish.

Don't touch `app/MainScaffold.kt`, `library/LibraryShellChrome.kt`, `home/HomeShellChrome.kt`,
`ui/subject/SubjectWorkCoverCard.kt` or `home/HomeFacts.kt` (another agent is editing them), or
`backup/` and migrations.
