# TASKS.md — Kudos task board

Shared, lightweight task board for all AIs + the human. **Read [`AGENTS.md`](AGENTS.md) first.**
Update this file whenever you start, finish, or hand off work — it is the primary
handoff channel between sessions and between agents.

## How to use it (30 seconds)

- **Claim** a task → move it to **In Progress**; set `Owner`, `Branch`, status `🔄`.
- **Finish** → move it to **Completed** with the commit SHA(s) + date.
- **Hand off / block** → leave it in **In Progress** with `✋ HANDOFF` or `⛔ BLOCKED`
  and a clear **Next step** / **Blocker**.
- Keep entries short; link to `docs/…` or `READIUM_MIGRATION_NOTES.md` for detail.
- Task IDs are `T-NN` (just for cross-reference; pick the next free number).

**Status:** 🔄 in progress · ✋ handoff (ready for pickup) · ⛔ blocked · ✅ done · 🅿️ backlog

---

## 🔄 In Progress

_None._ Claim a task from the Backlog and add a row here.

| ID | Task | Owner | Branch | Status | Next step / notes |
|----|------|-------|--------|--------|-------------------|
| —  | —    | —     | —      | —      | —                 |

---

## 🅿️ Backlog (prioritized)

### P1 — remaining
- **T-07 · Lazy / on-demand chapter extraction** 🅿️ *deferred.* Legacy/macOS reader
  only (the iOS Readium reader is already lazy); correctness-risky (WKWebView must
  resolve each chapter's CSS/image/font resources). Low ROI — do only if large-work
  perf becomes a real problem. Target: legacy `EPUBDocument.open` upfront-unzip.

### P2 — features (roadmap "Later" list; ID assigned on pickup)
- **Automatic CloudKit backup/sync** — portable file Export / Import completed
  in T-42; automatic background sync remains a later phase.
- **Highlights / notes / annotations** — large; a reader annotation system.
- **Text-to-Speech (TTS)** — large; `AVSpeechSynthesizer` in the reader.

### Phase 3 — native AO3 writes (most fragile; needs the per-page CSRF token)
- **Leave kudos · comment · subscribe · AO3-side bookmark** — fetch the work/page,
  extract its `authenticity_token`, POST the form, detect a login redirect. Build on
  `AO3AuthService.authenticatedRequest`. See [[native-ao3-roadmap]] Phase 3 +
  [`docs/AO3Authentication.md`](docs/AO3Authentication.md).

### UI-refinement & maintainability pass (user-planned — *after* the feature backlog)
- Polish the AO3 account sub-picker (the "Subs" label, 4-segment layout, "AO3
  History" vs the local "History"); a dedup / clarity sweep over the Phase-2 +
  download-queue / bulk-actions code; general maintainability pass.

### Readium migration — `readium-migration` only (see `READIUM_MIGRATION_NOTES.md`)
- **T-20 · Phase-4 interaction polish** — auto-hide chrome on scroll, custom
  page-turn animation, safe-area inset tuning. (Notes ▸ Migration status, Phase 4 = partial.)

### ⚠️ Verification & housekeeping debts (clear before trusting the new features)
- **🔴 Live AO3 verification (HIGH).** Every scraping feature shipped 2026-06-20
  (auth login; Marked-for-Later / Bookmarks / History / Subscriptions selectors +
  URLs; the series-page scrape for the download queue) is **build + unit-test
  verified only — never run with a real AO3 session.** Selector/URL assumptions are
  encoded in `KudosTests` fixtures; some may need a one-line fix once tested logged
  in. A single live login test validates the whole Phase-2 batch at once.
- **🔴 Visual verification (HIGH).** The simulator's display surfaces were
  unavailable for the entire 2026-06-20 session, so nothing new was screenshotted
  (AO3 sub-picker, Library bulk-select, download-queue banner, About page, Continue
  Reading shelf). All build/test-verified and the app boots clean, but unseen.
- **Keychain on a signed device build.** Confirm the session actually persists to
  Keychain on real hardware (the WebKit-store fallback is meant to be the
  Simulator/dev backstop only). See [`docs/AO3Authentication.md`](docs/AO3Authentication.md).
- **Broken intermediate commit `cb8e67b`** (the T-34 split) is on both branches'
  history and does **not** build on its own; HEAD is fine. Squash it via force-push
  only with the human's OK (AGENTS.md ▸ ask before force-pushing).
- **Scratch worktree cleanup.** Leftover `/private/tmp/Kudos-*` worktrees (incl. the
  `readium-migration` one ports go through). `git worktree prune` + remove when done.
- **Stashed pollution on `main` (2026-06-21).** `main`'s working tree had
  `readium-migration` content staged on it (Readium source, async `importEPUB`, rm
  `pbxproj`/`Package.resolved`). Stashed to **`stash@{0}`** ("POLLUTION: …") to
  restore a clean `main`. It's recoverable; **`git stash drop`** once confirmed it
  was accidental (it should not land on `main`).
- **Contaminated local `build/` derivedData.** It holds cached Readium modules
  (`ReadiumFuzi.o`, …), so `canImport(ReadiumShared)` wrongly evaluates **true** on
  `main`, making `KudosBackup`'s `readiumLocator` access fail to compile. `main` is
  actually fine (Codex's `#if canImport` guard is correct) — just **`rm -rf build/`**
  and rebuild. Use a fresh `-derivedDataPath` for `main` vs `readium-migration`.

### Bugs
- _No active bugs._ ↳ [`docs/Bugs.md`](docs/Bugs.md).

---

## ✅ Completed (recent — newest first)

| ID | Task | Owner | Branch(es) | SHA (main / readium-migration) | Date |
|----|------|-------|------------|--------------------------------|------|
| T-43 | Fix **BUG-4**: Library bulk-select `EditMode` is iOS-only → macOS build broke. Multi-select state guarded `#if os(iOS)`; macOS uses a plain `libraryList`. macOS + iOS both build, all tests pass. | Claude | both | _see git log_ | 2026-06-21 |
| T-42 | Portable `.kudosbackup` export/import for Library records, EPUBs, User Tags, bookmarks, custom fonts, and app/reader settings; merge-only restore through the system document picker (FI-19) | Codex | both | `6048684` / `5cd9394` | 2026-06-20 |
| T-41 | Local Reading Insights dashboard: works/words read, activity, completion, and top fandoms (FI-18) | Codex | both | `1cfe4b0` / `be74d8f` | 2026-06-20 |
| T-40 | Continue Reading shelf at the top of the Library (in-progress works, most-recently-read first → one-tap resume into the reader); added `SavedWork.lastReadDate` (FI-17) | Claude | both | _see git log_ | 2026-06-20 |
| T-39 | Settings → About / Sources & Licenses sheet (version, GPL-3.0, SwiftSoup/Readium/ao3_api credits, AO3/OTW disclaimer) (FI-16) | Claude | both | _see git log_ | 2026-06-20 |
| T-38 | Download queue (`DownloadQueue` + root progress banner) — "Download Whole Series" scrapes the series page (`AO3Client.seriesWorks`) and downloads/imports serially via the polite AO3Client; second half of "Download queue / bulk actions" (FI-15) | Claude | both | _see git log_ | 2026-06-20 |
| T-37 | Library bulk-select + bulk actions (delete / save / favorite) via EditMode + `List(selection:)`; first half of "Download queue / bulk actions" (FI-15) | Claude | both | _see git log_ | 2026-06-20 |
| T-36 | Phase-2: native AO3 work Subscriptions (4th "AO3" sub-tab) — reuses worksPage/parseSearchPage; only `li.work.blurb` items surface, so work subs only (FI-14). Completes the Phase-2 read backlog. | Claude | both | _see git log_ | 2026-06-20 |
| T-35 | Phase-2: native AO3 reading History + consolidate the account lists into one "AO3" segment with a sub-picker (`AO3AccountSection`) to avoid section-bar overflow (FI-13) | Claude | both | _see git log_ | 2026-06-20 |
| T-34 | Phase-2: native AO3 Bookmarks list — generalized the MfL view into `AO3AccountWorksList(kind:)`; `parseBookmarksPage` (`li.bookmark.blurb`, work id from `/works/` link, skips series/external) (FI-12) | Claude | both | _see git log_ | 2026-06-20 |
| T-33 | Phase-2 first authenticated feature: native "Marked for Later" reading list — Bookmarks "Later" segment, authenticated reads via AO3AuthService, reuses parseSearchPage + AO3WorkRow + pagination (FI-11) | Claude | both | _see git log_ | 2026-06-20 |
| T-21 | Calibrate Readium theme colors, typography units, margins, weight, built-in fallbacks, and imported custom-font rendering | Codex | `readium-migration` | — / `6fb3322` | 2026-06-20 |
| T-17 | Document EPUB ZIP/OPF/spine/TOC/metadata assumptions, import failures, security boundaries, tests, and Readium platform differences | Codex | both | `208df0c` / `a3f70ba` | 2026-06-20 |
| T-29 | Readium reader routes EPUB HTTP/HTTPS links to the in-app Browse tab while preserving system handling for non-web schemes | Codex | `readium-migration` | — / `6cb7525` | 2026-06-20 |
| T-32 | AO3 auth review follow-ups: off-screen login WebView gets a window, one silent hidden-login retry, calmer fallback copy, sign-up/reset links, AO3 HTML-fixture parser tests, doc + code clarifications | Claude | both | _see git log_ | 2026-06-20 |
| T-31 | Preserve successful AO3 login when Keychain is unavailable by recovering from WebKit's persistent app-scoped cookie store (BUG-3) | Codex | both | `3a3363d` / `39556be` | 2026-06-20 |
| T-30 | AO3 authentication foundation: native login, hidden WebView session capture, automatic visible fallback, Keychain persistence, session lifecycle, authenticated requests (FI-10) | Codex | both | `a5775d5` / `811a784` | 2026-06-20 |
| T-28 | EPUB web links (AO3 work/author/tag) open in the Browse tab, not inside the legacy reader's web view — verified in simulator (BUG) | Claude | both | _see git log_ | 2026-06-19 |
| T-15 | Sync in-app AO3 browser with app theme (FI-5) | Codex | both | `58663da` / `2f48e95` | 2026-06-19 |
| T-27 | Search Back returns to Browse (then the previous tab) after a fandom/typed search, instead of skipping straight to the tab (BUG) | Claude | both | _see git log_ | 2026-06-19 |
| T-26 | Toolbar "expand/collapse all" toggle for Search result cards | Claude | both | _see git log_ | 2026-06-19 |
| T-25 | Calm Search pagination layout (UI-1 follow-up) | Codex | both | `9374053` / `491b195` | 2026-06-19 |
| T-14 | Refine the Search pagination card (UI-1) | Codex | both | `024af77` / `1ab6781` | 2026-06-19 |
| T-24 | Enrich Browse-by-fandom cards: fandom/work counts, saved count, recently-read chips, regular text weight, section dividers (+ Search/Library card dividers) (FI-9) | Claude | both | _see git log_ | 2026-06-19 |
| T-16 | P2 AO3-red default accent + accent color picker (FI-6) | Claude | both | _see git log_ | 2026-06-19 |
| T-23 | Extend Include → Exclude → Clear cycling to Warnings/Categories (FI-3) | Codex | both | `ff4f93a` / `8373068` | 2026-06-19 |
| T-22 | Fix T-09 tag cycling UI + restore top picker search field (BUG-2) | Codex | both | _see git log_ | 2026-06-18 |
| T-09 | P2 Advanced rating + cycling include/exclude Search tags (FI-2, FI-3) | Codex | both | _see git log_ | 2026-06-18 |
| T-10 | P2 Expandable search result cards (FI-4) | Codex | both | _see git log_ | 2026-06-18 |
| T-11 | P2 Tap a tag (work/My) → filter the Library (FI-8) | Claude | both | _see git log_ | 2026-06-18 |
| T-12 | P2 Long-press Filters → Clear All Filters (FI-1) | Claude | both | _see git log_ | 2026-06-18 |
| T-13 | P2 Hide privacy eye button when no hidden works (FI-7) — *already implemented; verified* | Claude | n/a | — | 2026-06-18 |
| —    | docs: stable IDs + status across trackers | Claude | both | `2a8696d` / `1c3c8a4` | 2026-06-18 |
| —    | Collaboration system (`AGENTS.md` + `TASKS.md`) | Claude | both | `458dfd4` / `170d381` | 2026-06-18 |
| T-08 | P1 Sepia consistency verified (Settings); bug closed | Claude | both | `30f3e9a` / `746273a` | 2026-06-18 |
| T-06 | P1 Structured OSLog logging | Claude | both | `23392f0` / `d6b8c9f`+`b0ea6ff` | 2026-06-18 |
| T-05 | P1 Split `EPUB.swift` into focused files | Claude | both | `daa8422` / `edc07f4` | 2026-06-18 |
| —    | GitHub repo setup (GPL-3.0 LICENSE, README, docs/, topics) | Claude | both | `22ce718` / `20d7550` | 2026-06-18 |
| —    | P0-1 `KudosTests` target + 20 pure-logic tests | Claude | both | `7eac358`+`1012d53` / `8f6c7cc`+`aebe4ba` | 2026-06-18 |
| —    | P0-3 Typed `EPUBError`, AO3Client retry/backoff, surfaced failures | Claude | both | `362d5c0` / `cea2eb1` | 2026-06-18 |
| —    | P0-2 SwiftLint + SwiftFormat + pre-commit hook + CI | Claude | both | `f59a1bb` / `c5d9c1e` | 2026-06-18 |

_Older UI / reader / Library work predates this board — see `git log`._

---

## 🧭 Key decisions & open questions

- **macOS reader — decided:** iOS/iPadOS use Readium; **macOS keeps the legacy
  reader** (Readium navigator is UIKit-only). Readium SPM is scoped `platformFilter = ios;`.
- **Workflow — decided:** general work on `main` first, then port to
  `readium-migration` (see `AGENTS.md` ▸ golden branch rule).
- **AO3 authentication — decided:** native account UI drives AO3's real form in
  a hidden WebView; mechanism failures reveal the same WebView as a fallback.
  Sessions, never passwords, are stored device-only in Keychain.
- **Open — before going public:** scrub the Apple `DEVELOPMENT_TEAM` ID from
  `project.pbxproj`.
- **Open — migration (`READIUM_MIGRATION_NOTES.md` §6):** consolidate Library
  metadata on Readium vs keep the custom OPF layer?
- **Cleanup:** `test/card-lists` is abandoned/polluted and local-only — delete it
  eventually; never merge it.

---

## ↩️ Context for the next session

- **Done & pushed (both branches, in sync with `origin`):** the full AO3 auth
  foundation + **Phase-2 reads** (Marked for Later, Bookmarks, History,
  Subscriptions — all under the Bookmarks tab's "AO3" segment), plus the
  missing-features batch — **download queue & bulk actions, About page, Continue
  Reading shelf, Reading Insights, and portable Library backups** (T-30…T-42,
  FI-10…19).
- **Natural next pickup:** fix **BUG-4** to restore the promised macOS build,
  then start **Highlights / notes / annotations**. Automatic CloudKit backup/sync
  remains a later phase. The **live AO3 verification** debt still needs a real
  signed-in session.
- **Porting note:** `readium-migration` is checked out in a `/private/tmp/Kudos-*`
  worktree — port there (cherry-pick), not via `git checkout` in the main repo. See
  [[legacy-first-workflow]].
- Quick commands — Build/Test: `xcodebuild … CODE_SIGNING_ALLOWED=NO` ·
  `Scripts/test.sh` · Lint: `Scripts/lint.sh`.

## UI Consistency & Density Audit (Required Before Merge)

### Purpose
Ensure new UI work remains consistent with the established Kudos design language and does not regress information density, scanability, or theme behavior.

### Human Verification Required
The following items require screenshots and human review before completion:

- AO3 account sub-picker
- Library bulk-select mode
- Download queue banner
- About page
- Continue Reading shelf
- Search result cards
- Library cards

### Information Density Review
For every new or modified card:

- Verify title visibility is unchanged or improved
- Verify author visibility is unchanged or improved
- Verify fandom visibility is unchanged or improved
- Verify reading progress visibility is unchanged or improved
- Verify chapter/word count visibility is unchanged or improved
- Verify download status visibility is unchanged or improved
- Verify no critical metadata has been hidden behind additional taps

### Theme Consistency Review
Verify all new UI components:

- Use ThemeManager/AppThemeSurface
- Support Light, Dark, and Sepia themes
- Avoid hardcoded colors
- Avoid hardcoded corner radius values
- Avoid hardcoded shadows
- Follow existing spacing scale

### Card Family Consistency
Compare against existing Library/Search cards:

- Typography hierarchy
- Metadata presentation
- Badge styling
- Progress indicators
- Padding and spacing
- Corner radius treatment

### Approval Gate
Before merging UI changes:

1. Screenshot review completed
2. Density review completed
3. Theme review completed
4. Human approval received

Do not mark UI tasks complete until all four requirements are satisfied.
  
