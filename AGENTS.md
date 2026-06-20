# AGENTS.md — How AIs work on Kudos

> **Read this file, [`TASKS.md`](TASKS.md), and [`README.md`](README.md) before editing any code.**
> This project is worked on by multiple AIs (Claude, Codex) plus the human owner.
> This file is the contract that keeps us from clobbering each other's work.

## Project in one paragraph

Kudos is a native **SwiftUI + SwiftData** reader for Archive of Our Own, targeting
**iOS / iPadOS / macOS** (GPL-3.0). It scrapes AO3's public HTML with SwiftSoup
(AO3 has no API), imports works as EPUBs, and reads them in a native reader. See
[`README.md`](README.md) for features and build instructions.

## Branches — read carefully

| Branch | What it is | Rule |
|---|---|---|
| `main` | Stable **legacy** reader (custom WKWebView + `EPUB.swift` parsing). | Default branch. General work starts here. |
| `readium-migration` | The **Readium Swift Toolkit** migration (iOS reader = Readium; macOS still legacy). | Readium-specific work only. |
| `test/card-lists` | ⛔️ **Abandoned & polluted** — Readium code was copied onto it and UI work reverted. | **Never** branch from, edit, merge, or push it. |

`origin` = private `github.com/cidy02/kudos-ao3-reader` (only `main` + `readium-migration` are pushed).

### The golden branch rule

- **General** changes (bug fixes, UI polish, tests, tooling, non-reader features) →
  land on **`main` first**, then port to `readium-migration` (cherry-pick).
- **Readium-specific** changes (anything under `Features/ReaderReadium/`,
  `EPUBPreferences`, the Readium SPM wiring) → **`readium-migration` only**.
- Make a change **once** and cherry-pick it — never re-implement the same change
  independently on both branches (that causes the divergence/merge pain).

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
2. Read the relevant tracker(s): [`docs/Bugs.md`](docs/Bugs.md),
   [`docs/Feature_Ideas.md`](docs/Feature_Ideas.md),
   [`docs/UI_Polish_Todo.md`](docs/UI_Polish_Todo.md).
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
- **Branching:** work directly on `main` / `readium-migration` for normal tasks
  (the human prefers this to PR branches for a solo repo). Use a feature branch
  only for a risky/large spike, and say so in `TASKS.md`.
- **Port `main` → `readium-migration`:** `git checkout readium-migration && git cherry-pick <sha>`.
  Conflicts usually land in `WorkImporter.swift` (it's `async` on that branch) and
  the import call sites — combine `async` + `throws`. Build + test before
  `git cherry-pick --continue`.
- **Pushing:** push as you go (`git push origin <branch>`) unless told to batch.
  A `could not resolve host` failure is a transient DNS hiccup — just retry.
- **Verify before commit:** `Scripts/lint.sh` (SwiftLint gate; currently 0 errors /
  ~38 advisory warnings) and `Scripts/test.sh` (43 tests). Build with
  `CODE_SIGNING_ALLOWED=NO` for the simulator.

## `project.pbxproj` — handle with care (top conflict source)

The project uses `objectVersion = 90` with **deterministic IDs** and
**file-system-synchronized groups**.

- **Adding a Swift file? Do NOT edit `project.pbxproj`.** Files under
  `AO3_App_OpenSource/` and `KudosTests/` are auto-included by the synchronized group.
- **xcodebuild/Xcode rewrites `project.pbxproj` cosmetically on build** (app
  name/path, quote removal, key reordering). If you did **not** intentionally
  change the project, revert that churn before staging:
  `git checkout -- AO3_App_OpenSource.xcodeproj/project.pbxproj`.
- **Adding a target or build phase** needs careful hand-editing — mirror the app
  target and use the `…5xxxxx` ID block to avoid collisions. This is high-conflict:
  note it in `TASKS.md` and let **one** agent own pbxproj changes at a time.
- `readium-migration`'s project has the Readium SPM products (`platformFilter = ios;`)
  and a Run Script that strips Readium bundle xattrs — don't clobber these when
  cherry-picking.

## Sensitive / never-commit

- Build artifacts: `build/`, `DerivedData/`, `*.ipa`, `*.dSYM` (gitignored — keep it so).
- Local-only notes: `READIUM_MIGRATION_NOTES.md`, `*_NOTES.md`, `*prompt*` (gitignored).
- The Apple `DEVELOPMENT_TEAM` ID lives in `project.pbxproj` — fine while the repo is
  **private**; scrub it before going public.
- Never commit secrets/tokens. Treat the repo as if it could go public.

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
- Keep `docs/` trackers current: move fixed bugs to `docs/Bugs.md` ▸ Fixed/Verified;
  tick off items in `docs/Feature_Ideas.md` / `docs/UI_Polish_Todo.md`.
- When you verify UI in the simulator, say what you saw (and how) in the commit body
  or `TASKS.md`.
