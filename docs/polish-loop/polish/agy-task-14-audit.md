TASK (READ-ONLY AUDIT — do not edit, create or delete any file): audit these SwiftUI screens against the design spec
and the app's own shared patterns, and report mismatches. Repo root is the current directory.

Spec: docs/design/Final_Redesign_Spec.dc.html (artboards are `<div class="dv-opt" id="…">`, labels in
.claude-overnight/polish/artboards.tsv). Owner decisions already taken: .claude-overnight/polish/OWNER-DECISIONS.md
(skip anything listed there) and code comments naming an owner decision.

Screens (find the Swift files with grep):
- Reader chrome: ReaderContentsSheet, ReaderSearchView, ReaderNoteEditor, ReaderSpeechSettingsSheet,
  ReaderPronunciationSettingsView, ReaderFanMenu, CustomizeThemeView
- Writing: WritingDraftsView (1x + draft post/delete confirmations), WritingTextEditor / WritingPreviewView (1bv),
  WorkAssociationPickers ("Collections and gifts", "Series picker")
- Library sheets: NewCollectionSheet ("Local collection — new"), AddLibraryWorksSheet
- Account utilities: PrivacyDataView ("Privacy and local data"), AO3LoginView (1n), WelcomeView,
  SyncFolderOnboardingView, AboutView, LegalNoticesView, BugReportView, AvailabilitySweepView

Check each against its artboard where one exists, and ALWAYS against these app patterns:
- page header `SubjectHeaderBlock` + `SectionRuleHeader` groups; forms use `SubjectFormRow` in `.subjectPanel()`;
  List-based forms add `.environment(\.defaultMinListRowHeight, 0)` after `.cardList()`
- sheets: text Cancel + text confirm verb (`.confirmationAction`), grabber/detents where part-height
- failed loads keep page chrome with a "Try Again" button; empty states `ContentUnavailableView`
- text on a SOLID accent fill uses `palette.labelOnAccent` or `.prominentLabel()` (never `accentOnFill`)
- `SubjectFormRow(label:value:…) { … }` with a trailing closure is a BUG (binds to `action:`, swallows navigation)
- Dynamic Type: fonts that must scale use semantic styles or @ScaledMetric; flag hard-coded sizes on body text
- 44pt tap targets (`layoutFreeHitTarget`), except controls deliberately boxed at 28pt (documented)
- counts via `Int.compactCount` in chips/headers; fandom names via `FandomDisplayName.bareTitle`
- accents via `.tint` / `screenTint(palette)`, never `Color.accentColor`

Output: ONE markdown table, nothing else: | # | Sev (P1 broken / P2 visible inconsistency / P3 polish) | Screen |
file:line | Spec ref (artboard id + exact CSS value, or "app pattern: …") | Current | Expected | Smallest fix |.
Cite real file:line. Say "unsure" rather than guess. At most 30 rows, most severe first.
