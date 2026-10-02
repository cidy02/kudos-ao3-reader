# Brief 3c-fix: finish the queue page and the iOS-style switch

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. No network
except Gradle's offline cache. Leave changes uncommitted. Build and test, and iterate until green:
`cd android && JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ANDROID_HOME=$HOME/Library/Android/sdk ./gradlew :app:assembleDebug :app:testDebugUnitTest --offline --console=plain -q`

These follow your 3c work (commit dc18d01b; see `docs/android-port/briefs/3c-result.md`). Compare against
the iOS queue page: `docs/android-port/shots/ios/` has Home/Library/queues, and `queue-neon-reread-dark.png` is the iOS queue page; an iOS shot of the
"Neon reread" page shows the target. Read `kudos-ao3-reader/Features/Library/ReadingQueueBrowser.swift`
and `ReadingQueuePageParts.swift`.

1. **Up Next** on iOS is the rich ledger card: reading ring, fandom kicker, title, author · words ·
   chapters, and the status icon grid, on the subject card background. Android draws a plain row.
   Port it, reusing Home's ring and status tray.
2. **In Line** on iOS defaults to the compact display mode, a two-column grid of cover cards (Home's
   `SubjectWorkCoverCard`). The list mode is the alternative in "…" › Display. Match the default and
   both modes.
3. **Keep works offline**: turning it on, or adding a work to a queue that keeps, fetches missing AO3
   EPUBs through the existing serial `DownloadQueue`, as iOS `KeepOffline.downloadItems` does (only
   AO3 works with no file on disk, and not soft-deleted ones). Turning it off fetches nothing and
   deletes nothing. Add tests.
4. **Hide mature** in the queue page's "…" menu, wired to the existing privacy setting the Library
   uses. Read how `library/LibraryScreen.kt` handles privacy, but don't edit Library files
   (another agent is changing them); call the shared setting or repository instead.
5. **An iOS-style switch**: add `SubjectToggle` to `ui/subject` (an accent track when on, a neutral
   glass track when off, white thumb, iOS proportions), and use it in the queue sheet and Queue
   details instead of Material `Switch`.

Don't touch `app/MainScaffold.kt`, `home/HomeShellChrome.kt` or the `library/Library*` files; another
agent is changing them right now. Screenshots go in `docs/android-port/shots/3c-fix/` (emulator, Dark).
Write `docs/android-port/briefs/3c-fix-result.md` (under 300 words).
