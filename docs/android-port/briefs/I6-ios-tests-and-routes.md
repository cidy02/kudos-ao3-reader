# Brief I6 (iOS): tests owed for T-364, and debug routes for two unseen screens

**Write code in this worktree only (`~/kudos-agent-ios`, branch `claude/agent-ios-i6`); do not
commit, push, switch branches, sign in or contact archiveofourown.org; do not run xcodebuild (Claude
builds and tests).** Do not edit `TASKS.md`. Create `docs/android-port/briefs/I6-result.md` FIRST and
write each item into it as you finish it, with `path:line` and, for each test, what it would do
if the fix it covers were reverted (it must fail).

1. **Tests owed for T-364** (`TASKS.md` row T-364: "No test covers these five"). Write Swift Testing
   tests in `KudosTests/` for the two that are model rules, not view code:
   (a) a highlight, note or bookmark deleted in the reader records a **signed** deletion marker,
   as every other deletion does (find the reader's delete path and `SyncTombstones`); (b) every
   reader position save writes both the Readium locator **and** the chapter and place the Mac reader
   opens from (`lastSpineIndex` / scroll fraction or whatever the Mac reads; find the save path in
   `Features/ReaderReadium/` and `Models/Models.swift`), so a work read on the iPhone opens on the
   Mac at that chapter, and a newer iPhone copy never carries zeros over the Mac's chapter. Follow
   the style of the existing suites (in-memory `ModelContainer`, no network).
2. **Debug routes for two screens never put beside Android's** (DEBUG only, in `App/DemoLibrary.swift`
   and `App/ContentView.swift`, the way T-427 added `compose:<title>` and `bugreport`):
   `-KudosDebugRoute login` presents `AO3LoginView` (as the Comments and author screens present it,
   signed out); and a route that opens the comment thread screen a reader reaches from "Continue
   thread" on the demo comments page (`comments:<title>` shows that page; find what "Continue
   thread" pushes in `Features/Comments/` and `Features/Account/AccountInboxViews.swift`, and name
   the route `thread:<title>`). Say in the result which Android route shows the same screen
   (Android has `--es kudosDebugRoute nav:login`; its thread screen is reached through
   `nav:comments/<id>?focused=<commentId>`).

Nothing else changes. Builds for iOS and macOS must stay clean (guard iOS-only APIs).
