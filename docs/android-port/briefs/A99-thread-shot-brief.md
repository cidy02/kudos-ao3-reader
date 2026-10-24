# A99 — an Android screenshot route for the comment Thread page

**Agent:** Sonnet 5.5 (agy account 2). **Worktree:** `~/kudos-agent-gemini2`, branch
`android/agent-sonnet-a99` (from the lane's `82626348`). Debug-only plumbing: no visible change.

## Why

The `thread` screen pair has never been compared side by side: Android has no screenshot route to its
Thread page (`comments/CommentThreadScreen.kt`), and the shot that taps "Continue thread" finds no such
link, because the demo's whole conversation fits inline. The iPhone has `shot`-style route
`thread:<title>`, which opens the work's Comments and then pushes the first conversation's Thread screen
(`~/kudos-ios-polish/kudos-ao3-reader/App/DemoLibrary.swift:590-614`, read only): the root of the first
"Continue thread" row if there is one, otherwise the first conversation with replies, otherwise the
first conversation.

## What to do

1. In `android/app/src/main/java/io/github/cidy02/kudos/app/DebugShots.kt`, add a `"thread"` shot beside
   `"formattingtray"` and `"chapterpicker"` (`:53-54`): it opens the same demo work's Comments
   (`Routes.comments(12345)` as they do, unless the demo work the iPhone's `thread:Sodium Lights` uses has
   another id: check) and asks for the thread.
2. In `comments/CommentsScreen.kt`, beside the existing `DebugShotEffect("comments", …)` (`:186`), add a
   `DebugShotEffect` for the thread that, once the comments are loaded, sets `pushedThreadRootId` (`:194`)
   to the same root the iPhone picks (the rule above), so `CommentThreadScreen` opens through the real
   path at `:291-305`.
3. Follow how the existing debug shots are written (`DebugShotEffect`, the shot's list of sheet ids).
   Release builds must not change: keep it inside the same debug-only mechanism the others use.

## Test

Add one Robolectric test (beside the existing comments screen tests in
`android/app/src/test/java/io/github/cidy02/kudos/comments/`) that drives the thread shot and checks the
Thread page is showing (for example its title "Thread" and the root comment's author), and that fails
without the new effect.

## Rules

- Change only `DebugShots.kt`, `CommentsScreen.kt` and the one test file.
- Do not commit, push, switch branches, run Gradle (Claude builds and tests), sign in, contact
  archiveofourown.org, or edit `TASKS.md`. Never `--yolo` work.

## Output

Write `docs/android-port/briefs/A99-result.md` **first**, then keep it current: what changed (`path:line`),
which root the shot opens and why, and what the test checks and how it fails without the change.
