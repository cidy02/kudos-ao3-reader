# Handoff: `cloud/redesign-finish` (redesign wave 3 and writing editor E1)

| | |
|---|---|
| **Written** | 2026-09-25 by the Claude cloud session (Linux container, no Xcode, no simulator) |
| **Branch** | `cloud/redesign-finish`, pushed. Cut from `review/codex-item12` at `c4ce1e2`. |
| **Covers** | (1) The Mac session's handoff "Redesign handoff: finishing the remaining items" (2026-09-24). (2) The owner's writing-editor request: an architecture document, then Step 1 (E1). |
| **TASKS rows** | T-256 audits, facts and briefs ✅ DONE · T-257 to T-261 five redesign batches 🟡 NEEDS MAC VERIFY · T-262 editor architecture and E1 🟡 NEEDS MAC VERIFY |
| **`origin/review/codex-item12`** | Still `c4ce1e2` when this was written. The Mac's T-246 to T-255 work has never been pushed. |

TASKS.md stays the status of record; this file gathers everything in one place. The
root `handoff.md` is a different, earlier handoff (security and backup trust,
2026-09-21) and was left untouched.

---

## 0. In one screen

- **Done:** everything both requests asked for that a Linux container can do.
  - Five area audits, a skeptic pass, otwarchive facts Q11 to Q23, and five build
    briefs plus a partial C2 brief.
  - Five redesign batches implemented.
  - The writing-editor architecture document, and its Step 1 (E1) implemented.
- **Verified here, partly:** the Foundation-only Swift compiles with Linux Swift 6.4
  under the project's settings. Its tests (116 in 19 suites) ran green there, and the
  branch adds no compiler warnings over its base (§4).
- **Not verified anywhere:** no SwiftUI, UIKit or AppKit code has been compiled, run or
  seen. Every row with Swift in it is 🟡 NEEDS MAC VERIFY, and the owner's screenshot
  gate applies to all UI.
- **Blocked until the Mac pushes `review/codex-item12`:**
  - the C2 brief;
  - the 1f comments re-audit;
  - appending the facts to `otwarchive-facts.json`;
  - merging the two lines.
- **Blocked on the owner:** editor decisions OD1, OD3 and OD6, and the redesign owner
  list (§2.6 F).
- **Next steps:** §6.

---

## 1. Rules this work followed (still binding for whoever continues)

- **AO3:** never contact archiveofourown.org, never sign in, never perform or trigger an
  AO3 write. AO3's own code (otwarchive on GitHub) is the ground truth for markup,
  params and access rules.
- **Branches:**
  - Work only on your own branch.
  - Never commit to `main` or `review/codex-item12`.
  - Never merge, force-push, reset or delete a branch.
- **Git hygiene:** `git add` explicit paths only. Don't touch `project.pbxproj`.
  `DEVELOPMENT_TEAM` stays `""`. The repo is public: no secrets, tokens or personal
  identifiers.
- **Swift written without Xcode is unverified:**
  - its commit subject ends `[unverified: no Xcode]`;
  - its TASKS row is 🟡 NEEDS MAC VERIFY;
  - never write "builds", "passes" or "works" about code that was not compiled.
- **Keep out of:**
  - the T-255 networking core (`Services/AO3Client.swift`,
    `Services/AO3RequestCoordinator.swift`, `RequestCoalescer`);
  - deletion and persistence semantics (`PreservedWorkService`, `WorkLifecycle`, the
    SwiftData models);
  - T-253's files (`Features/Challenges/*`, `Services/AO3Client+Challenges.swift`,
    `Models/AO3ChallengeModels.swift`);
  - `project.pbxproj`.
- **Owner decisions:** list them, never build them. Any new schema field is an owner
  decision.

---

## 2. Part 1: redesign wave 3 (the original handoff)

### 2.1 What the handoff asked

- **3A:** audit the five areas nobody had audited, then run a skeptic pass
  (`critic-wave3.json`).
- **3B:** answer the new gaps' AO3 questions from otwarchive, starting at Q11.
- **3C:** write one build brief per area, plus C2 (collections moderation and
  account-settings collections).
- **3D:** implement the batches, unverified.
- **Section 4:** list the owner decisions.
- **Section 7:** report per-area counts, top bugs, batches and unknowns.

### 2.2 3A: audits and skeptic pass (T-256, ✅ DONE)

The files are in `docs/audits/2026-09-24/`. `CLOUD_WAVE3_README.md` explains how they
were made.

| Area | Boards | Items | DONE | BUG | GAP | DEVIATION | DECIDED | OWNER | Other |
|---|---|---|---|---|---|---|---|---|---|
| home-library | 1b 1ad 1ae 1af 1ag 1c 1d 1e 1ay | 47 | 29 | 5 | 7 | 1 | 3 | 1 | 1 SUPERSEDED |
| search-filters | 1k 1ao–1ax | 31 | 21 | 4 | 4 | 1 | – | 1 | – |
| browse-workdetail-comments | 1g 1al 1am 1an 1a 1az 1f 1ba 1be 1bf | 35 | 20 | 4 | 6 | 3 | 1 | 1 | – |
| account-hub-reading | 1m 1n 1bt 1o 1q 1t 1p 1l 1y | 33 | 17 | 6 | 4 | 2 | 3 | 1 | – |
| account-leftovers | 1z 1ac 1aa 1bb 1x | 11 | 7 | – | 2 | 1 | – | – | 1 NOT_BUILDABLE |
| **Total** | 44 | **157** | 94 | 19 | 23 | 8 | 7 | 4 | 2 |

**The skeptic pass** (`critic-wave3.json`) checked all 157 items and wrote its 17
corrections back into the area files:
- 151 confirmed.
- 3 wrong: 1ad.5, 1a.1 and 1au.2.
- 1 unsure: 1an.2.
- 2 added: 1a.1b and 1au.4.

**Caveats:**
- **Base.** Everything was audited at `c4ce1e2`. The handoff's inputs were not on
  origin: `AUDIT_METHOD.md`, `otwarchive-facts.json` (Q1–Q10), `critic-wave2.json`, the
  wave-2 JSONs and the T-246…T-255 commits. So the method was reconstructed from the
  handoff and `docs/REDESIGN_PLAN.md` §4, as `CLOUD_WAVE3_README.md` records.
- **1f comments** was audited before T-247 rebuilt the threading on the Mac. Its
  threading verdict describes the old code and must be re-audited.

### 2.3 3B: otwarchive facts (✅ DONE)

`docs/audits/2026-09-24/otwarchive-facts-wave3.json` holds Q11 to Q23, from otwarchive
at `00ad85b4`. Each entry has `q`, `answer`, `sources`, `quote` and `implication`.
Nothing was fetched from AO3 itself.

- **Q11:** do the relative "Updated" filter and After/Before combine?
- **Q12:** how is the subscriptions index paged, and does it print a total?
- **Q13:** what does AO3 render past `COMMENT_THREAD_MAX_DEPTH`?
- **Q14:** what order are comment threads paged in?
- **Q15:** what does the 10,000-character comment limit count? (Code points.)
- **Q16:** where do Blocked users and Muted users live?
- **Q17:** does the drafts page print each draft's deletion date?
- **Q18:** what does the dashboard's "Bookmarks (N)" count?
- **Q19:** how does a work come off Marked for Later?
- **Q20:** which HTML tags survive in comments?
- **Q21:** what do the Inbox counts cover, and which filters exist?
- **Q22:** what is the default sort?
- **Q23:** what does `/media` list?

**Left:** append these to the Mac's `otwarchive-facts.json` when the lines meet.

### 2.4 3C: briefs (✅ DONE, except C2)

- **Written:** `brief-home-library.md`, `brief-search-filters.md`,
  `brief-account-hub-reading.md`, `brief-browse-workdetail-comments.md` and
  `brief-account-leftovers.md`. Each lists bugs first, then small gaps (files, spec
  quote, exact change, proving test), then "Needs the owner" and "Later".
- **Partial, not a full brief:** `brief-C2.md`. Its inputs
  (`collections-moderation.json`, `account-settings-collections.json`,
  `critic-wave2.json`) were not on origin, and its files belong to T-240 and T-253. It
  records only what could be checked from source and otwarchive:
  - **C2-1:** the reject sheet promises AO3 emails a reason that AO3 never receives.
  - **C2-2:** `ModeratedItemsView` has no route.
  - **C2-3:** collection delete and icon upload.
  - **C2-4:** stored toggles that have no effect.

### 2.5 3D: batches (🟡 NEEDS MAC VERIFY)

| Batch | Row | Commit(s) | Items |
|---|---|---|---|
| home-library | T-257 | `c7fa926c` | H1–H9 |
| search-filters | T-258 | `89ed3857` | S1–S7 |
| account-hub-reading | T-259 | `d9ef791d` | A1–A7 |
| browse-workdetail-comments | T-260 | `70db11a1` | B1–B8 (not 1f / `CommentThreadRow`) |
| account-leftovers | T-261 | `e8e261ff`, test fix `f19db7fc` | L1, L2 |

Each row in TASKS.md says exactly what changed, what the Mac must build, run and
screenshot, and what was verified here.

**Top bugs fixed in code (unverified):**
- **Library carousels went stale:** the cache key ignored five filter fields (H1).
- **Home Subscriptions:** the header printed page 1's count as the total, and a failed
  load read as "not subscribed" (H2, H3).
- **Card "Ch N" came from an EPUB spine index,** off by the front matter. Cards and Work
  Details now show a Readium percentage, or nothing (H5; this also fixes 1a.4).
- **Search:** "Try Again" after a failed page jumped back to page 1 (S3).
- **Bookmarks:** opening the list replaced AO3's exact count with a smaller one (A1).
- **Subscriptions Refine hid every row not yet enriched,** showing "0 of 25 match" (A5).
- **Marked for Later's footer promised an unmark that doesn't exist** (A3).
- **Jump Back In wasn't ordered by last read,** and didn't refresh after reading (B1).
- **The comment budget counted graphemes where AO3 counts code points** (B2, Q15).

**Where the build departed from its own brief:**
- **H4:** the empty-state copy uses Android's wording, as
  `docs/iOS_Issues_Found_While_Porting.md` asks.
- **H9:** the provenance badge has a VoiceOver label ("From AO3").
- **B8:** the board's "No series yet" is the header subtitle, not a card line. Its
  "in Safari… Posting is not something the app does" is false here, so the footnote
  says "Opens archiveofourown.org in Browse. Series are made there, not in the app."

**Verification here (details in §4):**

| Batch | Compiled on Linux | Tests that ran green on Linux | Not compiled anywhere |
|---|---|---|---|
| T-257 | `LibraryFilters`, `LibrarySectionKind`, `HomeSections`, `WorkReadingPosition`; the pure statics of `WorkCoverCard` and `WorkSelectionTitle` | `WorkReadingPositionTests`, `HomeSubscriptionsTests`, `WorkSelectionTitleTests`, `SavedWorkProgressTests` | the views; `LibraryFiltersTests` and `LibrarySectionKindTests` need SwiftData |
| T-258 | the non-view parts of `AO3FilterPanel`, `SearchView`, `SearchResultsHero` | `SearchPanelRulesTests`, `AO3SummaryFilterRatingTests` | the views, `FilterPanelPresentation`, `NativeBrowseView` |
| T-259 | `AO3SubscriptionsRefine`, `AO3InboxModels`, `AO3AccountListCountsCache`; the non-view parts of the Marked for Later browser and `AO3FilterPanel`; `AccountView`'s row orders | `AO3AccountListCountsTests`, `AO3MarkedForLaterScreenTests`, `AO3InboxParseTests`, `AO3InboxTallyTests`, `AO3SubscriptionsRefineTests`, `AccountHubRowsTests` | `AccountView`, `AccountInboxScreen`, `AO3AccountWorksList`, the browser view |
| T-260 | `WorkDetailFigures`; `MediaBrowserView.jumpBackInFandoms` and its nested structs, `CommentComposerSheet.remainingCharacters`, `FandomListTally` | `BrowseAndWorkDetailRulesTests` | the views, including `rankJumpBackIn` |
| T-261 | `AO3WritingModels` (`AO3DraftsPage`, `DraftExpiry`), `AO3Client+Works` (`parseDraftDeletionDates`), `AO3WorkActions` (`loadDrafts`) | `DraftExpiryTests` | `AO3PreferencesView`, `WritingDraftsView`, `AuthorProfileComponents`, `SubjectStateBadge` |

### 2.6 What is left from the redesign handoff

**A. Mac verification of T-257 to T-261.** Each row lists its builds, tests,
screenshots and manual checks. The general procedure, from the handoff's section 6 and
AGENTS.md:

1. On a fresh clone, run `Scripts/fetch-fluidaudio.sh`.
2. Build for iOS: `xcodebuild -project AO3_App_OpenSource.xcodeproj -scheme
   AO3_App_OpenSource -destination "id=<sim>" build`.
3. Build for macOS with `-destination 'platform=macOS'`. It uses the legacy reader, so
   iOS-only APIs in shared code break it.
4. Run `Scripts/lint.sh`: zero `error:`, and warnings must not exceed the baseline of
   129.
5. Run the targeted suites with `-only-testing:KudosTests/<Suite>`, then the full
   suite, or `Scripts/verify.sh`.
6. Baseline proof: break the fix, watch its test fail, restore it.
7. Take a simulator screenshot, then pass the owner's screenshot gate.

Row-specific things to watch:
- **T-258:** `PresentationDetent` is now a stored property of the shared modifier on
  macOS.
- **T-260:** the `nonisolated` structs nested in `MediaBrowserView`, and the static
  `let` read from its nonisolated pass.
- **T-257:** on macOS, a work read only in the legacy reader now shows no progress
  label instead of the wrong "Ch N".

**B. Blocked until the Mac pushes `review/codex-item12`** (with T-246…T-255 and the
wave-2 files):
- **Finish C2.** Build the brief from the two C2 JSONs plus `critic-wave2.json` (its
  WRONG/UNSURE corrections win), merge in C2-1 to C2-4, and cap it at about 12 items.
  It can only be implemented after T-253 lands.
- **Re-audit 1f** against T-247's threading.
- **Append Q11–Q23** to `otwarchive-facts.json`.
- **Merge the two lines.** Expect conflicts in `TASKS.md` (both sides add rows at the
  top), and likely in `docs/REDESIGN_PLAN.md`, `docs/ARCHITECTURE_MAP.md`, `AccountView.swift` and
  `CommentsView.swift` (T-247 rebuilt comments on the Mac). Row IDs T-256 to T-262 may
  collide with Mac rows created after the handoff was written; renumber the cloud rows
  if they do.

**C. Not built: the briefs' "Later" lists.**
- **1ad.3:** WIP pill with counts (S/M). It adds a new filter dimension.
- **1ay.3:** name the colliding filter pair (M).
- **1b.5 and 1b.4:** queue card "next up" and its copy. Wait for T-252's queue work.
- **1l.2:** Inbox pill rail (M). Q21 shows AO3 has server filters for every pill.
- **1p.4:** Works / Series / Authors scopes on Subscriptions (M).
- **A1's residual:** History, Marked for Later and Subscriptions also drop rows AO3
  counts. This needs parser work in `AO3Client.swift`, so it waits for T-255.
- **1al.4:** "Group variants" switch on the fandom list (M).
- **Comments:** the signed-out action row gap. It is on the owner list.

**D. Carried over unchanged from the handoff's "items already known to remain".**
None of these were touched here.
- **Writing:**
  - 1bo chapters list (M);
  - the Preview screen, never wired (M);
  - 1bu drag-to-reorder chapters (M);
  - the Series row reads "None" for a work already in a series (M).
- **Queues and History:**
  - 1h add-works picker (M);
  - 1i select mode (M), 2×2 peek tile (S/M) and always-live drag (S; reorder stays
    disabled under a filter, T-254 #3);
  - 1bg drag while selecting (M);
  - 1bj select mode (M).
- **Schema fields (owner):** 1ah "Remove from history" and 1h queue description.
- **Challenges, after T-253 lands:**
  - 1bz read-only sign-up detail and per-row request/offer summary;
  - 1ca tag-limit checks;
  - 1cb pinch-hit rows;
  - 1cc fandom kicker;
  - 1cf Basics rows and Matching section;
  - 1by, whose audience is for the owner to decide (Q5).

**E. T-254 (Codex review #2 fixes) is Mac-owned.** It was not implemented here. The
handoff allowed it only if TASKS showed it not started *and* the owner said the Mac
session had stopped. The owner never said so, and this branch's TASKS.md predates the
Mac's rows. Its full spec is in the handoff's
section 5.

**F. Owner decisions (list them, never build them).**

From the handoff's section 4:
- **Comments depth:** built inline to depth 5; the artboard draws depth 0–2 plus
  "Continue thread".
- **Networking policy:** 1bc "since your last visit" needs a per-fandom fetch; 1ab
  notifications need background polling, which the policy forbids.
- **Effects of stored toggles:** queue "Keep offline"; collection "Keep downloads",
  "Show on Home" and colour.
- **Writing:**
  - 1bv formatted chapter editor. The editor document now proposes one (§3, OD1).
  - 1v single sheet vs several.
  - 1bn bulk Delete.
  - 1br series "Remove works".
- **Queues:** 1j glass buttons vs text buttons.
- **Collections moderation:** 1ce reject copy (AO3 sends no reason, Q6);
  `ModeratedItemsView` has no route.
- **Collections:** 1bl collection delete and icon upload. 1bh is excluded as a plan
  contradiction.
- **Comments:** the signed-out comment action row gap.

Added by this wave:
- **1ad.5:** make ledger rows the Reading Now default? They drop the summary, a density
  loss.
- **1au.4:** Search and Refine disagree on "Include Not Rated" under Rating Any. Pick one
  rule.
- **1o.4:** add Unmark to Marked for Later? It is an AO3 write (`PATCH
  /works/:id/mark_as_read`, Q19).
- **1f.5:** T-247's depth-5 inline threading vs AO3's own cutoff rule (Q13).
- **1an.2:** does "I have downloads from" mean kept permanently, or on disk?
- **1x.3:** Post and Delete as swipes on drafts. The code deliberately keeps them in the
  editor.
- **B6:** check that the tinted Kudos chip doesn't read as "you gave kudos" beside a
  tinted "Subscribed".
- **macOS legacy reader:** no progress label now. A real one needs a story-chapter
  index, which is a schema change.

**G. Known limitation of L2.** AO3 prints the deletion date in its own time zone, and
the chip counts whole local days, so near midnight it can be a day generous.

---

## 3. Part 2: the writing editor

### 3.1 What was asked

1. Explain how the draft editor works today. It is custom: a native `UITextView` /
   `NSTextView` raw-HTML buffer with no editor library.
2. As a principal architect, evaluate a dual-mode WYSIWYG + HTML editor for iOS and
   Android: engine choice, keep vs replace the native controller, and toggle state for
   50k-word chapters.
3. Write that up as `docs/WRITING_EDITOR_ARCHITECTURE.md`, including the TASKS row, the
   exact hand-off mechanics, the pre-loading budgets and the schema constraints, as one
   source of truth for both the Apple and Android branches.
4. Then do Step 1: fix the recovery store, move disk I/O and word counts off the main
   thread, and stop copying the whole chapter on every keystroke. Run unattended, and
   commit and push as you go.

### 3.2 The architecture document (T-262, `49cf50cc`, done)

`docs/WRITING_EDITOR_ARCHITECTURE.md` is the plan of record for both platforms.
Keep it byte-identical on the Android branch.

**Decisions:**
- **D1:** the Rich Text canvas is ProseMirror with Kudos's own AO3 schema, in a WebView,
  with native chrome around it. This is proposed and needs OD1.
- **D2:** HTML mode stays native on Apple. On Android it is native only if it passes the
  typing gate, otherwise CodeMirror 6.
- **D3:** the two modes hand the text off and never sync live.
- **D4:** the real text lives natively in a per-field `DraftSession`.
- **D5:** one shared parse5-based `editor-core` JS package.
- **D6:** each mode has its own undo history, and a switch that isn't followed by an
  edit changes nothing.
- **D7:** recovery never needs the WebView.
- **D8:** keystrokes cost O(edit).

**Contents:**
- §2: current state, with the Apple defects E1 fixes.
- §3: AO3 ground truth from otwarchive (cleaning pipeline, allow-list, per-field
  limits, ParagraphMaker, TinyMCE config, word counter).
- §4: rejected alternatives.
- §5: components and invariants I1–I10.
- §6: document schema (tiers, nodes, marks, serializer rules S1–S16, paste rules P1–P9,
  loss report, conformance tests).
- §7: exact hand-off mechanics (state machine, bridge protocol v1, switch sequences,
  caret mapping, freeze and IME, focus, failures, undo).
- §8: checkpoints and recovery (policy, on-disk formats E1/E3/E4, pruning, recovery on
  open, edit log, Save/Post).
- §9: reference devices, the 510,000-character fixture, budgets B1–B12, and the
  pre-warm and preload policy.
- §10: platform bindings; §11: security.
- §12: work plan E1–E5 and the parity checklist; §13: owner decisions.

### 3.3 E1: recovery store and per-keystroke work (`0f79d0f2`, 🟡 NEEDS MAC VERIFY)

**What changed:**
- **`WritingTextController`** (`WritingNativeTextView.swift`): an edit now only bumps a
  revision counter and calls `onEdit`, so a keystroke is O(1). `takeCheckpoint()` reads
  and compares the text at most once per checkpoint. An IME composition is committed
  only on explicit checkpoints, never idle ones.
- **`WritingCheckpoint.swift`** (new):
  - `WritingCheckpointPolicy` fixes the timing at 1.5 s after typing stops, and at
    least every 20 s during continuous typing. The numbers are shared with Android.
  - `WritingCheckpointScheduler` drives the checkpoints with one timer task.
  - `WritingWordCount` is `nonisolated`, and its count runs off the main thread.
- **`WritingTextEditor`:** the form binding, the recovery write and the word count
  change only at checkpoints. Done, leaving the screen, Restore, a scene change and a
  memory warning each checkpoint too. The recovery list loads off the main thread and
  leaves out this session's own file.
- **`WritingRecoveryWriter`** (new actor): writes off the main thread, ordered by
  checkpoint sequence so an older write never replaces a newer one. It hashes the
  original text once per session.
- **`WritingTextRecovery`:** prunes by file date without decoding, and always keeps the
  copy being written. An unreadable copy is skipped rather than hiding every other copy
  and stopping pruning for good.
- **`strippingHTML()`** is now `nonisolated`. `AO3Markup.writing`'s comment no longer
  claims AO3 posts content unparagraphed.
- **`Scripts/make-writing-fixture.py`** writes the deterministic 510,000-character
  budget chapter.
- **Tests:** `KudosTests/WritingCheckpointTests.swift` is new. The controller test in
  `WritingTextEditorTests` now asserts `takeCheckpoint()` rather than per-keystroke
  emission.
- **Docs:** `ARCHITECTURE_MAP.md` and `REGRESSION_TEST_MATRIX.md` are updated.

**Verified here:**
- The Foundation-only E1 files compile on Linux, with no warnings even under complete
  concurrency checking. Their 23 tests ran green.
- Deliberately breaking the sequence guard, the 20 s maximum, the unreadable-copy skip,
  the pruning exclusion or `fireNow` each turned a test red.
- **Not compiled anywhere:** `WritingTextEditor.swift`, `WritingNativeTextView.swift`,
  and the controller test in `WritingTextEditorTests`.

### 3.4 What is left for the editor

**A. E1 acceptance on a Mac and a device** (T-262 lists it):
1. Build iOS and macOS; `Scripts/lint.sh`.
2. Run `WritingCheckpointTests`, `WritingTextEditorTests` and `HTMLTextTests`, then the
   full suite.
3. On an iPhone 11-class device, paste the fixture into "Work text" of an **unsaved**
   new work and check the budgets: B1 (keystroke ≤ 16 ms p95), B3 (≤ 4 ms main thread
   per checkpoint), B5 (recovery write ≤ 50 ms, off the main thread) and B6 (open ≤
   300 ms).
4. Time Profiler must show no `JSONEncoder`, `SHA256`, `strippingHTML` or file I/O on
   the main thread while typing.
5. Force-quit mid-edit: the recovery prompt appears and Restore works.
6. The Privacy screen still counts recovery copies.
7. Pausing mid-composition with the Japanese IME must not commit it.

**B. Port the document** byte-identically to `kudos-ao3-reader-android`. It was not done
here; this session pushes only its own branch.

**C. Owner decisions (§13 of the document):**

| ID | Question | Proposal | Blocks |
|---|---|---|---|
| **OD1** | Run the Rich Text canvas in a WebView? It reverses the 2026-09-12 native-only rule for that canvas only. | Yes, with native chrome | E3, and Android rich mode |
| OD2 | Load remote images inside the editor? | Placeholders; load per chapter on request | E3 |
| **OD3** | Adopt AO3's word-count algorithm? It changes Chinese, Japanese, Thai and hyphenated counts. | Yes | E2 |
| OD4 | Keep recovery copies in device backups? | Keep as today (included) | – |
| OD5 | Android HTML-mode widget | Decided by the §9.2 gate | E5 |
| **OD6** | Spell-check in HTML mode? | Yes, matching AO3's textarea | E1b |

**D. Later steps (each gets its own TASKS row when claimed):**
- **E1b:** spell-check in HTML mode. Waits for OD6; deliberately not built.
- **E2:** the `editor-core` JS package: schema, parse5 pipeline, sanitizer and
  ParagraphMaker ports, serializer, paste cleaner, AO3 word counter, caret maps, loss
  report, golden tests and Node CI. Its word counter needs OD3.
- **E3:** Apple rich mode behind a feature flag. Needs OD1.
- **E4:** the edit log and crash replay, on both platforms.
- **E5:** the Android writing screens. Android has no writing editor today.

**E. Known limits of E1 to watch on device:**
- **The recovery write is asynchronous.** It starts when the scene goes inactive and
  takes milliseconds, with no background-task assertion. If iOS ever suspended the app
  inside that window, the last checkpoint (at most 20 s of typing) could miss the disk.
  If the force-quit check shows it, wrap the write in `beginBackgroundTask`.
- **Reopening a field within milliseconds of Done** can list the previous session's
  older copy as a recovery. It is harmless: "Keep form text" dismisses it.
- **As before E1,** leaving the screen tears the controller down, so returning (for
  example after a tab switch) rebuilds the editor without its undo history.
- **The word count is still the old algorithm.** AO3's is E2, pending OD3.

---

## 4. Verification done in this container

### 4.1 Results

- **Toolchain:** Swift 6.4 (`swift-6.4-RELEASE`) on Ubuntu 24.04.
- **Settings:** the same as the Xcode project:
  - Swift 5 mode and default MainActor isolation;
  - the five approachable-concurrency upcoming features;
  - member import visibility for the app target.
- **E1 alone:** 5 files; 23 tests green; no warnings under
  `-strict-concurrency=complete`. Five deliberate breaks were each caught.
- **Whole branch:** 119 Foundation-only app files built together, with
  `AO3AuthService`'s class stubbed. 116 tests in 19 suites ran green.
- **Warnings against the base:** the merge base `c4ce1e2` was built the same way. Both
  produce the same 222 distinct warnings (by file, message and source line), so the
  branch adds none.
- **A stricter comparison was not possible:** under complete concurrency checking, both
  trees stop at the same error in `Services/CommentSubmission.swift:118`, a file this
  branch doesn't touch.

### 4.2 How to redo it

The harness lived only in the session scratchpad; nothing of it is committed.

1. **Get the toolchain.**
   - `download.swift.org` is denied by this environment's network policy (§5). Docker
     Hub is allowed.
   - Take an anonymous token from `auth.docker.io`, then read the `linux/amd64`
     manifest of `library/swift:6.4.0-noble`.
   - Download its 1.1 GB toolchain layer (`sha256:6e595cf0…`) and check its digest.
   - Extract only its `usr/` tree anywhere and put `usr/bin` on `PATH`.
   - `apt-get install libcurl4-openssl-dev libxml2-dev libz3-dev`.
2. **Write a SwiftPM package** (tools 6.2) whose `Kudos` target copies the app files
   that import only Foundation, SwiftSoup, OSLog, `os` or CryptoKit. Use SwiftSoup
   `exact: "2.13.5"`, as `Package.resolved` pins it.
3. **Adapt the copies, never the repo:**
   - prepend `import FoundationNetworking`, `FoundationXML` and `Observation`;
   - swap `URL.applicationSupportDirectory` for a temporary directory;
   - strip `@Model`, `@Relationship` and `@Attribute` from `Models.swift`;
   - remove `import WebKit` from `AO3AuthService.swift` and replace its class with a
     stub carrying the real signatures;
   - include `MiniZip.swift`.
4. **Stand in the Apple-only APIs with their real signatures:**
   - CryptoKit (a real SHA-256, checked against the standard vectors);
   - an OSLog `Logger` that logs nothing;
   - Compression's `compression_decode_buffer`;
   - `RelativeDateTimeFormatter`, the cookie SameSite API and `AO3CookieBridge`.
5. **Take the pure parts of SwiftUI files.** Keep a file's top-level declarations that
   mention no UI types. A view becomes an empty struct plus its UI-free static members
   and nested types.
6. **Tests:** ship `KudosTests/Fixtures` as package resources, and read them through
   `Bundle.module`.
7. **Exclude what needs PDFKit, UI types or SwiftData:** `ImportedDocumentConverter`,
   `ImportedFileFormat`, `CanonicalWorkMerge`, `WorkConversionRecord`,
   `CommentsErrorMessages` and `FavoriteQuickFilter`, plus `LibraryFiltersTests` and
   `LibrarySectionKindTests`.

### 4.3 What it cannot tell you

- **SwiftUI, UIKit, AppKit and SwiftData code** is never compiled. That includes view
  bodies, modifiers, result builders and `@Query`.
- **Platform behaviour:** the text system, IME, TextKit, WebKit, and Apple's
  Foundation where it differs from Linux's.
- **Lint and runtime:** SwiftLint results, performance budgets, and anything visual.

---

## 5. Environment notes

- **No Xcode, macOS SDK or simulator** in the cloud container.
- **`download.swift.org` is denied** by the environment's network policy: the proxy
  answers 403 to CONNECT. To allow it, open the cloud environment menu in the session's
  title bar, choose Edit, then Network access, and pick a broader level or add the
  host. The levels are described at
  https://code.claude.com/docs/en/claude-code-on-the-web.
- **Docker Hub** worked. One CDN fetch failed with a transient TLS error; a retry
  succeeded.
- **apt** works through `archive.ubuntu.com`. The deadsnakes and ondrej PPAs are
  denied; that is harmless.

---

## 6. Next steps, in order

1. **Mac:** push `review/codex-item12` with T-246…T-255 and the wave-2 files. This
   unblocks C2, the 1f re-audit, the facts merge and the merge itself.
2. **Mac:** verify T-257 to T-262 on this branch (§2.6 A, §3.4 A). Fix, or report, what
   fails, and move rows to ✅ only after the owner's screenshot gate.
3. **Owner:**
   - for the editor, decide OD1, OD3 and OD6;
   - go through the redesign owner list (§2.6 F);
   - check the B6 Kudos tint.
4. **Merge the two lines** (owner's call). Resolve the TASKS.md, REDESIGN_PLAN.md,
   ARCHITECTURE_MAP.md, AccountView.swift and CommentsView.swift conflicts, and renumber
   colliding cloud rows.
5. **Finish C2, re-audit 1f, and append Q11–Q23** to `otwarchive-facts.json`.
6. **Copy `docs/WRITING_EDITOR_ARCHITECTURE.md`** byte-identically to
   `kudos-ao3-reader-android`.
7. **Then continue:** the briefs' "Later" items and the handoff's remaining M items
   (§2.6 C and D), and E1b, E2 and E3 as their decisions land.

---

## 7. Commits on `cloud/redesign-finish` (base `c4ce1e2`)

| Commit | Subject |
|---|---|
| `6dcc19c2` | Audit Home and Library against the spec, and claim the cloud wave |
| `a17f9351` | Audit Search and its filter panel against the spec |
| `a34ff660` | Audit Browse, Work Detail and Comments against the spec |
| `e95c8a52` | Audit the Account hub and its AO3 reading lists against the spec |
| `63149192` | Audit Preferences, Privacy, More on AO3 and Drafts against the spec |
| `7e2d24b7` | Run the skeptic pass over the wave-3 audits |
| `2451a8c5` | Answer the wave-3 AO3 questions from otwarchive, Q11 to Q23 |
| `353ffe1f` | Write the wave-3 build briefs |
| `6b357842` | Record the wave-3 audit as done in TASKS.md |
| `c7fa926c` | Build the home-library batch (H1-H9) [unverified: no Xcode] |
| `89ed3857` | Build the search-filters batch (S1-S7) [unverified: no Xcode] |
| `d9ef791d` | Build the account-hub-reading batch (A1-A7) [unverified: no Xcode] |
| `70db11a1` | Build the browse-workdetail-comments batch (B1-B8) [unverified: no Xcode] |
| `e8e261ff` | Build the account-leftovers batch (L1, L2) [unverified: no Xcode] |
| `f19db7fc` | Compare DraftExpiryTests' created date field by field [unverified: no Xcode] |
| `49cf50cc` | Write the writing editor architecture (T-262) |
| `0f79d0f2` | Build E1: checkpointed recovery, off-main word count, O(1) keystrokes [unverified: no Xcode] |
| `593631f3` | Record the Linux compile check of E1's Foundation-only code (T-262) |
| `0aef4d4c` | Record the Linux compile check of T-257..T-261's Foundation-only code |

The whole branch changes 84 files (+7,699 / −284) against `c4ce1e2`. It adds 29 files:
- the 14 in `docs/audits/2026-09-24/`;
- `docs/WRITING_EDITOR_ARCHITECTURE.md` and `Scripts/make-writing-fixture.py`;
- five Swift sources (`AO3SubscriptionsRefine`, `WorkDetailFigures`,
  `WritingCheckpoint`, `WritingRecoveryWriter`, `SubjectStateBadge`);
- eight test files.
