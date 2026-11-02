import SwiftUI

// Board 19's identity block — the things the top of a work's page says before
// it says anything else:
//
//   1. who this is  — fandom label and rule, Large Title, author byline
//   2. what it is   — the four symbols inline (`WorkStatusIconGrid`, `.inline`),
//                     drawn by `WorkDetailView.heroSection`
//   3. what to do   — the Resume card's detail variant and its one filled control
//
// All three sit directly on the page wash rather than inside `.cardRow()`
// chrome. The old four-cell `WorkDetailFigureStrip` is gone: rating, category,
// warnings and status are the symbols' names now, and the chapter count is a
// cell of the stats card (`WorkDetailStatsCard`).

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
