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
