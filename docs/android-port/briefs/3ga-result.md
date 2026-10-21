# Brief 3ga result

Branch: `android/agent-codex3-3ga`, starting at `f70401a5`.

Scope: A66 verified findings #4, #11, #12, #1, #23, #19, #6, #20, #5.
All nine requested fixes implemented; awaiting Claude’s build/test/device validation. No Gradle, AO3 requests, sign-in, commits, pushes,
branch switches, or TASKS.md edits. Claude owns builds, tests, visual checks and landing.

Completed items, iOS references and added tests are recorded below.

## #4 — reject fonts that cannot travel in a backup

- Changed `android/app/src/main/java/io/github/cidy02/kudos/files/CustomFontRepository.kt:42`:
  validates through BackupFontValidator before writing; enforces BackupLimits' 4 MB per-font
  and 32 MB installed-total caps, measured off the UI thread. Rejections use iOS's words.
- iOS followed: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Settings/SettingsView.swift:234`
  (`importFont`, `fontTotalRejectionReason`) and `Services/KudosBackup.swift:52` (`fontRejectionReason`).
- Tests: `android/app/src/test/java/io/github/cidy02/kudos/files/CustomFontRepositoryTest.kt:133`
  rejects empty, malformed, signature-only and >4 MB fonts without changing files/rows/selection;
  `:147` accepts exactly 32 MB and rejects the next font without changing selection/metadata.
  Existing success tests now use the existing real OpenDyslexic fixture instead of dummy bytes.

## #11 / #12 — native login

- Changed `android/app/src/main/java/io/github/cidy02/kudos/auth/AO3NativeLoginScript.kt:8`:
  checks remember-me before submit; extracted script keeps the HTTPS/exact-host guard and
  encodes credentials as JSON literals (memory only).
- Changed `android/app/src/main/java/io/github/cidy02/kudos/auth/AO3NativeLoginScreen.kt:105`:
  one guarded submit path for Log In and keyboard Go; failures retain the password, success
  and disposal clear it; no-form/no-fields reveal the existing visible fallback automatically.
  AO3 flash errors take precedence over the generic failed-login message.
- Changed `android/app/src/main/java/io/github/cidy02/kudos/auth/AO3WebLoginScreen.kt:155`:
  shared page inspection reads iOS's error selectors and properly decodes WebView's nested JSON,
  including escaped quotes/newlines/unicode, instead of extracting values with regex.
- iOS followed: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Services/AO3WebLoginCoordinator.swift:193`
  (failure/fallback), `:316` (submit/remember-me), `:361` (error selectors), and
  `Features/Auth/AO3LoginView.swift:122` (Go), `:202` (retain password on failure).
- Tests: `android/app/src/test/java/io/github/cidy02/kudos/auth/AO3NativeLoginScriptTest.kt:9`
  pins remember-me ordering and host guards, credential escaping, missing/invalid script responses
  and AO3 error decoding. Keyboard and fallback-retention UI coverage is recorded below.
- No sign-in or AO3 traffic performed. Existing fallback still uses Android's separate visible
  WebView; retaining iOS's same-WebView handoff is outside this verified fix.

## #1 — all four Privacy Clears always confirm

- Changed `android/app/src/main/java/io/github/cidy02/kudos/settings/PrivacyDataScreen.kt:180`:
  all four bulk-clear dialogs pass `confirmBeforeDelete = true`. The swipe preference stays intact.
- Added the owner-authorized reversal at the end of `docs/android-port/DECISIONS.md` (2026-10-20,
  brief 3ga), superseding the 2026-10-09 (3bz) choice.
- iOS followed: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/Account/PrivacyDataView.swift:120`
  through `:177`; Settings/SettingsStoragePages.swift's swipe-only footnote is unchanged.
- Test: `android/app/src/test/java/io/github/cidy02/kudos/settings/PrivacyDataScreenTest.kt:251`
  opens and cancels each dialog with swipe confirmation off; files, progress, history and cache
  remain intact. The existing four-clear effects/rescan test remains.

## #23 — Privacy storage pull-to-refresh

- Changed `android/app/src/main/java/io/github/cidy02/kudos/settings/PrivacyDataScreen.kt:85`:
  wraps the page in the existing KudosRefreshBox, remeasuring the scanner on a pull.
  Initial-open and post-clear scans remain; the refresh does no network work.
- iOS followed: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/Account/PrivacyDataView.swift:119`
  (`.refreshable { await measure() }`).
- Test: `android/app/src/test/java/io/github/cidy02/kudos/settings/PrivacyDataScreenTest.kt:273`
  adds font storage after opening, pulls, and checks the newly measured font figure appears.

## #19 — Downloads and Privacy share one storage total

- Changed `android/app/src/main/java/io/github/cidy02/kudos/settings/LocalDataFootprint.kt:28`:
  totalBytes sums the same six byte categories Privacy displays.
- Changed `android/app/src/main/java/io/github/cidy02/kudos/settings/SettingsPages.kt:195` and
  `SettingsScreen.kt:74`: Downloads measures the supplied footprintScanner, replacing the
  whole-filesDir walk. It shows “…” while scanning and “—” if no scanner is supplied.
- iOS followed: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Settings/StorageUsedRow.swift:17`
  and `Services/LocalDataFootprint.swift:37` (`totalBytes`).
- Tests: `android/app/src/test/java/io/github/cidy02/kudos/settings/LocalDataFootprintTest.kt:147`
  checks all six categories and zero; `SettingsA66ParityTest.kt:61` checks the rendered Downloads
  total includes Browse cache and imported fonts while excluding unrelated files.

## #6 — Appearance keeps typography customization in its sheet

- Changed `android/app/src/main/java/io/github/cidy02/kudos/settings/SettingsPages.kt:39`:
  removed only the second section (line height, letter/word spacing, margins), including its
  implicit Customize-on writes. Every removed control already exists in CustomizeThemeSheet
  (Line Spacing, Character Spacing, Word Spacing, Margins); no setting or stored value is lost.
  Theme, matching, reader theme, accent, reset, Customize Theme and Text Size remain.
- iOS followed: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Settings/SettingsReadingPages.swift:43`
  and `Features/Reader/CustomizeThemeView.swift:78`.
- Tests: `android/app/src/test/java/io/github/cidy02/kudos/settings/SettingsA66ParityTest.kt:42`
  checks Appearance's retained controls and that the sheet still holds all four sliders;
  `SettingsStringsTest.kt:34` moves the old-control guard to the sheet's current labels and
  checks Appearance no longer forces Customize on.

## #20 — Queue Storage author navigation

- Changed `android/app/src/main/java/io/github/cidy02/kudos/settings/QueueStorageScreen.kt:242`:
  uses VerifiedAuthorByline with the work's authorIdentitiesJSON, picking up LocalOpenAuthor.
  Row removal, swipe and Keep Download menu stay intact. Row visibility is internal for its UI test.
- iOS followed: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/Library/ReadingQueues.swift:383`
  (verified AO3AuthorBylineView in preserved-work rows); Android's existing shared verified byline
  resolves a pseud to its account rather than guessing by display text.
- Test: `android/app/src/test/java/io/github/cidy02/kudos/settings/QueueStorageBylineTest.kt:23`
  taps a verified pseud in the actual storage row and checks the exact account route; an
  unverified coauthor has no click action.

## #5 — work import picker accepts every file

- Changed `android/app/src/main/java/io/github/cidy02/kudos/settings/SettingsPages2.kt:95`:
  picker MIME types are `*/*`; all picks still use ExternalFileImport's existing date-confirmed
  work import path. Unknown-format rejections in `works/WorkImporter.kt:476` name the picked
  extension when one is available, with iOS's conversion guidance.
- iOS followed: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Settings/SettingsImportPage.swift:134`
  (`.data` catch-all); `Services/UserDocumentImport.swift:45` and
  `Services/ImportedDocumentConverter.swift:63` (work import / unsupported-format guidance).
- Checked `.kudosbackup`: iOS Import sends every pick through UserDocumentImport.perform; it
  does NOT route backups to BackupImportSheet. Android therefore keeps its existing work-import
  routing too. A backup ZIP without readable work entries reports the archive-specific error;
  the dedicated Backup page remains the place to restore it.
- Tests: `android/app/src/test/java/io/github/cidy02/kudos/settings/SettingsStringsTest.kt:49`
  pins the catch-all; `works/WorkImportFeedbackTest.kt:8` covers a named unsupported extension,
  extensionless guidance and unchanged PDF/archive-specific errors.

## Validation / handoff

- Added `android/app/src/test/java/io/github/cidy02/kudos/auth/AO3NativeLoginFieldTest.kt:22`:
  demo-only fallback/return preserves both credentials; `:37` checks keyboard Go calls submit.
  These tests mount no network WebView and attempt no login.
- Not run: Gradle, build/test suites, emulator or visual inspection (dispatch restriction).
  All new tests await Claude's execution; native failure/fallback UI still needs offline/device
  verification. Never exercised a live sign-in.

- Completed static verification: `git diff --check` passes. Reviewed all modified production
  paths against the verified findings and the cited iOS implementation. No new regex is added;
  the login JSON parser replaces two regexes. Room entities/migrations, backup version/manifest,
  signing, TASKS.md, branch and HEAD are unchanged. Working edits are intentionally uncommitted.
- Claude next: run the new/updated font, login, Privacy, footprint, Settings, queue-byline and
  import-feedback suites (including RegexPortabilityTest), build Android, then inspect the
  changed UI. Existing oversized/invalid installed fonts are preserved and may still prevent
  backup export, as on iOS; this brief prevents new invalid imports.

## Review fixes

This section supersedes the earlier import-routing claim: a real backup with EPUB entries
must never enter archive-to-work conversion. Findings read from the verified `3ga` entries in
`/Users/cidy02/kudos-android-lane/docs/android-port/audits/review-3fz-3ft-3fx-3ga.json`.

- **4 — login without a flash error:** `android/app/src/main/java/io/github/cidy02/kudos/auth/AO3NativeLoginScreen.kt:307`
  now automatically reveals the visible fallback for a non-authenticated finished page with no
  AO3 error, including login/CAPTCHA/interstitial pages. AO3 flash errors still take precedence;
  credentials remain in memory. Follows iOS `Services/AO3WebLoginCoordinator.swift:214`.
  Regression: `AO3NativeLoginScriptTest.submittedPageWithoutFlashErrorRequiresVisibleFallback`
  exercises the decision used by the page callback (no-flash → fallback; explicit error or
  authenticated session → no fallback). No network execution.
- **5 — caption byline:** `android/app/src/main/java/io/github/cidy02/kudos/settings/QueueStorageScreen.kt:242`
  opts into the shared verified byline's compact variant; `works/detail/WorkDetailIdentity.kt:196`
  uses 12sp normal-weight names and separators, preserving verified account navigation and the
  detail screen's existing default. Follows iOS `Features/Library/ReadingQueues.swift:383`.
  Regression: `QueueStorageBylineTest.verifiedPseudOpensItsAccountAndUnverifiedCoauthorStaysPlain`
  now also inspects actual Compose text layouts for both authors and the separator at 12sp;
  without this fix the layout assertion reads 15.5sp. Existing route/plain-text assertions remain.
- **2 — named unsupported formats:** `android/app/src/main/java/io/github/cidy02/kudos/files/ImportedFileFormat.kt:14`
  detects RTF, Word/OpenDocument ZIPs, Kindle/Palm, RAR and 7-Zip. Both initial import and
  rebuild refuse these instead of converting control words or treating office files as chapter
  archives. `works/WorkImporter.kt:484` provides iOS's specific refusal/conversion instructions
  (`Services/ImportedDocumentConverter.swift:65`). PDF/HTML/text/EPUB/ordinary ZIP support remains.
  Regressions: `ImportedFileFormatTest.unsupported office and archive formats are named rather
  than imported as prose` covers renamed content signatures and archive markers;
  `WorkImportFeedbackTest.namedUnsupportedFormatsUseIosConversionInstructions` pins every
  specific message. Before the fix RTF detects as TEXT, DOCX/ODT as ZIP and other types UNKNOWN.
- **1 — bounded file preparation:** `android/app/src/main/java/io/github/cidy02/kudos/works/PickedDocumentReader.kt:26`
  checks provider size and a 4 KB prefix before reading the remainder; refuses unsupported
  content immediately. Supported input is streamed with a 32 MiB ceiling even for missing or
  false size metadata. ZIP inspection uses a temporary file and central-directory lookup,
  bounded manifest/OPF reads, and finally deletes the temporary. `works/DocumentImportPreparation.kt:9`
  keeps only URI/name/date metadata until confirmation; `app/KudosApp.kt:73` loads one confirmed
  document at a time and reports per-file read failures. The backup picker uses the same bounded
  read, so an incoming backup cannot bypass this ceiling. The new explicit limit can refuse
  otherwise valid documents/backups larger than 32 MiB; it never changes or deletes those files.
  Regressions: `PickedDocumentReaderTest.unsupportedBinaryReadsOnlyPrefixAndKnownOversizeReadsNothing`
  verifies 4 KB/zero-byte reads; `unknownOrUnderreportedSizesAreBoundedDuringInspectionAndConfirmation`
  checks both passes stop at limit+1; `rtfIsRefusedBeforeReadingTheRestAndOfficeZipsGiveSpecificGuidance`
  checks early refusal and temp cleanup. `renamedEpubRetainsGeneratedDateWithoutReadingChapterPayloads`
  preserves the existing generated-date fallback with central-directory OPF lookup.
- **3 — backup routing:** `android/app/src/main/java/io/github/cidy02/kudos/works/PickedDocumentReader.kt:46`
  recognizes a root backup manifest (`version` + `works`), regardless of filename or supported
  version, before EPUB/archive conversion. `works/DocumentImportPreparation.kt:42` queues it
  separately; `app/KudosApp.kt:211` opens `backup/BackupScreen.kt:133`'s incoming-file mode and
  existing Import Backup sheet, with the existing Merge/Replace/safety-copy behavior. Batches
  review one backup at a time, then resume work date confirmation. Nothing restores before
  the user chooses an action. `works/converters/ArchiveWorkConverter.kt:26` also refuses a
  backup manifest so its nested EPUBs cannot become standalone works through a direct caller.
  This follows the latest dispatch's explicit routing requirement; it corrects the earlier
  result's claim that archive handling was adequate (the inspected iOS Import page itself
  still used the generic work path).
  Regressions: `PickedDocumentReaderTest.backupManifestWinsOverNestedEpubsAndNamesAndVersions`
  covers Works/*.epub, renamed ZIP/EPUB files, v8/v9, non-backup archives and converter refusal.
  `PickedBackupImportTest.pickedBackupOpensReviewAndCancelChangesNothing` runs picker preparation
  then the actual backup sheet and asserts no library write on preview/cancel;
  `pickedBackupMergeRestoresFlagsAndProgressInsteadOfImportingAStandaloneBook` uses that sheet's
  empty-library Restore action and asserts the original UUID/title/favorite/progress/EPUB.
  Before the fix, preparation queued a work instead and archive conversion returned its EPUB.

Review-fix verification: `git diff --check` passes; static scan finds no Android-rejected
regex flags and this pass introduces no regexes. Checked all PendingDocumentImport callers
and both format-conversion switches after changing the pending payload/format enum. Builds,
Gradle/JUnit/Compose suites, emulator screenshots, picker/provider behavior, and live login
were not run (dispatch restriction). Claude should run the new/updated
PickedDocumentReaderTest, PickedBackupImportTest, ImportedFileFormatTest,
WorkImportFeedbackTest, AO3NativeLoginScriptTest, AO3NativeLoginFieldTest,
QueueStorageBylineTest and RegexPortabilityTest, plus the original 3ga suites above.
Manual: mixed backup/work/error batches, multi-backup cancellation, oversized/unknown-size
SAF providers, CAPTCHA fallback and compact byline in Queue Storage. The visible fallback
still uses the existing separate WebView, as documented in the first pass.

Working edits remain uncommitted on `android/agent-codex3-3ga` at `f70401a5`.
No TASKS.md edit, schema/version/signing change, Gradle invocation, AO3 request, sign-in,
commit, push or branch switch was made.

## Full-gate follow-up — 2026-10-20

Addressed the three failures reported from the integrated lane's `c62201d0` gate
(3,104 other tests passed, per dispatch). This worktree remains at `f70401a5` with
the existing uncommitted 3ga/review edits; no rebase or branch switch was performed.

1. **Fallback return test used scrolling on a non-scrolling control.** In this
   worktree `AO3NativeLoginFieldTest.kt:32` was the **Back to username/password**
   `performScrollTo()`, not Use alternative method. The native form already has
   unconditional `verticalScroll`; the fallback's outer column scrolls only at
   accessibility text sizes. `auth/AO3NativeLoginFieldTest.kt:36` now asserts the
   normal-size Back control is displayed and clicks it directly. Native-form and
   accessibility-fallback scrolling are preserved. Added
   `largeTextFormAndFallbackControlsRemainScrollable` (`:44`), using native
   Robolectric graphics, a 411×800dp viewport and 200% text: scroll to both fields,
   enter credentials, scroll to the alternative-method button, fallback heading,
   prompt, Reload and Back; return and check the username and enabled Log In.
   iOS reference: `Features/Auth/AO3LoginView.swift:115` uses a native `Form`.

2. **Restore the fallback heading alongside its explanation.**
   `auth/AO3NativeLoginScreen.kt:146` now renders “Using alternative login method…”
   as a heading, followed by `message ?: FallbackPrompt`. iOS's
   `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/Features/Auth/AO3LoginView.swift:181`
   (`fallbackChrome`) shows both; `Services/AO3WebLoginCoordinator.swift:83,193–214`
   supplies “Let's finish logging in on AO3's page below.” for missing forms,
   failed submission and a submitted page without an AO3 error. The heading must
   not be replaced by that prompt. Updated
   `onboarding/FirstRunDemoScreensTest.kt:94` to check both lines and that Reload
   never invokes the external-page callback. Existing assertions still check no
   login completion and no mounted WebView before/after submission, help and
   fallback. No demo network guard or request behavior was changed.

3. **Seed data eligible for Clear reading history.** iOS
   `Features/Account/PrivacyDataView.swift:64–65,355–358` filters for no EPUB and no
   protection, and disables the row when that list is empty. Android's
   `WorkRepository.observeHistoryOnlyWorks` and `PrivacyDataScreen` already agree.
   `settings/PrivacyDataScreenTest.kt:260` now inserts a separate unprotected AO3
   history work with `hasEpub = false` and a reading date; the original EPUB fixture
   remains available for Free up space and Clear reading positions. Every Cancel
   also checks the history work's deletion flag and reading date stay unchanged.
   The existing empty-storage test (`:140`) now asserts Clear reading history is
   disabled. Production history eligibility and the existing clear-effects test
   were left intact.

Paths above are under `android/app/src/main/java/io/github/cidy02/kudos/` or
`android/app/src/test/java/io/github/cidy02/kudos/` as appropriate. iOS references
were read from `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`.

Verification: `git diff --check` passes; reviewed the changed Compose branches,
fixture eligibility, callers and iOS source. No Gradle/build/tests, emulator or
visual verification was run. Claude should rerun `AO3NativeLoginFieldTest`,
`FirstRunDemoScreensTest` and `PrivacyDataScreenTest`, including the new 200% text
test, then inspect the fallback on-device. These edits remain uncommitted.

Rebase note: **no edit to `backup/BackupScreen.kt` in this follow-up**. When
applying these fixes to the lane, keep 3fy's `OpenBackupDocument()` launcher and
the retained `prepareImport(uri)` refactor. This older worktree's backup diff is
not part of the follow-up. No TASKS.md, backup, schema, signing, network or git
mutation was made by this follow-up.
