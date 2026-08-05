# Android full-parity sweep — independent cold review

**Date:** 2026-08-04
**Branch reviewed:** `kudos-ao3-reader-android` @ `dfbaab4d` (local == origin, 0/0)
**iOS reference:** `.claude/worktrees/hig-review-reference/kudos-ao3-reader/` (branch `hig-review`)
**Reviewer:** Claude Opus 5, cold session
**Review branch:** `claude/opus-sanity-check-parity-25a7c4`

Every claim was verified against the repo or a running emulator in this session.
Nothing is restated from a prior report.

---

## Verdict

| Question | Answer |
|---|---|
| Does the branch build? | **Yes** — `assembleDebug` succeeds, 33 MB APK |
| Did the gate pass? | **No, it was red** — one stale test. Fixed here (`45125954`); now ALL GREEN |
| Are the write-path bugs fixed? | **Yes**, all three |
| Is `auth/` secure? | **Yes** — one dead invariant check to fix |
| Was anything reverted by the merges? | **No** |
| Dead / unwired code? | **Yes** — 3 instances, one user-facing |

**All 121 appendix line-items covered** (116 unique; 5 are cross-references).

| Verdict | At review | Now |
|---|---|---|
| PASS | 71 | **98** |
| PASS WITH NOTES | 21 | 20 |
| FAIL | 11 | **0** |
| NOT_STARTED | 18 | **2** |
| NOT-APPLICABLE | 0 | 1 |

**119 of 121 resolved.** Every FAIL is closed.

**Remaining NOT_STARTED (2):** P4-4 AO3 series preservation on queue-add ·
P4-6 Queue Storage screen. Both were attempted and pushed back as too large for
one pass; each now has its own prompt.

**NOT-APPLICABLE (1):** P11-8 reader edge-swipe-back. This was always a
verify-first item, and the verification says don't build it: Android's system
predictive-back wins at the window edge. Tested in the reader with a book open
on emulator-5554 — an edge swipe navigated back rather than being eaten by the
Readium WebView as a page turn, which is the failure iOS's `EdgeSwipeBack`
exists to work around. **Closed as not-applicable, not skipped.**

**Two items landed as PASS WITH NOTES rather than PASS:**
- P11-1 shared-element zoom — the destination modifier is applied in
  `WorkDetailScreen` only, so card → detail animates but card → reader does not.
- P8-7 conflict handling — the merge itself is right (every conflicting manifest
  is folded in, not just a winner), but iOS's `foldedConflicts` count is
  discarded, so colliding devices give the user no signal.

**Also outstanding:** F3 reader landscape, the PASS-WITH-NOTES polish, the
`contracts/fixtures/` layer, and MuPDF.

**Fixes applied in this branch:** F0, F1, F2, F4, F5, F6, F7, F8, plus checklist
items P7-2, P7-3, P7-8, P9-2, P9-4, P9-5, P9-7, P9-8, P9-9, P9-10, P9-11, P10-1,
P10-4, P11-3, P11-5 — and, unblocked by P9-10, P4-11 and P10-3. Phase 9 is now
complete apart from the PDF engine itself (MuPDF).

Bugs found in **iOS** while porting are logged separately in
[iOS_Issues_Found_While_Porting.md](iOS_Issues_Found_While_Porting.md) rather
than silently propagated to Android.

Phases 0, 1, 3 are **fully clean**. Phase 6 is near-clean (13/14). The debt is
concentrated in **Phase 9** (8 of 11 failed or absent) and **Phase 11** (6 of 8).

---

## Headline findings

### F0 — `verify.sh` was red through two releases  ✅ FIXED (`45125954`)

`483d874a` widened `isSupportedFileName` to `epub/pdf/html/htm/txt`
(`WorkImporter.kt:251`) but left `importLocalEpubRejectsNonEpubExtension`
asserting `"notes.txt"` is rejected.

```
WorkImporterLifecycleTest > importLocalEpubRejectsNonEpubExtension FAILED
    java.lang.ClassCastException: WorkImportResult$Success cannot be cast to WorkImportResult$Failure
574 tests completed, 1 failed
```

`verify.sh` aborts at step 2/5, so **steps 3/5, 4/5 and 5/5 had never run on this
branch** — and the red gate spanned both the 0.1.8 and 0.1.9 release bumps. After
the fix: `android verify: ALL GREEN`. **Cherry-pick `45125954`.**

### F1 — Phase 9 item 1: the intent-filter is dead (High)  ✅ FIXED (`d1b0c514`)

`AndroidManifest.xml:28-34` registers `ACTION_VIEW` + `ACTION_SEND` for
epub/pdf. `MainActivity.kt` never reads the Intent — no `onNewIntent`, no
`intent.data`, no `EXTRA_STREAM`. Every `ACTION_VIEW`/`ACTION_SEND` in the
codebase is outbound. "Open with Kudos" and Share → Kudos open the app to Home
and **silently discard the file**.

### F2 — Phase 9 item 3: `PDFWorkConverter` emits binary noise (High)  ✅ FIXED (`d1b0c514`)

`PDFWorkConverter.kt:7` regexes `\((.*?)\)` over ISO-8859-1-decoded raw bytes.
Measured against a real PDF:

```
non-blank matches (become <p> paragraphs): 18
 8/18 plain ASCII  —  10/18 raw binary noise
  "D:20181013142839-08'00'"                      <- PDF metadata timestamp
  '\x0bÚ\x9aZj\x12\x1aC\x14\x9arpèßhqO]\x85 hn-Z…'
```

Zero document text recovered, and the honest fallback (`"No easily extractable
text found"`) **never fires** because the regex "succeeded" on garbage. Users get
corrupt library entries instead of a clear failure. No OCR, no outline-based
chapter split, no header/footer strip, no encrypted-PDF detection.

### F3 — Reader is broken in landscape (Medium; **not** caused by the crash fix)

The `configChanges` fix works — 7 rotations with a book open, no crash, no
Activity recreation. But the reader's landscape layout is wrong: content pane
letterboxed, chapter heading behind the toolbar, dead space below.

Two controls disprove the obvious hypothesis:
- A **fresh launch directly into landscape** produces the identical layout.
- In the same orientation the **Library screen adapts correctly** — nav rail,
  full width, `areBoundsLetterboxed=false`, `resizeMode=RESIZE_MODE_RESIZEABLE`.

The reader has never laid out correctly in landscape. **Do not revert
`configChanges`** — that restores the crash and fixes nothing.
`ReaderScreen.kt:285` passes `Modifier.fillMaxSize()`; the constraint is inside
`ReadiumNavigatorHost`'s `FragmentContainerView` / the Readium WebView.

### F4 — Debug `println`s ship in release (Medium)  ✅ FIXED (`b07be588`)

8 calls: `CommentsViewModel.kt` 80, 85, 88, 97; `AO3CommentRepository.kt` 47, 50,
56, 63. Two dump whole objects (`"Repository returned: $result"`,
`"Parse thread result: $thread"`). `minifyEnabled` is set nowhere and
`proguard-rules.pro` is empty, so release keeps them — **user comment content to
logcat**. Delete all 8.

### F5 — Room `exportSchema = true` but no schemas committed (Medium)  ✅ FIXED (`882b68c4`)

`KudosDatabase.kt:45` + `build.gradle.kts:121` set schema export, but
`android/app/schemas/` doesn't exist and isn't gitignored. Migrations themselves
are fine (1→7 defined, all registered `KudosAppContainer.kt:64-69`, DB v7).
Nothing is broken today, but no `MigrationTestHelper` coverage is possible.

### F6 — A security invariant that can never fail (Low)  ✅ FIXED (`b07be588`)

`android/Scripts/check-invariants.sh` check #2 ("No password storage APIs") is
`if grep …; then : fi` — no-op `then`, no `else`. It passes unconditionally.
Checks #1, #3, #4, #5 are real. Implement it or delete it.

### F8 — The Account crash fix was treating a symptom  ✅ FIXED (`73c3ae71`)

Not in the original review — surfaced while writing a regression test for the
shipped guard. The test reproduced the failure **deterministically on the first
run**: `hubEntries[1]` is null and reading its `listKey` throws NPE.

It was never a race. `hubEntries` was an eager `val` built during
`AccountListType.<clinit>`; any code touching a subclass first
(`HomeViewModel.kt:138` reads `AccountListType.Subscriptions`) starts that
subclass's initializer, which triggers the superclass initializer, which reads
the subclass `INSTANCE` fields back while still null.

So the shipped `if (entry == null) continue` stopped the crash but left the
Account hub **silently missing counts** for whichever rows lost the ordering.
Fixed by making `hubEntries` `by lazy`.

### F7 — Dead code and stray files (Low)  ◐ PARTLY FIXED (`882b68c4`)

- ✅ `works/WorkMetadataRefresh.kt` — **wired**, not deleted: it is not redundant
  with `WorkRepository.refreshMetadata` (which only re-pulls tag groups), so it
  now backs a "Refresh Metadata" action in the Work Detail overflow menu.
- ⚠️ `scratch.kt` at repo root — **left in place, owner's call.** It is untracked
  in the main working directory, so deleting it is unrecoverable and it is not
  mine to remove.
- ✅ The Account crash now has a committed regression test — but not the one that
  was sitting uncommitted. `AccountScreenCrashTest.kt` needed Compose-on-Robolectric
  dependencies the project does not have (`compose.ui.test.junit4` is
  `androidTestImplementation` only), which is why it never landed. Replaced with a
  dependency-free JVM test that pins the actual invariant — and which promptly
  found F8.

---

## Full 121-item checklist

Legend: **P** = PASS · **PN** = PASS WITH NOTES · **F** = FAIL · **NS** = NOT_STARTED

### Phase 0 — write-path correctness bugs · 6/6 PASS

| # | Item | | Evidence |
|---|---|---|---|
| 1 | `markForLater` `_method=patch` | **P** | `AO3WriteRepository.kt:115` `"_method" to "patch"` |
| 2 | Bookmark `collection_names` carry-through | **P** | `AO3WriteRepository.kt:160-162` re-scrapes at submit, comment: "Never trust the caller's composer" |
| 3 | Reply CSRF URL | **P** | `AO3CommentRepository.kt:88-93` uses `commentThreadUrl(id, isReply = true)`, matching `Referer` :138 |
| 4 | Tag union + case-insensitive dedupe | **P** | `WorkTags.kt:40` `seenKeys.add(trimmed.lowercase())`; `WorkMetadataMerger.kt:99` `flatten().dedupeFirstSeen()` |
| 5 | Biometric reveal gate | **P** | `PrivacyGate.kt:3-4` BiometricPrompt, `:43` `requireBiometricToReveal`, gated in `reveal()` :48 / `toggleRevealAll()` :58 |
| 6 | Home pull-to-refresh | **P** | `HomeScreen.kt:91` `PullToRefreshBox` → `HomeViewModel.refresh()` :102 |

### Phase 1 — foundational infrastructure · 3/3 PASS

| # | Item | | Evidence |
|---|---|---|---|
| 1 | Search index | **P** | `WorkSearchIndex.kt:53-89` v2 w/ series + userTags + rating + language; rebuild sweep `KudosApplication.kt:42` |
| 2 | Canonical work merge | **P** | `CanonicalWorkMerge.kt:21` `remoteLed`; called `AccountViewModel.kt:121` |
| 3 | Comment tree model | **P** | `AO3CommentModels.kt:220-226` `threadPath`/`parentThreadPath`/`parentCommentId`/`isThreadCutoff`/`cutoffCount`/`replies` |

### Phase 2 — Reader · 5 P · 8 PN

| # | Item | | Evidence / note |
|---|---|---|---|
| 1 | TTS + MediaSession | **PN** | `ReaderSpeechController.kt:52` MediaSession, `:44` voices, `:108` rate. No `Notification`/`startForeground` → no true lock-screen notification |
| 2 | Highlighting & notes | **PN** | `AnnotationRepository.kt:81` `addOrRecolorHighlight`; `ReadiumNavigatorController.kt:53` decorations. No text-selection ActionMode — overflow-only entry (prior note still open) |
| 3 | Bookmarking | **P** | `ReaderScreen.kt:367-370` `toggleBookmarkAtProgress` |
| 4 | Contents sheet | **PN** | `ReaderScreen.kt:922` tabs Contents/Bookmarks/Highlights. No per-chapter start-percent, no swipe actions |
| 5 | Find in Work | **P** | `ReaderSearch.kt:18,25` Readium `SearchService`; 9 refs in `ReaderScreen.kt` |
| 6 | Fan/overflow menu | **PN** | `ReaderScreen.kt:790` DropdownMenu; kudos `:366`, rotation lock `:867`. "Rebuild from Original" absent — blocked on P9-10 |
| 7 | Orientation lock | **PN** | `ReaderScreen.kt:867-870` forces `SCREEN_ORIENTATION_PORTRAIT`, not the *current* orientation (prior note still open) |
| 8 | Drag-to-dismiss | **P** | `ReaderScreen.kt:325-330` `detectVerticalDragGestures`, 180f threshold |
| 9 | Position/progress chrome | **PN** | `ReaderProgressDisplay.kt:43` minutesRemaining; Slider `:898`; haptics `:369,:437`. No page-of-page count |
| 10 | End-of-work auto-finish | **PN** | **Repair fix confirmed intact**: `EndOfWorkActions.kt:26` `work.isComplete && !work.isFinished`; wired `ReaderViewModel.kt:109`. `nextInSeriesAvailable` still hardcoded false `:33` |
| 11 | Display sheet | **PN** | scroll/paged `:1097-1103`, spread `:1107`, TTS `:665-666`. **No font-family picker in the reader sheet** |
| 12 | Bold + letter/word spacing | **P** | `ReadiumSettingsAdapter.kt:40-42` all three mapped |
| 13 | Title → Work Details | **P** | `ReaderScreen.kt:756` `.clickable { onOpenWorkDetail(localWorkId) }` |

### Phase 3 — Account / Auth / Author · 10/10 PASS

| # | Item | | Evidence |
|---|---|---|---|
| 1 | Author dashboard + parser | **P** | `AO3AuthorParser.kt:20` `parseDashboard`; screen `AuthorProfileScreen.kt:69`; subscribe `:230`, block/mute `:233`. **Navigation real**: `AppNavHost.kt:323,469` → `:599` |
| 2 | Series + Bookmarks tabs | **P** | `AuthorProfileScreen.kt:62-65`; parsers `:102`, `:117` |
| 3 | About tab | **P** | `parseAbout` `AO3AuthorParser.kt:75`; userId `AuthorProfileScreen.kt:190` |
| 4 | Pseud scope switching | **P** | `AuthorProfileScreen.kt:201-202` shown only when `pseuds.size > 1` |
| 5 | Posting-pseud selection | **P** | `AO3PostingPseudStore.kt:30-34`; resolved against live form `AO3CommentRepository.kt:119-123`; `AO3WriteRepository.kt:133` |
| 6 | Session encryption | **P** | `AO3SessionStore.kt:81-85` `EncryptedFile` AES256_GCM_HKDF_4KB + MasterKey AES256_GCM |
| 7 | Native login form | **P** | `AO3NativeLoginScreen.kt`; host-guarded JS `:183-193`; password cleared on every path; `jsonEscape` `:259-265` |
| 8 | AO3 Preferences native | **P** | `AO3PreferencesParser/Repository/Screen`; reachable `AppNavHost.kt:318` → `:612` |
| 9 | Account-list counts cache | **P** | `AO3AccountListCountsCache.kt:9` 30-min TTL, matching iOS |
| 10 | Real avatar | **P** | `AuthorProfileScreen.kt:169-174`, `AccountScreen.kt:198` AsyncImage on `avatarUrl` |

### Phase 4 — Library / Queues / Collections · 6 P · 2 PN · 1 F · 3 NS

| # | Item | | Evidence / note |
|---|---|---|---|
| 1 | Drag-to-reorder in queue | **P** | `QueueDetailScreen.kt:81,116,263-267`, forces `LibrarySort.Manual` |
| 2 | Rename / soft-delete queue | **P** | `ReadingQueueRepository.kt:215,228`; system queues guarded `:219` |
| 3 | Filters / display / Expand All | **P** | `QueueDetailScreen.kt:271` Expand All, `:360` `LibraryFilterPanel` |
| 4 | AO3 series preservation on queue-add | **NS** | `AO3SeriesRepository` used only by `DownloadQueue.kt:27` (bulk download) + WorkDetail. `ReadingQueueRepository` has **zero** series references |
| 5 | Inline queue create + checkmarks | **P** | `LibraryScreen.kt:137,242`; `Checkbox` `:52` |
| 6 | Queue Storage screen | **NS** | No match repo-wide |
| 7 | Queue Recently-Deleted sweep | **P** | `ReadingQueueRepository.kt:293`, called `KudosApplication.kt:40` |
| 8 | Add Works to Collection | **P** | `CollectionDetailScreen.kt:352,365` `AddWorksToCollectionDialog` |
| 9 | Bulk action bar | **PN** | `LibraryViewModel.kt:191,214,227` softDelete/addToQueue/addToCollection. **No bulk Save toggle, no bulk Save-for-Later** |
| 10 | Remote-list multi-select (shared) | **F** | Only `SearchViewModel.kt:43-44`. Browse/FandomWorks and Author have none, and it is **not** a shared component |
| 11 | Rebuild from Original | **NS** | Correctly blocked on P9-10 |
| 12 | AO3 list screens: refine/display/expand + merge | **PN** | Merge present (`AccountScreen.kt:1246,1597` `canonicalWorks`). **No refine filter, no display-mode toggle, no expand-all** |

### Phase 5 — Comments · 16 P · 4 PN · 1 F

| # | Item | | Evidence / note |
|---|---|---|---|
| 1 | Nested reply tree | **P** | `CommentsScreen.kt:457-458` recursive `comment.replies.forEach` |
| 2 | Collapse/expand + chunked "show N more" | **PN** | Collapse real: `:431` auto-collapse `depth > 2`, toggle `:435`. **No chunking** — no 8-reply auto-fold threshold, no 20-reply chunks |
| 3 | AO3 thread-cutoff node | **P** | Parser `AO3CommentParser.kt:221-223`; rendered `CommentsScreen.kt:440-441` `CommentCutoffRow` |
| 4 | Deleted-comment tombstone | **P** | **Prior FAIL now fixed** — `CommentsScreen.kt:571-585` dedicated Surface, italic, `onSurfaceVariant` |
| 5 | Edit comment | **P** | `AO3CommentRepository.kt:174` `editComment`, `_method=put` `:186` |
| 6 | Delete comment + confirm | **P** | `:203` `deleteComment`, `_method=delete` `:211`; confirm `CommentsScreen.kt:131` |
| 7 | (= P0-3 reply CSRF) | **P** | see Phase 0 |
| 8 | Duplicate-post guard | **P** | `CommentsViewModel.kt:69` content-hash tracking, `:231` ambiguous-failure block |
| 9 | Draft persistence | **P** | **Regression fix confirmed**: `load()` uses `parentId = null` `:97-104`; `startReply()` looks up reply draft `:142-151` behind a target-unchanged guard |
| 10 | "By Chapter" scope | **P** | **Prior FAIL now fixed** — `ChapterScopePicker` `:739`, `onSelectTarget` genuinely wired `:227` and `:757` |
| 11 | Ordering toggle | **P** | `CommentsScreen.kt:231-241` Newest/Oldest First |
| 12 | Reader Comments chapter-awareness | **F** | `ReaderScreen.kt:124` `onOpenComments: (Long) -> Unit` — carries a workId only, no chapter target |
| 13 | Inbox focused-thread routing | **P** | `CommentsViewModel.kt:60-61,78-87` `focusedId` → `repository.loadThread(target, page, focusedId)` |
| 14 | Work Detail row differentiation | **PN** | `WorkDetailScreen.kt:1688` DiscussionTab, `:1707` distinct "Chapter Comments" row. Single-chapter hide **not confirmed** |
| 15 | Thread/parent jump + Copy Link | **PN** | `onViewThread` `:309,:425`. **No Copy Link action** |
| 16 | Continue-thread drill-down | **P** | Folded into 1/3 — `CommentCutoffRow` + `onViewThread` |
| 17 | Read-more clamp | **P** | `CommentsScreen.kt:590` `maxLines = 5`, `:602` "Read more" |
| 18 | Chapter badge | **P** | `:546-552` `comment.chapterLabel` |
| 19 | Comment page cache | **PN** | `CommentCache.kt:11` stale-while-revalidate disk cache. **No explicit 300s TTL constant found** |
| 20 | (= P0-1 markForLater) | **P** | see Phase 0 |
| 21 | (= P0-2 bookmark collections) | **P** | see Phase 0 |

### Phase 6 — Browse / Search · 13 P · 1 F

| # | Item | | Evidence / note |
|---|---|---|---|
| 1 | Local-first Global Search | **P** | `SearchViewModel.kt:52-61` `localMatches` via `WorkSearchIndex`; `SearchScreen.kt:203,227` + "Search AO3 works" action |
| 2 | (= P1 search index) | **P** | see Phase 1 |
| 3 | Canonical merge on remote lists | **P** | `AccountViewModel.kt:121` |
| 4 | Tappable tag/fandom chips | **P** | `AO3WorkCard.kt:57` `onTagClick` → `:141,159` `onLabelClick` |
| 5 | Refine filter on tag page | **P** | `TagWorksScreen.kt:63` `refine`, `:78` `activeFilterChips` |
| 6 | Fandom-works filter panel | **P** | `FandomWorksScreen.kt:180` `SearchFilterSheet` |
| 7 | Bulk multi-select over results | **F** | Same defect as P4-10 |
| 8 | Browse expand/collapse-all | **P** | `FandomWorksScreen.kt:65,126-129` |
| 9 | Pagination page bar | **P** | `KudosPaginationBar` used at `SearchScreen.kt:626` and `FandomWorksScreen.kt:167` |
| 10 | (= P0-4 tag union) | **P** | see Phase 0 |
| 11 | Background self-healing tag refresh | **P** | `WorkTagsRefreshWorker.kt:17-25` `needsAO3Refresh` + `lastTagRefreshAttemptAt`; scheduled `KudosApplication.kt:67-79` |
| 12 | Fandom catalog disk cache | **P** | **Genuinely wired**, not just present: `AO3BrowseRepository.kt:30,46,59` |
| 13 | AO3 tag autocomplete | **P** | `AO3TagAutocompleteRepository`; `TagSuggestField.kt:42,57-60` |
| 14 | Long-press quick actions | **P** | `AO3WorkCard.kt:84-86` `combinedClickable` + `onLongClick` |

### Phase 7 — Home / Onboarding / Privacy / Support · 3 P · 2 PN · 1 F · 3 NS

| # | Item | | Evidence / note |
|---|---|---|---|
| 1 | Reveal-all on Home | **P** | `HomeScreen.kt:104-105,256` `privacyGate.toggleRevealAll(activity)` |
| 2 | "See all" past the 12-item cap | **PN** | `HomeScreen.kt:351-352` exists but **only Subscriptions passes `onSeeAll`** (`:181`); other sections still capped with no escape |
| 3 | Collapsible sections, persisted | **F** | `HomeScreen.kt:88` `remember { mutableStateMapOf }` — session-only, resets on navigation. iOS uses `@AppStorage` |
| 4 | Home multi-select / bulk | **NS** | No `selectionMode` in `home/` |
| 5 | Home pull-to-refresh | **P** | = P0-6, `HomeScreen.kt:91` |
| 6 | Sync-folder onboarding step | **NS** | No onboarding sync step, though Phase 8's UI now exists so it's unblocked |
| 7 | Bug report rebuild | **PN** | `BugReportScreen.kt:93` prefilled GitHub issue with body. **No screenshot capture** — no `PixelCopy`/`drawToBitmap` anywhere |
| 8 | Shake haptic | **NS** | No `Vibrator`/`vibrate` in `ShakeDetector.kt` |
| 9 | Offline license/notices | **P** | `AboutScreen.kt:32` version, `:61-65` GPL-3.0, `:74-82` Jsoup MIT + Readium BSD-3-Clause credits |

### Phase 8 — Sync & Backup · 4 P · 1 PN · 3 NS

| # | Item | | Evidence / note |
|---|---|---|---|
| 1 | Persisted SAF tree access | **P** | `SyncRepository.kt:43-44` `takePersistableUriPermission` |
| 2 | Folder sync service | **PN** | `:34,38,43,54,89` `isSyncEnabled`/`getSyncFolderUri`/`connect`/`disconnect`/`runSync`. **One-way only** — no `syncDown`/`syncUp` split. **UI now exists** (Settings "Enable folder sync" / "Select sync folder", seen running) — the brief's "no UI entry point" gap is **stale** |
| 3 | WorkManager scheduling | **P** | `:68-78` `PeriodicWorkRequestBuilder<FolderSyncWorker>`, `enqueueUniquePeriodicWork` |
| 4 | Dirty-flag / pending-change tracking | **NS** | No dirty/pending state anywhere in `SyncRepository` |
| 5 | Auto-sync preference + status | **P** | `:34` `isSyncEnabled`, `:140` `updateSyncLastSyncAt` |
| 6 | Incremental/delta export + orphan prune | **NS** | No skip-if-unchanged, no orphan pruning — full export every run |
| 7 | Concurrent-writer conflict handling | **NS** | No conflict detection |
| 8 | App-wide persistence gate | **P** | `PersistenceGate.kt`; `BackupRepository.kt:44,76` `persistenceGate.withLock` |

### Phase 9 — Non-EPUB import · 1 P · 2 PN · 3 F · 5 NS  ← weakest phase

| # | Item | | Evidence / note |
|---|---|---|---|
| 1 | "Open with Kudos" intent-filters | **F** | Registered `AndroidManifest.xml:28-34`, **never handled** — see F1 |
| 2 | Content-based format sniffing | **NS** | No `ImportedFileFormat.kt`. Dispatch is extension-only (`WorkImporter.kt:246-252`). A working port exists unmerged in the Phase9 worktree |
| 3 | PDF → EPUB w/ OCR | **F** | See F2 — regex over raw bytes, no OCR/outline/header-strip/encryption detect |
| 4 | Text → EPUB | **PN** | `PlainTextWorkConverter.kt` produces a valid EPUB but has **no chapter-heading detection and no paragraph reflow** |
| 5 | HTML → EPUB | **PN** | `HTMLWorkConverter.kt` works but has **no format-specific chapter extraction** (AO3/ffn/heading-split) and **no metadata scraping** |
| 6 | HTML sanitization | **P** | `HTMLWorkConverter.kt` `Jsoup.clean(…, Safelist.relaxed())` — a real allowlist, not a pass-through |
| 7 | Non-EPUB zip handling | **NS** | — |
| 8 | Multi-encoding decode chain | **NS** | Only `Charsets.UTF_8` / hardcoded `ISO_8859_1` in the PDF path |
| 9 | Calibre/FanFicFare metadata | **NS** | — |
| 10 | Original archival + provenance | **NS** | Blocks P4-11 and P10-3 |
| 11 | Format-aware messaging | **F** | `WorkImporter.kt:135` still one generic string |

### Phase 10 — Availability / update-checking · 3 P · 1 PN · 1 F · 1 NS

| # | Item | | Evidence / note |
|---|---|---|---|
| 1 | `WorkAvailability` fields + migration | **PN** | `MIGRATION_5_6` adds `ao3Unavailable`/`lastAvailabilityCheck`; DB v7; registered `KudosAppContainer.kt:64-69`. **Schema JSONs not committed** — see F5 |
| 2 | `WorkAvailabilitySweep` + entry point | **P** | `WorkAvailabilitySweep.kt`; reachable `SettingsScreen.kt:133` ← `AppNavHost.kt:581`; worker `KudosApplication.kt:63-75` |
| 3 | `WorkReconversion` | **NS** | Correctly blocked on P9-10 — nobody built it on top of stubs |
| 4 | `WorkMetadataRefresh` | **F** | File exists, **zero callers** — classic built-but-unreachable. See F7 |
| 5 | Tag-refresh cooldown | **P** | `WorkTagsRefreshWorker.kt:17,25` `needsAO3Refresh` + `lastTagRefreshAttemptAt` |
| 6 | queued-then-favorited bug | **P** | `WorkRepository.kt:44,57` `filter { it.isProtected && !it.isQueueOnlyWork }`; regression test `WorkUpdateCheckerTest.kt:197` |

### Phase 11 — Shared UI/UX · 1 P · 1 PN · 3 F · 3 NS

| # | Item | | Evidence / note |
|---|---|---|---|
| 1 | Shared-element zoom transition | **NS** | No `SharedTransitionLayout` anywhere |
| 2 | Skeleton loading outside reader | **PN** | Only `HomeScreen.kt`. `ReaderPageSkeleton.kt` still pulses with **no "remove animations" check** — the exact sub-item the brief called out |
| 3 | ONE shared pull-to-refresh | **F** | `PullToRefreshBox` only in `HomeScreen.kt`. Library, Collections, Queues, Search, Browse have none. Not built as the shared pattern the brief required |
| 4 | Shared `DestructiveConfirmation` | **P** | `DeleteConfirmation.kt`; **15 call sites across 10 files**; `confirmBeforeDelete` now consistent — `LibraryScreen.kt:219,232` honors it, matching `CollectionDetailScreen.kt:228,238`. Both named pre-fix inconsistencies resolved. Remaining inline `AlertDialog`s are non-destructive (create queue, add to collection) |
| 5 | Remote multi-select (shared) | **F** | = P4-10 / P6-7 |
| 6 | Carousel collapse persisted | **F** | `LibraryScreen.kt:538` and `HomeScreen.kt:88` both `remember`-only |
| 7 | Shared search-field / Browse URL entry | **NS** | No `GlassFieldBar` equivalent |
| 8 | Reader edge-swipe-back | **N/A** | Verified in the reader with a book open (emulator-5554): an edge swipe navigated back, so Android's predictive-back already wins over the Readium WebView. The problem iOS works around does not exist here — closed as not-applicable |

---

## Cross-cutting checks

- **iCloud `" 2"` conflict files** — none. `find android/app/src \( -iname "* 2.kt" -o -iname "* 2.java" \)` empty; `git status --short | grep ' 2\.'` empty.
- **`android/keystore.properties`** — not committed, gitignored. ✓
- **Commit granularity** — `483d874a` bundles six unrelated concerns ("comments scope, tombstone, series persistence, sweep UI, converters, shared components") across three phases. Flagging, not blocking: it's also the commit that broke the gate unnoticed.
- **Built-but-unreachable audit** — the project's signature failure mode. Found **1 remaining instance** (`WorkMetadataRefresh`, P10-4) plus **1 inverted instance** (P9-1, entry point with no handler). Phase 3's author profile and preferences, Phase 4's reorder, and Phase 5's by-chapter scope are all now genuinely wired — verified by grepping for real navigation call sites, not file existence.

---

## Branch topology — resolved

`kudos-ao3-reader-android` is canonical; local == origin.
`android/full-parity-sweep` is gone.

**The six phase worktrees are dead leftovers.** `phase6..phase11-android-port`
exist as git worktrees (not standalone clones) at
`/Users/cidy02/Documents/AO3_App_OpenSource_Phase6…11`, all dirty, each ~5,000
lines *behind* the branch. I diffed every working tree against the branch and
traced each worktree-only file:

| Worktree-only file | Status |
|---|---|
| `AO3AutocompleteRepository.kt` | superseded by `network/ao3/search/AO3TagAutocompleteRepository.kt` |
| `SearchPaginationBar.kt` | superseded by `ui/components/KudosPaginationBar.kt` |
| `WorkTagRefresh.kt` | superseded by `WorkTags.kt` + `WorkTagsRefreshWorker.kt` |
| `RemoteWorkSelection.kt` | superseded — `SearchViewModel` has the state (but see P4-10) |
| `PersistenceSync.kt` (bare `Mutex`) | superseded by the richer `PersistenceGate.withLock` |
| `MultiSelectDelegate.kt` | superseded by `library/LibrarySelection` (deliberate simpler design) |
| `FolderSyncService/Repository.kt` | deliberately excluded; `SyncRepository` replaces them |
| `ImportedFileFormat.kt` | **genuinely missing → P9-2** |
| `schemas/6.json`, `7.json` | **genuinely missing → F5 / P10-1** |

`4b7ccd7b` ("Phase 9 intent filters"), the one commit unique to
`phase9-android-port`, is superseded not lost: the branch has the same filter
minus `text/html`/`text/plain`, which `788e629b` removed deliberately for Play
Protect.

**Once `ImportedFileFormat.kt` and the schema JSONs are merged, all six
worktrees and their branches can be deleted.**

---

## Emulator verification (fresh API 36, debug APK)

- **Account NPE guard** present in `refreshCounts`. **12 cold-launch → Account-tab
  cycles: zero NPEs**, empty crash buffer, Account renders fully (Overview/
  Reading/Writing/Activity, Shortcuts grid, Preferences row).
- **Rotation**: `configChanges` present. **7 rotations with a book open, no
  crash**, Activity never recreated. Landscape layout defective — F3.
- Live-confirmed reachable: onboarding, 4-tab nav, folder sync UI, biometric
  reveal toggle, reader chrome (search/TOC/Tt/TTS/overflow), bold + letter/word
  spacing controls, Home collapse chevrons, EPUB import end-to-end.
- A `net::ERR_FAILED` I hit initially was **my test fixture's fault**, not the
  app's — logcat: `ErrorException: No <head> opening tag found in this resource`,
  and `KudosTests/Fixtures/sample.epub` has no `<head>`. A well-formed EPUB
  renders correctly.

---

## Not verified

- **All authenticated write paths were verified by reading code only.** Kudos
  POST, comment/reply POST, bookmark update, Mark for Later, native login,
  inbox, account lists — none exercised against a live AO3 session, which needs
  real credentials. **Owner must test these.** Largest remaining risk.
- `AccountScreenCrashTest.kt` — read but not run; it is not on the branch.
- F3 root cause — proven and localised to the Readium fragment/WebView layer,
  not traced to a line.
- P5-14's single-chapter hide, and P5-19's exact cache TTL.
- Physical device (`R5CY710SE9M`) — deliberately unused; all testing on emulator.

---

## Suggested order of work

1. Cherry-pick `45125954` (F0) — restores the gate before anything else lands.
2. F4 + F7 — delete the 8 `println`s, `WorkMetadataRefresh.kt`, `scratch.kt`;
   commit `AccountScreenCrashTest.kt` + `debug/AndroidManifest.xml`.
3. F2 (P9-3) — stop PDF import emitting garbage. Ships corrupt data today.
4. F1 (P9-1) — wire incoming intents, or drop the filter.
5. P9-2 + F5 — merge `ImportedFileFormat.kt` and the schema JSONs, then delete
   all six phase worktrees and branches.
6. P11-3 and P11-5 — the two shared components other phases' gaps depend on
   (pull-to-refresh unblocks P7-5/P10-4 surfaces; multi-select unblocks
   P4-10/P6-7). Build once, as the brief specified.
7. P7-3 / P11-6 — persist collapse state (one fix, two items).
8. F3 — reader landscape layout.
9. F6 — fix or delete the no-op invariant.
10. Remaining NOT_STARTED items by phase, worst-first: Phase 9 (5), Phase 8 (3),
    Phase 7 (3), Phase 11 (3), Phase 4 (3).
11. **Owner:** live-session testing of every AO3 write path.
