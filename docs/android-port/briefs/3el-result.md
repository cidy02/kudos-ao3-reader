# 3el — comments pages fail closed (A50 F7)

Changes (Android paths below are under `android/app/src/`):

- `main/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentParser.kt`: work/chapter reads require `#comments_placeholder > ol.thread`; standalone reads use iOS's thread selectors and require a parsed comment. Missing lists and nonempty lists with no parseable comments throw; only a structurally empty work/chapter list means no comments.
- `main/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentRepository.kt`: passes the requested standalone-thread context (`focusedCommentId != null`) into the parser. Existing exception handling maps the failure to `AO3Error.Parse`, without caching it.
- `test/resources/ao3/comments/comments_basic.html`: wrapped the work's list in `#comments_placeholder`.
- `test/resources/ao3/comments/comments_empty.html`: replaced the fabricated empty-state paragraph with the placeholder and empty direct list shown in the debug empty fixture; retained the composer form.
- `test/java/io/github/cidy02/kudos/comments/CommentsViewModelDraftTest.kt`: corrected the chapter page made from a standalone thread; replaced all four unbounded draft-restoration waits with bounded, sleeping waits that fail immediately on Error/AuthRequired.
- `test/java/io/github/cidy02/kudos/comments/CommentsViewModelContextTest.kt`: corrected generated work/chapter pages; added coverage that an unrecognized 200 reaches Error, stops newest-page discovery after one read, and Retry can load a recognized empty page.
- `test/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentRepositoryTest.kt`: added the missing-list HTTP 200 regression for work, chapter and focused-thread requests, asserting `AO3Error.Parse`.
- `test/java/io/github/cidy02/kudos/network/ao3/comments/AO3CommentParserTest.kt`: added direct-list, malformed-list, recognized-empty and standalone-thread checks.
- `test/java/io/github/cidy02/kudos/account/CachedAO3PagesScreenTest.kt`: routes comment metadata reads to the real empty-comments fixture instead of an author works list.
- `test/java/io/github/cidy02/kudos/account/InboxFailedPageTest.kt`: likewise returns the empty-comments fixture for work-author lookups instead of an Inbox page.

No existing expectations changed: their valid-page behavior remains correct once the HTML is corrected.

The CPU spin is test-only: `CommentsViewModelDraftTest` waited on `isDraftRestored`, indirectly waiting for a successful Loaded state. `CommentsViewModel.present` sets that flag only on success, so Error left those loops advancing virtual time forever. `CommentsViewModelContextTest.until` already sleeps and is bounded. Production `present` sets Error once; `CommentsScreen` renders “Couldn't Load Comments” with “Try Again”. `openPendingReply` returns immediately unless Loaded; it does not poll. No production error-wait loop was found or changed.

Checked by reading the callers, screen, fixtures and the read-only iOS parser; `git diff --check` passes. Gradle compilation/tests and emulator UI were not run, as instructed; Claude still needs to run the comment suites and build. No AO3 contact or sign-in; no commits, pushes, branch switches, TASKS, backup-format or Room-schema changes.
