# Android sync from hig-review — findings & implementation

**Date:** 2026-07-31  
**Android branch:** `android/sync-from-hig-review`  
**Base:** `origin/kudos-ao3-reader-android` @ `bc54528`  
**iOS source of truth:** `hig-review` @ `29cd915`  
**Worktree:** `.claude/worktrees/android-sync-hig-review`  
**Method:** product-behavior port (not git merge). The iOS and Android trees are
not mergeable; this branch ports portable UX rules from hig-review into Compose.

> **Never merge** `kudos-ao3-reader-android` (or this sync branch) into `main`.
> Android remains a separate product line.

---

## 1. Executive summary

| Item | Result |
|---|---|
| Git merge of hig-review → Android | **Not applicable** (different platform tree) |
| Gap inventory | Complete (explore agent + manual review) |
| High-value portable ports | **Implemented** on this branch |
| Full feature parity with hig-review | **Not claimed** — large features remain deferred |
| Verification | Unit tests for stats helpers; see §6 |

This pass closes the most user-visible **reader-first** and **card density** gaps
introduced on iOS during the HIG / cover-card waves, expressed in Material 3.

---

## 2. Branch divergence (why not a merge)

```
hig-review (iOS)     29cd915  — SwiftUI, SwiftData, Readium iOS, HIG waves 1–10+
kudos-ao3-reader-android
                     bc54528  — Compose, Room, Readium Android, Phases 0–12
```

Shared product meaning lives in `docs/contracts/*`. Code is reimplemented per
platform. “Bring Android up to date” means:

1. Inventory portable product rules from hig-review tip.
2. Port those that Android can express without inventing new backend features.
3. Document remaining gaps for follow-up tasks.

---

## 3. What Android already had (baseline @ bc54528)

From `docs/contracts/UI_PARITY_CHECKLIST.md` and the Android phase plan:

| Surface | Status before this branch |
|---|---|
| Home / Library / Browse / Account + Search | Present |
| Work Detail + download lifecycle | Present |
| Readium reader + progress restore | Present |
| AO3 auth, account lists, writes, comments | Present |
| Privacy obscuring for mature works | Present |
| Local cards open | **Button-first** (Details + Read) |
| Stats on cards | Chip rows with prose labels |
| Reader open UX | Centered `CircularProgressIndicator` |
| Home shelf density | 4 cards × 300.dp |

---

## 4. hig-review product rules that drove this pass

### 4.1 Compact card open rule (`f1f2844`)

> Every compact cover card **reads** … The ⓘ is how you reach Work Details …

| Card kind | Primary tap | Secondary |
|---|---|---|
| Local compact (Home / Library) | Reader if EPUB available | ⓘ → Work Detail |
| Local without EPUB / obscured | Work Detail | ⓘ → Work Detail |
| Remote AO3 compact (iOS full rule) | Download-then-read | ⓘ → Detail |
| Detailed list rows | Work Detail (unchanged on iOS) | — |

### 4.2 Cover-card stats (`436d65f`)

- One stat per row (not flow-wrap of chips).
- Spelled-out nouns: `"12K words"`, `"3/5 chapters"`, not bare numbers.
- Rating middle length: `"Teen"` not `"T"` / not full AO3 string.
- Completion: `"In Progress"` not `"WIP"`.

### 4.3 Reader open skeleton (`5f2c3a8`)

- Full-page themed skeleton; no system-background flash; no spinner competing
  with first page paint.
- Android cannot share SwiftUI/Readium iOS chrome gating; we port the *loading*
  surface: skeleton replaces centered spinner on open.

### 4.4 Explicitly not ported this pass

| hig-review feature | Why deferred |
|---|---|
| Remote card → download-into-reader | Needs open-path import orchestration on Android |
| Zoom transition card ↔ reader | Platform-specific navigation animation |
| Peel dismiss / Liquid Glass | iOS-only chrome |
| Home Subscriptions / Recently Updated | AO3-backed Home shelves |
| Author profiles, Inbox, non-EPUB | Separate feature tracks |
| List skeletons (Search/Browse/Account) | Follow-up polish |
| Full reader settings / custom fonts | Phase 7 partial |
| Cover hue art | Visual polish |

---

## 5. What we implemented

### 5.1 Local card tap → reader (Home + Library)

**Files:**

- `android/.../home/HomeScreen.kt` — `HomeWorkCard`
- `android/.../library/LibraryScreen.kt` — `SavedWorkCard`, `CompactWorkRow`

**Behavior:**

```text
if (hasEpub && Visible) → onOpenReader
else                     → onOpenWork   // detail / download / mature gate
ⓘ button                 → onOpenWork   // always Work Detail
```

Removed equal-weight **Details** / **Read** button rows on these cards. Nav
wiring in `AppNavHost` was already correct; no route changes.

### 5.2 Remote AO3 cards: whole-card open → Work Detail

**File:** `android/.../ui/components/AO3WorkCard.kt`

- `Card(onClick = { onOpenWork(work) })`
- ⓘ secondary control (same destination for now)

**Not yet:** download-then-read for remote summaries (true hig-review compact
rule). Documented as next Android task once open-path import is designed.

### 5.3 Cover-card stats column

**New:** `android/.../ui/components/WorkStats.kt`

- `CoverCardStatsColumn` + `WorkStatItem`
- Pure helpers: `ratingDisplayName`, `chapterStatText`, `wordStatText`,
  `completionStatText`

**Wired into:** `HomeWorkCard`, `SavedWorkCard`, `AO3WorkCard`.

Local status (Downloaded / Favorite / Finished) stays as chips; AO3 stats move
to the one-per-row column.

### 5.4 Reader opening skeleton

**New:** `android/.../ui/components/ReaderPageSkeleton.kt`  
**Wired:** `android/.../reader/ReaderScreen.kt`

- `ReaderUiState.Loading` → `ReaderPageSkeleton("Opening…")`
- Readium open-null phase → `ReaderPageSkeleton("Opening “title”…")`
- Uses theme `background` (no black flash); fills height; quiet caption
- Centered spinner path removed for open states (errors still use buttons)

### 5.5 Home shelf density

| | Before | After |
|---|---|---|
| `HomeShelfLimit` | 4 | **12** (matches iOS carousel prefix scale) |
| Card width | 300.dp | **240.dp** (tighter after removing dual CTAs) |

### 5.6 Tests

**New:** `android/app/src/test/.../ui/components/WorkStatsTest.kt`

- Rating shortening, chapter/word spelling, completion wording.

---

## 6. Verification

| Check | Result |
|---|---|
| `./gradlew :app:compileDebugKotlin` | **PASS** (2026-07-31, Android Studio JBR 21) |
| `WorkStatsTest` | **PASS** (`:app:testDebugUnitTest --tests …WorkStatsTest`) |
| Full unit suite | Recommended before merging into android tip |
| Device / TalkBack visual | **Manual** — card tap, ⓘ, skeleton open |
| iOS build | N/A (Android-only branch) |

Manual checklist for human:

1. Home: tap downloaded work → Reader; tap ⓘ → Work Detail.
2. Library compact + full cards: same rule.
3. Search / Browse / Account cards: tap → Work Detail.
4. Open Reader on a large EPUB: skeleton fills screen, themed, no spinner flash.
5. Mature-obscured cards still do not expose title/author via TalkBack on Home
   (pre-existing fix @ bc54528).

---

## 7. Remaining gap inventory (post-pass)

Priority for future Android tasks:

| P | Gap | Notes |
|---|---|---|
| P0 | Remote compact → download-then-read | True parity with `f1f2844` |
| P1 | List/card skeletons for Search/Browse/Account | Perceived performance |
| P1 | Missing-EPUB restore phase copy | iOS “Restoring EPUB…” path |
| P2 | Home Subscriptions + Recently Updated | Needs signed-in AO3 on Home |
| P2 | Advanced Search filters UI | Models already exist |
| P3 | Authors, Inbox, non-EPUB, bulk select | Product features |
| P3 | Reader chrome polish / settings complete | Readium UX |
| — | Zoom / peel / Liquid Glass | Do not port |

---

## 8. File change map

| Path | Change |
|---|---|
| `ui/components/WorkStats.kt` | **New** — stats helpers + column |
| `ui/components/ReaderPageSkeleton.kt` | **New** — open skeleton |
| `ui/components/AO3WorkCard.kt` | Card click + stats column + ⓘ |
| `home/HomeScreen.kt` | Reader-first card, stats, shelf density |
| `library/LibraryScreen.kt` | Reader-first cards/rows, stats, ⓘ |
| `reader/ReaderScreen.kt` | Skeleton open path |
| `test/.../WorkStatsTest.kt` | **New** unit tests |
| `docs/audits/ANDROID_HIG_REVIEW_SYNC.md` | **This report** |

---

## 9. Suggested follow-up task text (for TASKS.md)

```text
Android: remote compact cards open for reading (download-then-read), matching
hig-review f1f2844. Register a single open-path importer so Search/Browse/
Account cards can land in the reader when the work is not yet local; keep ⓘ
for Work Detail. Branch off android/sync-from-hig-review or the then-current
kudos-ao3-reader-android tip.
```

---

## 10. Sources (iOS commits consulted)

| SHA | Topic |
|---|---|
| `f1f2844` | One rule for compact cards: tap opens the work |
| `436d65f` | Cover-card stats: one per row, values spelled out |
| `5f2c3a8` | Reader open is skeleton-only |
| `3d5765d` | Account-tab cards open the work |
| `29cd915` | hig-review tip (zoom iOS-only compile fix) |

Contracts: `UI_PARITY_CHECKLIST.md`, `CROSS_PLATFORM_UI_BRIDGE.md`,
`KUDOS_ANDROID_INTERFACE_GUIDELINES.md`.
