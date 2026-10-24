# A99 result — Thread page screenshot route

**Branch:** `android/agent-sonnet-a99`. Not committed, **not built or run** (no Gradle, per the rules):
Claude builds and runs `CommentThreadShotTest`.

## What changed

- `android/app/src/main/java/io/github/cidy02/kudos/app/DebugShots.kt:55-56` — new shot
  `"thread" -> DebugShot(Routes.comments(999_000_005), listOf("comments-thread"))`, beside `chapterpicker`.
  `"comments-thread"` is its own page id, so `chapterpicker`'s `"comments"` effect does not fire for it
  (and the reverse).
- `.../comments/CommentsScreen.kt:194-198` — `DebugShotEffect("comments-thread", ready = state is Loaded)`
  right after `pushedThreadRootId` is declared. Once the comments are loaded it sets `pushedThreadRootId`
  to `debugShotThreadRootId(...)`, so `CommentThreadScreen` opens through the real path
  (`if (pushedThreadRootId != null)` below). Same mechanism as the other shots: `DebugShotRequests.Read`
  does nothing unless `BuildConfig.DEBUG && DemoNetwork.isActive`, and the page only gets a request from a
  `shot=thread` launch, so release builds and normal runs are unchanged.
- `.../comments/CommentsScreen.kt` (end of file, `debugShotThreadRootId`) — the iPhone's rule
  (`DemoLibrary.swift:590-614`, `threadRootID(in:)`): the root of the first `ContinueThread` row of the
  list as built by `CommentConversationBuilder.rows`, else the first conversation with replies, else the
  first conversation.
- `android/app/src/test/java/io/github/cidy02/kudos/comments/CommentThreadShotTest.kt` (new, one test).

## Which id and which root

- **Work id 999000005, not 12345.** The iPhone's `thread:Sodium Lights` opens
  `work.ao3WorkID ?? 999_000_005` (`DemoLibrary.swift:588`), and Android's demo Sodium Lights is
  `ao3WorkID = 999_000_005` (`DemoLibrary.kt:531-533`). Every `comments` URL is served by the one
  `ao3_comments_page` fixture (`DemoNetwork.kt:184`), so the page is identical to `chapterpicker`'s.
- **Root `comment_1001` (StarrySky).** The demo page (`debug/assets/fixtures/ao3_comments_page.html`) has
  no "Continue thread" row: its deepest reply is depth 2 against an inline limit of 5, and a conversation
  with at most 8 replies shows inline. So the second rule applies: the first conversation with replies is
  1001 (StarrySky → Calytrix → a nested reply); the second conversation (1004) has none. This is the
  same root the iPhone picks from the same fixture.

## The test

`CommentThreadShotTest.theThreadShotShowsTheFirstConversationWithRepliesOnTheThreadPage`: activates the
demo network, opens the real `debugShot("thread", …)` through `DebugShotRequests.open`, composes the real
`CommentsScreen` for work 999000005 with a repository serving `ao3/comments/comments_basic.html`, and
waits for the Thread page. Then it checks:

1. the title "Thread" is showing (the Comments list has no such text);
2. the first conversation's root author `AO3_Reader` and its reply "A nested reply." are showing;
3. "Curious Guest", a later conversation that only the Comments list shows, is **not** showing.

**Without the effect** nothing sets `pushedThreadRootId`, the Comments list stays up, and
`waitUntil(15_000) { "Thread" }` times out, so the test fails. (Deleting only the `"thread"` entry in
`DebugShots.kt` fails it earlier, at `debugShot(...)!!`.)

## Open for Claude

- Nothing was compiled. Check `CommentThreadShotTest` compiles (`AO3AuthenticatedClient` members mirror
  `OfflineCommentsCopyTest.Page`) and that `shows("Thread", ignoreCase = true)` matches only the thread
  title (unmerged tree).
- `docs/android-port/audits/A82-shots.md` does not list `thread`; I did not touch it (out of scope).
