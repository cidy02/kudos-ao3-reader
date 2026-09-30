# Batch 3 queue UI polish audit (Codex)

Static, read-only audit of artboards `1h`, `1h.1`, `1h.2`, `1h.3`, `1h.4`, `1i`, `1j`, `1bg`, and `1bh` against `integrate/cloud-redesign`. I did not build, run Swift/Xcode, launch a simulator, or contact AO3.

## Findings

### batch-3-1 — P1

- **Artboard + code:** `1h`, `1h.1`, `1h.2`, `1bg` — `kudos-ao3-reader/Features/Library/ReadingQueueBrowser.swift:102-105`, compared with `kudos-ao3-reader/Features/Privacy/MatureContent.swift:62-65,87-90` and `kudos-ao3-reader/Features/Library/LibrarySectionListView.swift:98`.
- **Spec/convention:** PLAN B says Show/Hide Mature must work on every works screen whenever Hide Mature is on. The shared `SensitiveWorkRow`/`SensitiveWorkCoverCard` contract explicitly says Hide-mode callers remove hidden works before rendering.
- **Code:** `visibleWorks` applies only the queue quick filter and `LibraryFilters`; it never calls `PrivacyGate.isHidden`. In Hide mode, the sensitive row/card wrappers do not hide anything, so Mature/Explicit queue works remain visible even though the overflow offers “Show mature.”
- **Smallest fix:** inject `PrivacyGate` plus `matureContentMode`, remove `gate.isHidden(...)` works before the quick/library filters, and keep the existing reveal toggle so it invalidates that filtered result.

### batch-3-2 — P1

- **Artboard + code:** `1bg` — `kudos-ao3-reader/UIComponents/ScopedRemovalBulkActionBar.swift:119-124`; selection state is cleared only by `ReadingQueueBrowser.swift:932-937`.
- **Spec/convention:** “Move to” is one of the four queue-selection actions; after moving, the selected rows leave this queue and selection mode must end coherently.
- **Code:** successful move dismissal calls `onRemove()` but not `onDone()`. The rows disappear from `works`, while `selection` and the navigation title can remain “N selected”; all actions then operate on an empty `selectedWorks` array.
- **Smallest fix:** call `onDone()` immediately after `onRemove()` in the successful `showingMoveToQueue` dismissal branch.

### batch-3-3 — P1

- **Artboard + code:** `1h` add-works flow — `kudos-ao3-reader/Features/Library/AddLibraryWorksSheet.swift:26-40,61-67,91-99`.
- **Spec/convention:** PLAN B requires Show/Hide Mature on every works screen; PLAN E requires an empty state with an action. Other Library work lists expose `MatureRevealToggle` even when hiding leaves no visible rows.
- **Code:** the picker removes hidden Mature/Explicit candidates but has no reveal control. If all addable works are hidden, it reports “Every work in your library is already in this queue, or there are no works to add yet,” which is false, and offers no recovery action.
- **Smallest fix:** add `MatureRevealToggle` to the sheet toolbar when Hide Mature is enabled and distinguish “hidden works are available” from the genuine no-candidates state; the former should offer “Show mature.”

### batch-3-4 — P2

- **Artboard + code:** `1h.3`, `1h.4`, `1bg` — `kudos-ao3-reader/Features/Library/ReadingQueueSettingsView.swift:309-319` and `kudos-ao3-reader/UIComponents/ScopedRemovalBulkActionBar.swift:247-263`.
- **Spec/convention:** PLAN E requires visible loading/error states and retry for fetching work. “Keep downloaded” and “Download” promise an observable result.
- **Code:** both download loops use `try?`, discard every failure, and expose no error or retry. Queue Details flips the toggle on before downloading; the bulk bar merely disables “Download” during the task and silently re-enables it if copies are still missing.
- **Smallest fix:** retain the first failure plus failed count in view state, show a compact error/retry message, and leave successful copies intact.

### batch-3-5 — P2

- **Artboard + code:** `1h` empty queue — `kudos-ao3-reader/Features/Library/ReadingQueueBrowser.swift:401-417`; the queue setting is implemented at `ReadingQueueSettingsView.swift:291-300`.
- **Spec/convention:** a queue can be a plain list when “Keep works offline” is off; 1j says, “Off, the queue is just a list — nothing is preserved.”
- **Code:** every empty queue says, “Works you add to this queue will keep a local EPUB for offline reading,” even when `keepsWorksOffline == false`.
- **Smallest fix:** make the empty description conditional on `KeepOffline.queueKeeps(selectedQueue.keepsWorksOffline)`.

### batch-3-6 — P2

- **Artboard + code:** `1h` — `kudos-ao3-reader/Features/Library/ReadingQueueBrowser.swift:713-734`.
- **Spec/convention:** PLAN B locks the overflow order to Show/Hide Mature · Select · Reorder · display mode · Expand/Collapse · page items · destructive last.
- **Code:** the queue menu renders Mature · **Reorder · Select** · display mode · Queue Details · Rename · Delete.
- **Smallest fix:** swap Select and Reorder; keep the existing divider before queue-specific items.

### batch-3-7 — P2

- **Artboard + code:** `1h` — `kudos-ao3-reader/Features/Library/ReadingQueueBrowser.swift:60-65,222-230,713-734`.
- **Spec/convention:** PLAN B places Expand/Collapse All after the display-mode picker. The queue offers a real “Detailed” mode whose standard rows can expand.
- **Code:** there is no `expandAll` state or `ExpandAllMenuItem`, and `SensitiveWorkRow` always receives its default `expandAll: false`.
- **Smallest fix:** add one `expandAll` state, pass it into detailed standard rows, and insert the shared `ExpandAllMenuItem` after `DisplayModeMenuPicker` (only when Detailed is selected, if desired).

### batch-3-8 — P2

- **Artboard + code:** `1h`, `1h.1`, `1h.2` — `kudos-ao3-reader/Features/Library/ReadingQueuePageParts.swift:207-229` and `ReadingQueueBrowser.swift:538-540,594-596`.
- **Spec/convention:** the final 1h prose explicitly supersedes the earlier mock: “List and grid are no longer an inline picker — the view choice lives in the overflow menu, so the section header carries only its label.”
- **Code:** `QueueInLineHeader` still appends a segmented list/grid picker to “In Line,” while the overflow also contains the three-way display picker.
- **Smallest fix:** make `QueueInLineHeader` just `SectionRuleHeader(title:count:)`; delete its binding and leave the shared overflow picker as the sole control.

### batch-3-9 — P2

- **Artboard + code:** `1h` — `kudos-ao3-reader/Features/Library/ReadingQueueBrowser.swift:63-65,465-471`.
- **Spec/convention:** 1h says, “Up next stays a ringed row either way.”
- **Code:** `ledgerRow` uses `rowPresentation`; when the overflow selects Detailed, Up Next becomes a standard expandable card rather than the ringed ledger row. Compact explicitly forces ledger, so the three modes disagree.
- **Smallest fix:** render the Up Next call with `.ledger` independently of `rowPresentation`; apply the chosen presentation only to In Line.

### batch-3-10 — P2

- **Artboard + code:** `1bg` — `kudos-ao3-reader/Features/Library/ReadingQueueBrowser.swift:451-460,506-520`.
- **Spec/convention:** the artboard puts only the compact “NEON REREAD — 3 / 11” status rule beneath the selection title bar.
- **Code:** select mode renders the full 32pt queue hero (`SubjectHeaderBlock`, including kicker/name/subtitle) and then the compact selection status row, duplicating the queue identity and pushing the selectable rows down.
- **Smallest fix:** in selection mode, omit `subjectHeader` and render only `selectionStatusRow` before the flat rows.

### batch-3-11 — P2

- **Artboard + code:** `1bg` — `kudos-ao3-reader/UIComponents/ScopedRemovalBulkActionBar.swift:147-178,181-187`; mounted by `ReadingQueueBrowser.swift:782-790`.
- **Spec/convention:** the artboard’s replacement bottom bar contains exactly “Download · Move to · Tag · Remove.”
- **Code:** the queue bar adds “More” and a Done checkmark, for six controls, and prints “Remove from Queue” rather than “Remove.” This is both denser and a different action hierarchy than the mock.
- **Smallest fix:** keep the four artboard actions in the bottom bar; move selection exit to the top title-bar control/conventional cancel placement, and put secondary library actions in the row context menu rather than a fifth bottom item.

### batch-3-12 — P3

- **Artboard + code:** `1bg` — shared number styling at `kudos-ao3-reader/UIComponents/AppThemeSurface.swift:260-285`, applied by `ReadingQueueBrowser.swift:457-460`.
- **Spec/convention:** 1bg uses a 26pt number column with 15pt bold queue-colour numbers; 1h.1 uses the quieter 17pt/12pt tertiary number.
- **Code:** selection mode reuses the normal 1h.1 number style unchanged (17pt column, 12pt medium, tertiary).
- **Smallest fix:** let `cardRow` accept a selection-number style (or pass width/font/colour) and use the artboard’s larger accented variant only in queue selection mode.

### batch-3-13 — P2

- **Artboard + code:** `1h.1` — `kudos-ao3-reader/Features/Library/ReadingQueueBrowser.swift:231-241`; comparison convention at `kudos-ao3-reader/Features/Library/Collections.swift:493-502`.
- **Spec/convention:** scoped removal is destructive within its container; Collection rows use the shared `destructiveConfirmation`, and 1bg bulk removal also confirms.
- **Code:** a list-row “Remove from Queue” swipe immediately mutates membership with no confirmation, while the same job in a collection and in queue bulk mode asks first.
- **Smallest fix:** stage the row in `pendingRemoval` and use the shared scoped destructive confirmation copy before calling `removeFromQueue`.

### batch-3-14 — P2

- **Artboard + code:** `1h.2` — `kudos-ao3-reader/Features/Library/ReadingQueueBrowser.swift:664-670`; generic menu contents at `kudos-ao3-reader/Features/Library/WorkCardActions.swift:336-432`.
- **Spec/convention:** list mode exposes per-work removal; the same queue action must remain reachable when the same works are shown as cards.
- **Code:** compact cards get only the generic local-work context menu. That menu can delete the work from Kudos, but has no “Remove from Queue,” so grid mode loses the safe scope-specific action and leaves only bulk selection.
- **Smallest fix:** allow this call site to append one page-specific destructive “Remove from Queue” item (with the same confirmation as finding 13).

### batch-3-15 — P2

- **Artboard + code:** `1h`/`1h.1` and `1j` — `kudos-ao3-reader/Features/Library/ReadingQueuePageParts.swift:182-190`, `NewReadingQueueSheet.swift:155-178`, and shared `kudos-ao3-reader/UIComponents/SubjectSurface.swift:918-980`.
- **Spec/convention:** queue header/new-queue tags are 9.5pt semibold uppercase, 3×7pt padding, radius 6; organizer row tags already implement that exact language at `ReadingQueueOrganizer.swift:714-727`.
- **Code:** the header and creation sheet use the generic 13pt sentence-case `SubjectChip` with 6×11pt padding and radius 8. The same queue tag therefore changes typography and density between 1h/1j and 1i.
- **Smallest fix:** reuse/expose the existing compact queue-tag label style for 1h/1j, retaining a dashed compact variant for “+ Tag”/“+ New tag.” Keep the larger removable chips on Queue Details, where 1h.3 specifies them.

### batch-3-16 — P2

- **Artboard + code:** `1h`, `1h.1`, `1h.2` — `kudos-ao3-reader/Features/Library/WorkRow.swift:121-127,146-150` and `kudos-ao3-reader/UIComponents/SubjectSurface.swift:849-878`.
- **Spec/convention:** PLAN D says there must be no raw “0%” claims.
- **Code:** every unread ledger row creates `WorkProgressRing(progress: work.readingProgress ?? 0, state: nil)`, and the ring unconditionally prints `0%`; only the state word is suppressed.
- **Smallest fix:** make the unread leading state render an empty ring/“Unread” (no percentage), or make the shared ring accept a nil progress and omit its numeric label.

### batch-3-17 — P2

- **Artboard + code:** `1h.1`, `1h.2` — raw fandom display at `kudos-ao3-reader/Features/Library/WorkRow.swift:103-105,134-138` and `kudos-ao3-reader/Features/Home/HomeCards.swift:95-97`.
- **Spec/convention:** PLAN D requires bare fandom names where the artboard shows “Cyberpunk 2077,” “Doctor Who,” and “Star Wars”; the codebase’s verified display helper is `FandomDisplayName`.
- **Code:** ledger and compact queue cards print the raw first AO3 fandom tag, including media/format disambiguation and multilingual `|` segments.
- **Smallest fix:** display `FandomDisplayName.split(FandomDisplayName.primarySegment(of: raw)).title` while preserving the raw tag for identity/filtering and hue if desired.

### batch-3-18 — P2

- **Artboard + code:** `1h`, `1i` — queue pills at `ReadingQueuePageParts.swift:195-200`; organizer pills/stat strip/row count at `ReadingQueueOrganizer.swift:175-205,449-458,523-529`.
- **Spec/convention:** PLAN D says counts above 999 are compact on chips, cards, and stat strips; the established implementation is `.formatted(.number.notation(.compactName))` (`SubjectScreen.swift:608-613`).
- **Code:** all queue quick-filter counts, organizer tag-filter counts, Queues/Works/Offline stats, and per-queue card counts interpolate raw integers.
- **Smallest fix:** apply the existing compact-name formatter at those four display boundaries; keep exact counts in prose, accessibility values, seed copy, and selection totals.

### batch-3-19 — P3

- **Artboard + code:** `1h.2` — `kudos-ao3-reader/Features/Library/ReadingQueueBrowser.swift:614-622`; shared metrics at `kudos-ao3-reader/UIComponents/CarouselCardStyle.swift:33-51,141-152`.
- **Spec/convention:** the artboard centers two 164×232 cards with 12pt column and 14pt row gaps.
- **Code:** the cards are correctly 164×≈232, but the grid uses 16pt in both axes and is leading-aligned; the shared adaptive columns deliberately leave spare width on the trailing edge.
- **Smallest fix:** for this grid call site, pass 12pt column spacing, 14pt `LazyVGrid` spacing, and center the resulting columns. Do not change global carousel metrics.

### batch-3-20 — P2

- **Artboard + code:** `1h`, `1h.3`, `1h.4` — `kudos-ao3-reader/Features/Library/ReadingQueueBrowser.swift:496,602` and `ReadingQueueSettingsView.swift:232-234`; default defined at `kudos-ao3-reader/UIComponents/SubjectScreen.swift:121-126`.
- **Spec/convention:** the queue artboards resolve their wash at 560pt; Queue Details uses 620pt.
- **Code:** both screens take `subjectScreenWash`’s 380pt plain-list default, so the stored queue colour fades to the base page 180–240pt too early.
- **Smallest fix:** pass `washHeight: 560` on the queue page and `washHeight: 620` on Queue Details.

### batch-3-21 — P2

- **Artboard + code:** `1h.3`, `1h.4` — `kudos-ao3-reader/Features/Library/ReadingQueueSettingsView.swift:171-177`.
- **Spec/convention:** Queue Details repeats both the bare 5pt progress strip and “2 finished · 1 in progress · 9 unread · 9 of 12 kept offline.”
- **Code:** it renders only `QueueProgressStrip`; the legend is absent.
- **Smallest fix:** render `ReadingQueueFacts.legend(...)` immediately below the strip with the existing 11.5pt secondary treatment used by `QueueHeaderDetails`.

### batch-3-22 — P2

- **Artboard + code:** `1h.3`, `1h.4` — `kudos-ao3-reader/Features/Library/ReadingQueueSettingsView.swift:180-229,277-334`.
- **Spec/convention:** the artboard order is DESCRIPTION (bare serif note) · TAGS · one DETAILS panel containing Colour / Keep works offline / Order / Last read · offline consequence · separate Manage all tags row.
- **Code:** the screen is Description panel · Details (Order/Preserved/Last read) · separate Colour swatch panel and explanatory copy · Tags panel with Manage all tags inside · Offline and order (Pin/Keep downloaded) · Rename & Delete. It adds a redundant Preserved figure, moves Colour and Offline out of Details, renames “Keep works offline” to “Keep downloaded,” and wraps the serif note in a card.
- **Smallest fix:** reorder the existing views to the artboard, fold the colour/offline/order/last-read controls into one Details panel, restore the exact labels, remove the duplicate Preserved row, and place Manage all tags after the details/footnote. Pin can remain as an additional Details row if the owner wants 1i’s pin control here.

### batch-3-23 — P2

- **Artboard + code:** `1h.3`, `1h.4` — `kudos-ao3-reader/Features/Library/ReadingQueueSettingsView.swift:223-229,336-356`; queue overflow reference at `ReadingQueueBrowser.swift:793-815`.
- **Spec/convention:** 1h says rename and delete stay in “…”; PLAN B puts page items in that menu and destructive last. The Details mock has a trailing ellipsis and no Rename & Delete content block.
- **Code:** Queue Details has no toolbar overflow and instead adds a full Rename & Delete panel at the bottom. The parent queue screen separately retains those same menu actions.
- **Smallest fix:** add `WorkListMoreMenu` to Queue Details with Rename then Delete, and remove the body management section.

### batch-3-24 — P2

- **Artboard + code:** `1i` — the omission is explicit at `kudos-ao3-reader/Features/Library/ReadingQueueOrganizer.swift:26-30`; the rail implementation at `175-190` has no trailing action.
- **Spec/convention:** the 1i tag rail ends with the dashed “Edit tags” control.
- **Code:** it is deliberately omitted, leaving no organizer-level route to maintain the vocabulary represented by that rail.
- **Smallest fix:** add the dashed control at the rail’s trailing edge and route it to one all-queues tag manager; do not overload the per-queue `QueueTagManagerView`, whose counts/actions are queue-scoped.

### batch-3-25 — P2

- **Artboard + code:** `1i` — pinned rows at `kudos-ao3-reader/Features/Library/ReadingQueueOrganizer.swift:254-262`, versus all-queues rows at `274-293`.
- **Spec/convention:** PLAN B requires trailing swipe actions on lists of user-owned things; the same custom queue appears in Pinned and All queues.
- **Code:** only the All queues copy has Rename/Delete swipes. Swiping the identical row in Pinned does nothing.
- **Smallest fix:** extract/apply the existing custom-queue swipe block to both row placements; keep Saved for Later non-deletable.

### batch-3-26 — P2

- **Artboard + code:** `1i` — `kudos-ao3-reader/Features/Library/ReadingQueueOrganizer.swift:232-300`.
- **Spec/convention:** PLAN E requires a nonblank empty state with an action. The comparable collection screen shows “No matching works” plus “Clear Filters.”
- **Code:** a search/tag filter with zero queues leaves “ALL QUEUES 0” followed by the unrelated New Queue row. There is no “No matching queues,” no explanation, and no clear-search/filter action.
- **Smallest fix:** when `visibleQueues.isEmpty` and a search/tag filter is active, show `ContentUnavailableView` with the active cause and a “Clear Search and Filters” action; keep New Queue below or in the action set.

### batch-3-27 — P3

- **Artboard + code:** `1h`, `1i` — `kudos-ao3-reader/Features/Library/ReadingQueueBrowser.swift:717-725` and `ReadingQueueOrganizer.swift:399-406`.
- **Spec/convention:** PLAN B says Reorder is off under filters **with a reason**.
- **Code:** both menus disable Reorder and attach `.help(...)`. That exposes the reason on pointer-hover platforms but not in the iPhone menu where the disabled action appears.
- **Smallest fix:** include the reason in visible menu copy/secondary text (for example, a disabled “Clear filters to reorder” item) while retaining `.help` for macOS.

### batch-3-28 — P1

- **Artboard + code:** `1h`, `1i`, `1j` — interactive chips at `kudos-ao3-reader/UIComponents/SubjectSurface.swift:918-939`, queue pills at `FavoriteAuthorFilterRail.swift:22-31`, organizer pills at `ReadingQueueOrganizer.swift:192-205`, new-queue tag buttons at `NewReadingQueueSheet.swift:155-178`, and swatches at `SubjectHueSwatches.swift:50-83`.
- **Spec/convention:** PLAN F requires 44pt targets. The repo already supplies `minimumHitTarget()` for this exact purpose.
- **Code:** pill/tag buttons are roughly 27–29pt tall and swatches are 34pt (28pt circle + 3pt each side); none of these call sites applies a 44pt hit floor.
- **Smallest fix:** apply `minimumHitTarget()` to the actual `Button`s for quick filters, organizer tag filters, new-queue tags, and hue swatches while preserving the visible chip/circle size.

### batch-3-29 — P3

- **Artboard + code:** `1i` — `kudos-ao3-reader/Features/Library/ReadingQueueOrganizer.swift:192-205`.
- **Spec/convention:** visible tag pills include both label and queue count (“Rereads 2”); PLAN F requires labels/values to carry the same useful information.
- **Code:** `.accessibilityLabel(title)` overrides the visible `"\(title) \(count)"`, so VoiceOver hears “Rereads, button” and loses the count.
- **Smallest fix:** keep `title` as the label and add `.accessibilityValue("\(count) queue(s)")`, or label the full visible string.

### batch-3-30 — P2

- **Artboard + code:** `1j` — `kudos-ao3-reader/Features/Library/NewReadingQueueSheet.swift:34-35,85-96` and `kudos-ao3-reader/UIComponents/SubjectHueSwatches.swift:23-29,50-68`.
- **Spec/convention:** 1j includes a dashed “+” after the palette for a custom hue.
- **Code:** the shared row exposes only five fixed swatches; the file comment explicitly records the custom hue as not built.
- **Smallest fix:** add a trailing dashed custom-colour control using the native colour picker and store its hue in the existing `Double?` binding.

### batch-3-31 — P2

- **Artboard + code:** `1j` — `kudos-ao3-reader/Features/Library/NewReadingQueueSheet.swift:117-130`.
- **Spec/convention:** 1j explicitly specifies 34pt circular glass dismiss/check controls, with the check accent-filled.
- **Code:** the sheet uses text “Cancel” and “Create” navigation-bar buttons. This deliberately matches `NewCollectionSheet`, but it does not match the queue artboard’s chrome.
- **Smallest fix:** if artboard fidelity wins, use icon-only xmark/checkmark toolbar buttons with the existing accessible labels and queue-accent tint; apply the same chrome decision to New Collection so C consistency is not traded for A fidelity.

### batch-3-32 — P3

- **Artboard + code:** `1j` — `kudos-ao3-reader/Features/Library/NewReadingQueueSheet.swift:92-102,117,293-301`.
- **Spec/convention:** exact artboard copy is “New Queue”; “Set once instead of derived from the name, so renaming a queue no longer changes its colour”; tags explain that “Long fic” means the same thing; Saved for Later says “Copy all 12, leaving them saved.”
- **Code:** title is “New queue”; the colour/tag notes are rewritten generically and conditionally; seed copy adds “in the same order” and repeats “Saved for Later.” Meaning is close, but capitalization and copy are not exact.
- **Smallest fix:** restore the artboard title and helper sentences verbatim, substituting only the live seed count.

### batch-3-33 — P2

- **Artboard + code:** `1bh` — rows at `kudos-ao3-reader/Features/Library/QueueTagManagerView.swift:111-130`; edit sheet capabilities at `200-335`.
- **Spec/convention:** 1bh requires a row “…” menu ordered Rename · Merge into… · Show only this tag · Copy tag to another queue · Remove from N works (destructive last).
- **Code:** tapping anywhere on a row opens Edit Tag directly. Rename/Merge/Remove exist in that sheet, but there is no row menu, no “Show only this tag,” and no “Copy tag to another queue.”
- **Smallest fix:** add the ordered trailing menu; reuse the edit sheet for Rename/Merge, add the two missing scoped actions, and route Remove through the existing confirmation. Collaboration-only author/permission copy can remain omitted because the app has no shared queues.

### batch-3-34 — P2

- **Artboard + code:** `1h`/`1h.1`/`1h.2` — queue-specific bottom bar at `kudos-ao3-reader/Features/Library/ReadingQueueBrowser.swift:344-348,746-754` and `kudos-ao3-reader/Features/Library/ReadingQueueSwitcher.swift:19-66`.
- **Spec/convention:** 1h navigates back to the 1i organizer and shows no queue-switcher bar; its bottom mock chrome is the app-level tab/search system. The organizer now supplies the one-screen overview/switching job.
- **Code:** compact queue pages hide the app tab bar and install a second queue-navigation system at the bottom: All Queues icon · current queue capsule · New Queue. This is unique to this screen and duplicates the organizer plus the accent-filled top “+”.
- **Smallest fix:** remove the compact bottom switcher toolbar and let Back return to the organizer; retain the top Add Works action. If the app-wide pushed-screen rule continues to hide tab/search, leave the bottom clear rather than inventing queue-only chrome.

### batch-3-35 — P3

- **Artboard + code:** `1i` — `kudos-ao3-reader/Features/Library/ReadingQueueOrganizer.swift:301-304,213-218`.
- **Spec/convention:** the 1i frame is a flat `#0b0b0d` organizer; colour belongs to each queue row rather than one page-wide subject.
- **Code:** the organizer applies a 380pt `subjectScreenWash` using the global scope palette, adding a page gradient that the artboard does not show.
- **Smallest fix:** keep the transparent navigation chrome but use the app base backdrop (no subject wash) for this non-subject aggregate page.

## Per-screen coverage: checked, matches

### `1h` — queue family / shared requirements

- **A:** Stored queue hue drives `SubjectHeaderBlock`, page wash, add-button tint, and Queue Details (`ReadingQueueBrowser.swift:150-153`; `ReadingQueueSettingsView.swift:43-45`). Header uses the specified kicker/name/subtitle order and 32pt shared hero component.
- **B:** Add Works is a prominent top-toolbar `+`; Filter is directly visible; Queue Details/Rename/Delete are in the overflow with Delete last. Reorder is a mode and Done exits it; drag is disabled under narrowing filters. Findings 6–8, 13–14, 27, and 34 cover the remaining action defects.
- **C:** Uses shared `SubjectHeaderBlock`, `SectionRuleHeader`, `SubjectPillRail`, `FilterButton`, `ActionToolbar`, `WorkListMoreMenu`, `SensitiveWorkRow`, and `ScopedRemovalBulkActionBar` rather than local lookalikes.
- **D:** Header and legend keep exact counts in prose; word counts already use the app’s compact `WorkStat.localWorkMetadata`. Findings 16–18 cover the verified D failures.
- **E:** Genuine-empty and filtered-empty states both exist and have Add Works/Clear Filters actions. Pull-to-refresh is present. Findings 3–5 cover false/missing download and picker states.
- **F:** Progress strip has a combined spoken label; numbered rows announce position; grid reorder exposes Move Up/Down/Top/Bottom accessibility actions. Finding 28 covers undersized direct controls.
- **G:** Compact and regular layouts are explicit; iPhone selection owns bottom chrome; iPad/macOS use a sidebar; content is refreshable. This was code inspection only, not a build or visual check.

### `1h.1` — queue list

- Header, 5pt segmented progress strip, 11.5pt legend, quick-filter counts, Up Next/In Line split, stable whole-queue position numbers, 18pt block spacing, and 10pt rule-to-content intent are implemented.
- Rows use the shared ledger surface and queue positions remain stable under filters. Swipe removal exists and always means membership removal, not deleting the work from Kudos. Findings 13 and 17 cover confirmation/display gaps.
- No always-on drag handle: reorder handles are active only in reorder/select modes.

### `1h.2` — queue grid

- Cards use the shared 164×√2 (≈232) cover size and 16pt corner radius; Up Next stays a ledger row in Compact mode; per-queue display choice persists in UserDefaults.
- Grid select/reorder keeps a dedicated handle and supplies VoiceOver reorder actions. Findings 9, 14, and 19 cover the verified mode/action/spacing differences.

### `1h.3` / `1h.4` — Queue Details colour variants

- Both variants map to the same data-driven view; queue hue changes the palette rather than branching on a fixed violet. Kicker path, 32pt queue name, exact work/offline/storage subtitle, serif editable description, removable tags, stored hue, pin/offline controls, manual order, and latest-read date are implemented.
- Queue deletion is a soft delete to Recently Deleted for 90 days and confirms with copy that works remain in Kudos.
- Findings 4, 20–23 cover the verified visual hierarchy, progress, action-placement, and error-state differences.

### `1i` — organizer

- **A/C:** Search is in-content with exact placeholder; the four-cell shared stat strip matches 13pt/9pt metrics; tag rail is pill-shaped; rows are 16pt hue-washed cards with 44pt 2×2 peek tiles, 10pt colour dots, progress strips, compact tag labels, offline count/size, and 8pt inter-card spacing.
- **B:** Header exposes New Queue and overflow; overflow orders Select before Reorder; reorder is a mode with Done; selection bulk actions are Pin/Unpin, Tag, Delete, Done; delete confirms and soft-deletes only custom queues. No always-on drag handles remain.
- **Data:** Saved for Later is included; pinned queues are repeated as shortcuts and deduplicated for selection; search covers queue names, tag names, work titles, and authors.
- **States/F/G:** all content is local (no signed-out/loading requirement); row accessibility includes work/tag/storage summaries; iOS hides the tab bar during selection and macOS places selection actions in the primary toolbar. Findings 18, 24–29, and 35 cover remaining verified gaps.

### `1j` — New Queue

- Name, stored/fallback colour, shared tag vocabulary, Keep Works Offline, and Empty/Saved for Later seed are all real persisted choices. Creation is disabled for a whitespace-only name; Saved for Later is disabled at zero and exposes its live count to VoiceOver.
- The sheet wash, tint, selected tag, radio, toggle, and confirmation control follow the chosen queue palette. It uses a scrollable List, large iOS detent, and native text field/toggle/radio behavior for keyboard and Dynamic Type resilience.
- Findings 15, 28, and 30–32 cover the verified visual/copy/accessibility differences.

### `1bg` — queue select mode

- Selected rows keep their queue positions; select and reorder coexist; narrowing filters correctly disable drag; list mode uses SwiftUI move handles and grid mode uses the shared explicit handle; VoiceOver gets four move actions.
- Download, Move to, Tag, and Remove are all wired; Remove confirms and states that works remain in Library. The app tab bar is hidden while the selection bar owns the bottom safe area.
- Findings 2, 4, and 10–12 cover the verified broken/mismatched selection state and chrome.

### `1bh` — tag manager + edit sheet

- Tags are split into used/unused groups; used tags sort by in-queue work count; unused tags are retained; per-row counts and VoiceOver values are queue-scoped.
- New tag creation deduplicates through the shared `Tag` vocabulary. Edit Tag implements case-insensitive rename conflict detection, global rename warning, per-sibling merge counts, merge confirmation with affected count/undo warning, and destructive removal confirmation.
- Shared-queue author/collaborator attribution is intentionally absent and was not reported: the codebase has no shared queues, so fabricating “you” on every row would be false. Finding 33 covers the non-collaboration actions that are still missing.

## Three findings that matter most to the owner

1. **batch-3-1:** Hide Mature is visually offered but not applied to queue contents, so a privacy setting is broken on every queue layout.
2. **batch-3-2:** Move to leaves selection mode in a stale “N selected” state after the selected works have disappeared.
3. **batch-3-22:** Queue Details is structurally a different screen from 1h.3/1h.4 (order, panels, labels, duplicated facts), making the most visible queue settings surface feel unrelated to its approved artboard.
