# iOS ↔ Android domain audit (multi-agent)

**Date:** 2026-07-31  
**iOS SoT:** `hig-review` @ `29cd915`  
**Android:** `android/sync-from-hig-review` worktree  
**Method:** Six domain agents (related files grouped), not one agent per file (209 Swift files).  
**Follow-up ports in this commit:** UA, 600 ms pace, `AO3URLResolver`, `WorkIdentityIndex`, free-EPUB-on-finish, Android `verify.sh` gate.

---

## Agent partitions

| Agent | Domain | Swift / area |
|---|---|---|
| A | AO3 networking / auth / writes | `Services/AO3Client*`, auth, write, coalescer, coordinator |
| B | Backup / sync / persistence | `KudosBackup*`, FolderSync, PersistenceSync, queues, preservation |
| C | Work import / converters / lifecycle | `WorkImporter`, converters, DownloadQueue, tags, updates |
| D | Models / Reading / Utilities | `Models/*`, `Reading/*`, `Utilities/*` |
| E | Features (product surfaces) | Home, Library, Account, Search, Browse, Authors, Inbox |
| F | Reader + tests / CI gates | ReaderReadium, `KudosTests`, `Scripts/verify.sh` |

Full Features/* UI (100+ files) remains **MD3 expression**, not 1:1 SwiftUI ports.

---

## Executive matrix

| Domain | Ported | Partial | Missing | Top P0 remaining |
|---|---|---|---|---|
| Networking | Coalescer, coordinator, CSRF writes, parsers | UA✓, pace✓, writes, comments | Redirect cookie relay, CF jar, session live-validate | Redirect cookie relay |
| Backup | v1–v8 decode, ZIP SAF, works/EPUBs merge | Soft-delete skip | Tombstone apply, LWW, queues, annotations apply, folder sync | LWW + tombstones + queue apply |
| Import / lifecycle | AO3 EPUB download | Identity✓, free-on-finish✓ | Non-EPUB convert, update checker, download queue | Update checker |
| Models | Core SavedWork, session, search summary | — | Queues, tombstones, authors, inbox, soft-delete columns | Room schema expansion |
| Features | Home/Library/Browse/Account lists | Search (no advanced filters) | Inbox, authors, queues UI, bulk, Recently Deleted | Search filters UI |
| Reader | Open, progress contract, skeleton | Settings map only | Chrome, TOC, in-reader settings, progress pill | TOC + chrome + settings sheet |
| Tests / CI | Strong network/backup JVM | Partial vs KudosTests | Many iOS suites | `android/Scripts/verify.sh` ✓ |

---

## Implemented this pass (code)

| Item | Apple anchor | Android |
|---|---|---|
| Identifiable UA | `AO3RequestDefaults.userAgent` | `AO3UserAgent` + `KudosReader/0.1.0 (+repo)` |
| 600 ms pacing | 0.6 s pace | `AO3NetworkConfig.minDelay = 600` |
| URL resolver | `AO3URLResolver` | `network/ao3/AO3URLResolver.kt` + tests |
| Work identity | `WorkIdentityIndex` | `works/WorkIdentityIndex.kt` wired into `WorkImporter` |
| Free EPUB on finish | `WorkLifecycle.markFinished` | `WorkRepository.setFinished` (+ Reader) |
| Android verify gate | `Scripts/verify.sh` | `android/Scripts/verify.sh` + `check-invariants.sh` |

---

## Explicitly not claimed

- Full non-EPUB import (PDF/HTML/txt)  
- Folder / iCloud-style sync  
- Reading queues / annotations **apply** (decode only)  
- Tombstone LWW restore  
- Inbox / author profiles  
- Reader immersive chrome / TOC / TTS / annotations product  
- Pixel-perfect HIG chrome on Compose  

---

## Recommended next epic order

1. **P0 networking:** `AO3RedirectCookieRelay` + session restore validation  
2. **P0 backup semantics:** `progressModifiedAt` / `lastModifiedAt` Room + LWW merge; tombstone table  
3. **P0 reader UX:** TOC sheet, tap chrome, display sheet (prefs already mapped)  
4. **P1 product:** Search advanced filters UI (models exist), Home Subscriptions shelf  
5. **P1 lifecycle:** WorkUpdateChecker + Recently Updated shelf  
6. **P2:** Non-EPUB converters, queues UI, authors, inbox  

---

## Test / gate mapping (hig-review KudosTests → Android)

| iOS suite | Android | Status |
|---|---|---|
| AO3RequestCoordinator / RequestCoalescer / write / backup | Networking + BackupCompatibility | **has / strong** |
| AO3Auth / Client parsers | Split partial | **partial** |
| SavedWorkProgress | ReaderProgress* | **partial → expand** |
| ReadiumReader style | ReaderSettingsMapper | **partial** |
| EPUB MiniZip/OPF | — (Readium) | **ios_only stack** |
| FolderSync / PersistenceSync | — | **missing product** |
| ReadingStatistics | — | **missing** |

**Android DoD:** `android/Scripts/verify.sh`  
1 invariants · 2 full unit tests · 3 assembleDebug · 4 persistence subset · 5 whitespace  

---

## How to re-run domain agents

```text
spawn explore agents with the same partitions; worktree =
.claude/worktrees/android-sync-hig-review
```
