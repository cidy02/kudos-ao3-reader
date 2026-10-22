# Brief 3gs: two Android tests that fail only under the full suite's load

**Write test code (and production code only if the test proves a real race); do not commit, push,
switch branches, sign in, run Gradle or contact archiveofourown.org.** Claude runs them. Do not edit
`TASKS.md`. Create `docs/android-port/briefs/3gs-result.md` FIRST and fill it in as you go.

Both pass alone and failed once each in the full `:app:testDebugUnitTest` run on 2026-10-22:

1. `reader/speech/ReaderSpeechControllerTest.enginePreparationRunsOffMain` failed in `tearDown`
   (`ReaderSpeechControllerTest.kt:47`, `Dispatchers.resetMain()`) with
   `IllegalStateException: Dispatchers.Main is used concurrently with setting it`: a coroutine the
   test started (engine preparation) was still using Main when the test reset it. Make the test
   finish or cancel everything it launched (and wait for it) before `resetMain`. If the controller
   itself leaks a job that outlives its own close or release, that is a production fault: say so and
   fix it there, with the test pinning it.
2. `writing/WritingWorkActionsScreenTest.previewPostUsesItsOwnConfirmationAndErrorTitleAndKeepsPreviewOnRefusal`
   timed out at `awaitText` (`WritingWorkActionsScreenTest.kt:58`, 15 s) from `confirmPost` (`:64`).
   Find what it waits on (a real-time delay, a dispatcher the test does not drive, or work on
   `Dispatchers.IO`) and make the test drive it deterministically instead of racing the clock. Do not
   just raise the timeout.

For each: what made it flaky, the change, and why it can no longer race.
