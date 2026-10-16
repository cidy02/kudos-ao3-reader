# 3fp — A62 action parity follow-up

Status: HANDOFF, stopped after F10. Source changes and regression tests are written;
**nothing has been built or tested with Gradle**. The remaining findings start at F11.
Codex worked on `android/agent-codex-3fp`, starting and ending at
`ed75fc79acaad1afc767ce55d216f24bcb984a20`; the initial tree was clean.

## Scope and constraints

Followed `3fp-a62-actions.md` in priority order through F10. Android source was compared
with the read-only iOS worktree `/Users/cidy02/kudos-ios-polish/`. F01/F02/F03/F26 were
left as supplied; F21/F22 were explicitly excluded. No TASKS.md edit (the brief's
explicit exception to the general task-claim rule), Room schema or backup-format
change, commit, push, branch switch, sign-in, AO3 request, Gradle execution, stub,
helper script, or `.orig` file. All changes remain uncommitted for Claude.

## Changes and findings

Android paths below are relative to `android/app/src/main/java/io/github/cidy02/kudos/`.
iOS paths are relative to the reference worktree's `kudos-ao3-reader/`.

| Finding | Confirmation and source change | iOS reference |
|---|---|---|
| F04 | `library/LibraryScreen.kt`: bulk Delete always asks; the queue-only Remove swipe now has its own unconditional confirmation. `library/CollectionDetailScreen.kt`: bulk Remove always asks. `settings/QueueStorageScreen.kt`: Remove always asks. Also corrected Library's confirmed queue-only swipe to call new `ReadingQueueRepository.removeFromAllQueues`, which removes memberships and retains the work/EPUB, rather than soft-deleting it. Queue Storage retains its explicitly destructive removal path. | `UIComponents/WorkBulkActionBar.swift` and `ScopedRemovalBulkActionBar.swift` confirmation dialogs; `Features/Library/ReadingQueues.swift` Queue Storage dialog; `LibraryWorkSwipeActions.swift` removal confirmation and nondeleting `removeFromAllQueues`. |
| F05 | New shared `works/RebuildOriginalDialog.kt` is used by Library, Work Detail, My copy, and Home's existing rebuild entry. Asks first, blocks repeated taps while running, performs conversion off the UI thread, and displays importer failures/exceptions. `WorkImporter.rebuildFromOriginal` reads the latest local record after conversion, so an old confirmation snapshot cannot overwrite newer progress/flags. | `Features/Library/WorkCardActions.swift` rebuild confirmation/error; `Features/WorkDetail/WorkProvenanceSections.swift` rebuild confirmation/error. |
| F06 | `WorkImporter.prepareForReading` reuses a real local file or downloads a reading copy without forcing a keep; remote listing metadata is localized without a preliminary enrichment request. Existing keeps, identity and Readium locator survive; a deleted readable copy is revived through `resolveLocalWork`. A restored file resets Finished and paired fallback coordinates/legacy percent and records queue preservation, as iOS does. `WorkDetailScreen` awaits preparation, opens the reader on success and displays failures. Download remains the separate kept-copy action. | `Features/WorkDetail/WorkDetailView.swift` `read`/`withLocalWork`; `Features/Library/WorkCardActions.swift` `WorkReaderPreparation`. |
| F07 | `app/Routes.kt` `openReaderFromWorkDetail`, called only by Work Detail in `AppNavHost`: pop back to an immediately underlying reader for the same work. A different work still opens its own reader. | `Features/WorkDetail/WorkDetailView.swift` `read`'s `openedFromReader` handling. |
| F08 | `WorkDetailScreen` now has separate Chapter comments and Write a comment handlers. `AppNavHost` uses the existing chapter-aware route with chapter position 1, and the existing composer route, respectively. All comments is unchanged. | `Features/WorkDetail/WorkDetailSections.swift` three Comments actions; `Features/Comments/CommentsModel.swift` `loadInitialChapterScope` chooses the first chapter. |
| F09 | `ReaderScreen` supplies Contents' chapter Bookmark/Add Note handlers. Shared `ReadiumTocAdapter.chapterStartLocator` matches the first position by href, including when earlier resources have no positions. Actions and start percentages use the same position data and wait until ready. Add Note closes Contents then creates/reuses the bookmark and opens the existing autosaving editor. The editor accepts that bookmark's colour changes; ordinary bookmark taps still only navigate. | `Features/ReaderReadium/ReaderContentsSheet.swift` readiness and chapter actions; `ReadiumReaderView.swift` `readerSheet`, `chapterStartLocator`, `goToAnnotation`; `ReaderNoteEditor.swift`. |
| F10 | Queue and collection now use the existing `LibraryFilterPanel`, replacing their limited dialogs. Shared `LibraryQuery.applyScoped` applies the existing predicates using actual tag/collection memberships from `observeLibraryIndex`. Default preserves reading order; explicit sorts change presentation only. Reorder requires clear filters/sort; clearing and no-match states reset the complete filter state. | `Features/Library/ReadingQueueBrowser.swift` and `Collections.swift` filter-panel presentation. |

Two limits remain within this prefix:

- **F05:** Android has no converter-version stamp. Every rebuild conservatively asks,
  including a possibly stale import that iOS would rebuild immediately. No stamp/schema
  was added. Failures and the up-to-date-work confirmation are covered.
- **F08:** Android's existing chapter-aware Comments lifecycle first starts an All
  comments load, then resolves the requested chapter. The destination now selects the
  first chapter as requested, but iOS resolves its initial chapter before loading
  comments. No Comments repository/ViewModel lifecycle refactor was attempted here.

## Regression coverage written, not executed

Paths below are under `android/app/src/test/java/io/github/cidy02/kudos/`.

- `library/LibraryHistoryScreenTest.kt`: actual Library bulk Delete still asks when
  single-work delete confirmation is off; cancelling retains the work.
- `library/ReadingQueueRepositoryTest.kt`: Library removal from two queues retains the
  readable work and locator and emits no saved-work deletion tombstone.
- `works/WorkDetailShareTest.kt`: shared rebuild dialog asks before running and displays
  the importer's missing-original error without reporting success.
- New `works/WorkReadingCopyTest.kt`: remote Read remains unkept; a repeated Read reuses
  the same file/record; missing-file restoration keeps identity/keep/Readium locator and
  resets fallback coordinates; an existing deleted copy revives without downloading;
  refusal retains local data; rebuilding from a stale snapshot retains current flags
  and progress. All network dependencies are fakes; no real client request is needed.
- `app/RoutesNavigationTest.kt`: same reader returns to the original back-stack entry;
  another work gets a distinct reader; chapter route and composer remain distinct.
- `reader/readium/ReadiumTocAdapterTest.kt`: chapter anchor lookup handles a missing
  resource position group and a fragment, and refuses an absent resource.
- `reader/AnnotationTombstoneTest.kt`: chapter bookmark keeps its kind/identity while
  its note and colour are edited through the shared repository operations.
- `library/LibraryFiltersTest.kt`: scoped default order, explicit Title sort, combined
  real tag/collection membership, and downloaded-state filtering.

## Verification performed

- Initial and final branch/HEAD checked; no git history/ref mutations.
- Reviewed changed call sites, nullable locator serialization, shared dialog use,
  preservation/keep semantics, and default reading-order behavior against source.
- `git diff --check` passed after the final implementation edits.
- Changed-file inventory contains only Android production/tests and this report;
  TASKS.md, schema/entities, backup formats, Apple code and project files are untouched.
- **Not run:** Gradle, unit/UI tests, Android builds, emulator/device or screenshot
  verification, live network checks. The dispatch assigns builds/tests to Claude.
  No claim of compilation, runtime correctness or visual approval is made.

## Stop point and next work

Stopped after F10 to hand off this bounded, unbuilt batch. No later finding was
judged unimportant or dismissed as not worth fixing. **Still unaddressed:**
F11–F20, F23–F25, and F27–F33. F21/F22 remain excluded, and F26 was already fixed.
F11/F12's limited queue/collection menus are still present in `QueuePageScreen` and
`CollectionDetailScreen`; start there and reuse existing menu/picker components.
At HEAD, QueuePageScreen already passes its clear-filter callback to `FilterButton`
(part of F33), but the Library dashboard/section portions of F33 remain.

Claude's next step: build and run the regression classes listed above, then tap through
F04 with confirmations off; all four rebuild entries (Cancel, success, failure); Read
without a file and Continue Reading over an existing reader; all three Comments rows;
Contents chapter Bookmark/Add Note (Back/Cancel/Done/reopen); full queue/collection
filters, clear, explicit sorts and no-op Reorder. Human screenshots remain necessary
for visual approval. Then resume the brief at F11, retaining the F05/F08 limits above.
