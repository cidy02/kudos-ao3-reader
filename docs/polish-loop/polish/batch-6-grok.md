# Batch 6 — Work detail and Comments polish audit (Grok)

Repo: `integrate/cloud-redesign`. Read-only. Spec: `docs/design/Final_Redesign_Spec.dc.html` (inline styles, px = pt). Checklist A–G from `.claude-overnight/polish/PLAN.md`. Line numbers from this worktree. No build, no simulator, no AO3 traffic — nothing here was seen on a device. Where `docs/REDESIGN_DECISIONS.md` or `docs/REDESIGN_PLAN.md` already supersedes an artboard, that is under the screen’s checked list, not filed as a defect to revert.

Artboard → code map:

| Artboard | Screen | Primary files |
|---|---|---|
| 1a | Work detail, page and My copy sheet | `WorkDetailView.swift`, `WorkDetailIdentityBlock.swift`, `WorkDetailOverviewSections.swift`, `WorkDetailSections.swift`, `WorkDetailFactsSections.swift`, `WorkDetailAO3Actions.swift`, `AO3WorkActionsMenu.swift` |
| 1f | Comments list | `CommentsView.swift`, `CommentThreadRow.swift`, `CommentThreadScreen.swift` |
| 1ba | Composer, medium detent | `CommentsView.swift` (`CommentComposerSheet`) |
| 1be | Same sheet, keyboard up | The same sheet: bottom `safeAreaInset` + `[.medium, .large]` |
| 1bf | Formatting tray | `CommentMarkup.swift` (`CommentFormattingTray`, `CommentFormatBar`) |

---

## Findings

### batch-6-1 — P2 — 1a — `WorkDetailView.swift:297` / `:402` / `WorkDetailAO3Actions.swift:8`

**Artboard:** locked turn title **“Work detail — AO3 actions on the page, the local half behind a sheet.”** Caption: **“The AO3 account actions get their own lane under the summary — Kudos filled, since it is the one the app is named after. Everything local (download, preservation, activity, my tags, queue positions) moves behind one button at the bottom into a sheet built from the same parts as the page.”** The overflow menu (width 242, radius 14, rows `400 14.5px/1.2`, icon trailing) is **Add to Queue**, **Add to Collection**, **Share**, **Open on AO3**. Toolbar, left to right after the 34pt glass back: a filled star in accent glass (`rgba(201,166,255,.3)`, border `.5px rgba(201,166,255,.5)`, star `#e6d6ff`), a 34pt glass clock, a 34pt glass ellipsis.

**Code:** `pageSections` still inserts `quickActionsSection` (`WorkDetailOverviewSections.swift:111`) between the tags and the facts card. The grid is headed **Quick Actions** and offers **Open on AO3**, **Download** / **Downloaded**, **Save for Later** / **Remove from Later**, **Add to Queue** / **In N Queues**, **Add to Collection** / **In N Collections**, **Mark as Finished**, and **Comments**. Those are the local actions the caption puts behind My copy, plus a second **Open on AO3** and a second way into comments. The toolbar menu’s only content is `AO3WorkActionsMenu` (`AO3WorkActionsMenu.swift:22`): **Give Kudos**, **Comments**, **Bookmark on AO3** / **Edit Bookmark on AO3**, **Mark for Later**, **Subscribe** / **Unsubscribe**, **Open on AO3**. No **Share**. No clock. The star is `ToolbarIconButton` with `tint: .yellow` when favorited (`WorkDetailView.swift:392`), a system toolbar label, not the accent glass circle. `WorkDetailAO3Actions.swift:8` says the spec overflow “is part of the floating-chrome swap that is staged until someone has a device. Until then this page offers both.”

**Smallest fix:** Drop `quickActionsSection` from `pageSections`. Point the ellipsis at **Add to Queue**, **Add to Collection**, **Share**, **Open on AO3**, and leave Give Kudos / Subscribe / Bookmark / Mark for Later on the ON AO3 chips (the menu can keep them in the reader, where there is no chip row). Tint the favorite control with the subject accent. Leave the clock off until it has a destination — last opened is already the Activity row inside the sheet.

---

### batch-6-2 — P2 — 1a — `WorkDetailView.swift:362` / `WorkDetailSections.swift:188`

**Artboard, second device:** sheet titled **My copy** (`600 19px`, tracking `-.01em`) with subtitle **Private to this device** (`400 12px`, `.45`) and a 28pt circle X. Stat strip: **38% / PROGRESS**, **1.2 MB / ON DEVICE**, **Kept** in `#7ddc9a` / **PRESERVED**. Groups **STATUS**, **QUEUES**, **COLLECTIONS**, **STORAGE**, **ACTIVITY**, **MY TAGS**. Queue rows are the name with a trailing **#3 of 12**. **Add to queue** and **Add to collection** are their own rows, `500 14px` `#c9a6ff` plus a 14px plus. Tags are a tinted chip (**reread**) with an ×, a field **Add a tag**, an **Add** button, and suggestion chips. Activity dates are **11 Mar 2024, 9:14 PM** and **Last opened**.

**Code:** the sheet is a `NavigationStack` `List` titled **My copy**, closed with **Done**, wash height 220, no subtitle, no progress / size / preserved strip. `librarySections` is the pre-redesign library tab: section headers **Status**, **Storage**, **Activity**, **My Tags**. Queues are one **In N Queues** / **Add to Queue** label plus footnotes `"\(queue.name) — #\(index + 1) of \(orderedWorks.count)"` (`WorkDetailSections.swift:348`). Collections are one label plus a comma-joined footnote. Tags are text rows with a red `minus.circle.fill` at a 28pt hit target (`:505`). The file comment at `WorkDetailView.swift:358` says the content was left unchanged on purpose. `REDESIGN_PLAN.md` (2026-09-14) describes this sheet as already carrying the progress strip; the view does not.

**Smallest fix:** Restyle this sheet to the second device — 19pt title, **Private to this device**, the three-cell strip from facts the app already has (`readingProgress`, file size, preservation), one row per queue with the position as the trailing value, accent **Add to queue** / **Add to collection** rows, and the tinted tag chips. Keep the actions that already exist (retry preservation, rebuild converter, provenance). Do not invent an AO3-collection row; `AO3WorkSummary` has no collection field, and the board’s **Cyberpunk Big Bang 2077 / Collection** row is a local collection.

---

### batch-6-3 — P2 — 1a — `WorkDetailFactsSections.swift:154` / `SubjectSurface.swift:784`

**Artboard:** the tally strip’s comments cell is the only one that looks tappable. Value **47** is `600 13px` `#d9c1ff` with a 9px chevron in the same colour. The label **COMMENTS** is `400 9px` tracking `.07em` `#c9a6ff`. Kudos, bookmarks, and hits have neither the tint nor the glyph.

**Code:** the comments cell sets `isHighlighted: true` and an `action`. `SubjectStatStrip.cellBody` tints only the value (`palette.accentOnFill`) and draws no chevron. The label is `.secondary` for every cell, including this one. The comment at `WorkDetailFactsSections.swift:130` says the artboard draws the cell “in the subject accent with a glyph beside it.” The glyph is not there. VoiceOver does get “Comments, 47, opens the discussion,” so the control exists and only the sighted cue is missing.

**Smallest fix:** When a cell has an `action`, colour the label with the subject accent and append a 9pt chevron to the value. Leave kudos, bookmarks, and hits alone.

---

### batch-6-4 — P2 — 1f — `CommentsView.swift:102` / `:428` / `CommentThreadRow.swift:40`

**Artboard:** header `padding:22px 22px 0`, gap 9. Title **Echoes of Time** is `700 30px/1.08` tracking `-.02em`. Byline **saltandsilver** is `400 14.5px/1.3` at `.72`. The section rule and the thread sit at `padding:0 22px`.

**Code:** `CommentsView` passes `gutter` = `SubjectMetrics.accountGutter` (16, `SubjectSurface.swift:328`) into `SubjectHeaderBlock`, and `CommentThreadGeometry.sideMargin` is 16. `SubjectHeaderBlock` draws the title at 32pt bold (`SubjectSurface.swift:467`) and the byline is called at 15.5pt (`CommentsView.swift:440`). The doc comment at `:417` says “the work at 32pt” as if that were 1f. 1a’s own header is supposed to be 32 / 15.5 / gutter 26, and it is — comments borrowed the work-detail header.

The frame’s kicker is `#E39B9B` and the rule under it is 22×2.5 `#A3B2EC`. The frame disagrees with itself. The shared kicker (10pt bold, tracking `0.11em`, rule 26×2.5 in `palette.accent`) is the right one. Do not retint the rule to match the rose kicker.

**Smallest fix:** On this screen only, a 30pt title, a 14.5pt byline, and a 22pt side inset (`SubjectMetrics.panelGutter` is already 22). Leave `SubjectHeaderBlock`’s defaults for every other subject page.

---

### batch-6-5 — P2 — 1f — `CommentThreadRow.swift:1360`

**Artboard:** the ellipsis on every row is a bare 15px mark at `rgba(255,255,255,.5)`, in a 40×40 hit area, no capsule. Caption: **“…” sits right on every row.**

**Code:** `CommentOverflowButtonLabel` draws `ellipsis` at caption bold, `.primary`, inside a `.quaternary` capsule, then a 44×44 frame. The same label is shared with Inbox.

**Smallest fix:** Drop the capsule fill and the bold caption weight; keep a 44pt hit target with `minimumHitTarget()` so the control stays legal without looking like a chip. If Inbox should keep the capsule, pass a style rather than changing both.

---

### batch-6-6 — P2 — 1ba / 1be — `CommentsView.swift:1289` / `CommentMarkup.swift:261`

**Artboard 1ba:** header is Cancel (`400 15px` `.7`), centred **Reply to corvidiary** (`600 14.5px`), and **Post** as a 30pt capsule (`padding:0 14px`, radius 99, fill `#A3B2EC`, `600 13.5px` `#16192e`). The format bar is `height:52px`, `padding:0 12px`, `gap:2px`, top hairline `.5px`. Each control is a 34×34 square, `border-radius:9px`, `background:transparent`: Georgia **B** (`700 16px`), italic Georgia **I**, **U**, **S**, then two 18px symbols, then an ellipsis. 1be says the same bar stays pinned to the sheet’s bottom edge, above the keys. 1bf’s build note: the compact bar is those six, then the tray.

**Code:** Cancel and Post are system `ToolbarItem`s. Post is semibold text, disabled until the field is non-empty, the budget is ≥ 0, and the reader is signed in (`:1290`). `CommentFormatBar` puts every control, including the ellipsis, in a `GlassCircleButton` (`SubjectSurface.swift:996`: 34pt circle, glass fill, 17pt medium SF Symbol). `quickBar` is `[.bold, .italic, .underline, .strike, .link, .quote]` (`CommentMarkup.swift:77`), which is the right six, in the right order. The tray already draws the serif B/I/U/S (`CommentFormatTileFace`, `:489`). Bar height 52, horizontal padding 12, spacing 2, and the top hairline match. The bar is a bottom `safeAreaInset` (`CommentsView.swift:1266`), which is what 1be asks for.

**Smallest fix:** Draw Post as the 30pt accent capsule (`palette.solidButtonLabel` on `palette.accent`), and keep the disabled rules. Draw the six bar buttons with the tray’s letterforms and symbols inside a 34×34, radius-9, clear button. The hit target can stay 44.

---

### batch-6-7 — P3 — 1a — `WorkCardActions.swift:224` / `WorkDetailFactsSections.swift:193`

**Artboard:** the outline pair is **Mark finished** and **Open on AO3**, each `flex:1`, `padding:13px 0`, radius 12, `border:1px solid rgba(255,255,255,.18)`, `500 15px`.

**Code:** chrome matches (`WorkDetailOutlineButton`, radius 12, 15pt medium, vertical padding 13, stroke 0.18). The title is `WorkActionLabels.finished`: **Mark as Finished** / **Mark as Still Reading**. That pair is shared with card menus and the bulk bar. The button has no `minimumHitTarget`, so the drawn height is 15 + 26 = 41pt.

**Smallest fix:** On this page only, use **Mark finished** / **Still reading**, and add `minimumHitTarget()` without growing the visible stroke.

---

### batch-6-8 — P3 — 1a — `WorkDetailIdentityBlock.swift:194` / `:203` / `SubjectSurface.swift:860`

**Artboard:** resume card radius 20, padding 16×18, gap 15 (these match). Ring prints **38%** at `600 12px` tabular. Primary line **Chapter 3** is `600 16.5px` (matches). Subtitle is `400 12.5px` `.6`: **Rain on the Wire · 9 pages left**. Play circle is 42pt white, icon 17pt.

**Code:** `WorkProgressRing` at diameter 48 sizes the percent as `diameter * 15 / 68` ≈ 10.6pt, not 12. Primary line is the Readium locator title, or **Reading**, or the action title (`readAction`). Secondary line is `lastReadDate` formatted `.relative(presentation: .named)` — a date, not the chapter title. The play glyph is 16pt semibold. **9 pages left** is absent on purpose (`REDESIGN_PLAN.md`, 2026-09-14): the figure is not persisted, and opening the book to print it is the wrong request. A 0% ring is also correctly withheld until `hasStartedReading` (`WorkDetailView.swift:277`).

**Smallest fix:** Pass `diameter: 48` a 12pt percent (or a size argument on `WorkProgressRing`) and draw the play glyph at 17. Keep the date. Do not add “pages left” until the reader stores the number.

---

### batch-6-9 — P3 — 1a — `WorkDetailAO3Actions.swift:42` / `WorkDetailSections.swift:94` / `SubjectSurface.swift:925`

**Artboard:** ON AO3 chips are `padding:8px 12px`, radius 8, gap 7, icon 15, `500 13.5px`. Tag chips are `padding:6px 11px`, radius 8, `500 13.5px` (relationship tinted) or `400 13.5px` (characters, tags).

**Code:** both rows are `SubjectChip` at 13pt, medium only for `.tinted`, otherwise regular, padding 6×11 (rect) or 7×14 (pill), icon 11pt. Chip hit target is `minimumHitTarget(30)`. The modifier’s own comment allows a floor under 44 when 44 would overlap neighbours; these chips are that case. The relationship cluster is the tinted one, which matches. The trailing tag count is `SubjectFieldLabel`’s count, printed only when `tags.count > 4` (the board prints **7**).

**Smallest fix:** A chip size for this page: 13.5pt medium on the ON AO3 row (padding 8×12, 15pt icon) and 13.5pt on tag chips. Leave the 30pt floor.

---

### batch-6-10 — P3 — 1f — `CommentsView.swift:506` / `:568` / `:823` / `CommentThreadRow.swift:1097` / `:1297`

**Artboard:** signal strip radius 12, fill `.07`, values `600 12.5px` tabular, labels `400 9px` tracking `.07em` at `.68`. Chapter pill is 34pt tall, solid accent, `600 13px` `#16192e`, text **Chapter 4**, chevron 11, no book icon. Sort pill is **Newest** at `500 13px` with a 14px icon. **REPLYING TO YOU** is `400 9px` tracking `.07em` in the page accent, regular weight. **Reply** is `500 12.5px` in the page accent. **Write a comment** is a comment-bubble icon (17px) and `600 14px` on the accent, with a shadow.

**Code:** the strip is the shared `SubjectStatStrip`: 13pt semibold values, 9pt labels tracking 0.63, `.secondary` labels, `subjectPanel()` radius 14. The chapter pill is `SubjectChip` `.pill` with `systemImage: "book"` and `chevron.down`; chip text is 13pt regular unless the style is `.tinted`. **Yours** highlights the value only when `mine > 0`, which matches the board’s structure (value accent, label not). **REPLYING TO YOU** is `.caption2.weight(.semibold)`, tracking 0.7, `theme.effectiveTint` (`CommentThreadRow.swift:1097`) — the comment there refuses a fixed 9pt so it scales. **Reply** is `.caption.weight(.medium)` in `.tint`, min height 44. The write pill is 14pt semibold on `palette.accent` with `palette.solidButtonLabel` (the dark-on-accent pair matches), height 44, but the icon is `pencil` (or a person glyph when signed out) and the shadow is `.clear` on dark themes (`:846`).

**Smallest fix:** A comments-specific strip (12.5pt values, radius 12, label opacity 0.68) only if the shared strip’s 13 / 14 is not an owner call the way the work-detail strip is. Drop the book icon. Draw **REPLYING TO YOU** in the page accent at regular weight (keep it scaled). Use `.tint` of `palette.accent` for Reply. Swap the pencil for a bubble. Keep the dark-theme shadow off if that is the app’s card rule; the board does draw one.

---

### batch-6-11 — P3 — 1ba — `CommentsView.swift:1403` / `:1432`

**Artboard:** the quote is `margin:0 16px`, `padding:10px 12px`, radius 11, fill `rgba(235,235,245,.06)`, left rail 2px `#A3B2EC`. The whole kicker **corvidiary · Chapter 4** is `600 11px` in that accent. Body is `400 12.5px/1.45` at `.6`, class `clamp2`.

**Code:** padding 10×12, radius 11, and a 2pt `palette.accent` rail match. Fill is `glassFill(0.09)`, not 0.06. `lineLimit(3)`. When the author has a profile route, only the name is accent and the **· Chapter** suffix is `.secondary` (`:1450`). With no route, the whole string is `.secondary`.

**Smallest fix:** Paint the whole “author · chapter” string in `palette.accent` (the name can stay the button), clamp the body at 2 lines, and use fill 0.06.

---

### batch-6-12 — P3 — 1bf — `CommentMarkup.swift:392` / `:464` / `:493`

**Artboard:** group labels **Text** and **Blocks & links** are `700 8.5px` tracking `.1em` at `.4`. Tiles are height 58, radius 11, fill `.09`, gap 7 (these match: `CommentFormattingLayout`). Name is `500 10.5px`. Tag is `400 9.5px` mono at `.74`. **U** and **S** are drawn as underlined and struck-through letterforms. Header **Formatting** `600 14px` and **Done** `600 13px` in a capsule at `rgba(235,235,245,.16)`, horizontal padding 13, match (`:364`).

**Code:** group titles are `SubjectFieldLabel` `.field` — 10pt semibold, tracking 1.0, not 8.5pt bold. Tile name and tag are both `.caption2` (about 11pt). **U** and **S** are plain 16pt serif.

**Smallest fix:** An 8.5pt bold label for these two groups, tile name at 10.5 medium, tag at 9.5 mono, and underline / strikethrough on the U and S glyphs. The four-column grid, the tag list, and the absent Image tile already match (see checked).

---

### batch-6-13 — P3 — 1f — `CommentThreadRow.swift:1323` / `:1748`

**Artboard:** the ellipsis menu is not drawn, so there is no specified order. Destructive-last is the app rule.

**Code:** the menu is **Reply** (or **Log in to Reply**), **Edit Comment**, **Copy Link**, **Thread**, **Parent Thread**, **Delete Comment**. The trailing swipe (`allowsFullSwipe: false`) is **Copy Link**, **Edit**, **Delete**. The same action is **Edit Comment** in the menu and **Edit** on the swipe.

**Smallest fix:** Label the swipe **Edit Comment**.

---

### batch-6-14 — P3 — 1a — `WorkDetailView.swift:315` / `:691`

**Artboard:** no error state is drawn.

**Checklist E:** an error has a retry, and nothing is blank.

**Code:** a failed refresh sets `loadError` to **“Refresh failed; existing details were left unchanged. ”** plus `WorkMetadataRefresh.message(for:)`, drawn as red footnote text (`:328`). `.refreshable` calls `refreshDetails()` (`:144`), and the footnote does not say so and has no **Try Again**. Comments, on the same batch, uses `ContentUnavailableView` **Couldn't Load Comments** with **Try Again** (`CommentsView.swift:658`).

**Smallest fix:** Add a **Try Again** button next to that footnote that calls `refreshDetails()`. Keep the existing-details sentence.

---

### batch-6-15 — P3 — 1a — `WorkDetailIdentityBlock.swift:41`

**Artboard:** the kicker is the bare fandom **Cyberpunk 2077**.

**Checklist D:** fandom names without the disambiguator, via `FandomDisplayName`, where the board shows a bare name.

**Code:** `displayFandoms` (`WorkDetailView.swift:479`) is the stored tag list, passed straight into the kicker. Nothing in `Features/WorkDetail/` calls `FandomDisplayName`. A tag stored as `Cyberpunk 2077 (Video Game)` would print the parenthetical in the kicker and in the Fandoms chips. The chips should stay the full tag, because a tap searches that tag (`WorkDetailSections.swift:93`).

**Smallest fix:** Run the kicker through `FandomDisplayName.split(_:).title`. Leave the chips as the AO3 string.

---

## Checked, matches

### 1a — page

- Wash height 620 and the work hue (`WorkDetailView.swift:143`). Pull to refresh calls `refreshDetails()`.
- Header: kicker 10pt bold, tracking `size * 0.11`, uppercase, subject accent; rule 26×2.5; title 32pt bold, tracking −0.6; byline 15.5pt; stack spacing 9. That is 1a’s header, not 1f’s. Horizontal gutter 26. The list row’s top inset is 20 (`:237`) against the board’s `padding:22px 26px 0` — measured, 2pt, not filed.
- Figure strip: rating, warnings, category, completion; only rating and warnings take a colour (`WorkDetailIdentityBlock.swift:71`); values 13pt semibold, labels 9pt tracking 0.63; cell padding 10×6, gap 5; `subjectPanel()` radius 14, fill 0.09 (`SubjectForm.swift:47`). Completion label is **Complete**, value is the chapter fraction. Category extras print `+N`. Top inset 16 and panel gutter 22 match `padding:16px 22px 0`.
- Resume card radius 20, padding 16×18, gap 15, fill 0.10, hairline 0.14, circle 42pt in `solidButtonFill` (white on dark). Download glyph when there is no EPUB. No 0% ring on an unopened work. **9 pages left** omitted on purpose (2026-09-14). The ring’s type size is batch-6-8.
- Summary: 16pt serif, `lineSpacing(5.5)` for the 1.6 line height, opacity 0.82, top inset 20. **Show More** / **Show Less** after the collapse threshold, and it checks Reduce Motion. The board’s sample is one sentence; the control is the right extra.
- ON AO3 label is `SubjectFieldLabel` **On AO3** (10pt semibold, tracking 0.1em). Chips: **Kudos ·** the exact formatted count, **Subscribe** / **Subscribed**, **Bookmark** / **Edit Bookmark**, **Mark for Later**. Kudos count stays `isDone: false` — decision **B6** (only reader states tint). Chip metrics are batch-6-9. The row is hidden unless signed in and the work has an AO3 id; the toolbar still carries the writes. Subscription and bookmark state are fetched when the menu opens, not on appear (`AO3WorkActionsMenu.swift:64`), which is the networking rule.
- Tag clusters: Archive Warnings, Fandoms, Relationships (tinted), Characters, Additional Tags. Count only past four tags. Empty copy distinguishes a refreshable work from an imported EPUB. Extra groups beyond the three the board drew are the density choice recorded in the file comment (`WorkDetailSections.swift:75`). Warnings appearing in both the strip and the chips is the same choice.
- Facts card: `subjectPanel(cornerRadius: 16, isFilled: false)`, top inset 24, panel gutter 22. Series value is **Part N** or **Series**, with a chevron only when there is a URL. **Part N of M** is omitted on purpose (2026-09-14): the total is not on the work page. Headline is **Language · N words** / **upd DATE**, monospace. Published and Added are extra rows the board does not draw; the file comment says dropping a known fact to match the mock is a regression. No AO3 collection row: `AO3WorkSummary` has no collection property. Counts use `.formatted()` (the board prints **1,773** and **5,207**), not the compact 1.2K used on chips and cards.
- Tally order Kudos, Comments, Bookmarks, Hits, same chrome as the figure strip, top inset 14. Comments is the cell with the action. The missing chevron and label tint are batch-6-3.
- **Open on AO3** outline copy matches. Button chrome matches; the other label and the 41pt height are batch-6-7.
- My copy row: title **My copy** 15pt medium, subtitle 12pt, icon `iphone` at 17pt, chevron, radius 14, padding 14×16, gap 12, top inset 10. Summary is **Downloaded · N queues · N collections · N tags**, zeros omitted, empty state **Nothing saved on this device yet** (`WorkDetailComponents.swift:123`). Shown only when a local work exists. The board’s sample omits collections; the code adds them when the count is real.
- A second **Series** card (`WorkDetailOverviewSections.swift:224`) sits below the facts row: the series name, other downloaded works, **Download Whole Series**, **View Full Series on AO3**. The facts-file comment (`WorkDetailFactsSections.swift:104`) keeps it as navigation. Not filed.
- Comment entry points on this page — **All comments**, **Chapter comments** (unless the work is one chapter), **Write a comment**, plus the footnote **“Comment pages load when you open them; nothing is fetched in advance.”** — are the documented extra (`WorkDetailSections.swift:112`). The accented tally cell is also wired. Not filed.
- `overviewSections` still exists and is not what `body` renders. `pageSections` is the live order. Not a user-facing duplicate.

### 1a — My copy sheet

- The actions the board lists are present, under the old chrome (batch-6-2): saved toggle, saved-for-later with a preservation footnote, per-queue position lines, collections, finished toggle, **Downloaded · size**, **Converted from**, **Conversion / Up to date**, rebuild when stale, **Added**, **Last Opened**, a progress bar from `publicationProgress`, provenance, **Add a tag**, suggestion chips, footer **“My Tags are private to your Library on this device and separate from AO3's tags.”**
- Empty local copy: **“Not in your Library yet. Save it, queue it, or start reading and your download, progress, and tags will appear here.”**
- Drag indicator is on. The close control is **Done**, not the 28pt X (batch-6-2).

### 1f — comments list

- Default sort is newest (`newestFirst`). Sort menu **Oldest First** / **Newest First**; the pill reads **Newest** or **Oldest**. Both pills call `minimumHitTarget()` (44).
- Signal cells: **Comments** is `page.totalComments`, exact `.formatted()`, the whole work. **Threads**, **Yours**, **Latest** are counted from the loaded page. **Yours** is omitted when signed out. When `totalPages > 1` the note says **“Threads, yours and latest count this page. AO3 pages its comments, and only the comment total is the whole work’s.”** **Latest** uses `.relative(presentation: .numeric, unitsStyle: .narrow)`. Whether that string is **31m** or **31m ago** was not executed; not filed as a mismatch.
- **1f.4** continuous loading is **No** (`REDESIGN_DECISIONS.md`). The list pages with **Previous**, **Page N of M**, **Next**, each previous/next at 44pt (`CommentsView.swift:761`). The board’s **Loading more comments…** row is the superseded design.
- **1f.5:** inline depth is 5 (`CommentThreadGeometry.maxInlineDepth`). Deeper replies use **Continue thread** · **N deeper replies** (singular **1 deeper reply**), a chevron, min height 44. AO3’s own cutoff placeholder stays.
- Section header **Comments** plus a monospaced medium count of loaded comments, including replies. The hairline the board draws after the count is gone because `SectionRuleHeader` no longer draws one (`SubjectSurface.swift:594`, owner call). Not reverted.
- Loading is four `CommentSkeletonRow`s shaped like a root comment: 30pt circle, name bar, three text lines, shimmer (`CommentsView.swift:1521`). Empty is **No Comments Yet** / **Be the first to leave one.** The write pill is still on screen in `.loaded`, including the empty case. Failure is **Couldn't Load Comments** with the server message and **Try Again**. Offline stale comments show a banner. Pull to refresh calls `model.load(forceRefresh: true)`.
- Write pill copy **Write a comment** / **Log in to comment**, 14pt semibold, dark-on-accent, height 44, horizontal padding 20. Signed out opens the login sheet. Disabled and dimmed to 0.45 when offline. Icon and shadow are batch-6-10.
- Body: 14pt scaled from `.body`, line spacing about 0.35× the size (the 1.55 line height), opacity 0.8, collapsed at 5 lines then **Read more** / **Show less**, Reduce Motion respected.
- Names step 14 / 13.5 / 13, semibold. Avatars 30 / 26 / 22. Avatar-to-text gap 11 / 10. Rail 1pt, elbow radii 21 / 18, conversation gap 18. Rails are `glassStroke`, not an accent stripe. Initials are the first grapheme, uppercased. Guests use `person.fill`.
- **Author** / **Me** / **Guest** are the role raw values. The author glyph is `person`, and the comment at `CommentThreadRow.swift:285` says that is the author symbol on Home, the work hero, and this badge. Not filed as “use the board’s star.” Badge type is caption2 semibold on `.tint` with white text; the board is 10pt semibold, dark on the page accent. Recorded here rather than as its own finding: it is the same `.tint` / white pair as the rest of the role chips.
- Signed-out rows keep Reply off and overlap the overflow so the lone ellipsis does not open a gap (`CommentActionRowLayout`). That is the **signed-out action row gap = Fix** decision, implemented.
- Delete confirmation: **Delete this comment?** / **This removes the comment on AO3. It can't be undone.** / **Delete** / **Cancel**. Leading swipe is full-swipe **Reply**. Trailing swipe does not full-swipe, and **Delete** is last.
- A pushed thread (`CommentThreadScreen`) reuses the row chrome, hides the chapter badge, and when the subtree is gone shows **Thread Unavailable** / **This comment is no longer part of the loaded page.** No separate retry: the comment is no longer on the loaded page.
- Modal presentation uses an X labelled **Close** and, when offered, an expand control. A push uses the system back button. The board draws a back chevron because it is a sheet over the reader; the push path is the system one. macOS sets `navigationTitle("Comments")` (`:169`).
- Wash height is 480 against the board’s 520. Measured, not filed on its own.

### 1ba / 1be — composer

- Build note “posting comments is an AO3 write the app does not implement” is stale. `CommentComposerSheet` posts. Title is **Reply to {author}**, **New comment**, or **Edit comment**. An edit’s button is **Save**; a reply’s is **Post**, not “Post Reply” (`:1191`).
- Character budget is 10,000 unicode scalars (`:1181`), which is the AO3 code-point count. Identity line is **as {username}** or **Not signed in**, and **N left**, both 11.5pt. Over budget turns the count red. Decision B2 is fixed.
- Caption: **“the footer says the sheet drags taller.”** The constant `dragTallerFooter` is **Drag the sheet taller** and it is drawn under the identity row (`:1249`). The 462px frame’s HTML does not contain those words; the caption does. Not a defect.
- Detents are `[.medium, .large]` with a drag indicator. The comment at `:1332` says `.medium` stands in for 462pt and the keyboard shortens it, and that a pinned `.height(462)` would be one phone’s number. That is 1be’s “two numbers, not two layouts.”
- Format bar is a bottom `safeAreaInset`, so it rides the keyboard (1be). Its glass circles are batch-6-6. Bar metrics (52, pad 12, gap 2, top hairline) match.
- A by-chapter new comment shows **“New comments post to the whole work — AO3 shows them on its latest chapter.”** The board does not, and the sentence is true. Not filed.
- Placeholders **Write your reply…** / **Share your thoughts…** sit where the board shows typed text. Drafts autosave. Busy posting replaces the button label with a progress view. Submission states (**We're checking whether this posted…**, **Check Again**, **Posted.**) are real and not on the board.
- Quote metrics that match: padding 10×12, radius 11, 2pt accent rail, body 12.5pt. The colour split, the 3-line clamp, and the 0.09 fill are batch-6-11.

### 1bf — tray

- Title **Formatting**, **Done** capsule, four columns (two at an accessibility size, one at accessibility3), gap 7, tile min height 58, radius 11, fill 0.09, inner spacing 3.
- Tags, in order: Bold/strong, Italic/em, Underline/u, Strike/s, Superscript/sup, Subscript/sub, Small/small, Code/code, Quote/blockquote, Bullets/ul, Numbers/ol, Heading/h1–h6, Divider/hr, Link/a href, Spoiler/details. Image is absent (`AO3Markup` refuses `<img>`). `<p>` and `<br>` are left out of the comment vocabulary on purpose: AO3 paragraphs the body, and the chapter editor is the surface that writes them.
- Heading is one tile labelled `h1–h6`, then a row of `SubjectChip`s for h1–h6. A tap on the tile writes h3. The chips are how a level is chosen; the board has no second control, and without them the range label would be a lie. Not filed.
- Group-label size, tile type size, and the undecorated U/S are batch-6-12.
- Tray wash is `subjectWash` at 320, not `subjectScreenWash`, so the sheet keeps its own bar. Done’s row is `minHeight: 44`.

### Accessibility and platform (checked in code, not on a device)

- Comment rows, the write pill, pagination, sort and chapter pills, the formatting **Done** button, and Reply use a 44pt target. ON AO3 chips, tag chips, and the my-tag delete use a documented smaller floor (30 or 28) because they share a row. Outline buttons do not (batch-6-7).
- Comment overflow, Reply, the delete alert, the skeleton (`accessibilityHidden`), and the resume card expose labels. **REPLYING TO YOU** is `accessibilityHidden` because the row hint already says it.
- Reduce Motion is checked for the summary toggle and for **Read more**.
- `#if os(macOS)` guards the inline title mode, the sheet drag indicator, and the comments navigation title. iPad and macOS layout were not run. Keyboard avoidance for 1be is the `safeAreaInset`; it was not watched with a keyboard up.

---

## The three that matter

1. **batch-6-1.** The locked caption of 1a is “AO3 actions on the page, the local half behind a sheet.” The page still shows a **Quick Actions** grid of the local work, and the ellipsis is the AO3 menu (no **Share**, no **Add to Queue**, no **Add to Collection**). The code comment says that swap is staged.
2. **batch-6-2.** The second device of 1a — **Private to this device**, the progress / size / preserved strip, one row per queue with **#3 of 12**, accent add rows, tinted tags — was never built. The sheet is still the old library list, closed with **Done**.
3. **batch-6-6.** Three of the five boards are the composer. **Post** is a system bar button, and the format bar is glass circles with SF Symbols, while the tray two taps away already draws the Georgia B/I/U/S the bar is supposed to be. The comments header being 32/15.5 on a 16pt gutter (batch-6-4) is the next one, if the list matters more than the sheet you type in.
