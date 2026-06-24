# AGENTS.md — How AIs work on Kudos

> **Read this file, [`TASKS.md`](TASKS.md), and [`README.md`](README.md) before editing any code.**
> This project is worked on by multiple AIs (Claude, Codex) plus the human owner.
> This file is the contract that keeps us from clobbering each other's work.

## Project in one paragraph

Kudos is a native **SwiftUI + SwiftData** reader for Archive of Our Own, targeting
**iOS / iPadOS / macOS** (GPL-3.0). It scrapes AO3's public HTML with SwiftSoup
(AO3 has no API), imports works as EPUBs, and reads them in a native reader. See
[`README.md`](README.md) for features and build instructions, and
[`docs/PROJECT_PHILOSOPHY.md`](docs/PROJECT_PHILOSOPHY.md) for the product
direction, design/engineering principles, and the final guiding principle every
contribution is measured against.

## Branch — single `main`

The project is a **single `main` branch** (origin default; private
`github.com/cidy02/kudos-ao3-reader`). A `main` (legacy) / `readium-migration` split
existed during the reader migration; it was **consolidated into `main` in June 2026**,
and all other branches (`readium-migration`, `test/card-lists`, etc.) were deleted.
Just commit to `main` — there is no more cross-branch porting / cherry-picking.

**Reader (per-platform, one codebase):** `BookReaderView` routes **iOS → Readium**
(`Features/ReaderReadium/`, the Readium Swift Toolkit) and **macOS → the legacy
WKWebView reader** (`Features/Reader/ReaderView.swift` + `ReaderController.swift`, which
are `#if os(macOS)`-guarded, so they're excluded from iOS). Readium's navigator is
UIKit-only, hence the macOS fallback. Readium SPM products are scoped `platformFilter = ios`.

## Roles & responsibilities

**Human (cidy02)** — owns product decisions, final approval, and anything
outward-facing (GitHub auth, repo visibility, releases). Tiebreaker on conflicts.
**Ask the human before:** publishing/going public, force-pushing, deleting
branches, or changing the bundle id / signing / `DEVELOPMENT_TEAM`.

**Claude** — broad scope: features, refactors, test/lint/CI tooling, simulator
verification (screenshots), git operations, and keeping `TASKS.md` + project
memory current. Maintains persistent project memory across sessions.

**Codex / other coding models** — focused implementation of a **single claimed
task**. ⚠️ *History:* an earlier Codex session copied the whole Readium migration
onto `test/card-lists` and reverted other agents' UI work — the rules below exist
to prevent a repeat. If you are Codex: **claim one task in `TASKS.md`, stay on its
branch, touch only its files, and never revert another agent's commits.**

## Before you touch code (mandatory)

1. Read **`AGENTS.md`** (this), **[`TASKS.md`](TASKS.md)**, **[`README.md`](README.md)**.
2. The bug / feature-idea / UI-polish trackers are now consolidated **into
   [`TASKS.md`](TASKS.md)** (the Bugs / Feature Ideas / UI Polish registries).
3. If your work touches the reader or the migration, read
   **`READIUM_MIGRATION_NOTES.md`** (gitignored, local-only — ask the human if absent).
4. Run `git status` + `git branch --show-current`. Know where you are and that the
   tree is clean before you start.
5. **Claim your task in `TASKS.md`** (set `Owner` + `🔄 IN PROGRESS`) before editing.
   If a task is already in progress under another owner, pick a different one.

## Git workflow

- **One task = one owner = one logical change.** Commit when it builds + tests pass;
  don't sit on a large uncommitted diff.
- **Commit messages:** imperative subject; short body explaining *why*; end with
  your own co-author trailer, e.g.
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **Branching:** work directly on **`main`** for normal tasks (the human prefers this
  to PR branches for a solo repo). Use a feature branch only for a risky/large spike,
  and say so in `TASKS.md`. (No more cross-branch porting — single branch.)
- **Pushing:** push as you go (`git push origin main`) unless told to batch.
  A `could not resolve host` failure is a transient DNS hiccup — just retry.
- **Verify before commit:** `Scripts/lint.sh` (SwiftLint gate) and `Scripts/test.sh`.
  Build **both** iOS (resolves the Readium SPM graph) and **macOS** (legacy reader,
  no Readium) before claiming a cross-platform change is done. Build with
  `CODE_SIGNING_ALLOWED=NO` for the simulator.

## `project.pbxproj` — handle with care (top conflict source)

The project uses `objectVersion = 90` with **deterministic IDs** and
**file-system-synchronized groups**.

- **Adding a Swift file? Do NOT edit `project.pbxproj`.** Files under
  `kudos-ao3-reader/` and `KudosTests/` are auto-included by the synchronized group.
- **xcodebuild/Xcode rewrites `project.pbxproj` cosmetically on build** (app
  name/path, quote removal, key reordering). If you did **not** intentionally
  change the project, revert that churn before staging:
  `git checkout -- AO3_App_OpenSource.xcodeproj/project.pbxproj`.
- **Adding a target or build phase** needs careful hand-editing — mirror the app
  target and use the `…5xxxxx` ID block to avoid collisions. This is high-conflict:
  note it in `TASKS.md` and let **one** agent own pbxproj changes at a time.
- The project has the Readium SPM products (`platformFilter = ios;`) and a Run Script
  that strips Readium bundle xattrs — don't clobber these.

## Sensitive / never-commit

- Build artifacts: `build/`, `DerivedData/`, `*.ipa`, `*.dSYM` (gitignored — keep it so).
- Local-only notes: `READIUM_MIGRATION_NOTES.md`, `*_NOTES.md`, `*prompt*` (gitignored).
- The repo is **public**. The Apple `DEVELOPMENT_TEAM` in `project.pbxproj` is
  scrubbed to `""` — keep it empty when you commit (Xcode re-adds your team locally
  under Automatic signing; don't commit that back).
- Never commit secrets/tokens or personal identifiers. The repo is public.

## Handoff protocol — leave work pickup-ready

When you stop (finished, blocked, or out of context), do **all** of:

1. **Land the code** — commit working changes (build + tests green). If you must stop
   mid-change, commit as `WIP: …` and state exactly what's unfinished.
2. **Clean tree** — `git status` shows no stray edits (revert pbxproj churn).
3. **Update `TASKS.md`** — move your task's status (→ `✅ DONE` / `⛔ BLOCKED` /
   `✋ HANDOFF`), record the commit SHA(s) + branch, and write a one-line **Next
   step** and any **open question**.
4. **Push** (if push-as-you-go) and note in `TASKS.md` whether the change still
   needs **porting** to the other branch.
5. Don't leave another agent's in-progress files half-edited.

The next agent should continue from `TASKS.md` + your commit with **zero archaeology**.

## Conventions that reduce context loss

- Prefer small, reviewable commits over big drops.
- Match the surrounding code style. The codebase is **hand-wrapped**; SwiftFormat is
  **advisory, not enforced** — do not bulk-reformat.
- Keep the **`TASKS.md`** registries current: move fixed bugs to the Bugs registry,
  and update the Feature Ideas / UI Polish registries as items land.
- When you verify UI in the simulator, say what you saw (and how) in the commit body
  or `TASKS.md`.

  ## UI Consistency
  - UI modernization must preserve or improve information density, a visually cleaner design that reduces scanability or hides metadata is considered a regression unless explicitly approved.
    - New UI elements should be consistent with existing elements, unless explicitly approved.
