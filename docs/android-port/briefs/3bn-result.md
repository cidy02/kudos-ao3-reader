# 3bn result — iOS rules read first

## iOS reference (read-only, `/Users/cidy02/kudos-ios-polish/`)

References below are to `kudos-ao3-reader/` in that worktree.

- `Features/WorkDetail/WorkDetailView.swift:836–872,926–972`: Save for Later first adds/preserves the anchor; only an anchor with a nonempty series URL offers series preservation. No prompt on opening detail, downloading a work, removing Saved for Later, or adding an ordinary queue membership. It shows “Checking series size…” and reads only the first series page (`Services/AO3Client.swift:1308–1320`). Invalid URL or failed preview still offers the warning prompt; it does not pretend the count is zero. Enabled auto-preserve + complete first page + count ≤ saved threshold starts preservation without a sheet. Otherwise “Saved for Later.” and the sheet. Off defaults to false; threshold defaults to 5 and Settings allows 2…25 (`Settings/SettingsStoragePages.swift:88–91,116–125`).
- `Services/ReadingQueueService.swift:42–93`: complete preview is reused; incomplete preview is not reused for the later full crawl. Prompt words are “This series has N work(s). Download every work in the series?”, or “This series has at least N work(s) and more may be on other pages. Download every work in the series?”, or “Kudos couldn't check how many works are in this series. Continuing may download many works. Kudos adds them one at a time.” Switch: “Always auto-preserve series under N works” (inclusive ≤ despite “under”).
- `Features/WorkDetail/WorkDetailView.swift:1183–1232`: title “Preserve Series?”; message, then “Kudos saves the series one work at a time, with the usual pause between visits to AO3.”; switch, then “Kudos saves a series automatically only when the first AO3 page shows the full series and it has N works or fewer.”; “Preserve Entire Series”; “Only This Work”. Only This Work dismisses and keeps the saved anchor.
- `Services/ReadingQueueService.swift:563–734`: explicit full preservation gets series pages in order until complete/empty, then processes summaries in that order. Targets default to Saved for Later; queue sheet targets selected queues. Existing deleted records revive; unavailable records are counted without downloading. Preserved works gain missing memberships without downloading, count already-preserved; Unpreserved works with empty targets count skipped (the earlier already-preserved branch still wins). New works are queue-only, existing Library flags survive. Membership is saved before awaiting the EPUB. Each attempted work finishes before the next, sleeping 2 seconds after an attempted preservation while work remains; local skips do not sleep. Failures count and continue; 404 counts unavailable; no failure removes a record, membership or EPUB. Cancellation leaves completed work and memberships alone, counts the unprocessed rest and stops. iOS has no explicit restricted-summary skip in this loop; refusal prevention follows the owner's standing rule on Android.
- `Features/WorkDetail/WorkDetailView.swift:345–356,980–1041`: starts “Preserving series…”, progress “Preserving series X of N…” with determinate bar, “Cancel Series Preservation”; tap gives “Cancelling series preservation…”. Completion: “Series preservation cancelled. Preserved N work(s).”; zero total “No other series works were found.”; no fragments “Series works are already preserved for later.”; otherwise “Series preservation complete: ” + comma-separated nonzero fragments + period. Fragment order preserved, already preserved, unavailable, failed, skipped (`ReadingQueueService.swift:30–38`). A failed series-list read has total zero, so Swift shows the zero-total sentence even with failed=1.
- `Features/Library/ReadingQueues.swift:448–553,605–687`: iOS DOES retain series in Add to Queue, after New queue and Queues. Header “Queues”; footer “A queue with Keep works offline turned on keeps its works downloaded for you.” Series header “Series”, switch “Also add works from this AO3 series”, first-page preview on enabling, queue preview threshold fixed at 5, then “Add Series to Selected Queues” (disabled while running/no selected queue). It reuses a complete preview. “Cancel Series Addition” cancels its task. Progress “Adding X of N series works…”. Completion: “Stopped adding the series. N work was added.” / “N works were added.”; zero “No series works were found.”; otherwise fragments using “added”, period, or “Series works are already in the selected queues.” Footer “Kudos adds series works only after you choose Add Series, one work at a time.” Toolbar “Done”. iOS queue toggles can remove memberships and discards unattached records on exit; these destructive portions are excluded by this brief.
- `Features/WorkDetail/AO3WorkActionsModel.swift:130–162,190–257`: composer uses existing advisory bookmark input on edit, else blank notes/tags, Private false, Recommend false. Title “Bookmark on AO3” / “Edit Bookmark on AO3”. Notes header, unlabeled text editor minimum 90pt, no placeholder; Tags header, “Comma-separated tags” placeholder, footer “Separate your bookmark tags with commas.”; Private, Recommend; inline AO3 error; Cancel and Save toolbar. No collection or pseud picker, no local character-count validation. Working disables Notes, Tags, Cancel and interactive dismissal and replaces Save with progress. Swift leaves Private and Recommend editable during submission; Android follows that detail too. Error keeps sheet and typed input; success dismisses, banners result and refreshes advisory states. Android's existing `AO3WriteRepository.createBookmark` remains unchanged: fresh authenticated work GET/token/form; one POST; notes/tags unchanged; private/rec 0/1; existing collection names retained, existing pseud preference resolution, PUT override for edits. `AO3WriteFormParser.writeErrorMessage` already treats `#error li` as refusal.

## Implementation written

| Android path | Change | Swift rule matched |
|---|---|---|
| `works/WorkDetailScreen.kt` | Shared Save for Later helper for menu and My Copy, anchor preservation first, bounded preview, collected setting/threshold, complete-preview reuse, separate series prompt/task/progress/result and Cancel. Ordinary download and queue add do not trigger this prompt. | `WorkDetailView.swift:836–872,926–1041` |
| `library/SeriesPreservation.kt` | Swift's exact prompt, inclusive threshold decision and all preservation/addition result sentences. | `ReadingQueueService.swift:42–93`; `WorkDetailView.swift:1017–1041`; `ReadingQueues.swift:667–680` |
| `library/ReadingQueueRepository.kt` | Shared identity matcher; preserve-status accounting; revival/unavailable/already-held branches; target selection; metadata then membership before awaiting each EPUB; failures counted and retained; cancellable 2-second pause; cancellation also caught during suspending Room operations. Batch membership adds suppress the ordinary background download enqueue. The Detail queue form also awaits its anchor before enabling Add Series, preventing an earlier background download from racing the batch. Ordinary form additions preserve only when that queue keeps works offline (`ReadingQueueService.swift:405–420`). | `ReadingQueueService.swift:563–734` |
| `works/WorkImporter.kt` | Listing-only localization option; await existing EPUB path without a work-page read ahead; attempt stamp before actual attempt; preserved/failed/queued-on-cancel states in existing nullable fields. | `ReadingQueueService.swift:476–528,690–732` |
| `works/detail/WorkDetailForms.kt` | Token-styled grouped form sheets for preservation, bookmark and Add to Queue, own `ProvidePushedShellChrome`, scrollable fields, line heights, adaptive title/control rows, explicit progress colours. Series controls remain in Add to Queue after queue rows; Add works on the new name inline; Done dismisses. Progress/Cancel/result on Detail and queue sheet. | `WorkDetailView.swift:328–356,1183–1232`; `ReadingQueues.swift:448–553`; `AO3WorkActionsModel.swift:190–257` |
| `network/ao3/writes/AO3WriteRepository.kt` | Added one **read-only** combined advisory snapshot for the two labels, guarded before read when signed out. Composer opening uses the snapshot and makes no GET. Failed attempts are not retried by recomposition. `createBookmark` and its parameters/body are untouched. | `AO3WriteActions.swift:342–351`; `AO3WorkActionsModel.swift:41–65,130–162` |
| `works/WorkDetailScreen.kt` bookmark driver | Keep draft and sheet on refusal; inline AO3 reason; dismiss only on success, banner then one advisory refresh. Hidden existing pseud remains carried to the unchanged write; no new collection/pseud UI. | `AO3WorkActionsModel.swift:130–162`; `AO3WriteActions.swift:358–398` |

No work, membership or download deletion was added. Queue-sheet choices add membership and leave an existing membership selected. Existing explicit removal commands elsewhere on Detail were not changed. The model/entity/settings edits outside those paths are **comments only**: no Room property, migration, backup key/default/version or transport mapper changed. Existing downloadedAt/progress/favorite/finished/keep flags survive preservation.

## Local demo routes and taps

Use the existing debug demo (`kudosDemoLibrary=true`); the existing `kudosDemoSignedIn` option is only a local fixture session for bookmark review, not an AO3 login. Neither option was launched here. No credentials or live requests are needed.

Sodium Lights and Unanswered Is Not Unread are reachable through **Library → Reading Now** → Work Detail. Burn my heart, heed my eyes is in **Library → Reading queues → Case fic pile** → Work Detail (local search by exact title is also available). The existing destination is `Routes.workDetail(NavArgCodecs.encodeWorkDetailSource(WorkDetailSource.LocalWork(id)))`; local IDs are generated by the seeder, not hardcoded into a new route.

| Work | Work address | Series address/answer |
|---|---|---|
| Sodium Lights | `/works/999000005` | `/series/999`, existing shared `ao3_demo_series.html`: four works, complete first page, including its existing restricted marker |
| Unanswered Is Not Unread | `/works/995110` | `/series/1000`: original three-work page 1; `/series/1000?page=2`: original three-work page 2, `ao3_demo_series_two_pages_1/2.html` |
| Burn my heart, heed my eyes | `/works/995120` | `/series/1001`: terminal local 404, shared failed answer for native and read-only browser |

- **Prompt / Only This Work:** switch off Settings → Reading queues → Auto-preserve small series. On Sodium Lights, **More actions → Save for Later**. See “Preserve Series?”, then choose **Only This Work**. Only the anchor gains Saved for Later membership; no EPUB batch follows.
- **Preserve Entire Series / Cancel part-way:** with setting off, open Unanswered Is Not Unread, **More actions → Save for Later → Preserve Entire Series**. It re-reads page 1 then page 2 only after that explicit choice, as Swift does for an incomplete preview. Anchor is already held; new Letter works download serially. During the two-second pauses tap **Cancel Series Preservation** after two new works have been preserved. Completed files/memberships remain; later works are not requested. Existing `/downloads/<id>/work.epub` endpoints for these IDs return real locally built EPUB ZIPs.
- **Automatic on/off:** on a fresh demo/library or an anchor not yet in Saved for Later, setting **on**, limit **4 or greater**, Sodium Lights **More actions → Save for Later** auto-preserves from its one-page preview without a sheet. Setting **off** prompts instead. Limit **3** also prompts despite the old fixed five. The two-page series always prompts even with limit 25. Do not use Remove from Later to reset a data-safety test; use a fresh demo instance or the queue sheet for repeated addition trials.
- **Failed preview:** Burn my heart, heed my eyes **More actions → Save for Later** offers the unknown-size warning and retains the anchor. No retry/read ahead occurs automatically.
- **Queue sheet:** **More actions → Add to Queue**, select an existing queue (or enter New queue and Add), enable **Also add works from this AO3 series**, then **Add Series to Selected Queues**. Check “Adding X of N series works…”, **Cancel Series Addition**, the final sentence and the footnote. Selections stay selected; no toggle removes membership.
- **Bookmark:** use the existing local fixture-session option, open Sodium Lights **More actions → Edit Bookmark on AO3** (or the ON AO3 bookmark action). Inspect Notes, Tags/placeholder/footer, Private, Recommend, Cancel and Save. Submit 5,001 notes characters: local POST returns `#error li`, form remains with exact input and “Notes must be less than 5000 characters long.” No real sign-in performed. Signed-out Save shows the existing authentication refusal inline.

`DemoNetworkRoutes.fixtureName(HttpUrl)` selects the same listing answer for every caller; there is no screen-specific response. Existing single-page `/series/999` is reused rather than copied. Seeder upgrades only the three anchors' links on an existing demo; it does not clear reading data. Small-series members without a matching AO3 identity are correctly treated as new queue-only copies rather than deduplicated by title.

## Decided without asking

- Reuse existing form components and existing series page repository; no dependencies, schema or backup changes.
- Keep Add to Queue's series block: Swift, not the older brief wording, decides this.
- Queue selection in this change is additive only; never port iOS removal or discard-on-exit.
- Put the three forms together under existing `works/detail/WorkDetailForms.kt`; reuse SettingsSection, SubjectTextFieldRow, SubjectFormRow, SubjectToggle and SettingsActionRow. ModalBottomSheet supplies a sheet surface, not stock dialog/field/button decoration; title and controls stack at accessibility scale to fit.
- Reuse the existing small-series fixture and three existing library titles. Add two complete original listing HTML files under debug assets for the two-page case; failure uses a terminal address, not a placeholder/stub file. Generate real local EPUBs with existing EpubBuilder. Share fixtures between browser/native readers.
- Place pure setting/copy cases in `library/SeriesPreservationPromptTest.kt`, extend the existing repository suite and write suite, and put form/actual Detail interaction tests beside WorkDetail tests. Compose tests use native graphics, tall windows and patient waits; pacing tests use the real coordinator with a virtual clock.

## Open questions

- iOS's queue preview threshold is a fixed 5; retained there because it does not decide auto-preservation. Work Detail uses the saved threshold.
- No extra metadata reads were introduced for preservation. iOS may run `syncMetadata` after a successful EPUB when refresh is due (`ReadingQueueService.swift:516–517,539–560`). Android uses the listing metadata and keeps existing separate enrichment available. Under the brief's sparing-read rule, I did not add a new per-work batch enrichment path. This is the deliberate remaining difference to review.
- iOS's loop has no restricted-summary guard. Owner's refusal rule wins for a known restricted work without a local EPUB: count skipped and do not read it. A held restricted copy may join queues locally; a final download permission guard covers its file disappearing before preservation. No authenticated bulk read is added.
- Swift allows Private/Recommend to be changed while submitting, although Notes/Tags and dismissal are disabled. Android follows the code. Submitted input is snapshotted at tap time, and a refusal retains the current draft.
- iOS's queue membership-removal and unattached-record discard rules were stopped for this brief's data-safety requirement. No destructive portion was ported.

## Verification

**Executed here:** read real Swift/Kotlin symbols and callers; `git diff --check` (clean); a standard-library HTML check confirmed two pages, three unique work rows each, six total identities and shared pagination addresses; static inspection of request paths, no fan-out/read-ahead, cancellation, input preservation, token colours/line heights and fixture routing. No test runner/build/UI was invoked. No AO3 connection or sign-in, no git commit/push/branch change, no TASKS edit, no helper script or `.orig` file left behind.

**Written, not run:**

- `ReadingQueueRepositorySeriesTest`: 11 cases for awaited/serial EPUBs, virtual 600ms request-start coordinator + 2s per-work pause, already-held/unavailable/restricted copies, selected targets, failure in the middle, Cancel after second work, Cancel during an EPUB, held restricted copies, complete preview reuse, explicit multi-page crawl, failed size read and zero targets/404 safety.
- `SeriesPreservationPromptTest`: 6 cases for off/on, under/at/over threshold, multiple pages/failure, DataStore threshold/toggle round trip rather than a constant, exact prompt/result sentences.
- `WorkDetailSaveForLaterTest`: 7 cases exercising actual Detail → Save for Later: no series, setting off + Only This Work, setting on at/under threshold, over a saved threshold of 3, multi-page and failed preview. Opening alone makes no series read. All answers are local; any EPUB read of the held test works or background enqueue fails the test.
- `WorkDetailFormsTest`: 11 Compose cases: series and bookmark inventory in Light/Dark/Sepia/OLED at 2× scale; exact bookmark fields through existing write plus 5,001-character refusal retaining draft; disabled Notes/Cancel/interactive dismissal while working; queue progress/Cancel/completion/footnote. Text checks use `!didOverflowHeight` and last-line non-ellipsis, not `hasVisualOverflow`.
- `DemoSeriesPreservationTest`: 2 cases with a terminal interceptor that fails any socket attempt, shared native/browser answers, real EPUB bytes and local bookmark validation.
- Existing `AO3WriteRepositoryTest`: 2 added cases for one shared advisory GET/no signed-out read and exact over-length bookmark fields/refusal/no retry. Existing create/update payload cases remain.

**Claude must run:** Android compile and the focused suites above, then the app's required regression checks (existing queue membership/download/import/backup tests should remain green). In particular all coroutine/Room cancellation, Compose modal/IME/layout and live-collected setting claims need execution. Visually review both sheets, queue sheet and status rows in all four themes at default and accessibility font scale; drag/back/scrim during bookmark writes; manual partial Cancel with the two-page demo. No visual correctness is claimed here. The full request body implementation in `createBookmark` is unchanged; the optional advisory read helper is the only production write-repository addition.

## Landing note (Claude, 2026-10-08)

Applied on top of the lane with one conflict (the old inline dialogs in `WorkDetailScreen.kt`,
which this brief removes; taken as written). Gate: 2,022 tests, green on the second run; see
the flaky test below.

Changed on landing:

- A forced unwrap in the series loop (`workDao.getById(saved.id)!!`) is now a fallback to
  the row just saved.
- One new test compared a row with the object `upsert` handed back, which keeps more than
  the stored milliseconds; it compares the stored row before and after.
- **The sheets' text actions were unreadable in Dark.** Cancel, Save, Done, the tick and the
  progress colours used the theme's raw accent (`#990000` on a near-black sheet, a contrast
  of about 1.8 to 1). They now use the scope palette's accent, as the newer screens do. The
  action rows inside the sheets (`SettingsActionRow`: "Preserve Entire Series", "Only This
  Work") still use the raw accent, as every Settings action row does: that is a fault of the
  whole app in Dark and OLED on both platforms, now owner question 19.

**What Android now writes that it did not before:** `epubPreservationStatusRaw` ("preserving",
"preserved", "failed", "queued": all values iOS's enum has) and `preservedAt`, on an explicit
series or queue preservation. Before this brief Android only carried those fields through a
backup. iOS writes the same values at the same moments, and Android's merge already marks a
queued work with a file "preserved", so a backup either way stays consistent.

Seen on `emulator-5556` in airplane mode, Dark: Work Detail → More actions → Edit Bookmark
on AO3 (Notes, Tags with its placeholder and footnote, Private, Recommend, Cancel, Save);
Add to Queue (New queue, the four queues with a tick on the current one, the Series switch;
with the switch on: "This series has 4 works. Download every work in the series?" and Add
Series to Selected Queues, which ended "1 added, 2 already preserved, 1 skipped."); Save for
Later on a work in a four-work series ("Preserve Series?" with the switch, its footnote,
Preserve Entire Series and Only This Work).

Not seen: Cancel part-way through a long series, the two-page series, a failed preview, the
bookmark's refusal, Sepia, Light, OLED and large text for these sheets.

Leads, not from this brief:

- **A flaky test run.** One gate run failed `BackupTrustPhase1Test.importPackageMergeKeepsExistingAnnotationNoteAndInsertsNewId`
  with "uncaught exceptions before the test started": a coroutine from an earlier test in
  the same fork threw after its test ended. It passed on the rerun and had not been seen in
  about fifteen runs before this landing, so the leak is probably in one of this brief's
  new tests. Watch for it.
- The Library's long-press menu says "Remove from Saved for Later" for a work that is in
  another queue and not in Saved for Later (Work Detail, for the same work, offers "Save for
  Later"). Probably the menu reads the "queued" flag and not the membership.
- In the queue sheet, tapping the switch's label does not move the switch (iOS's is the
  same); the switch's node does not report itself checkable to accessibility.
