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
///   tapping it opens a scrubber. That is Books' "Go to Page" and the Music
///   scrubber — a slider is how iOS moves through a long ordered set, because a
///   thumb travelling 300pt can address 5,000 pages and a row of pills cannot.
///
/// So the bar shows your position, always, in words — which the numbered version
/// never actually did — and holds no chrome for a jump you make once a session.
///
/// The pagination *logic* is untouched: `navigationPage`, `compactPageWindow` and
/// `abbreviate` are the same functions, still unit-tested, now feeding a different
/// presentation.
struct SearchPaginationBar: View {
    let currentPage: Int
    let totalPages: Int
    let onSelect: (Int) -> Void

    @State private var showingScrubber = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            navButton(.backward)

            Button { showingScrubber = true } label: {
                positionLabel
            }
            .buttonStyle(.plain)
            .disabled(totalPages <= 1)
            .accessibilityLabel("Page \(currentPage) of \(totalPages)")
            .accessibilityHint(totalPages > 1 ? "Opens the page scrubber." : "")
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
        .sheet(isPresented: $showingScrubber) {
            PageScrubberSheet(
                currentPage: currentPage,
                totalPages: totalPages,
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

            if totalPages > 1 {
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
        let enabled = isBackward ? currentPage > 1 : currentPage < totalPages
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

    /// Page window around the current page, valid for ANY input pair. Pagination
    /// state is remote-derived, and `currentPage ≤ totalPages` currently holds only
    /// because `AO3Client.paginationTotal(in:currentPage:)` happens to seed its
    /// max-scan with the requested page — an accident of the parser, not a
    /// contract. Unclamped, a stale `currentPage` past a shrunken `totalPages`
    /// (e.g. 7 of 5) would build `6...5` and trap at render time.
    static func compactPageWindow(currentPage: Int, totalPages: Int) -> ClosedRange<Int> {
        let last = max(totalPages, 1)
        let anchor = min(max(currentPage, 1), last)
        return max(1, anchor - 1) ... min(last, anchor + 1)
    }
}

/// The long jump. A slider, because that is how iOS addresses a long ordered set —
/// a thumb crossing 300pt can reach any of 5,000 pages, where a rail of pills would
/// need 5,000 taps' worth of scrolling.
///
/// **The slider does not load anything while you drag.** Pagination is a network
/// fetch, so a live-bound slider would fire a request per tick and rate-limit the
/// user out of AO3 in one gesture. The sheet holds a draft, previews it in the
/// readout, and commits once — which is also why it can afford to be a slider at
/// all rather than a stepper.
private struct PageScrubberSheet: View {
    let currentPage: Int
    let totalPages: Int
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: Double

    init(currentPage: Int, totalPages: Int, onSelect: @escaping (Int) -> Void) {
        self.currentPage = currentPage
        self.totalPages = totalPages
        self.onSelect = onSelect
        _draft = State(initialValue: Double(currentPage))
    }

    private var draftPage: Int {
        min(max(Int(draft.rounded()), 1), max(totalPages, 1))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                readout

                Slider(
                    value: $draft,
                    in: 1 ... Double(max(totalPages, 1)),
                    step: 1
                ) {
                    Text("Page")
                } minimumValueLabel: {
                    Text("1").font(.caption).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text(SearchPaginationBar.abbreviate(totalPages))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .disabled(totalPages <= 1)
                // A tick per page as the thumb passes it, like a picker — the
                // gesture's own feedback, not the page load's.
                .sensoryFeedback(.selection, trigger: draftPage)

                nearbyPages

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .navigationTitle("Go to Page")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Go") {
                            if draftPage != currentPage { onSelect(draftPage) }
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .disabled(draftPage == currentPage)
                    }
                }
        }
        #if os(iOS)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var readout: some View {
        VStack(spacing: 2) {
            Text("\(draftPage)")
                .font(.system(size: 48, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(draftPage)))
                .animation(reduceMotion ? nil : .snappy, value: draftPage)
            Text("of \(totalPages.formatted())")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Page \(draftPage) of \(totalPages)")
    }

    /// The pages either side of where the thumb currently sits — fine adjustment
    /// after a coarse drag, which a slider alone is bad at on a 5,000-page range.
    /// Reuses the same window helper the old bar used for its narrow fallback.
    private var nearbyPages: some View {
        let window = SearchPaginationBar.compactPageWindow(
            currentPage: draftPage, totalPages: totalPages
        )
        return HStack(spacing: 8) {
            Button("First") { draft = 1 }
                .disabled(draftPage == 1)

            Spacer(minLength: 8)

            ForEach(Array(window), id: \.self) { page in
                Button {
                    draft = Double(page)
                } label: {
                    Text("\(page)")
                        .font(.footnote.weight(page == draftPage ? .bold : .regular))
                        .monospacedDigit()
                        .frame(minWidth: 32, minHeight: 32)
                        .background(
                            Circle().fill(page == draftPage
                                ? AnyShapeStyle(.tint.opacity(0.18))
                                : AnyShapeStyle(.quaternary))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Page \(page)")
                .accessibilityAddTraits(page == draftPage ? [.isSelected] : [])
            }

            Spacer(minLength: 8)

            Button("Last") { draft = Double(max(totalPages, 1)) }
                .disabled(draftPage == totalPages)
        }
        .font(.footnote)
        .buttonStyle(.borderless)
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
