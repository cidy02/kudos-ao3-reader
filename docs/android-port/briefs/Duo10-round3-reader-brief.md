# Duo10 — iPhone Duo round 3: a readable page and a real fold-aligned spread

**Agent:** Codex. **Worktree:** `~/kudos-agent-ios2`, branch `claude/agent-ios-duo10` (from the iOS lane's tip with
T-451 landed; Claude names the SHA in the dispatch). iOS only. Duo9 (round 2 navigation) runs at the same time in
`~/kudos-agent-ios`: don't touch Library, Account, Settings or `UIComponents/LocalNavigationHost.swift`.

## Decided (Claude-CLI, owner-delegated; `docs/android-port/DECISIONS.md` 2026-10-24)

Your Duo7 plan (`docs/android-port/briefs/Duo7-plan.md`) is the direction; this brief is its **Round 3** plus the
Reader section ("What pinned Readium permits…"): read both first. Model: Apple Books. Decisions that bind it:
- **One navigator, one locator, one speech session.** The pinned Readium 3.9.0 (`de07026e`) stays; no upgrade, fork,
  second navigator, middle mask or bare `colGap = 40`. Prefer the existing style/script seam and RS properties; the
  smallest app-owned CSS correction only where bundled media queries defeat the chosen layout.
- **Spread:** paged mode with the existing Two-page spread setting on shows two consecutive readable pages in inner
  landscape and Book pose when two measures fit at the user's font. In Book pose the gutter contains the fold (the
  active `.division` region plus clearance), centred on the **physical** fold, not the rail-shifted safe midpoint.
  Don't change `readerTwoPage`'s stored value or default.
- **Single page and Scroll:** a bounded readable measure (target 55–75 characters per line of Latin prose, from the
  font's real metrics and the user's margins), centred. In Book pose, Scroll, spread-off and large-font fallbacks sit
  wholly in the **leading** pane; never a line across the fold. Never smaller type to make a spread fit.
- **Chrome:** close/title in the leading pane; fan menu and the whole position/TTS card in the trailing pane (one
  safe pane's width at accessibility sizes, never a slider or play control across the fold); selection/colour
  controls in the selected text's pane; no hit target in a reserved region.
- **Position:** T-450 and T-451's lifecycle is the baseline (Readium owns position through a resize; one settled
  paged restore, cancelled by navigation or touch). Consume it; don't add another hold or restore. A
  reserved-region-only change (Open ↔ Partially Open at unchanged size) is a layout change like a resize. Keep the
  turn-based slider metric (scroll width ÷ viewport width); no new leaf-page numbering.
- Fixed-layout EPUBs: a whole page fits one pane in Book pose; a pair only when each complete page fits its side;
  no reflow CSS injected into fixed layouts.

## Measure first

Nothing runs here, so add a DEBUG-only diagnostic (`Log.epub.debug`, no release behaviour) that records, on each
resource load and geometry or region change: the computed column count and width, column gap, which ReadiumCSS
media query applied, the viewport and safe rects, the fold rect in navigator coordinates and the first/last text
rect per visible column. Claude runs it on the Duo and the iPad and returns the numbers. Ship the implementation
with it; Claude will send you the measurements to correct against.

## Tests

Keep `ReadiumReaderTests`, `ReadiumLocatorPreservationTests`, `ReadiumResizeNavigationTests`,
`ReadiumProgressPersistenceTests`, `ReadiumProgressParityTests` and the page-box/metrics/scrub suites green. Add a
geometry + CSS contract test (columns, gutter centred on an asymmetric fold, measure bounds, single-pane fallback,
region-only invalidation); each new test fails with its logic reverted.

## Before landing

This touches reading position: a fresh adversarial review runs on your patch before it lands (Living Prompt §9).
List in your result exactly what a reviewer must try to break (skips or repeats after a turn, a chapter ending on
the leading page, stale CSS on the next resource, the restore after a pose change, TTS focus).

## Rules

- iOS only, in this worktree. Do not commit, push, switch branches, build, sign in, contact
  archiveofourown.org, or edit `TASKS.md`. Nothing builds here; Claude builds, gates and shoots every pose
  (`~/kudos-tools/duo-pose`), with the local EPUB fixtures.

## Output

`docs/android-port/briefs/Duo10-result.md`, written first and kept current: each change (file:line) and why, tests
and how they fail when reverted, the exact screens, poses and settings for Claude, the reviewer's break list,
anything you'd decide differently from Duo7, and any whole-app feature idea (for `FEATURE-IDEAS.md`), listed apart.
