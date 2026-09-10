import SwiftUI

// Artboard 1a's identity block — the three things the top of a work's page
// says before it says anything else:
//
//   1. who this is  — fandom kicker, 32pt title, author byline
//   2. what it is   — the four-cell figure strip (rating, warnings, category,
//                     chapters)
//   3. what to do   — the glass resume card and its one filled control
//
// All three sit directly on the page wash rather than inside `.cardRow()`
// chrome. That is the spec's own division of the page: the work's identity gets
// the full width, and card chrome is reserved for the things listed *about* it
// further down (series, collection, publication). It also replaces
// `WorkDetailHeroCard`, which packed all three into one card — a card that read
// as a carousel item lifted onto a page of its own.

/// The page header for a work: its primary fandom as the kicker, the title at
/// 32pt, and the author byline underneath.
///
/// The byline goes through `SubjectHeaderBlock`'s trailing slot rather than its
/// plain-string `subtitle`, because it has to stay a real `AO3AuthorBylineView`
/// — every co-author is individually tappable through to their AO3 profile here
/// exactly as it is on every row and card in the app, and a `String` subtitle
/// would quietly drop that.
struct WorkDetailIdentityHeader: View {
    let title: String
    let authors: [String]
    let identities: [AO3AuthorIdentity]
    let fandoms: [String]
    let palette: SubjectPalette

    /// The fandom the kicker names. Blank entries are skipped rather than
    /// printed as an empty accent line.
    private var namedFandoms: [String] {
        fandoms.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        SubjectHeaderBlock(
            kicker: namedFandoms.first ?? "Work",
            // The kicker names one fandom; this is the count of the ones it is
            // not naming. Every fandom is still listed in full under Tags —
            // this is the trace that says to go looking.
            kickerTrailingCount: max(0, namedFandoms.count - 1),
            title: title,
            palette: palette,
            hasTrailing: !authors.isEmpty
        ) {
            // 15.5pt to the spec, which is the same size the subtitle string
            // would have taken — the slot changes, not the type.
            AO3AuthorBylineView(
                names: authors,
                identities: identities,
                includesBy: false,
                font: .system(size: 15.5),
                expandsHitTarget: false
            )
        }
    }
}

/// The four-cell strip under the title: rating, archive warnings, relationship
/// category, and how many chapters of how many.
///
/// It replaces the 2×2 `WorkStatusIconGrid` that sat in the hero card's corner.
/// The grid says the same four things in a sixth of the space, which is why it
/// stays on every row and cover card — but it says them in colour-coded glyphs
/// that have to be learned, and this page has the width to spell them out.
///
/// Only rating and warnings take a colour. Spec 1a leaves category and chapters
/// white, and that is right for more than fidelity: `WorkStat.categoryColor`
/// paints "Other" black, which on a near-black page is an invisible cell.
struct WorkDetailFigureStrip: View {
    let rating: String
    let warnings: [String]
    let categories: [String]
    let chapters: String
    let completion: WorkCompletionStatus
    let palette: SubjectPalette

    private var warningStatus: WorkWarningStatus {
        WorkWarningStatus(rawWarnings: warnings)
    }

    /// AO3's own single-letter shorthand, as spec 1a prints it ("G"). This is
    /// the dense four-figure row `WorkStat.ratingLetter` was written for; the
    /// full name still reaches VoiceOver below.
    private var ratingCell: SubjectStatStrip.Cell {
        SubjectStatStrip.Cell(
            value: WorkStat.ratingLetter(rating) ?? "—",
            label: "Rating",
            tint: WorkStat.ratingColor(rating),
            accessibilityText: WorkStat.ratingName(rating).map { "Rating: \($0)" } ?? "No rating given"
        )
    }

    private var warningsCell: SubjectStatStrip.Cell {
        SubjectStatStrip.Cell(
            value: warningStatus.figureText,
            label: "Warnings",
            tint: warningStatus.figureColor,
            accessibilityText: warningStatus.accessibilityLabel(rawWarnings: warnings)
        )
    }

    /// One category is printed; the rest become the same dimmed `+N` the kicker
    /// uses for extra fandoms, since three of them ("F/F, F/M, Gen") scale down
    /// to unreadable inside a quarter-width cell.
    private var categoryCell: SubjectStatStrip.Cell {
        let named = categories.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let extras = max(0, named.count - 1)
        let printed = named.first.map { extras > 0 ? "\($0) +\(extras)" : $0 } ?? "—"
        return SubjectStatStrip.Cell(
            value: printed,
            label: "Category",
            accessibilityText: named.isEmpty
                ? "No relationship category"
                : named.map(WorkStat.categoryAccessibilityLabel).joined(separator: ", ")
        )
    }

    /// AO3 answers "is this finished?" with a chapter fraction — 3/3 is done,
    /// 3/12 is not — so the label asks and the count answers, exactly as the
    /// artboard draws it. A converted EPUB with no chapter range falls back to
    /// the status word, which is all that is actually known about it.
    private var completionCell: SubjectStatStrip.Cell {
        let range = chapters.trimmingCharacters(in: .whitespacesAndNewlines)
        return SubjectStatStrip.Cell(
            value: range.isEmpty ? completion.shortText : range,
            label: "Complete",
            accessibilityText: range.isEmpty
                ? "Status: \(completion.text)"
                : "\(range) chapters, \(completion.text)"
        )
    }

    var body: some View {
        SubjectStatStrip(
            cells: [ratingCell, warningsCell, categoryCell, completionCell],
            palette: palette
        )
    }
}

/// The glass card under the figure strip: where you stopped, and the one filled
/// control that takes you back there.
///
/// The whole card is the button, not just the circle. The circle is drawn, in
/// the same way `HomeResumeHero`'s Resume pill is drawn — a real button nested
/// inside a card-sized tap target races it for the same touch, and there is
/// only one thing this card does.
struct WorkDetailResumeCard: View {
    /// What the action is called right now — Read / Continue Reading /
    /// Download & Read / Downloading…, from `WorkDetailPresentation.readAction`
    /// so this card and the rest of the screen never disagree about it.
    let actionTitle: String
    /// Set for a work with a readable copy on device; nil while it still has to
    /// be fetched. Spec 1a's filled circle is a play triangle, which is a
    /// promise this button cannot keep until there is something to open, so the
    /// download case keeps the download glyph.
    let hasReadableCopy: Bool
    let isBusy: Bool
    /// Nil for a work with no local reading state — a remote work nobody here
    /// has opened. Drawing a 0% ring for it would claim it is being tracked.
    let readingProgress: Double?
    let lastSpineIndex: Int
    let lastReadDate: Date?
    let palette: SubjectPalette
    let action: () -> Void

    @Environment(ThemeManager.self) private var themeManager

    private var clampedProgress: Double? {
        readingProgress.map { min(1, max(0, $0)) }
    }

    /// The chapter the reader stopped in, or the action's own name when they
    /// have not started. Spec 1a puts the chapter's *title* here; `SavedWork`
    /// stores only the spine index, so this says the number instead — the same
    /// gap `HomeResumeHero` documents, waiting on the same reading log.
    private var primaryLine: String {
        guard clampedProgress != nil else { return actionTitle }
        return lastSpineIndex > 0 ? "Chapter \(lastSpineIndex + 1)" : "Reading"
    }

    /// Spec 1a's "Rain on the Wire · 9 pages left" is two facts the app does not
    /// have (a chapter title and a page estimate). When the work has been opened
    /// the honest one is when — same substitution, same reason, as the Home hero.
    private var secondaryLine: String? {
        guard clampedProgress != nil else { return nil }
        return lastReadDate?.formatted(.relative(presentation: .named))
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                if let clampedProgress {
                    WorkProgressRing(progress: clampedProgress, diameter: 48)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(primaryLine)
                        .font(.system(size: 16.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    if let secondaryLine {
                        Text(secondaryLine)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.primary.opacity(0.6))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)

                circleControl
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(actionTitle)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityValue: String {
        guard let clampedProgress else { return "Not started" }
        let percent = Int((clampedProgress * 100).rounded())
        return [primaryLine, "\(percent) percent", secondaryLine]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    /// 42pt, filled, and the only high-contrast thing on the page — the same
    /// `solidButton` pair the Home hero's Resume pill uses, so the app has one
    /// "this is the action" colour rather than one per screen.
    @ViewBuilder
    private var circleControl: some View {
        ZStack {
            Circle().fill(palette.solidButtonFill)
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .tint(palette.solidButtonLabel)
            } else {
                Image(systemName: hasReadableCopy ? "play.fill" : "arrow.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.solidButtonLabel)
            }
        }
        .frame(width: 42, height: 42)
    }

    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return shape
            .fill(themeManager.appTheme.glassFill(0.10))
            .overlay(shape.strokeBorder(themeManager.appTheme.glassStroke(0.14), lineWidth: 0.5))
    }
}
