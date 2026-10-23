# I12 result (iOS): titles and A84a follow-ups

Implemented in `/Users/cidy02/kudos-agent-ios`, on `claude/agent-ios-i12`, based on
`72c0d603`. Changes remain uncommitted for Claude's build/test and screenshot pass.

## 1. Long sheet titles

Chose **short navigation titles plus the full action/subject heading in scrolling
content**, rather than putting another long string in the navigation bar's fixed
height. The headings use unlimited lines, natural Dynamic Type and vertical
`fixedSize`, so the device/queue/collection name has space to wrap and scroll.
This follows the short action titles of the existing destination pickers
(`kudos-ao3-reader/Features/Library/ReadingQueues.swift:555`, "Add to Queue", and
`kudos-ao3-reader/Features/Library/Collections.swift:693`, "Add to Collection").

- `kudos-ao3-reader/Settings/PairingSheet.swift:229`: the Form starts with the
  complete `Revoke <device name>` heading; the empty-name fallback remains
  `Revoke This Device`. At `:248`, the bar says **Revoke Device**.
- `kudos-ao3-reader/Features/Library/AddLibraryWorksSheet.swift:71`: the List starts
  with the complete `Add to <destination name>` heading, including when no works
  are eligible or the search has no matches. At `:112`, the bar says **Add Works**.
  The common List lets the heading scroll in every state; search is now attached
  to that List, including its empty states.
- `kudos-ao3-reader/UIComponents/SubjectScreen.swift:149`: added an opt-in
  `accessibilityHidden` argument to `wrappingInlineTitle`. These two callers hide
  the short principal item from VoiceOver and clear the underlying iOS navigation
  title (`:154`, `:165`); the full content heading is the one accessible heading.
  The existing bookmark/availability callers keep their behavior. All navigation
  bar APIs remain inside `#if os(iOS)`; no `navigationSubtitle` API was needed.

**Still manual:** default and largest Dynamic Type screenshots with long names,
Light/Dark/Sepia, scrolling, and VoiceOver confirming one complete title
announcement. This is a source-level fix, not a claim of visual verification.

## 2. Pronunciation storage errors

- `kudos-ao3-reader/Features/ReaderReadium/KokoroPronunciationStore.swift:69`:
  `loadForEditing()` distinguishes a genuinely absent file (empty initial store)
  from read/decode failures (throws). It retains migration from the old location
  when the current file is absent and propagates a migration-write failure.
  The existing forgiving playback/backup read API at `:50` is unchanged.
- The same file, `:94`: `updateGlobal` applies paste, rename and multi-delete with
  one checked read and one atomic save, retaining unrelated corrections and the
  fandom/work layers. Failed reads cannot turn into destructive empty-store edits.
  Existing `setOverride`/`removeOverride` also use checked reads (`:124`, `:136`).
- `kudos-ao3-reader/Features/ReaderReadium/ReaderPronunciationSettingsView.swift:169`:
  reuses the sheet's native OK alert, with an error title for storage failures.
  `reload` at `:190` keeps the previously displayed list and reports **"Could not
  read corrections. Your saved file has been kept."**
- Paste at `:246` reports **"Could not save corrections. Try again."** on failure;
  it no longer announces an Added result after a failed write. Successful imports
  retain last-duplicate-wins parsing and the existing success count.
- Delete at `:358` reports **"Could not delete correction. Try again."** and keeps
  the list on failure. A multi-delete is a single write.
- Editor save at `:225` uses the same atomic update for renames, avoiding a saved
  new key followed by a silently failed old-key deletion. Failed saves still
  return false to T-436's editor alert and preserve the editor's input.
- Guessed-word cleanup at `:292` also catches write failures and reports **"Could
  not clear guessed words. Try again."** The guessed-word cache's existing
  forgiving read API remains unchanged; it is derived data, not saved corrections.

**Still manual:** inject correction read/decode/write failures in the app, then
exercise load, paste, swipe delete and rename; confirm alerts, retained rows/input,
retry, and the success wording. Test guessed-word cleanup failure as well.

## 3. Add counts only eligible selections

`kudos-ao3-reader/Features/Library/AddLibraryWorksSheet.swift:66` derives `chosen`
from eligibility and the selected IDs, through `selectedWorks` at `:173`. The
button's count, disabled state and `onAdd` payload all use that same array
(`:118`, `:122`). Concealed selections and stale candidate IDs cannot inflate the
count or keep Add enabled. Search alone still does not discard selected works;
selection order follows the eligible Library list, as before.

**Still manual:** reveal mature content, select tame and mature works, hide it
again, and confirm count/payload exclude mature works; an all-hidden selection
must disable Add. Exercise both queues and collections.

## 4. Empty comments chapter index

- `kudos-ao3-reader/Features/Comments/CommentsModel.swift:127`: added
  `chaptersLoaded`, set on both cached and fetched success (`:924`, `:940`),
  including an empty array. It resets on session transition (`:268`). The early
  return at `:916` treats an empty success as completed. Errors remain errors and
  can retry; existing request/session fences are retained.
- `kudos-ao3-reader/Features/Comments/CommentsView.swift:1029`: loading/error/empty
  presentation is a List row rather than an overlay covering All Comments. A
  successful empty index says **"No chapters available."** (`:1040`); only a
  pending result spins. All Comments remains usable, matching Android's available
  all-comments action. No new AO3 reads, retries, or parser changes were added.
- `kudos-ao3-reader/Features/Comments/CommentsModel.swift:1228`: moved the unchanged
  `knownTotalPages` helper to a same-file extension to keep the main class below
  SwiftLint's existing 900-line error threshold.

**Still manual:** fixture/mock empty index, pending index, failed index and normal
chapter selection; check the compact sheet's layout at large text. No AO3 contact
was made for this work.

## Regression tests added (not run)

The outcomes below are **source-derived expectations**, not executed mutation
results. A full production revert while retaining these tests removes the new
`loadForEditing`/`updateGlobal`, `selectedWorks`, or `chaptersLoaded` APIs, so the
corresponding tests no longer compile. Narrow behavior reversions that keep the
APIs have these expected effects:

| Test location | What it checks | Expected effect of reverting its behavior |
|---|---|---|
| `KudosTests/KokoroPronunciationStoreTests.swift:27`, `aMissingEditingFileIsAnEmptyStore` | First-use missing file is a valid empty store. | Making missing files throw fails the test; this compatibility case does not by itself catch swallowed corrupt-file errors. |
| `KudosTests/KokoroPronunciationStoreTests.swift:31`, `anUnreadableEditingFileThrows` | A directory at the file path is a read error, not an empty store. | Restoring forgiving reads fails the throws expectation. |
| `KudosTests/KokoroPronunciationStoreTests.swift:40`, `failedReadsDoNotOverwriteTheSavedFile` | Malformed saved bytes survive failed load, paste/add, delete, and the existing single-entry mutation APIs. | Using forgiving reads permits mutation and changes the original bytes, failing the throws/byte-preservation checks. |
| `KudosTests/KokoroPronunciationStoreTests.swift:56`, `batchEditsPreserveUnrelatedCorrectionsAndLayers` | A rename/paste and multi-delete retain untouched globals and fandom/work layers. | Dropping removals, replacing the whole file/global layer, or dropping layer preservation fails the content checks. This does not simulate a mid-write filesystem failure. |
| `KudosTests/CollectionWorkPickerTests.swift:64`, `hidingSelectedMatureWorksCountsOnlyWhatWillBeAdded` | Three selections become two eligible additions after hiding mature content; stale IDs are ignored, order is retained, and an all-concealed selection is empty. | Counting/returning raw selected IDs instead of the eligible intersection fails the count/payload checks. Reverting only the button's wiring to `selection.count` requires the manual UI check above. |
| `KudosTests/CommentsAccountTransitionTests.swift:478`, `anEmptyChapterIndexFinishesLoadingAndIsCached` | Empty fetched and cached success both finish loading, without another request. | Omitting either success flag assignment fails the loaded checks. Reverting only the View's spinner branch requires the manual UI check above. |
| `KudosTests/CommentsAccountTransitionTests.swift:514`, `aChapterFailureCanRetryToAnEmptyResult` | Failure stays unloaded; a retry to empty becomes loaded and clears the failure. | Marking failures loaded blocks the retry; omitting the empty success flag or failure clearing fails the state checks. |

Also extended `KudosTests/CommentsAccountTransitionTests.swift:113`,
`chapterStateAndCacheAreIsolatedAcrossAccounts`, with unloaded/loaded assertions
at the account transition. These retain its existing suspended stale-completion
check. New chapter tests live in a same-file extension to avoid a new type-length
lint warning; they remain in the existing serialized suite.

## Verification and handoff

- `git diff --check`: passed.
- SwiftLint ran on all ten changed Swift source/test files with the unchanged
  `.swiftlint.yml`: **8 warnings / 0 errors before and after**, with the same rule
  counts. Captures: `/tmp/kudos-i12-lint-before.json` and
  `/tmp/kudos-i12-lint-after.json`. No new suppressions or config edits.
- No xcodebuild, compiler, test suite, simulator, sign-in, AO3 request, commit,
  push, branch switch, or TASKS.md edit. Existing untracked `Packages`, `Vendor`
  and other brief files were left alone. No project-file changes.
- `READIUM_MIGRATION_NOTES.md` is absent here; requested its location while
  continuing these local UI/storage changes. No reader migration APIs changed.
- **Claude next:** build iOS and macOS, run the three changed suites (and the
  usual required gates), then perform the title/VoiceOver and failure-state UI
  checks above. This patch is ready for that verification, not merge approval.
