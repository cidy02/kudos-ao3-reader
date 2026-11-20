#if os(iOS)
import SwiftUI

/// The bottom floating card: page-within-chapter, a slider that seeks within the
/// chapter, and a summary line across the whole work.
///
/// When read-aloud is active, the mini player sits above a hairline separator
/// inside this same glass surface — one card, not a second floating bar. The
/// separator is omitted entirely when no mini player is provided.
///
/// While scrubbing, `pageLabel` should be the live preview from the thumb, and
/// `scrubOrigin` marks where the drag started (a `|` on the track) so the user
/// can return to that point to cancel. The thumb magnets to the origin when
/// nearby; the page digit and chapter duration ("8 min") use `tint` when the
/// preview page differs from the scrub origin.
/// The compact position bar of the Duo boards: the work's title and "Ch 7 of 20"
/// in one row, the slider, then "Page 4 of 18 · 21 min left" (T-562a).
struct ReaderPositionCardCompact: Equatable {
    let title: String
    let chapter: String
}

struct ReaderPositionCard<MiniPlayer: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accentInk) private var ink
    /// Current page (1-based) shown in "Page **N** of M".
    let page: Int
    /// Total pages in the chapter.
    let pageCount: Int
    /// Minutes left in chapter for " **N min** left in chapter"; nil hides the line.
    let chapterRemainingMinutes: Int?
    let workLine: String
    let tint: Color
    @Binding var sliderValue: Double
    /// Disabled (and drawn without a thumb-drag affordance) when the chapter has
    /// only one position — nothing to seek within.
    let sliderEnabled: Bool
    /// 0…1 thumb position when the scrub began; `nil` when not editing.
    let scrubOrigin: Double?
    /// When true, page **number** and chapter duration use theme tint (not suffixes).
    let scrubValuesEmphasized: Bool
    let onEditingChanged: (Bool) -> Void
    /// Non-nil draws the compact bar instead of the three-line card.
    let compact: ReaderPositionCardCompact?
    /// Optional read-aloud strip. Pass `EmptyView` (the default) when speech is
    /// stopped — the separator only appears when a real mini player is provided.
    @ViewBuilder private var miniPlayer: () -> MiniPlayer

    init(
        page: Int,
        pageCount: Int,
        chapterRemainingMinutes: Int?,
        workLine: String,
        tint: Color,
        sliderValue: Binding<Double>,
        sliderEnabled: Bool,
        scrubOrigin: Double? = nil,
        scrubValuesEmphasized: Bool = false,
        compact: ReaderPositionCardCompact? = nil,
        onEditingChanged: @escaping (Bool) -> Void,
        @ViewBuilder miniPlayer: @escaping () -> MiniPlayer = { EmptyView() }
    ) {
        self.page = page
        self.pageCount = pageCount
        self.chapterRemainingMinutes = chapterRemainingMinutes
        self.workLine = workLine
        self.tint = tint
        self._sliderValue = sliderValue
        self.sliderEnabled = sliderEnabled
        self.scrubOrigin = scrubOrigin
        self.scrubValuesEmphasized = scrubValuesEmphasized
        self.onEditingChanged = onEditingChanged
        self.compact = compact
        self.miniPlayer = miniPlayer
    }

    /// Full string for accessibility / value readout. Mirrors `pageTitleLabel`'s
    /// own "not ready yet" guard — without it VoiceOver announced the nonsense
    /// "Page 0 of 1" during the swipe-scale measuring window instead of a
    /// sentence that matches what's visually shown ("Page …").
    private var pageAccessibilityLabel: String {
        guard page >= 1, pageCount >= 1 else { return "Measuring pages" }
        return "Page \(page) of \(pageCount)"
    }

    private var showsMiniPlayer: Bool {
        MiniPlayer.self != EmptyView.self
    }

    /// Slider binding that snaps onto the origin `|` as soon as the preview
    /// page matches the origin page (not a tight track-distance threshold).
    private var snappingSliderValue: Binding<Double> {
        Binding(
            get: { sliderValue },
            set: { newValue in
                sliderValue = ReaderChapterScrub.snapped(
                    value: newValue,
                    toOrigin: scrubOrigin,
                    pageCount: pageCount
                )
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsMiniPlayer {
                miniPlayer()
                    .padding(.horizontal, SubjectMetrics.gutter)
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                // Only while the mini player is present — no orphan rule when
                // speech is stopped.
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 1)
                    .padding(.horizontal, SubjectMetrics.gutter)
            }

            if let compact {
                compactBody(compact)
            } else {
                standardBody
            }
        }
        .glassEffect(
            .regular,
            in: RoundedRectangle(
                cornerRadius: compact == nil ? SubjectMetrics.cornerRadius : Self.compactCornerRadius,
                style: .continuous
            )
        )
    }

    /// The Duo boards' bar radius (26 pt), against the iPhone card's 16 pt.
    static var compactCornerRadius: CGFloat { 26 }

    private var standardBody: some View {
        VStack(spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                // At the accessibility sizes the row broke every piece apart ("Pa / ge",
                // "98 / 0", "chap- / ter", seen at AX5): the page, then the time, each one
                // string that wraps between words.
                VStack(alignment: .leading, spacing: 2) {
                    pageTitleLabel
                    chapterTimeLabel
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    // Page digit + duration tint when scrubbing away from origin;
                    // "Page" / "of M" / "left in chapter" stay unemphasized.
                    pageTitleLabel
                    Spacer(minLength: 8)
                    chapterTimeLabel
                }
            }

            scrubSlider
                .disabled(!sliderEnabled)
                .accessibilityLabel("Seek within chapter")
                .accessibilityValue(pageAccessibilityLabel)

            Text(workLine)
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                // Shrink a little before truncating, so the longest reading stays
                // legible at large Dynamic Type sizes. Carried over from the
                // progress pill this card replaced (HIG wave, A-F: position
                // readout must not clip or truncate as text scales).
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, SubjectMetrics.gutter)
        .padding(.top, showsMiniPlayer ? 12 : 13)
        .padding(.bottom, 15)
    }

    private func compactBody(_ compact: ReaderPositionCardCompact) -> some View {
        VStack(spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                // Same reason as the card: at AX sizes a one-line row cuts the title to a word.
                VStack(alignment: .leading, spacing: 2) {
                    Text(compact.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(3)
                    Text(compact.chapter)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(compact.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Text(compact.chapter)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }

            scrubSlider
                .disabled(!sliderEnabled)
                .accessibilityLabel("Seek within chapter")
                .accessibilityValue(pageAccessibilityLabel)

            compactPositionLine
        }
        .padding(.horizontal, 18)
        .padding(.top, showsMiniPlayer ? 12 : 10)
        .padding(.bottom, 10)
    }

    /// "Page 4 of 18 · 21 min left": the digit and duration tint while scrubbing,
    /// as on the card.
    private var compactPositionLine: some View {
        let pageReady = page >= 1 && pageCount >= 1
        let digit = Text(pageReady ? "\(page)" : "…")
            .foregroundStyle(scrubValuesEmphasized ? AnyShapeStyle(ink) : AnyShapeStyle(.secondaryInk))
        var line = Text("Page ") + digit
        if pageReady { line = line + Text(" of \(pageCount)") }
        if let minutes = chapterRemainingMinutes {
            line = line + Text(" · ")
                + Text(ReaderTimeEstimate.durationLabel(minutes: minutes))
                    .foregroundStyle(scrubValuesEmphasized ? AnyShapeStyle(ink) : AnyShapeStyle(.secondaryInk))
                + Text(" left")
        }
        return line
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondaryInk)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            .minimumScaleFactor(0.75)
    }

    @ViewBuilder
    private var pageTitleLabel: some View {
        // page/pageCount <= 0 → measure not ready (never show fake "1 of 1").
        if page < 1 || pageCount < 1 {
            Text("Page …")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondaryInk)
                .monospacedDigit()
        } else if dynamicTypeSize.isAccessibilitySize {
            // One string, so it wraps between words. The digit keeps its tint; it gives up
            // the rolling-number transition a separate `Text` has at the ordinary sizes.
            (Text("Page ").foregroundStyle(.primary)
                + Text("\(page)").foregroundStyle(scrubValuesEmphasized ? ink : Color.primary)
                + Text(" of \(pageCount)").foregroundStyle(.primary))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Page ")
                    .foregroundStyle(.primary)
                Text("\(page)")
                    .foregroundStyle(scrubValuesEmphasized ? ink : Color.primary)
                    .contentTransition(.numericText())
                    .animation(.default, value: page)
                    .animation(.easeInOut(duration: 0.15), value: scrubValuesEmphasized)
                Text(" of \(pageCount)")
                    .foregroundStyle(.primary)
            }
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
        }
    }

    /// "8 min left in chapter" — only the duration ("8 min") takes theme tint.
    @ViewBuilder
    private var chapterTimeLabel: some View {
        if let minutes = chapterRemainingMinutes, dynamicTypeSize.isAccessibilitySize {
            (Text(ReaderTimeEstimate.durationLabel(minutes: minutes))
                .foregroundStyle(scrubValuesEmphasized ? AnyShapeStyle(ink) : AnyShapeStyle(.secondaryInk))
                + Text(" left in chapter").foregroundStyle(.secondaryInk))
                .font(.footnote)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        } else if let minutes = chapterRemainingMinutes {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(ReaderTimeEstimate.durationLabel(minutes: minutes))
                    .foregroundStyle(scrubValuesEmphasized ? AnyShapeStyle(ink) : AnyShapeStyle(.secondaryInk))
                    .contentTransition(.numericText())
                    .animation(.default, value: minutes)
                    .animation(.easeInOut(duration: 0.15), value: scrubValuesEmphasized)
                Text(" left in chapter")
                    .foregroundStyle(.secondaryInk)
            }
            .font(.footnote)
            .monospacedDigit()
        }
    }

    /// System slider with an optional origin tick (`|`) at the scrub start.
    private var scrubSlider: some View {
        Slider(value: snappingSliderValue, in: 0 ... 1, onEditingChanged: onEditingChanged)
            .tint(tint)
            .background {
                GeometryReader { geo in
                    if let origin = scrubOrigin, sliderEnabled {
                        // Thumb centers travel inset from the view edges; match that
                        // so the tick lines up with value 0…1.
                        // Approximate UISlider horizontal inset to thumb center.
                        let inset: CGFloat = 15
                        let usable = max(0, geo.size.width - inset * 2)
                        let x = inset + CGFloat(origin.clamped01) * usable
                        // Thin vertical bar — “where you started,” not a second thumb.
                        Capsule()
                            .fill(Color.secondary.opacity(0.85))
                            .frame(width: 2, height: 14)
                            .position(x: x, y: geo.size.height / 2)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
    }
}

private extension Double {
    var clamped01: Double { min(1, max(0, self)) }
}
#endif
