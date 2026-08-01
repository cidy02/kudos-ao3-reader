# Remaining iOS ↔ Android feature parity & UI gaps

**Date:** 2026-07-31 (post soft-delete / deferred-epic merge)  
**Android tip (pre-wave):** `android/sync-from-hig-review` @ `c44081b`  
**iOS SoT in worktree:** `kudos-ao3-reader/` (hig-review product rules)  
**Method:** Fresh inventory against current Android tree + prior domain/UI agents.  
**Policy:** Never merge Android into `main`. Port behavior into Compose / MD3.

---

## Honest status

| Area | Status |
|---|---|
| Core reader loop (Library → Detail → EPUB → Readium) | **Roughly done** |
| AO3 auth, account lists, writes, comments, backup v1–v8 merge | **Roughly done** |
| Soft-delete / Recently Deleted / reading queues (data + basic UI) | **Mostly done** |
| Advanced Search filters, saved searches, local tag suggest | **Mostly done** |
| Home AO3 shelves (Subscriptions, Recently Updated) | **Missing** |
| Editable Settings (not read-only rows) | **Missing** |
| Work update checker | **Missing** (fields exist; no poller/UI) |
| Bulk select, download queue banner, reading stats | **Missing** |
| Authors, Inbox, non-EPUB import, folder sync | **Missing** (larger tracks) |
| UI hierarchy (nav icons, CTA weight, dual titles, Library density) | **Partial — still feels different** |

**Complete feature parity is multi-wave.** This document is the living backlog.
Each wave implements a slice, merges to `android/sync-from-hig-review`, runs
`android/Scripts/verify.sh`, then re-ranks.

---

## Product parity matrix

Legend: ✅ done · 🟡 partial · ❌ missing · 🚫 platform-only / out of scope

| Feature (Apple) | Android | Priority | Notes |
|---|---|---|---|
| Home Continue / Favorites / Recent | ✅ | — | Shelves present; density tuned |
| Home **Recently Updated** | ❌ | **P0** | Needs `WorkUpdateChecker` + `hasUpdate` |
| Home **Subscriptions** shelf | ❌ | **P0** | Account list API exists |
| Library shelves + filters | 🟡 | **P0 UI** | Filters dominate; collapse filters |
| Soft-delete / Recently Deleted | ✅ | — | Soft-delete entry on Work Detail |
| Reading queues UI | 🟡 | P1 | List + detail exist; polish membership |
| Bulk select / multi-actions | ❌ | P1 | Library selection mode |
| Work update checker | ❌ | **P0** | `knownChapterCount` columns already Room |
| Download queue + banner | ❌ | P1 | Single-download only |
| Editable Settings | ❌ | **P0** | Display-only `SettingRow`s |
| Settings → Backup / Reset | ✅ | — | SAF import/export |
| Account lists (MFL, bookmarks, history, subs, works) | ✅ | — | Lists work; hub layout weak |
| AO3 Collections (remote) | ❌ | P2 | Local collections only |
| Account dashboard hub | 🟡 | **P0 UI** | Flat cards vs iOS nav rows |
| Work Detail local + AO3 actions | 🟡 | **P0 UI** | All actions equal-weight buttons |
| Hydrate `Ao3WorkId` / remote URL | ❌ | P1 | Metadata parser exists |
| Advanced Search filters | ✅ | — | Deferred epic landed |
| Saved searches | ✅ | — | |
| Tag suggest (local) | 🟡 | P2 | Local-only; no AO3 autocomplete |
| Reader TOC / chrome / display | 🟡 | P1 | Epic3 partial; device verify |
| Custom font import | 🟡 | P2 | Store exists; Settings UI incomplete |
| Reading statistics | ❌ | P2 | |
| Authors profiles | ❌ | P2 | |
| Inbox / comments hub | ❌ | P2 | Per-work comments only |
| Non-EPUB (PDF/HTML/txt) | ❌ | P2 | |
| Folder / iCloud-style sync | 🚫 | — | Android path TBD |
| Liquid Glass / peel / zoom | 🚫 | — | iOS-only chrome |

---

## UI hierarchy gaps (human-visible “still different”)

| ID | Gap | Apple behavior | Android today | Priority |
|---|---|---|---|---|
| **UI-P0-1** | Bottom nav icons | SF Symbols | Single **letters** `H/L/B/A` | **P0** |
| **UI-P0-2** | Dual titles | One large title | TopAppBar **+** `KudosScreenHeader` | **P0** |
| **UI-P0-3** | Work Detail CTAs | Primary Read/Download; secondary/overflow AO3 | All equal `Button`/`OutlinedButton` grid | **P0** |
| **UI-P0-4** | Library density | Shelves first; filters tucked | Long filter wall before content | **P0** |
| **UI-P1-1** | Account hub | List rows / labels | Stacked Cards | P1 |
| **UI-P1-2** | TopAppBar actions | Icons | Text “Search” / theme label | P1 |
| **UI-P1-3** | Home section order | Reading Now → Updated → Subs → Fav → Opened | Continue → Fav → Opened → Added | P1 |
| **UI-P1-4** | Reader chrome | Minimal chrome, progress pill | Needs device compare | P1 |
| **UI-P2-1** | Cover art / hue cards | Generated covers | Dense Material cards (ok MD3) | P2 |
| **UI-P2-2** | Search idle polish | | | P2 |

**MD3 rule:** Not a pixel clone of SwiftUI. Match **information hierarchy,
primary actions, and scanability** — Material icons, FAB patterns, lists,
`FilterChip`s are correct tools.

---

## Wave 1 tickets (this pass)

| # | Ticket | Owner files (non-overlapping) | Acceptance |
|---|---|---|---|
| W1-A | Editable Settings | `settings/*`, `SettingsRepository` | Toggles/pickers/sliders write DataStore; privacy + app + key reader prefs |
| W1-B | Home updates + Subscriptions | `home/*`, `works/WorkUpdateChecker.kt`, `WorkRepository` update helpers, `AppNavHost` home deps | Recently Updated shelf; Subscriptions shelf when signed in; polite 6h throttle |
| W1-C | Nav icons + app bar | `MainScaffold.kt`, `Routes.kt` | Material icons for tabs; icon Search; keep labels |
| W1-D | Work Detail CTA hierarchy | `WorkDetailScreen.kt` | Primary filled Read/Download; local toggles secondary; AO3 actions in secondary section |
| W1-E | Library shelves-first | `LibraryScreen.kt` | Filters collapsed by default; shelves/search first |
| W1-F | Account hub + dual-title | `AccountScreen.kt` (+ light header cleanup) | ListItem rows; drop redundant page titles where TopAppBar already names the screen |

---

## Wave 2+ (after W1 lands)

1. Bulk select mode (favorite / finished / soft-delete / queue add)  
2. Download queue + global banner  
3. Hydrate `WorkDetailSource.Ao3WorkId` via metadata fetch  
4. Reading statistics screen  
5. AO3 collections list  
6. Author profile surface  
7. Inbox / comments hub  
8. Non-EPUB converters  
9. Reader device polish (progress pill, chrome timing)  
10. Soft-delete sweep job (90-day purge)

---

## Verification gate

```bash
cd android && ./Scripts/verify.sh
# optional device
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Manual (human): Z Flip7 — Home shelves, Settings toggles, nav icons, Work Detail
primary CTA, Library filter collapse, Account list rows.

---

## Explicitly not “parity blockers”

- Pixel-perfect HIG chrome, Liquid Glass, peel dismiss, zoom transitions  
- iCloud Drive folder sync  
- Readium iOS-only navigator APIs on Android  
- Exact SF Symbol shapes (use MD3 icon equivalents)
