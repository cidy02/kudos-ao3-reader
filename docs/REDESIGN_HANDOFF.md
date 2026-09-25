# Redesign handoff: finishing the remaining items (cloud session)

Written 2026-09-24 by the Mac-side Claude session that ran the overnight redesign loop.
Branch: `review/codex-item12`. Evidence: `docs/audits/2026-09-24/`.

**Read first:**
1. `AGENTS.md`
2. `TASKS.md`: the newest rows, T-246 onwards, are at the top.
3. This file.
4. `docs/audits/2026-09-24/AUDIT_METHOD.md`

`docs/REDESIGN_PLAN.md` is intent, not status. It has been wrong in both directions, so prove every
status claim from live code and real call sites.

---

## 0. The one thing to know about this environment

A cloud session almost certainly has **no Xcode, no macOS SDK and no iOS simulator**. Check with
`which xcodebuild`. Without them you cannot build this app, run its tests, or look at a screen, so:

- **Audits and fact-finding** (sections 3A and 3B) are fully doable here. Do them first; they are
  the most valuable thing you can finish.
- **Any Swift you write is UNVERIFIED.** Mark it in the commit subject (`[unverified: no Xcode]`),
  and set its TASKS.md row to `🟡 NEEDS MAC VERIFY`, not DONE. Never write "builds", "passes" or
  "works" about code you could not compile.
- If `swift` exists, `swiftc -parse <file>` catches syntax errors only. SwiftUI and SwiftData do not
  exist on Linux, so nothing type-checks.

## 1. Hard rules

- **AO3:** never contact archiveofourown.org, never sign in, never perform or trigger an AO3 write.
  Building the UI for a write is allowed only where section 3 says so.
- **otwarchive:** read AO3's own open-source code on GitHub (`raw.githubusercontent.com/otwcode/otwarchive/...`,
  `api.github.com/repos/otwcode/otwarchive/contents/...`). It is the ground truth for markup,
  params and access rules; prefer it over this repo's hand-written HTML fixtures.
- **Branches:** work on your own branch, `cloud/redesign-finish`, created from the tip of
  `review/codex-item12`.
  - Never commit to `main` or `review/codex-item12`.
  - Never merge, force-push, reset or delete branches.
  - Push only your own branch.
- **Git hygiene:** `git add` explicit paths only. Don't touch `project.pbxproj`: new Swift files are
  picked up by synchronized groups. `DEVELOPMENT_TEAM` stays `""`.
- **Public repo:** no secrets, tokens or personal identifiers.
- **Coordination:** claim a TASKS.md row (`🔄 IN PROGRESS`, owner "Claude (cloud)") before editing.
  If a row is `🔄 IN PROGRESS` by "Claude (Mac)", don't touch it or its files.

## 2. Where things stand

### Built and committed on `review/codex-item12` (all verified on the Mac: iOS + macOS builds, lint, tests with baseline-proof)

| Row | What | Commit |
|---|---|---|
| T-246 | graphify codebase map + hooks | f9d00e36, e3f18e06 |
| T-240 | Collections screens bound to the session that loaded them | b11d179a |
| T-247 | Comments 1f threading rebuild (elbow rails, inline to depth 5) + skeleton | afe4b85f, c78f15e1 |
| T-248 | Writing W1: backdate date picker, draft posting + confirm, required ∗, single-series picker | 75778daa |
| T-249 | Writing W2: presentation polish on 1u/1w/1bn/1bq/1br/1bv/1bo | 856d5c22 |
| T-250 | History/Favorites/Recently Deleted HF1 (1ai 1ah 1aj 1ak 1bc 1bd 1bj) | 49d930ab |
| T-251 | Fixes for Codex review #1 (4 findings) | 50ffb70f |
| T-252 | Queues HF2 (1h 1bg 1j 1i, S items) | e32fba77 |

None of these is owner-approved on screen yet. The owner's screenshot gate applies to all UI.

### In flight on the Mac when this was written. Mac-owned: check TASKS.md before touching.

- **T-253 Challenges batch C1:** bugs plus S gaps on 1bz 1ca 1cb 1cc 1by 1cf, built against
  `docs/audits/2026-09-24/otwarchive-facts.json`. Files: `kudos-ao3-reader/Features/Challenges/*`,
  `Services/AO3Client+Challenges.swift`, `Models/AO3ChallengeModels.swift`.
- **T-254 Codex review #2 fixes:** 8 findings, all verified against code by the Mac session. The
  full spec is in section 5, in case the Mac session stops before landing them.
- **T-255 AO3 load stall:** on the owner's phone, Browse and every other AO3 page stopped loading
  until the app was relaunched. A read-only root-cause investigation is running. Don't touch
  `Services/AO3Client.swift`, `Services/AO3RequestCoordinator.swift` or `RequestCoalescer`.

## 3. Work queue (in this order)

### 3A. Audit the five areas nobody has audited yet (read-only; fully doable here)
Follow `docs/audits/2026-09-24/AUDIT_METHOD.md` exactly, and write
`docs/audits/2026-09-24/<area>.json` for each area:

| Area | Boards |
|---|---|
| `home-library` | 1b 1ad 1ae 1af 1ag 1c 1d 1e 1ay |
| `search-filters` | 1k 1ao 1ap 1aq 1ar 1as 1at 1au 1av 1aw 1ax |
| `browse-workdetail-comments` | 1g 1al 1am 1an 1a 1az 1f 1ba 1be 1bf. For comments, compare the row/card/thread visuals against `CommentThreadRow.swift` and friends; 1f's depth-5 inline threading is an owner decision. |
| `account-hub-reading` | 1m 1n 1bt 1o 1q 1t 1p 1l 1y. 1m/1bt: the hub was flattened by the owner (`AccountView.tabSections`). |
| `account-leftovers` | 1z 1ac 1aa 1bb 1x. These are the boards of the original account-settings area that tonight's audit did not cover. |

Then run a skeptic pass over your own five files, the way `critic-wave2.json` did for the last
wave. Re-open each DONE claim and each gap's file:line, and write
`docs/audits/2026-09-24/critic-wave3.json`.

### 3B. otwarchive facts for the new gaps
Some gaps depend on AO3 markup, a param or an access rule. For each one, answer it from otwarchive
and append to `otwarchive-facts.json`, using the same entry shape: `q`, `answer`, `sources`,
`quote`, `implication`. Q1–Q10 are already answered; start at Q11.

### 3C. Build briefs, one per batch
For each audited area, and for **C2** (collections-moderation + account-settings-collections: the
JSONs plus `critic-wave2.json`, where the critic's WRONG/UNSURE corrections win), write
`docs/audits/2026-09-24/brief-<batch>.md`. Each brief contains:
- **Bugs first:** wrong or dishonest output. Tonight's audits found plenty: page-1 counts shown as
  totals, failures shown as "empty", one date shown as another, a reject sheet claiming AO3 emails a
  reason it never receives (otwarchive Q6).
- **Then S gaps that need no owner decision.** For each: files, the spec quote, the exact change,
  and the one test that proves it.
- **A separate "Needs the owner" list.**
- **Cap:** at most ~12 items per batch, so one implementer can finish a batch in a single session.

### 3D. Implement batches (UNVERIFIED here; only after 3A–3C are committed and pushed)
Take one brief at a time. Per batch:
- **Commit:** one commit, subject ending `[unverified: no Xcode]`.
- **TASKS row:** `🟡 NEEDS MAC VERIFY`, listing exactly what the Mac must check.
- **Tests:** pure decisions go in `static func`s with Swift Testing tests. Parser changes get a
  small fixture matching the otwarchive template, never invented markup.
- **Design system:** reuse the parts listed in AUDIT_METHOD.md. New List/Form views need
  `.appThemedScroll()` / `.appThemedRows()`. Chips and pills need internal padding.
- **Style:** match the surrounding code's comment density and idiom.
- **Keep out of:**
  - AO3 networking core (T-255).
  - Deletion and persistence semantics (`PreservedWorkService`, `WorkLifecycle`, SwiftData
    models). Any new schema field is an owner decision.
  - `project.pbxproj`.

**Items already known to remain.** The per-item detail is in the JSONs.

- **Writing** (`writing.json`, S items done in T-248/T-249):
  - 1bo chapters list (`chapterIndex`) — M.
  - Preview screen (`previewWork` / `previewChapter`, never wired) — M.
  - 1bu drag-to-reorder chapters — M.
  - The Series row reads "None" for a work already in a series (parse AO3's "Current Series") — M.
- **Queues / History** (`history-favorites-queues.json`, S items done in T-250/T-252):
  - 1h + add-works picker — M.
  - 1i select mode (bulk pin/tag/delete) — M.
  - 1i 2×2 peek tile — S/M.
  - 1i always-live drag — S. Mind T-254 #3: reorder must stay disabled while a filter is active.
  - 1bg drag while selecting — M.
  - 1bj select mode — M.
  - Needs a schema field (owner): 1ah "Remove from history" (hide marker) and 1h queue
    description.
- **Challenges, after T-253 lands** (`challenges.json` + facts Q1–Q5, Q9):
  - 1bz read-only sign-up detail. Q2: maintainers CAN view another user's sign-up show page, so
    this is a new show-page parser plus a view (M).
  - 1bz per-row request/offer summary. Q1: no printed count; derive it from the rendered prompts
    (M).
  - 1ca per-request tag-limit checks (M).
  - 1cb pinch-hit rows (M).
  - 1cc fandom kicker (M).
  - 1cf Basics rows (M).
  - 1cf Matching section from `potential_match_settings` (Q9) (M; save is an AO3 write).
  - 1by "who is this for": Q5 says the settings pages are maintainer-only, so the non-maintainer
    route likely fails. Report this; the owner decides the audience.
- **Collections / moderation / account settings:** C2, per the briefs you write in 3C.

## 4. Owner decisions: list them, never build them

- **Comments depth:** built inline to depth 5; artboard 1f draws depth 0–2 plus "Continue thread".
  The cap is one constant, `CommentThreadGeometry.maxInlineDepth`.
- **Networking policy:**
  - 1bc "since your last visit" needs a per-fandom fetch.
  - 1ab notifications need background polling, which the policy forbids.
- **Effects of stored toggles:** queue "Keep offline"; collection "Keep downloads" / "Show on
  Home" / Colour.
- **Writing:**
  - 1bv formatted chapter editor (which OSS editor?).
  - 1v single sheet vs several.
  - 1bn bulk Delete.
  - 1br series "Remove works" (a separate AO3 delete route).
- **Queues:** 1j round ×/✓ glass buttons vs text buttons (parity with NewCollectionSheet).
- **Collections moderation:**
  - 1ce reject copy: AO3 sends no reason (Q6).
  - `ModeratedItemsView` has no route: wire it or delete it.
- **Collections:** 1bl collection delete (a DELETE write, Q10) and icon upload (no multipart
  support).
- **1bh:** plan contradiction, excluded.
- **Comments:** signed-out comment action row gap.

## 5. T-254 spec (Mac-owned; implement only if TASKS.md shows it not started and the owner says the Mac session stopped)

Codex (gpt-5.6-sol) reviewed 49d930ab, 50ffb70f and e32fba77. Its verdict was FIX FIRST, and the
Mac session re-verified every finding against the code.

1. **P0, stale per-item confirmation.** `RecentlyDeletedView` builds per-item closures (`:230`
   work, `:248` collection, `:265` queue) that hard-delete unconditionally. If sync, a restore or
   another window restores the item while the alert is open, confirming deletes a live record.
   - **Fix:** add `PreservedWorkService.deletePermanently(_:)` overloads (work / collection / queue)
     that no-op unless `isPendingDeletion`. The view and `hardDeletePending` use them.
   - **Not in `WorkLifecycle.hardDelete`:** tests call it on live works.
   - **Tests:** a live work, collection and queue each survive `deletePermanently`.
2. **Coauthor chevron.** `ReadingAffinities.authors` (`:83`) gives a coauthored byline its first
   registered identity, so the chevron opens the wrong author. Set `username` only when the work has
   exactly ONE registered identity; add a test.
3. **Reorder under a filter.** `ReadingQueueOrganizer` reorders only the filtered ids, rewriting
   `sortOrder` from 0 and corrupting hidden queues' order. While search or a tag filter is active,
   hide Reorder and pass `.onMove(perform: nil)`.
4. **Saved for Later ignores the tag filter** in `visibleQueueCount` (`:82`) and in its row (`:256`).
   Apply `matchesTagFilter` too.
5. **Stale persisted `tagFilter`.** When the stored tag no longer exists, the rail disappears and
   the filter can't be cleared. Show the rail when `!queueTagNames.isEmpty || !tagFilter.isEmpty`.
6. **`ReadingQueue.addTag(named:among:in:)` trusts `known`.** A failed or stale fetch can insert a
   duplicate `@Attribute(.unique)` `Tag`.
   - **Fix:** do an authoritative `context.fetch` before inserting, and return nil if the fetch
     fails.
   - Drop the `among:` parameter (3 callers).
7. **Comments counts ignore cutoff placeholders.** `CommentThreadRow` has two counts, the
   collapse label `replyCount` (`:716`) and the expander `hiddenCount`s. They ignore the AO3
   cutoff placeholder's `cutoffCount`. Use one helper, shared with `deeper` in
   `CommentConversationBuilder.items`.
8. **`PreservedWorkTests:145`:** add a live collection and a live queue to the "nothing live" bulk
   test.

## 6. Mac verification checklist (for every `[unverified]` commit)

1. **iOS build:**
   `xcodebuild -project AO3_App_OpenSource.xcodeproj -scheme AO3_App_OpenSource -destination "id=<sim>" build`
2. **macOS build:** `-destination 'platform=macOS'`. It uses the legacy reader, so iOS-only APIs
   in shared code break it.
3. **Lint:** `Scripts/lint.sh`, 0 `error:`, and warnings must not exceed the 129 baseline.
4. **Tests:** targeted suites with `-only-testing:KudosTests/<Suite>`. Suites under
   `PersistenceGateSuites` need their nested names.
5. **Baseline-proof:** break the fix, watch its test fail, then restore.
6. **Screen:** a simulator screenshot, then the owner's screenshot gate.

## 7. When you stop

- **Commits:** everything lands with explicit paths, and your branch is pushed.
- **TASKS.md:** your rows carry an honest status, including what you could NOT verify.
- **Final reply contains:**
  - per-area status counts
  - the top bugs found
  - batches written and batches implemented, with the unverified list
  - owner-decision additions
  - anything you couldn't determine
