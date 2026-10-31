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
/// Large Title, and the tappable author byline underneath (board 19).
struct WorkDetailIdentityHeader: View {
    let title: String
    let authors: [String]
    let identities: [AO3AuthorIdentity]
    let fandoms: [String]
    let palette: SubjectPalette

    @ScaledMetric(relativeTo: .subheadline) private var bylineSize: CGFloat = 15.5

    /// The fandom the kicker names. Blank entries are skipped rather than
    /// printed as an empty accent line.
    private var namedFandoms: [String] {
        fandoms.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        SubjectPageHeading(
            fandomKicker: namedFandoms.first.map(FandomDisplayName.bareTitle),
            // The kicker names one fandom; this is the count of the ones it is
            // not naming. Every fandom is still listed in full under Tags —
            // this is the trace that says to go looking.
            fandomExtraCount: max(0, namedFandoms.count - 1),
            title: title,
            palette: palette,
            hasTrailing: !authors.isEmpty
        ) {
            AO3AuthorBylineView(
                names: authors,
                identities: identities,
                includesBy: false,
                font: .system(size: bylineSize),
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
/// paints "Other" near-black, which on a near-black page is an invisible cell.
/// The two coloured cells are text, so they take the text step of AO3's tile
/// colours (`WorkStat.ratingInk`), not the fills themselves.
struct WorkDetailFigureStrip: View {
    /// What a cell prints when the field is genuinely unknown, rather than
    /// leaving a blank quarter of the strip that reads as a layout gap.
    private let emptyFigure = "—"

    let rating: String
    let warnings: [String]
    let categories: [String]
    let chapters: String
    let completion: WorkCompletionStatus
    let palette: SubjectPalette

    @Environment(ThemeManager.self) private var themeManager

    private var warningStatus: WorkWarningStatus {
        WorkWarningStatus(rawWarnings: warnings)
    }

    /// AO3's own single-letter shorthand, as spec 1a prints it ("G"). This is
    /// the dense four-figure row `WorkStat.ratingLetter` was written for; the
    /// full name still reaches VoiceOver below.
    private var ratingCell: SubjectStatStrip.Cell {
        let printed: String = WorkStat.ratingLetter(rating) ?? emptyFigure
        var spoken = "No rating given"
        if let name = WorkStat.ratingName(rating) {
            spoken = "Rating: " + name
        }
        return SubjectStatStrip.Cell(
            value: printed,
            label: "Rating",
            tint: WorkStat.ratingInk(rating, on: themeManager.appTheme),
            accessibilityText: spoken
        )
    }

    private var warningsCell: SubjectStatStrip.Cell {
        SubjectStatStrip.Cell(
            value: warningStatus.figureText,
            label: "Warnings",
            tint: themeManager.appTheme.accentInk(for: warningStatus.figureColor),
            accessibilityText: warningStatus.accessibilityLabel(rawWarnings: warnings)
        )
    }

    /// One category is printed; the rest become the same dimmed `+N` the kicker
    /// uses for extra fandoms, since three of them ("F/F, F/M, Gen") scale down
    /// to unreadable inside a quarter-width cell.
    private var categoryCell: SubjectStatStrip.Cell {
        let named: [String] = categories.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var printed = emptyFigure
        var spoken = "No relationship category"
        if let first = named.first {
            let extras: Int = named.count - 1
            printed = extras > 0 ? first + " +" + String(extras) : first
            spoken = named.map(WorkStat.categoryAccessibilityLabel).joined(separator: ", ")
        }
        return SubjectStatStrip.Cell(value: printed, label: "Category", accessibilityText: spoken)
    }

    /// AO3 answers "is this finished?" with a chapter fraction — 3/3 is done,
    /// 3/12 is not — so the label asks and the count answers, exactly as the
    /// artboard draws it. A converted EPUB with no chapter range falls back to
    /// the status word, which is all that is actually known about it.
    private var completionCell: SubjectStatStrip.Cell {
        let range: String = chapters.trimmingCharacters(in: .whitespacesAndNewlines)
        var printed: String = completion.shortText
        var spoken: String = "Status: " + completion.text
        if !range.isEmpty {
            printed = range
            spoken = range + " chapters, " + completion.text
        }
        return SubjectStatStrip.Cell(value: printed, label: "Complete", accessibilityText: spoken)
    }

    var body: some View {
        SubjectStatStrip(
            cells: [ratingCell, warningsCell, categoryCell, completionCell],
            palette: palette
        )
    }
}

/// Work Detail's full Resume variant. The visual and chapter logic live in the
/// same `WorkResumeCard` Home and queues use, while this seam keeps the detail
/// screen's read/download actions local to that screen.
struct WorkDetailResumeCard: View {
    let actionTitle: String
    let model: ResumeCardModel
    let localWork: SavedWork?
    let isBusy: Bool
    let action: () -> Void
    let readAloud: () -> Void
    let contents: () -> Void
    let updateDownload: (() -> Void)?

    var body: some View {
        // The whole card opens the reader, the way the old detail card did.
        // Resume, Contents and Update stay their own buttons inside the label,
        // so a tap on one of them does not also fire this one.
        Button(action: action) {
            WorkResumeCard(
                model: model,
                localWork: localWork,
                variant: .detail,
                primaryLabel: actionTitle,
                isBusy: isBusy,
                onPrimary: action,
                onReadAloud: readAloud,
                onContents: contents,
                onUpdate: updateDownload
            )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityElement(children: .contain)
    }
}
