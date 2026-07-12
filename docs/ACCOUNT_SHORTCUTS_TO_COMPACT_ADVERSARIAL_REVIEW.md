# Adversarial review: Account shortcuts redesign → compact work lists

**Date:** 2026-07-12  
**Branch:** `account-page-redesign-refinement`  
**Scope:** Uncommitted Account UI work after `e918382` (Swift 6 / processPool), plus product path from Overview shortcut redesign through native Dashboard, Detailed/Compact, privacy toggle.  
**Prior committed baseline on branch:** `cd5f9c7` / `e918382` (Account refinement + concurrency cleanup).

**Method:** Tree + full diffs of modified Account/Author/Bookmarks files + cross-read of Library compact pattern (`LibrarySectionListView`) + call-site greps. No full `Scripts/verify.sh` in this pass (build succeeded for iOS simulator earlier).

---

## Scope under review

| Area | What changed |
|------|----------------|
| Overview Shortcuts | AO3-style 6-item 3×2 **individual** icon cards |
| My Dashboard | Native user home via `AuthorProfileView` (not web, not a link dump) |
| More on AO3 | Sidebar long-tail only (drafts/skins/stats/challenges) |
| Work lists | Detailed/Compact + Library-style compact host (`ScrollView` + `NavigationLink`) |
| Toolbar | Display mode picker, Expand (detailed only), Mature reveal |
| Default | **Compact** is default for `account.displayMode` |
| Concurrency (committed) | `nonisolated` models, remove `WKProcessPool` |

---

## Status summary

| Severity | Count | Notes |
|----------|------:|-------|
| Blocker | 0 | None that prevent shipping if manual UI gate passes |
| Real bug | 4 | Dual-root gaps, dead route, AppStorage migration quirk, fandom chips in scroll |
| Minor | 5 | UX/density, unused residual, test gap |
| Residual risk | 3 | Manual / cross-platform |

---

## Findings

### R1 — Compact root omits surfaces that live only in List `tabSections` (real bug, partially mitigated)

**Where:** `AccountView.usesLibraryStyleCompactLayout` + `compactWorksContent`

When `displayMode == .compact` **and** the current secondary tab is a work list, Account swaps the entire root from `List` to `ScrollView`. That is correct for `NavigationLink` grids (Library pattern).

**Failure scenario:** User is in Compact on Reading → Later, then switches secondary menu to **Collections** (or Writing → Series/Drafts, Activity → Inbox). `showsWorkListControls` becomes false, so the root flips back to `List` and those surfaces appear. That path works.

**Remaining gap:** While still on a work-list secondary tab in Compact, the ScrollView chrome is a **reduced** Account shell (profile + segments + scope + works). Overview shortcuts, Preferences, More on AO3 are **not** on that shell — user must switch to Overview (or Detailed) to reach them. Intentional for density, but easy to misread as “Preferences disappeared.”

**Severity:** Real bug / product clarity — not a crash. Footer on Overview explains destinations; Compact shell has no equivalent reminder.

**Mitigation already present:** Segmented control still includes Overview.

---

### R2 — Auth `noticeMessage` was missing on Compact shell (real bug — fixed in this pass)

**Where:** `libraryStyleCompactRoot` vs `profileCardSection` footer

List mode shows `auth.noticeMessage` under the profile card. Compact ScrollView shell did not.

**Failure scenario:** Session notice / soft error after verify is invisible while user stays on Compact work lists.

**Status:** Fixed in-tree during review (footnote under profile card on compact shell).

---

### R3 — `Route.inbox` / `AccountInboxListView` are effectively dead (minor / dead code)

**Where:** `AccountView.Route.inbox`, `destination`, `AccountInboxListView`

After Dashboard stopped being a link dump, nothing in the UI `path.append`s `.inbox`. Inbox is only Activity → Inbox (shared `inboxModel` on the tab, not the pushed list).

**Failure scenario:** None for users; maintenance trap (two inbox UIs, one unused).

**Severity:** Minor. Prefer delete `Route.inbox` + `AccountInboxListView` or wire a single entry point.

---

### R4 — Fandom filter `Section` embedded in ScrollView compact Works (real / minor layout)

**Where:** `profileContentSections(layout: .scroll)` still embeds `AO3AuthorFandomFilterSection`, which is implemented as a List `Section`.

**Failure scenario:** On Compact → Writing → Works (or Reading → Bookmarks path uses profile sections for bookmarks only; Works uses fandom chips), chip strip may get odd spacing/accessibility when not inside a `List`.

**Severity:** Real-bug for layout polish on Compact Works; verify on device.

---

### R5 — AppStorage default Compact does not migrate existing users (minor / expected)

**Where:** `@AppStorage("account.displayMode") … = .compact`

Default applies only when the key is **absent**. Anyone who already launched with the previous default (`detailed`) keeps Detailed until they change the menu.

**Failure scenario:** Reviewer / long-running sim user thinks “default compact” failed.

**Severity:** Minor. Acceptable AppStorage semantics; document if product wants a force-migration.

---

### R6 — Mature reveal gated on *any* library adult work, not on-screen list (minor)

**Where:** `showsMatureRevealControl` uses full `@Query` of local works.

**Failure scenario:** Eye icon appears on History even when the loaded page has no local adult pairing (still useful if a later page might). Matches “has mature in library” more than “this screen is blurred.”

**Severity:** Minor; same class of approximation as some Home toolbars.

---

### R7 — Dual root destroys list state when flipping Detailed ↔ Compact (minor)

**Failure scenario:** Pagination page, expand-all, and scroll position reset when toggling layout because `AccountWorksInlineSection` is recreated under a different host (`list` vs `scroll`).

**Severity:** Minor; same class as Library switching display mode on a pushed section list.

---

### R8 — No automated tests for shortcuts / compact navigation / dual root (minor)

No new tests under `KudosTests` for:

- Overview shortcut tab routing  
- Compact `NavigationLink` destinations (`SavedWork` / `AO3WorkSummary`)  
- Layout host switch when `displayMode` changes  

**Severity:** Minor for a UI-heavy change; human screenshot gate remains binding (AGENTS.md).

---

### R9 — Unused `PrivacyGate` environment (fixed)

`@Environment(PrivacyGate.self) private var gate` was unused (static `PrivacyGate.hasVisibleMatureWorks` only). Removed during review.

---

## Cross-cutting critic

| Concern | Verdict |
|---------|---------|
| Conflicting dual implementations of compact nav | **Resolved in intent** — Library ScrollView+`NavigationLink` adopted; earlier Button/selection and List-embedded grids removed from happy path |
| Scope creep | High but **coherent product arc** (shortcuts → dashboard meaning → list density → privacy parity). Concurrency commit is separate and already landed |
| Platform | iOS path heavily exercised in sim; **macOS Account compact ScrollView** not verified in this pass |
| Docs / TASKS.md | Uncommitted work **not** reflected in `TASKS.md` or onboarding docs |
| Invariants | No model schema / backup / AO3 write-path changes in the uncommitted UI delta. Networking only via existing profile/list fetchers |
| pbxproj | New `AO3DashboardView.swift` is under synchronized group — **no pbxproj edit required** |

---

## What looks solid

1. **Dashboard semantics corrected** — user home (`AuthorProfileView`), not a sidebar sitemap. Long-tail remains More on AO3 + Browse.  
2. **Compact navigation** — hosting grids outside `List` matches Library and fixes last-card / multi-back defect.  
3. **Privacy control restored** on Account work-list toolbars.  
4. **Display mode** shared via `account.displayMode` with refine lists (`AO3AccountWorksList`).  
5. **Committed Swift 6 / processPool cleanup** is low behavioral risk if build stays green on both platforms.

---

## Manual verification still required

- [ ] Fresh install: Account work lists open in **Compact** by default  
- [ ] Compact: tap several different covers → correct work; single Back returns to list  
- [ ] Compact ↔ Detailed toggle; Mature eye show/hide and blur/reveal  
- [ ] Compact → switch to Collections / Series / Drafts / Inbox / Overview (root flip to List)  
- [ ] My Dashboard vs avatar profile (own author surface, own-profile actions only)  
- [ ] Shortcut grid: each of 6 destinations  
- [ ] macOS Account compact + toolbar  

---

## Verdict

**Ship-ready after human UI pass**, with R3 (dead inbox route) and R4 (fandom chips in scroll) as follow-ups, not merge blockers if density/UX accepted.

**Do not claim done** until the checklist above is exercised on a device/sim with a session that has mature library works and multi-page history.

---

## Suggested next steps (optional)

1. Commit uncommitted Account UI + this review (or fold review into TASKS.md row).  
2. Remove or wire `Route.inbox` / `AccountInboxListView`.  
3. Adapt `AO3AuthorFandomFilterSection` for non-List hosts (plain `VStack` chips).  
4. Run `Scripts/verify.sh` + macOS build before merge-test stack.
