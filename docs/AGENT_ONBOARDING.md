# AGENT_ONBOARDING.md — read before coding

Operational doc for AI agents. Facts below are **confirmed against the codebase as of 2026-07-07** unless marked *(inferred)* or *(unknown)*. Deeper docs: [ARCHITECTURE_MAP.md](ARCHITECTURE_MAP.md) · [DATA_AND_PERSISTENCE_INVARIANTS.md](DATA_AND_PERSISTENCE_INVARIANTS.md) · [AO3_NETWORKING_POLICY.md](AO3_NETWORKING_POLICY.md) · [REGRESSION_TEST_MATRIX.md](REGRESSION_TEST_MATRIX.md).

## What Kudos is

Native SwiftUI + SwiftData reader for Archive of Our Own (iOS/iPadOS/macOS, GPL-3.0). Scrapes AO3's public HTML with SwiftSoup (no official API), downloads works as EPUBs, reads them natively. Unofficial; not affiliated with OTW/AO3 (README.md:139). Single app target `AO3_App_OpenSource`, product name `Kudos`, bundle `com.cidy02.Kudos`, scheme `AO3_App_OpenSource`.

## High-level architecture

- **UI**: SwiftUI, 4 tabs + global Search (`App/ContentView.swift` TabView; routing via `AppRouter`).
- **Models**: all `@Model` classes in `Models/Models.swift` (`SavedWork`, `WorkCollection`, `ReadingQueue`, `ReadingQueueMembership`, `Tag`, `Bookmark`, `CustomFont`, `SavedSearch`, `SyncTombstone`). Remote value types in `Models/AO3Models.swift`.
- **Services**: `Services/` — one file per concern (see ARCHITECTURE_MAP).
- **Reader**: iOS → Readium (`Features/ReaderReadium/`); macOS → legacy WKWebView reader (`Features/Reader/`, `#if os(macOS)`). Readium SPM products are `platformFilter = ios`.
- **Concurrency**: `@MainActor` almost everywhere that touches SwiftData; `AO3Client` is an actor.

## Platform constraints

| Constraint | Detail |
|---|---|
| Xcode | Xcode-beta at `/Applications/Xcode-beta.app` is the active toolchain (`xcode-select -p`). `Scripts/build-macos.sh` pins a stable build for macOS. |
| Test destination | `platform=iOS Simulator,name=iPhone 17,OS=26.5` (canonical, used in TASKS.md verification notes). |
| Parallel tests | **Disabled** (`Scripts/test.sh` passes `-parallel-testing-enabled NO`): `PersistenceOperationGate` is a process-wide static lock; parallel suites contend it and flake. Persistence-touching suites are `@Suite(.serialized)`. |
| Signing | Simulator/tests: `CODE_SIGNING_ALLOWED=NO`. Device builds need a team in Xcode's Accounts pane. ⚠️ Policy drift: AGENTS.md says keep `DEVELOPMENT_TEAM` scrubbed to `""`, but commit `bcfe335`'s follow-ups carry `NQH85H7343` — human decision pending; don't "fix" either way without asking. |
| Release config | Historical: Release builds once crashed the beta Swift compiler in vendored SwiftSoup (T-66 note). Verify before assuming Release works. |

## Branch / workflow rules (supersedes AGENTS.md's old "just commit to main")

- `main` = last human-approved state. **Do not commit directly to it.**
- `merge-test` = integration branch (linear chain of every feature since T-65). Features stack on the latest tip: `merge-test` ← `indexing-implementation` ← `release-hardening` (current tip).
- One focused branch per feature/fix pass; a `TASKS.md` row (T-xx) per branch with verification evidence; adversarial review before merge.
- **UI approval gate** (TASKS.md, "UI Consistency & Density Audit"): UI changes need human screenshot review before merging to `main`. Do not merge to `main` yourself.
- `kudos-ao3-reader-android` is a separate product line — never merge it.

## Common pitfalls (each cost a real debugging session)

| Pitfall | Rule |
|---|---|
| `isDeleted` on `@Model` | Collides with CoreData's reserved `NSManagedObject.isDeleted`; silently resets on save. Use `isPendingDeletion`. Backup JSON key stays `isDeleted` (plain Codable structs are fine). |
| Multiple `.fileImporter` on one view node | Only one file-dialog presenter per node; siblings silently fail. SettingsView uses ONE enum-driven importer (`FileImportKind`) — extend it, never add a sibling. |
| Actor ≠ serial | Actors are reentrant across `await`. `AO3Client` politeness comes from `pace()` (slot-claiming, ≥0.6s between request starts), not from being an actor. |
| Fire-and-forget `Task {}` touching `@Model` | Model may be invalidated before/while the task runs → SwiftData assertion crash. Guard `work.modelContext != nil` at entry AND after awaits (see `WorkTags.refreshFromAO3`, `WorkSearchIndex.rebuildIfNeeded`, `PersistenceMigrationService`). |
| `.iso8601` JSON dates | Truncate to whole seconds → merge decisions become unorderable. `KudosBackup` uses a fractional-seconds encoder with whole-second decode fallback. Don't change either direction. |
| Per-request headers | Override session-level `httpAdditionalHeaders`. The User-Agent is single-sourced in `AO3RequestDefaults.userAgent` — never define a second UA. |
| `project.pbxproj` | File-system-synchronized groups: adding Swift files needs **no** pbxproj edit. Revert cosmetic churn before staging. Info.plist array keys are injected by a Run Script phase (PlistBuddy) — `INFOPLIST_KEY_*` can't express arrays. |
| `remove`-then-write | Never delete a destination before writing its replacement (sync package destruction window). Stage to `itemReplacementDirectory` (same volume — EXDEV) + `replaceItemAt`. |
| Reindex ≠ edit | `WorkSearchIndex.reindex` must never call `markModified()` — derived state must not win sync merges. |
| OSLog in closures | `OSLogMessage` interpolation may require explicit `self.` for captured values (T-65). |
| Sepia theme | New List/Form screens need `.appThemedScroll()` / `.appThemedRows()` or they render wrong under Sepia. |
| Unstructured `Task {}` in views | SwiftUI never cancels them — store in `@State` and cancel in `.onDisappear` for long/network work. |

## Definition of done (all of it, before saying "done")

1. **`Scripts/verify.sh`** — the whole gate in one command: mechanical invariants (`Scripts/check-invariants.sh`) → lint → full iOS suite → macOS build → `git diff --check`. All green, no exceptions. (iOS-only APIs must be `#if os(iOS)`-guarded or step 4 fails.)
2. New behavior has tests (see REGRESSION_TEST_MATRIX for suite placement). Suite count only goes up (216 tests / 29 suites as of T-74).
3. If your change makes any statement in `docs/*.md` false, update that doc **in the same commit** — stale docs become hallucination sources (this file's own AGENTS.md predecessor rotted exactly that way).
4. `TASKS.md` row updated with what was verified and what remains **manual** — honesty about unverified device/UI behavior is a project convention.
5. Merge-bound branches get an adversarial review per [`ADVERSARIAL_REVIEW_TEMPLATE.md`](ADVERSARIAL_REVIEW_TEMPLATE.md). Multi-part work should be prompted per [`TASK_PROMPT_TEMPLATE.md`](TASK_PROMPT_TEMPLATE.md).
6. UI changes: the human screenshot gate still applies; don't claim visual correctness you didn't see.
7. **Reporting discipline:** every finding or implementation claim cites the exact file/function/class involved. Never state "the app currently does X" unless you verified it in code this session — recalled or inferred behavior is labeled as such. Numbers (test counts, line refs) come from command output, not estimation.
