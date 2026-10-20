# A65 — Ledger of What Is Still Open on Android (`28bcd3c5`)

Scope: Android lane at `28bcd3c5` (`/Users/cidy02/kudos-agent-gemini2`); iOS reference at `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` (read-only). Read-only audit across `docs/android-port/LIVING-PROMPT.md` (§7, §10, §11, §12), `docs/android-port/briefs/3e*-result.md` and `3f*-result.md`, `docs/android-port/audits/A49-result.md` … `A64-result.md`, `docs/android-port/DECISIONS.md` (from 2026-10-10 on), and `git log --oneline 1da8f5fa..28bcd3c5`.

---

## 1. Open `code` Rows (Ordered Most Harmful to a Reader First)

### A. Lost text, place, or work / persistence & archive integrity
1. **Row #96 — Ungated local file-writer race against Replace/sync (`3fa-result.md:92`)**
   - Quote: `"The existing ungated file-writer race is unchanged."`
   - Harm: A concurrent local EPUB/cover/original write during a backup Replace or folder sync can race with staged file replacement.
   - Android: `android/app/src/main/java/io/github/cidy02/kudos/works/WorkFileStore.kt:42`
   - iOS: `kudos-ao3-reader/Services/PersistenceOperationGate.swift:18`
2. **Row #97 — Sync can remain paused after a failed Replace (`3fa-result.md:95`)**
   - Quote: `"Sync may remain paused after a failed Replace, as before."`
   - Harm: If a Replace import fails after pausing folder sync, automatic sync stays paused until re-enabled.
   - Android: `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupRepository.kt:129`
   - iOS: `kudos-ao3-reader/Services/KudosBackupService.swift:612`
3. **Row #115 — Fixed-layout two-resource spread does not report end-of-work completion (`A61-result.md:11`, `3fo-result.md:28`)**
   - Quote: `"Recognize true end of a fixed-layout two-resource spread: the installed SDK supplies no pagination viewport for that layout"`
   - Harm: Reaching the final two-resource spread of a fixed-layout EPUB never triggers auto-finish (`ReadiumReaderCompletion.isAtEnd`).
   - Android: `android/app/src/main/java/io/github/cidy02/kudos/reader/readium/ReadiumNavigatorHost.kt:119`
   - iOS: `kudos-ao3-reader/Features/ReaderReadium/ReadiumReaderCompletion.swift:20`
4. **Row #117 — Backup streaming ignores central directory / ZIP64 chain corruption (`A61-result.md:24`, `3fo-result.md:7`)**
   - Quote: `"Validate the backup central directory/ZIP64 chain if matching iOS’s malformed-archive rejection is required"`
   - Harm: `ZipInputStream` stops before CEN/EOCD records, admitting archives with malformed central directories or truncated ZIP64 extras that iOS `MiniZip` rejects.
   - Android: `android/app/src/main/java/io/github/cidy02/kudos/backup/BackupImporter.kt:34`
   - iOS: `kudos-ao3-reader/Reading/MiniZip.swift:10`
5. **Row #112 — Temp EPUB/backup staging files omit explicit app cache directory (`A60-result.md:87`)**
   - Quote: `"Consider follow-up cleanup to explicitly pass the app cache directory (or delete on exit) in case an uncaught error bypasses the normal .use block"`
   - Harm: `File.createTempFile` defaults to `java.io.tmpdir` instead of `context.cacheDir` in `EpubImportMetadata` and `BackupImporter`.
   - Android: `android/app/src/main/java/io/github/cidy02/kudos/works/EpubImportMetadata.kt:208`
   - iOS: `kudos-ao3-reader/Services/EPUBMetadataExtractor.swift:32`

### B. Unwanted or uncoordinated AO3 network traffic
6. **Row #90 — 503 retry branch in `AO3Client` can repeat a GET outside the request coordinator (`A51-result.md:49`)**
   - Quote: `"That same 503 branch can internally repeat a GET outside the coordinator too."`
   - Harm: A 503 retry inside `performOnce` sleeps and re-requests without re-entering `AO3RequestCoordinator` spacing/width gates.
   - Android: `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/AO3Client.kt:129`
   - iOS: `kudos-ao3-reader/Services/AO3Client.swift:30`
7. **Row #122 — Chapter-focused Comments load starts an `All` comments GET before resolving the chapter (`3fp-result.md:37`)**
   - Quote: `"Android's existing chapter-aware Comments lifecycle first starts an All comments load, then resolves the requested chapter"`
   - Harm: Opening chapter comments triggers an extra initial work-level comments request before switching to `ByChapter`.
   - Android: `android/app/src/main/java/io/github/cidy02/kudos/comments/CommentsScreen.kt:153`
   - iOS: `kudos-ao3-reader/Features/Comments/CommentsView.swift:92`
8. **Row #55 — Returning from a collection's Manage screen loses segment/scroll and re-fetches (`LIVING-PROMPT.md:1035`)**
   - Quote: `"a collection's page forgets its segment and its place, and reads its page again, every time the reader comes back"`
   - Harm: `AO3CollectionDetailScreen` holds its state in route-scoped `remember`, losing the reader's tab/scroll place and re-requesting the collection page on Back.
   - Android: `android/app/src/main/java/io/github/cidy02/kudos/account/AO3CollectionDetailScreen.kt:85`
   - iOS: `kudos-ao3-reader/Features/Account/AO3CollectionDetailView.swift:23`

### C. Missing features & degraded reader flows
9. **Row #114 — Image-only PDF imports have no OCR fallback (`3fo-result.md:24`, `A61-result.md:9`)**
   - Quote: `"OCR remains missing: adding an Android OCR engine and its lifecycle/dependency/device validation is beyond this focused fix"`
   - Harm: Scanned/image-only PDFs fail to import rather than running an OCR pass like iOS Vision's `recognizeText`.
   - Android: `android/app/src/main/java/io/github/cidy02/kudos/works/converters/PDFWorkConverter.kt:68`
   - iOS: `kudos-ao3-reader/Services/PDFWorkConverter.swift:291`
10. **Row #61 — No converter-version stamp for `Rebuild from Original` (`LIVING-PROMPT.md:1379`, `3fp-result.md:34`)**
    - Quote: `"Android has no converter-version stamp. Every rebuild conservatively asks, including a possibly stale import that iOS would rebuild immediately."`
    - Harm: Android cannot detect when a converted work's `.original` sidecar is stale after converter upgrades, so it omits the reader's stale-rebuild pill (`LIVING-PROMPT.md:903`) and always asks before rebuilding.
    - Android: `android/app/src/main/java/io/github/cidy02/kudos/works/WorkDetailScreen.kt:1045`
    - iOS: `kudos-ao3-reader/Features/WorkDetail/WorkProvenanceSections.swift:137`
11. **Row #116 — Read Aloud hold-seek on Previous/Next is missing (`3fo-result.md:40`, `A61-result.md:23`)**
    - Quote: `"ReaderSpeechController and its mini-player currently operate on a string paragraph queue, with no chapter-position seek callback or hold gesture."`
    - Harm: Holding Previous/Next while Read Aloud is paused cannot step through scaled visual-page positions (`ReaderSpeechSkip.seekIndex`).
    - Android: `android/app/src/main/java/io/github/cidy02/kudos/reader/speech/ReaderSpeechController.kt:162`
    - iOS: `kudos-ao3-reader/Features/ReaderReadium/ReaderSpeechSkip.swift:10`
12. **Row #85 — Read Aloud loads the entire work's prose before speaking the first word (`docs/android-port/briefs/3ea-read-aloud-text.md:23`)**
    - Quote: `"the rest of the work is read in before the first word, so a very long work may be slow to start"`
    - Harm: Starting Read Aloud on a multi-hundred-thousand-word work walks every spine eagerly before utterance 1.
    - Android: `android/app/src/main/java/io/github/cidy02/kudos/reader/ReaderContentText.kt:16`
    - iOS: `kudos-ao3-reader/Features/ReaderReadium/ReadiumReaderView.swift:1750`
13. **Row #88 — `AutomaticTTSService` checks offline voice availability only at init (`A49-result.md:133`)**
    - Quote: `"the offline check runs only at initialization, not before each utterance"`
    - Harm: If a neural voice pack is deleted or becomes unavailable mid-session, `AutomaticTTSService` does not re-check before each utterance.
    - Android: `android/app/src/main/java/io/github/cidy02/kudos/speech/AutomaticTTSService.kt:69`
    - iOS: `kudos-ao3-reader/Services/TTS/AutomaticTTSService.swift:45`
14. **Row #56 — First failing pull-to-refresh on Inbox replaces the kept page with an error (`LIVING-PROMPT.md:1052`)**
    - Quote: `"Both apps, P3, not changed: the Inbox shows 'Couldn't load your inbox' instead of its kept page on the first failing pull"`
    - Harm: Pulling to refresh an already-visible cached Inbox page when offline replaces the rows with the error state on the first failure.
    - Android: `android/app/src/main/java/io/github/cidy02/kudos/account/AccountInboxPane.kt:290`
    - iOS: `kudos-ao3-reader/Features/Account/AccountInboxViews.swift:566`
15. **Row #41 — Saving a bookmark on a work opened from Bookmarks does not update the list row on Back (`LIVING-PROMPT.md:883`)**
    - Quote: `"is a bookmark saved from a work opened out of the Bookmarks list shown in that list's row on the way back (P3)."`
    - Harm: Editing or creating a bookmark on Work Detail opened from the AO3 Bookmarks list does not refresh the Bookmarks row when popping back.
    - Android: `android/app/src/main/java/io/github/cidy02/kudos/account/AccountWorksListScreen.kt:140`
    - iOS: `kudos-ao3-reader/Features/Account/AO3BookmarksWorksBrowser.swift:28`
16. **Row #98 — In-app AO3 WebView fallback ignores `isForMainFrame` and demo external-link blocking (`3fg-result.md:155`, `A55-result.md:307`)**
    - Quote: `"Deferred A55 items: #9's WebView frame/demo behavior is untouched."`
    - Harm: Foreign iframe embeds in `AO3WebViewFallbackScreen` are externalized as if top-level navigations, and demo mode has no `BrowserThemeStyle.navigationVerdict` equivalent for external links.
    - Android: `android/app/src/main/java/io/github/cidy02/kudos/web/AO3WebViewFallbackScreen.kt:160`
    - iOS: `kudos-ao3-reader/Features/Browse/WebBrowser.swift:18`

### D. Looks, wording, and low-impact request-shape / test hygiene
17. **Row #99 — Search filter badge overcounts subject fandom and sort direction (`3fg-result.md:155`, `A55-result.md:95`)**
    - Quote: `"The lower-priority badge, long-press, tapped-tag passthrough, and filtered-tag adult-consent items are also untouched."` (badge item)
    - Harm: `activeFilterCount` counts the subject fandom and sort direction, disagreeing with the hero's Filters cell count.
    - Android: `android/app/src/main/java/io/github/cidy02/kudos/search/SearchFilterHelpers.kt:131`
    - iOS: `kudos-ao3-reader/Features/Search/SearchResultsHero.swift:320`
18. **Row #100 — Pagination arrows lack long-press jump to First/Last page (`3fg-result.md:155`, `A55-result.md:106`)**
    - Quote: `"arrowsUseTapForAdjacentAndLongPressForEnds: Android has separate First/Last buttons but no arrow long-press handler."`
    - Harm: Long-pressing the `<` / `>` buttons does not jump to page 1 / `totalPages` (separate `FirstPage` / `LastPage` icon buttons are right beside them).
    - Android: `android/app/src/main/java/io/github/cidy02/kudos/ui/components/KudosPaginationBar.kt:82`
    - iOS: `kudos-ao3-reader/Features/Search/SearchPaginationBar.swift:29`
19. **Row #101 — Filtered tag works URL omits `view_adult=true` and `utf8`/`commit` passthrough (`3fg-result.md:156`, `A55-result.md:45`)**
    - Quote: `"The lower-priority badge, long-press, tapped-tag passthrough, and filtered-tag adult-consent items are also untouched."` (tag URL items)
    - Harm: `buildFandomWorksUrl` omits `view_adult=true` and cosmetic `utf8=✓`/`commit=Sort and Filter` parameters when rebuilding a tapped tag URL.
    - Android: `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/search/AO3SearchUrlBuilder.kt:32`
    - iOS: `kudos-ao3-reader/Services/AO3Client.swift:1189`
20. **Row #102 — Challenge settings form replays hidden-zero + checked-one pairs for ticked checkboxes (`3fg-result.md:158`, `A55-result.md:332`)**
    - Quote: `"Challenge checkbox duplicate pairs remain unchanged"`
    - Harm: Ticked challenge checkboxes emit both the hidden `0` and checked `1` pair (Rails takes the last, so effective state is unchanged, but request pairs differ from iOS's deduplicated map).
    - Android: `android/app/src/main/java/io/github/cidy02/kudos/network/ao3/account/AO3ChallengeSettingsForm.kt:122`
    - iOS: `kudos-ao3-reader/Services/AO3ChallengeModels.swift:410`
21. **Row #124 — Add Chapter custom-date switch lacks explicit `"Custom publication date"` semantics label (`A64-result.md:9`)**
    - Quote: `"iOS labels the custom-date switch 'Custom publication date' ... while Android uses a plain Switchnext to the visible 'Publication date' row text"`
    - Harm: Screen readers see an unlabelled `Switch` beside the `"Publication date"` text instead of `"Custom publication date"`.
    - Android: `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingChapterFormScreen.kt:138`
    - iOS: `kudos-ao3-reader/Features/Writing/AddChapterView.swift:265`
22. **Row #35 — `WritingWorkActionsScreenTest` worker-thread view-touch flake (`LIVING-PROMPT.md:861`)**
    - Quote: `"WritingWorkActionsScreenTest's flake: the gate's reader prints a failure's stack trace now, so the next occurrence will say what touched a view"`
    - Harm: Intermittent Robolectric test failure when a worker thread touches a view during `WritingWorkActionsScreenTest`.
    - Android: `android/app/src/test/java/io/github/cidy02/kudos/writing/WritingWorkActionsScreenTest.kt:1`
    - iOS: `?`
23. **Row #47 — Five Robolectric tests close a Room DB in `@After` before Compose settles (`LIVING-PROMPT.md:923`)**
    - Quote: `"Five other test classes close a database in @After beside a Compose rule (ReaderHighlightEditorTest, FavoriteScopesScreenTest, LibraryHistoryScreenTest, WorkDetailSaveForLaterTest, WorkDetailShareTest)"`
    - Harm: Potential test teardown race if Compose accesses Room after `@After` closes the DB.
    - Android: `android/app/src/test/java/io/github/cidy02/kudos/reader/ReaderHighlightEditorTest.kt:52`
    - iOS: `?`
24. **Row #67 — `CommentsViewModelDraftTest` `Dispatchers.Main` race flake (`LIVING-PROMPT.md:1652`)**
    - Quote: `"Known flake: CommentsViewModelDraftTest (Dispatchers.Main race) failed twice once, passed twice alone."`
    - Harm: Test-only `Dispatchers.Main` race in `CommentsViewModelDraftTest`.
    - Android: `android/app/src/test/java/io/github/cidy02/kudos/comments/CommentsViewModelDraftTest.kt:1`
    - iOS: `?`
25. **Row #108 — Missing unit test for Clear History session-change-during-GET and 307/308 redirect refusal (`3fn-result.md:223`)**
    - Quote: `"a dedicated Clear History session-change-during-GET/pacing test and F1 redirect test remain valuable coverage gaps"`
    - Harm: Production code is fixed (`42155cc1`), but dedicated regression tests for those two branches are not yet written.
    - Android: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/writes/AO3WriteRepositoryTest.kt:1`
    - iOS: `KudosTests/AO3WriteDispatchFenceTests.swift:291`
26. **Row #113 — `RegexPortabilityTest` scans only `network/ao3` instead of full `main/java` (`A60-result.md:96`)**
    - Quote: `"Consider broadening RegexPortabilityTest.kt:13–20 from network/ao3 to the full main/java source tree"`
    - Harm: ICU regex portability lint test could miss an unescaped `{` outside `network/ao3`.
    - Android: `android/app/src/test/java/io/github/cidy02/kudos/network/ao3/RegexPortabilityTest.kt:13`
    - iOS: `?`

---

## 2. Open `verify` Rows Grouped by §7 Area

### Cross-Cutting (All §7 Rows: Four Themes, 2.0× Text, Process Death, Accessibility)
- **Row #1 (`LIVING-PROMPT.md:571`):** Full 4-theme (Sepia, Light, Dark, OLED) + largest text (2.0×) side-by-side pass against the iPhone across every §7 row so rows can advance from 🟦 to ✅.
- **Row #25 (`LIVING-PROMPT.md:815`):** Process-death / state-restoration checks for: Read Aloud playing and a download running through a kill; a note or highlight being made in the reader; a hardware keyboard being connected; a change of language while open.
- **Row #34 (`LIVING-PROMPT.md:857`):** Remaining screens in Light and OLED not yet walked in `3dw`/`3et`/`3eu` (e.g., Comments, Author pages, Challenges, Writing forms).
- **Row #43 (`LIVING-PROMPT.md:894`):** 2.0× large-text visual pass on series and tag-set forms, reader note editor, Find in Work, comment `"Continue thread"` (row 4), avatar initials (rows 7–8), and cover cards (rows 10–13).
- **Row #57 (`LIVING-PROMPT.md:1126`):** 2.0× large-text visual pass on work preview, participant read, Challenge Settings, tag set, and prompt meme.
- **Row #109 (`3fn-result.md:236`):** Visual inspection of reader skeleton bounds and remaining Dark surfaces (`#1C1C1E`).

### Library & Reading Queues (§7 Row 1)
- **Row #13 (`LIVING-PROMPT.md:712`):** `AddSelectionToCollectionDialog` manual/emulator check (Robolectric hung / OOM'd on two dialog tests in `3fp`).
- **Row #22 (`LIVING-PROMPT.md:745`):** Bulk `Download` action in a queue where works do not already have a local EPUB copy (`3fp` F11).
- **Row #123 (`3fq-result.md:145`):** Emulator visual check of bulk remote `Download` partial failure / cancellation and Home/Library/Search/Account action fixes from `3fq`.

### Search, Browse & Fandoms (§7 Row 2)
- **Row #91 (`A53-result.md:23`):** Manual emulator check of `SaveSearchSheet` over `SearchFilterSheet` (Back navigation, focus, and keyboard dismissal).
- **Row #123 (`3fq-result.md:245`):** TalkBack check of the Fandom list alphabet scrubber adjustment action (`F32`, `browse/FandomListChrome.kt`).

### Work Detail & Comments (§7 Row 3)
- **Row #39 (`LIVING-PROMPT.md:870`):** Emulator check of Chapter Comments from Work Detail (`3fp` F08).
- **Row #59 (`LIVING-PROMPT.md:1150`):** Remaining fourteen rows of `3ca` (`WorkDetailScreen`), `"Show in Library"`, and `"Share Profile"`.

### Reader & Read Aloud (§7 Row 4)
- **Row #2 (`LIVING-PROMPT.md:588`):** Put the Android reader and its controls beside the iPhone's across all four themes and largest text sizes (including landscape and paged mode, `LIVING-PROMPT.md:858`).
- **Row #39 (`LIVING-PROMPT.md:870`):** Emulator check of reader note editor and Find in Work at 2.0× text.

### Account Lists: History, Bookmarks, Marked for Later, Subscriptions, Inbox (§7 Row 5)
- **Row #39 (`LIVING-PROMPT.md:870`):** Emulator check of `3cg` (History/Subscriptions/Marked for Later with a change of signed-in reader) and `3cf` (bookmark date changed and saved).
- **Row #49 (`LIVING-PROMPT.md:932`):** TalkBack pass on the Favorite Authors block and author cards.
- **Row #80 (`LIVING-PROMPT.md:1767`):** Visual check of two covers on one line in Compact mode (no demo list draws two covers on one line).

### Authors & Series (§7 Row 6)
- **Row #8 (`LIVING-PROMPT.md:593`):** Full like-for-like visual pairing of Author profile / Dashboard / Series detail beside the iPhone's across themes.

### Collections & Challenges (§7 Row 7)
- **Row #68 (`LIVING-PROMPT.md:1654`) & Row #125 (`A64-result.md:16`):** Complete the full action and visual parity audit of Challenges (and Writing) that stopped when the iOS login expired during `A64`.

### Writing: Work Form, Chapter Form, Rich-Text Editor, Bulk Edit (§7 Row 8)
- **Row #27 (`LIVING-PROMPT.md:834`):** Emulator walkthrough of Series Reorder and Remove works, the preview before posting, and the rich-text editor.
- **Row #60 (`LIVING-PROMPT.md:1216`):** Emulator check of the keyboard closing when leaving the writing editor (`3bf`), the work form's date picker, and the Work text row.
- **Row #68 (`LIVING-PROMPT.md:1654`) & Row #125 (`A64-result.md:16`):** Complete the `A64` action parity audit of Writing (`Features/Writing/` vs `writing/`).

### Onboarding, Support, About & Settings (§7 Row 9)
- **Row #11 (`LIVING-PROMPT.md:600`):** Visual side-by-side check of Support screen (`SettingsSupportScreen.kt` vs `SupportKudosView.swift`; strings were compared in `2f00aa6a`).
- **Row #71 (`LIVING-PROMPT.md:1685`):** Emulator check of backup import and export completion messages via the SAF file picker.

---

## 3. Full Ledger of Open-Looking Notes (2026-10-08 to 2026-10-16)

| # | Note (quote, ≤25 words) | Where (`file:line`) | Kind | Closed by (quote + `file:line` or commit) | Verdict |
|---|---|---|---|---|---|
| 1 | `"No row has gone from 🟦 to ✅ since 10-08, because nobody has taken a row through four themes and the largest text"` | `docs/android-port/LIVING-PROMPT.md:571` | `verify` | — | `OPEN` |
| 2 | `"read aloud is built (3ak, reader/speech/) ... not put beside the iPhone's"` | `docs/android-port/LIVING-PROMPT.md:588` | `verify` | — | `OPEN` |
| 3 | `"read aloud is built (3ak, reader/speech/) but not heard since: an emulator has no ears"` | `docs/android-port/LIVING-PROMPT.md:588` | `device` | — | `OPEN` |
| 4 | `"the look of its controls waits on owner question 12"` | `docs/android-port/LIVING-PROMPT.md:588` | `owner` (§11 Q12) | — | `OPEN` |
| 5 | `"3an Unsubscribe, fixtures only"` | `docs/android-port/LIVING-PROMPT.md:591` | `device` | — | `OPEN` |
| 6 | `"3co Clear History, second review owed"` | `docs/android-port/LIVING-PROMPT.md:591` | `code` | `"Both F1 and F2 are now fixed on Android (42155cc1) and iOS (T-417)"` (`docs/android-port/DECISIONS.md:2199`, commit `42155cc1`) | `CLOSED` |
| 7 | `"series page 3z, not seen with works: no demo fixture"` | `docs/android-port/LIVING-PROMPT.md:593` | `verify` | `"3da (8b14b15f): AO3 Series page on the emulator: Works (1–2 of 2)"` (`docs/android-port/LIVING-PROMPT.md:1750`, commit `8b14b15f`) | `CLOSED` |
| 8 | `"Authors ... not yet paired like for like with the iPhone's"` | `docs/android-port/LIVING-PROMPT.md:593` | `verify` | — | `OPEN` |
| 9 | `"Challenges ... Writes run against fixtures only."` | `docs/android-port/LIVING-PROMPT.md:595` | `device` | — | `OPEN` |
| 10 | `"Writing ... Writes run against fixtures only; the editor's widget not yet measured on a phone"` | `docs/android-port/LIVING-PROMPT.md:596` | `device` | — | `OPEN` |
| 11 | `"Support not looked at"` | `docs/android-port/LIVING-PROMPT.md:600` | `verify` | — | `OPEN` |
| 12 | `"Data parity ... never tried on two real phones"` | `docs/android-port/LIVING-PROMPT.md:601` | `device` | — | `OPEN` |
| 13 | `"Robolectric can't settle AddSelectionToCollectionDialog (two tests hung; one ran the test JVM out of memory)."` | `docs/android-port/LIVING-PROMPT.md:712` | `verify` | — | `OPEN` |
| 14 | `"A62 is done but for F21/F22 (owner Q12)"` | `docs/android-port/LIVING-PROMPT.md:714` | `owner` (§11 Q12) | — | `OPEN` |
| 15 | `"deferred #2/#5 (reader link gesture: an owner choice, since an imported EPUB may use a script to move between its own chapters)"` | `docs/android-port/LIVING-PROMPT.md:717` | `owner` (§11 Q12 / §11 reader gesture note `:1644`) | — | `OPEN` |
| 16 | `"left #29 (owner Q12)"` (compact reader section pill labels P/S/N/M/A) | `docs/android-port/LIVING-PROMPT.md:719` | `owner` (§11 Q12) | `"## 2026-10-16 — A61 resolved (3fo, 860c39f7 and 82f536b9)"` (`docs/android-port/DECISIONS.md:2234`, `:2244`) | `CLOSED-BY-DECISION` |
| 17 | `"#31 (design)"` (shared `ErrorStateCard` single warning icon vs offline symbol) | `docs/android-port/LIVING-PROMPT.md:719` | `design` | `"## 2026-10-16 — A61 resolved (3fo, 860c39f7 and 82f536b9)"` (`docs/android-port/DECISIONS.md:2234`, `:2245`) | `CLOSED-BY-DECISION` |
| 18 | `"Left: 3fm's rows"` (remaining A59 missing rows) | `docs/android-port/LIVING-PROMPT.md:727` | `code` | `"3fm (446888ee): the rest of A59"` (`docs/android-port/LIVING-PROMPT.md:1666`, commit `446888ee`) | `CLOSED` |
| 19 | `"Left: ... A58's deferred cosmetic items"` (#7, #11, #12, #13, #16, #19, #20) | `docs/android-port/LIVING-PROMPT.md:727` | `code` | `"3fn part 1 (06293acb): the five remaining A58 items (#7, #11, #12, #16, #19; #13 and #20 were closed in e2963490 and 7fcb9725)"` (`docs/android-port/LIVING-PROMPT.md:1662`, commits `e2963490`, `7fcb9725`, `06293acb`) | `CLOSED` |
| 20 | `" What is left is owner question 23 (Blur mode's Reorder screen, a search or filter answering for a blurred work...)"` | `docs/android-port/LIVING-PROMPT.md:732` | `owner` (§11 Q23) | — | `OPEN` |
| 21 | `"Three second reviews are still owed (3ci, 3co Clear History, 3df)."` | `docs/android-port/LIVING-PROMPT.md:738` | `code` | `"## 2026-10-15 — A50 second review closed (3ei–3el)"` (`docs/android-port/DECISIONS.md:1894`, commits `0dce4dae`, `226b3a4d`, `acce50d8`, `afe9d5e4`, `42155cc1`) | `CLOSED` |
| 22 | `"Not run: Download (every demo work in a queue has its copy)."` | `docs/android-port/LIVING-PROMPT.md:745` | `verify` | — | `OPEN` |
| 23 | `"Not yet compared: sheets and their sizes, the words on buttons inside forms."` | `docs/android-port/LIVING-PROMPT.md:751` | `code` | `"3fe (1186ce9f): filter sheets open at half height"` + `"3fp (b67cf686, 0eba1d83, af14c5f7): A62's 31 findings"` (`docs/android-port/LIVING-PROMPT.md:1656,1678`, commits `1186ce9f`, `af14c5f7`, `e9583487`) | `CLOSED` |
| 24 | `"Second review owed on 3df before closing."` | `docs/android-port/LIVING-PROMPT.md:779` | `code` | `"3ei (0dce4dae): A50 F1 and F2 (3df)"` (`docs/android-port/LIVING-PROMPT.md:1710`, commit `0dce4dae`) | `CLOSED` |
| 25 | `"Left unchecked, each small: Read Aloud playing and a download running through a kill; a note or highlight being made in the reader; a hardware keyboard being connected; a change of language while open."` | `docs/android-port/LIVING-PROMPT.md:815` | `verify` | — | `OPEN` |
| 26 | `"3dn — the rest of Writing on the emulator (done: 0aa9e6d0)"` | `docs/android-port/LIVING-PROMPT.md:833` | `verify` | `"3dn (0aa9e6d0): the Writing forms on the emulator"` (`docs/android-port/LIVING-PROMPT.md:1735`, commit `0aa9e6d0`) | `CLOSED` |
| 27 | `"what was not (Reorder and Remove works, the preview before posting, the rich-text editor)"` | `docs/android-port/LIVING-PROMPT.md:834` | `verify` | — | `OPEN` |
| 28 | `"3du — what is left of Challenges, each small: a sign-up's own page, a tag set's page, 'Your items' on the AO3 Collections list, the Recently decided list, 'Withdraw sign-up'"` | `docs/android-port/LIVING-PROMPT.md:842` | `code` | `"3du (b1241f29)"`, `"3er (6edc6860)"`, `"3es (91416466): Tag Set page built on Android"` (`docs/android-port/LIVING-PROMPT.md:1695–1696,1725`, commits `b1241f29`, `6edc6860`, `91416466`) | `CLOSED` |
| 29 | `"3ci's second review (still owed; do before closing the item)"` | `docs/android-port/LIVING-PROMPT.md:846` | `code` | `"3ej (226b3a4d): A50 F3 and F4 (3ci)"` (`docs/android-port/LIVING-PROMPT.md:1709`, commit `226b3a4d`) | `CLOSED` |
| 30 | `"3dv — Reading Insights, Availability Sweep and the empty states in Dark (done: f1938c17)"` | `docs/android-port/LIVING-PROMPT.md:848` | `verify` | `"3dv (f1938c17): Reading Insights, Check AO3 Availability and the empty states in Dark"` (`docs/android-port/LIVING-PROMPT.md:1722`, commit `f1938c17`) | `CLOSED` |
| 31 | `"3dw — Light and OLED spot check (first pass done: 3eb948e6)"` | `docs/android-port/LIVING-PROMPT.md:851` | `verify` | `"3dw (3eb948e6): Light and OLED on the emulator"` (`docs/android-port/LIVING-PROMPT.md:1720`, commit `3eb948e6`) | `CLOSED` |
| 32 | `"3dx — the rest of the screens in Dark (done: 26aa80a3)"` | `docs/android-port/LIVING-PROMPT.md:854` | `verify` | `"3dx (26aa80a3): the remaining screens in Dark"` (`docs/android-port/LIVING-PROMPT.md:1718`, commit `26aa80a3`) | `CLOSED` |
| 33 | `"3dy — the reader in four themes, and the rest of Dark (done: e6bd281a)"` | `docs/android-port/LIVING-PROMPT.md:856` | `verify` | `"3dy (e6bd281a): the reader in Light, Sepia, Dark and OLED"` (`docs/android-port/LIVING-PROMPT.md:1716`, commit `e6bd281a`) | `CLOSED` |
| 34 | `"then the same passes in Light and OLED (3dw did Home, Library, Account, Settings and a work's page)."` | `docs/android-port/LIVING-PROMPT.md:857` | `verify` | — | `OPEN` |
| 35 | `"WritingWorkActionsScreenTest's flake: the gate's reader prints a failure's stack trace now"` (Android `WritingWorkActionsScreenTest.kt:1`, iOS `?`) | `docs/android-port/LIVING-PROMPT.md:861` | `code` | — | `OPEN` |
| 36 | `"Library's fandom chips, Home's 'Last opened', Account glyphs, iOS Search's white page"` | `docs/android-port/LIVING-PROMPT.md:864` | `code` | `"3dp (2431bcde)"`, `"3do (03cb6d25)"`, `"3cp (e63f263a)"`, `"iOS T-405 (a5daf903)"` (`docs/android-port/LIVING-PROMPT.md:1714,1733,1734,1791`) | `CLOSED` |
| 37 | `"Then the rest of A35's leftovers on the iPhone at AX5 (Prompt Meme, Assignments, the work form, the chapter form, the tag picker, the preview)"` | `docs/android-port/LIVING-PROMPT.md:867` | `ios` | `"iOS T-411..T-413: the remaining A35 large-text items are fixed; the six unseen screens ... were walked on the iPhone 17 simulator at AX5"` (`docs/android-port/LIVING-PROMPT.md:1691`, commits `e2fb9200`, `bd0c1fc4`, `b0b251c4`) | `CLOSED` |
| 38 | `"Account's 'Posting as…' chip ... and the comments stat strip's date"` at double text size | `docs/android-port/LIVING-PROMPT.md:869` | `code` | `"3cq (e72bc1b6): Account's 'Posting as…' pill wraps"`, `"3cs (233be299, 297d74fd): the comments stat strip's date stays whole"` (`docs/android-port/LIVING-PROMPT.md:1788–1789`) | `CLOSED` |
| 39 | `"A36's (series and tag-set forms, reader note editor and Find in Work), and the emulator checks not done (3cg with a change of reader, 3cf date changed and saved, Chapter Comments)."` | `docs/android-port/LIVING-PROMPT.md:870` | `verify` | — | `OPEN` |
| 40 | `"Not yet compared between the apps the way confirmations and pull to refresh were: .swipeActions, .contextMenu, .searchable."` | `docs/android-port/LIVING-PROMPT.md:880` | `code` | `"Comparison, swipe actions and long-press menus: all 31 on Android by their words; search fields: 4 of 5"` (`docs/android-port/LIVING-PROMPT.md:1794`, plus `A62`/`A63`/`3fp`/`3fq`) | `CLOSED` |
| 41 | `"One question left on both: is a bookmark saved from a work opened out of the Bookmarks list shown in that list's row on the way back (P3)."` (Android `account/AccountWorksListScreen.kt:140`, iOS `Features/Account/AO3BookmarksWorksBrowser.swift:28`) | `docs/android-port/LIVING-PROMPT.md:883` | `code` | — | `OPEN` |
| 42 | `"Still to look at: ... the collection form; the Library's section pages ... the login screens"` at double text size | `docs/android-port/LIVING-PROMPT.md:894` | `verify` | `"Done (504443df): the six Library sections, both login screens and the collection form at 2.0×"` (`docs/android-port/LIVING-PROMPT.md:905`, commit `504443df`) | `CLOSED` |
| 43 | `"Still to look at: the series ... and tag-set forms; ... the reader's note editor and Find in Work; ... 'Continue thread' (row 4), avatar initials (7, 8), cover cards (10 to 13)."` | `docs/android-port/LIVING-PROMPT.md:894` | `verify` | — | `OPEN` |
| 44 | `"Left of W3: the hints (rows 17 to 21)"` | `docs/android-port/LIVING-PROMPT.md:918` | `code` | `"## 2026-10-13 — W3 TalkBack hints (2fd287ff)"` (`docs/android-port/DECISIONS.md:1640`, commit `2fd287ff`) | `CLOSED-BY-DECISION` |
| 45 | `"Left of W3: ... a pull to refresh on comments while offline (not looked into)"` | `docs/android-port/LIVING-PROMPT.md:918` | `code` | `"## 2026-10-12 — Comments pull-to-refresh keeps loaded threads on failure (adeb9618)"` (`docs/android-port/DECISIONS.md:1493`, commit `adeb9618`) | `CLOSED-BY-DECISION` |
| 46 | `"Left of W3: ... whether an Inbox card's selected state is spoken"` | `docs/android-port/LIVING-PROMPT.md:919` | `code` | `"3cl (ba4b2d04): ... an Inbox card in selection mode now gives its checked state to TalkBack"` (`docs/android-port/LIVING-PROMPT.md:1800`, commit `ba4b2d04`) | `CLOSED` |
| 47 | `"Five other test classes close a database in @After beside a Compose rule (ReaderHighlightEditorTest, FavoriteScopesScreenTest, LibraryHistoryScreenTest, WorkDetailSaveForLaterTest, WorkDetailShareTest)"` (Android `ReaderHighlightEditorTest.kt:52`, iOS `?`) | `docs/android-port/LIVING-PROMPT.md:923` | `code` | — | `OPEN` |
| 48 | `"A second review is owed on 78beddc1, 1b25f24d, 36b8ebe5 and 2ddab9c7."` (Favorite authors) | `docs/android-port/LIVING-PROMPT.md:931` | `code` | `"3ek (acce50d8): A50 F5–F9 (Favorite authors)"` (`docs/android-port/LIVING-PROMPT.md:1708`, commit `acce50d8`) | `CLOSED` |
| 49 | `"Not seen: a real library (the user's own, or an imported backup with several works per author); TalkBack on the new block."` | `docs/android-port/LIVING-PROMPT.md:932` | `verify` | — | `OPEN` |
| 50 | `"Lead: in the Authors row a one-word name breaks mid-word at double text size."` | `docs/android-port/LIVING-PROMPT.md:942` | `code` | `"3cl-2 (504443df): ... at large text a work card's fandom line and a favorite author's name are whole"` (`docs/android-port/LIVING-PROMPT.md:1803`, commit `504443df`) | `CLOSED` |
| 51 | `"Second review owed on 3ch."` (Author pages) | `docs/android-port/LIVING-PROMPT.md:947` | `code` | `"3el (afe9d5e4): A50 F10 and F11 (3ch)"` (`docs/android-port/LIVING-PROMPT.md:1707`, commit `afe9d5e4`) | `CLOSED` |
| 52 | `"a small iOS lead: after deleting a work its line keeps the old words and kudos until the page is reopened"` | `docs/android-port/LIVING-PROMPT.md:949` | `ios` | — | `OPEN` |
| 53 | `"iOS leads, not changed: ... a comment's own thread, ... taller of two series cards, ... menu picker's chosen value is one line, ... time zone breaks inside '(GMT-05:00)', ... collection's cover card does not grow, ... Dashboard fandom chip loses its count, ... card's fandom kicker is one line"` | `docs/android-port/LIVING-PROMPT.md:998` | `ios` | — | `OPEN` |
| 54 | `"iOS T-377, T-378 and T-379 were not seen on the simulator at all"` | `docs/android-port/LIVING-PROMPT.md:1031` | `ios` | — | `OPEN` |
| 55 | `"Android, P3, not changed (found at 06:07): a collection's page forgets its segment and its place, and reads its page again, every time the reader comes back from one of its Manage screens"` (Android `account/AO3CollectionDetailScreen.kt:85`, iOS `Features/Account/AO3CollectionDetailView.swift:23`) | `docs/android-port/LIVING-PROMPT.md:1035` | `code` | — | `OPEN` |
| 56 | `"Both apps, P3, not changed: the Inbox shows 'Couldn't load your inbox' instead of its kept page on the first failing pull after opening"` (Android `account/AccountInboxPane.kt:290`, iOS `Features/Account/AccountInboxViews.swift:566`) | `docs/android-port/LIVING-PROMPT.md:1052` | `code` | — | `OPEN` |
| 57 | `"Not yet seen at that size: the work preview, ... the participant read, ... Challenge Settings, the tag set, the prompt meme."` (2.0× text) | `docs/android-port/LIVING-PROMPT.md:1126` | `verify` | — | `OPEN` |
| 58 | `"iOS, P3, not fixed: a collection row's chips shrink to stubs; ... Work Detail's four stat captions truncate."` (series row figures fixed in `T-387`) | `docs/android-port/LIVING-PROMPT.md:1136` | `ios` | — | `OPEN` |
| 59 | `"Still owed: the other fourteen rows of 3ca, 'Show in Library', 'Share Profile'; on the simulator T-371's series form scroll."` | `docs/android-port/LIVING-PROMPT.md:1150` | `verify` | — | `OPEN` |
| 60 | `"Not seen on the emulator: the keyboard closing when the editor is left (3bf, two lines); the work form's date picker and Work text row."` | `docs/android-port/LIVING-PROMPT.md:1216` | `verify` | — | `OPEN` |
| 61 | `"Rebuild from Original in the menu (Android cannot tell a stale conversion)"` + `"the reader's 'Rebuild from Original' pill"` (Android `works/WorkDetailScreen.kt:1045`, iOS `Features/WorkDetail/WorkProvenanceSections.swift:137`) | `docs/android-port/LIVING-PROMPT.md:1379` | `code` | — | `OPEN` |
| 62 | `"Owed on a phone before the editor's native text field is accepted: B1 (a keystroke within 16 ms) and B6 (open within 300 ms) with the 510,000-character chapter ... composing Japanese or Chinese."` | `docs/android-port/LIVING-PROMPT.md:1218` | `device` | — | `OPEN` |
| 63 | `"Never run against AO3, and owed a check on a real signed-in phone before a release: Unsubscribe (3an)."` | `docs/android-port/LIVING-PROMPT.md:1259` | `device` | — | `OPEN` |
| 64 | `"the queued-flag part is held for owner question 7"` (`SavedWork.isQueuedForLater` retirement) | `docs/android-port/LIVING-PROMPT.md:1324` | `owner` (§11 Q7) | — | `OPEN` |
| 65 | `"Left: iOS also gives back the toolbar's bookmark on the same page (it matches Readium's position; Android matches the stored locator)."` | `docs/android-port/LIVING-PROMPT.md:1376` | `code` | `"## 2026-10-16 — A62 part 1: data-loss, confirmation and navigation fixes (3fp, b67cf686)"` (`docs/android-port/DECISIONS.md:2261`, commit `b67cf686`) | `CLOSED` |
| 66 | `"iOS §5c item 3: ... The composer and thread screen are still unseen"` | `docs/android-port/LIVING-PROMPT.md:1647` | `ios` | — | `OPEN` |
| 67 | `"Known flake: CommentsViewModelDraftTest (Dispatchers.Main race) failed twice once, passed twice alone."` (Android `CommentsViewModelDraftTest.kt:1`, iOS `?`) | `docs/android-port/LIVING-PROMPT.md:1652` | `code` | — | `OPEN` |
| 68 | `"A64 (Writing, Challenges): Gemini stopped on an expired login... A full action audit of Writing and Challenges waits for Codex (back 2026-10-22) or Gemini"` | `docs/android-port/LIVING-PROMPT.md:1654` | `verify` | — | `OPEN` |
| 69 | `"The document converter's gaps are recorded as a feature, not a fault."` | `docs/android-port/LIVING-PROMPT.md:1674` | `design` | `"## 2026-10-15 — Imported-document converter (HTML / TXT / PDF) vs iOS"` (`docs/android-port/DECISIONS.md:2022`) | `CLOSED-BY-DECISION` |
| 70 | `"Noted, not copied: iOS's Library collection page hashes a work's raw first fandom ('Doctor Who (2005)', pink) where its other screens and Android use the bare fandom (purple)."` | `docs/android-port/LIVING-PROMPT.md:1683` | `ios` | — | `OPEN` |
| 71 | `"Not seen on the emulator: the import and export messages (the SAF picker; the messages are tested)."` | `docs/android-port/LIVING-PROMPT.md:1685` | `verify` | — | `OPEN` |
| 72 | `"Left: iOS's cover tile shows no author for an anonymous work while its rows say 'by Anonymous' (iOS-only, small)."` | `docs/android-port/LIVING-PROMPT.md:1686` | `ios` | — | `OPEN` |
| 73 | `"Left, recorded: an ordinary read opened in that window can still join (iOS documents the same limit)."` | `docs/android-port/LIVING-PROMPT.md:1690` | `design` | `"## 2026-10-15 — Post-write verification read does not join a pre-write read in flight (3ex, a04697ed)"` (`docs/android-port/DECISIONS.md:1932`) | `CLOSED-BY-DECISION` |
| 74 | `"Lead: an author page's loading card sits under the top bar for a moment."` | `docs/android-port/LIVING-PROMPT.md:1697` | `code` | `"3et (a26c7883): ... and an author page's loading card moved below the bar"` (`docs/android-port/LIVING-PROMPT.md:1694`, commit `a26c7883`) | `CLOSED` |
| 75 | `"A37 left: F3 (a post-write read joining a pre-write read in flight)"` | `docs/android-port/LIVING-PROMPT.md:1697` | `code` | `"3ex (a04697ed): A51 F4 / A37 F3"` (`docs/android-port/LIVING-PROMPT.md:1690`, commit `a04697ed`) | `CLOSED` |
| 76 | `"A37 left: ... F6 (bulk form controls for unserved groups; iOS the same), F7 (a partial bulk tag run; recorded in 3cd)."` | `docs/android-port/LIVING-PROMPT.md:1697` | `design` | — | `OPEN` |
| 77 | `"Left: a session ends after 80,000 characters; Read author's notes."` | `docs/android-port/LIVING-PROMPT.md:1706` | `code` | `"3ed (f56ab6bc): Read Aloud no longer cuts off a long work at 80,000 characters"`, `"3ee (cdc33861): 'Read author's notes' setting"` (`docs/android-port/LIVING-PROMPT.md:1703–1704`) | `CLOSED` |
| 78 | `"TagWorksScreen found unreachable (candidate for removal)."` | `docs/android-port/LIVING-PROMPT.md:1712` | `code` | `"3ec (0b679d91): removed the unreachable TagWorksScreen"` (`docs/android-port/LIVING-PROMPT.md:1705`, commit `0b679d91`) | `CLOSED` |
| 79 | `"Two things Android leaves out on purpose on Challenge (assignment counts, the pinch-hitter sentence) were checked against the code's own note and left."` (pinch-hitter closed in `3er` `6edc6860`; assignment counts waits on Q16) | `docs/android-port/LIVING-PROMPT.md:1747` | `owner` (§11 Q16) | — | `OPEN` |
| 80 | `"Not seen: two covers on one line (no demo list draws them). Android still opens on Ledger."` (opening on Compact closed in `3fb` `e66684a8`) | `docs/android-port/LIVING-PROMPT.md:1767` | `verify` | — | `OPEN` |
| 81 | `"Left as it is: a library copy draws the AO3 ledger body where iOS draws its library row; Unmark stays under the card."` | `docs/android-port/LIVING-PROMPT.md:1775` | `code` | `"## 2026-10-16 — A63 part 2: remote selection, local-match parity, and comment threads (3fq, b5a21a66)"` (`docs/android-port/DECISIONS.md:2310`, commit `b5a21a66`) | `CLOSED` |
| 82 | `"Three rows are different on purpose and recorded: iOS has a separate 'Sync Details' screen, 'Scan a QR Code' ... and 'Add Saved Works to Saved for Later'; Android has Replace's second-attempt 'I understand the risks' checkbox"` | `docs/android-port/LIVING-PROMPT.md:1781` | `design` | `"## 2026-10-16 — Settings & About parity audit (2f00aa6a)"` (`docs/android-port/DECISIONS.md:2343`, `:1628`) | `CLOSED-BY-DECISION` |
| 83 | `"Not seen: a real AO3 help page (by rule)."` | `docs/android-port/LIVING-PROMPT.md:1785` | `device` | — | `OPEN` |
| 84 | `"Not seen: the undo pages (tests only); the demo keeps no mute or block."` | `docs/android-port/LIVING-PROMPT.md:1787` | `device` | — | `OPEN` |
| 85 | `"the rest of the work is read in before the first word, so a very long work may be slow to start; walk content.iterator() lazily if that shows."` (Android `reader/ReaderContentText.kt:16`, iOS `Features/ReaderReadium/ReadiumReaderView.swift:1750`) | `docs/android-port/briefs/3ea-read-aloud-text.md:23` | `code` | — | `OPEN` |
| 86 | `"Pronunciation dictionary, model/compute unit choices, pause/chunk developer settings"` out of scope for Android Read Aloud | `docs/android-port/briefs/3ea-read-aloud-text.md:31` | `design` | `"## 2026-10-14 — Read Aloud reads the EPUB's prose and offers Automatic"` (`docs/android-port/DECISIONS.md:1884`, `A62-result.md:718`) | `CLOSED-BY-DECISION` |
| 87 | `"The reader's Display & Themes sheet does not have it yet: the reader's controls wait on owner question 12."` (`Read author's notes` in reader sheet) | `docs/android-port/briefs/3ee-read-authors-notes.md:13` | `owner` (§11 Q12) | — | `OPEN` |
| 88 | `"the offline check runs only at initialization, not before each utterance"` (Android `speech/AutomaticTTSService.kt:69`, iOS `Services/TTS/AutomaticTTSService.swift:45`) | `docs/android-port/audits/A49-result.md:133` | `code` | — | `OPEN` |
| 89 | `"F10 — P3: SearchFilterHelpers.kt:238–244 — rounded lower-bound label can contradict the works it admits"` | `docs/android-port/audits/A49-result.md:309` | `design` | `"## 2026-10-15 — A49 audit resolved (3ef, 3eg, 3eh)"` (`docs/android-port/DECISIONS.md:1891`) | `CLOSED-BY-DECISION` |
| 90 | `"That same 503 branch can internally repeat a GET outside the coordinator too."` (Android `network/ao3/AO3Client.kt:129`, iOS `Services/AO3Client.swift:30`) | `docs/android-port/audits/A51-result.md:49` | `code` | — | `OPEN` |
| 91 | `"F3 — P2: AO3CommentRepository.kt:111–132 — new chapter comment can be posted as a work-level comment"` | `docs/android-port/audits/A51-result.md:160` | `design` | `"## 2026-10-15 — A51 write audit resolved (3ev 6bdc52b7, 3ew e44f64d6; F3 not a fault)"` (`docs/android-port/DECISIONS.md:1915`, `:1927`) | `CLOSED-BY-DECISION` |
| 92 | `"Back, focus and keyboard remain a manual boundary"` (`SaveSearchSheet` over `SearchFilterSheet`) | `docs/android-port/audits/A53-result.md:23` | `verify` | — | `OPEN` |
| 93 | `"Can two records collide? Yes; two genuinely different works require inconsistent identity data ... Not a 3fc regression; hardening would be a separate cross-platform design change"` | `docs/android-port/audits/A53-result.md:35` | `design` | — | `OPEN` |
| 94 | `"4. Repeated deletions: by design. ... 5. Queue clock clamp: by design. ... 7. First moved callback / trailing debounce: not a fault as shown. ... 9. Ambiguous font files, 10. conflict totals, 11. trust-key display: no data lost ... Recorded, not changed."` | `docs/android-port/audits/A52-result.md:266` | `design` | `"## 2026-10-15 — Backup/sync parity fixes from A52 (3ez, cbe9b859)"` (`docs/android-port/DECISIONS.md:1939`, `A52-result.md:266–278`) | `CLOSED-BY-DECISION` |
| 95 | `"Merge/Reconcile intentionally retain partial apply: only Replace rolls back its whole library replacement on asset write failure."` | `docs/android-port/briefs/3fa-result.md:77` | `design` | `"## 2026-10-15 — Transactional Replace rollback and incomplete-backup disclosure (3fa, 49da9d98)"` (`docs/android-port/DECISIONS.md:1959`) | `CLOSED-BY-DECISION` |
| 96 | `"The existing ungated file-writer race is unchanged."` (Android `works/WorkFileStore.kt:42`, iOS `Services/PersistenceOperationGate.swift:18`) | `docs/android-port/briefs/3fa-result.md:92` | `code` | — | `OPEN` |
| 97 | `"Sync may remain paused after a failed Replace, as before."` (Android `backup/BackupRepository.kt:129`, iOS `Services/KudosBackupService.swift:612`) | `docs/android-port/briefs/3fa-result.md:95` | `code` | — | `OPEN` |
| 98 | `"Deferred A55 items: #9's WebView frame/demo behavior is untouched."` (Android `web/AO3WebViewFallbackScreen.kt:160`, iOS `Features/Browse/WebBrowser.swift:18`) | `docs/android-port/briefs/3fg-result.md:155` | `code` | — | `OPEN` |
| 99 | `"The lower-priority badge, long-press, tapped-tag passthrough, and filtered-tag adult-consent items are also untouched."` — filter badge overcount (`A55-result.md:95`, Android `search/SearchFilterHelpers.kt:131`, iOS `Features/Search/SearchResultsHero.swift:320`) | `docs/android-port/briefs/3fg-result.md:155` | `code` | — | `OPEN` |
| 100 | `"The lower-priority badge, long-press..."` — pagination arrow long-press (`A55-result.md:106`, Android `ui/components/KudosPaginationBar.kt:82`, iOS `Features/Search/SearchPaginationBar.swift:29`) | `docs/android-port/briefs/3fg-result.md:155` | `code` | — | `OPEN` |
| 101 | `"...tapped-tag passthrough, and filtered-tag adult-consent items are also untouched."` (`A55-result.md:45,48`, Android `network/ao3/search/AO3SearchUrlBuilder.kt:32`, iOS `Services/AO3Client.swift:1189`) | `docs/android-port/briefs/3fg-result.md:156` | `code` | — | `OPEN` |
| 102 | `"Challenge checkbox duplicate pairs remain unchanged"` (`A55-result.md:332`, Android `network/ao3/account/AO3ChallengeSettingsForm.kt:122`, iOS `Services/AO3ChallengeModels.swift:410`) | `docs/android-port/briefs/3fg-result.md:158` | `code` | — | `OPEN` |
| 103 | `"SameSite remains unresolved. java.net.HttpCookie has no standard SameSite accessor"` | `docs/android-port/briefs/3fk-result.md:106` | `design` | `"## 2026-10-15 — Client host boundary, identity-only cookies, and empty-blurb guard (3fk, c682c744)"` (`docs/android-port/DECISIONS.md:2030`) | `CLOSED-BY-DECISION` |
| 104 | `"Gift recipients: conditional skip. ... Adding a new gift/recipient field requires model/database/UI plumbing"` | `docs/android-port/briefs/3fk2-result.md:135` | `design` | `"## 2026-10-15 — EPUB preflight, availability refresh, and work-page status parity (3fk-2, c31f1417)"` (`docs/android-port/DECISIONS.md:2042`) | `CLOSED-BY-DECISION` |
| 105 | `"A58 #7, #11, #12, #13, #16, #19 and #20 remain unchanged"` | `docs/android-port/briefs/3fl-result.md:50` | `code` | `"3fn part 1 (06293acb): the five remaining A58 items (#7, #11, #12, #16, #19; #13 and #20 were closed in e2963490 and 7fcb9725)"` (`docs/android-port/LIVING-PROMPT.md:1662`, commits `e2963490`, `7fcb9725`, `06293acb`) | `CLOSED` |
| 106 | `"F1 — P2: AccountListRepository.kt:123–149 — Clear History's token GET runs outside the write coordinator"` + `"F2 — P2: ... author-write bare-redirect verification"` | `docs/android-port/briefs/3fm-result.md:103` | `code` | `"## 2026-10-16 — Clear History pacing, 307/308 write-redirect refusal, and author-write verification (3fn part 2, 42155cc1)"` (`docs/android-port/DECISIONS.md:2179`, commit `42155cc1`) | `CLOSED` |
| 107 | `"The existing paragraph skip controls have no precise Readium speech locator; verify their system time display, pause/resume, rate changes and lock-screen controls on a device."` | `docs/android-port/briefs/3fn-result.md:34` | `device` | — | `OPEN` |
| 108 | `"a dedicated Clear History session-change-during-GET/pacing test and F1 redirect test remain valuable coverage gaps"` (Android `AO3WriteRepositoryTest.kt:1`, iOS `KudosTests/AO3WriteDispatchFenceTests.swift:291`) | `docs/android-port/briefs/3fn-result.md:223` | `code` | — | `OPEN` |
| 109 | `"visually inspect skeleton bounds and Dark surfaces"` | `docs/android-port/briefs/3fn-result.md:236` | `verify` | — | `OPEN` |
| 110 | `"F1 — ICU regex illegal repetition in AO3SignUpForm.kt:121 and AO3WorkForm.kt:553"` | `docs/android-port/audits/A60-result.md:11` | `code` | `"## 2026-10-16 — ICU regex literal braces and Readium EpubNavigatorFactory asset release (A60, 172ef1cf)"` (`docs/android-port/DECISIONS.md:2208`, commit `172ef1cf`) | `CLOSED` |
| 111 | `"F2 — Unclosed Readium Asset in ReadiumNavigatorController.kt:94–129"` | `docs/android-port/audits/A60-result.md:54` | `code` | `"## 2026-10-16 — ICU regex literal braces and Readium EpubNavigatorFactory asset release (A60, 172ef1cf)"` (`docs/android-port/DECISIONS.md:2208`, commit `172ef1cf`) | `CLOSED` |
| 112 | `"Consider follow-up cleanup to explicitly pass the app cache directory (or delete on exit)"` (Android `works/EpubImportMetadata.kt:208`, iOS `Services/EPUBMetadataExtractor.swift:32`) | `docs/android-port/audits/A60-result.md:87` | `code` | — | `OPEN` |
| 113 | `"Consider broadening RegexPortabilityTest.kt:13–20 from network/ao3 to the full main/java source tree"` (Android `RegexPortabilityTest.kt:13`, iOS `?`) | `docs/android-port/audits/A60-result.md:96` | `code` | — | `OPEN` |
| 114 | `"OCR remains missing: adding an Android OCR engine and its lifecycle/dependency/device validation is beyond this focused fix"` + `"Native library rebuild/device PDF import remains mandatory"` (Android `works/converters/PDFWorkConverter.kt:68`, iOS `Services/PDFWorkConverter.swift:291`) | `docs/android-port/briefs/3fo-result.md:24` | `code` | — | `OPEN` |
| 115 | `"9: confirmed/deferred: installed Readium 3.3.0 EpubNavigatorFragment API ... has no public visible-spread range"` (Android `reader/readium/ReadiumNavigatorHost.kt:119`, iOS `Features/ReaderReadium/ReadiumReaderCompletion.swift:20`) | `docs/android-port/briefs/3fo-result.md:28` | `code` | — | `OPEN` |
| 116 | `"21: confirmed/deferred: ReaderSpeechController and its mini-player currently operate on a string paragraph queue, with no chapter-position seek callback or hold gesture."` (Android `reader/speech/ReaderSpeechController.kt:162`, iOS `Features/ReaderReadium/ReaderSpeechSkip.swift:10`) | `docs/android-port/briefs/3fo-result.md:40` | `code` | — | `OPEN` |
| 117 | `"22. Validate the backup central directory/ZIP64 chain if matching iOS’s malformed-archive rejection is required"` (excluded from `3fo`, Android `backup/BackupImporter.kt:34`, iOS `Reading/MiniZip.swift:10`) | `docs/android-port/audits/A61-result.md:24` | `code` | — | `OPEN` |
| 118 | `"11. Reconcile reader typography mapping with the iOS contract ... 12. Add the tested whole-line page-box inset rule"` (excluded from `3fo` for device measurement) | `docs/android-port/audits/A61-result.md:13` | `device` | — | `OPEN` |
| 119 | `"25. Offer From your other works from works already loaded ... 26. Translate timeout ... 28. Give Unknown its own question-mark status symbol"` (`A61` #25–#31) | `docs/android-port/audits/A61-result.md:27` | `code` | `"## 2026-10-16 — A61 resolved (3fo, 860c39f7 and 82f536b9)"` (`docs/android-port/DECISIONS.md:2234`, commits `860c39f7`, `82f536b9`) | `CLOSED` |
| 120 | `"F21 — Missing: reader theme customization lacks Customize on/off, line spacing, margins, justification, Reset Theme and preview; reader font list lacks custom fonts/Add/Delete."` | `docs/android-port/audits/A62-result.md:29` | `owner` (§11 Q12) | — | `OPEN` |
| 121 | `"F22 — Different: Read Aloud Previous/Next moves paragraphs rather than chapters; hiding chrome also hides the only mini-player."` | `docs/android-port/audits/A62-result.md:31` | `owner` (§11 Q12) | — | `OPEN` |
| 122 | `"F08 limit: Android's existing chapter-aware Comments lifecycle first starts an All comments load, then resolves the requested chapter"` (Android `comments/CommentsScreen.kt:153`, iOS `Features/Comments/CommentsView.swift:92`) | `docs/android-port/briefs/3fp-result.md:37` | `code` | — | `OPEN` |
| 123 | `"Manual/emulator boundaries: ... bulk Download partial failure/cancellation ... TalkBack alphabet adjustment"` | `docs/android-port/briefs/3fq-result.md:145` | `verify` | — | `OPEN` |
| 124 | `"iOS labels the custom-date switch 'Custom publication date' (AddChapterView.swift:265), while Android uses a plain Switch next to the visible 'Publication date' row text"` (Android `writing/WritingChapterFormScreen.kt:138`, iOS `Features/Writing/AddChapterView.swift:265`) | `docs/android-port/audits/A64-result.md:9` | `code` | — | `OPEN` |
| 125 | `"A full action audit of Writing and Challenges waits for Codex (back 2026-10-22) or Gemini"` | `docs/android-port/audits/A64-result.md:16` | `verify` | — | `OPEN` |
