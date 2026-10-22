# Brief 3gs result

Status: test fixes ready for Claude to run. No Gradle runs, commits, pushes, branch switches, sign-ins, or AO3 traffic. `TASKS.md` untouched.

## Reader speech preparation

- Cause: `ReaderSpeechController` owns `CoroutineScope(Dispatchers.Main + Job())`, outside `runTest`'s job tree. `speakCurrent()` switches to `Dispatchers.Default`. Receiving the fake engine's call proves entry into `speak`, not completion of that coroutine. `shutdown()` cancels the controller scope, but cancellation is asynchronous: Default can still dispatch back to Main after the test returns and `tearDown()` calls `resetMain()`.
- Change: every controller in `ReaderSpeechControllerTest` now uses a test-only `shutdownAndJoin()` cleanup helper. It reads the existing private scope with Robolectric reflection, calls the real `shutdown()`, asserts that shutdown cancelled its root job, then joins that job and asserts completion. No extra cancellation masks the production shutdown behavior.
- Why it cannot race: joining the root job waits for all its children, including old chapter pulls, collectors, and the Default speech coroutine's return to Main. Each test's `finally` finishes this join inside `runTest`, before JUnit runs `tearDown()` and resets Main. Draining the test scheduler alone would not wait for real Default work.
- Production assessment: source inspection shows the work is owned by the scope that shutdown cancels; asynchronous cancellation alone is not a leaked job. No production change is justified. The cancellation/completion assertions pin that lifecycle contract when Claude runs the suite.

## Writing preview post

- Cause: `WritingAO3PreviewScreen` shows the preview notice and Post row immediately, while a `LaunchedEffect` formats the preview rows using `withContext(Dispatchers.Default)`. Post is disabled until `rows != null`. The test waited only for the notice, scrolled to Post and clicked; under load that click could hit the disabled row and do nothing. `confirmPost()` then spent 15 seconds waiting for a dialog that was never opened. There is no real-time delay or IO on this readiness path; Compose's idle clock does not own Default's work.
- Change: the failing test waits for the fixture's `Preview title` heading before scrolling to Post, and asserts Post is enabled before clicking. The heading is rendered only from the completed `rows` list. Existing timeout values are unchanged.
- Why it cannot race: the heading is an observable completion barrier for background formatting, not the earlier notice. The same composition publishes ready rows and enables Post. Only after that barrier does the test scroll (so inserted paragraphs cannot displace the target) and click. Default remains a real dispatcher; the test synchronizes on its published result rather than assuming Compose idleness means it finished. The bounded wait can still report a genuinely stalled renderer, but cannot consume an ignored disabled tap and then wait for its nonexistent dialog.

## Verification

- `git diff --check`: passed. Result Markdown also checked for trailing whitespace.
- Static cleanup inventory: all eight controller constructions have a matching `finally` cleanup using `shutdownAndJoin()`.
- Reviewed the changed tests against the controller's scope ownership and preview's `rows != null` enablement condition. The preview fixture puts `Preview title` first in the rendered rows, within the initial viewport before scrolling.
- Only the two test files and this result file were changed. The pre-existing untracked `3gs-flaky-tests.md` brief was left alone. No production files changed.
- Claude should run both focused classes, then the full `:app:testDebugUnitTest` suite under load; no compilation or runtime pass is claimed here.
