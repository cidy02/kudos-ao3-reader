# Redesign fidelity audit: method (one area, read-only)

This audit covers one area of the Kudos iOS redesign. For every artboard in your area:
- find the LIVE SwiftUI view,
- compare it to the artboard,
- report the TRUE status and the concrete gaps that remain.

The output drives build work, so precision matters more than breadth of prose.

**STRICTLY READ-ONLY.** Make no edits except your result file. No builds, no git writes. The only
network allowed is otwarchive's source on GitHub (see below). Keep usage lean: use targeted greps,
and read only the view bodies you need.

## Tools
- **Spec:**
  - `python3 Scripts/redesign-spec-outline.py --canvas docs/design/Final_Redesign_Spec.dc.html --board <id>`
    prints one board.
  - Add `--screen N` for a board's later screens; the header line lists them.
  - `--list` lists every board.
  - `--notes` prints every board's prose and build notes. It is large, so grep it for your ids.
- **Commit history:** `git log --oneline -S '<symbol>'` finds the commit that built something.
- **AO3's real behaviour:** read otwarchive's source, the ground truth for markup, params and access
  rules.
  - Fetch `https://raw.githubusercontent.com/otwcode/otwarchive/master/app/views/<controller>/<file>.html.erb`,
    and `app/controllers/`, `app/models/`, `config/routes.rb` the same way.
  - List a directory with `https://api.github.com/repos/otwcode/otwarchive/contents/<dir>`.
  - This repo's HTML fixtures are often hand-written, and a fixture's silence is not evidence.
  - Never contact archiveofourown.org.
- **Codebase map:** `graphify explain "<path>::<Symbol>"`, only if `graphify-out/` exists locally.
  It is gitignored; don't build it for this.

## The plan doc is stale in BOTH directions: prove everything from code
`docs/REDESIGN_PLAN.md` and `TASKS.md` are intent, not status. On 2026-09-24 alone:
- Account 1m/1bt were listed as "left to build", but the owner had flattened the hub
  (`AccountView.tabSections`).
- 1bk was "NOT done" but was built in 633bf7c1.
- 1s was "left" but was built in eeb28def.
- Six Challenges screens were "done" but have 35 gaps.

So for each board:
1. Find the live view through real call sites (`grep -rn "ViewName(" kudos-ao3-reader`).
2. Confirm it is reachable: a navigation route or destination leads to it.
3. Only then compare.

Some code comments record an OWNER decision to depart from an artboard ("per the owner",
"deliberate departure", "owner decision"). Report those as OWNER_DECISION with the file:line, never
as a gap. An implementer's own reasoning in a comment is NOT an owner decision.

Screens are built from these design-system parts (`kudos-ao3-reader/UIComponents/` and
neighbours): SubjectHeaderBlock, subjectPanel(), SubjectFormRow (.value/.control),
SubjectFieldLabel, SubjectFormValue, SectionRuleHeader, SubjectStatStrip, SubjectChip,
SubjectKicker, SubjectSegmentedControl, SubjectRowSeparator, WorkLedgerRow, and the wash/hue
system (ThemeManager).

Known owner decisions:
- **1bh:** excluded.
- **Comments 1f threading** (afe4b85f, T-247): built inline to depth 5, a deliberate departure from
  the artboard's depth 2.
- **1bk Show on Home / Keep downloads, and queue Keep offline:** the effects are open owner
  decisions (stored, unread).
- **Continuous comment streaming:** open owner decision.
- **Account hub 1m/1bt:** flattened by the owner.

## How to compare (per board, per screen)
- **Structure:** section structure and order.
- **Components:** which design-system parts are used vs what the board draws.
- **Copy:** labels and kickers.
- **Data:** what data is shown. If a parse or network capability is missing, the status is
  BLOCKED_CAPABILITY; name exactly what is missing.
- **Interactions:** controls, swipes, menus, sheets, detents, confirmations.
- **States:** the empty, loading and error states the board draws.
- **Colour:** hue and wash.

Ignore exact pixel sizes and theme colours. DO flag:
- missing elements
- wrong ordering
- wrong components
- clearly different typography roles
- wrong or dishonest data: a page-1 count shown as a total, a fetch failure shown as "empty", one
  date shown as another

If a board shows an AO3 WRITE, set `aoWrite: true`. Writes can be built but are never exercised by
agents.

## Self-skeptic pass (before you finish)
- For every board you mark DONE, name the one element most likely to be missing and confirm it
  exists (file:line).
- For every NOT_BUILT / BLOCKED_CAPABILITY, grep for the capability under other names first.
- Effort: an "S" that needs a new SwiftData field, a new parser or a new network request is really
  M, or an owner item.
- When unsure, choose the status that assumes work remains.

## Output: `docs/audits/2026-09-24/<area>.json`
```json
{"area": "...", "boards": [{"id": "1x", "title": "...", "liveViews": ["path:line"],
 "reachable": "how you get there",
 "status": "DONE|GAPS_MINOR|GAPS_MAJOR|NOT_BUILT|BLOCKED_CAPABILITY|OWNER_DECISION|EXCLUDED",
 "planDocAccurate": true, "gaps": [{"element": "...", "current": "...", "where": "path:line",
 "effort": "S|M|L", "needs": "...", "aoWrite": false}], "notes": "..."}], "areaNotes": "..."}
```
Every gap needs a spec quote (in `needs`) AND a file:line (in `where`). Validate the file with
`python3 -m json.tool`.
