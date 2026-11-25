# Redesign decisions — 2026-09-26

The owner delegated every open redesign decision to Claude ("make decisions, your best effort
based on everything you know about the app"). These are those decisions. They are binding for
the rest of the redesign unless the owner overrides one; agents cite this file instead of asking.

How they were made: the app's own rules come first — `AGENTS.md` (UI must keep or improve
information density; new UI stays consistent with existing UI), `docs/AO3_NETWORKING_POLICY.md`
(its "must not implement" list is binding), `docs/DATA_AND_PERSISTENCE_INVARIANTS.md`, and
`docs/PROJECT_PHILOSOPHY.md` (native first, AO3 parity, privacy). Where the spec and those rules
disagree, the rules win. AO3 behaviour comes from otwarchive's source
(`docs/audits/2026-09-24/otwarchive-facts*.json`), never guesses.

AO3 writes below are **built** (with a confirmation and local stub tests) but never exercised by
agents; the owner verifies them live.

## Settings (1ab) — segment the page

Today Settings is one long page of 17 sections. It becomes a short **hub of grouped rows**, each
row pushing to a focused page — the shape 1ab draws (`SectionRuleHeader` groups of
`subjectPanel` value rows such as "Theme · Dark ›"). Order follows 1ab (Reading first, Downloads
second, About last):

| Group | Row → page | Contents today (moved, not rewritten) |
|---|---|---|
| **Reading** | Appearance › | Theme, accent colour, text size |
| | Font › | Font picker, custom fonts |
| | Reader › | Reading mode and the other reader options (`ReaderOptionsForm`), keep screen awake |
| | Listening › | Text-to-speech (`ReaderSpeechSettingsSection`); Developer settings stay behind their own gate |
| **Downloads & Storage** | Downloads › | Download on subscribe, "Keep downloads for", storage used |
| | Preservation › | Preservation settings |
| | Reading Queues › | Queue settings |
| **Library & Sync** | Backup › | Backup / restore |
| | Sync Folder › | Folder sync, status, last result, deletion trust (tombstone trust) |
| | Import › | EPUB / document import |
| **Account & Privacy** | AO3 Account › | Signed-in account, Sign out |
| | Privacy › | Privacy settings, recovery copies |
| **About** | About › | Version, licences, links |

Each value row shows the current value on the right (e.g. "Theme · Dark", "Keep downloads for ·
30 days", "Sync Folder · On"). Every existing control keeps its behaviour and `@AppStorage` key —
this is a reorganisation, not a rewrite; nothing a user set changes. Pages use the design-system
parts (`SectionRuleHeader`, `subjectPanel`, `SubjectFormRow`) and `.appThemedScroll()` /
`.appThemedRows()`. macOS shows the same hub (a sidebar-less push list is fine).
**Notifications (1ab): not built** — it needs background polling, which the networking policy
forbids; the row is left out rather than shown disabled.

## Writing

| Item | Decision | Why |
|---|---|---|
| **OD1** rich WYSIWYG canvas in a WebView | **Not now.** Keep the native HTML editor; add a **native formatting toolbar** (inserts AO3-allowed tags around the selection) and a **rendered preview toggle** (read-only). Revisit OD1 after E2. | The 2026-09-12 native-only rule; a WebView editor is an L job with IME, VoiceOver and 50k-word memory risks; toolbar + preview gives most of 1bv's value natively. |
| **OD2** remote images in the editor | Placeholders; load on request. | Privacy (no silent third-party requests). |
| **OD3** AO3's word-count algorithm | **Yes** — match AO3 (E2). | The number a writer sees should be the number AO3 shows. |
| **OD4** recovery copies in device backups | Keep as today (included). | Losing a draft on a restored phone is worse. |
| **OD6** spell-check in HTML mode | **Yes.** | Matches AO3's own textarea. |
| **1bv** formatted editor | As OD1: toolbar + preview, formatted-by-default deferred. | — |
| **1v** works sort & filter | **One sheet**, the same shape as Search's filter panel. | Consistency rule; the spec draws one sheet. |
| **1bn** bulk Delete | **Build**: Delete in the bulk bar → alert naming the count and titles, destructive, never pre-selected. | AO3 parity (its edit_multiple page deletes); strong confirmation. |
| **1br** series "Remove works" | **Build** via AO3's per-work series removal, with confirmation. | AO3 parity. |
| **1x.3** Post/Delete swipes on drafts | **No** — stay in the editor. | Deliberate: destructive/irreversible actions don't belong on a swipe. |
| Preview screen, 1bo chapters list, 1bu reorder, Series row "None" | **Build** (no decision needed). | — |

## Library, queues, history

| Item | Decision | Why |
|---|---|---|
| Queue **Keep offline** / collection **Keep downloads** effect | **Build**: ON → member works' missing EPUBs are fetched through the existing paced download queue (only when the user turns it on or adds a work — no polling) and exempt from the cache sweep; OFF → a plain list that doesn't count against storage (the copy the spec already has). | Makes a stored toggle mean what it says; networking policy respected. |
| Collection **Show on Home** | **Build**: flagged collections appear as a Home carousel after Queues. | The toggle exists; the spec draws it. |
| **1ah** Remove from history | **Build** with one optional field `hiddenFromHistoryAt: Date?` (backup + sync + invariants doc). | The spec's only destructive action on History, and it must not delete the work. |
| **1h** queue description | **Build** with one optional field `ReadingQueue.notes: String?` (backup + sync). | Spec draws it; low risk. |
| **1j** round ×/✓ glass buttons | **No** — keep text Cancel/Create. | Consistency with NewCollectionSheet and iOS sheets. |
| **1ad.5** ledger rows default for Reading Now | **No** — keep cards. | They'd drop the summary: a density loss (AGENTS.md). |
| **1bc** "since your last visit" per-fandom fetch | **No.** | Networking policy (no per-fandom polling); keep local counts. |
| **1an.2** "I have downloads from" | Means **on disk now**. | What the reader can open offline. |

## Comments

| Item | Decision |
|---|---|
| Threading depth | Inline to depth 5 (owner decision, T-247) — unchanged. |
| **1f.4** continuous loading | **No** — keep AO3's pages (fewer requests, matches AO3). |
| Signed-out action row gap | **Fix** (layout bug). |
| **1f.5** depth 5 vs AO3's cutoff | Keep depth 5; AO3's "N more comments" placeholder stays the way onward. |

## Search, browse, account

| Item | Decision |
|---|---|
| **1au.4** "Include Not Rated" under Rating Any | One rule for Search and Refine: **Search's** rule. |
| **1o.4** Unmark in Marked for Later | **Build** (AO3 write `PATCH /works/:id/mark_as_read`, Q19) as a swipe with the standard confirmation-free toggle, like AO3's button. |
| **B6** Kudos chip tint | The kudos **count** chip is neutral; only states about the reader (Subscribed, You gave kudos) are tinted. |
| **1al** Group variants switch, **1l** Inbox pill rail, **1p.4** Subscriptions scopes, **1ad.3** WIP pill, **1ay.3** colliding filter pair | **Build.** |

## Challenges and collections

| Item | Decision | Why |
|---|---|---|
| **1by** who sees Challenge settings | **Owners only** (read + edit), per Q5; non-maintainers see the public profile. | AO3 refuses the page to everyone else. |
| **1cb** Report a default / Claim a pinch hit | **Build** (AO3 writes, confirmations). | AO3 parity. |
| **1cc** New prompt | **Build** via the sign-up form. | Parity. |
| **1ce** reject copy | Confirmation alert, **no reason field**, no email claim (Q6). | AO3 has neither. |
| ModeratedItemsView (unreachable) | **Delete** it; its "recently decided" goes into 1cd. | Deletion over a second screen. |
| **1bl** collection delete | **Build** for owners (Q10), destructive alert naming the collection. | Parity. |
| **1bl** icon upload | **No** (needs multipart upload). | Low value, new capability. |
| **1bh** | Excluded (unchanged). | — |

## macOS

| Item | Decision |
|---|---|
| Reading-progress label | **Parity with iOS** (owner, 2026-09-25): T-264 computes Readium's whole-publication progression on the Mac. |
| T-264 "quick open" write | Accept the residual (a quick open can record the percent on close only if the restored page lands measurably off the saved spot). |

## Backup, Insights and Read Aloud — best-effort decisions (2026-11-22, for the owner's later review)

The owner asked Claude to "make a best effort decision on the other two and document them in the owner decisions document for later review".
These stand until the owner overrides them.

| Question | Decision | Why |
|---|---|---|
| **Replace Library with an archive that omits `readingSessions` / `readingFavorites` / `fandomWatermarks`** (e.g. an Android re-export): today the decoder turns a missing key into `[]`, so Replace deletes and tombstones every local row the archive doesn't list. | **An absent key means "this archive says nothing about these rows" — Replace leaves them alone.** Only a key that is present (even as `[]`) replaces that collection. Writers keep emitting the key whenever they hold the data, so an iOS archive behaves as today. | Matches the rule the rest of backup already follows ("an omission never clears"); an older build or Android cannot silently erase reading history. Cost: a user who really wants to wipe sessions must use an archive that carries `readingSessions: []` (every current iOS export does). Android should write the keys it holds (A-541). Tracked as **T-563**. |
| **Your own AO3 actions in Insights (D11: kudos, bookmarks, comments you made)** across several AO3 accounts on one device/sync set | **Record the AO3 account (username) with each action and show only the signed-in account's actions; a signed-out view shows none.** Older unattributed records stay visible under every account until the owner chooses otherwise. Private-bookmark observations are never shown under a different account. | Keeps one account's private bookmark history from appearing while another is signed in; cheapest change that respects privacy. Tracked inside T-536 (follow-up T-536b); D11 itself is outside T-536a and lands with T-536c. |
| **Read Aloud engine bugs found in the Insights rounds** (Kokoro/Core ML start, pause/skip races) | **Not split out** (owner, 2026-11-22: "do not split out the bugs just fix them"): fixed in the Read Aloud lane `claude/rd-t535c` until its review passes, then landed with the Insights follow-ups. | Owner instruction. |
| **Android SDK on the build Mac** | **Installed** (owner: "install what you need"): command-line tools via Homebrew, SDK at `~/Library/Android/sdk` (platform 37, build-tools, platform-tools), Java from Android Studio's bundled JBR; Google's SDK licences accepted under that instruction. | Unblocks `android-check.sh` and the Android parity strand. |
| **Android Folder Sync: whose is a manual backup import?** (A-541 review 7: Folder A → import → disconnect → connect Folder B either dropped the imported works' pass-through fields, e.g. `authorIdentitiesJSON`, or carried Folder A's tag across) | **A manual backup import belongs to this device's library, not to a folder.** Its pass-through overlay is stored untagged and travels with the library to whichever folder syncs next, including after a folder switch. Only the last *synced* manifest (what a folder last held) stays folder-scoped and is dropped on a switch. The tag and body are written as one file in one atomic move. | The import already changed this device's library; dropping its extra fields at a folder switch silently loses data on the next export, and every folder is the reader's own. Best-effort call by Claude, 2026-11-22, pending the owner's review. |
| **Read Aloud: a Stop within ~10 ms of audio becoming audible** (T-535i review: the heard start can be lost) | **Accepted for now:** the reader re-hears at most one passage. A drain that tried to keep that start credited it to the wrong passage on a same-chapter re-anchor, so it was dropped. Integration before wave 36 erred the other way (skipped ahead to unheard text). Revisit on a device (T-535k). | Re-hearing is the safe direction; nine review rounds had not converged on the timing edges, which only a device can verify. Claude, 2026-11-22. |
| **Insights T-536 and Android A-541 split mid-review** | T-536 → D7–D9 landed (wave 35), D10–D11 → T-536c. A-541 → pass-through + folder provenance (A-541a), Replace crash journal (A-541r), sitting-key carry (A-541s). | Each had gone 5–12 review rounds with new P1s in the riskiest part; landing the reviewed-safe part and isolating the rest keeps progress without lowering the bar. Claude, 2026-11-22. |
| **Manifest streaming — what the streaming parsers accept** (T-567/A-567 P2; P1 found today's routes differ) | **One shared accepted-input contract on both platforms = what iOS accepts today:** a leading UTF-8 BOM, trailing commas, first value wins for a duplicate key; a lone surrogate is rejected; a top-level scalar is not a manifest. Android drops its extra lenient-decoder acceptance (single quotes, comments, `;`/`=`, unquoted tokens) — Kudos never writes those. | Owner approved, 2026-11-22. A streaming parser can't reproduce kotlinx's lenient fallback; one contract keeps both apps reading the same files the same way. |
| **Manifest streaming — nesting depth limit** | **512 levels**, both platforms (new limit). Real manifests nest about 5 deep. | Owner approved, 2026-11-22. Bounds parser stack use on hostile input. |
| **Library scale requirement** (owner, 2026-11-22: "every aspect of the app code can handle any size library that a human might reasonably have" — e.g. an archivist with 15,000 works saved over three decades) | **Design target: 50,000 works and 30 years of reading history** (≈ 300,000 reading sessions, 50,000 bookmarks, 20,000 highlights/notes, 1,000 collections and queues, 200,000 distinct tags), on both platforms. **Test points: 15,000 works (the realistic archivist) and 50,000 (headroom).** No screen or service may load, sort or compute over the whole library on the main thread, and memory must not grow with the library beyond what is on screen or in a bounded batch. Tracked as T-568 (audit, fixture, device benchmarks, fixes). | Owner requirement. The target is set above the example so nothing is tuned just under a real user's library; the owner can change the numbers. |
| **Sync policy — edits made around a delete** (D4 Q-1) | **Kept:** edits concurrent with a delete are held, and a restore brings the work back with them. | Owner, 2026-11-23. |
| **Sync policy — permanent delete** (D4 Q-8) | **Everywhere:** an explicit permanent delete (Delete Now / empty Recently Deleted) removes the work from Recently Deleted on every device; the confirmation says so. The automatic 90-day cleanup still loses to a restore. | Owner, 2026-11-23. Confirmation wording to be shown to the owner with the UI. |
| **Sync policy — 90-day window with two deletions** (D4 Q-9) | **Latest deletion** starts the window, so a work never gets less than 90 days. | Owner, 2026-11-23. |
| **Sync policy — AO3 id and URL point at different works** (D4 Q-3) | **Decided automatically** by the existing AO3-id-first rule, with a diagnostic; no review screen for now. | Owner, 2026-11-23. |
| **iOS store layer (T-571 / D3)** | **SwiftData stays.** T-567 P1b (`out/t567p1b-ios.md`, simulator): bounded batches pass (15–22 MiB peak, ≤ 1.5 MiB growth 128→512 MiB) when each batch runs on a fresh context **inside its own `autoreleasepool`** — P1's growth was autorelease-pool buildup, not SwiftData; the shadow store + journaled swap passed a 15-step kill matrix (always the old or the new store, EPUBs in step). Conditions: (1) **add an index on `SavedWork.id`** (and other id lookups the apply uses) — batch fetches scan the table today, which is why apply time ratios miss (5–6×) and a 512 MiB apply took 382 s; additive SwiftData schema change, migration tested on iOS and macOS; (2) **quiesce before a swap**: every container/context holder (P1b lists them: `sharedModelContainer`, `FolderSyncBackgroundTask`, `DownloadQueue`, the stored contexts, the `@ModelActor` backfills, views) is drained under `PersistenceOperationGate`, and user edits are blocked during a Replace/restore apply (as the gate already blocks other persistence work) — replaying them from the outbox becomes possible after D6; (3) re-proven on a device before release. SQLite-direct is not pursued. | Claude, 2026-11-23, from measurements; within the plan's gate. The owner is told (no migration). |
| **A-541a landed with a known limit** (Android manifest pass-through + folder provenance) | **Landed** on `android/redesign-parity` (`38951110a`) with a documented limit: sync and backup manifests over Android's 8 MiB read cap. On such a library Android may republish opaque data from conflict copies (leaving a manifest it cannot read back), may run out of memory reading the manifest before the cap check, and a manual export can fail after two imports (Codex check 5). The streaming manifest work (T-567/A-567 P3/P4) replaces this read path and removes the cap. | Owner, 2026-11-24 ("Yes, land it"), on Claude's recommendation |

## Overnight 2026-11-25 — best-effort decisions (Claude, overnight 2026-11-25 — for owner review)

The owner, 2026-11-25 ~00:20: "you're the desicionmaker, i will be asleep … make a best effort decision yourself and record it in the
owner decisions document for me to review later". Each row below is one such call; override any of them and it is undone.

| Question | Decision | Why |
|---|---|---|
| **Tab bar (T-572)** | **System tab bar back** (owner's call, 2026-11-25); the custom shrinking bar is shelved on branch `claude/rd-t572` and documented in TASKS T-572, not deleted. | Owner: "not worth putting in the effort to perfect it". Revisit means rebasing that branch, not rewriting it. |
| **Comments composer placement** (asked earlier because the custom bar changed the bottom inset) | **Moot — no change.** The composer keeps today's placement above the system bar. | The question only existed with the custom bar. |
| **Per-work cover choice (T-573/A-573) — what "Follow Settings" means after an explicit choice** | A reset writes an explicit `"follow"` value (not "no value"), so the reset syncs to other devices. | "No value" never clears in Kudos merges (absent never clears), so a reset could never reach another device. |
| **Per-work cover choice — how it merges** | **Its own clock**, `coverArtPreferenceChangedAt`: newest stamp wins; equal stamps → the alphabetically greater value wins (same on every device); a value without a stamp (older backups, Android before A-573) loses to a stamped one; Replace Library (a restore) always takes the backup's value. A cover tap does **not** move the work's "last modified" time. | Tying it to the work's clock let a cover tap undo another device's favourite/finished edit, and let a newer unrelated edit swallow a cover choice. A restore must roll back. |
| **T-521 Reader Response calibration** | **Not started overnight; still waits for your yes.** | About 1,400 anonymous AO3 requests over several days — new AO3 traffic needs your explicit approval (networking policy); nothing in tonight's instruction covers it. |
| **Overnight order** | iPhone: BUG-14 redo and T-573 (both in confirmation review) → T-530 → T-531 → T-537 → T-536c → T-535k (non-device parts) → T-507. Then Android parity: A-573 first (in progress), then A-509c, A-511, A-512, A-506/458/505, A-459/465, A-475+, A-513. Data-architecture docs (D4/D5/P3) continue in parallel on Codex. | Finishes what is nearly done first, then the iPhone queue in TASKS order, then Android in the order of its parity list. |
