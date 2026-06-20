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

| ID | Task | Owner | Branch | Status | Next step / notes |
|----|------|-------|--------|--------|-------------------|
| T-15 | Sync in-app AO3 browser with app theme (FI-5) | Codex | `main` → `readium-migration` | 🔄 IN PROGRESS | Inject scoped AO3 Light/Sepia/Dark styles, update live on theme changes, then verify navigation and persistence. |

---

## 🅿️ Backlog (prioritized)

### P1 — remaining
- **T-07 · Lazy / on-demand chapter extraction** 🅿️ *deferred.* Legacy/macOS reader
  only (the iOS Readium reader is already lazy); correctness-risky (WKWebView must
  resolve each chapter's CSS/image/font resources). Low ROI — do only if large-work
  perf becomes a real problem. Target: legacy `EPUBDocument.open` upfront-unzip.

### P2 — features & polish (detail in `docs/`)
- **T-17 · Document EPUB format assumptions** → new `docs/EPUBParsing.md` (P2 backlog)

### Readium migration — `readium-migration` only (see `READIUM_MIGRATION_NOTES.md`)
- **T-20 · Phase-4 interaction polish** — auto-hide chrome on scroll, custom
  page-turn animation, safe-area inset tuning. (Notes ▸ Migration status, Phase 4 = partial.)
- **T-21 · Typography calibration** — match Readium sepia/`backgroundColor` to the
  app's; spacing/margin/bold scale; verify a real imported custom font. (Notes §5.)

### Bugs
- _No active bugs._ ↳ [`docs/Bugs.md`](docs/Bugs.md).

---

## ✅ Completed (recent — newest first)

| ID | Task | Owner | Branch(es) | SHA (main / readium-migration) | Date |
|----|------|-------|------------|--------------------------------|------|
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
- **Open — before going public:** scrub the Apple `DEVELOPMENT_TEAM` ID from
  `project.pbxproj`.
- **Open — migration (`READIUM_MIGRATION_NOTES.md` §6):** consolidate Library
  metadata on Readium vs keep the custom OPF layer? Verify a real imported custom
  font (TTF)? Match Readium's sepia to the app's exactly?
- **Cleanup:** `test/card-lists` is abandoned/polluted and local-only — delete it
  eventually; never merge it.

---

## ↩️ Context for the next session

- **P0** (lint, error handling, tests) and **P1 #5 / #6 / #8** are **done on both
  branches and pushed**; both branches are in sync with `origin`.
- Natural next pickups: T-15, T-17, or Readium Phase-4 polish (T-20 / T-21).
- Quick commands — Build: `xcodebuild … CODE_SIGNING_ALLOWED=NO` · Test:
  `Scripts/test.sh` · Lint: `Scripts/lint.sh`.
