# Brief 3au result: file sharing and opening an original

**Landing note (Claude, 2026-10-05).** Codex ran out of usage as it finished; the code and
tests were complete. Gate green (1,537 tests). Where this file says the owner answered, it was
Claude (the decision is in `DECISIONS.md`); the owner has not been asked.

Changed on landing:
- The file's name for the receiving app is the work's title, which is the author's text. It now
  loses path separators and control characters, a leading dot, and anything past 80
  characters (`shareFileName`, with a test of hostile titles).
- The reader asked the disk whether the file and the original exist every time the work's row
  changed, which is every page turn. It now asks once per work.
- Eight of the new tests failed for a reason in the test setup, not the app: Android's file
  provider remembers its folders in a static and each test gets a new folder. The setup clears
  it.

Seen on the emulator: an import with no link now has Share in the reader's menu, and the
system's sheet offers "The Long Way Down.epub"; a work with a link shares its title and link
exactly as before; with a stand-in original file in place, the Original icon appears between
Share and Read aloud, the system asks which app to open it with, and the chosen app opened it
under the work's title. Not checked: the file's contents inside the other app, a real
converted import (the demo has none), and a device with no app for the file's type.

## Status

Implementation and regression tests are written; compilation, test execution,
and device verification are pending Claude's run. No Gradle or Xcode invocation,
network request, sign-in, commit, push, branch switch, or TASKS.md edit was made.
All edits are in this worktree; the iOS reference was read only. No backup format
or Room schema changes, public/cache copies, helper scripts, or `.orig` files.
Static checks passed: provider XML parses and contains exactly the three roots
listed below; `git diff --check` reports no whitespace errors.

**Clarification is Claude's, not the owner's:** after the initial stop, Claude
(who runs this port) answered “follow iOS”. The owner was not asked. The work page
therefore stays unchanged: link-only Share, no EPUB fallback, no Original viewer.
The original brief's description of that page was incorrect.

## Reference findings

Reference root: `/Users/cidy02/kudos-ios-polish/`, read only.

- `ReadiumReaderView.swift:1952`, `shareURL`: AO3 identity first (stored ID,
  then source-derived identity), then a source URL whose scheme starts with
  `http`, then the EPUB when `WorkReaderPreparation.hasReadableEPUB` succeeds.
  `WorkCardActions.swift:266` defines readable as `hasEPUB` plus an existing file.
- `ReadiumReaderView.swift:1244`, `fanRoundActions`: Original follows conditional
  Kudos and precedes Read Aloud; Share is the first slot supplied separately by
  `ReaderFanMenu`. Original's accessibility label is “View the original file this
  work was converted from”. It opens Quick Look using `previewingOriginal`.
- `WorkReconversion.swift:33`, `candidate`: an archived original must exist;
  a conversion record is not required. A missing record receives a version-zero
  fallback. Converter staleness does not gate Original.
- The reader's share and original target functions have no Mature, history-hidden,
  login, finished, or availability condition. Quick Look has no app-defined
  missing-viewer message at this call site.
- The work page has **no EPUB sharing fallback**: `WorkDetailOverviewSections.swift:131`
  puts Share inside `if let ao3URL`; `WorkDetailView.swift:597` defines `ao3URL`
  as a nonempty local source URL or the remote work URL. A linkless local import
  receives neither. Claude confirmed this behavior takes precedence over the brief.
- The reference work page does not offer an Original viewer. Its
  `WorkProvenanceSections` offers **Rebuild from Original**, not viewing.
  Claude confirmed that no work-page Original viewer should be added.

## Entry and privacy tracing

- iOS `RecentlyDeletedView` / `RecentlyDeletedEntry` and Android
  `RecentlyDeletedScreen` provide restore and permanent-delete controls, not a
  reader/open/share action. Held finished copies also have recovery controls
  there; they remain active works and can be opened from normal shelves.
- iOS `WorkDetailView.withLocalWork` restores a pending-deletion work before its
  `read` action opens it. `ReadiumReaderView` itself does not guard deletion in
  `shareURL` or `originalDocumentURL`.
- Android's `WorkDao.getById` and `ReaderRepository.open` do not reject deleted
  records on a direct reader route. No new reader entry is added here. The new
  address/intent builder rejects `isDeleted`, and `ReaderViewModel.shareWork` /
  `openOriginal` re-read `repository.currentWork` immediately before the
  synchronous handoff and decline deleted/missing records. Thus an open reader
  with an old snapshot cannot mint an address after the work is deleted.
- iOS `MatureContent.swift`: Hide filters out unrevealed adult works; Blur taps
  reveal (optionally requiring device authentication), rather than navigate.
  Android `LibraryPrivacy.visibility` / `LibraryQuery` and `SensitiveWorkRow`,
  plus Library's cover-card tap handler, have the corresponding boundary.
  Existing entry/reveal behavior is untouched. Once reading, neither new action
  adds a Mature/Explicit restriction, matching iOS's reader actions.
- History-hidden is different from Mature privacy: iOS `ReadiumSessionStamp`
  calls `SavedWork.markProgressModified`, which clears `hiddenFromHistoryAt`;
  Android `ReaderRepository.open` likewise clears it. It does not block Share
  or Original. Finished and unavailable works likewise keep their file actions.

## Existing Android boundary

`AndroidManifest.xml` already declares the non-exported
`androidx.core.content.FileProvider` at `${applicationId}.fileprovider`, with
`grantUriPermissions="true"`. It is unchanged. `res/xml/file_paths.xml` now has
exactly these three roots:

| Root | Reachable directory | Purpose |
| --- | --- | --- |
| `updates` (existing) | `filesDir/updates/` | APK installation |
| `works` (new) | `filesDir/works/` | Readable EPUBs |
| `originals` (new) | `filesDir/originals/` | Archived source files |

These provider mappings cover contents beneath those roots; they do not make
them public. No database, preferences/datastore, cookies, fonts, whole filesDir,
external storage, or cache root is exposed. Conversion records reside in the
originals root but the new builder never returns an address for one.

`WorkFileStore` stores EPUBs in `filesDir/works/` and originals (including
conversion record sidecars) in `filesDir/originals/`; `originalFile` excludes
the conversion record. `ReaderWorkActions.fileAddress` accepts a work, never a
path. It selects only `workEpubPath(work.id)` or `originalFile(work.id)`, requires
a regular existing file without following file symlinks, and compares canonical
paths against the exact root and selected filename. Symlinked roots, outside
paths (including traversal), another work's file substituted via a symlink,
sidecars, invalid IDs, missing files, and deleted works yield null. EPUBs also
require `hasEpub`. FilesDir itself may have a platform-provided canonical alias;
the comparison anchors at its canonical path.

## Implemented behavior

- `ReaderWorkActions.shareIntent` keeps the existing title + URL text format
  for links. `readerShareUrl` supplies stored AO3 ID, then source-derived AO3 ID,
  then an HTTP-prefix source scheme, exactly as the iOS reader does. With no
  link it supplies an existing readable EPUB as `ACTION_SEND`, correct MIME,
  `EXTRA_STREAM`, one URI in ClipData, and only `FLAG_GRANT_READ_URI_PERMISSION`.
  `share` wraps it in the system “Share Work” chooser.
- `originalIntent` supplies `ACTION_VIEW`, the same address builder, MIME,
  ClipData and read-only grant. Neither path uses a prefix, write, persistable,
  or package-wide grant. The system grants access for that one URI to the
  receiving app; there is no call to `grantUriPermission` or file copy.
- The FileProvider display-name overload supplies the work title plus the
  actual file extension, including for unusual Unicode/punctuation names.
  EPUB MIME is `application/epub+zip`; originals use Android's extension MIME
  map, with `application/octet-stream` for unknown extensions.
- `ReaderScreen` inserts Original after conditional Kudos and before Read Aloud.
  `readerOriginalAction` uses Material `FindInPage` and iOS's exact accessibility
  label. Original requires an archived file, not a conversion record or a stale
  converter version. Existing button-count pill sizing is retained.
- `ActivityNotFoundException` for Original yields exactly
  “No app on this device can open this file.” through the reader's existing
  `writeMessage` Snackbar: OK dismisses it, and its existing 3.5-second timer
  clears it. A disappeared file gets a plain missing-file message. No viewer
  launches during the tests.
- `WorkDetailScreen.kt` is unchanged.

## Verification outstanding

`ReaderWorkActionsTest` covers the real declared provider and address builder:
both allowed folders; excluded database/datastore/cookie/cache/outside/sibling
paths; existing APK root; missing files; invalid/traversal IDs; file and directory
symlinks; another work's file; sidecar-only originals; unusual display names and
actual extensions; MIME types; all link/file preferences; Original without a
record; Mature/Explicit/finished/history-hidden/deleted cases; chooser and VIEW
intents using a recording launcher; exact grant flags, stream and ClipData; and
missing-viewer/missing-file behavior. The recording-launcher test also checks
that private/cache directory contents do not change after either handoff.
An own-process provider read verifies the
mapping only, not cross-app permission enforcement.

`WorkDetailShareTest` renders the actual work page and its overflow menu with a
linkless import that has both an EPUB and an original. It checks that Share,
Original viewer, and Open on AO3 remain absent. Injected network clients fail on
any request; no real network or activity launch is involved.

The existing `ReaderFanMenuTest` link-preference test and
`ReaderFanMenuUiTest` link-share regression remain applicable. The old test name
that described missing file sharing was corrected.

**Not run:** Gradle compilation, these new and existing tests, and the Android
gate. Claude must run them; API/symbol inspection and `git diff --check` are not
a build or test pass. The cached AndroidX FileProvider artifact was inspected
to confirm its four-argument display-name overload; real source was read for
every repository/model/UI entry point used. No iOS verification is needed for
this Android-only diff.

Suggested focused run from `android/` (for Claude, not run here):

```sh
./gradlew :app:testDebugUnitTest --tests '*ReaderWorkActionsTest' \
  --tests '*WorkDetailShareTest' --tests '*ReaderFanMenuTest' --tests '*ReaderFanMenuUiTest'
```

Then run the normal Android build/test gate before committing. There are 12 new
`ReaderWorkActionsTest` cases and one new work-page UI case; their coverage claims
remain unverified until that run.

Device checks will still be required: another app can read a granted content URI;
the share sheet presents the EPUB with its title and real extension; a viewer
opens the original with the correct MIME type; and the missing-viewer message
is visible. UI placement, round-row width on a small screen, Snackbar timing,
and the selected recipient's read-only URI grant also need device verification.
