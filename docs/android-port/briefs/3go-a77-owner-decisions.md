# Brief 3go: owner decisions A77 found missing or different on Android

**Write code; do not commit, push, switch branches, sign in, run Gradle or contact
archiveofourown.org.** Claude builds, tests, looks on the emulator and lands it. Do not edit
`TASKS.md`. Create `docs/android-port/briefs/3go-result.md` FIRST and write each item into it as
you finish it: **fixed / already right / not a fault (why)**, Android `path:line`, the iOS
`path:line` you followed, and the test.

Your own audit `docs/android-port/audits/A77-result.md` (section 6, ranks below) has the evidence;
Claude confirmed ranks 1, 6, 9 and 10 in the code. Re-read each item's code before changing it.
iOS source: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`. Fix shared components once, for
every caller. Rank 5 (comment swipe rails) is not a fault (Android has no comment swipe) and rank 9
(Backup's notes) is owner question 9: leave both.

1. **Rank 1, Dark/OLED accent glyphs.** `AccentIconSquare` (`ui/subject/SubjectComponents.kt`)
   tints its glyph with the raw accent. iOS draws the glyph in readable ink and keeps the fill
   exact (`UIComponents/AccentInk.swift`, owner question 19 answer A). Use the readable ink for the
   glyph (as `KudosTokens.accentInk` does), the exact colour for the fill, for any accent passed in.
2. **Rank 2, picked colours.** The queue and collection editor sheets' switches (and any other
   control the sheet colours) must use the exact picked colour as fill, as iOS
   (`NewReadingQueueSheet.swift:238`, `NewCollectionSheet.swift:123`), not a hue-derived shade.
3. **Ranks 3 and 4, downloading.** The ring that replaces the reading ring shows the download's
   own fraction: task progress where the download reports it, otherwise iOS's pacing creep capped
   below 90% (`Services/DownloadQueue.swift:96`), then 100% held 300 ms before Done (`:176`), not a
   repeating sweep. Grey the work page's resume card and the saved detailed rows while their work
   downloads, as iOS (`WorkDetailView.swift:291`, `WorkRow.swift:91`).
4. **Rank 8, keep a file already here.** iOS still shows a 0.7 s fill (`showInstantDownload`,
   `DownloadQueue.swift:32`, `WorkDownload.swift:69-72`); Android flips the state at once. Emit the
   same short queue event from both Keep paths (`LibraryViewModel.kt:395`, `HomeWorkMenu.kt:193`).
5. **Rank 6, Recently Deleted.** "Downloaded work" follows "kept" (iOS `isDownloaded`,
   `RecentlyDeletedView.swift:464`), not the file's presence (`RecentlyDeletedScreen.kt:158`).
6. **Rank 7, the colour of the screen on top.** The shell takes the newest registered wash, as
   iOS (`SubjectSurface.swift:1298`; decision 2026-10-12, owner 2026-10-11), not the oldest
   (`SubjectComponents.kt:178`); a coloured sheet's own controls (Cancel and the rest) take the
   sheet's palette, as `NewReadingQueueSheet.swift:150` does.
7. **Rank 10, a work with no tags.** Work detail shows iOS's sentence instead of nothing:
   "AO3 hasn't provided tags for this work yet. Pull down to get the latest details from AO3." for
   an AO3 work, "This imported work isn't linked to AO3, so you won't see AO3 tags here." otherwise
   (`Features/WorkDetail/WorkDetailSections.swift:44-55`).

Tests: one per rule (glyph ink vs fill on Dark and OLED; the editor switch's fill equals the picked
colour; the download fraction's creep cap, 100% hold and Done; the instant fill event for a file
already here; the kicker follows "kept"; the newest wash wins and the old one returns when the
sheet closes; both no-tags sentences). Structural Compose or JVM tests only (no
`captureToImage`). Existing tests that pin the old behaviour change with the fix; say which.
