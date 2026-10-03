
TASK 13: implement these verified audit rows (your task-12 table; numbers refer to it). Spec-closer only: no new
parsing, no new requests, no behaviour change. Take sizes from the artboards; colours from theme tokens.
List changed files per item.

Comments (Features/Comments):
- #3 Composer "Post" (CommentsView ~1299, 1ba): a filled 30pt capsule, padding 0×14, 600 13.5pt, label
  `palette.labelOnAccent` on `palette.accent` (NOT accentOnFill). Keep it a toolbar confirmation item and keep
  its disabled state visibly dimmed.
- #4 Format bar (CommentMarkup ~268, 1ba/1be): six plain 34×34 rounded-square (radius 9) controls, transparent,
  bar height 52 / padding 0×12 / gap 2; B, I, U, S drawn as literal serif glyphs (Georgia-like: `.system(size: 16,
  design: .serif)` with bold / italic / underline / strikethrough). One small shared private button face.
  Each keeps its accessibility label; 44pt tap via `layoutFreeHitTarget`.
- #5 Parent quote (CommentsView ~1414): fill `glassFill(0.06)`; the whole byline (author + chapter) in
  `palette.accent`, both branches.
- #6 Formatting tray (CommentMarkup ~387, 1bf): group label 700 8.5pt tracking .1em; tile name 500 10.5pt;
  tag 400 9.5pt monospaced; U and S example glyphs `.underline()` / `.strikethrough()`.
- #7 Thread screen (CommentThreadScreen ~37, 1f): first row a `SubjectHeaderBlock` (kicker = work title,
  title = "Thread", subtitle = the chapter/author context it already has) and `.subjectScreenWash(palette:)`
  with the comments palette; macOS-only navigationTitle as elsewhere.

Failure shells (T-320 pattern — failed loads keep their page chrome):
- #9 FandomListView ~96 and #24 AuthorProfileView ~61/695: render the failure INSIDE the normal List/wash
  with the page's SubjectHeaderBlock, the retry card as a `.cardRow()`, button "Try Again",
  `UserFacingError.message(for:)` / `.systemImage(for:)`. Copy the pattern from AO3SeriesDetailView.

Fandom list (Features/Search):
- #12 FandomFamilyRows ~57: the aggregate work count shows only in "Most works" order (pass the sort in).
- #13 FandomFamilyRows ~23: member list gets 14pt leading padding inside the rail (rail stays at 21).

Save Search (Features/Search/SaveSearchSheet ~61, 1ax): #16 wrap the chip flow in `.subjectPanel()`
(padding 13×14), included chips green / excluded chips red (system .green/.red at 15% fill, 35% stroke,
400 12pt, padding 4×9, capsule) and facet chips neutral; drop the header count; add the footer
"Only settings you changed are saved." (400 11.5pt, secondary). Excluded chips lose the dashed border.

Author:
- #22 AuthorProfileView ~301 (1y): Dashboard subtitle appends the parsed pseud count ("2 pseuds") when
  `header.pseuds` has more than one; nothing else (no joined date / invitations — no data).
- #25 AuthorProfileContentSections ~473 (1az): the empty own-Series state is ONE `.subjectPanel(cornerRadius: 18)`
  card: message, a hairline divider, then the existing "New series on AO3" action — merge the two blocks.

Also verify and fix if real: the standard (Detailed) work card shows "0" for stats AO3 did not print (words,
comments, kudos, bookmarks, hits — seen on an anonymous work's card on the author Dashboard in Detailed mode).
Commit 3d739dc7 (L3-B5-20) fixed the same class elsewhere; reuse its mechanism.

Do not touch SubjectForm.swift, AO3AccountWorksList.swift, AuthorDashboardSections.swift (Claude changed them).
