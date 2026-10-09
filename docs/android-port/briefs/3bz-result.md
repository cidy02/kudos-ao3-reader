# Brief 3bz result

## iOS reference, read from code

Reference: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/Account/PrivacyDataView.swift`, `Services/LocalDataFootprint.swift`, `Services/LocalDataClearing.swift`, `Services/AO3AuthService.swift`, and `UIComponents/DeleteConfirmation.swift`.

Header: **AO3 Account › Settings** / **Privacy** / **Your reading data stays on this device**.

**Code wins over the brief:** iOS DOES have the opening card, headed “No ads or tracking, and no separate Kudos account”. Its body is “Kudos connects to AO3. After you approve a Voice Pack download, it also connects to the service providing the pack. Your library, reading positions, tags, collections, and AO3 sign-in stay on this device.” It uses the Mint subject palette, 17-point semibold title and 13-point body, 6-point gap, 18/16-point horizontal/vertical padding and 16-point radius. Android follows this actual code.

### 1. Stored on this device

In order (byte rows use `byteLabel`, which shows “—” before measurement):

| Label | Computation / wording | Visibility |
|---|---|---|
| Downloaded works | `LocalDataFootprintScanner.measure`: recursive `Storage.worksDirectory` size minus reading-copy bytes, clamped at zero | Always |
| Works you're reading | `measure`: sum logical file sizes of live `SavedWork` files where `hasEPUB && !isDownloaded` | Positive only |
| Original files kept | `measure`: recursive `Storage.originalsDirectory`, including conversion records | Positive only |
| Imported fonts | `measure`: recursive `Storage.fontsDirectory` | Positive only |
| Draft recovery | `measure`: recursive `WritingTextRecovery().directory` (chapter, summary and note recovery copies, not comment drafts) | Always |
| Caches | `measure`: recursive `Storage.metadataCacheDirectory` plus Caches/Reader scratch | Always |
| Reading positions | `LocalDataClearing.selectReadingPositions(from: works)`: live works with nonempty Readium locator, positive spine index or scroll fraction, or nonnil legacy progress; `countLabel(N, "work")` | Always |
| Local collections | live `@Query WorkCollection` records, excluding pending deletion; decimal count | Always |
| Saved searches | all `@Query SavedSearch` records; decimal count | Always |
| Search history | “Not recorded” | Always |

Directories are Application Support/Works, Originals, Fonts and WritingTextRecovery; metadata lives in Caches/Metadata and reader scratch in Caches/Reader. `directorySize` skips hidden and nonregular files, recursively sums allocated file size when available, otherwise logical size, and skips unreadable entries. `measure` runs in a detached utility task. `LocalStorageFootprint.formatted` uses `ByteCountFormatter`, `.file` (decimal units), `allowsNonnumericFormatting = false`, nonnegative bytes: numeric “0 bytes”, uppercase KB, MB, GB, etc. Counts are “1 work” / “N works”; confirmation nouns capitalize and also pluralize only when N != 1. Counts are available from queries while disk figures wait. Conditional size rows are absent until a positive measurement. Opening measures once; iOS also supports pull-to-refresh; Free up space and Clear Browse Cache trigger new scans.

Footnote, verbatim: “The sizes shown are measured on this device. Browse keeps fandom and category lists so it opens faster; it rebuilds them when needed, and your device may remove them to free space.”

### 2. Clear

Rows in order: **Free up space** · `N file(s)`; **Clear reading positions** · `N work(s)`; **Clear reading history** · `N work(s)`; **Clear browse cache** · formatted total cache bytes. The first three disable at zero. Browse changes to **Browse cache cleared**, without disclosure/destructive styling, disabled after clearing. History selects live works without an EPUB and without `isProtected`; Free up space selects live finished works with an EPUB and without `isProtected`; positions use the predicate above.

Footnote, verbatim: “Each option asks before it clears anything and tells you what will change on this device. Your AO3 reading history is separate; clear it from History or turn it off in AO3 Preferences.”

Confirmations (all have **Cancel**, destructive button listed below):

| Title | Message, verbatim | Destructive button |
|---|---|---|
| Free Up Space? | Removes the copies of works you've finished reading and didn't download, favourite or queue. Kudos gets them again from AO3 if you open them. | Free N File(s) |
| Clear Reading Positions? | Clears your place in every work. Your works and their order in Continue Reading stay the same. | Clear N Position(s) |
| Clear Reading History? | Moves works that only remain in your reading history to Recently Deleted for 90 days. Your saved and downloaded works stay where they are, and you can download these works from AO3 again. | Clear N Work(s) |
| Clear Browse Cache? | Removes saved fandom and category lists. Your reading, saved works, and downloads stay untouched; Browse rebuilds the lists next time you open it. | Clear [formatted cache bytes] |

### 3. AO3 session

Signed in: **Signed in** · username; destructive **Remove AO3 session** with no value. Every other status: **AO3 account** · **Not signed in**. Footnote, verbatim: “Your AO3 sign-in is kept only on this device and is never shared.” Append one space and `auth.noticeMessage` when present. Logout notices: “Logged out of AO3.” or “Signed out here, but this device couldn't fully remove the saved AO3 session. It won't be restored automatically — we'll keep retrying.” Expiry: “Your AO3 session expired. Please log in again.” Failed pending-removal retry: “Couldn't finish removing a previous AO3 session from this device. We'll keep retrying; you are not signed in.”

Confirmation: **Log out of AO3?**; “You will be signed out of AO3 on this device. Your Library, downloads, and queues stay.”; **Log Out** (destructive), **Cancel**.

### 4. Read Aloud downloads

Immediately after AO3 session, one panel with these two paragraphs, verbatim:

“Optional Voice Pack downloads stay separate from your reading data.”

“Kudos never sends a work's text, spoken audio, your AO3 sign-in, saved works, reading history, usage information, or anything that identifies your account to the Voice Pack provider. The provider can see your IP address and basic details about the connection. Kudos tells you this before downloading a Voice Pack, and the installed voices stay on this device.”

## Decided without asking

- Keep new measuring logic and screen-specific text/rows in `settings/`; reuse the current repositories and confirmations. No shared component, backup format or Room schema changes.
- Preserve existing Clear effects and preference-controlled confirmations. Use Android's existing logout, which clears local session storage and cookies and sends **zero requests** to AO3.
- Demo assets use the existing seed path; tests live alongside the Settings suites.

- `LocalDataFootprint.kt` contains the scanner, snapshot, decimal byte formatter and conditional-row rule. No dependency or second storage implementation was added. Android has no Foundation formatter; `NumberFormat` provides local numeric formatting with file-style decimal KB/MB/GB units, numeric zero and adaptive 0/1/2 fraction digits. Foundation's localization/rounding at unit boundaries still needs comparison on the devices.
- Android paths: `Context.filesDir/works/<uuid>.epub` for kept and reading copies; `filesDir/originals/` for originals and conversion records; `filesDir/fonts/` for imported fonts; `filesDir/WritingTextRecovery/` for chapter/summary/note crash recovery. `CommentDraftStore`'s `filesDir/datastore/comment_drafts.preferences_pb` is not the Swift scanner's WritingTextRecovery category, so is not folded into it. The persisted Browse metadata cache is `Context.cacheDir/fandom-catalog.json`. Readium opens/streams EPUB ZIP assets; there is no app-owned Reader unzip directory to count. Android's separate `cacheDir/comment_threads/` is also outside the Swift scanner's Metadata/Reader directories and excluded. Voice pack staging, import staging and WebView caches are outside iOS's named categories and excluded.
- Scan on `Dispatchers.IO`, recursively skipping hidden and nonregular entries/symlinks. Android POSIX `st_blocks * 512` supplies allocated size, otherwise logical size. Reading copies use logical `Files.size`, then subtract from the entire works directory, exactly like Swift (including its mixture of logical reading sizes and allocated directory sizes). Active works use `observeLibraryWorks`, rather than the old saved-only observer; protection/download decoration comes from WorkRepository. Positions use `observePositionedWorks`; collections use `CollectionDao.getAll` (active only); saved searches use `SavedSearchDao.getAll` (all records). No production figure is omitted: all corresponding stores can be measured. In an unconfigured preview with no injected scanner, unavailable figures are omitted instead of inventing values.
- Default demo launch: `kudosDemoLibrary=true`, `kudosDebugRoute=nav:settings`, `kudosSettingsPage=privacy`. The nested destination is `privacy`; no new app route. `kudosDemoSignedIn=true` supplies the existing local fixture identity for the signed-in state (no real sign-in).
- Demo: **Tea in the Jasmine Dragon** has an AO3 source, an EPUB and no keep flags/keepers: `hasEpub && !isDownloaded` is true, so the reading-copy row appears. **Ashfall** is explicitly saved and in the keeping Slow burns queue: downloaded bytes are positive. Other kept fixture EPUBs contribute too. Existing positive spine/fraction rows (Sodium Lights, Ashfall, Winter Garden, etc.) provide reading positions. **Comfort reads** and **To recommend** are active collections (Summer 2025 is deleted and excluded). Additive `seedPrivacyData` preserves existing rows, progress and assets and also runs for installed demos: **Paper Cranes** gets its actual demo chapter text as a kept TXT original; **Privacy-demo.ttf** copies an existing readable system TTF and adds a valid UUID font record; `WritingTextRecovery` gets a real unpublished summary for the local demo identity; **Demo: Doctor Who** is a saved search with a searchable fandom filter; the fandom-catalog cache contains a TV Shows entry for Doctor Who with 42 works. No HTTP fixture or network request is added.
- Filesystem tests supply small real files in a disposable temporary directory, a Room in-memory database and local auth stores. Byte-only font fixtures test measurement, not font parsing; device demo fonts are actual system fonts. Screen tests use native graphics, a tall window, patient waits, explicit Unit coroutine bodies and per-row selectors where figures repeat. No cleanup waits for the main thread.

## Open questions

- iOS always asks before its four Clear actions; Android's existing `confirmBeforeDelete` preference can bypass those dialogs. The brief also requires existing confirmations/effects unchanged, so preserve that preference. Remove AO3 session always asks. No request is made to resolve this difference.
- If a device has no readable `/system/fonts/*.ttf`, the demo omits its font fixture instead of creating an invalid font or downloading one. Normal Android emulator images have system TTFs; Claude must verify this row is nonzero on the chosen image. System files are copied only at runtime in the demo; no font asset is redistributed in this patch.
- iOS supplies record counts synchronously through SwiftData queries. Room supplies them asynchronously: Android displays “—” until the first real counts arrive; it never flashes fabricated zero counts. Positions then remain live through the collected observer; collections/search counts and sizes rescan after each Clear. iOS also has pull-to-refresh; this patch follows the brief's opening/after-Clear measurement triggers, without adding a new refresh control to the existing Settings frame.
- iOS's `freedHistory` does not explicitly exclude `isQueuedForLater`; Android's already-landed history predicate does. That narrower Android effect stays unchanged as required. Both use protection/deletion checks and keep saved, favourited, imported and unavailable works safe.

## Implementation / verification

- Replaced every hardcoded figure in `PrivacyDataScreen` with measured bytes/counts; added the missing size categories and zero visibility rules, separate Clear heading/footnotes, session panel, and Read Aloud panel. Mint promise panel now follows the Swift code. Page uses `SettingsPage` / `SubjectHeaderBlock`, `SectionRuleHeader`, `SubjectFormRow`, `subjectPanel`, and settings' destructive color/action style. New text has explicit line height; section headers inherit a screen-local line height. No shared component was edited. Long labels have short trailing values, with unbounded stacked values at accessibility scale. `ProvidePushedShellChrome()` owns this nested screen's shell row.
- Clear methods remain `freeFinishedCopies`, `clearReadingPositions`, `softDeleteHistoryOnly` and `FandomCatalogCache.clear`, unmodified. Existing messages match iOS already; Free up space now correctly says **1 file**, the post-clear browse label becomes **Browse cache cleared**, and Browse's value and confirmation button now include actual cache bytes. All three work action values use the same predicates as their existing writers; no history/filter rewrite or new deletion effect.
- `AO3AuthRepository.noticeMessage` is collected by the screen. Notices follow actual successful/failed durable removal and expiry; the existing mutex/generation/cookie/delete behavior remains intact. `Remove AO3 session` uses the existing always-confirming `LogOutConfirmation`, then only `AO3AuthRepository.logout`. That method deletes local durable credentials, marks removal pending on failure, clears the local cookie store and in-memory session. `AndroidAO3CookieStore.clear` expires AO3 cookies in CookieManager and flushes that local store. It sends **no GET, POST or other HTTP request**, and the screen never restores/verifies a session or fetches AO3 data.
- Written, **not run**: `LocalDataFootprintTest` (4 cases: exact nonzero file/record measurements including active/deleted collection exclusion; adding files and ignoring hidden/unrelated files; zero row visibility/decimal wording; demo selection/nonzero figures/idempotency), `PrivacyDataScreenTest` (6 cases: sections/words and zero rows; signed-in/remove/cancel/confirm/local logout; expiry notice; failed-removal notice; existing Clear effects and measured rescan; four palettes at accessibility scale). Room measurement tests forbid main-thread queries and record query threads; the scanner's entire disk traversal is inside `withContext(Dispatchers.IO)`. All test dependencies are local, with no validator or HTTP client installed.
- Existing `WorkLifecycleTest` cases `freeUpSpaceAlsoFreesLegacyFinishedCopiesWithoutAHoldStamp`, `clearReadingHistoryTakesOnlyWorksThatRemainInTheHistoryAlone`, and `clearReadingPositionsForgetsThePlaceAndKeepsTheWorkAndItsShelfDate` are unmodified and must still pass. Also rerun DemoLibraryTest, auth suites (including failed durable deletion), Settings suites, backup/font regressions.
- Ran `android/Scripts/check-invariants.sh`: **passed**. `git diff --check`: **passed**. Read actual repository/model/file-store/auth/navigation/component signatures used. These mechanical checks do not establish Kotlin compilation, runtime behavior or visual correctness.
- Claude must run `assembleDebug` and `testDebugUnitTest`, including both new suites and the existing suites above. Verify shell Back, normal/AX text, Light/Dark/Sepia/OLED, every demo byte/count row nonzero, section ordering, all confirmation buttons/cancel paths, disabled zero rows, and pending em dashes. Compare Foundation/Android byte labels around unit boundaries; inspect font validity on the actual emulator. No visual-correctness claim is made here.
- Changes remain uncommitted on the original `android/agent-gemini-3bz` branch. No AO3 contact, actual sign-in, branch switch, commit, push, TASKS edit, helper/scratch/stub source, `.orig`, schema or backup-format change. iOS reference files were read only.

## Final continuation review

- Continued the existing patch in place. Strengthened the screen tests with independent Swift wording literals and checked the common sections in both signed-in and not-signed-in states. Corrected allocation fallback: a real sparse file with valid block metadata may occupy zero blocks; only unavailable block metadata falls back to logical size. Both changes remain unexecuted Kotlin code.
- Final mechanical checks: Android invariants and `git diff --check` passed. The branch, TASKS, schemas, backup format and iOS reference remain unchanged.

## Needs a test run

- **Compile:** Android `assembleDebug`, including Room/Compose signatures and all test source compilation. No Gradle or Xcode was run here.
- **New automated suites:** `LocalDataFootprintTest` and `PrivacyDataScreenTest` (ten cases total). Validate nonzero/exact bytes and record counts, file/record additions, zero-row hiding, ignored files, IO-thread measurement, section wording in both session states, confirmed logout/cancel, expiry/removal-failure notices, Clear effects/rescans, and four themes at accessibility scale.
- **Existing automated suites:** WorkLifecycle's Free up space/history/positions cases; DemoLibraryTest; auth/removal-pending/generation tests; Settings tests; font and backup regressions. Their code was not changed or run.
- **Device UI:** open `nav:settings` with `kudosSettingsPage=privacy` and demo seeding; inspect every measured row as nonzero, all four sections, pending “—”, disabled zero actions, shell Back, cancellation, and ordinary/accessibility text in Light, Dark, Sepia and OLED. Use only local demo identity/fixtures; never sign in or contact AO3 for this verification.
- **Device byte formatting/storage:** compare Android's decimal byte labels against Foundation near unit boundaries and in the chosen locale; verify allocated-block results and that the copied system TTF is readable and appears under Imported fonts. No visual or runtime correctness claim is made until these checks pass.

## Decided without asking — final list

- Kept the iOS promise card because the actual Swift code contains it, despite the brief's contrary statement; copied its words and Mint palette.
- Put measurement/formatting rules in `settings/LocalDataFootprint.kt`, kept screen-specific rows/text in `PrivacyDataScreen.kt`, and placed both new test suites in the existing Settings test directory. Reused the actual repositories, confirmation components and nested Settings route.
- Used numeric decimal file units, allocated bytes where supported, logical reading-copy bytes, active records, and iOS's positive-only visibility rules. Pending figures show “—”; unavailable preview figures are omitted. Excluded stores outside the Swift scanner's named categories instead of broadening the measurement.
- Preserved the existing Clear writers, preference-controlled confirmations and Android's narrower history predicate. Added no refresh control; rescans occur on opening and after each existing Clear action. Remove AO3 session always confirms and calls only the existing local sign-out, which sends nothing to AO3.
- Made demo fixtures additive: existing EPUBs/progress/collections supply their existing figures; Paper Cranes supplies preserved TXT source, a device system TTF supplies font bytes, a local summary supplies recovery bytes, and one named search/catalog entry supplies search/cache figures. Nothing is fetched; a device without a readable TTF gets no invented font.
- Used temporary real filesystem entries, an in-memory Room database and local auth test stores. Font-byte test fixtures exercise counting rather than font parsing; the runtime demo copies a real font. No helper script, stub production file, `.orig`, new dependency, schema change or backup-format change was left behind.

---

## Landing note (Claude, 2026-10-09)

Landed on `android/redesign-parity`; the patch applied cleanly. Gate: 2,375 tests. **Not seen
on the emulator** (agents were running): owed are the four sections with the demo's figures
(`kudosDebugRoute=nav:settings`, `kudosSettingsPage=privacy`), each Clear with its
confirmation and the figures after it, Remove AO3 session and its footnote, in Light and
Sepia and at the largest text; and the imported-fonts row being above zero on the emulator
image.

Changed on landing, in the tests only:

- `clearRowsRetainTheirEffectsAndRescanDiskAndCounts` failed in two different ways on two
  runs. It waited for two rows reading "0 works" after Clear reading history, and two rows
  already say that once the positions are cleared (the stored row and the Clear row), so the
  wait passed at once and the assertions raced the Clear. It waits on the works themselves
  now. And the test's teardown closed the database while the screen was still measuring on
  another thread ("connection is closed"): the in-memory database is no longer closed there.
  Three runs in a row pass.

Read and left as written: the sign-in repository gains a notice (iOS's words: the session
expired, logged out, and the two sentences for a saved session that could not be removed);
nothing in it reads from or writes to AO3, and Remove AO3 session is the existing local
logout. The four Clear actions keep the reader's "confirm before delete" preference, where
iOS always asks.
