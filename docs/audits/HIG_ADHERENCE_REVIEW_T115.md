# HIG Adherence Deep-Dive Review — T-115

**Type:** Review-only (no implementation).
**Branch:** `claude/hig-review-task-f5e043` (from `release-fixes` tip `08cbc11`).
**Date:** 2026-07-18. **Reviewer:** Claude (multi-agent workflow + live simulator/macOS passes).
**HIG source:** https://developer.apple.com/design/human-interface-guidelines/ (fetched live during review).

---

## 1. Method & evidence chain

- **HIG research:** 6 parallel research agents read the relevant HIG sections live from
  developer.apple.com (Materials/Color/Typography; Layout & Navigation-and-search; components
  incl. segmented controls, lists, sheets, toolbars, inspectors; Accessibility — VoiceOver,
  Dynamic Type, Reduce Motion, hit targets, contrast; iOS Design; macOS Design) and distilled
  each into testable criteria for a SwiftUI reader app.
- **Codebase audit:** 10 parallel area-audit agents covered the prompt's full scope (root
  interface layer; T-114 Work Detail hub; `UIComponents/`; Search; Home; Library; Account +
  Settings; reader chrome + customization; author profiles/Browse/Comments; onboarding/privacy
  gate/auth/support + app-wide accessibility grep sweeps), each citing file/line evidence.
- **Synthesis:** per-area strengths / minor deviations / potential issues, cross-referenced
  against the HIG criteria.
- **Adversarial verification:** every one of the **56 potential issues** was independently
  re-verified by a skeptic agent that re-read the actual source (and re-ran any claimed grep
  sweeps) before a verdict. Result: **52 confirmed** (24 P2, 28 P3 — final severities are the
  verifier's, which downgraded or refuted every provisional P1), **4 refuted** (§6).
  The verification pass spanned three sessions due to usage limits; the full merged verdict
  set is preserved (see §8 Evidence).
- **Runtime passes (seen, not inferred):** iPhone 17 simulator (iOS 26.5) across Sepia / Dark /
  OLED / Light themes, default + accessibility-XL Dynamic Type, and Reduce Motion on/off; the
  real macOS app (owner's data) across Home, Library, Browse, Search, Account, About, and the
  legacy reader. §5 has the notes; §7 lists the screenshots.

**Caveat on scope:** the per-area *minor deviations* (§4) are single-pass audit output and were
**not** adversarially verified — only the §3 potential issues were. Treat §4 items as leads.

---

## 2. Strengths / excellent adherence

The app's overall HIG posture is strong: the audit produced **zero confirmed P1s**, and the
recurring pattern in the evidence is that the *canonical* implementation of each pattern in the
codebase is correct — the findings are mostly siblings that missed the canonical treatment.

- **Navigation architecture.** Root TabView exposes exactly the HIG-recommended 4 destinations
  + Search role; every tab pairs an SF Symbol with a text label; iPadOS uses the adaptable
  tab-bar/sidebar pattern rather than a hand-maintained sidebar; Browse/Author/Comments are
  clean typed push hierarchies with modality reserved for genuinely separate tasks
  (`App/ContentView.swift`, `Features/Browse/NativeBrowseView.swift`).
- **Liquid Glass discipline.** Glass is confined to the functional/navigation layer (floating
  reader chrome, toolbar pills); content-layer cards deliberately use opaque theme-token
  surfaces — exactly the sanctioned alternative. `UIComponents/` documents the pill-grouping
  interaction (`ToolbarIconButton`) rather than fighting it.
- **T-114 Work Detail hub is a genuinely strong reference implementation:** 44pt tag-chip hit
  targets with the HIG cited in-comment, quick-action grid drops 3→2 columns at accessibility
  sizes (**runtime-confirmed**, §5), scoped VoiceOver grouping (stat pills combined, co-author
  buttons individually focusable), Reduce-Motion-gated animations (**runtime-confirmed**, §5),
  correct sheet-vs-push discipline.
- **Reader chrome.** Platform-correct supplementary UI (macOS inspector pane / iOS detented
  sheet with grabber); immersive chrome is a coordinated tap-to-toggle system; swipe-to-dismiss
  is Reduce-Motion-aware; theming/typography are single-source-of-truth between the
  customization UI and both rendering engines; `TextSizeSlider` is a model accessible custom
  control (label + value + adjustable).
- **Accessibility exemplars exist for every pattern the findings flag elsewhere:**
  `OnboardingPointRow` (grouped row, hidden decorative icon, growing text), `SkeletonShimmer`
  (central Reduce Motion accommodation with static fallback — **runtime-corroborated**, §5),
  `SensitiveWorkRow` (labeled reveal buttons, collapsed noisy content), `SearchPaginationBar`'s
  VoiceOver scaffolding, Library's swipe-actions-duplicated-into-context-menus rationale
  comment, `AO3LoginView`'s AutoFill/keyboard wiring and Sepia Form pattern.
- **Empty/error states** use native `ContentUnavailableView`; destructive actions consistently
  route through native `confirmationDialog`/`alert` with specific consequence text (the §3
  exceptions are misapplied *roles*, not missing confirmations).
- **Dynamic Type resilience where it matters most:** `WorkRow`/`AO3WorkRow` wrap or expand
  instead of clamping; the T-114 hero card reflows cleanly at AX sizes (**runtime-confirmed**,
  §5); `FlowLayout` measures subviews so chips reflow rather than clip.

---

## 3. Confirmed potential issues (52 — all adversarially verified)

Grouped thematically; every item was re-verified against source by an independent agent.
Severities are the verifier's. Registry rows: **UI-2 … UI-9** and **BUG-7 / BUG-8** in
`TASKS.md`.

### 3.1 VoiceOver labeling & grouping gaps (→ UI-2, P2)

The canonical treatments exist in-repo (see §2); these sites missed them:

- `UIComponents/WorkStatLabel.swift:7-21` — raw `HStack{Image;Text}`, zero a11y modifiers; every
  card's stats read as disconnected icon-name + text fragments. Same for `CardMetaLabel`
  (`Features/Home/HomeCards.swift`).
- `Features/Comments/CommentThreadRow.swift:331-461` — reply structure (is-a-reply, to whom,
  depth) is conveyed *only* by the accessibility-hidden spine/rail chrome; invisible to
  VoiceOver. HIG: never convey information through visual presentation alone.
- `Features/Account/AccountInboxViews.swift` — notification rows are a ZStack of 5 overlapping
  buttons; no combined element + custom actions.
- `Features/Library/RecentlyDeletedView.swift:182-207` — row pieces surface as 3 disconnected
  stops; file has no a11y modifiers at all.
- `Features/Reader/CustomizeThemeView.swift:196-217` — all four sliders unlabeled (VoiceOver
  announces an anonymous slider with a raw % that contradicts the visible "1.45"-style value);
  `:163-190` — theme swatch selection is ring-color-only, no `.isSelected`, no non-color cue
  (also a Color finding). `TextSizeSlider` next door does it right.
- `Features/Library/LibraryFilterPanel.swift:143-158` — `selectableRow` checkmark without
  `.isSelected` (the sibling `filterChip` in `LibraryView.swift:443` has the trait);
  `Features/Search/AO3FilterPanel.swift:183-205` — `cyclingFacetRow` include/exclude state not
  combined into one element.
- `Features/Privacy/MatureContent.swift:289,296` — the *blurred* branches of
  `SensitiveWorkCoverCard` use bare `.onTapGesture` (no button trait) for reveal/select while
  the non-blurred branches and `SensitiveWorkRow` use real Buttons; `:184,195` — the outer
  `children: .ignore` swallows the nested `WorkRowExpandButton`, making expand unreachable
  under VoiceOver.
- `UIComponents/AppThemeSurface.swift:265-277` — `CardNavigationModifier`'s opacity-0
  NavigationLink likely adds an unlabeled focusable stop to *every* card (needs a VoiceOver
  runtime check — flagged, not runtime-verified).
- `Features/Authors/AuthorProfileContentSections.swift:309-321` — re-implements the shared
  selectable row minus its hint + `.isSelected` (P3; delete in favor of `SelectableAO3WorkRow`).
- `UIComponents/TagChip.swift` — no a11y parameters; `LibraryView.swift:436-444` already
  hand-patches around it (P3).
- `Features/Support/BugReportView.swift:94-99` — attached screenshot unlabeled (P3); `:53-58` —
  "Continue on GitHub" gates a `Link` with `.disabled()`, whose disabled semantics for
  VoiceOver are undefined vs. Button (P3).
- `Features/WorkDetail/WorkDetailComponents.swift:156-157` — tile applies `.combine` +
  `.isButton` *inside* a wrapping Button → doubled announcement risk (P3).
- **Systemic:** 126 of 160 Swift files carry no accessibility modifiers (grep re-run by the
  verifier), incl. 16 control-heavy files (`WorkCardActions.swift` alone: 17 controls, 0
  modifiers). This is the backlog umbrella for the sweep.

### 3.2 Hit targets below the 44pt default (→ UI-3, P2)

HIG: 44×44pt default on iOS/iPadOS (28pt absolute floor). All verified sub-default:

- `Features/Account/AccountInboxViews.swift` — bulk-action bar icons `minHeight: 32`.
- `Features/Search/SearchPaginationBar.swift:64,131` — 31×31pt nav/page buttons (arrows use a
  *fixed* frame that can't grow with Dynamic Type; page buttons at least use min-frames).
- `Features/Library/WorkRow.swift:186-202` — `WorkRowExpandButton`, small bordered circle, no
  frame/contentShape guarantee.
- `Features/WorkDetail/WorkDetailSections.swift:403-409` — icon-only Remove-tag button, while
  tag chips at :54-60 in the *same file* got the deliberate 44pt fix.
- `UIComponents/AO3AuthorNavigation.swift:127-140` — tappable author names sized to text glyphs
  (~15-20pt tall) on nearly every row/card in the app.
- `UIComponents/ReorderHandle.swift:13` — 28×28pt drag handle (absolute floor, not default),
  no hint describing the drag, and per its own doc comment it is the *only* reorder mechanism.
- `UIComponents/WorkCarouselSection.swift:58-84` — section collapse toggle and the see-all
  chevron (sole entry to the full list) both content-hugging.
- `Features/Comments/CommentsView.swift` — pagination Previous/Next + sort Menu lack the
  44pt min-frame their sibling controls in the same file reserve (P3).

### 3.3 Dynamic Type — fixed frames & truncation (→ UI-4, P2)

- `UIComponents/CarouselCardStyle.swift:19-23` + `Features/Home/HomeCards.swift:44-48` — the
  fixed 164×228pt cover-card frame with `.lineLimit` and no `minimumScaleFactor`/growth path.
  **Runtime-confirmed at AX-XL** (§5): title/author/fandom truncate to near-uselessness
  ("The Q…", "JYN0…", "Froze…") across Home/Library carousels. `WorkStatLabel`'s
  `.lineLimit(1)` + `.fixedSize()` chain additionally forbids wrap/shrink.
- `Features/WorkDetail/WorkDetailView.swift:221-232` — the hub's primary segmented control has
  no AX-size fallback (native segmented controls cap label scaling rather than reflow;
  runtime-observed at AX-XL, §5) — while the quick-action grid in the same file demonstrates
  the correct pattern.
- `Features/WorkDetail/WorkDetailComponents.swift:58-63` — hero fandoms line `lineLimit(3)`,
  no expand affordance (title above it wraps unlimited; summary has Show More) (P3).
- `Features/ReaderReadium/ReadiumReaderView.swift:848-851` — progress pill: scaling `.footnote`
  text inside a fixed 40pt capsule, `lineLimit(1)`, no backstop (P3; macOS analogue static).
- `Features/Home/HomeSectionListView.swift:200-228` — "Apple Books-style" see-all grid
  hard-codes 2 columns; never widens on iPad/macOS (adaptive-width, not text, but same family).
- Account Overview shortcut grid shrinks text via `minimumScaleFactor` at a fixed 3-column
  layout instead of reflowing (single-pass sibling of the confirmed grid finding).

### 3.4 Reduce Motion coverage (→ UI-5, P2)

Grep re-verified: **3 files** read `accessibilityReduceMotion` (all correctly gating) while
**15 files** use `withAnimation`/`.animation(...)`. Confirmed ungated spatial animation sites:

- `Features/Comments/CommentThreadRow.swift:690,770,779` + `CommentsView.swift:273,289`
  (animated scrollTo) + `BrowseView.swift:119,147-150` (toast `.move` transition).
- `UIComponents/WorkCarouselSection.swift` — collapse/expand `withAnimation(.snappy)`.
- Reader chrome show/hide fade (iOS) — the same view already reads the env value for a
  sibling animation; `CustomizeThemeView` toggle/reset; Reading Statistics
  `.contentTransition(.numericText())` (§4 leads, same family).
- The three exemplary gated sites (WorkDetail ×2 + SkeletonShimmer) are the pattern to copy;
  runtime pass (§5) confirmed both behave correctly with Reduce Motion on.

### 3.5 Theming & color-role hygiene (→ UI-6, P2)

- `App/ContentView.swift:250-268` — Sepia segmented-control theming via a *global UIKit
  appearance proxy* with hardcoded RGB literals; can't adapt to Increase Contrast/Reduce
  Transparency and hits every segmented control app-wide (P3 after verification, but the
  registry groups it here).
- `Features/Search/TagSelectField.swift:326-328` + `AO3FilterPanel.swift:199` — excluded-state
  hardcodes `.red` (plus a third site the verifier found); Sepia contrast unverified; no
  semantic "exclude" role in ThemeManager.
- `Features/Support/BugReportView.swift:70` — the app's own required Sepia modifiers
  (`.appThemedRows()`/`.appThemedScroll()`) are missing; verifier confirmed it is the sole
  outlier among all 12 grouped-Form screens (P3, two-line fix).
- `Features/Search/AO3FilterPanel.swift:138` — "Reset Filters" carries `role: .destructive`
  for a recoverable action; `Features/Library/Collections.swift:134-140` — swipe "Remove"
  styled destructive though the file's own doc comment says it's non-destructive;
  `UIComponents/WorkCardListControls.swift:32-38` — "Clear All Filters" is context-menu-only
  *and* unconfirmed, diverging from the app's destructive-action pattern (all P3; color-role
  consistency: red should keep one meaning).

### 3.6 Cross-platform & internal consistency (→ UI-7, P2)

- `Features/Library/LibraryView.swift:48-64,496-501` vs `LibrarySectionListView` — bulk-select
  exists twice, incompatibly: the dashboard's is `EditMode`-based and structurally absent on
  macOS, while the section list one level down has a cross-platform Bool-based select mode.
  macOS users get no select mode at the entry point that advertises it (P2).
- `Features/Library/LibraryView.swift:149-156` — selection mode hides the tab bar (non-modally)
  to mask a Liquid Glass ambient-bleed artifact; HIG sanctions tab-bar hiding only in modal
  contexts (P3; fix the bleed, not the chrome).
- Hub-chrome divergence (P3): Account uses the 20pt `accountControlCardRow` everywhere; Work
  Detail uses it *only* for its picker and 16pt `cardRow` elsewhere (incl. the hero), plus a
  stray 14pt tile literal — despite `WorkDetailComponents.swift:3-7`'s comment claiming
  sibling parity. Author Profile's picker uses a third shell (§4).
- Disclosure-affordance misuse (P3): Overview's Comments row shows `chevron.right` but only
  switches the segmented tab (`WorkDetailOverviewSections.swift:252-273`); Add-to-Queue /
  Add-to-Collection rows chevron into *sheets* (`WorkDetailSections.swift:249-274,302-328`).
  HIG reserves the disclosure indicator for hierarchical push.
- `Features/Search/SearchView.swift:220-233` — the identical pagination bar renders twice
  (above and below results) with identical a11y labels (P3).
- `Features/Search/SearchPaginationBar.swift:72-93` — jump-to-first/last long-press is
  disclosed to VoiceOver only; no sighted-user affordance (P3; mitigated by the always-visible
  first/last page pills).
- `Features/Library/LibraryFilterPanel.swift:166-192` — multi-select field opens a `.sheet`
  from inside the `.inspector` (which is itself a bottom sheet on iPhone) — sheet-on-sheet
  on that platform (P3).

### 3.7 Timing magic numbers standing in for completion signals (→ UI-8, P2/P3)

- `Features/Comments/CommentsView.swift:557,1118` + `AuthorProfileView.swift:64x` — 350ms
  `Task.sleep` sequences modal teardown before the next push, ×3 sites (P2).
- `App/AppRouter.swift:152-164` — 700ms sleep suppresses same-touch author-profile double
  navigation; correctness depends on device timing (P3).

### 3.8 Platform-split code health (→ UI-9, P3)

- `Features/Reader/ReaderController.swift` + `ReaderView.swift` — globally
  `#if os(macOS)`-guarded files containing nested `#if os(iOS)` blocks that can never compile,
  and the dead copy already diverged from the live one: `.presentationContentInteraction(.scrolls)`
  exists *only* in the dead variant, not the live iOS reader sheet.
- `ReaderStyle.swift:246,301-309` vs `ReadiumReaderView` — shared `letterSpacingRange`
  (-0.03…0.12) renders unclamped on macOS but is clamped to ≥0 on iOS, so the negative half of
  a shared persisted setting is platform-dependent.

### 3.9 Live-found macOS bugs (→ BUG-7, BUG-8)

Found in the live macOS pass (§5.3), not by the static audit:

- **BUG-7 (P2):** the legacy macOS reader lays its WKWebView content out under the overlaid
  sidebar — the leading edge of every preface/metadata line is occluded ("~~Post~~ed
  originally on…", "~~Teen A~~nd Up Audiences", "~~Categor~~y:"); content is centered
  relative to the full window, not the detail column. Reproduced 2026-07-18 on "The Queen's
  Mercy" with the sidebar visible. `Features/Reader/ReaderView.swift` /
  `ReaderController.swift` (macOS-only path).
- **BUG-8 (P3, owner decision):** on macOS, clicking a Library card opens the *reader*
  directly, bypassing the Work Detail hub — contradicting the documented decision
  ("Library cards open the work's **detail** page… by design", TASKS.md Key decisions) which
  carries no platform qualifier. Possibly never ported to macOS; intended divergence or bug?

---

## 4. Minor deviations / polish opportunities (single-pass — **not** adversarially verified)

Curated from the 66 single-pass synthesis items; the full set lives in the evidence JSON (§8).
Recurring themes:

- **Token hygiene:** spacing/radius/shadow literals instead of shared tokens — sidebar capsule
  padding, `GlassFieldBar` metrics, TagChip off-grid padding, onboarding scaffold literals,
  three coexisting card radii (14/16/20pt), Sepia warm-brown literal duplicated ×5, Collections
  vs Reading-Queue card shadows diverging, comment-pill paddings ×3, composer radius 12.
- **Small a11y leads:** Text-Size slider's flanking "A" glyphs announced as bare stops; macOS
  reader prev/next chapter buttons rely on SF-symbol default names; quick-action tile busy
  state has no `.accessibilityValue`; login/bug-report fields don't auto-focus; "Not Now" /
  "View on GitHub" text-sized targets.
- **Pattern consistency:** primary Search field is a custom `GlassFieldBar` while two sibling
  pickers in the same feature use native `.searchable()` (undocumented rationale); Search
  hand-rolls its back button + edge-swipe recreation; Home carousels don't snap-align
  (`scrollTargetBehavior(.viewAligned)`); Home mixes `.toolbarTitleDisplayMode(.inlineLarge)`
  with the older inline API one push deeper; sheet detents follow no content-driven rule;
  two different destructive-confirmation idioms across the two bulk-action bars; Author
  Profile / Comments segmented pickers use divergent shells; Reset Theme is styled destructive
  but fires without confirmation.
- **Layout/behavior leads:** local vs remote cover cards disagree on fandom lineLimit (1 vs 2);
  content-warning text at `.caption2` (smallest ramp) for safety-relevant info;
  `ReadingStatisticsView` detail text `lineLimit(1)`; per-work context menu ~9 mixed actions
  with no `Divider()` grouping and inline Delete; the live iOS reader sheet is missing
  `.presentationContentInteraction(.scrolls)` (see §3.8 — the dead macOS copy has it);
  `MediaBrowserView` needed a manual `listRowBackground` clear-out under Sepia (evidence the
  theme doesn't flow through List chrome by default); launch housekeeping is one long
  sequential await chain; series rows push a full second hub per hop.
- **Noted for follow-up:** `ThemeManager.swift` holds no palette — the real Light/Dark/Sepia
  colors live in `ReaderTheme`, which was outside the audited file set, so **palette contrast
  ratios (4.5:1) remain unaudited** (§9).

---

## 5. Runtime verification notes (seen in this review, 2026-07-18)

### 5.1 Dynamic Type (iPhone 17 sim, `content_size accessibility-extra-large`)

- **Work Detail hero card reflows correctly:** title wraps to 2 lines, stat pills restack
  vertically, nothing truncates (`ios_dark_workdetail_AX2.png`).
- **Quick-action grid drops 3→2 columns as designed** — all 8 tiles fully readable, zero
  truncation (`ios_dark_workdetail_AX2_grid.png`). T-114's accommodation works.
- **Segmented control does not reflow:** all four labels stay on one row with visibly capped
  label scaling — readable but far smaller than surrounding text; corroborates §3.3.
- **Carousel cover cards break down badly:** Library/Home cards truncate nearly every field
  ("The Q…", "JYN0…", "Froze…", "Busine…", "Wedn…") — primary content lost at AX sizes
  (`ios_dark_library_AX2_truncation.png`, plus the Account Activity grid variant seen in the
  Sepia pass). Corroborates §3.3's top finding.

### 5.2 Reduce Motion (system-wide via `com.apple.Accessibility ReduceMotionEnabled`)

- **Skeleton loading:** Account cold-open shows placeholders that resolve with no shimmer
  sweep — consistent with `SkeletonShimmer`'s static fallback (and with refuting the §6
  claim against it).
- **Work Detail section switching:** the frame captured immediately after tapping Tags shows
  the section fully rendered — instant switch, no mid-transition state (`animateUnlessReduced`
  behaves as designed).
- Not runtime-checked: the §3.4 *ungated* sites (comment expand/highlight, Browse toast,
  carousel collapse) — static evidence stands on its own (exact `withAnimation` sites cited).

### 5.3 macOS live pass (real app, owner's data)

- Home / Library dashboards, Browse categories (real counts), Search (live per-keystroke
  library results for "queen"), Account (signed-out state), About — all render correctly in
  Dark; Library shows fandom chips, mature-blur "Tap to reveal" cards, Finished empty-state,
  Reading Queues.
- **BUG-7 reproduced** (reader under sidebar — §3.9) and **BUG-8 observed** (card → reader
  routing).
- macOS screenshots could not be saved to files (the shell lacks the Screen Recording
  permission `screencapture` needs; `simctl` covers only the simulator). The observations
  above were made live through the review's screen-capture tooling; the owner's manual gate
  (§9) should re-capture macOS evidence if files are wanted.

### 5.4 VoiceOver

**Not runtime-verified.** All §3.1 VoiceOver findings are static-analysis conclusions from
code reading (each verified against source by a second agent, but announcement order/behavior
was not exercised with VoiceOver or Accessibility Inspector). The two findings that
specifically need a runtime check are marked in-place (`CardNavigationModifier`'s stray stop;
the quick-action tile double-announcement).

---

## 6. Refuted findings (4) — dispositions

1. **Home cover cards lack aggregate a11y grouping → refuted.** Every carousel card is hosted
   in a `NavigationLink`, which SwiftUI groups into a single focusable element automatically.
   No action. (The *stat-label* grouping finding, §3.1, stands — it's about phrasing, not
   fragmentation.)
2. **LibrarySectionListView swipe rows lack a context-menu fallback → refuted.** The menu is
   attached one composition layer down (`SensitiveWorkRow.visibleRow` →
   `.localWorkContextMenu`). No action.
3. **Account skeleton shimmer ignores Reduce Motion → refuted.** Central accommodation in
   `SkeletonLoading.swift:38-47`; call-site gating would be redundant. Recorded as a strength
   (§2); runtime-corroborated (§5.2).
4. **AccountScopeMenu icon tint inconsistency → refuted.** The cited comment documents the
   pitfall the code *avoids*; the unconditional `.foregroundStyle(.tint)` at :314-315 is the
   fix already applied. No action.

---

## 7. Screenshot inventory (iPhone 17 sim, iOS 26.5)

23 PNGs, copied for owner review to `~/Downloads/HIG_T115_evidence/hig_screenshots/`
(originals in the session scratchpad):

- **OLED (owner's theme):** home, library, workdetail_{overview,tags,discussion,library},
  search, search_results, account.
- **Sepia:** home, library, workdetail_{overview,tags,discussion,library}, search, account,
  plus `ios_sepia_current.png` (Account Activity grid at an AX size — truncation evidence).
- **Dark:** home (with mature-blur reveal pill visible), workdetail_overview,
  workdetail_AX2 (hero reflow), workdetail_AX2_grid (3→2 grid), library_AX2_truncation.
- **Light:** verified live in an earlier pass of this review (Settings/Search/Work Detail
  seen); Light-theme captures were not persisted to files — listed for the owner gate.

Evidence JSONs alongside: `final_verified_findings.json` (56 findings + verdicts),
`hig_full_result.json` (research + synthesis + areas), `completeness_critique.json`.

---

## 8. Evidence & provenance

- Research/audit/synthesis/verification ran as `Workflow` runs across three sessions
  (2026-07-18): the primary run (6 research + 10 audit + 10 synthesis agents; 23 verifications
  landed before a usage limit), a resume run (remaining synthesis + verifications; second
  usage limit), and a recovery session that re-ran the 33 lost verifications + a completeness
  critique. Verdicts were merged from the recovery workflow's journal and cross-checked
  against its persisted output (0 mismatches) before this document was written.
- The completeness critique's 9 gaps were each addressed or explicitly recorded here: macOS
  file-captures and VoiceOver runtime remain honest limitations (§5.3, §5.4, §9); severity
  counts in this doc use the verifier's final numbers; §4 is labeled single-pass; HIG source
  URLs are attached below.
- Key HIG references: /materials, /color, /typography, /layout, /navigation-and-search,
  /searching, /segmented-controls, /lists-and-tables, /sheets, /toolbars, /inspectors,
  /accessibility, /designing-for-ios, /designing-for-macos
  (all under https://developer.apple.com/design/human-interface-guidelines/).

## 9. Remaining manual gates (owner)

- Screenshot review (the §7 set + re-capture macOS evidence as files if wanted).
- A VoiceOver / Accessibility Inspector pass over Home cards, Library rows, Customize Theme
  sliders, and one comment thread (validates §3.1's two runtime-flagged items and the
  announcement-order conclusions).
- Decision on BUG-8 (macOS card→reader routing: intended divergence or port gap).
- `ReaderTheme` palette contrast audit (4.5:1 per theme) — explicitly out of this review's
  file set (§4 last bullet).
- Prioritization of UI-2 … UI-9 (suggested order: UI-2/UI-3 first — highest user impact,
  mostly mechanical fixes with in-repo exemplars to copy).
