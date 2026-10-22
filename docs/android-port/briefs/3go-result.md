# Brief 3go result

Scope: A77 owner decisions, ranks 1–4, 6–8 and 10.
No TASKS.md edits, branch changes, commits, pushes, sign-in, Gradle, or AO3 contact.
Tests will be added for Claude to build/run and verify on the emulator.

## Completed items

Android paths below are relative to `android/app/src/main/java/io/github/cidy02/kudos/`;
iOS paths are relative to `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`.
Tests are relative to `android/app/src/test/java/io/github/cidy02/kudos/`.
**Fixed means implemented with tests added; no Gradle/test execution or visual verification is claimed.**

1. **Rank 1 — fixed.** `AccentIconSquare` derives readable ink from the **supplied** accent
   on Dark/OLED and retains the original accent at 0.16 alpha for its square.
   Android `ui/subject/SubjectComponents.kt:831`/`:849`, shared ink rule
   `ui/subject/KudosTokens.kt:89`. Followed iOS `UIComponents/AccentInk.swift:5`/`:58`
   (Q19 A). Test: `ui/subject/OwnerDecisions3goComposeTest.kt:53` inspects the glyph's
   actual `colorFilter` and the square's actual background for red, navy and an already
   readable yellow on both themes, with a different app accent.

2. **Rank 2 — fixed.** Both editor switches pass `palette.tint`, the exact picked colour,
   rather than its hue-derived `accent`. Picked chip/pill fills use that same exact role.
   Android `library/QueueEditorSheet.kt:205`, `library/CollectionEditorSheet.kt:252`/`:272`,
   `ui/subject/SubjectPalette.kt:181`, `ui/subject/SubjectComponents.kt:529`.
   Followed iOS `Features/Library/NewReadingQueueSheet.swift:238` and
   `Features/Library/NewCollectionSheet.swift:123`.
   Tests: `library/ActionParityFormsTest.kt:138`/`:154` inspect the actual editor switch
   backgrounds; `ui/subject/OwnerDecisions3goComposeTest.kt:72` covers picked fills and
   readable sheet ink on all four themes.

3. **Rank 3 — fixed.** Queue items now expose their own monotonic fraction. The existing
   paced/retried binary client reports bytes when Content-Length is available; otherwise
   the queue uses iOS's exponential creep, strictly below 90%. Successful import sets
   100%, holds 300 ms, then marks Done. Failure removes the download presentation.
   Android `works/DownloadQueue.kt:217`/`:237`/`:339`,
   `network/ao3/AO3Client.kt:147`/`:413`, `ui/subject/WorkReadingRing.kt:12`.
   Followed iOS `Services/DownloadQueue.swift:96`/`:104`/`:176`.
   Tests: `works/DownloadQueueTest.kt:329`/`:337` (creep cap, task progress cannot retreat,
   299 ms still Downloading, 300 ms Done); `network/ao3/AO3ClientHostPolicyTest.kt:65`
   uses in-memory response bodies for known/unknown lengths, with no sockets;
   `ui/subject/OwnerDecisions3goComposeTest.kt:100` pins a 37% ring across three seconds
   and its return to reading progress.

4. **Rank 4 — fixed.** Work detail's resume card and the shared saved detailed row grey
   while their work downloads and display its fraction. Shared covers, Home's resume,
   queue cards and all three shared ledger-row callers use the same fraction too.
   Android `works/detail/WorkDetailIdentity.kt:348`,
   `ui/components/SensitiveWorkRow.kt:802`/`:842`, `ui/subject/WorkLibraryComponents.kt:165`.
   Followed iOS `Features/WorkDetail/WorkDetailView.swift:291`,
   `Features/Library/WorkRow.swift:91`/`:155`.
   Test: `ui/subject/OwnerDecisions3goComposeTest.kt:100` inspects the graphics-layer
   modifiers on both requested cards, their substituted rings, and restoration.

5. **Rank 5 — not a fault (unchanged).** Android has no comment swipe; its buttons and
   long-press actions never move the row, so there are no swipe rails to hide/restore.
   Android `comments/CommentThreadComponents.kt:90`/`:307` was reread; no `swipedId`
   writer exists in the comments feature. Compared iOS's swipe tracker at
   `Features/Comments/CommentThreadRow.swift:965`. Test: no new test or interaction;
   text-only search confirmed no Android comment swipe writer. Owner explicitly excluded it.

6. **Rank 6 — fixed.** Recently Deleted's kicker uses `isDownloaded` (kept), rather than
   `hasEpub` (file presence). Android `library/RecentlyDeletedScreen.kt:158`/`:1025`.
   Followed iOS `Features/Library/RecentlyDeletedView.swift:464`.
   Test: `library/OwnerDecisions3goTest.kt:14` covers an un-kept reading file, an explicit
   keep, queue/collection keep, an import, and a kept work without a file.

7. **Rank 7 — fixed.** The newest registered wash wins; changing an existing wash leaves
   its order intact and closing it restores the previous wash. Both editors install a
   shared sheet palette for Cancel, Create/Done, fields, radio controls and auxiliary dialogs;
   ink is readable while filled controls retain the exact picked colour.
   Android `ui/subject/SubjectComponents.kt:178`, `ui/subject/SubjectPaletteTheme.kt:9`,
   `library/QueueEditorSheet.kt:96`, `library/CollectionEditorSheet.kt:150`.
   Followed iOS `UIComponents/SubjectSurface.swift:1298` and
   `Features/Library/NewReadingQueueSheet.swift:150`.
   Tests: `library/OwnerDecisions3goTest.kt:24` covers insertion, update and removal;
   `library/ActionParityFormsTest.kt:138` inspects Cancel's resolved text colour in the real
   queue editor; `ui/subject/OwnerDecisions3goComposeTest.kt:72` checks scoped Material/token roles.

8. **Rank 8 — fixed.** Both named Keep paths emit the shared 0.7 s instant-download
   event when the EPUB is already here. Bulk Library Keep and work detail's separate Keep
   path also emit it; none fetches again. Instant events are separate from the serial queue.
   Android `works/DownloadQueue.kt:42`, `library/LibraryViewModel.kt:269`/`:397`,
   `home/HomeWorkMenu.kt:196`, `works/WorkDetailScreen.kt:620`.
   Followed iOS `Services/DownloadQueue.swift:32`/`:78`, `Services/WorkDownload.swift:69`.
   Test: `works/DownloadQueueTest.kt:368` calls both named production paths, checks 50%
   at 350 ms, expiry at 700 ms, a kept file, and no network queue item; fetching throws.

9. **Rank 9 — not a fault to change in this brief (owner question 9; unchanged).**
   Backup's extra notes remain pending the owner's answer, as explicitly instructed.
   Android `backup/BackupScreen.kt:254`/`:260` and iOS
   `Settings/SettingsBackupPage.swift:503` were reread. Test: no new test; no Backup edits.

10. **Rank 10 — fixed.** Empty work tags show the exact AO3 or unlinked-import sentence,
    selected by AO3 identity. Android `works/detail/WorkDetailSections.kt:218`/`:276`,
    caller `works/WorkDetailScreen.kt:1650`.
    Followed iOS `Features/WorkDetail/WorkDetailSections.swift:44`–`:55`.
    Test: `ui/subject/OwnerDecisions3goComposeTest.kt:127` checks both exact sentences,
    their replacement when identity changes, and removal when tags arrive.

## Verification and handoff

Local review/checks in progress. No runtime or visual claim.
