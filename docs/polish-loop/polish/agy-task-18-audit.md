TASK (READ-ONLY SECOND-PASS AUDIT — do not edit, create or delete any file): audit these SwiftUI screens against the
design spec and the app's own patterns. Repo root is the current directory. This is the SECOND pass: earlier audits
already fixed the obvious; look for what remains — spec mismatches in spacing/type/copy, inconsistent patterns between
sibling screens, broken states (empty, error, one item, very long titles), accessibility (labels, 44pt targets, Dynamic
Type that clips or overlaps), and anything that looks unfinished.

Spec: docs/design/Final_Redesign_Spec.dc.html (artboards `<div class="dv-opt" id="…">`; labels in
.claude-overnight/polish/artboards.tsv). Skip anything in .claude-overnight/polish/OWNER-DECISIONS.md or explained by a
code comment naming an owner decision.

Screens (find files with grep): HomeView + HomeResumeHero + HomeSectionListView (1a-ish Home artboards); LibraryView +
LibrarySectionListView + Collections.swift (collection detail/grid) + ReadingQueueBrowser (queue page) + RecentlyDeletedView;
WorkDetailView + WorkDetail*Sections; the "My copy" sheet (grep "My copy").

App patterns to check: SubjectHeaderBlock page heads; SectionRuleHeader groups; "…" menu order (Mature, Select, Reorder,
layout picker, Expand, then page items, then destructive); add = neutral toolbar "+"; delete = trailing destructive swipe
that asks; empty states via ContentUnavailableView; failed loads keep page chrome with "Try Again"; text on SOLID accent
fills uses palette.labelOnAccent / .prominentLabel(); Int.compactCount for counts in chips/headers; FandomDisplayName.bareTitle
for fandom names; `.tint`/screenTint, never Color.accentColor.

Output ONE markdown table, nothing else: | # | Sev (P1/P2/P3) | Screen | file:line | Spec ref (artboard + CSS value, or
"app pattern: …") | Current | Expected | Smallest fix |. Real file:line only; say "unsure" rather than guess. Max 25 rows.
