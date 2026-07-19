# Fixes & HIG Implementation Plan

**Type:** Planning only — no code, no implementation prompts, no UI redesign, no re-audit.
**Author:** Claude (lead-architect planning pass), 2026-07-19.
**Base branch:** `release-fixes` (tip `08cbc11`).
**Primary input:** [`HIG_ADHERENCE_REVIEW_T115.md`](HIG_ADHERENCE_REVIEW_T115.md) — 52 adversarially-verified
findings (0 P1 / 24 P2 / 28 P3), UI-2…UI-9 + BUG-7/BUG-8.
**Folded inputs (still-open findings from every other audit):** `RELEASE_READINESS_FABLE5.md`
(Areas 1–10 + T91-RF), [`PONYTAIL_AUDIT_RELEASE_FIXES.md`](PONYTAIL_AUDIT_RELEASE_FIXES.md),
[`COMMENTS_AO3_API_AUDIT.md`](../COMMENTS_AO3_API_AUDIT.md), the three adversarial reviews
(Account redesign, Account shortcuts→compact, Scrolled-reader hang), and the TASKS.md
Bugs/Backlog/decision registries. **80 open non-HIG findings** harvested (44 P2 / 36 P3); **28
of them touch HIG-flagged files** and are folded into the HIG waves so those files are opened
once, not twice.

> All findings are treated as **authoritative**. This document does not re-audit or re-verify
> them; it only sequences their implementation for maximum engineering efficiency.

---

## Executive Summary

### Overall strategy — shared components first, then disjoint per-directory sweeps

The single biggest efficiency lever is that the HIG findings are dominated by **a small number of
repeated defects across many call sites**, and the codebase **already contains the correct
pattern for each** (`SkeletonShimmer` for reduce-motion, `WorkDetailView.animateUnlessReduced`,
`OnboardingPointRow`/`SensitiveWorkRow` for grouped VoiceOver, `RemoteWorkSelection` as a
consolidation precedent, `DeleteConfirmation` for destructive alerts). The plan therefore:

1. **Builds a shared-foundation layer first** (Wave 1): six reusable helpers/tokens that collapse
   ~40 individual call-site fixes into 6 component changes + mechanical application. Nothing
   downstream is touched until these exist.
2. **Sweeps the shared UIComponents next** (Wave 2): fixing `WorkStatLabel`, `AO3AuthorNavigation`,
   `ReorderHandle`, `TagChip`, `WorkCarouselSection` once fixes every card, byline, reorder handle
   and chip in the app — the largest multiplier in the plan.
3. **Then runs per-directory feature waves that touch disjoint file sets** (Search, Library,
   WorkDetail, Account/Inbox, Comments). After Waves 1–2 land, these branches share **no files**
   and can proceed in parallel with zero merge conflicts.
4. **Isolates the two highest-risk concerns into late, sequential, own-gate waves**: Dynamic-Type
   structural layout changes (Wave 8) and the macOS reader (Wave 10).
5. **Keeps genuinely separate concerns on their own tracks** (Track B: security, comment-parser
   correctness, performance, functional correctness) so a UI-adherence branch is never blocked on
   a security fix and each gets the right review lens.

### Recommended execution order

```
Wave 0  Owner decisions (no code)         ── ✅ RESOLVED 2026-07-19; Waves 4,10, Track B1 clear
Wave 1  Shared foundation                 ── ✅ DONE 2026-07-19 (T-118); Wave 2 next
Wave 2  UIComponents/ sweep               ── biggest multiplier
        ┌─ Wave 3  Search/        ┐
        ├─ Wave 4  Library/       │  disjoint files → may run in PARALLEL
        ├─ Wave 5  WorkDetail/    │  (short-lived branches, rebased before merge)
        ├─ Wave 6  Account+Support│
        └─ Wave 7  Comments+Authors┘
Wave 8  Dynamic-Type structural (UI-4)    ── higher risk; after 2/5/7 touch those files
Wave 9  Timing/navigation (UI-8)          ── small, correctness-sensitive
Wave 10 Reader (UI-9 + BUG-7)             ── HIGHEST risk; own gate; macOS-heavy
Track B  Security / Comments-Part-D / Perf / Functional  ── owner-prioritized, parallel to Track A
```

### Highest-value improvements (do these regardless of how far the plan runs)

- **Wave 1 + Wave 2** together retire the bulk of UI-2/UI-3/UI-5 across the whole app for the
  least code, because the fixes live in shared components every surface already uses.
- **The combined-accessibility-row helper applied to `WorkStatLabel`/`CardMetaLabel`** (Wave 2)
  is the single highest-frequency VoiceOver fix — those labels render on every card in Home,
  Library, Search, and Account.
- **The `.minimumHitTarget()` helper** (Wave 1) closes UI-3 *and* the release-readiness A9-F1/A9-F2
  accessibility findings in one stroke.

### Highest-risk areas

- **Wave 10 (Reader).** macOS WKWebView + legacy `ReaderController`, dead nested `#if os(iOS)`
  blocks (UI-9), BUG-7 sidebar occlusion, and the still-unmerged, owner-smoke-pending T-98
  scrolled-hang fix all live here. Regression-prone, macOS-only, thinnest test coverage.
- **Wave 8 (Dynamic-Type structural).** UI-4 relaxes fixed card frames and adds a segmented-control
  AX fallback — real layout changes across Home/WorkDetail/Account that need runtime AX
  verification and the screenshot gate, unlike the mostly-mechanical earlier waves.
- **Wave 1 token unification & theme roles.** Low code risk but wide visual reach (31 files read
  the theme); it must pass the density/theme screenshot gate before mass adoption.

---

## Cross-Wave Improvements (build these in Wave 1, before any call-site fix)

Each is a shared addition that eliminates duplicated work downstream. All six are **additive** —
they don't change behavior until a later wave adopts them — except the token unification and theme
roles, which are visual and need the screenshot gate. The reference implementation of each helper
is applied to **one** call site in Wave 1 to prove it; mass application happens in the per-directory
waves.

| # | Shared improvement | Replaces / model already in repo | Serves (findings) |
|---|---|---|---|
| X1 | **`.minimumHitTarget()` ViewModifier** — pads any control's hit area to 44×44pt (or 28pt floor where space-constrained) via `.contentShape` + min-frame, visible glyph unchanged. | No shared helper today; every fix is a hand-written `.frame(minWidth:44…)`. | UI-3 (~8 sites), A9-F1, A9-F2 |
| X2 | **Shared reduce-motion helper** — promote `WorkDetailView.animateUnlessReduced` (currently private) to a `View`/global helper + a `.animateUnlessReduced` modifier. | `SkeletonShimmer` (UIComponents/SkeletonLoading.swift) is the correct model; `animateUnlessReduced` already exists privately. | UI-5 (12+ sites) |
| X3 | **Semantic theme color roles** — add `error` / `exclude` / `favorite` / `status` roles (with light/dark/sepia/OLED variants + a contrast-safe "on-accent" foreground) to `ThemeManager`/`ReaderTheme`. | Replaces hardcoded `.red`/`.green`/`.yellow`; `ThemeManager` already owns accent. | UI-6, A9-F3 (accent erases fixed-white labels) |
| X4 | **One card-radius/spacing token source** — reconcile `CardListMetrics`(16) / `CarouselCardMetrics`(12) / `AccountControlMetrics`(20) into one documented family; retire the stray 14pt literals. | Three enums exist in three files today (the "3 coexisting radii" finding). | UI-7 hub-chrome divergence, §4 token-hygiene leads |
| X5 | **Combined-accessibility-row helper** — a `.combinedAccessibilityRow(label:)` (or convert to native `Label`) so icon+text meta pairs read as one VoiceOver stop. | `OnboardingPointRow`/`WorkStateBadge` already do this correctly; `WorkStatLabel`/`CardMetaLabel` are the broken raw HStacks. | UI-2 (highest-frequency) |
| X6 | **One destructive-confirmation idiom** — a single shared confirm helper unifying `DeleteConfirmation` (`.alert`) and `WorkBulkActionBar` (`.confirmationDialog`). | Both patterns exist; the split is the finding. | UI-6 destructive-role items, §4 |

**Also fold into the shared track (over-engineering audit, PONY-6.1):** the ~10 duplicated
AO3-href-to-absolute-URL resolvers across `Services/` — a genuine shared-component consolidation
that fits Wave 1's "one helper, many call sites" theme. It is `Services/`-side (not UI), so it can
ride Wave 1's branch or Track B; either way, do it as one shared resolver, not per-site.

---

## Implementation Waves

Notation: **[HIG]** = from the T-115 review; **[fold]** = still-open finding from another audit
placed here because it shares this wave's files. `verify.sh` = `Scripts/verify.sh` (invariants →
lint → iOS suite → macOS build → whitespace), required ALL GREEN before every merge.

### Wave 0 — Owner decisions (no code; unblocks later waves) — ✅ RESOLVED 2026-07-19

- **Goal:** resolve the decision-gated items that otherwise block downstream waves.
- **Decisions** (full detail: `TASKS.md` Key Decisions + T-117):
  1. **BUG-8 / KD-LAYOUT-READERAFFORD** — not a bug. Library cards open the reader directly on
     **both** iOS and macOS by design (confirmed live on-device); the "cards open detail" text
     was stale documentation and has been corrected. Wave 4 drops the BUG-8 routing item.
  2. **A1-F2 / KD-TEAMID** — keep `DEVELOPMENT_TEAM = NQH85H7343` as-is. No scrub, no
     git-history purge. Track B1 drops the team-id action item.
  3. **PONY-6.7** — raise `KudosBackupManifest.supportedVersions` to the latest version only (no
     pre-July backups in use). Decided, **not yet implemented** — one-line change in
     `Services/KudosBackup.swift:174-175`, unscheduled.
  4. **KD-MIGRATION-META** — split by platform: iOS consolidates onto Readium metadata; macOS
     keeps the custom OPF layer (no Readium navigator there to source from).
  5. **SHORT-R5** — keep `@AppStorage` Compact-default semantics, no forced migration. **New
     scope item:** unify the compact/detailed toggle into one app-wide setting (today 5
     independent, un-synced stores — full list in `TASKS.md` T-117). Unscheduled; candidate for
     Wave 1 (same "one helper, many call sites" shape as X1–X6).
- **Shared components / files:** none (decisions only).
- **Dependencies:** none. **Blocked (now cleared):** Wave 4, Wave 10, Track B1 may proceed.
- **Testing:** none. **Complexity:** Small (owner time, not engineering).

### Wave 1 — Shared foundation (MERGE FIRST) — ✅ DONE 2026-07-19 (T-118)

- **Goal:** land the six cross-wave helpers (X1–X6) + the PONY-6.1 resolver, each proven on one
  reference call site. Establish the API every later wave imports.
- **Findings addressed:** none end-to-end yet (infrastructure) — but unblocks UI-2/3/5/6/7.
- **Shared components created:** `UIComponents/MinimumHitTarget.swift` (X1); `UIComponents/ReduceMotion.swift`
  (X2); `UIComponents/SemanticThemeColors.swift` + `relativeLuminance` (`Utilities/ColorHex.swift`)
  + `onAccentColor` (`App/ThemeManager.swift`) (X3); `CardRadius` enum in `UIComponents/AppThemeSurface.swift`
  (X4); `combinedAccessibilityRow(_:)` in `UIComponents/WorkStatLabel.swift` (X5); `DestructiveConfirmationStyle`
  + generic overloads in `UIComponents/DeleteConfirmation.swift` (X6); `Services/AO3URLResolver.swift`
  (PONY-6.1, +14 unit tests). Also folded the **App/ContentView.swift Sepia segmented-control** fix
  (UI-6/P3) — now reads `ReaderTheme.appBaseBackground`/`appElevatedBackground`/`textColor` instead
  of hardcoded RGB.
- **Reference call sites (proof, not mass adoption):** `WorkRow.swift` (X1 expand button, X3 favorite
  star), `WorkCarouselSection.swift` (X2 collapse toggle), `AccountComponents.swift` +
  `WorkDetailComponents.swift` (X4, both stray 14pt tiles), `WorkStatLabel.swift` + `HomeCards.swift`
  (X5), `Collections.swift` (X6, "Remove from collection" — previously unconfirmed despite
  `role: .destructive`), `AO3Client.swift` `parseBlurb` (PONY-6.1).
- **Dependencies:** Wave 0 not required. **Everything in Track A depends on this.**
- **Risks:** token unification + theme roles have wide visual reach (31 files read the theme) →
  screenshot gate required (owner, still open — see Remains manual below); call-site migration
  deliberately OUT of this wave (Wave 2 mass-adopts) to bound blast radius.
- **Testing:** `verify.sh` ALL GREEN (602 tests/57 suites, iOS + macOS builds); 14 new table-driven
  unit tests for the resolver. **Adversarial review (T-119, 2026-07-19) found 5 issues in X1/X2/X3/X6**
  — all fixed; see `TASKS.md` T-119 for the fixes and the runtime evidence. X1's hit-target claim is
  now **runtime-verified by real device taps** (was previously asserted, not exercised); X3's
  `onAccentColor` was renamed `onEffectiveTint` and fixed to judge the color controls actually
  render with. **Remains manual (owner):** the screenshot gate — Library (X1 row height), Account
  (X4's 14→12pt radius), Sepia theme (ContentView fix + X3 favorite-star recolor); **and** a real
  VoiceOver/Accessibility-Inspector pass on X5's `combinedAccessibilityRow` label text (T-119
  implemented the fix but couldn't complete the runtime spot-check — Accessibility Inspector's
  element-picker mode got stuck globally intercepting clicks via a system service that computer-use
  can't allowlist). `errorColor`/`favoriteColor`/`statusSuccessColor` RGB values are placeholder
  estimates, not WCAG-verified against each theme's real backdrop — check before Wave 2 migrates the
  exclude/status call sites onto them. **API review gate**: skim the six signatures before Wave 2
  mass-adopts them.
- **Complexity:** Medium.

### Wave 2 — `UIComponents/` sweep (biggest multiplier)

- **Goal:** apply X1/X2/X5 (+ token migration) across the shared components so every downstream
  surface inherits the fix.
- **Findings addressed:** **[HIG]** UI-2 (`WorkStatLabel`, `TagChip`, `AppThemeSurface`
  `CardNavigationModifier` stray VoiceOver stop), UI-3 (`ReorderHandle`, `WorkCarouselSection`
  collapse+see-all, `AO3AuthorNavigation` byline targets), UI-5 (`WorkCarouselSection` collapse
  animation), UI-6 (`WorkCardListControls` clear-filters idiom via X6); **[fold]** A9-F2
  (ReorderHandle drag-only + missing hint), A9-F4 (author links keyboard-focusable), A6-F2 partial
  (bulk-action bar lives here).
- **Shared components:** `WorkStatLabel`, `CardMetaLabel`, `TagChip`, `ReorderHandle`,
  `WorkCarouselSection`, `AO3AuthorNavigation`, `WorkCardListControls`, `AppThemeSurface`,
  `CarouselCardStyle` (token only — defer the frame change to Wave 8).
- **Primary files:** all under `UIComponents/`.
- **Dependencies:** Wave 1. **Risks:** these render everywhere — a regression is app-wide, so the
  screenshot + VoiceOver spot-check gates are mandatory. Do NOT change card frame sizes here
  (that's Wave 8) to keep this wave low-risk.
- **Testing:** `verify.sh`; VoiceOver spot-check on Home/Library cards (validates the two
  runtime-flagged UI-2 items: `CardNavigationModifier` stray stop, WorkStatLabel grouping);
  screenshot gate. **Complexity:** Medium. **Highest value in the plan.**

### Wave 3 — `Features/Search/`

- **Goal:** apply the shared helpers + theme roles to the Search surface.
- **Findings:** **[HIG]** UI-2 (`AO3FilterPanel` cyclingFacetRow, `TagSelectField`), UI-3
  (`SearchPaginationBar` 31pt buttons), UI-6 (`TagSelectField`/`AO3FilterPanel` `.red` → X3
  exclude role; reset-filters destructive role), UI-7 (`SearchView` duplicate pagination bar),
  UI-3 (pagination long-press affordance); **[fold]** A9-F1 (pagination hit-target + gesture-only —
  same file as UI-3), A9-F3 partial (accent contrast on chips/pagination).
- **Shared components:** consumes X1, X3. **Primary files:** `Features/Search/*`.
- **Dependencies:** Waves 1–2. **Parallel-safe** with Waves 4–7 (disjoint files).
- **Risks:** low. **Testing:** `verify.sh`; screenshot gate; AX runtime check of the pagination
  bar. **Complexity:** Small–Medium.

### Wave 4 — `Features/Library/`

- **Goal:** Library accessibility + consistency.
- **Findings:** **[HIG]** UI-2 (`LibraryFilterPanel.selectableRow` trait, `RecentlyDeletedView`
  grouping), UI-3 (`WorkRow` expand button), UI-6 (`Collections` remove destructive role, favorite
  star `.yellow` → X3), UI-7 (`LibraryView` dual bulk-select impl + non-modal tab-bar hide),
  UI-2 (`WorkCardActions` a11y coverage); **[fold]** A6-F1 (queue drag-reorder broken — pairs with
  Wave 2's ReorderHandle). ~~BUG-8 (macOS card routing)~~ — resolved by Wave 0 as not-a-bug, dropped.
- **Shared components:** consumes X1, X3, X6, and the Wave-2 ReorderHandle. **Primary files:**
  `Features/Library/*` (`LibraryView`, `LibraryFilterPanel`, `RecentlyDeletedView`, `Collections`,
  `WorkRow`, `WorkCardActions`, `ReadingQueues`).
- **Dependencies:** Waves 1–2. **Parallel-safe** with 3/5/6/7.
- **Risks:** the bulk-select unification (UI-7) is behavioral (adds macOS select mode) — keep it a
  clearly-scoped sub-change; A6-F1 reorder is a real correctness fix, review separately.
- **Testing:** `verify.sh`; new tests for reorder index bridge (per A6-F1); screenshot gate on
  select mode. **Complexity:** Medium (Large if A6-F1 reorder repair is included).

### Wave 5 — `Features/WorkDetail/`

- **Goal:** finish the T-114 hub's HIG polish.
- **Findings:** **[HIG]** UI-2 (`WorkDetailComponents` tile double-announcement), UI-3
  (`WorkDetailSections` remove-tag button), UI-7 (hub-chrome token divergence via X4; disclosure
  `chevron.right` on non-navigating rows in `WorkDetailOverviewSections`/`WorkDetailSections`),
  UI-4 segmented-control AX fallback is **deferred to Wave 8** (structural).
- **Shared components:** consumes X1, X4, X5. **Primary files:** `Features/WorkDetail/*` (+ read-only
  coordination with `Features/Account/AccountControlStyle.swift` for the shared hub token — land
  the token in Wave 1 so both hubs consume it without conflict).
- **Dependencies:** Waves 1–2. **Parallel-safe** with 3/4/6/7 (WorkDetail owns its files; the
  Account token is already unified in Wave 1).
- **Risks:** low–medium (hub is recent, well-tested). **Testing:** `verify.sh`; the existing
  `WorkDetailPresentationTests`; screenshot gate. **Complexity:** Small–Medium.

### Wave 6 — `Features/Account/` + `Features/Support/` (+ Inbox)

- **Goal:** Account hub, Inbox, and Support-screen adherence.
- **Findings:** **[HIG]** UI-2 (`AccountInboxViews` overlapping-button rows, `BugReportView`
  screenshot label + Link-vs-Button), UI-3 (`AccountInboxViews` 32pt bulk-bar icons), UI-6
  (`BugReportView` missing `.appThemedRows()/.appThemedScroll()`), UI-7 (Account/WorkDetail
  hub-chrome parity via X4); **[fold]** T91-RF10 (inbox redundant VoiceOver controls — same file),
  T91-RF6/RF8 (inbox empty-state drop / failed-pagination hides content — same file, correctness),
  A3-F1 (inbox avatar bypasses paced pipeline — same file, different concern: route through the
  paced image loader).
- **Shared components:** consumes X1, X3, X6. **Primary files:** `Features/Account/AccountInboxViews.swift`,
  `Features/Support/BugReportView.swift`, `Features/Account/AccountView.swift` (chrome token only).
- **Dependencies:** Waves 1–2. **Parallel-safe** with 3/4/5/7.
- **Risks:** T91-RF6/RF8/A3-F1 are correctness/networking, not a11y — review them with a
  functional lens even though they share the file. **Testing:** `verify.sh`; inbox parse/pagination
  tests (RF6/RF8); screenshot gate. **Complexity:** Medium.

### Wave 7 — `Features/Comments/` + `Features/Authors/` (UI layer only)

- **Goal:** comment-thread & author-profile UI adherence — **not** the comment parser/model
  (that is Track B2).
- **Findings:** **[HIG]** UI-2 (`CommentThreadRow` reply-structure invisible to VoiceOver), UI-3
  (`CommentsView` pagination/sort), UI-5 (`CommentThreadRow` expand/highlight + `CommentsView`
  scrollTo + Browse toast — all ungated animations), UI-2/UI-3 (`AuthorProfileContentSections`
  re-implemented selectable row → adopt shared `SelectableAO3WorkRow`); **[fold]** CAA-7
  (deep-thread cutoff renders as colliding tombstones — UI rendering, same file).
- **Shared components:** consumes X1, X2, X5; adopts existing `SelectableAO3WorkRow` (RemoteWorkSelection).
- **Primary files:** `Features/Comments/CommentThreadRow.swift`, `Features/Comments/CommentsView.swift`
  (UI paths only), `Features/Authors/AuthorProfileContentSections.swift`, `Features/Browse/BrowseView.swift`
  (toast).
- **Dependencies:** Waves 1–2. **Parallel-safe** with 3/4/5/6.
- **Risks:** `CommentsView` also holds the T-103 account-isolation logic — **touch only UI
  modifiers, not the auth/generation fencing**. **Testing:** `verify.sh`; do not perturb
  `CommentsAccountTransitionTests`; screenshot gate. **Complexity:** Small–Medium.

### Wave 8 — Dynamic-Type structural (UI-4) — higher risk, cross-directory

- **Goal:** the one wave that changes layout structure, not just modifiers.
- **Findings:** **[HIG]** UI-4 (fixed 164×228 cover-card frame → growth/stacked fallback at AX
  sizes; segmented-control AX fallback in `WorkDetailView`; `HomeSectionListView` see-all grid
  2-col → adaptive; Account shortcut grid reflow), plus the hero-fandoms `lineLimit(3)` and
  reader progress-pill (P3) if not already handled.
- **Shared components:** `UIComponents/CarouselCardStyle.swift` (frame), `UIComponents/SkeletonLoading.swift`
  (matching skeleton frame). **Primary files:** `CarouselCardStyle`, `Features/Home/HomeCards.swift`,
  `Features/Home/HomeSectionListView.swift`, `Features/WorkDetail/WorkDetailView.swift`,
  `Features/Account/AccountView.swift` (grid).
- **Dependencies:** Waves 2 and 5 (they touch `CarouselCardStyle` and `WorkDetailView` first for
  a11y — do those before the structural change to avoid two passes / conflicts). **Sequential, not
  parallel.**
- **Risks:** **highest layout-regression risk in Track A** — relaxing fixed frames can ripple
  through every carousel. Requires the runtime AX pass the HIG review already demonstrated
  (hero/quick-grid reflow) extended to cover cards.
- **Testing:** `verify.sh`; **mandatory runtime AX-XL screenshot pass** on Home, Library, Account,
  WorkDetail; density/screenshot gate. **Complexity:** Large.

### Wave 9 — Timing / navigation correctness (UI-8)

- **Goal:** replace timing magic-numbers with deterministic completion signals.
- **Findings:** **[HIG]** UI-8 (350ms `Task.sleep` modal-teardown sequencing at `CommentsView`
  ×2 + `AuthorProfileView`; 700ms `AppRouter` same-touch author-nav suppression).
- **Shared components:** consider one shared `router` onDismiss-continuation helper (the audit
  notes all three want the same pattern). **Primary files:** `Features/Comments/CommentsView.swift`,
  `Features/Comments/` composer, `Features/Authors/AuthorProfileView.swift`, `App/AppRouter.swift`.
- **Dependencies:** best after Wave 7 (shares `CommentsView`); **coordinate `AppRouter` with Track
  B1's A5-F7 hostname predicate** (same file). **Risks:** navigation-timing regressions are subtle
  — verify author-profile double-tap suppression and modal→push sequencing on a slow device
  profile. **Testing:** `verify.sh` + manual nav smoke. **Complexity:** Small–Medium.

### Wave 10 — Reader (UI-9 + BUG-7) — HIGHEST risk, own gate

- **Goal:** reader platform-split cleanup, macOS layout bug, reader a11y.
- **Findings:** **[HIG]** UI-9 (delete dead nested `#if os(iOS)` blocks in the macOS-guarded
  `ReaderController`/`ReaderView`, after porting the `.presentationContentInteraction(.scrolls)`
  that only survives in the dead copy; reconcile `letterSpacingRange` clamp divergence), UI-2
  (`CustomizeThemeView` sliders + swatch selection), UI-5 (reader-chrome fade, CustomizeTheme
  animations), UI-3/UI-4 (progress pill), BUG-7 (macOS reader renders under the sidebar);
  **[fold]** A7-F3 (macOS callback controller/WebView retention), A7-F5 (cross-spine state desync),
  A7-F8 (iOS chapter sheet drops nested TOC), T-98 GATE (scrolled-hang fix awaiting owner smoke —
  unmerged), T98-F4/F5/F6 (deferred reader perf/state items).
- **Shared components:** consumes X1, X2. **Primary files:** `Features/Reader/ReaderController.swift`,
  `Features/Reader/ReaderView.swift`, `Features/ReaderReadium/ReadiumReaderView.swift`,
  `Features/Reader/CustomizeThemeView.swift`.
- **Dependencies:** Waves 1–2; owner smoke on T-98 (Wave 0 / gate). **Sequential, last.**
- **Risks:** **highest in the plan** — macOS WKWebView, legacy controller, thin test coverage,
  and an unmerged in-flight fix (T-98). Do the dead-code deletion (UI-9) and BUG-7 layout fix as
  separate reviewable commits from the reader-correctness folds.
- **Testing:** `verify.sh` incl. macOS build; reader smoke on iOS (Readium) **and** macOS (legacy);
  the T-98 scrolled-mode owner smoke; screenshot gate. **Complexity:** Large.

---

## Track B — folded non-HIG concerns (separate branches, owner-prioritized)

These are open findings from the other audits that are **not** UI-adherence and do not share files
with the HIG waves (except where noted). They get their own branches and review lens so a UI branch
is never blocked on them. Order within Track B is owner's call; none blocks Track A except the
noted `AppRouter`/`MatureContent` file coordination.

| Track | Findings | Files | Notes |
|---|---|---|---|
| **B1 Security** | ~~A1-F2/KD-TEAMID~~ (resolved by Wave 0 — keep as-is, no action), A5-F5 (log hygiene), A5-F6 (Face-ID fail-open), A5-F7 (AO3 hostname predicate), A5-F8 (path in tracked doc), A7-F4 (macOS EPUB script) | `project.pbxproj`, `Services/AO3Client.swift`, `Features/Privacy/MatureContent.swift`, `App/AppRouter.swift`, `Services/`, `Features/Reader/ReaderController.swift` | **Coordinate:** A5-F6 shares `MatureContent.swift` with HIG UI-2 (Wave 7-adjacent); A5-F7 shares `AppRouter.swift` with Wave 9. Sequence these to avoid double-touch. |
| **B2 Comments Part D+** | CAA-8, CAA-9 (Part D, not started), CAA-10, CAA-12, CAA-13, CAA-14, CAA-15, BUG-6, A6-F5, A8-F3 (cache eviction) | `Services/` comment parser/model, `Features/Comments/CommentsModel` | Continues the T-97/99/102/103 line. Parser/correctness, not UI — keep off Wave 7. Heavy on fixture tests; **no live AO3**. |
| **B3 Functional correctness** | A6-F1 (folded to Wave 4), A6-F2 (Wave 2-adjacent), A6-F3 (account list pagination), A6-F4 (batch cancel), T91-RF4/RF7/RF9/RF11 | `Features/Library/`, `Features/Bookmarks/AO3AccountWorksList.swift`, `Services/`, `Models/` | RF6/RF8/RF10 already folded into Wave 6. The rest are standalone correctness. |
| **B4 Reader correctness** | A7-F6, A7-F7, A7-F9, A7-F10, T-07 (lazy extraction) | `Services/` EPUB/reader, `Features/Reader/` | Batch after Wave 10 (same area, but distinct from the a11y/dead-code work). |
| **B5 Performance** | A8-F1 (root whole-store observation — `App/ContentView.swift`), A8-F2 (backup peak memory) | `App/ContentView.swift`, `Services/KudosBackup.swift` | A8-F1 shares `ContentView.swift` with Wave 1's Sepia-segmented fix — coordinate. A8-F3 lives in B2. |
| **B6 Over-engineering** | PONY-6.1 (href resolvers — **fold to Wave 1**), PONY-4.7/4.10/6.4/6.5/6.7 (deferred / owner-decision) | `Services/`, parsers | Only PONY-6.1 is actionable now (and it rides Wave 1). The rest are deferred leads from T-104 §10 — leave as-is unless owner reprioritizes. |

### Explicitly out of scope for this roadmap (features & manual gates — list only)

Backlog **features**, not fixes: BL-HIGHLIGHTS (annotations), BL-TTS, BL-PH3-WRITES (verify),
T-20 (Readium Phase-4 polish), KD-LAYOUT-CHIPS/COLLECTION (deferred layout features),
KD-MIGRATION-META, BL-UIREFINE, the SHORT-R* compact-nav follow-ups. **Manual/owner gates**, not
code: DEBT-LIVE-AO3 (live-session verification), DEBT-KEYCHAIN (signed-device), DEBT-VISUAL,
BL-SYNC (real-device iCloud), APRR-RES1/BL-PH3-WRITES (write-path live verification), SHORT-MANUAL,
SHORT-R8 (test-only). These stay owner-owned; the roadmap does not schedule them.

---

## Branch Strategy

Aligned to `AGENTS.md` (feature branches off the `release-fixes` tip; **never** commit to `main`;
the **UI Consistency & Density Audit** human gate precedes any merge to `main`). The repo has scar
tissue about cross-branch pollution (the T-104/Codex Readium incident) — so keep branches
**short-lived, few, and rebased on the current tip before merge**, never a deep long-running stack.

**Spine (sequential cut → merge → cut):**

1. `claude/hig-w1-shared-foundation` ← `release-fixes`. Merge to `release-fixes` after the API +
   screenshot gates. **Everything else cuts from the updated tip.**
2. `claude/hig-w2-uicomponents` ← updated `release-fixes`. Merge before opening the parallel fan
   (later waves depend on the fixed shared components).

**Parallel fan (cut from the post-Wave-2 tip; disjoint files → no conflicts):**

3. `claude/hig-w3-search`, `claude/hig-w4-library`, `claude/hig-w5-workdetail`,
   `claude/hig-w6-account-support`, `claude/hig-w7-comments-authors` — run up to **~2–3
   concurrently** (not all five) to keep the density-gate review load manageable and rebasing
   cheap. Each merges independently.

**Sequential tail (higher risk, own gates):**

4. `claude/hig-w8-dynamictype` (after w2+w5+w7 merged — it re-touches their files).
5. `claude/hig-w9-timing-nav`.
6. `claude/hig-w10-reader` (last; needs macOS smoke + T-98 owner smoke).

**Track B** rides parallel branches on its own cadence: `claude/sec-hardening` (B1),
`claude/comments-part-d` (B2), `claude/functional-correctness` (B3), `claude/reader-correctness`
(B4), `claude/perf` (B5). Coordinate the three shared-file collisions called out above
(`AppRouter` ↔ W9/B1, `MatureContent` ↔ W7-adjacent/B1, `ContentView` ↔ W1/B5) by merging one side
first and rebasing the other.

> Naming note: the prompt's `feature/hig-wave-N` example is fine; the `claude/…` prefix above just
> matches this repo's existing branch convention. Either is acceptable — the important properties
> are **one wave per branch, cut from the current tip, merged before the next dependent wave.**

---

## Human Review Gates

The `AGENTS.md` UI-Consistency/Density screenshot gate is **mandatory before every UI wave merges
to `main`**. In addition:

1. **Wave 0 — decision gate. ✅ Resolved 2026-07-19** (BUG-8 → not a bug; team-id → keep as-is;
   manifest versions → raise floor to latest, unimplemented; migration-meta → split iOS
   Readium/macOS OPF; Compact-default → keep, no forced migration, plus a new app-wide-scope
   follow-up). Full detail: `TASKS.md` Key Decisions + T-117. Waves 4/10 and Track B1 are clear
   to start.
2. **After Wave 1 — API + visual gate.** Review the six helper signatures **before** mass
   application (a bad shared API multiplies across every later wave), plus a screenshot pass on the
   token-unification / theme-role visuals.
3. **After each UI wave (2–7) — density + screenshot gate.** Per `AGENTS.md`: title/author/fandom/
   progress/metadata visibility unchanged-or-improved; Light/Dark/Sepia/OLED intact; no new taps to
   reach metadata.
4. **Before Wave 8 — go/no-go.** Dynamic-Type structural changes are the highest layout risk; gate
   on a runtime AX-XL screenshot pass across Home/Library/Account/WorkDetail.
5. **Before Wave 10 — go/no-go.** Reader is the highest overall risk; gate on iOS **and** macOS
   reader smoke, plus the still-pending T-98 scrolled-mode owner smoke.
6. **VoiceOver / Dynamic-Type / Reduce-Motion runtime matrix.** The HIG review verified UI-2's
   VoiceOver findings **by code, not at runtime** (report §5.4/§9). Before closing the accessibility
   waves (2, 6, 7), the owner runs a VoiceOver / Accessibility-Inspector pass — this is the gate
   that confirms the two runtime-flagged UI-2 items (`CardNavigationModifier` stray stop; WorkStatLabel
   grouping) actually resolved.
7. **Track B security (B1) — separate security-review lens** (not the UI density gate); the team-id
   scrub additionally needs the owner's public-repo decision from Wave 0.

**Global testing bar (every wave):** `Scripts/verify.sh` ALL GREEN (incl. macOS build); new tests
per `docs/REGRESSION_TEST_MATRIX.md`; any `docs/*.md` statement a change falsifies updated in the
same commit; `TASKS.md` row updated with what was verified and what remains manual.
