# I6 result

Worktree: `/Users/cidy02/kudos-agent-ios`; branch: `claude/agent-ios-i6`.

Scope: T-364 model regression tests and DEBUG login/thread routes only.
No TASKS.md edits, commits, pushes, branch switches, sign-ins, AO3 requests,
or xcodebuild runs. Existing untracked Android-port briefs are preserved.
`READIUM_MIGRATION_NOTES.md` is absent; tracked implementation and invariants
are used to trace the reader paths.

## Completed items

### 1(a). Signed reader deletions

- `KudosTests/ReadingAnnotationBackupTests.swift:45`:
  `readerDeletionPersistsASignedTombstone` runs for highlight, note (a highlight
  with note text), and bookmark. It deletes through the reader's model operation,
  saves and reloads an in-memory store, checks the annotation is gone and the
  work remains, verifies the Ed25519 signature and checks adoption by a distinct
  trusted peer. Signing/Keychain/cloud seams are isolated and restored.
- `kudos-ao3-reader/Features/ReaderReadium/ReadiumReaderPersistence.swift:24`
  extracts the existing signed tombstone + hard-delete operation, called by both
  reader paths at `kudos-ao3-reader/Features/ReaderReadium/ReadiumReaderView.swift:725`
  (bookmark toggle) and `:856` (Delete).
- Reverting T-364's signing fix in that operation to an unsigned `SyncTombstone`
  makes all three cases fail the signer, nonempty signature, signature verification,
  and peer-adoption assertions. Omitting the tombstone fails its required fetch;
  omitting the hard-delete fails the empty annotation fetch.

### 1(b). iPhone position saves carry the Mac resume pair

- `KudosTests/SavedWorkProgressTests.swift:139`:
  `readiumPositionSavePersistsBothResumeFormats` starts with either zeros or a
  stale Mac chapter, writes a locator with chapter progression 0.375 and overall
  progression 0.65, and reloads an in-memory store. It requires the exact locator,
  spine index 5 (not the section's array offset/story chapter), chapter fraction
  0.375, and progress timestamp, while keeping the streamed-save shelf clocks.
  Reverting the pair writes makes both cases fail the spine/fraction assertions
  (0/0 or 7/0.9 survives instead of 5/0.375).
- `KudosTests/SavedWorkProgressTests.swift:170`:
  `newerIPhonePositionDoesNotResetMacChapter` saves/reloads the phone copy, feeds
  its snapshot through the actual `SyncMerge.applyProgress` used by restore/sync,
  then saves/reloads the Mac copy. The newer phone position must replace the older
  Mac pair with 5/0.375 and retain its Readium locator. Reverting T-364's pair writes
  makes this test fail: the newer phone's 0/0 overwrites the Mac's 7/0.9.
- `kudos-ao3-reader/Features/ReaderReadium/ReadiumReaderPersistence.swift:10`
  extracts the existing locator parsing, href-to-spine matching and clamped
  chapter-progression writes. The view delegates at
  `kudos-ao3-reader/Features/ReaderReadium/ReadiumReaderView.swift:759`;
  debounce, flush and publication-end all continue through that method.
  The extracted implementation and new tests are iOS-guarded; the Mac reader
  still reads its existing pair. No model/schema changes.

### 2. DEBUG login and thread routes

- Login: `-KudosDebugRoute login` presents the actual `AO3LoginView` as a sheet
  (`kudos-ao3-reader/App/ContentView.swift:70`).
  `kudos-ao3-reader/App/DemoLibrary.swift:408` supplies a fresh, unrestored auth
  service so the form has no logged-in session, even with `-KudosDemoSignedIn YES`.
  It does not erase the surrounding app's saved session. Android equivalent:
  `--es kudosDebugRoute nav:login`.
- Thread: `-KudosDebugRoute 'thread:Sodium Lights'` (or another exact demo title)
  follows the existing Home → work detail → Comments route, then pushes the real
  `CommentThreadScreen` with the Comments model and handlers. Route registration:
  `kudos-ao3-reader/App/DemoLibrary.swift:369` and `:399`; root selection: `:381`.
  It chooses a visible Continue-thread root, otherwise the first conversation
  with replies (the bundled fixture uses comment 1001), otherwise the first root.
- The required DEBUG-only integration hook in
  `kudos-ao3-reader/Features/Comments/CommentsView.swift:225` runs after the normal
  initial load and calls the existing `openThread` action exactly once per view.
  This retains Back, reply, login, author and parent-thread handling rather than
  rendering a separate imitation. Account Inbox's destination was also traced:
  it opens `CommentsView` with `initialCommentID` in
  `kudos-ao3-reader/Features/Account/AccountView.swift:215`; its route data is in
  `kudos-ao3-reader/Features/Account/AccountInboxViews.swift:21`.
- Android equivalent: `--es kudosDebugRoute 'nav:comments/<id>?focused=<commentId>'`;
  for the bundled fallback work/comment, use
  `nav:comments/999000005?focused=1001`. Android's focused route is defined in
  `android/app/src/main/java/io/github/cidy02/kudos/app/Routes.kt:88`.
- Use the existing offline launch harness:
  `-KudosDemoLibrary YES -hasCompletedOnboarding YES -KudosFixtureDir <fixture-dir>`
  plus the requested route. No request to AO3 was made during this work.
  All route additions are DEBUG-only and introduce no platform-specific APIs.

## Verification

- Passed: `Scripts/check-invariants.sh`; SwiftLint on all changed Swift files
  (exit 0, existing size/style
  warnings only); Swift frontend syntax parsing for DEBUG/macOS and DEBUG/iOS;
  `git diff --check`.
- The iOS syntax-only parse used the host sysroot and reported its expected
  SDK/target mismatch warning; neither parse type-checks or builds the app.
- No xcodebuild, tests, simulator launches, sign-in, network access, commits,
  pushes, branch switches or TASKS.md edits were performed.
- Claude still needs to run the new parameterized tests/full suite, build iOS
  and macOS, and visually inspect both routes (including Back from Thread).
