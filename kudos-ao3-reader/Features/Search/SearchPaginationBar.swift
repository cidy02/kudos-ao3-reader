import SwiftUI

/// Page navigation for AO3 results.
///
/// **Why this isn't a numbered page bar.** AO3's own pagination is a web control —
/// `1 … 5 6 7 … 142` — and porting it verbatim made the app's most-used list read
/// as a website embedded in a native app. Numbered bars solve a problem the web has
/// and iOS doesn't: no gesture layer, no sheets, and a mouse that can hit a 20px
/// target. On a phone that shape spends the full width of a row on ten tap targets,
/// eight of which are wrong, and still can't reach page 2,731 of 5,000.
///
/// What replaced it is the split every first-party app makes between the *common*
/// move and the *rare* one:
///
/// - **Common — one page at a time.** Two chevrons, and that is the whole visible
///   control. This is Books' chapter navigation and Photos' day stepper: the app
///   assumes you are reading forwards.
/// - **Rare — go somewhere far away.** The centre reads `Page 3 of 5,000`, and
///   tapping it opens the page sheet: a number field, the ten nearby pages as
///   tiles, and First / Last. The field is what addresses page 4,017 exactly —
///   the scrubber this replaced (artboard 1k) could only ever get near it,
///   because one thumb pixel is several pages on a long list.
///
/// So the bar shows your position, always, in words — which the numbered version
/// never actually did — and holds no chrome for a jump you make once a session.
///
/// The pagination *logic* is untouched: `navigationPage` and `abbreviate` are the
/// same functions, still unit-tested, now feeding a different presentation.
struct SearchPaginationBar: View {
    let currentPage: Int
    let totalPages: Int
    /// A page fetch is in flight. Paging is a network round trip behind a 0.6s
    /// politeness pacer, and until now *nothing* moved when you tapped an arrow:
    /// the previous page stayed on screen, unchanged, for the whole wait, so the
    /// tap read as ignored and the app as slow. It also let a second tap queue a
    /// second fetch a slot behind the first, which genuinely made it slower.
    var isLoading: Bool = false
    /// The subject the results belong to, so the sheet's confirm button and its
    /// selected tile take the same hue as the page around them. Nil falls back
    /// to the app accent.
    var palette: SubjectPalette?
    let onSelect: (Int) -> Void

    @State private var showingPageSheet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            navButton(.backward)

            Button { showingPageSheet = true } label: {
                positionLabel
            }
            .buttonStyle(.plain)
            .disabled(totalPages <= 1 || isLoading)
            .accessibilityLabel("Page \(currentPage) of \(totalPages)")
            .accessibilityHint(totalPages > 1 ? "Opens the page picker." : "")
            // An adjustable element so VoiceOver users can page with a swipe up or
            // down instead of hunting for the two chevrons — the same gesture the
            // system's own steppers answer to.
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment where currentPage < totalPages: onSelect(currentPage + 1)
                case .decrement where currentPage > 1: onSelect(currentPage - 1)
                default: break
                }
            }

            navButton(.forward)
        }
        .frame(maxWidth: .infinity)
        // Paging is a discrete move through a list; the tick is the same feedback
        // a picker gives, and it fires on the value actually changing rather than
        // on the tap, so a tap on a disabled edge stays silent.
        .sensoryFeedback(.selection, trigger: currentPage)
        .sheet(isPresented: $showingPageSheet) {
            PageJumpSheet(
                currentPage: currentPage,
                totalPages: totalPages,
                palette: palette,
                onSelect: onSelect
            )
        }
    }

    /// The position, in words. Abbreviated only past 999 so the row can't be
    /// widened off the card by a five-digit total.
    private var positionLabel: some View {
        HStack(spacing: 4) {
            Text("Page ")
                .foregroundStyle(.secondary)
                + Text("\(currentPage)")
                .foregroundStyle(.primary)
                .fontWeight(.semibold)
                + Text(" of \(Self.abbreviate(totalPages))")
                .foregroundStyle(.secondary)

            if isLoading {
                // Same slot as the disclosure arrows, so the pill doesn't resize
                // and the row doesn't shift under the thumb that just tapped it.
                ProgressView()
                    .controlSize(.mini)
            } else if totalPages > 1 {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.subheadline)
        .monospacedDigit()
        // Rolls the digits rather than cutting to the new number — the motion is
        // what says "you moved", which a numbered bar needed a filled pill to say.
        .contentTransition(.numericText())
        .animation(reduceMotion ? nil : .snappy, value: currentPage)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .contentShape(Capsule())
    }

    private func navButton(_ direction: Direction) -> some View {
        let isBackward = direction == .backward
        let atEdge = isBackward ? currentPage <= 1 : currentPage >= totalPages
        // Disabled while a fetch is running: a second tap used to queue a second
        // request one pacer slot behind the first, so impatience made it slower.
        let enabled = !atEdge && !isLoading
        let page = Self.navigationPage(
            direction, longPress: false, currentPage: currentPage, totalPages: totalPages
        )
        let endPage = Self.navigationPage(
            direction, longPress: true, currentPage: currentPage, totalPages: totalPages
        )
        let endLabel = isBackward ? "First page" : "Last page"

        return Button {
            onSelect(page)
        } label: {
            Image(systemName: isBackward ? "chevron.backward" : "chevron.forward")
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 34, minHeight: 34)
                .background(.regularMaterial, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        // `.disabled` rather than the old hand-rolled colours: it dims the label,
        // blocks the tap and tells VoiceOver, all with the system's own treatment.
        .opacity(enabled ? 1 : 0.35)
        .minimumHitTarget()
        .contextMenu {
            // Long-press to reach an end, unchanged in behaviour. Gated on the
            // arrow being live so a disabled edge's long-press stays inert rather
            // than offering an action that does nothing.
            if enabled {
                Button(endLabel) { onSelect(endPage) }
            }
        }
        .accessibilityLabel(isBackward ? "Previous page" : "Next page")
    }

    enum Direction {
        case backward
        case forward
    }

    static func navigationPage(_ direction: Direction, longPress: Bool,
                               currentPage: Int, totalPages: Int) -> Int {
        switch (direction, longPress) {
        case (.backward, true):
            1
        case (.backward, false):
            max(1, currentPage - 1)
        case (.forward, true):
            totalPages
        case (.forward, false):
            min(totalPages, currentPage + 1)
        }
    }

    static func abbreviate(_ page: Int) -> String {
        switch page {
        case ..<1000: "\(page)"
        case ..<1_000_000: trimmed(Double(page) / 1000) + "k"
        default: trimmed(Double(page) / 1_000_000) + "m"
        }
    }

    /// One decimal place, dropping a trailing ".0" (1.0 → "1", 1.2 → "1.2").
    private static func trimmed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
    }

}

/// The long jump. A slider, because that is how iOS addresses a long ordered set —/// Artboard 1k's page sheet: a number field, the ten nearby pages as tiles, and
/// First / Last for the ends.
///
/// **Why this replaced a scrubber.** The slider it supplanted made a real
/// argument — a thumb travelling 300pt can address 5,000 pages, and ten tiles
/// cannot. The spec's answer is that the *field* addresses all 5,000, and it
/// does so exactly, which is what a thumb never could: one thumb pixel is
/// several pages on a long list, so the slider was good at "somewhere around
/// there" and bad at "page 4,017". The tiles cover the other real case —
/// stepping a few pages from where you are — where a slider is fiddliest.
///
/// **Nothing loads until you confirm.** Paging is a network fetch behind a
/// politeness pacer; a tile that navigated on tap would fire a request per
/// tile-tap. Tiles and First/Last stage a draft, and the confirm button commits
/// it once.
extension SearchPaginationBar {
    /// The pages the sheet offers as tiles: `count` of them, centred on `page`
    /// and slid back inside the range at either end rather than truncated — so
    /// page 2 of 3,216 still offers ten choices instead of two.
    ///
    /// Pure, and separate from the view, because the off-by-one at the ends is
    /// the only part of this control worth a test.
    static func nearbyPageWindow(around page: Int, totalPages: Int, count: Int = 10) -> [Int] {
        guard totalPages > 0 else { return [] }
        let windowSize = min(count, totalPages)
        let centred = page - (windowSize - 1) / 2
        let start = max(1, min(centred, totalPages - windowSize + 1))
        return Array(start ..< (start + windowSize))
    }
}

private struct PageJumpSheet: View {
    let currentPage: Int
    let totalPages: Int
    var palette: SubjectPalette?
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @State private var draftText: String
    @FocusState private var fieldFocused: Bool

    init(currentPage: Int, totalPages: Int, palette: SubjectPalette?, onSelect: @escaping (Int) -> Void) {
        self.currentPage = currentPage
        self.totalPages = totalPages
        self.palette = palette
        self.onSelect = onSelect
        _draftText = State(initialValue: String(currentPage))
    }

    private var resolvedPalette: SubjectPalette {
        palette ?? themeManager.appTheme.subjectPalette(hue: themeManager.scopeHue)
    }

    /// The typed page, clamped. An empty or unparseable field reads as the page
    /// you are already on, so confirming a half-typed number never jumps
    /// somewhere arbitrary — it just does nothing.
    private var draftPage: Int {
        guard let typed = Int(draftText), typed > 0 else { return currentPage }
        return min(typed, max(totalPages, 1))
    }

    private var nearbyPages: [Int] {
        SearchPaginationBar.nearbyPageWindow(around: draftPage, totalPages: totalPages)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(themeManager.appTheme.glassStroke(0.10))

            VStack(alignment: .leading, spacing: 18) {
                fieldSection
                nearbySection
                endsRow
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        #if os(iOS)
        .presentationDetents([.height(430)])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var header: some View {
        HStack(spacing: 9) {
            GlassCircleButton(accessibilityName: "Cancel", action: { dismiss() }) {
                Image(systemName: "xmark")
            }

            Text("Go to page")
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            GlassCircleButton(
                isAccented: true,
                palette: resolvedPalette,
                accessibilityName: "Go to page \(draftPage)",
                action: {
                    if draftPage != currentPage { onSelect(draftPage) }
                    dismiss()
                }
            ) {
                Image(systemName: "checkmark")
            }
            .disabled(draftPage == currentPage)
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .bold))
            .tracking(1.26)
            .foregroundStyle(.secondary)
    }

    private var fieldSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Page number")
            HStack(spacing: 8) {
                TextField("Page", text: $draftText)
                    .font(.system(size: 16))
                    .monospacedDigit()
                    .focused($fieldFocused)
                    .textFieldStyle(.plain)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    // Digits only, filtered on the way in rather than validated on
                    // the way out: a paste of "page 12" should become 12, not an
                    // error, and a non-ASCII digit should not survive either.
                    .onChange(of: draftText) { _, typed in
                        let digits = typed.filter { $0.isASCII && $0.isNumber }
                        if digits != typed { draftText = digits }
                    }

                Text("of \(totalPages.formatted())")
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(fieldBackground)
        }
    }

    private var fieldBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        return shape
            .fill(themeManager.appTheme.glassFill(0.08))
            .overlay(shape.strokeBorder(themeManager.appTheme.glassStroke(0.14), lineWidth: 0.5))
    }

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Nearby")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(nearbyPages, id: \.self) { page in
                    Button { draftText = String(page) } label: {
                        Text(page.formatted())
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(tileBackground(isSelected: page == draftPage))
                            .foregroundStyle(page == draftPage ? resolvedPalette.accentOnFill : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Page \(page)")
                    .accessibilityAddTraits(page == draftPage ? .isSelected : [])
                }
            }
        }
    }

    private func tileBackground(isSelected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        return shape
            .fill(isSelected ? resolvedPalette.chipFill : themeManager.appTheme.glassFill(0.08))
            .overlay(
                shape.strokeBorder(
                    isSelected ? resolvedPalette.chipStroke : themeManager.appTheme.glassStroke(0.13),
                    lineWidth: 0.5
                )
            )
    }

    /// The two pages a long list makes unreachable by stepping. Last states its
    /// number, because "how many pages are there" is the other thing you came to
    /// this sheet to find out.
    private var endsRow: some View {
        HStack(spacing: 8) {
            endButton("First page") { draftText = "1" }
                .disabled(draftPage <= 1)
            endButton("Last (\(totalPages.formatted()))") { draftText = String(max(totalPages, 1)) }
                .disabled(draftPage >= totalPages)
        }
    }

    private func endButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(tileBackground(isSelected: false))
                .foregroundStyle(Color.primary)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Middle of a long list") {
    SearchPaginationBar(currentPage: 3, totalPages: 5000) { _ in }
        .padding()
}

#Preview("First page") {
    SearchPaginationBar(currentPage: 1, totalPages: 12) { _ in }
        .padding()
}

#Preview("Single page") {
    SearchPaginationBar(currentPage: 1, totalPages: 1) { _ in }
        .padding()
}
