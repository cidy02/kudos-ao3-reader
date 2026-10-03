
TASK 15: spec-closer UI work, one commit-sized change per item (list files per item). No new AO3 requests, no new
SwiftData fields, no behaviour change beyond what is described. Take sizes from the named artboards' inline styles and
colours from theme tokens (never the artboards' literal dark rgba). Keep default Dynamic Type sizes matching the spec and
make new text scale (@ScaledMetric), without hard-capping at AX sizes.

1. 1al fandom list A–Z index (Features/Search/FandomListView.swift): when the list is in A–Z order, show a vertical
   letter index pinned to the trailing edge (spec: `right:2px; width:16px; font:500 8.5px/1.5 ui-monospace`, secondary
   colour) that jumps to the letter's section (ScrollViewReader + the existing section ids). Letters with no section are
   dimmed and inert. 44pt-tall hit regions are not possible per letter; instead a drag across the index scrubs
   (DragGesture mapping y → letter), plus VoiceOver adjustable action. Hidden in Most-works order and when searching.
2. 1al fandom rows (FandomListRow / FandomFamilyRows): show the favourite star and the local downloaded-works count
   that `FandomLibraryIndex` already builds (spec: star #F2C879 when favourite else hidden; download glyph + count
   `font:500 11.5px ui-monospace`, mint). Pass the index entry into the row; no new computation.
3. 1bv chapter editor toolbar (Features/Writing/WritingTextEditor.swift ~252–267): replace the plain ScrollView of
   bordered buttons with 1bv's bar — material background with a top hairline, padding 11×14, pill buttons radius 9 with
   `glassFill(0.09)` backgrounds, same actions and accessibility labels.
4. 1ac promise panel (Features/Account/PrivacyDataView.swift ~199–220): the "No ads, no analytics…" panel takes 1ac's
   mint treatment — a subtle mint gradient fill and mint-tinted 0.5pt border — using the Mint swatch hue
   (SubjectHueSwatches "Mint") through `subjectPalette(hue:)` so it adapts to every theme.
5. Availability sweep (Features/Account/AvailabilitySweepView.swift): it is a `Form` whose sections also carry `.cardRow()`
   (a List modifier), so cards double-inset. Make it consistent with the app's List pages: `List` + `.cardList()` +
   `.environment(\.defaultMinListRowHeight, 0)`, SubjectHeaderBlock-free (it is a sheet with its own nav title), rows via
   `.cardRow()`; keep every control and the Stop/Done toolbar exactly as they are.
6. Fandom family block (Features/Search/FandomFamilyRows.swift): the family card draws a second, lighter rounded panel
   inside its card (box in a box) around the head and members. Remove the inner panel so the family reads as one card;
   keep the rail, spacing and the zoom-source modifier.

Do not touch SubjectForm.swift, SubjectSurface.swift or AccountComponents.swift (changed today). Claude builds, screenshots
(default size and AX5) and commits.
