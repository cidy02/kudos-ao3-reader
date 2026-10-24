# Duo3 — iOS layout audit for iPhone Duo

Status: complete read-only source audit, 2026-10-24. Source: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` at `d3e660779647ed33f91ccad015efea7ee7693b62` (HEAD verified). This audit writes only this report; it makes no source, task-board or Git changes. Concurrent source-worktree edits appeared during the audit; quoted finding files were compared with `git show d3e66077:<path>` and matched the pinned versions. Other agents' edits were left alone.

Device behavior and dimensions are the supplied Duo2 brief/task assumptions: cover 466×678 pt; inner portrait 669×951 pt; inner landscape 951×669 pt, regular/regular; Book pose has a roughly 40 pt central reserved division. System bars can move to the side. No SDK/device claims are independently re-verified in this source audit.

Evidence standard: source deductions are predictions until Claude verifies them on the Duo simulator. The supplied Home screenshot is separate visual evidence. P1 = broken/unreadable; P2 = clearly wrong; P3 = polish. Line numbers refer to the pinned source, with paths relative to `kudos-ao3-reader/` unless stated otherwise.

The source tree has no local `READIUM_MIGRATION_NOTES.md`; this audit will trace the current reader code directly. No build, network call, branch change, commit or push is part of this task.

## Findings

### 1. Home queue shelf paints beneath the vertical tab rail — P2

**States:** cover (visually confirmed in the supplied screenshot); inner landscape with a side rail (predicted).

`Features/Home/HomeView.swift:454–460`: `private var readingQueuesCarousel: some View { ... return WorkCarouselSection(`. The shared implementation at `UIComponents/WorkCarouselSection.swift:93–101` is:

```swift
ScrollView(.horizontal, showsIndicators: false) {
    HStack(alignment: .top, spacing: 12) { cards() }
        .uniformWorkCardHeights()
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
}
.scrollClipDisabled()
```

The screenshot `/Users/cidy02/kudos-tools/out/duo/duo-home-light-s1.png` shows the third queue deck behind the Search end of the right tab rail. Fixed content padding does not bound out-of-viewport painting when clipping is disabled. This is also shared by other work/collection shelves; the Continue Reading strip separately repeats `.scrollClipDisabled()` at `Features/Home/HomeView.swift:442`. The screenshot proves overlap, not that the last card can never be scrolled clear.

**Smallest fix:** constrain each shelf to its container's usable horizontal region and clip horizontal overflow there; preserve shadow room vertically. Use actual safe-area/bar geometry for leading/trailing scroll content margins so the final card can settle entirely clear of the rail. Verify the shared shelf and the separate Continue Reading strip together; do not add a guessed fixed rail width.

### 2. Screen-based card clamp exceeds the usable pane — P2

**States:** cover with side rail at large text; inner portrait/landscape in narrow panes; Book pose after splitting around the fold.

`UIComponents/CarouselCardStyle.swift:80–98`:

```swift
private var maxWidth: CGFloat {
    #if os(iOS)
    UIScreen.main.bounds.width - 32
    // ...
}
private var clampRatio: CGFloat { min(1, maxWidth / scaledWidth) }
var width: CGFloat { scaledWidth * clampRatio }
```

Cards pin their own width (`Features/Library/ReadingQueues.swift:62`: `.frame(width: cardSize.width, alignment: .leading)`). At accessibility sizes, the clamp uses the whole display even when a side bar, queue sidebar or fold leaves a much narrower content pane. Adaptive grids cannot shrink a card that has already pinned itself wider than their available width. The 164 pt baseline and paper aspect ratio are not themselves defects.

**Smallest fix:** pass the measured usable container/pane width to the shared sizing helper and clamp against that, preserving proportional scaling and the existing adaptive grid.

### 3. Two-page reading exists but is explicitly unavailable on Duo — P2; P1 reading risk in Book pose

**States:** inner landscape (single page regardless of available spread space); Book pose (text can cross the division); inner portrait still excludes the option regardless of available width.

`Settings/SettingsView.swift:103–111,128–130`:

```swift
@AppStorage("readerTwoPage") private var twoPageEnabled = false
private var twoPageSpreadAvailable: Bool {
    #if os(iOS)
    return UIDevice.current.userInterfaceIdiom != .phone
    // ...
}
if twoPageSpreadAvailable {
    Toggle("Two-page spread", isOn: $twoPageEnabled)
        .disabled(readingMode != .paged || !twoPageAvailable)
}
```

`Features/ReaderReadium/ReadiumReaderView.swift:1435–1436,1469–1477`:

```swift
private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
// in ReadiumReaderStyleMapper.preferences(...):
columnCount: (twoPageEnabled && !isPhone) ? .auto : .one
```

`Features/ReaderReadium/ReadiumReaderStyleMapper.swift:25,39,43`:

```swift
columnCount: readingMode == .scroll ? nil : columnCount,
pageMargins: max(0, style.margin),
scroll: readingMode == .scroll,
```

**Answer:** yes, Readium's `EPUBPreferences.columnCount` is wired, with `.auto` for enabled non-phone paged reading, `.one` for phone paged reading, and nil in scroll mode. Duo remains a phone in this policy, so enabling the stored setting elsewhere still cannot yield a spread. The iOS options presenter calls `ReaderOptionsForm()` (`ReadiumReaderView.swift:1667`), leaving its `twoPageAvailable` default true (`SettingsView.swift:18`); no reader width is passed there today. No app-owned reserved-region handling was found. A single text flow can pass through the Book division; simply changing `.one` to `.auto` does not establish that Readium leaves the actual fold band empty. Exact line length depends on Readium CSS defaults as well as these preferences; this audit does not assert that prose necessarily fills all 951 pt.

**Smallest fix:** replace both idiom gates with available reading width and expose the existing preference on wide Duo windows. In Book pose, align the page gutter with the measured reserved division and verify the actual Readium web layout; preserve normal continuous scroll behavior outside that pose. Spread support and fold clearance must be tested separately.

### 4. Filters always use the phone sheet policy — P3

**States:** inner portrait and inner landscape.

`UIComponents/FilterPanelPresentation.swift:37–47`:

```swift
if UIDevice.current.userInterfaceIdiom == .phone {
    content.sheet(isPresented: $isPresented) {
        panel()
            .presentationDragIndicator(.visible)
            .presentationDetents(detents ?? [.large])
    }
} else {
    content.inspector(isPresented: $isPresented) { panel() }
}
```

This is the third layout idiom gate (the other two are in finding 3). A wide Duo still overlays/dismisses results to filter them while iPad uses a simultaneous side inspector. It is a missed wide-layout opportunity, not proof that the system sheet is broken. The file's `:6–28` comments document a real compact inspector/navigation-destination failure, so a blanket swap to inspectors risks reviving it.

**Smallest fix:** retain a real sheet when the available content width cannot support both results and an inspector; use the inspector only when it can, with a navigation-destination regression check. Keep native sheets for their built-in fold adaptation.

### 5. The regular queue browser is a fixed custom split, not a fold-aware split view — P2

**States:** inner portrait, inner landscape; Book pose is the strongest failure case.

`Features/Library/ReadingQueueBrowser.swift:295–299,397–428`:

```swift
if horizontalSizeClass == .regular { regularLayout } else { compactLayout }
// regularLayout:
HStack(spacing: 0) {
    List { /* queues and New Queue */ }
        .listStyle(.sidebar)
        .frame(width: 240)
        .disabled(isSelecting || isReordering)
    Divider()
    pageContent
}
.toolbar(.hidden, for: .tabBar)
```

The regular branch really does run on the inner phone display. In portrait, 669 − 240 = 429 pt remain before dividers/margins; regular does not guarantee a roomy detail pane. In full landscape, a 240 pt sidebar places the middle of the display inside `pageContent`, rather than at the split divider: content can straddle the reserved fold. This HStack gets none of the supplied framework split-view fold behavior. It also unconditionally removes the global tab rail; the queue list is not a replacement for Home/Library/Browse/Account navigation. Back still exists, so this is not a navigation trap.

**Smallest fix:** use a framework split container with a collapsible queue column and measured minimum detail width. Let its division avoid the fold, and retain global tab access when space allows. Test the 669 pt portrait pane and select/reorder modes, not just 951 pt landscape.

### 6. Account accessibility fallback only protects compact width — P2, conditional on large text

**States:** inner portrait and narrower regular panes; Book pose if the grid is assigned one half. At default text size this is not an established defect.

`Features/Account/AccountView.swift:626–628`:

```swift
let isCramped = dynamicTypeSize.isAccessibilitySize && horizontalSizeClass == .compact
return Array(repeating: GridItem(.flexible(), spacing: 10), count: isCramped ? 2 : 3)
```

`Features/Account/AccountComponents.swift:496–507`:

```swift
Text(title)
    .font(.system(size: titleSize, weight: .medium))
    .lineLimit(title.contains(where: \.isWhitespace) ? 2 : 1)
    .minimumScaleFactor(title.contains(where: \.isWhitespace) ? 0.8 : 0.5)
// ...
.padding(8)
.frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
```

The regular/regular inner display always retains three columns, including at AX5. In a narrow regular pane, a long one-word label such as Subscriptions must shrink toward half the requested font size instead of reducing columns. Regular width alone does not establish that three scaled tiles fit. On the unsplit inner portrait display there is more room than on cover, so confirm the actual shrink before calling that whole-display state broken.

**Smallest fix:** derive column count from actual grid width and a minimum tile width that tracks text size, using the existing adaptive-grid pattern. This and finding 5 are the relevant compact/regular branches; there is no hidden app-wide tablet layout switch to enable.

### 7. Full-bleed reader drops horizontal safe areas — P2; P1 if controls/text meet an occupied edge

**States:** cover with side status/control exclusion; inner landscape with lateral exclusions; Book pose requires additional interior clearance (finding 3).

`Features/ReaderReadium/ReaderDismissDrag.swift:176–183`:

```swift
host.safeAreaRegions = []
host.view.frame = view.bounds
host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
```

`Features/ReaderReadium/ReadiumReaderView.swift:990,1003,1021–1022,1074–1075`:

```swift
.ignoresSafeArea()
// top bar:
.padding(.top, book.pageBoxChromeSafeTop)
// fan:
.padding(.trailing, ReaderChromeTopBar.edgeInset)
.padding(.top, book.pageBoxChromeSafeTop)
// bottom controls:
.padding(.horizontal, Self.chromeInset)
.padding(.bottom, book.pageBoxChromeSafeBottom + Self.chromeInset)
```

`Features/ReaderReadium/ReadiumBook.swift:1234`:

```swift
return UIEdgeInsets(top: insets.top, left: 0, bottom: insets.bottom, right: 0)
```

The code explicitly replaces inherited safe areas with vertical-only values. Top-bar edge padding is just 16 pt (`ReaderChromeTopBar.swift:21,61`), and Readium's horizontal text gutters are the user margin, not the window's safe sides. Controls or ink can therefore occupy a lateral reserved edge. The app tab bar is hidden in the reader; this is not evidence that its mini-player collides with a visible tab bar. Native navigation bars cannot rescue custom reader overlays.

**Smallest fix:** keep the page background full-bleed, but obtain all four safe insets from the hosting reader window and apply lateral clearance to content and controls. Preserve the existing vertical no-jump behavior deliberately. Fold avoidance needs a separate interior region, not inflated left/right padding alone.

### 8. Reader chrome centers critical content directly on the Book fold — P1

**States:** Book pose; inner landscape without a fold is mainly a P3 over-wide-control issue.

`Features/ReaderReadium/ReaderChromeTopBar.swift:45–49`:

```swift
Spacer(minLength: 0)
if !titleHidden { titlePill }
Spacer(minLength: 0)
```

`Features/ReaderReadium/ReadiumReaderView.swift:973–977,1064–1075`:

```swift
.overlay(alignment: .top) { topBarLayer }
.overlay(alignment: .bottom) { bottomChromeLayer }
// bottomChromeLayer:
VStack(spacing: 10) {
    if chromeVisible {
        highlightColorBar
        positionCard(includeMiniPlayer: speechActive)
    } else if speechActive { standaloneMiniPlayer }
}
.padding(.horizontal, Self.chromeInset)
.padding(.bottom, book.pageBoxChromeSafeBottom + Self.chromeInset)
```

`Features/ReaderReadium/ReaderPositionCard.swift:130–140` puts `scrubSlider` across the card and uses `.frame(maxWidth: .infinity, alignment: .center)` / `.multilineTextAlignment(.center)` for `Text(workLine)`. The TTS transport is centered in a full-width ZStack (`ReaderSpeechController.swift:862–872`), including:

```swift
Button { controller.toggle(from: nil) } label: {
    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
        .frame(width: Self.hitSize, height: Self.hitSize)
}
```

The title, work-position text, middle of the seek track and play/pause are aligned to the screen center, exactly where the Book division lies. The 44 pt transport hit target (`ReaderSpeechController.swift:854,891`) is approximately the supplied fold band's width. A two-page EPUB change alone leaves these controls in the division. In regular landscape the card also stretches nearly 951 pt wide, separating labels and stretching the slider more than necessary.

**Smallest fix:** constrain the position card and mini-player to one usable pane, with the title pill in a usable pane too; keep their existing button targets and all actions. Route seek gestures entirely within that pane. Test chrome up/down, paused/playing speech and highlight colors in Book pose.

### 9. Reader seeds from screen height and freezes on height alone — P2 transition risk

**States:** cover ↔ inner landscape transitions; resize/hinge changes that alter width or exclusions without a significant height change.

`Features/ReaderReadium/ReadiumBook.swift:201–206`:

```swift
let safe = Self.liveWindowSafeArea
let height = UIScreen.main.bounds.height
refreshFrozenPageBoxGeometry(viewHeight: height, safeTop: safe.top, safeBottom: safe.bottom)
```

`:1243–1255`:

```swift
let heightChanged = frozenPageBoxViewHeight <= 1
    || abs(viewHeight - frozenPageBoxViewHeight) > 1
if heightChanged {
    frozenPageBoxViewHeight = viewHeight
    frozenPageBoxSafeTop = max(0, safeTop)
    frozenPageBoxSafeBottom = max(0, safeBottom)
    return
}
if frozenPageBoxSafeTop == 0, safeTop > 0 { frozenPageBoxSafeTop = safeTop }
if frozenPageBoxSafeBottom == 0, safeBottom > 0 { frozenPageBoxSafeBottom = safeBottom }
```

The initial height is not the actual host's height. Later queries do use `view?.bounds.height` (`:1205–1214`), which can correct that seed: this is not evidence of permanent screen-sized pagination. But width, side insets and reserved regions are absent from the freeze key; same-height nonzero inset changes are intentionally ignored. Cover and inner landscape heights are close (678 vs 669), and an ordinary transition between those exact heights should refresh; do not mistake "close" for equal. A same-height exclusion/hinge change remains unsupported.

**Smallest fix:** seed from the actual hosting window/view and invalidate layout on meaningful host-size or reserved-region changes, while retaining the separate protection against chrome-only status-bar toggles. Trigger inset refresh and visual-page remeasurement after that layout settles, retaining the current locator.

**Pagination follow-through:** `ReadiumBook.swift:795–808` measures actual web viewport dimensions (`var vw = Math.max(1, window.innerWidth || 1)`; `pageCount = Math.max(1, Math.round(scrollW / vw))`), not a portrait constant. However `:835–846` requires one web view to cover ≥55% of the root:

```swift
let rootArea = max(1, rootBounds.width * rootBounds.height)
guard visibleArea >= rootArea * 0.55 else { return nil }
```

If a fold fix uses two separate half-width web views, neither can pass; the page bar can stay unready. This is a **conditional P2 constraint on that implementation**, not a demonstrated defect in the current one-web-view spread. Keep Readium's existing spread if it can represent the real gutter; otherwise adapt sampling to the new viewport ownership. Recheck swipe-page vs spread semantics, seek and resume after opening/folding.

### 10. Home hero, subject headers and stat strips have no content division — P2

**States:** Book pose; inner landscape also expands a phone-shaped one-column page.

`Features/Home/HomeResumeHero.swift:167–189`:

```swift
VStack(alignment: .leading, spacing: 12) {
    // fandom, title, metadata
    metadataLine
    resumeRow
}
.padding(.horizontal, 18)
.frame(maxWidth: .infinity, alignment: .topLeading)
```

`:251–259` selects the hero's row/stack only from Dynamic Type:

```swift
let layout = dynamicTypeSize.isAccessibilitySize
    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
    : AnyLayout(HStackLayout(spacing: 16))
```

Home inserts this hero with just `.padding(.horizontal, 16)` (`HomeView.swift:392–400`). A long title/metadata can run across the Book division; the progress/place/Resume row has no relationship to the fold. Horizontal queue decks are individually small (`ReadingQueues.swift:71–88`: `let width = 148 * scale`, `let height = 88 * scale`, offsets `16 * scale` / `8 * scale`, outer height `96 * scale`), so their proportions are not the cause. Their **shelf placement** can leave one resting across the division.

Shared headers also fill their offered width (`UIComponents/SubjectSurface.swift:555`: `.frame(maxWidth: .infinity, alignment: .leading)`). `SubjectStatStripContent` lays out custom cells in an uninterrupted row at `:860–869`:

```swift
HStack(spacing: 0) {
    ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
        // hairline and cellBody(cell)
    }
}
```

An even cell count might put a hairline near the fold by accident; there is no reserved 40 pt gutter, and odd counts can put a cell there. A wide static custom strip is not automatically a system split view.

**Smallest fix:** assign whole semantic blocks to usable panes: hero/identity on one side and next-up/details on the other where space permits, while retaining metadata density. Apply fold clearance to shared headers/stat strips within their pane. For horizontal carousels, decide resting/snap positions from usable regions; continuous orthogonal scrolling across the fold need not be prohibited. Do not stretch or enlarge the 164 pt cards to fill 951 pt.

### 11. Long prose and the writing editor can span the division — P1 where text crosses it

**States:** Book pose; inner landscape without a fold has over-long lines (P2).

`Features/WorkDetail/WorkDetailOverviewSections.swift:50–69`:

```swift
VStack(alignment: .leading, spacing: 10) {
    Text(summary)
        .font(.system(size: summarySize, design: .serif))
        .lineSpacing(5.5)
        .fixedSize(horizontal: false, vertical: true)
        .lineLimit(collapses && !summaryExpanded ? 8 : nil)
    // Show More/Less
}
.pageBodyRow(top: 20)
```

`Features/Writing/WritingTextEditor.swift:92–101`:

```swift
ZStack {
    if let controller {
        WritingNativeTextView(controller: controller)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // opacity/accessibility/hit-testing for Preview
    } else { ProgressView().accentFill() }
    if isPreviewing { preview }
}
```

These are continuous text surfaces without an app-level fold division. Outer system safe areas cannot represent an interior gap. A summary can have a sentence through the fold; the editor can put text/caret there. This audit does not establish that every native text control ignores new framework behavior; verify its actual wrapping before patching text internals. A readable pane allocation fixes both without changing document content or its model.

**Smallest fix:** constrain prose to a readable usable pane in Book pose; use the other pane for related facts or preview when appropriate. For the writing editor, first contain the existing editor and keep its buffer/selection/undo implementation; do not implement a second text engine solely for Duo.

### 12. Root download banner overlays the bottom of the whole tab container — P2

**States:** cover and inner landscape with side bars; Book pose; inner portrait also retains the existing overlay-obscures-content risk.

`App/ContentView.swift:60`:

```swift
.overlay(alignment: .bottom) { DownloadQueueBanner() }
```

`Services/DownloadQueue.swift:198–219`:

```swift
HStack(spacing: 12) {
    ProgressView().accentFill()
    VStack(alignment: .leading, spacing: 2) { /* count, currentTitle */ }
    Spacer(minLength: 8)
    Button("Cancel") { queue.cancel() }
}
.padding(.horizontal, 16)
.padding(.vertical, 10)
.glassEffect(.regular, in: .capsule)
.padding(.horizontal)
.padding(.bottom, 8)
.transition(.move(edge: .bottom).combined(with: .opacity))
```

This overlay is attached **outside** the tabs rather than to the selected tab's usable content, and reserves no space in it. It neither knows which edge the tab/toolbar occupies nor avoids the interior division; the final content row can be covered and Cancel can meet the side rail. It is not an "above a 49 pt tab bar" formula—none was found here. The observed queue-row overlap is finding 1, not caused by this inactive banner.

**Smallest fix:** host the banner within the active content's usable region and reserve its actual occupied space with a safe-area inset (or a suitable system scene accessory). On Book pose, constrain it to one pane. Verify Cancel reachability while the side bar is visible.

### 13. Bulk toolbar custom content assumes a horizontal capsule — P2 risk requiring simulator confirmation

**States:** cover and inner landscape when the system relocates toolbars vertically; inner portrait is the control case.

`Features/Home/HomeView.swift:260–263` hosts `WorkBulkActionBar(...)` in `ToolbarItemGroup(placement: .bottomBar)`. The shared view at `UIComponents/WorkBulkActionBar.swift:44–54,102–118` includes:

```swift
Button(role: .destructive) { confirmDelete = true } label: {
    Label("Delete", systemImage: "trash")
}
Spacer()
Menu { /* actions */ } label: {
    Text("Actions")
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
}
Spacer()
Button { onDone() } label: { Image(systemName: "checkmark") }
```

The system can adapt the toolbar group, so `.bottomBar` alone is **not** a bug. The custom text-only Actions pill and spacing are the suspect part: its intrinsic width can be wider than a vertical rail. The own-works variant is more exposed (`Features/Authors/OwnWorksBulkBar.swift:14–20,98`): `Button("Edit …")`, `Spacer()`, `Button("Collections")`, `Spacer()`, `Button("Visibility")`, `Spacer()`, `Button("Delete", role: .destructive, action: delete)` under `.bottomBar`. These supply wide text-only items rather than compact symbol labels.

**Smallest fix:** let the platform arrange individual semantic toolbar items; give Actions and text-only bulk actions symbol-backed labels with accessibility names, and select compact presentation from the actual vertical-toolbar environment when needed. Keep confirmations and all operations. Check overflow/reachability before replacing every `.bottomBar` caller—framework-managed buttons may already adapt correctly.

### 14. Wide custom fields embedded in toolbar principal slots — P2 risk requiring simulator confirmation

**States:** cover and inner landscape if that principal slot is moved/compressed into a vertical bar; Book pose if a wide principal field is centered across the division.

`UIComponents/GlassFieldBar.swift:16–32`:

```swift
HStack(spacing: 6) {
    leading()
    TextField(placeholder, text: $text)
    trailing()
}
.padding(.horizontal, 12)
.padding(.vertical, 6)
.frame(minWidth: 220, idealWidth: 480, maxWidth: 680)
```

`Features/Browse/BrowseView.swift:70–72` places `addressField` in `ToolbarItem(placement: .principal)`, and `:91–96` builds it with this helper. Search has the same active host (`Features/Search/SearchView.swift:223`: `ToolbarItem(placement: .principal) { searchField }`, built with `GlassFieldBar` at `:614`). A 220 pt minimum cannot fit a narrow vertical rail. SwiftUI might keep/rehome the principal item rather than attempting that fit, so the exact failure is unconfirmed. The shared field's use in `Features/Writing/WritingTagsEditor.swift:163` is in content, not itself proof of a bar bug.

**Smallest fix:** in vertical-bar layouts, place the browser address entry in a content safe-area row or use a compact toolbar action that opens the field; keep ordinary horizontal presentation where it fits. Size the field to its actual container rather than preserving a 220 pt minimum in every context.

### 15. A fixed bottom tab-bar allowance survives in an unused scaffold — P3, latent only

**States:** cover/inner landscape if this scaffold is adopted; inner portrait also receives the unconditional gap.

`UIComponents/SubjectScreen.swift:50–53`:

```swift
.frame(maxWidth: .infinity, alignment: .leading)
// The floating tab bar overlaps the last rows otherwise ...
.padding(.bottom, 110)
```

The same scaffold's chrome calls `.hidesFloatingTabBar()` (`:92`). Repository search found the declaration and extension, but **no construction call sites** for `SubjectScreenScaffold`. This is therefore not evidence that forty current screens have a 110 pt gap. If reused, it wastes vertical space for a bar that may be on the side or hidden.

**Smallest fix:** remove the fixed allowance when this scaffold is used and reserve actual visible accessory space at its real edge. No urgent source change is justified for an unused helper by this audit alone.

### 16. Reader visual-page count has no explicit resize invalidation — P2

**States:** cover ↔ inner display, inner portrait ↔ landscape, Book pose layout changes during the same chapter.

`Features/ReaderReadium/ReadiumBook.swift:692–704`:

```swift
if previousHref != newHref {
    clearVisualPageMetrics()
    schedulePageBarRemeasure()
} else if pageBarReady, !isScrubbing {
    scheduleSettledPageDigitRefresh()
}
```

That same-resource refresh reaches `:874–877`:

```swift
if digitOnly {
    guard pageBarReady, let known = visualPageCount, known == best.pageCount else { return }
    publishPageBar(page: best.page, pageCount: known, allowShrink: false)
    return
}
```

The injected script registers touch/pointer arming (`:1111–1112`) and `window.addEventListener('scroll', reportFromScroll, { passive: true })` (`:1168`); it has no resize listener. The app resets the count after preference changes (`ReadiumReaderView.swift:879–887`: `book.clearVisualPageMetrics()` / `book.schedulePageBarRemeasure()`), opening, or a changed chapter href, but has no corresponding host-size/hinge observer. A display transition can reflow the **same chapter** to a new count; a normal Readium location callback alone then selects digit-only refresh, rejects the changed count, and leaves the old denominator/seek scale. Touch scrolling may later yield a fresh sample, so this is a transition-staleness risk, not proof of permanent corruption or saved-progress loss.

**Smallest fix:** on a settled reader viewport or reserved-region change, retain the locator and run the existing clear + scheduled remeasurement path. Reuse the existing dual-agreement guard; do not replace it with an immediate guessed count. Verify both increased and decreased page counts without changing chapters or settings.

## Coverage and exclusions

- **All layout idiom checks:** the two spread gates (finding 3) and shared filter presenter (finding 4). No model-name string selects a layout. `Features/Support/BugReportView.swift:173` uses `UIDevice.current.systemName` / `.systemVersion` only for diagnostics, and `:183` uses `utsname()` for a bug-report identifier; these are not layout defects.
- **All direct screen reads:** card max width (finding 2) and reader seed height (finding 9). `UIScreenEdgePanGestureRecognizer` in `UIComponents/EdgeSwipeBack.swift:46` is a gesture recognizer, not a screen-bounds read.
- **Size-class branches:** Account's `horizontalSizeClass == .compact` is finding 6; queue browser's `.regular` layout is finding 5. The queue browser's other `.regular` test at `ReadingQueueBrowser.swift:280–284` is inside `#if os(macOS)` and only chooses a title. `WorkListDisplayMode.compact` means compact **cards**, not a device size class. There is no vertical-size-class layout branch in the app source.
- **GeometryReader math:** no direct portrait-width/height assumption was found in these uses. `Features/Home/HomeCards.swift:388–392` reports `geometry.size.height` for equal card heights. `Features/Search/FilterRangeSlider.swift:42–46` uses `let width = max(geo.size.width, 1)` for its own track. `Features/ReaderReadium/ReaderPositionCard.swift:224–230` uses `geo.size.width` for the origin tick; the containing full-width slider's fold placement is finding 8. `Features/Library/ReadingInsightsView.swift:248–249,310` scales chart bars to `proxy.size.height` / `proxy.size.width`; its custom chart still belongs in a usable pane in Book pose. The fandom index uses its own height (`Features/Search/FandomListView.swift:297`: `let rowHeight = geometry.size.height / CGFloat(Self.indexLetters.count)`), not a screen/portrait ratio.
- **Reader loading state, P3 extension of finding 7:** `UIComponents/SkeletonLoading.swift:322,339,356` takes only `(safeTop, safeBottom)`, uses `.padding(.horizontal, 28)`, and returns `(insets.top, insets.bottom)` from the window. Thus its loading bars can cross the same side exclusions/fold even before prose paints. Smallest fix: give it the same pane and complete safe-region inputs as the real reader; its `proxy.size.height` fill calculation is otherwise size-based.
- **Legacy reader is not Duo's reader:** `Features/ReaderReadium/ReadiumReaderView.swift:26–31` routes `#if os(iOS)` to `ReadiumReaderView(work: work)` and `#else` to `ReaderView(work: work)`. `Features/Reader/ReaderView.swift:8` and `ReaderController.swift:6` are guarded by `#if os(macOS)`. The legacy width measurement (`ReaderView.swift:237–239`: `availableWidth = width`) and its wide-window spread cannot rescue the iPhone reader. Shared reader settings remain relevant (finding 3).
- **Native sheets are not custom overlays:** reader panels use `NavigationStack` and `.presentationDetents([.medium, .large])` (`ReadiumReaderView.swift:1670–1683`); My copy uses `NavigationStack` plus a top safe-area inset (`Features/WorkDetail/WorkDetailView.swift:400–408`). Under the supplied platform contract these presentations get framework fold avoidance; no extra custom sheet position arithmetic was found there. The explicit login minimum (`Features/Auth/AO3LoginView.swift:77`: `.frame(minWidth: 360, minHeight: 440)`) merits a keyboard smoke check on cover, but 360×440 fits the supplied full display before keyboard/bar constraints; static evidence alone does not establish a Duo defect.
- **Bottom is sometimes intentional:** the comment formatter uses `.safeAreaInset(edge: .bottom, spacing: 0)` to sit above the keyboard (`Features/Comments/CommentsView.swift:1391–1397`), and the writing editor places `tagBar` after its editor (`WritingTextEditor.swift:113–115`). These are keyboard relationships, not offsets derived from a bottom tab bar. Do not move them to a side just because native toolbars move. No fixed 49/83 pt tab-bar compensation or app-wide floating action button above a tab bar was found. The fixed 110 pt scaffold allowance is explicitly separated as latent (finding 15).
- **No app-level Duo APIs:** the pinned app source has no `ReservedRegion`, `reservedRegions`, `onHingeChange`, `DeviceHingeContext`, `UIHinge`, `toolbarVerticalEdge` or `verticalBarEdge` usage. This proves absence of app-owned accommodation, not absence of adaptations inside SwiftUI/UIKit/Readium dependencies. Background washes such as `UIComponents/HeroWash.swift:22` (`.frame(height: 380)`) can safely span the fold as decoration; content is what needs division.

## Verification handoff

This was static inspection plus viewing the supplied Home PNG. No build, simulator interaction, test run, AO3 request, sign-in, source edit, task-board edit, branch switch, commit or push was performed. The missing local migration notes and runtime behavior of the pinned Readium/framework dependencies were not independently resolved. All P1s are predicted Book-pose/lateral-exclusion failures, not observed device failures.

Claude's minimum visual pass: cover Home with 3+ queues (scroll to the last one), then Home/queue browser at both inner sizes; AX5 Account and grids; Book pose Home hero, queue detail, summary and editor; reader scroll/paged with chrome up/down and speech; fold/unfold and rotate mid-chapter while checking page count, slider and resume; selection bars and Search/browser fields with side controls; active download Cancel; native sheets plus keyboard. Use existing local/demo content so this pass need not contact AO3.

## Highest-impact changes, in order

1. **Give shared content the actual usable container width and side clearance.** Fix horizontal shelf clipping/margins and the shared card clamp first (findings 1–2), then root download placement and compact bar content (12–14). This directly addresses the screenshot-confirmed cover failure and benefits most card surfaces without changing their density.
2. **Finish the existing Readium spread path for wide phone windows.** Remove both idiom exclusions, feed real host geometry, align the reading gutter to the actual reserved division, and invalidate page metrics on viewport/region changes (3, 7, 9, 16). Verify one-/two-page and scroll behavior at both inner sizes; do not assume `.auto` alone avoids the fold.
3. **Move reader chrome into usable panes.** Keep title, seek card and TTS play/pause out of the Book division and clear lateral exclusions (7–8); share those geometry inputs with the loading skeleton. This addresses the highest-severity control/readability risks while retaining the existing reader controls.
4. **Use real adaptive panes for the inner app.** Replace the queue browser's fixed HStack with a framework split, allocate Home hero/subject prose/editor blocks around the division, and derive grids/filter presentation from available width (4–6, 10–11). Prefer existing components within those panes; retain metadata and global navigation access.
