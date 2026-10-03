TASK (READ-ONLY AUDIT — do not edit any file): audit these screens' code against the spec and report mismatches.
Screens (Swift file → artboard ids in docs/design/Final_Redesign_Spec.dc.html, `<div class="dv-opt" id="…">`;
labels in .claude-overnight/polish/artboards.tsv; find the files with grep):
- NewReadingQueueSheet → 1j ; ReadingQueueSwitcher → 1h ; AddToQueue / add-to-collection sheets (no artboard: check
  against 1j and the app's own sheet chrome)
- CommentComposerSheet, CommentMarkup → 1ba, 1be, 1bf ; CommentThreadScreen → 1f
- FandomListView, FandomListFilterSheet, FandomFamilyRows → 1al, 1am, 1an ; SaveSearchSheet → 1ax
- AO3HistoryWorksBrowser → 1t ; AuthorProfileView + AuthorProfile*Sections + WorksScopeAndSort → 1u, 1v, 1w, 1y ;
  AO3SeriesDetailView → 1az
Report ONE markdown table: | # | Sev (P1 broken / P2 visible inconsistency / P3 polish) | Screen | file:line | Spec
ref (artboard id + exact CSS value) | Current | Expected | Smallest fix |. Cite real file:line and real spec values;
say "unsure" rather than guess. Skip anything the app deliberately departs from with a code comment naming an owner
decision (and OWNER-DECISIONS.md items 1–9 in .claude-overnight/polish/). Also check the app's own shared patterns:
SubjectHeaderBlock headers, SectionRuleHeader groups, SubjectFormRow panels, "Try Again" failure cards,
.prominentLabel() or Palette.labelOnAccent on SOLID accent fills (accentOnFill is only for the 24%-alpha fill),
FandomDisplayName.bareTitle, Int.compactCount, 44pt hit targets without taller rows, and — new bug class — any
`SubjectFormRow(label:value:…) { … }` trailing closure (it binds to `action:` and swallows row navigation).
