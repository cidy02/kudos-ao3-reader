READ-ONLY AUDIT. Do not edit, create, or delete any file. Do not run git commands that change state. Never contact archiveofourown.org or any network service.

You are auditing the Kudos iOS app (SwiftUI; iPhone only) against its redesign spec, `docs/design/Final_Redesign_Spec.dc.html`. Each artboard is `<div class="dv-opt" id="<ID>">`; read its label text and the inline-styled HTML mockups inside it (styles are exact: spacing, font sizes, radii, colours). Owner decisions recorded in code comments ("owner, 2026-…") and in TASKS.md override the spec.

SCOPE (screens → artboards): {{SCOPE}}

For every screen in scope check:
1. Spec match: layout, spacing (measure from the HTML), type sizes/weights, radii, colours, copy, order of elements.
2. One design language across the app: page header = SubjectHeaderBlock; group header = SectionRuleHeader; "…" menu order = Mature, Select, Reorder, layout picker, Expand, then page items, then destructive; add = neutral toolbar "+"; delete = trailing swipe, destructive role, asks first; container removal = "Remove", asks; reorder = a mode ended by "Done"; empty = ContentUnavailableView; loading = skeleton; sheets = Cancel + verb, grabber, detent; counts via Int.compactCount on chips/strips/headers; fandom names via FandomDisplayName.bareTitle; accented controls use the screen's tint (screenTint / .tint), never Color.accentColor.
3. Actions: can the user add/delete/reorder/select where they would expect to, in the standard place? Anything important only in a long-press?
4. States: empty, loading, error + Try Again, signed-out, mature-hidden, filtered-to-nothing, one item, many items, long titles.
5. Accessibility: Dynamic Type to AX5 (clipping/overlap), VoiceOver labels/values, 44pt hit targets (without inflating layout).
6. Bugs: wrong/stale/duplicated/misaligned behaviour, state that can get stuck.

Verify every claim against the actual code (cite file:line) and the artboard (cite id and the exact style value). If you are not sure, say "unsure" instead of guessing. Do not report things that match.

OUTPUT: only a Markdown table:
| # | Sev (P1 bug/broken, P2 visible inconsistency, P3 polish) | Screen | file:line | Spec ref (id + value) | Current | Expected | Smallest fix |
Then at most 5 lines of "owner decision candidates" (things that depart from the spec on purpose or need a product call).
