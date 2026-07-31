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
struct ReaderPositionCard<MiniPlayer: View>: View {
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
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                // Only while the mini player is present — no orphan rule when
                // speech is stopped.
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 1)
                    .padding(.horizontal, 18)
            }

            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    // Page digit + duration tint when scrubbing away from origin;
                    // "Page" / "of M" / "left in chapter" stay unemphasized.
                    pageTitleLabel
                    Spacer(minLength: 8)
                    chapterTimeLabel
                }

                scrubSlider
                    .disabled(!sliderEnabled)
                    .accessibilityLabel("Seek within chapter")
                    .accessibilityValue(pageAccessibilityLabel)

                Text(workLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .lineLimit(1)
                    // Shrink a little before truncating, so the longest reading stays
                    // legible at large Dynamic Type sizes. Carried over from the
                    // progress pill this card replaced (HIG wave, A-F: position
                    // readout must not clip or truncate as text scales).
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 18)
            .padding(.top, showsMiniPlayer ? 12 : 13)
            .padding(.bottom, 15)
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private var pageTitleLabel: some View {
        // page/pageCount <= 0 → measure not ready (never show fake "1 of 1").
        if page < 1 || pageCount < 1 {
            Text("Page …")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Page ")
                    .foregroundStyle(.primary)
                Text("\(page)")
                    .foregroundStyle(scrubValuesEmphasized ? tint : Color.primary)
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
        if let minutes = chapterRemainingMinutes {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(ReaderTimeEstimate.durationLabel(minutes: minutes))
                    .foregroundStyle(scrubValuesEmphasized ? tint : Color.secondary)
                    .contentTransition(.numericText())
                    .animation(.default, value: minutes)
                    .animation(.easeInOut(duration: 0.15), value: scrubValuesEmphasized)
                Text(" left in chapter")
                    .foregroundStyle(.secondary)
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
