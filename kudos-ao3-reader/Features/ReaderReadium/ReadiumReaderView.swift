import OSLog
import SwiftData
import SwiftUI
#if os(iOS)
import QuickLook
import ReadiumNavigator
import ReadiumShared
import UIKit
import WebKit
#endif

/// Platform router for the book reader. iOS/iPadOS use the new Readium navigator;
/// macOS keeps the legacy WKWebView reader, because Readium's navigator is a
/// `UIViewController` (UIKit) and has no AppKit/`NSViewController` form — see the
/// macOS note in the Phase 2 summary. Both call sites use this so the choice is
/// made in one place.
struct BookReaderView: View {
    let work: SavedWork

    var body: some View {
        #if os(iOS)
        ReadiumReaderView(work: work)
        #else
        ReaderView(work: work)
        #endif
    }
}

/// Full-bleed page skeleton on a solid reader-theme fill — used by the open
/// path and as a cover over Readium until the first spread paints.
///
/// Background is `SwiftUI.Color` explicitly: this file also imports
/// `ReadiumNavigator`, which defines its own `Color` type.
private struct ReaderPageSkeletonFill: View {
    let background: SwiftUI.Color

    var body: some View {
        ReaderPageSkeleton()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background)
    }
}

#if os(iOS)

/// The Readium-backed reader screen. Mirrors the legacy `ReaderView`'s chrome
/// (immersive page, tap-to-toggle bars, Chapters / Display sheets) but renders
/// with `EPUBNavigatorViewController` and drives Readium's `EPUBPreferences` from
/// the app's existing reader settings + `ThemeManager`.
struct ReadiumReaderView: View {
    @Bindable var work: SavedWork

    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AO3AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \CustomFont.dateAdded) private var customFonts: [CustomFont]
    /// Every annotation in the store; narrowed to this work by `annotations`.
    /// A `#Predicate` can't compare an optional relationship's id, so the filter
    /// is done in Swift — the list is small (per-reader marks, not the library).
    @Query(sort: \ReadingAnnotation.progression) private var allAnnotations: [ReadingAnnotation]
    @AppStorage("readerMode") private var readingMode: ReadingMode = .scroll
    @AppStorage("readerTwoPage") private var twoPageEnabled = false
    @AppStorage("readerFontID") private var fontID: String = "system"
    // Apple Books–style typography; layout options are gated by `customizeEnabled`
    // (mirrored from the legacy reader via `ReaderTextStyle.resolved`).
    @AppStorage("readerCustomize") private var customizeEnabled = false
    @AppStorage("readerBoldText") private var boldText = false
    @AppStorage("readerFontPt") private var fontSizePt: Double = ReaderTextStyle.defaultFontSizePt
    @AppStorage("readerLineHeight") private var lineHeight: Double = ReaderTextStyle.defaultLineHeight
    @AppStorage("readerLetterSpacing") private var letterSpacing: Double = 0
    @AppStorage("readerWordSpacing") private var wordSpacing: Double = 0
    @AppStorage("readerMargin") private var pageMargin: Double = ReaderTextStyle.defaultMargin
    @AppStorage("readerJustify") private var justifyText = false
    /// Voice id only — rate/pitch are read live from UserDefaults per utterance.
    @AppStorage(ReaderSpeechPreferences.voiceIDKey) private var speechVoiceID = ""

    /// The reader-scoped rotation lock. Shared (not per-view) because iOS asks
    /// the app delegate, not this view, which orientations are supported.
    private var orientationLock: ReaderOrientationLock { .shared }

    @State private var book = ReadiumBook()
    /// Debounces SwiftData writes for the Readium locator stream (see
    /// `ReadiumProgressPersistence`). UI locator / progress pill stay live.
    @State private var progressPersistence = ReadiumProgressPersistence()
    /// Native comments sheet over the reader (only for AO3-backed works).
    @State private var showingComments = false
    /// Non-nil while the archived original is being previewed by QuickLook.
    @State private var previewingOriginal: URL?
    @State private var rebuildError: String?

    /// The afterword's own AO3 boilerplate — "Please drop by the Archive and
    /// comment…" — links straight at `/works/<id>/comments/new`, which this
    /// work's native comments sheet already covers. Opens that instead of the
    /// AO3 web form when the URL is for *this* work.
    ///
    /// The link itself is untouched (nothing removed from the EPUB) and every
    /// other URL — including this same link for a different work, or if this
    /// check simply doesn't match — still falls through to the normal
    /// `router.openAO3Link` path below, so the original in-app-browser fallback
    /// is never lost.
    private func openCommentsLinkIfMatching(_ url: URL) -> Bool {
        guard let ao3WorkID, (url.host ?? "").contains("archiveofourown.org") else { return false }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 3, parts[0] == "works", Int(parts[1]) == ao3WorkID, parts[2] == "comments"
        else { return false }
        showingComments = true
        return true
    }

    private var ao3WorkID: Int? {
        work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL)
    }
    /// UIKit peel surface — interactive samples never touch SwiftUI state.
    @State private var dismissSurface = ReaderDismissDragSurface()
    @State private var isDismissingByDrag = false

    // MARK: Chrome state

    /// One inset for every floating chrome layer. The back button, the fan
    /// button, and the position card all sit exactly this far from the screen
    /// edge — previously the top bar double-padded (layer + its own internal
    /// padding), so the back button sat twice as far in as the fan button.
    /// The card uses it on all three of its free edges, so its bottom gap
    /// matches its sides.
    private static let chromeInset: CGFloat = 12

    @State private var fanMenuOpen = false
    @State private var searchModel = ReaderSearchModel()
    /// The highlight whose note is being written, if the editor is open.
    @State private var editingNote: ReadingAnnotation?
    /// Note editor queued from inside the Contents sheet, opened only once that
    /// sheet has finished dismissing (see the `onDismiss` on the panel sheet).
    @State private var pendingNoteAfterPanelDismiss: ReadingAnnotation?
    /// Annotation that just got a **Highlight** and still has the floating
    /// colour bar up — nil when the bar is dismissed.
    @State private var colorBarAnnotationID: UUID?
    /// Title-pill → work details, as a sheet over the live reader (see the
    /// `.sheet(isPresented: $showingWorkDetail)` below for why — not a push).
    @State private var showingWorkDetail = false
    @State private var speech = ReaderSpeechController()
    /// Which tab the Contents sheet opens on — the fan's "Contents" and
    /// "Bookmarks & Highlights" pills both route here, differing only in this.
    @State private var contentsSegment: ReaderContentsSegment = .chapters
    /// Chapter-relative seek fraction (0...1) shown by the position card's slider.
    /// Driven from `book.readingPosition` while not being dragged; only pushed to
    /// the navigator on editing-ended, so it never fights `locationDidChange`.
    @State private var sliderValue: Double = 0
    @State private var isEditingSlider = false
    /// Last page live-seeked to during the current drag, so `handleScrubSeek`
    /// fires once per page crossed rather than once per slider sample.
    @State private var lastScrubSeekPage: Int?
    /// Session was playing when hold-seek began — resume speaking on release.
    /// (Kept here with the other stored state; the hold-seek *methods* live in
    /// the speech/scrub extension below, which can't hold stored properties.)
    @State private var speechSeekWasPlaying = false
    /// True while a hold-seek is in progress (suppresses page-follow thrash).
    @State private var speechSeekHolding = false
    /// 0…1 thumb position when the chapter slider scrub began — origin `|` tick.
    @State private var sliderScrubOrigin: Double?
    /// Session-only "kudos left" flag — there's no persisted per-work kudos state
    /// (AO3 doesn't expose one to check), so this reflects only this reading
    /// session's own successful tap, same honesty rule as `AO3WorkActionsModel`.
    @State private var kudosGiven = false
    @State private var kudosWorking = false
    @State private var kudosBanner: String?

    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    /// The effective typography (layout options collapse to defaults when Customize
    /// is off; font weight + size always apply) — same rule as the legacy reader.
    private var textStyle: ReaderTextStyle {
        ReaderTextStyle(
            customize: customizeEnabled, bold: boldText, fontSizePt: fontSizePt,
            lineHeight: lineHeight, letterSpacing: letterSpacing, wordSpacing: wordSpacing,
            margin: pageMargin, justify: justifyText
        ).resolved
    }

    /// Reader chrome (bars) visibility — driven by tapping the page.
    /// Hidden until the first spread has painted so open is skeleton-only
    /// (no spinner, no half-ready position card over empty WebView).
    private var chromeVisible: Bool {
        !book.chromeHidden && book.hasPresentedFirstPage
    }

    /// Collapses colour-bar dismiss triggers into one `onChange` dependency so
    /// `body` stays type-checkable. Any change clears the bar (chrome-hide is
    /// handled separately so it can also close the fan).
    private var colorBarDismissToken: String {
        let position = book.currentLocator?.locations.position.map(String.init) ?? "-"
        return "\(fanMenuOpen)|\(router.panel)|\(showingComments)|\(showingWorkDetail)|\(position)"
    }

    /// The reader's effective theme (app theme while linked).
    private var readerTheme: ReaderTheme {
        themeManager.readerTheme
    }

    private var preferences: EPUBPreferences {
        ReadiumReaderStyleMapper.preferences(
            style: textStyle,
            theme: readerTheme,
            fontFamily: readiumFontFamily,
            readingMode: readingMode,
            // .auto lets Readium show a two-page spread on wide screens (iPad)
            // and one column when narrow; iPhone stays single-column.
            columnCount: (twoPageEnabled && !isPhone) ? .auto : .one
        )
    }

    /// The selected font as a Readium `FontFamily`: a quote-safe custom family
    /// declared via `fontFamilyDeclarations`, or a built-in's primary name.
    /// System is explicit because Readium's default family is serif, while the
    /// legacy System choice is Apple's sans-serif UI stack.
    private var readiumFontFamily: FontFamily? {
        let option = ReaderFontOption.current(id: fontID, customFonts: customFonts)
        return ReadiumReaderStyleMapper.fontFamily(for: option)
    }

    /// `@font-face` declarations for the user's imported fonts, so the navigator can
    /// load and apply them, plus fallback stacks for the built-in choices.
    private var fontFamilyDeclarations: [AnyHTMLFontFamilyDeclaration] {
        ReadiumReaderStyleMapper.fontFamilyDeclarations(
            options: ReaderFontOption.options(customFonts: customFonts)
        )
    }

    /// Re-submit preferences whenever any mapped setting changes (instant updates).
    private var preferencesToken: String {
        "\(readingMode.rawValue)|\(readerTheme.rawValue)|\(fontID)|\(twoPageEnabled)|\(textStyle.token)"
    }

    /// Font declarations are fixed when Readium builds its navigator. Recreate it
    /// after an import or deletion so a newly selected font works immediately.
    private var bookLoadToken: String {
        let fontFiles = customFonts.map(\.fileName).joined(separator: "|")
        return "\(work.id.uuidString)|\(fontFiles)"
    }

    /// Chapters / Display share the app-wide panel slot so only one opens at once.
    private var readerPanelBinding: Binding<Bool> {
        Binding(
            get: {
                router.panel == .readerChapters || router.panel == .readerDisplay
                    || router.panel == .readerFind
            },
            set: { if !$0 { router.panel = .none } }
        )
    }

    var body: some View {
        // Dim + card peel are driven in UIKit during the gesture (see
        // `ReaderDismissDragSurface`) so pan samples don't rebuild this tree.
        ZStack {
            readerTheme.backgroundColor
                .ignoresSafeArea()
            ReaderDismissDimAnchor(surface: dismissSurface)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            dismissableReaderCard
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(readerTheme.colorScheme)
        .navigationTitle(work.title)
        .navigationBarTitleDisplayMode(.inline)
        // The floating top bar replaces the system nav bar entirely. Hide the
        // bar *and* its background so the Library's top-leading menu can't draw
        // over the reader during the push transition.
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
            // `onDismiss` is what makes Contents → Add Note work. These are two
            // sibling sheets on one presenter, and SwiftUI won't present the
            // second while the first is still dismissing — setting both in the
            // same update simply drops the editor. Handing it off here runs it
            // once the panel is really gone.
            .sheet(isPresented: readerPanelBinding, onDismiss: presentPendingNoteEditor) {
                readerSheet
            }
            .commentsSheet(
                isPresented: $showingComments,
                workID: ao3WorkID ?? 0,
                context: .init(savedWork: work),
                initialChapterPosition: currentAO3Chapter
            )
            .sheet(item: $editingNote) { annotation in
                ReaderNoteEditor(annotation: annotation) {
                    try? modelContext.save()
                    FolderSyncService.markDirty()
                    refreshHighlightDecorations()
                } onDelete: {
                    deleteAnnotation(annotation)
                    refreshHighlightDecorations()
                }
                .preferredColorScheme(readerTheme.colorScheme)
            }
            // Title pill → work details as a *sheet*, not a navigation push.
            // Pushing via `navigationDestination(isPresented:)` while the reader
            // has `.toolbar(.hidden, for: .navigationBar)` + statusBarHidden
            // frozen the UI mid-transition (nav stack and status-bar ownership
            // fight). A sheet keeps the immersive reader underneath intact and
            // avoids Detail→Reader→Detail stack bloat.
            .sheet(isPresented: $showingWorkDetail) {
                NavigationStack {
                    WorkDetailView(work: work, openedFromReader: true)
                }
                .preferredColorScheme(readerTheme.colorScheme)
                .presentationDragIndicator(.visible)
            }
            // Highlights made in an earlier session have to be drawn when the
            // book opens, not only when one is created.
            .onChange(of: book.phase) { _, phase in
                guard phase == .ready else { return }
                // Seed slider from initialLocator-backed readingPosition before
                // the first visual JS report can briefly claim last page.
                if !book.isLocatorIngestionBlocked {
                    syncSliderFromPosition(book.readingPosition)
                }
                refreshHighlightDecorations()
                // Tap a highlight on the page → colour / note / delete editor.
                book.observeHighlightTaps { id in
                    openHighlight(id: id)
                }
                speech.prepare(
                    publication: book.publication,
                    title: work.title,
                    author: work.author,
                    totalPositions: book.positionsByReadingOrder.reduce(0) { $0 + $1.count }
                )
                // Keep the page with the voice as it moves between utterances.
                // Blocked during dismiss freeze / successful-exit latch so TTS
                // cannot seek the navigator (or corrupt the flushed locator).
                speech.onAdvance = { locator in
                    // Dismiss freeze/exit latch, and hold-to-seek — never fight
                    // the user (or corrupt a committed exit flush) by page-follow.
                    guard !book.isLocatorIngestionBlocked, !speechSeekHolding else { return }
                    book.go(to: locator)
                }
                // Lock Screen / Island previous-next track = chapter skip (mini player).
                speech.onSkipPrevious = { handleSpeechSkipBack() }
                speech.onSkipNext = { handleSpeechSkipForward() }
            }
            // Voice changes from the Display sheet apply on the next utterance.
            .onChange(of: speechVoiceID) { _, _ in speech.applyPreferences() }
            .onChange(of: chromeVisible) { _, visible in
                if !visible {
                    fanMenuOpen = false
                    colorBarAnnotationID = nil
                }
            }
            // Single token so we don't hang the type-checker with a forest of
            // .onChange on `body` (colour bar is contextual — drop when context ends).
            .onChange(of: colorBarDismissToken) { _, _ in
                colorBarAnnotationID = nil
            }
            .alert("AO3", isPresented: kudosBannerPresented) {
                Button("OK", role: .cancel) { kudosBanner = nil }
            } message: {
                Text(kudosBanner ?? "")
            }
            // Immersive reading: hide the tab bar; the status bar follows the chrome.
            .toolbar(.hidden, for: .tabBar)
            .statusBarHidden(!chromeVisible)
            .persistentSystemOverlays(chromeVisible ? .automatic : .hidden)
            .animation(unlessReduced: .easeInOut(duration: 0.25), value: book.chromeHidden)
            .animation(.easeInOut(duration: 0.25), value: speech.isSessionActive)
            // Readium's WebView swallows the system edge-swipe; add our own.
            .edgeSwipeToGoBack { dismissReader() }
            .task(id: bookLoadToken) {
                // Seed page-box inputs before the navigator exists: first
                // content-inset query runs during setup.
                book.renderedLineHeightPoints = textStyle.fontSizePt * textStyle.lineHeight
                book.renderedPageMarginPoints = max(0, textStyle.margin)
                book.seedPageBoxGeometryFromWindowIfNeeded()
                await openBook()
            }
            .onChange(of: preferencesToken) { _, _ in applyReaderPreferences() }
            // The Display / Customize controls live in a sheet over the reader; a
            // behind-the-sheet onChange can be missed, so re-apply when it closes.
            .onChange(of: router.panel) { _, panel in
                if panel == .none {
                    applyReaderPreferences()
                    speech.applyPreferences()
                    // Drop results (and any in-flight search) with the sheet, so
                    // reopening Find starts clean instead of on a stale query.
                    searchModel.reset()
                }
            }
            .onChange(of: book.readingPosition) { _, newValue in
                // Dismiss freeze / exit latch: never move the scrub bar.
                guard !book.isLocatorIngestionBlocked else { return }
                syncSliderFromPosition(newValue)
            }
            .onChange(of: scenePhase) { _, phase in
                // Force-quit safety: flush when leaving the foreground so a
                // debounced window can't lose the last settle.
                // - `.background`: full shelf stamp (Continue Reading).
                // - `.inactive` (Control Center / app switcher): position only —
                //   avoid rewriting lastReadDate on every transient inactive flip.
                switch phase {
                case .background:
                    flushProgress(shelfStamp: true)
                case .inactive:
                    flushProgress(shelfStamp: false)
                default:
                    break
                }
            }
            .onDisappear {
                // Safety net: `isScrubbing` gates the debounced progress write,
                // so a drag that never delivers `onEditingChanged(false)` (view
                // torn down mid-gesture, slider disabled mid-drag) would leave
                // it latched and silently stop persisting progress for the rest
                // of the session. Releasing it here costs nothing when the flag
                // is already clear, which is the normal case.
                book.isScrubbing = false
                isEditingSlider = false
                // Flush the exact final position so resume lands precisely, even if the
                // last scroll's debounce window hadn't elapsed before we left.
                flushProgress(shelfStamp: true)
                WorkLifecycle.freeEPUBIfFinished(work, in: modelContext)
                try? modelContext.save()
                scheduleFolderSyncOnReaderClose()
                // The lock is the reader's, not the app's — never leave the rest
                // of the app pinned to whatever orientation reading ended in.
                orientationLock.release()
                // Reading aloud is bound to this reader: leaving a *work* tears
                // down speech + remote commands + Now Playing. Backgrounding the
                // app with the reader still open keeps TTS (system Now Playing).
                // Mini-player stop still uses `stop()` only — see `stopReadingAloud`.
                speech.tearDown()
                if router.panel == .readerChapters || router.panel == .readerDisplay {
                    router.panel = .none
                }
            }
    }

    /// Ends speech and collapses the mini-player strip. Shared by the fan-menu
    /// waveform control (when active) and the mini player's stop button.
    /// Leaving the reader uses `speech.tearDown()` instead so remote commands
    /// are removed (not only paused/stopped).
    private func stopReadingAloud() {
        speech.stop()
    }

    /// Fan-menu waveform: start from the current page when idle; otherwise the
    /// same full stop as the mini player (not pause).
    private func toggleReadingAloud() {
        if speech.status != .stopped {
            stopReadingAloud()
        } else {
            speech.toggle(from: book.currentLocator)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch book.phase {
        case .loading:
            // Opaque page skeleton so the Library toolbar/menu can't show through
            // during the push transition, and so opening matches the rest of the app.
            ReaderPageSkeletonFill(background: readerTheme.backgroundColor)
        case let .failed(message):
            ContentUnavailableView("Couldn't open this EPUB", systemImage: "exclamationmark.triangle",
                                   description: Text(message))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(readerTheme.backgroundColor)
        case .ready:
            if let navigator = book.navigator {
                // Navigator must be in the hierarchy to load spreads, but Readium
                // draws a centered UIActivityIndicator until the first WebView
                // paints. Keep the same page skeleton on top until
                // `hasPresentedFirstPage` so the user never sees that spinner
                // after the destination/open skeleton handoff.
                ZStack {
                    ReadiumNavigatorContainer(
                        controller: navigator,
                        readingMode: readingMode,
                        dismissSurface: dismissSurface,
                        reduceMotion: reduceMotion,
                        onDismissInteractionActiveChange: handleDismissInteractionActiveChange,
                        onDismissDragEnded: handleDismissDragEnded,
                        onHighlight: { createAnnotationFromSelection(withNote: false) },
                        onAddNote: { createAnnotationFromSelection(withNote: true) }
                    )
                    .ignoresSafeArea()
                    if !book.hasPresentedFirstPage {
                        ReaderPageSkeletonFill(background: readerTheme.backgroundColor)
                            .transition(.opacity)
                    }
                }
                .animation(unlessReduced: .easeOut(duration: 0.15), value: book.hasPresentedFirstPage)
            } else {
                // Keep a full-size host even if the navigator is momentarily nil
                // so chrome overlays never re-collapse to a zero-size anchor.
                ReaderPageSkeletonFill(background: readerTheme.backgroundColor)
            }
        }
    }

    private func handleDismissInteractionActiveChange(_ active: Bool) {
        // Successful exit keeps the gate latched until the book is deallocated.
        if !active && (isDismissingByDrag || book.isDismissExitLatched) { return }
        book.setDismissInteractionActive(active)
    }

    private func handleDismissDragEnded(_ shouldDismiss: Bool, unfreeze: @escaping () -> Void) {
        guard !isDismissingByDrag else { return }
        if shouldDismiss {
            // Lock the peel transform *before* flush/latch. Those touch
            // @State/@Observable and rebuild the peel host; without the lock the
            // card snaps to identity (bounce up), re-applies finger offset
            // (comes down), then flies off.
            dismissSurface.lockTransformForExit()
            // Flush *before* latching so live (still freeze-stable) locator is
            // recorded once; subsequent flushes skip re-record.
            flushProgress(shelfStamp: true)
            isDismissingByDrag = true
            book.latchDismissExit()
            // Leave page freeze in place until view teardown — never call
            // `unfreeze` on the success path (would re-enable ingestion mid-exit).
            if reduceMotion {
                dismissSurface.endCardSnapshot()
                dismissSurface.reset(reduceMotion: true)
                dismissReader()
                return
            }
            // Fly the card snapshot off-screen, then pop.
            dismissSurface.animate(
                to: 1400,
                reduceMotion: false,
                duration: 0.22,
                spring: false
            ) {
                self.dismissSurface.endCardSnapshot()
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { self.dismissReader() }
            }
            return
        }
        // Cancel: spring snapshot back, restore live card, unfreeze WebKit.
        if dismissSurface.offset != 0 {
            dismissSurface.animate(
                to: 0,
                reduceMotion: reduceMotion,
                duration: 0.38,
                spring: true
            ) {
                self.dismissSurface.endCardSnapshot()
                unfreeze()
            }
        } else {
            dismissSurface.endCardSnapshot()
            unfreeze()
        }
    }

    // MARK: In-book annotations

    /// Creates a highlight from the reader's current text selection, optionally
    /// opening the note editor straight afterwards.
    ///
    /// Re-highlighting the same passage with **Highlight** compares the
    /// currently-picked colour against the existing mark's (ANN-2, product
    /// decision 2026-07-28): the *same* colour again toggles it off, same as
    /// tapping your own highlighter twice; a *different* colour recolours it
    /// in place instead of stacking a second mark over the same words.
    /// **Add Note** on an existing mark opens its editor either way.
    ///
    /// New marks use the last-picked colour, then surface the floating colour
    /// bar so the reader can refine without a second trip through the editor.
    ///
    /// The anchor is the selection's own `Locator` — it carries the CFI//text
    /// range Readium needs to redraw the highlight over the exact words — and
    /// `text.highlight` is stored alongside it as the passage snapshot.
    private func createAnnotationFromSelection(withNote: Bool) {
        guard let selection = book.currentSelection,
              let locatorString = selection.locator.persistenceString
        else { return }

        if let existing = existingHighlight(matching: selection.locator) {
            book.clearSelection()
            if withNote {
                colorBarAnnotationID = nil
                editingNote = existing
            } else if existing.color == ReadingAnnotationColor.lastUsed {
                colorBarAnnotationID = nil
                deleteAnnotation(existing)
            } else {
                applyHighlightColor(ReadingAnnotationColor.lastUsed, to: existing)
            }
            return
        }

        let color = ReadingAnnotationColor.lastUsed
        let spineIndex = (book.readingPosition?.chapter ?? 1) - 1
        let annotation = ReadingAnnotation(
            work: work,
            kind: .highlight,
            locatorString: locatorString,
            selectedText: selection.locator.text.highlight ?? "",
            color: color,
            progression: selection.locator.locations.totalProgression ?? 0,
            spineIndex: spineIndex,
            chapterTitle: chapterTitle(forSpineIndex: spineIndex)
        )
        modelContext.insert(annotation)
        try? modelContext.save()
        FolderSyncService.markDirty()

        book.clearSelection()
        refreshHighlightDecorations()
        if withNote {
            colorBarAnnotationID = nil
            editingNote = annotation
        } else {
            // Immediate colour refine — the system menu can't host a picker.
            colorBarAnnotationID = annotation.id
        }
    }

    private func applyHighlightColor(_ color: ReadingAnnotationColor, to annotation: ReadingAnnotation) {
        guard annotation.color != color else {
            colorBarAnnotationID = nil
            return
        }
        annotation.color = color
        annotation.markModified()
        ReadingAnnotationColor.lastUsed = color
        try? modelContext.save()
        FolderSyncService.markDirty()
        refreshHighlightDecorations()
        // One tap applies and dismisses — refining again is a tap on the mark.
        colorBarAnnotationID = nil
    }

    /// The live highlight that covers this selection, if any.
    /// Match is **locator-string equality only** (see `ReadingAnnotationMatching`).
    private func existingHighlight(matching locator: Locator) -> ReadingAnnotation? {
        guard let selectionLocator = locator.persistenceString, !selectionLocator.isEmpty
        else { return nil }

        return annotations
            .filter { $0.kind == .highlight }
            .first { annotation in
                ReadingAnnotationMatching.isSamePassage(
                    existingLocator: annotation.locatorString,
                    selectionLocator: selectionLocator
                )
            }
    }

    /// Redraws every highlight for this work over the page. Called after any
    /// change to the set, and once the book is ready (a highlight made in a
    /// previous session has to be drawn on open, not just when created).
    private func refreshHighlightDecorations() {
        let decorations: [Decoration] = annotations
            .filter { $0.kind == .highlight }
            .compactMap { annotation in
                guard let locator = Locator(persistenceString: annotation.locatorString) else { return nil }
                let tint = UIColor(annotation.color.tint)
                // Underline is a rule, not a fill — match the palette swatch.
                let style: Decoration.Style = annotation.color == .underline
                    ? .underline(tint: tint)
                    : .highlight(tint: tint)
                return Decoration(
                    id: annotation.id.uuidString,
                    locator: locator,
                    style: style
                )
            }
        book.applyHighlightDecorations(decorations)
    }

    /// Adds a bookmark at the current page, or removes the one already there.
    /// Deletion records a `.readingAnnotation` tombstone so a restore from an
    /// older archive can't resurrect it (see the merge rules in
    /// `docs/DATA_AND_PERSISTENCE_INVARIANTS.md`).
    private func toggleBookmarkAtCurrentPosition() {
        if let existing = bookmarkAtCurrentPosition {
            modelContext.insert(SyncTombstone(
                recordID: existing.id,
                recordType: .readingAnnotation,
                sourceURL: work.sourceURL,
                ao3WorkID: ao3WorkID
            ))
            modelContext.delete(existing)
            try? modelContext.save()
            FolderSyncService.markDirty()
        } else if let locator = book.currentLocator {
            addBookmark(at: locator)
        }
    }

    /// `book.sections`' spine index for a locator's resource, matched by href.
    ///
    /// All three index spaces here are the same length — `ReaderSectionBuilder`
    /// emits one `ReaderSection` per spine href, and Readium builds
    /// `positionsByReadingOrder` as `readingOrder.map { ... ?? [] }`, keeping
    /// empty entries. The reason to prefer href is not length, it's *derivation*:
    /// `readingPosition.chapter` resolves the chapter by scanning global
    /// position ranges, so it only answers for locators that carry a
    /// `locations.position`. Search results don't (Readium's search service
    /// emits progression only), and neither does a locator mid-navigation — for
    /// those it silently falls through to a different answer than href matching
    /// gives. Since `ReaderSearchGrouping` buckets results by href, deriving the
    /// reader's own index any other way let the two disagree, which is why
    /// "This Chapter" didn't reliably pin first.
    private func spineIndex(for locator: Locator) -> Int? {
        let key = ReaderSectionBuilder.hrefKey(locator.href.string)
        return book.sections.first { ReaderSectionBuilder.hrefKey($0.href) == key }?.spineIndex
    }

    /// The reader's live chapter, on the same `sections`-href basis as
    /// `spineIndex(for:)` — see its doc comment for why that matters.
    private var currentSpineIndex: Int? {
        book.currentLocator.flatMap(spineIndex(for:))
    }

    /// Adds a bookmark at an arbitrary locator (e.g. a Find in Work result),
    /// unlike `toggleBookmarkAtCurrentPosition` which only ever targets the
    /// reader's live position.
    /// Returns the bookmark now at this spot — the newly created one, or the
    /// existing one when there already was a bookmark there — so callers that
    /// need to act on it (Contents' **Add Note**, which opens the editor on it)
    /// don't have to re-find it and can't accidentally create a second.
    @discardableResult
    private func addBookmark(at locator: Locator) -> ReadingAnnotation? {
        let locator = resolvedPositionLocator(for: locator)
        guard let locatorString = locator.persistenceString else { return nil }
        // Don't stack a second bookmark on a spot that already has one. Matched
        // on `position` (not the whole locator string) for the same reason
        // `bookmarkAtCurrentPosition` does: a search-result locator and a
        // live-reading locator for the same page carry different progression
        // and text, so string equality would see two distinct marks where the
        // reader sees one page.
        if let position = locator.locations.position,
           let existing = bookmarkAnnotations.first(where: {
               Locator(persistenceString: $0.locatorString)?.locations.position == position
           }) {
            return existing
        }
        let spineIndex = spineIndex(for: locator) ?? 0
        let bookmark = ReadingAnnotation(
            work: work,
            kind: .bookmark,
            locatorString: locatorString,
            progression: locator.locations.totalProgression ?? 0,
            spineIndex: spineIndex,
            chapterTitle: chapterTitle(forSpineIndex: spineIndex)
        )
        modelContext.insert(bookmark)
        try? modelContext.save()
        FolderSyncService.markDirty()
        return bookmark
    }

    /// Backfills `locations.position` when it's missing, so bookmarks created
    /// away from the live navigator still participate in `bookmarkAtCurrentPosition`'s
    /// position-based matching. Readium's search service returns locators with
    /// `progression` but not `position` (that's a separate `PositionsService`
    /// cross-reference the search index doesn't do) — storing one of those
    /// as-is meant a Find in Work bookmark could never be recognized as
    /// "already bookmarked" by the regular bookmark button, silently allowing
    /// a duplicate at the same spot. Finds the closest position-list entry in
    /// the same chapter by progression and borrows its `position`, leaving
    /// every other field (href, progression, text) untouched.
    private func resolvedPositionLocator(for locator: Locator) -> Locator {
        guard locator.locations.position == nil,
              let progression = locator.locations.progression,
              let spineIndex = spineIndex(for: locator),
              book.positionsByReadingOrder.indices.contains(spineIndex)
        else { return locator }
        let candidates = book.positionsByReadingOrder[spineIndex]
        guard let nearest = candidates.min(by: {
            abs(($0.locations.progression ?? 0) - progression) < abs(($1.locations.progression ?? 0) - progression)
        }), let resolvedPosition = nearest.locations.position else { return locator }
        return locator.copy(locations: { $0.position = resolvedPosition })
    }

    /// The section title to stamp on a new annotation, so its list row reads
    /// well even before the book's sections are loaded.
    private func chapterTitle(forSpineIndex index: Int) -> String {
        guard book.sections.indices.contains(index) else { return "" }
        return book.sections[index].title
    }

    /// Jumps to an annotation's anchor and closes the sheet. Highlights also
    /// open the note/colour/delete editor so a bare mark is editable in place.
    private func goToAnnotation(_ annotation: ReadingAnnotation) {
        if let locator = Locator(persistenceString: annotation.locatorString) {
            book.go(to: locator)
        }
        router.panel = .none
        if annotation.kind == .highlight {
            editingNote = annotation
        }
    }

    private func deleteAnnotation(_ annotation: ReadingAnnotation) {
        if editingNote?.id == annotation.id {
            editingNote = nil
        }
        if colorBarAnnotationID == annotation.id {
            colorBarAnnotationID = nil
        }
        modelContext.insert(SyncTombstone(
            recordID: annotation.id,
            recordType: .readingAnnotation,
            sourceURL: work.sourceURL,
            ao3WorkID: ao3WorkID
        ))
        modelContext.delete(annotation)
        try? modelContext.save()
        FolderSyncService.markDirty()
        refreshHighlightDecorations()
    }

    /// Opens the editor for a highlight the reader tapped on the page.
    private func openHighlight(id decorationID: String) {
        guard let annotation = annotations.first(where: {
            $0.kind == .highlight && $0.id.uuidString == decorationID
        }) else { return }
        editingNote = annotation
    }

    /// Submits mapped preferences and keeps page-box inputs in step with Customize:
    /// - **Text size / line height** → `renderedLineHeightPoints` + forced spread
    ///   content-inset refresh so whole-line snap is not stale.
    /// - **Page margin** → Readium horizontal `pageMargins` (vertical box uses
    ///   frozen safe area only; margin is not subtracted from safe top/bottom).
    private func applyReaderPreferences() {
        book.renderedLineHeightPoints = textStyle.fontSizePt * textStyle.lineHeight
        book.renderedPageMarginPoints = max(0, textStyle.margin)
        book.submit(preferences)
        // Typography submit updates CSS but may not re-run spread updateContentInset.
        book.forcePageBoxContentInsetRefresh()
        // Font/columns/mode/margin change swipe pageCount — remeasure instead of sticky Y.
        book.clearVisualPageMetrics()
        book.schedulePageBarRemeasure()
    }

    private func dismissReader() {
        // Close button / edge swipe: kill TTS page-follow, flush the live locator
        // once, then latch so `onDisappear`'s second flush cannot re-record a
        // speech- or teardown-corrupted position. Swipe-down already flushed +
        // latched before fly-off; latch is idempotent.
        speech.onAdvance = nil
        if !book.isDismissExitLatched {
            flushProgress(shelfStamp: true)
            book.latchDismissExit()
            isDismissingByDrag = true
        } else {
            // Already committed on peel success — shelf stamp only if needed.
            flushProgress(shelfStamp: true)
        }
        dismiss()
    }

    /// Flush point (dismiss / background / disappear): always persist the latest
    /// locator when it differs from disk, and refresh Continue Reading order.
    /// Bypasses the debounce window — a flush must never be dropped.
    private func flushProgress(shelfStamp: Bool) {
        progressPersistence.cancelTrailingWrite()
        // Prefer the live navigator locator; fall back to the last noted string.
        // After exit has committed (swipe peel or close/edge), never re-record a
        // live locator — freeze release / late TTS can still mutate `currentLocator`
        // while the view is tearing down.
        let exitCommitted = isDismissingByDrag || book.isDismissExitLatched
        if !exitCommitted, let live = book.currentLocator?.persistenceString {
            progressPersistence.record(
                locatorString: live,
                totalProgression: book.currentLocator?.locations.totalProgression
            )
        }
        let now = Date()
        if let toWrite = progressPersistence.locatorForFlush() {
            if shelfStamp {
                work.readiumLocator = toWrite
                work.markProgressModified(now)
            } else {
                work.applyDebouncedReadiumLocator(toWrite, at: now)
            }
            progressPersistence.markPersisted(
                locatorString: toWrite,
                totalProgression: book.currentLocator?.locations.totalProgression
                    ?? progressPersistence.latestTotalProgression,
                at: now
            )
            try? modelContext.save()
            FolderSyncService.markDirty()
        } else if shelfStamp, progressPersistence.hasSessionPosition {
            // Locator already on disk — still bump lastReadDate so the shelf
            // reflects this reading session on a quick open/close.
            work.markProgressModified(now)
            try? modelContext.save()
        }
    }

    /// Reader close is a natural batch point for reading progress, so it gets a
    /// near-immediate sync-up rather than waiting out the normal debounce window —
    /// but it must never block dismissal, so this fires a detached, best-effort Task.
    private func scheduleFolderSyncOnReaderClose() {
        FolderSyncService.markDirty()
        guard FolderSyncService.snapshot().isConnected, FolderSyncService.snapshot().autoSyncEnabled else { return }
        let context = modelContext
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            _ = try? await FolderSyncService.syncUp(in: context)
        }
    }

    // MARK: Chrome

    /// Page + floating chrome as one surface, so drag-to-dismiss moves the whole
    /// reader (not only the EPUB text) — Apple Books card behaviour.
    ///
    /// Host must always fill the screen: while `.loading` (and until the first
    /// spread paints), `content` is a themed page skeleton so Library chrome
    /// and Readium's own activity indicator never flash mid-screen.
    /// Sheets / lifecycle modifiers stay *outside* this tree so they are not
    /// scaled/offset with the card.
    private var dismissableReaderCard: some View {
        // UIKit host owns the peel transform for page + chrome as one unit.
        ReaderDismissPeelHost(surface: dismissSurface, reduceMotion: reduceMotion) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Each chrome layer sizes to its own content (no infinite-frame
                // hit-test area), so taps between controls still reach the page.
                .overlay(alignment: .top) { topBarLayer }
                // Bottom stack: colour bar + position card / decoupled mini player.
                .overlay(alignment: .bottom) { bottomChromeLayer }
                .overlay { fanDismissBackdropLayer }
                .overlay(alignment: .topTrailing) { fanMenuLayer }
                .overlay(alignment: .trailing) { scrollIndicatorLayer }
                .background(readerTheme.backgroundColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // `host.safeAreaRegions = []` (inside the peel host) only stops the
        // *inner* UIHostingController from handing safe-area insets down to its
        // own SwiftUI content — it has no effect on how the *outer* SwiftUI
        // layout treats `ReaderDismissPeelHost` itself. Without this, SwiftUI
        // still shrinks this representable into the safe sub-rectangle by
        // default, and the manual `pageBoxChromeSafeTop`/`Bottom` chrome padding
        // below then stacks a second inset on top of that — the double top/
        // bottom padding bug. This is the modifier the "peel host zeroes SwiftUI
        // safe regions" comments elsewhere assumed was already in effect.
        .ignoresSafeArea()
    }

    private var topBarLayer: some View {
        ReaderChromeTopBar(
            title: work.title, author: work.author,
            tint: themeManager.effectiveTint, titleHidden: fanMenuOpen,
            onClose: dismissReader,
            onOpenDetails: { showingWorkDetail = true }
        )
        // Peel host zeroes SwiftUI safe regions — pad from the same frozen
        // window safe area the page box uses (plus chromeInset).
        .padding(.top, book.pageBoxChromeSafeTop + 8)
        .allowsHitTesting(chromeVisible)
        .opacity(chromeVisible ? 1 : 0)
    }

    /// Present only while the fan is open — otherwise a screen-sized tap target
    /// would swallow every tap meant for the page's own chrome toggle.
    @ViewBuilder
    private var fanDismissBackdropLayer: some View {
        if fanMenuOpen, chromeVisible {
            ReaderFanMenu.dismissBackdrop(isOpen: $fanMenuOpen, reduceMotion: reduceMotion)
        }
    }

    private var fanMenuLayer: some View {
        ReaderFanMenu(isOpen: $fanMenuOpen, pills: fanPills, shareURL: shareURL,
                      roundActions: fanRoundActions,
                      accentColor: themeManager.effectiveTint, reduceMotion: reduceMotion)
            .padding(.trailing, Self.chromeInset)
            .padding(.top, book.pageBoxChromeSafeTop + 8)
            .allowsHitTesting(chromeVisible)
            .opacity(chromeVisible ? 1 : 0)
            // QuickLook renders the archived original in place — a PDF stays a PDF, so
            // the reader can compare the conversion against the source, including the
            // images conversion drops.
            .quickLookPreview($previewingOriginal)
            .alert(
                "Couldn't Rebuild This Work",
                isPresented: Binding(
                    get: { rebuildError != nil },
                    set: { if !$0 { rebuildError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { rebuildError = nil }
            } message: {
                Text(rebuildError ?? "")
            }
    }

    /// Re-runs conversion from the archived original, in place. Surfaced in the reader
    /// because that is where a reader notices the conversion is wrong.
    @MainActor
    private func rebuildFromOriginal() async {
        do {
            try await WorkReconversion.reconvert(work, in: modelContext)
        } catch {
            rebuildError = error.localizedDescription
        }
    }

    /// Bottom chrome stack:
    /// - **Chrome up + speech:** colour bar (optional) + position card with mini player inside
    /// - **Chrome down + speech:** mini player alone (decoupled; seek card hidden)
    /// - **Chrome up, no speech:** position card only
    /// - **Chrome down, no speech:** empty
    ///
    /// Colour bar lives in this VStack (not a magic `+ 88` offset) so it always
    /// clears the card cleanly.
    @ViewBuilder
    private var bottomChromeLayer: some View {
        let speechActive = speech.isSessionActive
        VStack(spacing: 10) {
            if chromeVisible {
                highlightColorBar
                // Coupled: mini player rides inside the position card when speaking.
                positionCard(includeMiniPlayer: speechActive)
            } else if speechActive {
                // Decoupled: transport stays reachable while full chrome is hidden.
                standaloneMiniPlayer
            }
        }
        .padding(.horizontal, Self.chromeInset)
        .padding(.bottom, book.pageBoxChromeSafeBottom + Self.chromeInset)
        .allowsHitTesting(chromeVisible || speechActive)
    }

    @ViewBuilder
    private var highlightColorBar: some View {
        if let id = colorBarAnnotationID,
           let annotation = annotations.first(where: { $0.id == id })
        {
            ReaderHighlightColorBar(
                selected: annotation.color,
                onSelect: { applyHighlightColor($0, to: annotation) },
                onDismiss: { colorBarAnnotationID = nil }
            )
        }
    }

    /// Mini player in its own glass when chrome is dismissed mid-TTS.
    private var standaloneMiniPlayer: some View {
        speechMiniPlayer(tint: themeManager.effectiveTint)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func speechMiniPlayer(tint: SwiftUI.Color) -> some View {
        ReaderSpeechMiniPlayer(
            controller: speech,
            tint: tint,
            onStop: { stopReadingAloud() },
            onSkipBack: { handleSpeechSkipBack() },
            onSkipForward: { handleSpeechSkipForward() },
            onSeekHoldStart: { forward in handleSpeechSeekHoldStart(forward: forward) },
            onSeekHoldTick: { forward in handleSpeechSeekHoldTick(forward: forward) },
            onSeekHoldEnd: { handleSpeechSeekHoldEnd() },
            // Empty areas of the strip (caption, waveform, gutters) show chrome —
            // same idea as tapping the page when only the mini player is up.
            onBackgroundTap: { book.chromeHidden = false }
        )
    }

    /// Position card; when `includeMiniPlayer` the TTS strip sits above a
    /// hairline separator inside the same glass surface. While the EPUB is
    /// still opening (or before the first locator), show a glass skeleton so
    /// the bottom chrome occupies its final layout immediately.
    @ViewBuilder
    private func positionCard(includeMiniPlayer: Bool) -> some View {
        Group {
            if let summary = positionSummary {
                positionCardContent(summary: summary, includeMiniPlayer: includeMiniPlayer)
            } else {
                ReaderPositionCardSkeleton()
            }
        }
    }

    @ViewBuilder
    private func positionCardContent(
        summary: ReaderPositionSummary,
        includeMiniPlayer: Bool
    ) -> some View {
        let tint = themeManager.effectiveTint
        // Always use readingPosition for both page and pageCount so we never mix
        // visual swipe pages (e.g. 95) with Readium ~1 KB chapter positions (e.g. 10).
        // That mixed pair produced "Page 95 of 10" until the next swipe refreshed UI.
        let pos = book.readingPosition
        let pageReady = pos?.pageBarReady == true
        let pageCount = pageReady ? max(1, pos?.pageCount ?? 1) : 1
        let sliderEnabled = pageReady && pageCount > 1
        // Live page under the thumb while scrubbing; otherwise navigator page.
        let displayPage: Int = {
            guard pageReady else { return 1 }
            if isEditingSlider {
                return ReaderChapterScrub.page(sliderValue: sliderValue, pageCount: pageCount)
            }
            return min(pageCount, max(1, pos?.page ?? 1))
        }()
        // Chapter minutes left track the thumb while scrubbing.
        // Visual page units must never be fed to `minutes(forPositions:)` as if
        // they were ~1 KB Readium positions — scale via chapter position count.
        let chapterRemainingMinutes: Int? = {
            guard pageReady else { return nil }
            if isEditingSlider {
                guard let chapterPositions = book.currentChapterPositions,
                      !chapterPositions.isEmpty, pageCount > 0
                else { return nil }
                let remaining = ReaderPageMetrics.chapterRemainingPositions(
                    page: displayPage,
                    pageCount: pageCount,
                    chapterPositionCount: chapterPositions.count
                )
                return ReaderTimeEstimate.minutes(forPositions: remaining)
            }
            if let remaining = book.remainingPositions?.chapter {
                return ReaderTimeEstimate.minutes(forPositions: remaining)
            }
            return nil
        }()
        // Theme tint on page digit + "N min" when scrubbed away from origin.
        let scrubValuesEmphasized = ReaderChapterScrub.isDeviatedFromOrigin(
            sliderValue: sliderValue,
            origin: sliderScrubOrigin,
            pageCount: pageCount
        )
        // Until swipe-scale measure is ready: page=0 signals "Page …" (not 1 of 1).
        let cardPage = pageReady ? displayPage : 0
        let cardPageCount = pageReady ? pageCount : 0
        Group {
            if includeMiniPlayer {
                ReaderPositionCard(
                    page: cardPage,
                    pageCount: cardPageCount,
                    chapterRemainingMinutes: chapterRemainingMinutes,
                    workLine: summary.workLine,
                    tint: tint,
                    sliderValue: scrubBinding,
                    sliderEnabled: sliderEnabled,
                    scrubOrigin: sliderScrubOrigin,
                    scrubValuesEmphasized: scrubValuesEmphasized,
                    onEditingChanged: handleSliderEditingChanged
                ) {
                    speechMiniPlayer(tint: tint)
                }
            } else {
                ReaderPositionCard(
                    page: cardPage,
                    pageCount: cardPageCount,
                    chapterRemainingMinutes: chapterRemainingMinutes,
                    workLine: summary.workLine,
                    tint: tint,
                    sliderValue: scrubBinding,
                    sliderEnabled: sliderEnabled,
                    scrubOrigin: sliderScrubOrigin,
                    scrubValuesEmphasized: scrubValuesEmphasized,
                    onEditingChanged: handleSliderEditingChanged
                )
            }
        }
        // Selection ticks only while scrubbing (trigger is 0 when not editing).
        .sensoryFeedback(.selection, trigger: scrubPreviewPage(pageCount: pageCount))
    }

    /// Page under the thumb while scrubbing; stable `0` when not editing so
    /// sensory feedback only fires on real scrub steps.
    private func scrubPreviewPage(pageCount: Int) -> Int {
        guard isEditingSlider, pageCount > 0 else { return 0 }
        return ReaderChapterScrub.page(sliderValue: sliderValue, pageCount: pageCount)
    }


    /// The fan's round action row (after the native `ShareLink` slot): kudos is
    /// wired to the existing native write action; read aloud and in-book
    /// bookmarking are shown per the layout but disabled until their capabilities
    /// land (TASKS.md) rather than faked.
    private var fanRoundActions: [ReaderFanRoundAction] {
        var actions: [ReaderFanRoundAction] = []
        // Icons always use the reader theme tint; active/inactive is outline vs
        // filled SF Symbol (kudos heart, bookmark), not grey vs tint.
        let tint = themeManager.effectiveTint
        if let ao3WorkID {
            actions.append(ReaderFanRoundAction(
                id: "kudos",
                systemImage: kudosGiven ? "heart.fill" : "heart",
                tint: tint,
                accessibilityLabel: kudosGiven ? "Kudos given" : "Give kudos",
                isEnabled: !kudosWorking && !kudosGiven
            ) {
                giveKudos(workID: ao3WorkID)
            })
        }
        // Converted imports only — an AO3 EPUB has no "original" behind it. Sits in
        // the round row rather than the pill list because the owner wanted it here,
        // and it reads as a peer of Share: both are about the file rather than the
        // reading session.
        //
        // Worth having at all because conversion is lossy — images are dropped, layout
        // is reflowed — so checking the source is how a reader tells a conversion
        // artefact from something the author actually wrote.
        if let original = originalDocumentURL {
            actions.append(ReaderFanRoundAction(
                id: "original",
                systemImage: "doc.text.magnifyingglass",
                tint: tint,
                accessibilityLabel: "View the original file this work was converted from"
            ) {
                previewingOriginal = original
            })
        }
        // Start when idle; when the mini player is up (playing *or* paused) this
        // is the same `stopReadingAloud()` the mini player's stop button uses —
        // not pause — so the strip dismisses instead of lingering muted.
        // `isSessionActive` (not `status != .stopped`): the raw comparison also
        // matched `.unavailable`, so a publication Readium can't speak got the
        // filled/emphasized "active" look and a "Stop reading aloud" a11y label
        // on a control that was simultaneously disabled below.
        let speechActive = speech.isSessionActive
        actions.append(ReaderFanRoundAction(
            id: "readAloud",
            // Active: filled waveform + theme capsule fill (same emphasized
            // treatment as rotation lock) so "speaking" is obvious at a glance.
            systemImage: speechActive ? "waveform.circle.fill" : "waveform",
            tint: tint,
            accessibilityLabel: speechActive ? "Stop reading aloud" : "Read aloud",
            // Needs extractable content; a publication Readium can't tokenise
            // gets a disabled control rather than silent no-op playback.
            isEnabled: speech.isAvailable,
            isEmphasized: speechActive
        ) {
            playReaderToggleHaptic()
            withAnimation(.snappy(duration: 0.35)) {
                toggleReadingAloud()
            }
        })
        let rotationLocked = orientationLock.isLocked
        actions.append(ReaderFanRoundAction(
            id: "rotationLock",
            // Open padlock while rotation is free, closed once pinned — the SF
            // Symbol for the open variant is `lock.open.rotation`, not
            // `lock.rotation.open`, which silently renders nothing. Pair with
            // `.contentTransition(.symbolEffect(.replace))` on the Image and
            // `withAnimation` here for the Control Center lock morph.
            // Locked also fills the capsule with theme tint + a white glyph so
            // the state is obvious (outline vs closed lock alone is too subtle).
            systemImage: rotationLocked ? "lock.rotation" : "lock.open.rotation",
            tint: tint,
            accessibilityLabel: rotationLocked ? "Unlock rotation" : "Lock rotation",
            isEmphasized: rotationLocked
        ) {
            playReaderToggleHaptic()
            withAnimation(.snappy(duration: 0.35)) {
                orientationLock.toggle(in: ReaderOrientationLock.activeScene)
            }
        })
        let isBookmarked = bookmarkAtCurrentPosition != nil
        actions.append(ReaderFanRoundAction(
            id: "bookmark",
            systemImage: isBookmarked ? "bookmark.fill" : "bookmark",
            tint: tint,
            accessibilityLabel: isBookmarked ? "Remove bookmark" : "Add bookmark",
            // Needs a locator to anchor to; disabled until the navigator reports one.
            isEnabled: currentReadingPosition != nil
        ) {
            playReaderToggleHaptic()
            toggleBookmarkAtCurrentPosition()
        })
        return actions
    }

    /// Light toggle tick for fan round actions (rotation lock, TTS, bookmark).
    private func playReaderToggleHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Stronger tick when a chapter skip / restart commits (Music-like boundary).
    private func playSpeechChapterHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Soft step feedback while hold-seeking within a chapter.
    private func playSpeechSeekTickHaptic() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    // MARK: Loading + progress

    private func openBook() async {
        // Capture references (not the view struct) so the escaping callback is clean.
        let work = work
        let context = modelContext
        let router = router
        let progressPersistence = progressPersistence

        // Baseline + one session-open shelf stamp (Continue Reading). Mid-session
        // settles use the debounced path and do not rewrite lastReadDate.
        progressPersistence.seed(
            persistedLocatorString: work.readiumLocator.isEmpty ? nil : work.readiumLocator
        )
        work.markProgressModified(Date())
        try? context.save()

        progressPersistence.onDebouncedWrite = { locatorString in
            work.applyDebouncedReadiumLocator(locatorString)
            try? context.save()
            // Durable dirty flag only — does not schedule an immediate package
            // syncUp (that still waits for flush/close/background or launch).
            FolderSyncService.markDirty()
        }
        book.onLocatorChange = { locator in
            guard let string = locator.persistenceString else { return }
            // note() may call onDebouncedWrite immediately or schedule a trailing write.
            progressPersistence.note(
                locatorString: string,
                totalProgression: locator.locations.totalProgression
            )
        }
        // Finish a completed work only at the navigator's true end state — the
        // final resource visible with its trailing edge at 1.0 — never from a
        // progression threshold (A7-F1). WIPs stay manual, so an ongoing read
        // is never marked finished (and later freed) out from under the user.
        book.onReachedPublicationEnd = {
            // Keep locator + progressModifiedAt in sync for merge; full shelf stamp
            // only when we actually auto-finish (below).
            if let string = book.currentLocator?.persistenceString {
                work.applyDebouncedReadiumLocator(string)
                progressPersistence.markPersisted(
                    locatorString: string,
                    totalProgression: book.currentLocator?.locations.totalProgression
                )
                FolderSyncService.markDirty()
            }
            guard work.isComplete, !work.isFinished else {
                try? context.save()
                return
            }
            work.isFinished = true
            // Full stamp: Continue Reading + lastModifiedAt for folder-sync dirty.
            work.markProgressModified(Date())
            try? context.save()
        }
        book.onOpenExternalURL = { url in
            if openCommentsLinkIfMatching(url) { return }
            // AO3 links in the work (e.g. the preface's tag links) route to the matching
            // native screen where one exists; everything else opens the in-app web view.
            router.openAO3Link(url)
        }
        let initialLocator = Locator(persistenceString: work.readiumLocator)
        // No Readium progress yet but a legacy position exists → resume at that chapter.
        let fallbackSpineIndex = initialLocator == nil && work.lastSpineIndex > 0
            ? work.lastSpineIndex : nil
        let config = EPUBNavigatorViewController.Configuration(
            preferences: preferences,
            // Adds Highlight / Add Note to the system selection menu next to
            // Copy, Look Up and friends.
            editingActions: ReadiumBook.selectionEditingActions,
            fontFamilyDeclarations: fontFamilyDeclarations,
            readiumCSSRSProperties: ReadiumReaderStyleMapper.readingSystemProperties
        )
        await book.open(fileURL: work.fileURL, initialLocator: initialLocator,
                        fallbackSpineIndex: fallbackSpineIndex, config: config)
    }
}

// Split out to keep `ReadiumReaderView`'s own body under SwiftLint's
// type_body_length gate — `private` state is still reachable from an extension
// in the same file, just not from the primary type declaration SwiftLint measures.
extension ReadiumReaderView {
    /// Only while chrome is hidden — the position card's own scrub slider already
    /// covers this when chrome is visible, so showing both would be redundant.
    @ViewBuilder
    private var scrollIndicatorLayer: some View {
        let pos = book.readingPosition
        if !chromeVisible, pos?.pageBarReady == true, let pageCount = pos?.pageCount, pageCount > 1 {
            ReaderScrollIndicator(
                page: min(pageCount, max(1, pos?.page ?? 1)),
                pageCount: pageCount,
                tint: themeManager.effectiveTint
            )
            .padding(.trailing, 3)
            .padding(.vertical, book.pageBoxChromeSafeTop + 24)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: chromeVisible)
        }
    }
}

/// Reader behaviour that isn't the view hierarchy itself: Apple-Music-style
/// speech chapter skip / hold-seek, the position card's label inputs, the
/// scrub slider's live seek, and kudos. Split out purely for navigability —
/// same file, so the `private` members above stay reachable and nothing
/// about access levels or behaviour changes.
extension ReadiumReaderView {

    // MARK: Contents sheet helpers

    /// Opens the note editor queued by Contents' **Add Note**, now that the
    /// panel sheet has finished dismissing. A no-op for every other way the
    /// panel closes, which is why it can hang off the shared `onDismiss`.
    private func presentPendingNoteEditor() {
        guard let pending = pendingNoteAfterPanelDismiss else { return }
        pendingNoteAfterPanelDismiss = nil
        editingNote = pending
    }

    /// First Readium locator of a chapter — the anchor for Contents' swipe
    /// actions, which act on the chapter's start rather than the live position.
    /// nil until `positionsByReadingOrder` has loaded, which is what gates those
    /// actions from appearing at all (see `ReaderContentsSheet`).
    private func chapterStartLocator(for section: ReaderSection) -> Locator? {
        guard book.positionsByReadingOrder.indices.contains(section.spineIndex) else { return nil }
        return book.positionsByReadingOrder[section.spineIndex].first
    }

    // MARK: Annotation lookups

    /// This work's live bookmarks / highlights / notes, in book order.
    private var annotations: [ReadingAnnotation] {
        allAnnotations.filter { $0.work?.id == work.id && !$0.isPendingDeletion }
    }

    private var bookmarkAnnotations: [ReadingAnnotation] {
        annotations.filter { $0.kind == .bookmark }
    }

    /// All in-book highlights (with or without a note). Bare marks used to be
    /// invisible here, which left no sheet-based path to delete them.
    private var noteAnnotations: [ReadingAnnotation] {
        annotations.filter { $0.kind == .highlight }
    }

    /// The Readium position (1-based, publication-wide) the reader is on.
    /// This is the page's identity, so bookmarking can toggle exactly rather
    /// than fuzzily matching progressions.
    private var currentReadingPosition: Int? {
        book.currentLocator?.locations.position
    }

    /// The bookmark on the current page, if one exists — drives the round
    /// button's filled/outline state and makes the tap a toggle.
    private var bookmarkAtCurrentPosition: ReadingAnnotation? {
        guard let position = currentReadingPosition else { return nil }
        return bookmarkAnnotations.first {
            Locator(persistenceString: $0.locatorString)?.locations.position == position
        }
    }

    // MARK: Contents / Display sheet

    private var readerSheetTitle: String {
        switch router.panel {
        case .readerChapters: "Contents"
        case .readerFind: "Find in Work"
        default: "Display & Themes"
        }
    }

    private var readerSheet: some View {
        NavigationStack {
            Group {
                if router.panel == .readerChapters {
                    ReaderContentsSheet(
                        segment: $contentsSegment,
                        sections: book.sections,
                        bookmarks: bookmarkAnnotations,
                        notes: noteAnnotations,
                        chapterStartPercent: { section in
                            guard let locator = chapterStartLocator(for: section),
                                  let progression = locator.locations.totalProgression
                            else { return nil }
                            return Int((progression * 100).rounded())
                        },
                        onSelectChapter: { section in
                            book.go(toSpineIndex: section.spineIndex)
                            router.panel = .none
                        },
                        onBookmarkChapter: { section in
                            guard let locator = chapterStartLocator(for: section) else { return }
                            addBookmark(at: locator)
                        },
                        onAddNoteToChapter: { section in
                            guard let locator = chapterStartLocator(for: section),
                                  let bookmark = addBookmark(at: locator)
                            else { return }
                            // Queue rather than present: the panel's `onDismiss`
                            // opens the editor once Contents is actually gone.
                            pendingNoteAfterPanelDismiss = bookmark
                            router.panel = .none
                        },
                        onSelectAnnotation: goToAnnotation,
                        onDeleteAnnotation: deleteAnnotation
                    )
                } else if router.panel == .readerFind {
                    ReaderSearchView(
                        model: searchModel,
                        publication: book.publication,
                        sections: book.sections,
                        // Matched by href against `book.sections`, the same basis
                        // `ReaderSearchGrouping` matches results against — not
                        // `readingPosition.chapter`, which is 1 + an index into
                        // `positionsByReadingOrder`. That array can have fewer
                        // entries than `book.sections` (any spine item with zero
                        // Readium positions is absent from it), so the two "chapter
                        // index" spaces can silently drift apart after such a gap.
                        // This was why "This Chapter" only pinned first sometimes.
                        currentSpineIndex: currentSpineIndex,
                        onSelect: { locator in
                            book.go(to: locator)
                            router.panel = .none
                        },
                        onBookmark: { locator in addBookmark(at: locator) }
                    )
                } else {
                    ReaderOptionsForm()
                }
            }
            .navigationTitle(readerSheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { router.panel = .none }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        // Annotation rows and the segmented control tint from the theme, not the
        // raw accent, so Sepia keeps its warm brown.
        .tint(themeManager.effectiveTint)
        .preferredColorScheme(readerTheme.colorScheme)
    }
    private func handleSpeechSkipBack() {
        guard let pos = book.readingPosition else { return }
        switch ReaderSpeechSkip.backwardAction(
            page: pos.page,
            chapter: pos.chapter,
            chapterCount: pos.chapterCount
        ) {
        case .restartChapter:
            goToSpineChapterStart(pos.chapter, resumePlaying: speech.isPlaying)
            playSpeechChapterHaptic()
        case .previousChapter:
            goToSpineChapterStart(pos.chapter - 1, resumePlaying: speech.isPlaying)
            playSpeechChapterHaptic()
        case .none:
            break
        }
    }

    private func handleSpeechSkipForward() {
        guard let pos = book.readingPosition else { return }
        switch ReaderSpeechSkip.forwardAction(chapter: pos.chapter, chapterCount: pos.chapterCount) {
        case .nextChapter:
            goToSpineChapterStart(pos.chapter + 1, resumePlaying: speech.isPlaying)
            playSpeechChapterHaptic()
        case .none:
            break
        }
    }

    /// 1-based spine chapter → first Readium position; re-anchors TTS.
    private func goToSpineChapterStart(_ chapter1Based: Int, resumePlaying: Bool) {
        let index = chapter1Based - 1
        guard book.positionsByReadingOrder.indices.contains(index),
              let first = book.positionsByReadingOrder[index].first
        else { return }
        book.go(to: first)
        // Keep a paused session paused at the new chapter; only autoplay if we
        // were already speaking.
        speech.reanchor(to: first, resumePlaying: resumePlaying)
    }

    private func handleSpeechSeekHoldStart(forward: Bool) {
        speechSeekWasPlaying = speech.isPlaying
        speechSeekHolding = true
        if speech.isPlaying {
            speech.pause()
        }
        // First seek step is the hold control's immediate first tick.
    }

    private func handleSpeechSeekHoldTick(forward: Bool) {
        guard let positions = book.currentChapterPositions, positions.count > 1 else { return }
        // Never index the positions list with visual page-1 (mixed metrics).
        // Prefer the live locator's global position; else map visual→progression
        // the same way the chapter scrub slider does.
        let currentIdx: Int = {
            if let globalPos = book.currentLocator?.locations.position,
               let first = positions.first?.locations.position {
                return max(0, min(positions.count - 1, globalPos - first))
            }
            if let progression = book.currentLocator?.locations.progression, positions.count > 1 {
                let idx = Int((progression * Double(positions.count - 1)).rounded())
                return max(0, min(positions.count - 1, idx))
            }
            if let pos = book.readingPosition {
                return ReaderPageMetrics.positionIndex(
                    visualPage: pos.page,
                    visualPageCount: pos.pageCount,
                    positionCount: positions.count
                )
            }
            return 0
        }()
        let delta = forward ? 1 : -1
        guard let newIdx = ReaderSpeechSkip.seekIndex(
            current: currentIdx,
            count: positions.count,
            delta: delta
        ) else { return }
        let locator = positions[newIdx]
        book.go(to: locator)
        speech.noteSeekLocator(locator)
        playSpeechSeekTickHaptic()
    }

    private func handleSpeechSeekHoldEnd() {
        guard speechSeekHolding else { return }
        speechSeekHolding = false
        speech.reanchor(to: book.currentLocator, resumePlaying: speechSeekWasPlaying)
        speechSeekWasPlaying = false
    }

    /// The AO3 story chapter the reader is currently on, for the chapter-aware
    /// Comments entry and the position card's chapter line. `pos.chapter - 1` is
    /// the current spine index; the section list normalizes it past Preface/
    /// Summary/Afterword. nil (→ Comments opens on All) until a position and
    /// built sections both exist.
    private var currentAO3Chapter: Int? {
        guard let pos = book.readingPosition, !book.sections.isEmpty else { return nil }
        return book.sections.ao3StoryChapter(forSpineIndex: pos.chapter - 1)
    }

    /// The position card's label lines, built from `book.readingPosition` +
    /// `book.remainingPositions` — no new requests, no new persistence.
    private var positionSummary: ReaderPositionSummary? {
        guard let pos = book.readingPosition else { return nil }
        let remaining = book.remainingPositions
        return ReaderPositionSummary(
            page: pos.page, pageCount: pos.pageCount, percent: pos.percent,
            place: .resolve(chapter: pos.chapter, chapterCount: pos.chapterCount,
                            sections: book.sections,
                            postedChapterTotal: SavedWork.totalChapterCount(from: work.chapters)),
            remainingInChapter: remaining?.chapter, remainingInWork: remaining?.work
        )
    }

    /// Pushes the slider to the reader's live position while the user isn't
    /// dragging it, so it tracks normal reading without fighting the drag.
    /// While the page bar is not ready, leave the thumb alone — forcing 0 from
    /// the stub pageCount:1 readingPosition was a next/back snap on the slider.
    private func syncSliderFromPosition(_ pos: ReadiumBook.ReadingPosition?) {
        guard !isEditingSlider, let pos, pos.pageBarReady, pos.pageCount > 0 else { return }
        // A single-page chapter has nowhere left to go — page 1 of 1 is both the
        // start and the end, so the bar should read full, not empty.
        sliderValue = pos.pageCount > 1 ? Double(pos.page - 1) / Double(pos.pageCount - 1) : 1
    }

    /// Seeks the page under the thumb *while* dragging, so the text scrubs with
    /// the slider (Books-style) instead of only jumping on release. Rate-limited
    /// two ways — only when the rounded page actually changes, and at most once
    /// per `scrubSeekInterval` — because a fast drag across a long chapter would
    /// otherwise queue a `go(to:)` per intermediate page. `syncSliderFromPosition`
    /// stays suppressed while editing, so these seeks can't fight the thumb.
    private func handleScrubSeek() {
        guard isEditingSlider, !book.isLocatorIngestionBlocked, !isDismissingByDrag else { return }
        guard book.pageBarReady, book.visualPageCount != nil else { return }
        let pageCount = book.readingPosition?.pageCount ?? 0
        guard pageCount > 1 else { return }
        let page = ReaderChapterScrub.page(sliderValue: sliderValue, pageCount: pageCount)
        // Only when the rounded page actually changes — many slider samples map
        // to the same page. Backpressure past that is the seek's own job
        // (`scrubToProgressionInCurrentResource` coalesces to latest-wins), not
        // a fixed time gate here, which only ever added lag of its own.
        guard page != lastScrubSeekPage else { return }
        lastScrubSeekPage = page
        book.scrubToProgressionInCurrentResource(
            ReaderPageMetrics.progression(page: page, pageCount: pageCount)
        )
    }

    /// Write-through binding for the position card's slider: stores the thumb
    /// value, then live-seeks. Deliberately *not* an `.onChange(of: sliderValue)`
    /// on `body` — this view already carries enough modifiers that one more
    /// blew the SwiftUI type-checker's budget (see the `colorBarDismissToken`
    /// note for the same problem solved the same way).
    private var scrubBinding: Binding<Double> {
        Binding(
            get: { sliderValue },
            set: { newValue in
                sliderValue = newValue
                handleScrubSeek()
            }
        )
    }

    /// Live-seeks during the drag (`handleScrubSeek`) and commits the exact page
    /// on release — the release seek still runs unconditionally, since the last
    /// live one may have been rate-limited away short of where the thumb ended.
    /// On begin, freeze a scrub-origin tick so the user can return to cancel.
    private func handleSliderEditingChanged(_ editing: Bool) {
        if editing {
            isEditingSlider = true
            book.isScrubbing = true
            sliderScrubOrigin = sliderValue
            // Seed with where we already are, so the first tiny drag inside the
            // starting page doesn't fire a seek to the page we're on — which in
            // scrolled mode would snap the text to that page's top edge.
            lastScrubSeekPage = book.readingPosition?.page
            return
        }
        isEditingSlider = false
        book.isScrubbing = false
        sliderScrubOrigin = nil
        lastScrubSeekPage = nil
        // Ignore scrub commit while dismiss freeze / exit latch is up — a release
        // that races with swipe-down must not seek the navigator mid-exit.
        guard !book.isLocatorIngestionBlocked, !isDismissingByDrag else { return }
        let pageCount = book.readingPosition?.pageCount ?? 0
        guard pageCount > 0 else { return }
        let page = ReaderChapterScrub.page(sliderValue: sliderValue, pageCount: pageCount)
        // Swipe-scale seek once page bar is ready.
        if book.pageBarReady, book.visualPageCount != nil {
            book.goToProgressionInCurrentResource(
                ReaderPageMetrics.progression(page: page, pageCount: pageCount)
            )
            return
        }
        // Position-list fallback when visual metrics aren't available yet.
        guard let positions = book.currentChapterPositions, !positions.isEmpty else { return }
        let index = ReaderChapterScrub.positionIndex(
            sliderValue: sliderValue,
            pageCount: positions.count
        )
        book.go(to: positions[index])
    }

    private func giveKudos(workID: Int) {
        guard !kudosWorking, !kudosGiven else { return }
        kudosWorking = true
        Task {
            do {
                kudosBanner = try await auth.giveKudos(workID: workID)
                kudosGiven = true
            } catch {
                kudosBanner = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            kudosWorking = false
        }
    }

    private var kudosBannerPresented: Binding<Bool> {
        Binding(get: { kudosBanner != nil }, set: { if !$0 { kudosBanner = nil } })
    }
}


// MARK: - Fan menu items

/// The fan menu's labelled pills and its share target.
///
/// An extension purely so `ReadiumReaderView`'s own body stays inside SwiftLint's
/// `type_body_length` limit — adding the two conversion pills pushed it past the
/// error threshold. Kept in this file so it can still reach the view's `private`
/// state (Swift allows that for same-file extensions), which means no visibility
/// had to widen. Pure code movement.
extension ReadiumReaderView {
    /// The fan's labelled menu pills: Contents, Bookmarks & Highlights, Find in Work,
    /// Comments (AO3-backed works only — not in the reference design's four, but
    /// dropping it would lose an existing feature, which the brief forbids), and
    /// Themes & Settings.
    private var fanPills: [ReaderFanMenuPill] {
        var pills: [ReaderFanMenuPill] = [
            ReaderFanMenuPill(id: "contents", title: contentsPillTitle, systemImage: "list.bullet") {
                contentsSegment = .chapters
                router.panel = .readerChapters
            },
            ReaderFanMenuPill(id: "bookmarks", title: "Bookmarks & Highlights", systemImage: "bookmark") {
                contentsSegment = .bookmarks
                router.panel = .readerChapters
            },
            ReaderFanMenuPill(
                id: "find", title: "Find in Work", systemImage: "magnifyingglass",
                // Readium synthesises a content search service for EPUBs; if this
                // publication somehow has none, dim the control rather than open a
                // box that can never return anything.
                isEnabled: ReaderSearchModel.isSearchable(book.publication)
            ) {
                router.panel = .readerFind
            }
        ]
        if ao3WorkID != nil {
            pills.append(ReaderFanMenuPill(
                id: "comments", title: "Comments", systemImage: "bubble.left.and.bubble.right"
            ) {
                showingComments = true
            })
        }
        if WorkReconversion.candidate(for: work)?.isStale == true {
            pills.append(ReaderFanMenuPill(
                id: "rebuild", title: "Rebuild from Original", systemImage: "arrow.triangle.2.circlepath"
            ) {
                Task { await rebuildFromOriginal() }
            })
        }
        pills.append(ReaderFanMenuPill(id: "settings", title: "Themes & Settings", systemImage: "textformat.size") {
            router.panel = .readerDisplay
        })
        return pills
    }

    private var contentsPillTitle: String {
        guard let percent = book.totalProgression.map({ Int(($0 * 100).rounded()) }) else { return "Contents" }
        return "Contents · \(percent)%"
    }

    /// What the fan's `ShareLink` slot offers, best available first.
    ///
    /// This used to be `ao3WorkID.map(AO3AuthService.workURL)`, so a work with no AO3
    /// id had no share slot at all — and a non-AO3 work's menu is already the sparse
    /// one, since Kudos and Comments cannot apply to it. There is always *something*
    /// worth sharing:
    ///
    /// 1. the AO3 page, when the work has one;
    /// 2. the original posting on whatever site it came from (a fanfiction.net story
    ///    link, say), which for a deleted work is often the only citation left;
    /// 3. failing any link, the EPUB itself — which is the whole point of a
    ///    community copy, and the only way to hand it on.
    private var shareURL: URL? {
        if let ao3WorkID { return AO3AuthService.workURL(ao3WorkID) }
        if let source = URL(string: work.sourceURL), source.scheme?.hasPrefix("http") == true {
            return source
        }
        return WorkReaderPreparation.hasReadableEPUB(for: work) ? work.fileURL : nil
    }

    /// The file this work was converted from, when it was converted and the original is
    /// still archived. Drives the "Original File" pill.
    private var originalDocumentURL: URL? {
        WorkReconversion.candidate(for: work)?.originalURL
    }
}

#endif
