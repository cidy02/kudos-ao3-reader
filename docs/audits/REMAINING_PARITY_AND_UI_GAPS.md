# Remaining iOS ↔ Android feature parity & UI gaps

**Date:** 2026-07-31  
**Android tip:** `android/sync-from-hig-review` (post Wave 1+2 merge; run `git log -1`)  
**iOS SoT in worktree:** `kudos-ao3-reader/` (hig-review product rules)  
**Method:** Multi-agent waves; product-behavior port into Compose / MD3.  
**Policy:** Never merge Android into `main`.

---

## Honest status (after Waves 1–2)

| Area | Status |
|---|---|
| Core reader loop (Library → Detail → EPUB → Readium) | **Done** |
| AO3 auth, account lists, writes, comments, backup v1–v8 merge | **Done** |
| Soft-delete / Recently Deleted / queues / purge-on-launch | **Done** |
| Advanced Search filters, saved searches, local tag suggest | **Done** |
| Home Recently Updated + Subscriptions + update checker | **Done (W1)** |
| Editable Settings | **Done (W1)** |
| Nav Material icons, Work Detail CTA hierarchy, Account hub | **Done (W1)** |
| Library shelves-first + bulk select + Collections + Insights | **Done (W1–2)** |
| Download queue + banner | **Done (W2)** |
| Dual-title cleanup across major screens | **Done (W2)** |
| Authors works-from-detail, AO3 remote collections, series download, custom fonts | **Done (W3)** |
| Inbox hub, non-EPUB, folder sync | **Still missing** (Inbox not first-class on current iOS tree; non-EPUB/folder deferred) |
| Reader device polish | **Partial** — needs human device compare |

**Complete feature parity is multi-wave.** This document is the living backlog.
Each wave implements a slice, merges to `android/sync-from-hig-review`, runs
`android/Scripts/verify.sh`, then re-ranks.

---

## Product parity matrix

Legend: ✅ done · 🟡 partial · ❌ missing · 🚫 platform-only / out of scope

| Feature (Apple) | Android | Priority | Notes |
|---|---|---|---|
| Home Continue / Favorites / Recent | ✅ | — | Shelves present; density tuned |
| Home **Recently Updated** | ✅ W1 | — | `WorkUpdateChecker` + `hasUpdate` |
| Home **Subscriptions** shelf | ✅ W1 | — | Account list page 1 |
| Library shelves + filters | ✅ W1 | — | Filters collapsed by default |
| Soft-delete / Recently Deleted | ✅ | — | + app-start purge W2 |
| Reading queues UI | 🟡 | P2 | List + detail; polish |
| Bulk select / multi-actions | ✅ W2 | — | Favorite/finished/soft-delete |
| Work update checker | ✅ W1 | — | 6h throttle |
| Download queue + banner | ✅ W2 | — | Serial WorkImporter |
| Editable Settings | ✅ W1 | — | Switches/chips/sliders |
| Settings → Backup / Reset | ✅ | — | SAF import/export |
| Account lists | ✅ | — | Hub ListItems W1 |
| **Local** Collections UI | ✅ W2 | — | Create/detail/delete |
| AO3 Collections (remote) | ✅ W3 | — | My Collections (AO3) + works |
| Account dashboard hub | ✅ W1 | — | ListItem hierarchy |
| Work Detail CTA hierarchy | ✅ W1 | — | Primary/secondary/danger |
| Hydrate `Ao3WorkId` / remote URL | 🟡 W1 | P2 | Partial metadata hydrate |
| Advanced Search / saved searches | ✅ | — | |
| Tag suggest (local) | 🟡 | P3 | Local-only |
| Reader TOC / chrome / display | 🟡 | P2 | Device verify |
| Custom font import UI | ✅ W3 | — | SAF import + Settings |
| Reading statistics | ✅ W2 | — | Insights screen |
| Authors works (from detail) | ✅ W3 | — | Creator search list |
| Full author profile / Inbox hub | ❌ | P3 | Not on current iOS Features tree |
| Non-EPUB (PDF/HTML/txt) | ❌ | P2 | |
| Folder / iCloud-style sync | 🚫 | — | Android path TBD |
| Liquid Glass / peel / zoom | 🚫 | — | iOS-only chrome |

---

## UI hierarchy gaps (human-visible “still different”)

| ID | Gap | Apple behavior | Android today | Priority |
|---|---|---|---|---|
| **UI-P0-1** | Bottom nav icons | SF Symbols | **Material filled/outlined icons (W1)** | ✅ |
| **UI-P0-2** | Dual titles | One large title | **Demoted/removed duplicate headers (W2)** | ✅ |
| **UI-P0-3** | Work Detail CTAs | Primary Read/Download | **Primary / local / On AO3 / danger (W1)** | ✅ |
| **UI-P0-4** | Library density | Shelves first | **Filters collapsed; shelves first (W1)** | ✅ |
| **UI-P1-1** | Account hub | List rows | **ListItems + icons (W1)** | ✅ |
| **UI-P1-2** | TopAppBar actions | Icons | **Search/back/theme icons (W1)** | ✅ |
| **UI-P1-3** | Home section order | Updated → Subs | **Matched iOS order (W1)** | ✅ |
| **UI-P1-4** | Reader chrome | Minimal chrome | Needs device compare | P2 |
| **UI-P2-1** | Cover art / hue cards | Generated covers | Dense Material cards (ok MD3) | P2 |
| **UI-P2-2** | Search idle polish | | | P2 |

**MD3 rule:** Not a pixel clone of SwiftUI. Match **information hierarchy,
primary actions, and scanability** — Material icons, FAB patterns, lists,
`FilterChip`s are correct tools.

---

## Waves completed

### Wave 1 ✅ (merged + verify green)
| # | Ticket | Result |
|---|---|---|
| W1-A | Editable Settings | Interactive privacy/app/reader controls |
| W1-B | Home updates + Subscriptions | `WorkUpdateChecker`, shelves, iOS order |
| W1-C | Nav icons + app bar | Material icons; Search/Back/theme IconButtons |
| W1-D | Work Detail CTA hierarchy | Primary/local/On AO3/danger + soft-delete copy + partial hydrate |
| W1-E | Library shelves-first | Filters collapsed |
| W1-F | Account hub | ListItem destinations |

### Wave 2 ✅ (merged + verify green)
| # | Ticket | Result |
|---|---|---|
| W2 bulk | Library multi-select | Favorite/finished/soft-delete |
| W2 dlqueue | Download queue + banner | Serial queue, MainScaffold banner |
| W2 stats | Reading Insights | Pure stats + screen + Library entry |
| W2 purge | Soft-delete expiry | App-start `purgeExpiredSoftDeletes` |
| W2 dualtitle | Header cleanup | No stacked page titles |
| W2 collections | Local Collections UI | List/detail/create/delete |

### Wave 3 ✅ (merged + verify green)
| # | Ticket | Result |
|---|---|---|
| W3 fonts | Custom font import | SAF + FontFileStore + Settings |
| W3 series | Download entire series | Series scrape → DownloadQueue |
| W3 authors | Author works from detail | Tappable author → creator search |
| W3 AO3 collections | My Collections (AO3) | Parse + list + works |

### Still deferred (not parity blockers for everyday reading)
1. Non-EPUB converters (PDF/HTML/txt)  
2. Folder / Drive-style sync  
3. Full author profile pages / Inbox hub (not present as first-class Features on this iOS tip)  
4. Reader device polish (progress pill timing)  
5. Biometric reveal for mature works  
6. Remote compact-card download-into-reader open path

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
