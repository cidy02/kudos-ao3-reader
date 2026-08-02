# iOS task history vs Android — whole-feature gap pass

**Date:** 2026-08-02  
**Method:** Read-only. Walk the full DONE history in  
`.claude/worktrees/hig-review-reference/TASKS.md` (In Progress rows marked ✅ DONE  
**plus** the ✅ Completed table; tip includes work through ~T-185; T-186 is READY and  
was not treated as shipped). For each **distinct user-facing feature**, ask whether  
`android/` (`io.github.cidy02.kudos`) has an equivalent (even partial).  
**Not** an area-by-area code diff — that already produced  
`ANDROID_PARITY_REPORT.md`, `ANDROID_PARITY_FINDINGS_VERIFIED.md`, and  
`PARITY_SWEEP2_{A,B,C,D}_*.md` (31 findings).

**Scope filters (do not re-report):**

1. Owner-confirmed gaps (spot-checked before this pass).  
2. Anything already in the four audit registries above (and their “known/deferred”  
   lists).  
3. Pure bug-fix rounds, adversarial-review-fix rounds for the same-numbered task,  
   doc-only / process / lint tasks.  
4. Pure HIG / accessibility / Dynamic Type / VoiceOver polish waves (ranges below),  
   unless a row clearly ships a **new** user capability (none of the pure polish  
   rows below did, for this pass).

---

## Summary counts

| Bucket | Count |
|---|---|
| DONE iOS tasks inventoried (In Progress ✅ + Completed table) | **147** |
| Distinct feature candidates considered after de-dup / skip rules | **~55** |
| **New whole-feature gaps (this pass)** | **4** |
| Already-known (owner list + prior registries) — noted, not re-reported | **see below** |
| Present / adequately partial on Android | **majority of product features** (auth lists, Home/Library shelves, queues, collections, backup, search filters, comments shell, reader, stats, series download, custom fonts, etc.) |

### New whole-feature gaps found this pass: **4**

| Severity of gap | Count |
|---|---|
| Absent | 2 |
| Partial | 2 |

---

## New gaps (not in prior registries / owner list)

| iOS Task | Feature | Android Status | Confidence |
|---|---|---|---|
| **T-80** | On-demand AO3 **session health**: Account shows last-verified state (`unknown` / `verifying` / `healthy(Date)` / `expired` / `unreachable`) plus a **Verify Session** control that re-validates without requiring logout/login; transient network failures must not force sign-out | **Partial** — launch/restore validation exists (`LiveAO3SessionValidator` wired from `KudosAppContainer` into `AO3AuthRepository.restoreSession()`). No `verifySession()` API, no `AO3SessionHealth` state machine, no Account “Session” row / “Verify Session” button (`AccountScreen` only shows signed-in username / expired / error) | **High** |
| **T-26** | Search toolbar **Expand all / Collapse all** for result cards (batch toggle for every expandable blurb on the page) | **Partial** — per-card progressive disclosure exists (`AO3WorkCard` More/Less). No toolbar/batch expand-all or collapse-all control on `SearchScreen` | **High** |
| **T-15** | In-app AO3 **browser theme sync** — fallback WebView injects CSS so Dark/Sepia/OLED pages match the app theme (Light leaves AO3 native skin) | **Absent** — `AO3WebViewFallbackScreen` is explicitly “no JavaScript bridge / script injection”; chrome uses Material surface colors only; no `kudos-app-theme` (or equivalent) CSS injection. (WebView **download** listener gap is already in the parity report — this is the separate *theme* capability from T-15.) | **High** |
| **T-76** | **Reader section indexing** for AO3/Calibre EPUBs: classify spine items as Preface / Summary / Chapter / Afterword / other; progress pill and chapter index count only real story chapters (`P`/`S`/`A` vs `i/total`), so front/back matter does not inflate “Ch. N” | **Absent** — `ReaderProgressDisplay.label` always formats `Ch. (spineIndex+1)/spineCount` with no `ReaderSection` / `ReaderSectionKind` equivalent under `reader/`. TOC builder is a flat list only | **High** |

---

## Already-known (do not re-report) — owner list

| iOS Task(s) | Feature | Status on this pass |
|---|---|---|
| **T-50** | First-launch onboarding / Welcome | Confirmed absent (`*Onboard*` / `*Welcome*` — zero). **Already known.** |
| **T-58** | Local **user EPUB file import** (distinct from AO3 download) | Confirmed absent; Settings file picker is **font** import only. **Already known.** |
| **T-39 / T-101** | About: version, GPL-3.0, dependency credits (SwiftSoup/Readium/… ↔ Jsoup/Readium-Kotlin/…) | `AboutScreen.kt` has AO3/OTW disclaimer only. **Already known.** (Also covers **T-122** commit-SHA-in-version as a sub-detail of About.) |
| **T-50** (+ Support) | **Shake-to-report** + structured bug report (GitHub-prefilled / screenshot) | Settings “Report a Bug” is plain `mailto:`; no shake / `Sensor` / screenshot path. **Already known** (on top of mailto-vs-GitHub-form). |

---

## Already-known (do not re-report) — prior audit registries

These appear in `ANDROID_PARITY_REPORT.md`, `ANDROID_PARITY_FINDINGS_VERIFIED.md`,  
and/or `PARITY_SWEEP2_{A,B,C,D}_*.md` (or the owner’s skip list). Inventoried only  
so a human can see they were considered and filtered:

| iOS feature cluster (task examples) | Why skipped here |
|---|---|
| Inbox hub / activity (T-82 era, T-91/T-95/T-96) | Inbox stub — known |
| Full author profile + Block/Mute/Subscribe on author (T-87) | Author works-list only — known |
| Non-EPUB / community-copy import + PDF→EPUB (T-157, T-184) | Known deferred |
| Rebuild from Original / Last Copy provenance UI (T-172) | Downstream of non-EPUB originals + **Check Availability** (Settings Preservation already in parity report) |
| Folder / iCloud-style Library Sync (T-66–T-69, T-139 folder side) | Known deferred / platform TBD |
| Biometric mature reveal | Known deferred |
| Reader TOC polish / full display customize / TTS / peel-dismiss chrome (T-21, T-61, T-153, reader waves) | Known deferred reader polish |
| Advanced Search gaps already listed (local-first Search T-54/T-72 partial, AO3 tag autocomplete, fandom works filter UI, etc.) | In report / sweep B |
| Preferences WebView-only (vs native `AO3PreferencesView`) | Known |
| Account Series / Drafts stubs | Known |
| Pull-to-refresh (T-63) Home/Library/Account/Work Detail | Known (sweep A/C/D) |
| Subscribe label stale / no work-page state (live-test follow-ups) | Known (sweep D) |
| No disk-backed FandomCatalog cache (T-51 local-first disk) | Known; in-memory only called out in Browse code |
| Library See All / full filter panel / multi-select bulk Queue+Collection (T-37/T-46/T-52 partial UI) | Report + sweep A |
| Collection rename; collection Add Works (T-53/T-78) | Sweep A / report |
| Queue reorder / Queue Storage settings / auto-preserve series (T-59/T-77 + Settings) | Report |
| Privacy & Local Data screen (clear browse cache / history) from T-54 privacy surface | Report |
| Comments: reply, pagination, idempotency, work header (T-82/T-99/T-102) | Report / verified |
| Remote compact-card download-then-open (T-178/T-179) | Known deferred in report |
| AppNavHost shared selection / navigation stack correctness (T-112 family) | Report |
| Accent color persisted but not applied; OLED alias (T-16 partial) | Sweep D |
| WebView EPUB download listener | Report (distinct from T-15 theme) |

---

## HIG / accessibility / polish ranges skipped en masse

Human spot-check list: these DONE ranges were treated as **not** shipping a new  
standalone product feature (layout, hit targets, Dynamic Type, VoiceOver, theme  
injection bugs, card scaling, dual-title, skeleton flash, system-blue icons, etc.).  
If a row buried a real capability, it would have been pulled out — none were for  
this pass beyond T-76’s earlier non-HIG indexing task.

| Range / cluster | Why skipped |
|---|---|
| **T-115 – T-117** | HIG review / planning / Wave 0 decisions only |
| **T-118 – T-121** | HIG Waves 1–2 + review-fix (shared foundation / UIComponents) |
| **T-123 – T-125** | HIG Wave 3 Search + review-fix / pagination clamp |
| **T-126 – T-128** | HIG Wave 4 Library + review-fix / no-op reorder churn |
| **T-129 – T-130** | HIG Wave 5 Work Detail + review-fix geometry |
| **T-131 – T-138** | Dynamic Type / card scaling / footer pin / sheet theme follow-ups |
| **T-140 – T-144** | HIG Wave 7 Comments/Authors UI + regression F1–F7 VoiceOver/layout |
| **T-146 – T-148, T-150** | Onboarding bar Sepia polish; HIG Waves 8–9 DT / timing |
| **T-153, T-185** | HIG Wave 10 reader chrome/skeleton polish (not new reader *capabilities* beyond known TOC/chrome debt) |
| **T-156** | SwiftLint file-split / gate repair only |
| **T-174, T-176** | App-wide icon tint regression; compact-card stats layout copy |
| **T-90, T-106–T-108** | Account control-shape / compact Overview / dropdown tint polish |
| **T-55, T-56, T-64, T-79 (UI bits)** | Card depth / selection outline / carousel polish without new product surface |

Also skipped as **non-feature** (infra, docs, pure bugs, review loops):  
T-05, T-06, T-08, T-17, T-22, T-25, T-27, T-28, T-31, T-32, T-43, T-45, T-48, T-49,  
T-65, T-73–T-75, T-84, T-89, T-92–T-93, T-95–T-96, T-99–T-100, T-102–T-105,  
T-111–T-113, T-124, T-149, T-151, and similar adversarial/certification rows.

**Not started / not DONE** (out of scope for “shipped iOS history”): T-158, T-164,  
T-171, T-173, T-175, T-180–T-182, T-186, open Inbox T-91, etc.

---

## Present on Android (high-level; not exhaustive)

For orientation only — these DONE iOS features have a real Android counterpart  
(sometimes thinner UI, but not “missing entirely”):

T-09/T-23 search include/exclude cycling · T-10 expandable cards · T-13 hide privacy  
eye when no mature works (`showPrivacyToggle`) · T-16 accent *picker* (apply = known  
bug) · T-24 Browse category enrichment · T-30 auth · T-33–T-36 account lists ·  
T-37 bulk select · T-38 download queue + series download · T-40 Continue Reading ·  
T-41 Reading Insights · T-42/T-139/T-145 `.kudosbackup` ZIP merge · T-44 Home  
dashboard · T-46 Library shelves · T-51 request coordinator / coalescing (disk  
Fandom cache still known-missing) · T-52 fandom chips · T-53 collections · T-59  
queues · T-70 Recently Deleted · T-71 `WorkIdentityIndex` · T-80 launch session  
validate only · T-81 reading-state-ish `isInProgress`/`hasStartedReading` · T-82  
comments shell · T-94 mark finished in reader · T-114 Work Detail hub tabs ·  
T-152-class backup import summary+progress · W3 custom fonts / authors / AO3  
collections.

---

## Method notes / confidence

- iOS SoT: `.claude/worktrees/hig-review-reference/TASKS.md` + spot-checks under  
  that worktree’s `kudos-ao3-reader/` (e.g. `AO3AuthService.verifySession`,  
  `WebBrowser` theme CSS, `ReaderSection.swift`, `AccountComponents` Session row).  
- Android SoT: `android/app/src/main/java/io/github/cidy02/kudos/**` on this  
  worktree tip (`android-sync-hig-review`).  
- This pass optimizes for **whole features missing**, not micro-parity of every  
  DONE task. A “partial” row means the user can get some of the capability, not  
  that the implementation is complete.  
- No production code was modified; this file is the only deliverable.

---

## Suggested next product picks (from *new* gaps only)

1. **T-80** Verify Session on Account — small, high trust value for signed-in users.  
2. **T-76** Reader section indexing — correctness for almost every AO3 EPUB progress pill.  
3. **T-15** WebView theme CSS — visible whenever “Open on AO3” fallback is used in dark/sepia.  
4. **T-26** Expand/collapse all — small Search QoL once result density is high.

Owner-known items (onboarding, local EPUB import, About credits/version,  
shake-to-report) remain higher product visibility than T-26 if prioritization is  
user-facing completeness rather than “new findings only.”
