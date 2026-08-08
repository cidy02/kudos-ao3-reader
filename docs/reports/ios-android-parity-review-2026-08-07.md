# iOS ↔ Android parity review — 2026-08-07

**Trees reviewed:** `hig-review` @ `e9ed0c6a` (worktree `.claude/worktrees/hig-review-reference`, iOS source root `kudos-ao3-reader/`) · `android/exclusion-parity` @ `a5a46116` (worktree `.claude/worktrees/android-exclusion-parity`, Android source root `android/app/src/main/java/io/github/cidy02/kudos/`)

> Note on the Android branch name: the review prompt names the branch
> `kudos-ao3-reader-android`. The worktree at `.claude/worktrees/android-exclusion-parity`
> is checked out on `android/exclusion-parity` @ `a5a46116` — which is the exact SHA the
> prompt cites, so this is the intended tree under a different branch label.

**Method:** see *Method log* at the foot of this file. Updated as work proceeds.
**Status:** in progress

**Confirmed sizes** (`find | wc -l`, run 2026-08-07): iOS 214 Swift sources + 85 test
files; Android 281 Kotlin sources + 93 test files. Both match the prompt's figures.

---

## Progress ledger

**Resume here:** Batches A (areas 2–8, AO3 network surface) and B (areas 9–15, app data
surface) are dispatched and running as multi-agent reviews; their findings are not yet
merged into this file. Batch C (areas 1, 16–21) is **not yet dispatched** — that is the
next action if picking this up cold, followed by merging whatever A and B produced.
Areas 17 and 21 already have verified material in this file (see the re-check table and
the Asymmetric test coverage section); do not redo those two checks.

| # | Area | iOS roots | Android roots | Status | Findings | Notes |
|---|---|---|---|---|---|---|
| 1 | Onboarding & first run | `Features/Onboarding/`, `App/MyApp.swift`, `App/ContentView.swift` | `onboarding/`, `app/` | ⬜ not started | – | |
| 2 | Auth / session / cookies | `Services/AO3AuthService.swift`, `AO3SessionVault.swift`, `AO3WebLoginCoordinator.swift`, `AO3RedirectCookieRelay.swift`, `Features/Auth/` | `auth/` | ⬜ not started | – | |
| 3 | Networking core (pacing, retry, coalescing, errors, URL resolution) | `Services/AO3Client.swift`, `AO3RequestCoordinator.swift`, `RequestCoalescer.swift`, `AO3URLResolver.swift` | `network/ao3/` (root files) | ⬜ not started | – | prior art: `docs/reports/ao3-networking-review*.md` (iOS-only) |
| 4 | Search + filters + tag autocomplete + saved searches | `Features/Search/`, `Models/SavedSearch.swift` | `search/`, `network/ao3/search/` | ⬜ not started | – | `filter-parity-2026-08-07.md` covers endpoints only |
| 5 | Browse (category → fandom → works) + fandom catalog | `Features/Browse/`, `Features/Search/FandomCatalog*.swift` | `browse/`, `network/ao3/browse/` | ⬜ not started | – | |
| 6 | Work detail + write actions (kudos/bookmark/subscribe) | `Features/WorkDetail/`, `Services/AO3WriteActions.swift` | `works/WorkDetailScreen.kt`, `network/ao3/writes/` | ⬜ not started | – | |
| 7 | Comments (threads, drafts, posting) | `Features/Comments/`, `Services/AO3Client+Comments.swift`, `AO3CommentActions.swift`, `CommentSubmission.swift` | `comments/`, `network/ao3/comments/` | ⬜ not started | – | |
| 8 | Author profile + series | `Features/Authors/`, `Services/AO3AuthorProfileService.swift`, `AO3Client+Authors.swift` | `author/`, `network/ao3/author/`, `network/ao3/series/` | ⬜ not started | – | |
| 9 | Reader(s) | `Features/ReaderReadium/`, `Features/Reader/`, `Reading/` | `reader/` (+ `readium/`, `settings/`, `speech/`) | ⬜ not started | – | iOS has two readers (Readium iOS / legacy macOS); Android one |
| 10 | Library / collections / queues / stats / recently deleted | `Features/Library/`, `Services/ReadingQueueService.swift` | `library/` | ⬜ not started | – | T-193 known divergences live here |
| 11 | Home | `Features/Home/` | `home/` | ⬜ not started | – | |
| 12 | Account / inbox / dashboard / AO3 preferences | `Features/Account/`, `Services/AO3Client+Inbox.swift`, `AO3InboxActions.swift`, `AO3Client+Preferences.swift` | `account/`, `network/ao3/inbox/`, `network/ao3/preferences/` | ⬜ not started | – | |
| 13 | Import / conversion / EPUB pipeline | `Services/WorkImporter.swift`, `*WorkConverter.swift`, `Reading/` | `works/converters/`, `works/WorkImporter.kt`, `files/` | ⬜ not started | – | |
| 14 | Backup / restore / folder sync | `Services/KudosBackup*.swift`, `PersistenceSync.swift`, `FolderSyncService.swift` | `backup/` | ⬜ not started | – | contract doc: Android `docs/contracts/BACKUP_FORMAT.md` |
| 15 | Persistence + migrations (SwiftData vs Room) | `Models/Models.swift` | `data/local/` (`entity/`, `dao/`, `KudosDatabaseMigrations.kt`) | ⬜ not started | – | |
| 16 | Settings / theming | `Settings/`, `App/ThemeManager.swift` | `settings/`, `data/preferences/`, `ui/theme/` | ⬜ not started | – | |
| 17 | Update system | (none expected) | `update/`, `network/github/` | ⬜ not started | – | Android-only; confirm iOS truly has none |
| 18 | Support / bug report / shake | `Features/Support/` | `support/` | ⬜ not started | – | |
| 19 | Error handling & empty states | cross-cutting | cross-cutting | ⬜ not started | – | |
| 20 | Accessibility | cross-cutting | cross-cutting | ⬜ not started | – | |
| 21 | Test coverage asymmetry | `KudosTests/` (85) | `android/app/src/test`, `androidTest` (93) | ⬜ not started | – | |

Legend: ⬜ not started · 🔄 in progress · ✅ done · ⏭️ skipped (reason in Notes)

---

## Summary

*Stub — written last, once there is enough confirmed material to say something true.*

---

## Findings

*None confirmed yet.*

---

## Bugs present on both platforms

*None confirmed yet.*

---

## Asymmetric test coverage

Partially assessed. The shape of the two suites, established by direct enumeration:

| | iOS | Android |
|---|---|---|
| Test files | 85 under `KudosTests/` | 93 under `android/app/src/test/` |
| Test targets / source sets | one target, `KudosTests` (only `name = KudosTests;` appears in `AO3_App_OpenSource.xcodeproj/project.pbxproj`) | one source set, `src/test` (JVM) |
| UI / instrumented tests | **none** — no UI-test target, and `grep -rl XCUIApplication KudosTests` → zero hits | **none** — `android/app/src/androidTest/` does not exist |
| UI-test dependency declared | n/a | yes — `androidTestImplementation(libs.androidx.compose.ui.test.junit4)` at `android/app/build.gradle.kts:110`, plus the Compose BOM at `:77` |
| Android-framework simulation in unit tests | n/a | Robolectric (`android/app/build.gradle.kts:117`), used by ≥10 unit tests incl. `ReaderViewModelPreferencesTest.kt`, `CommentsViewModelDraftTest.kt`, `RoutesNavigationTest.kt`, `ThemeTest.kt` |

Two observations follow, and they point in opposite directions:

1. **Neither app has a single UI-level test.** This is a *shared* gap, not an asymmetry —
   every screen on both platforms is verified only by the human screenshot gate that
   `AGENTS.md` mandates. It is recorded here rather than in Findings because it is a
   property of the project's testing strategy, not a divergence between the two apps.
2. **Android declares an instrumented-test dependency it never uses.**
   `androidTestImplementation(libs.androidx.compose.ui.test.junit4)` is resolved on every
   build for a source set that does not exist. That is dead build configuration —
   `minor`, and worth deleting or filling.

The per-rule comparison (which behavioural rules are pinned by a test on one platform and
left unpinned on the other) is **not yet done** — it is the substance of this section and
belongs to area 21, which has not been dispatched.

---

## Already-known divergences, re-checked

The calibration list from the review prompt. Status filled in as each area is reached.

| Known divergence | Recorded in | Re-checked? | Status |
|---|---|---|---|
| "Show zero counts" (Settings → Library) is iOS-only; Android always shows zeros | `TASKS.md` T-193 | ⬜ | |
| Android's `SavedWork` has no `bookmarks` column | `TASKS.md` T-193 | ⬜ | |
| Compose `FlowRow` applies `SpaceBetween` to a wrapped last row; iOS leaves it ragged | `TASKS.md` T-193 | ⬜ | |
| iOS ships two readers (Readium iOS / legacy macOS); Android has one | prompt | ⬜ | |
| Android has a GitHub-backed self-update system; iOS has none | prompt | ✅ | **Still true.** `grep -rniE "appUpdate\|checkForUpdate\|releases/latest\|api\.github\.com\|installUpdate\|AppUpdateRepository" kudos-ao3-reader --include="*.swift"` returns exactly two hits, both `WorkUpdateChecker` — which checks *AO3 works* for new chapters (`Services/WorkUpdateChecker.swift:17`, called from `Features/Home/HomeView.swift:134`), not the app. iOS has no app-update path of any kind. Android's lives in `update/` + `network/github/`. |

---

## Open leads

*Nothing is ever deleted from this section — leads are promoted to Findings or moved
to Ruled out with a reason.*

**L-1 — the Android branch's in-tree copy of the iOS app is 122 files behind.**
Suspicion: Android work is being ported against a stale iOS reference, so "parity"
decisions recorded on the Android branch may be parity with an iOS that no longer
exists. Where seen: `find .claude/worktrees/android-exclusion-parity/kudos-ao3-reader
-name '*.swift' | wc -l` → **92**, versus **214** in `hig-review-reference`. The check
that settles it: diff the file lists, then confirm whether any Android-side doc or
task cites iOS behaviour that `hig-review` has since changed. This is a process
finding, not a user-visible one — it is recorded here because it predicts *where*
user-visible drift will be found.

---

## Ruled out

*None yet.*

---

## Not covered

*Filled in as areas are closed or skipped. Currently: everything.*

---

## Method log

Chronological record of what was actually done, so a cold reader can judge the
evidence rather than trust the conclusions.

### 2026-08-07 — scoping pass (no source files read yet)

- Confirmed both worktrees exist at the SHAs the prompt names (`git worktree list`):
  `hig-review-reference` @ `e9ed0c6a`, `android-exclusion-parity` @ `a5a46116`.
- Read `AGENTS.md`, `docs/AGENT_ONBOARDING.md`, `docs/ADVERSARIAL_REVIEW_TEMPLATE.md`
  in the `hig-review` tree.
- `TASKS.md` in `hig-review` is 530 lines / 450 KB (very long rows). Indexed rather
  than read linearly: `grep -oniE '(android|parity|deferred|not ported|port to)…'`
  shows Android/parity material concentrated in rows 24, 26, 30, 61, 64, 75, 78, 82,
  87, 93, 116, 241, 262, 382. Full-text search against `TASKS.md` is the required
  check before any finding is reported.
- Enumerated both source trees to build the area map above (`ls` per package).
- **Noted for the record:** the Android worktree carries its own, divergent `docs/`
  tree (`docs/audits/`, `docs/contracts/`, `docs/Android_Parity_Review_2026-08-04.md`,
  `docs/iOS_Issues_Found_While_Porting.md`) that the `hig-review` tree does not have,
  and `hig-review`'s `docs/reports/` does not exist on the Android branch. It also
  contains a **stale copy of the iOS app**: 92 Swift files under `kudos-ao3-reader/`
  versus 214 in `hig-review`. Anyone comparing "iOS" from inside the Android worktree
  is comparing against a much older iOS. Recorded as Open lead L-1.
- No source file has been read yet; no suite has been run. Nothing below is claimed
  as verified until it carries file:line evidence on both platforms.
