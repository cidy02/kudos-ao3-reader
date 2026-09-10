import SwiftUI

// The lower half of artboard 1a: the grouped facts card, the archive tally
// strip, the two outline buttons, and the My copy row that leads to the local
// state. Built from the shared form family (`UIComponents/SubjectForm.swift`)
// rather than from anything of its own — these rows are the same shape the
// spec's fifty-odd form and settings artboards are made of.

extension WorkDetailView {
    // MARK: Grouped facts

    /// Artboard 1a's outlined card of labelled facts.
    ///
    /// The artboard's example work carries four of these rows; this app knows
    /// more about a work than that mock did, and `AGENTS.md` treats dropping a
    /// stat to match a mock as a regression. So the card is the spec's chrome
    /// around every fact the three cards it replaces used to state — Publication
    /// and Work and Stats — minus only what the figure strip at the top of the
    /// page now says better.
    ///
    /// Unfilled, unlike a form panel: this card sits on the work's own wash, and
    /// a glass fill over it would mute the colour the whole page is built from.
    @ViewBuilder
    var factsCardSection: some View {
        let rows = factRows
        if !rows.isEmpty {
            Section {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            // Full-bleed, not inset: on an outlined card the line
                            // reads as a division of the card itself rather than
                            // as a gap under a label.
                            SubjectRowSeparator(inset: 0)
                        }
                        row.view
                    }
                }
                .subjectPanel(cornerRadius: 16, isFilled: false)
                .pagePanelRow(top: 24)
            }
        }
    }

    /// One row of the facts card, kept as data so the separators can be placed
    /// between them without the container having to take its children apart.
    struct FactRow: Identifiable {
        let id: String
        let view: AnyView
    }

    private var factRows: [FactRow] {
        var rows: [FactRow] = []

        if !displaySeriesTitle.isEmpty {
            rows.append(FactRow(id: "series", view: AnyView(seriesFactRow)))
        }
        if !headlineFactSegments.isEmpty {
            rows.append(FactRow(id: "headline", view: AnyView(headlineFactRow)))
        }
        if !displayPublishedDate.isEmpty {
            rows.append(FactRow(id: "published", view: AnyView(
                SubjectFormRow(label: "Published", value: displayPublishedDate, isMonospaced: true)
            )))
        }
        if let work = localWork {
            let added = work.dateAdded.formatted(date: .abbreviated, time: .shortened)
            rows.append(FactRow(id: "added", view: AnyView(
                SubjectFormRow(label: "Added", value: added, isMonospaced: true)
            )))
            // Source and preservation state deliberately absent:
            // `WorkProvenanceSections` states both further down the page, and
            // twice on one screen is not density, it is noise.
        }
        return rows
    }

    /// Spec 1a's own last row: the work's shape on the left, when AO3 last
    /// touched it pushed to the trailing edge in monospace. The two facts a
    /// reader scanning a shelf compares between works.
    private var headlineFactRow: some View {
        var updated = ""
        if !displayUpdatedDate.isEmpty {
            updated = "upd " + displayUpdatedDate
        }
        return SubjectFormRow(
            label: headlineFactSegments.joined(separator: " · "),
            value: updated,
            isMonospaced: true
        )
    }

    private var headlineFactSegments: [String] {
        var segments: [String] = []
        if !displayLanguage.isEmpty {
            segments.append(displayLanguage)
        }
        if let words = displayWords {
            segments.append(words.formatted() + " words")
        }
        return segments
    }

    /// The series row states the series' own name and where this work sits in
    /// it. It opens the series on AO3 when there is one to open — the works
    /// already downloaded from it are listed by `seriesSection` below, which is
    /// navigation rather than a fact and stays where it is.
    private var seriesFactRow: some View {
        var partText = "Series"
        if displaySeriesPosition > 0 {
            partText = "Part " + String(displaySeriesPosition)
        }
        let seriesURL: URL? = URL(string: displaySeriesURL)
        var openSeries: (() -> Void)?
        if let seriesURL {
            openSeries = { router.open(seriesURL) }
        }
        return SubjectFormRow(
            label: displaySeriesTitle,
            value: partText,
            showsDisclosure: seriesURL != nil,
            action: openSeries
        )
    }

    // MARK: Archive tallies

    /// Kudos · comments · bookmarks · hits, as spec 1a's second figure strip.
    ///
    /// Comments is the accented cell and the only one that acts: it is a way
    /// into the discussion rather than a number about the work, which is why
    /// the artboard draws it in the subject accent with a glyph beside it.
    @ViewBuilder
    var archiveStatsSection: some View {
        let cells = archiveStatCells
        if !cells.isEmpty {
            Section {
                SubjectStatStrip(cells: cells, palette: workPalette)
                    .pagePanelRow(top: 14)
            }
        }
    }

    private var archiveStatCells: [SubjectStatStrip.Cell] {
        var cells: [SubjectStatStrip.Cell] = []
        if let kudos = displayKudos {
            cells.append(SubjectStatStrip.Cell(
                value: kudos.formatted(), label: "Kudos",
                accessibilityText: kudos.formatted() + " kudos"
            ))
        }
        if ao3WorkID != nil {
            let printed = displayComments.map { $0.formatted() } ?? "—"
            cells.append(SubjectStatStrip.Cell(
                value: printed,
                label: "Comments",
                isHighlighted: true,
                accessibilityText: "Comments, " + printed + ", opens the discussion",
                action: { withAnimationUnlessReduced(reduceMotion: reduceMotion) { selectedTab = .discussion } }
            ))
        } else if let comments = displayComments {
            cells.append(SubjectStatStrip.Cell(
                value: comments.formatted(), label: "Comments",
                accessibilityText: comments.formatted() + " comments"
            ))
        }
        if let bookmarks = displayBookmarks {
            cells.append(SubjectStatStrip.Cell(
                value: bookmarks.formatted(), label: "Bookmarks",
                accessibilityText: bookmarks.formatted() + " bookmarks"
            ))
        }
        if let hits = displayHits {
            cells.append(SubjectStatStrip.Cell(
                value: hits.formatted(), label: "Hits",
                accessibilityText: hits.formatted() + " hits"
            ))
        }
        return cells
    }

    // MARK: Page actions

    /// The artboard's pair of outline buttons. Deliberately outlined rather than
    /// filled: the page already has one filled control, the resume card's
    /// circle, and a second would compete with it for the same glance.
    @ViewBuilder
    var pageActionsSection: some View {
        Section {
            HStack(spacing: 10) {
                let finished = localWork?.isFinished ?? false
                WorkDetailOutlineButton(
                    title: WorkActionLabels.finished(isFinished: finished).title,
                    action: toggleFinished
                )
                .disabled(working)

                if let url = ao3URL {
                    WorkDetailOutlineButton(title: "Open on AO3") { router.open(url) }
                }
            }
            .pageBodyRow(top: 22)
        }
    }

    // MARK: My copy

    /// The row at the foot of the page that leads to everything local about this
    /// work. Shown only once there *is* a local copy — on a work being browsed
    /// from Search there is nothing behind it yet.
    @ViewBuilder
    var myCopySection: some View {
        if let work = localWork {
            Section {
                WorkDetailMyCopyRow(
                    summary: WorkDetailPresentation.myCopySummary(
                        isDownloaded: work.hasEPUB,
                        queueCount: work.queueMemberships.count,
                        tagCount: work.tags.count,
                        collectionCount: work.collections.count
                    ),
                    action: { withAnimationUnlessReduced(reduceMotion: reduceMotion) { selectedTab = .library } }
                )
                .pageBodyRow(top: 10)
            }
        }
    }
}

/// One of the page's two outline buttons.
struct WorkDetailOutlineButton: View {
    let title: String
    let action: () -> Void

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(themeManager.appTheme.glassStroke(0.18), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// The My copy row: a glyph, the two lines that say what this device holds, and
/// a chevron into the detail.
struct WorkDetailMyCopyRow: View {
    let summary: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "iphone")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("My copy")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .subjectPanel(cornerRadius: 14)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("My copy")
        .accessibilityValue(summary)
    }
}
