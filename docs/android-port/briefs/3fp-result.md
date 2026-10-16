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

## Part 2

Status: IN PROGRESS. Continuing at F11 on `android/agent-codex-3fp2`, starting
from clean HEAD `0eba1d83df9baa2e69bebc609d098291b3743ca0`. F01–F10/F26 are
already landed. F21/F22 remain excluded. No commit, push, branch switch, sign-in,
AO3 contact, Gradle execution, TASKS.md edit, Room schema or backup-format change.
Builds/tests remain assigned to Claude by the brief. Findings, changes and
verification will be appended here as work proceeds.

### Source changes so far (unbuilt)

- **F11/F12:** QueuePageScreen and CollectionDetailScreen reuse LibraryWorkMenu;
  queue ledger rows also reuse Library leading swipes. Scoped removal asks and
  removes membership only. New ScopedWorkActions hosts the existing deletion,
  rebuild, download and membership operations. Comments/importer are passed from
  AppNavHost through ReadingQueueBrowserScreen. Blurred/selection/reorder rows
  do not expose a work menu.
- **F13:** Library refresh receives the actual section list (including quick
  filters), or dashboard shelf items; WorkMetadataRefresh deduplicates and refreshes
  sequentially with cancellation. Queue-count refresh remains. Remote Work Detail
  refresh now fetches metadata without creating a local work.
- **F14:** Library dashboard New Collection now mounts CollectionEditorSheet,
  including description, colour and both behaviour switches.
- **F15:** Library single/bulk, Home single/bulk and Search bulk queue pickers use
  WorkDetailQueueForm through QueueMembershipDialog. Full-selection checks toggle
  memberships, allow queue creation and explicit series addition via the existing
  sequential preservation service. Work Detail's additive-only rule is retained.
- **F16:** AddSelectionToCollectionDialog now shows full-selection membership
  checks and toggles without closing; creates a collection in place. Library bulk
  uses it too; scoped selection keeps the picker open after each toggle.
- **F17:** ScopedSelectionBar offers Remove from Saved for Later when every
  selected work is a member, otherwise Save for Later.

These are implementation notes, not compilation or runtime claims. Further source
review and regression coverage are still in progress.

### Remaining findings implemented in source (unbuilt)

- **F18:** Library sections can choose Detailed/Ledger and expand/collapse all
  detailed cards. Queue adds Detailed beside Compact/Ledger, using SensitiveWorkRow
  and its existing expansion state. Collection adds the same expansion command.
- **F19:** My copy tag names request the existing Library user-tag filter; the
  minus remains removal. Failed/missing queue preservation gets Retry, using
  WorkImporter.preserveQueuedWork and surfacing its failure.
- **F20:** Work Detail lists other active local works with the same series title,
  ordered by series position. Hide mode excludes mature works; blur mode presents
  a reveal action before a work title/link. Uses local observation only.
- **F23/F24:** Highlight applies immediately using the last chosen colour (a local
  preference); the same exact locator/colour repeat deletes via the signed
  tombstone path, a different colour retains identity/note. Annotation deletion is
  immediate from Contents and the editor. Existing initial-note behavior remains.
- **F25:** History/Favorites swipe says Remove from Saved for Later.
- **F27:** Edit tag's Remove row opens the manager's existing scoped confirmation.
- **F28:** Existing Collection Details fields save as changed; admitted local writes
  serialize and survive dismissal. Done/Back flush before closing. New collection
  remains Create/Cancel. Keep downloads still enqueues only on the off→on transition.
- **F29:** Both reader voice-pack entry points ask before enqueueing. Display sheet
  shows Cancel during queued/running work, reports failure and offers Retry Download.
  Cancellation checks were added to download/extraction loops; no pack was downloaded.
- **F30:** Queue organizer selection adds Select All/Deselect All over visible queues.
- **F31:** Detailed saved/remote card bylines reuse the existing byline component,
  enabled only by AO3AuthorIdentities; picker bylines dismiss before native navigation.
- **F32:** Expanded tag groups render every clickable tag, removing the 16-tag cap.
- **F33:** Dashboard uses FilterButton's existing long-press clear; section lists
  pass their clear callback too. Queue already had it at starting HEAD.

Source review caught two additional integration hazards: scoped Saved for Later
checks now query that specific system queue (isQueuedForLater means *any* queue),
and refresh merges onto the latest local row after the request, retaining edits
and deletions that happened while it waited. A visible-page refresh stops after a
non-404 failure rather than trying the rest of the page through a block/outage.
