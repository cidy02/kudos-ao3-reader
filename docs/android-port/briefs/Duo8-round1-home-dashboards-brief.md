# Duo8 — iPhone Duo round 1: Home and the Library dashboard, composed for the inner display

**Agent:** Codex. **Worktree:** `~/kudos-agent-ios`, branch `claude/agent-ios-duo8` (from the iOS lane's
`64979c71`). iOS only. Duo5c (the reader) runs at the same time in `~/kudos-agent-ios2`: don't touch
`Features/ReaderReadium/`.

## Decided (Claude-CLI, owner-delegated; `docs/android-port/DECISIONS.md` 2026-10-24)

Your Duo7 plan (`docs/android-port/briefs/Duo7-plan.md`, copied here) is the direction. This brief is its
**Round 1**, as you wrote it, with these decisions: the root stays the system TabView; layout by measured usable
space, never by "is a Duo"; no information or density lost, no smaller type; nothing on the fold in Book pose;
the cover and the iPhone unchanged; the iPad gets the same where it fits. Model: Apple Books' Home and Music's
Home on iPad.

## Round 1 (from Duo7)

**Outcome:** opening the inner display shows a composed reading app, not a stretched phone; in Book pose no card
or text crosses the fold.

**Files:** a proposed `UIComponents/AdaptiveContentRegions.swift` (usable regions: safe bounds, active
reserved regions in local coordinates, pane rectangles, fit results); `UIComponents/HorizontalScrollViewport.swift`
(pane/group composition only; keep T-447's behaviour); `UIComponents/TabDashboardShell.swift`;
`Features/Home/{HomeView,HomeResumeHero,HomeCollectionShelves}.swift`; `Features/Library/LibraryView.swift`
(dashboard content). No root navigation change.

**Brief:** derive usable regions and fit thresholds; put the Continue Reading hero beside the next reading works
instead of full width; bounded two-row card groups for wide shelves and pane-aware groups in Book pose (a card
never clipped at the fold; split shelves into pane-contained pages rather than masking the middle); keep compact
branches and the original items and order. Extend the existing `CarouselCardGrid` where needed, no second sizing
system. Use the 27.1 SDK's reserved-region API (`GeometryProxy.reservedRegions(kind:options:...)` or UIKit's
`UIView.reservedRegions(kind:options:)`; confirm the exact signature in the SDK on this Mac) with the iOS
availability guard the deployment target needs; on systems without it, no fold.

**Risks (yours, keep them in view):** clipping instead of reflowing, duplicate items, blank loading width,
author/privacy leaks (hidden mature titles), changing the first work or Resume, scroll and VoiceOver order,
AX5 cards too wide for half a Book display.

**Tests:** geometry tests for the region calculation (asymmetric safe areas, a translated division, margins, an
inactive region, a width too small for two cards); `CarouselCardSizingTests` stay green; each new test fails with
its logic reverted.

**Claude checks (on the simulator, `~/kudos-tools/duo-pose`):** cover Home/Library with 3+ queues and the last
shelf card; inner portrait Home; inner landscape Home/Library; landscape → Book → landscape without relaunch
(hero/Resume and metadata wholly in one region; lower cards clear of the fold and the rail); iPhone 17 and an
iPad; Light/Dark/Sepia; default and AX5.

## Rules

- iOS only, in this worktree. Do not commit, push, switch branches, build, sign in, contact
  archiveofourown.org, or edit `TASKS.md`. Nothing builds here; Claude builds, gates and shoots.

## Output

`docs/android-port/briefs/Duo8-result.md`, written first and kept current: each change (file:line) and why,
tests and how they fail when reverted, the exact screens and poses for Claude, and anything you'd decide
differently than Duo7 said, with the reason.
