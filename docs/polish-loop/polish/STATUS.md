# Polish loop status (lane claude/polish-loop, DerivedData ~/Library/.../kudos-polish)

## Owner asks (do first)
- [x] Download/Remove Download follows the file on device (WorkDownload + WorkDownloadButton;
      swipe/context/detail/bulk/remote; kept-by-queue names itself). Tests: WorkDownloadTests.
- [x] Comments: byline row is avatar-height, centred — names line up with avatars.
- [x] 1g two rows, bare names, compact counts (T-286, integrated)
- [x] Queues Reorder in "..." (T-285, integrated)

## Infrastructure
- [x] DemoLibrary (-KudosDemoLibrary YES -hasCompletedOnboarding YES
      -hasPermanentlyDismissedSyncFolderOnboarding YES) + DebugLaunchRoute (-KudosDebugRoute
      library|browse|account|search|section:<kind>|queues|queue:<name>). UI automation (tap/swipe)
      is NOT enabled in XcodeBuildMCP; snapshot_ui works.

## Batch 2 Library (Grok) — triage
FIX: 2-2 (Save for Later swipe on History/Favorites), 2-3 (no Compact on History), 2-4 (ExpandAll),
2-6 (ring SAVED/DONE), 2-10 (hairline + 3h 20m), 2-12 label "50k+ words", 2-13 (series empty card
+ "+"), 2-14 (skeleton + 18/16 spacing), 2-15, 2-16 (16pt names, no star), 2-17, 2-19, 2-1 initials.
OWNER: 2-1 since-last-visit (new AO3 fetch), 2-5 AO3 card in Saved for Later, 2-7 History state
buckets, 2-11 Insights extra cards, 2-12 new Unread/Downloaded facets.
REJECT: 2-8 Sort vs Filter chip (keep Filter app-wide), 2-9 → pass 2, 2-18 owner decisions.

## Batch 3 Queues (Codex) — triage
DONE (lane): 3-1 hide-mode filter (+ reorder blocked while hidden), 3-2 move ends select,
3-5 empty copy, 3-6 menu order, 3-9 Up Next ledger, 3-10 select header, 3-13 remove confirm,
3-14 grid Remove from Queue (ScopedRemoval), 3-16 no 0% ring (app-wide), 3-17 bare fandom kickers
(app-wide, FandomDisplayName.bareTitle), 3-18 compact counts (Int.compactCount), 3-20 wash
heights, 3-21 details legend, 3-25 pinned swipes, 3-26 no-match empty state, 3-27 visible reason,
3-29 a11y value.
TODO: 3-3 add-works sheet reveal/empty, 3-7 ExpandAll, 3-15 compact queue tag chips, 3-28 hit
targets (pills/swatches), 3-33 tag manager row menu, 3-4 download error surfacing, 3-19 grid spacing.
OWNER: 3-34 remove bottom queue switcher, 3-24 all-queues tag editor, 3-30 custom colour,
3-22 Queue Details reorganisation.
REJECT: 3-8 (1h prose keeps the In line switch), 3-11 (keep More + explicit "Remove from Queue"),
3-12 → pass 2, 3-31 (text Cancel/Create app-wide), 3-32 (copy close enough), 3-35 (wash keeps nav).

## Batches
1 Home — Claude — screenshots started (hero OK; kicker disambiguation fixed via 3-17)
2 Library — Grok done, triaged
3 Queues — Codex done, triaged
4 Collections — Grok grok-5952 running
5–9 — pending

## 2026-09-28 23:30 — landed on integrate c82da11b + installed on iPhone
Pass-1 commits (demo library, comment alignment, downloads rule, Queues/Library/Collections
fixes, small targets). Codex usage limit until Oct 3 → Grok runs batches 5 (grok-28971) and 7
(grok-28988); 8, 9 pending.

## In lane since (not yet integrated)
- 3-3 add-works sheet reveal + honest "Mature works are hidden" empty state
- 3-7 queue Expand All; 3-15 shared small-caps QueueRowTagLabel on 1h header
- 2-13 series empty: /series/new (site path — the old /users/<u>/series/new was wrong), 18/13.5pt,
  dead AO3SeriesEmptyCard (wrong Safari copy) removed
- 2-15 Recently Deleted row on subjectPanel
- Screenshot finds: Library fandom chips were raw tags ("Doctor Who" + "Doctor Who (2005)") → chips
  and LibraryFilters.fandoms match by family (bareTitle). History said "most recently read first"
  but LibraryFilters.apply re-sorted every section by Date Added → new LibrarySort.natural default
  ("Default"), no Sort chip unless changed.
REJECTED this round: 2-6 (ring says Finished, app's word), 3-28 pills (rails keep 28pt floor;
swatches got 44), 3-33 (tap-to-edit sheet already has the actions), 4-7 (Direction matches works
sheet), 6-4 (one header size app-wide), 6-7, 6-13 (short swipe labels app-wide).
Batch 6 (Work detail/Comments, Grok) done: fixed 6-3, 6-5, 6-14, 6-15; later: 6-1, 6-2, 6-6.

## 2026-09-29 ~00:30 — integrate e3694a81 (full verify + device install running: bjy1am3tz)
Landed since last note: Library natural sort + family fandom chips; add-works reveal; queue Expand
All + shared tag label; /series/new; Recently Deleted row; Browse downloads = on device; Save Search
shows the full search; Open AO3 Website row; fandom list empty state; Inbox single header; Log Out
confirms (3 places); in-app rows use chevron; Work detail = 1a (Quick Actions grid removed; local
actions in "…" menu, neutral tint, compact tallies); downloads via DownloadQueue banner (errors
visible); challenge empty states; honest pinch-hit button; Edit Tags order; own Works "+" toolbar.
All 9 batches audited (Codex: 3; Grok: 2,4,5,6,7,8,9; Claude: 1 via screenshots).
Pass 2 (cross-screen consistency sweep) running: grok-52388 → pass2-grok.md.
Still open (deferred, P2/P3): 6-2 My copy sheet restyle, 6-6 composer Post capsule, 7-2..7-5 account
list row styles, 5-6..5-13 fandom-list rows/index/search-ledger sizes, 4-4..4-12 AO3 maintainer
screens, 8-1/8-3/8-4 own-works rows, 8-6 delete helper, 9-3 remove-prompt swipe, skeletons (4-13,
7-10, 8-14, 9-23). Owner decisions pending: queue bottom switcher, since-last-visit fetch, History
state buckets, Insights extra cards, Unread/Downloaded filters, all-queues tag editor, custom colour.

## 2026-09-29 ~01:40 — pass 2 group A integrated (lane 1401ab53 → integrate 789146e7, T-288)
Fixed: pass2-2, -3, -8, -9, -11, -12, -13 (Done word), -18, -19, -20, -21, -24, -25 (collection
chrome), -26, -27, -28, -30, -31, -32 (titles/"cannot"; "Delete on AO3" kept — it is the app's AO3
verb in 4 places), -33.
REJECTED: pass2-6 (1h asks for the accent-filled + on the queue page), pass2-13 handles-in-select
(drag of a selected block is deliberate), pass2-15 (tag chips have no Reorder mode; the subtitle is
the only visible affordance), pass2-22 (subscriptions list names, not works — a work skeleton would
lie), pass2-25 queue-sheet tint (1j tints the sheet), pass2-29 (remote favorite needs a new
save path; context menu has no Favorite either — later).
Next group B: pass2-1, -4, -7, -10, -14, -16, -17, -23, -34.

## 2026-09-29 ~02:05 — group B integrated (lane a5280d6b, T-289); group A on device
Fixed: pass2-1, -10 (card long-press Delete — cards are not List rows), -14, -16, -23.
REJECTED: pass2-7 (collection New card and organizer New queue row are 1c/1i's; AO3 toolbar link
already reads as a "+"), pass2-5 (dashboard's hoisted mature button is the Select-mode chrome).
DEFERRED: pass2-4 (Select on account works / AO3 collections — rows mix local+remote, needs a
selection path for local entries), pass2-17 (See All / tag-works headers, P3), pass2-34 (Favorites
order rail is 1aj's — owner call).
OWNER QUESTION: word counts use two decimals ("18.02K words", owner call 2026-09-12) while every
other count now uses one ("1.5K"). Unify?

## 2026-09-29 ~13:00 — LOOP-v3 iteration 1
Landed: T-295 (Library ledger swipes + spec section spacing), T-296 (My copy sheet = 1a; page no
longer repeats Origin/Status/Conversion), T-297 (shelf shadow band). INVENTORY.md built (12 batches).
In flight: Codex B1 audit (Home/Library), Grok B2 audit (queues), Gemini 3.8 Flash inventory trial.
Gemini 3.1 Pro trial: unusable inventory (see TEAM.md).

## 2026-09-29 ~14:45 — LOOP-v3 iterations 3–4
Landed: T-299 (queues: Grok B2 fixes incl. 2 P1 select bugs, grid gaps app-wide, tint sweep),
T-300 (UserFacingError across 95 sites; DemoNetworkBlock — demo runs cannot reach AO3; Account
quick fixes), T-301 (Browse keeps Jump Back In above a failure).
Grok B5 (Account) done: 3 fixed, 3 rejected, 1 owner decision (#4 Hide Mature on AO3 lists),
14 spec-layout rebuilds queued for Codex (back 17:27). Grok now on B7 (Writing/author).
Gemini: B4 digest hung twice → killed; Claude did B4 directly.
## 2026-09-29 ~15:05 — iteration 5
Landed T-302 (collection page redesigned; Library debug routes). Recently Deleted, Reading Insights
match their artboards in sim. Grok still on B7.
## 2026-09-29 ~15:50 — iterations 6–7
Grok OUT (402, balance exhausted). Built the offline AO3 fixture harness (T-303) — Account/Writing
screens now screenshot-able. Landed T-303 (Works rails), T-304 (Account rows 15pt medium),
T-305 (Search chrome). Codex briefs ready (codex-task-1..4) for 17:27.

### Iter 9 (17:07)
- T-309 Series list cards restored (Section-modifier fold) + dead Account series block removed. Lane dfdbb2bd/+1, integrate 53b98211, 88d65fe4.
- Section-modifier follow-ups logged in FINDINGS L3-B7-1.
- Next: 17:28 launch Codex task 6 (Dynamic Type, P1) + task 1 in polish-codex worktree (effort high).

### Iter 10 (18:10)
- Codex T-310 collection cards (integrate 826d3b7d) and T-311 Dynamic Type sweep (56364203) landed after Claude review + fixes.
- Full suite: 2272 tests, only the 12 known env failures.
- Codex sandbox can't build/commit: brief updated; Claude builds, screenshots, commits.
- Running: Codex task 3 (queue details, codex2 branch polish-codex3), task 2 (bookmark card, codex branch polish-codex4).
- Next Codex: task 4 (account), 5 (fixtures), 7 (Home pills). Claude: L3-AX-4 Reading Now card truncation.

### Iter 10b (18:25)
- L3-AX-4 fixed (96fcdc3c): detailed WorkRow title/byline wrap at AX sizes.
- Codex hit its usage limit again at 18:13 (back 22:29). Claude finished task 3 → T-312 (integrate 63dcfd45):
  Details in spec order, tag-row menu, Show only → filters.userTags, Remove asks, accent Colour dot,
  `queue-details:<name>` route, removeTagFromWorks test. Resolved SubjectChip conflict keeping T-311 scaling.
- Task 2 (bookmark card 1q) partial in polish-codex (branch claude/polish-codex4): AO3WorkRow + AuthorProfileComponents + TASKS. Claude finishes next.
- Then: tasks 4 (account), 5 (fixtures), 7 (Home pills) — Claude, unless Codex returns first.

### Iter 11 (18:36)
- T-313 bookmark card 1q landed (integrate e5c536c2), Claude-finished from Codex partial. Lane == integrate (app sources).
- INVENTORY updated: queue settings/tags, bookmarks, collections grid.
- Next (Claude, Codex out until 22:29): task 7 Home pills, task 4 account rows, task 5 fixtures (collections/challenges) → B6/B8 audits.
- 18:45 T-314 Home Recently Updated pills landed (integrate 8fef0dc0). Next: task 4 account rows.
- 18:55 T-315 Account hub header + scope rows (Grok B5 rows 1, 2) landed (integrate b65162ec).
  Remaining task 4: row 19 dashboard cards, row 12 subscriptions, rows 14/15 inbox (inbox fixture shows skeletons — fix fixture first).
- 19:00 T-316 Dashboard compact cards (Grok B5 row 19) landed. Remaining task 4: row 12 subscriptions, rows 14/15 inbox.
- 19:06 T-317 landed (integrate bf68ff2c). Remaining task 4: inbox rows 14/15 (fixture first). Then L3-B5-20.
- 19:15 T-318 inbox landed (integrate 357443c9). Task 4 done. Next: L3-B5-20 unknown-stat zeros (P2), then L3-B5-21, task 5 fixtures (B6/B8).
- 19:22 L3-B5-20 (3d739dc7) and L3-B5-21 (7c363981) landed. Next: task 5 fixtures → B6 AO3 collections, B8 challenges audits.
- Task 5 held for Codex (22:29): mechanical, fixture-heavy. Claude meanwhile: B9 (insights, recentlyDeleted, collection pages), then B10 settings rows L3-B10-1.
- 19:28 T-319 insights period (integrate). B9 insights/recentlyDeleted audited.
- 19:30 L3-B9-2 Select glyph (e265f5ea). Next: L3-B10-1 settings form rows.
- 19:36 L3-B10-1 settings hub (0c183944). L3-FORM-1 sweep logged. L3-AX-2 (shelf card icon grid clipping) needs AX verify.
- 19:41 L3-FORM-1: WorkEditView fixed (+acct:workedit:<id> route). Remaining forms need routes.
- 19:45 L3-FORM-1: EditTags + Chapters (ae22a6d8). B6/B8 forms added to codex-task-5. Left for Claude: SeriesEdit, AddChapter, EditMultipleWorks (need routes).
- 19:52 T-320 writing loader page (integrate). Series edit has no fixture (series/\d+/edit) → note for task 5. Left: SeriesEdit/AddChapter/EditMultiple rows.
- 20:00 T-321 Browse Jump Back In (c13a0be9). Browse/Search fixtures added. Next: B4 fandom list + search results.
- 20:08 T-322 search hero (integrate). tagsearch:<fandom> route. agy Opus running task 5 in polish-codex2 (claude/polish-agy5).
- 20:27 task 5 fixtures + Series Edit rows landed (dc893721). Unverified agy screen edits held in lane working tree; next: debug routes into collection detail → challenge screens, verify each.
- 20:36 L3-FORM-1 B6/B8 screens landed (941f052f); acct:ao3collection:<slug> route. Left: AddChapter, EditMultiple rows; B6/B8 failure pages (T-320 pattern); L3-B7-2.
- 20:41 Try Again label unified (12 screens). B6/B8 failure cards keep chrome (brief note corrected).
- 20:55 T-323 prominent label contrast (integrate). B10 prefs/more/onboarding audited; B11 reader page ✓ (OD #6).
- 21:0x full suite checkpoint: 2277 tests, only the 12 known env failures.
- 21:10 L3-B1-8 labels (ee568d6f + lint fix). Title bar needs presentation move (5 call sites) — Codex candidate.
- 23:45 organizer gutter (df43b534). Codex back; task 8 (library filter sheet) running in polish-codex (claude/polish-codex8).
- 23:55 T-324 library filter sheet (Codex) landed 491e46c6. Next Codex: task 9 (P3 batch).
- 00:15 T-325 (Codex task 9, 3 of 4 kept) landed aab3aa25.
## 2026-09-30 ~15:00 — new session (handoff), iteration 12
- Codex task 10 collected and verified (FINDINGS). T-326 landed (lane f7975b56, integrate 87e9eb81): challenge
  screens + SubjectFormRow value width (app-wide). Lint 0/123. 110 tests in 10 suites green.
- Harness: `-KudosDebugManageRow <label>` opens a collection Manage row; route `acct:ao3collection:winter_exchange`
  (the fixture's own slug — `fest` breaks owner detection). TAP/SCROLL TOOL FOUND: AXe at
  ~/.npm/_npx/99336612077b7094/node_modules/xcodebuildmcp/bundled/axe (run in place; `swipe`, `tap`,
  `describe-ui`). Unblocks the 32 tap-only INVENTORY rows.
- Codex task 11 running (task-muogxxns-iqqrca, polish-codex, claude/polish-codex11). OD #7–#9 added.
- 15:45 iteration 13: Codex task 11 collected → T-327 (lane ff2e6630, integrate ada6e2fc) with Claude fixes: two dead
  pushing rows (L3-B8-2, P1), filled-button label contrast on 9 buttons (L3-TH-3, P1), 1s approval chip menu.
  Participants fixture → Moderation + Maintainers screenshot offline. 110 tests / 11 suites green; lint 0/123.
  B8 INVENTORY rows updated. Next: fixtures for Prompt meme (`/requests`) and Tag set (`/profile` tag-set links),
  then the tap-only rows (sheets, comment composer, reader chrome) with AXe.
- 15:55 T-326 follow-up landed (lane 0b1d11b0, integrate 6cda4ea9): form link rows full width again; `/profile` route.
  Codex task 12 (read-only audit: queue sheets, comments, fandom list, save search, AO3 history, author profile,
  series) running as task-muoii0d1-9lsmu7.
- 16:25 iteration 14: Codex task 12 audit verified (27 rows: 4 fixed by Claude → T-328 integrate eab554df, 12 queued
  as Codex task 13 task-muojvppo-qwib0l, 2 later, 6 rejected, 2 owner). OD #10 (History layout). Author layout
  picker P1 fixed. 81 tests / 8 suites green.
- 16:50 iteration 15: Codex task 13 (hit usage limit before its own checks; back 19:59 local) reviewed, 4 review fixes,
  landed T-329 (lane 2ac7d5dd, integrate 375fdd49). 195 tests / 20 suites green. New: L3-B4-5 (Browse hidden chips
  exposed to VoiceOver), L3-B4-6. Full suite running in background (first since handoff).
- 16:55 FULL SUITE (lane, after T-329): 2278 tests, 12 issues = exactly the 12 known env failures (10 backup/sync
  case-fold, HistoryHideAndQueueNotes round trip, Kokoro names). L3-FORM-1 closed: Add Chapter + Edit Multiple
  (lane c04c74ce, integrate 4ebb9acf; not screenshotted — same 2-line fix as 4 landed screens).
  L3-B4-5 downgraded to unverified (AXe lists opacity-0 chips despite .accessibilityHidden; needs VoiceOver check).
- 17:15 iteration 16: agy (Opus 4.6) task-14 audit verified → T-330 (lane 3206bf94, integrate ce771dff). 36 tests / 4 suites.
  New L3-B10-2 (Settings sub-pages still system Forms). Codex back 19:59.
- 17:20 L3-B10-2 landed (lane 5110252d): ten Settings pages drop the header that repeated their title. SettingsHubTests 10/10.
- 17:25 agy task 15 (edit mode, polish-codex2 / claude/polish-agy14): List minimum on Drafts/Preview/pickers, dead fallbackHue removed + collection colour footnote (L3-B1-9), Prompt Meme fixture + test.
- 17:40 iteration 17: agy task 15 → T-331 (lane 08e4382a, integrate 1962033b). Prompt Meme screenshot matches 1cc. 21 tests / 3 suites.
- 17:45 FIRST PASS COMPLETE (68 rows). Second pass started: theme contact sheets (Dark/Light/Sepia/OLED) for 21 routes, scratchpad themes-batch.sh.
- 18:15 second pass: theme sheets 1–6 reviewed (Home, Browse, Search, Account, Dashboard, Works, Inbox, Prefs, Settings, Queues, Collections, Insights, Recently Deleted, Work Detail) — consistent; L3-TH-4 fixed (integrate ffdcc764 + 9d8a2c00).
- 18:25 second pass: theme sheets 7–10 reviewed (My copy, Bookmarks, History, Subscriptions, Marked for Later, AO3 collection) — consistent; History's grid-by-default supports OD #10. AX5 batch (16 routes) running.
- 18:35 AX5 second pass: L3-AX-5 landed (lane 72210287, integrate 1e20fff9); 7 AX5 layout breaks briefed as codex-task-14-ax5.md.
- 18:55 L3-AX-6…12 fixed by Claude (lane 9e5955f0, integrate baec039b). codex-task-15-design.md ready for Codex's return.
- 20:40 Codex task 15 running (task-muot1sa8-5nm7gq, polish-codex, claude/polish-codex15 @ baec039b). Device build for owner's iPhone resumed after materializing iCloud-evicted .git (1,398 files) and Packages/Vendor/sources (~650).
- 20:55 OWNER-REQUESTED INSTALL: integrate baec039b (Debug, DEVELOPMENT_TEAM on the command line only; pbxproj unchanged)
  installed on "Yan's iPhone" (00008160-000045392021400A). Root cause of the stalls: data volume 98% full → iCloud
  re-evicting repo/.git; owner approved deleting 15 stale DerivedData caches (now 52 GB free).
- Gemini Flash task 17 (read-only pattern audit, ~15 min, 9.8k chars): pattern A 6 hits all false positives (closures
  are real actions, no nav link — my brief was too loose); D 3 real (AO3CollectionFormView, NewReadingQueueSheet,
  QueueTagSheet List minimum); E 15 fixed-size titles (backlog). No hallucinated file:lines.
- 23:00 T-333 (owner request) Browse fandom/tag results on the Search tab's redesigned page — integrate 8067e790.
  T-332 Codex task 15 (A–Z index, fandom markers, 1bv toolbar, mint privacy panel, Availability list) — integrate e97e1a7f.
  Gemini's 3 List-minimum rows — integrate 317b0b96. Second pass: challenge screens Light ✓, AX5 → Codex task 16 running
  (task-muoxtt6s-vp4t4b: scale body text in challenge/collection cards). agy Opus 4.6 task 18 (Home/Library/Work Detail
  second-pass audit) running. iCloud: integrate worktree + .git re-materialized; cherry-picks wait on it.
- 23:05 PAUSED (usage limit). In flight, to collect on resume: Codex task 16 (task-muoxtt6s-vp4t4b, polish-codex,
  claude/polish-codex16 @ 8067e790 — uncommitted edits; review, build, AX5+default screenshots, land); agy task 18 audit
  (output: scratchpad agy18.md / ~/.gemini/antigravity-cli/brain/<id>/design_audit.md). Before any build or git op:
  re-materialize .git + Packages/Vendor + integrate tree (iCloud keeps evicting). Then: rest of second pass, full suite
  on integrate, owner summary + OWNER-DECISIONS (10 items).
- 23:35 resumed: T-334 Codex task 16 (Dynamic Type for challenge/collection card text) landed after review (2 fixes:
  byline line limit, "Open on AO3" label restored) — lane 7160e9a1, integrate ebd52474. agy Opus 4.6 OUT (quota resets in
  ~141h); its Home/Library/Work Detail/My copy second-pass audit reassigned to Codex task 17 (read-only,
  task-muoz16as-wrac40). Full suite running on lane (== integrate sources).
- 23:45 FULL SUITE (lane == integrate ebd52474 sources): 2281 tests, 11 issues — all known env failures (10 backup/sync case-fold + Kokoro names); HistoryHideAndQueueNotes passed this run. No new failures.
- 23:55 Codex task 17 audit lost (usage limit until 01:37). Gemini Flash task 19 pattern sweep on Home/Library/WorkDetail running. OWNER-SUMMARY.md drafted (end phase).
- 00:10 Gemini task 19 (Home/Library/WorkDetail pattern sweep): A/B/C none; D ×4 fixed (integrate 90ca7ca2; Queue Details
  groups no longer spread apart); E ×15 fixed-size row titles → P3 backlog in the owner summary.
- 00:12 STOP CONDITION MET: two passes complete, no open P1/P2, full suite = known env failures only. Owner summary
  (OWNER-SUMMARY.md) and OWNER-DECISIONS.md presented; waiting for the owner's install request. Loop stopped.
