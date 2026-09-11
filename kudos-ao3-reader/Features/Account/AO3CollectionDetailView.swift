import SwiftUI

/// Navigation value for a whole collection. Deliberately not
/// `AO3AccountWorksList.Kind.collection`, which still means "the works page of a
/// collection" and is pushed from other places — this one opens all three segments.
struct AO3CollectionDestination: Hashable {
    let slug: String
    let title: String
}

/// Artboard **1ci** — a collection as someone browsing it sees it.
///
/// The other side of 1cd. Its three segments are three different AO3 pages, which
/// is why they load independently rather than as one payload — the spec's own note
/// says so, and it is also what stops opening the screen costing three requests
/// when a reader only ever looks at Works.
///
/// **Anonymous is the collection's state, not the work's.** The same work reads as
/// Anonymous here and under its creator everywhere else, which is why the badge sits
/// on the card rather than replacing the byline: a reader who sees "Anonymous" with
/// no explanation learns nothing, and one who sees a badge learns that this
/// collection is hiding creators.
struct AO3CollectionDetailView: View {
    let slug: String
    let title: String

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme

    @State private var show: AO3CollectionShow?
    @State private var segment: Segment = .works
    @State private var works: [AO3WorkSummary] = []
    @State private var bookmarks: [AO3WorkSummary] = []
    @State private var people: [AO3CollectionPerson] = []
    /// Which segments have already been fetched, so switching back to one does not
    /// re-request it. Keyed by segment rather than a set of booleans so a fourth
    /// segment cannot be added without deciding this.
    @State private var loaded: Set<Segment> = []
    @State private var phase: Phase = .idle
    @State private var expandAll = false

    private enum Phase: Equatable { case idle, loading, loaded, failed(String) }

    nonisolated enum Segment: String, CaseIterable, Hashable, Sendable {
        case works
        case bookmarks
        case people

        var title: String {
            switch self {
            case .works: "Works"
            case .bookmarks: "Bookmarks"
            case .people: "People"
            }
        }
    }

    var body: some View {
        List {
            Section {
                header.pageBodyRow(top: 20, gutter: 0)
                if let show, !statCells(for: show).isEmpty {
                    SubjectStatStrip(cells: statCells(for: show), palette: palette)
                        .pageBodyRow(top: 12, gutter: SubjectMetrics.panelGutter)
                }
                segmentStrip.pageBodyRow(top: 14, gutter: SubjectMetrics.accountGutter)
            }

            switch phase {
            case .loading:
                Section { loadingRow.pageBodyRow(top: 20, gutter: SubjectMetrics.accountGutter) }
            case let .failed(message):
                Section { failureCard(message).pageBodyRow(top: 14, gutter: SubjectMetrics.accountGutter) }
            default:
                segmentContent
            }
        }
        .cardList()
        .subjectScreenWash(palette: palette)
        .task(id: segment) { await loadIfNeeded() }
        .refreshable {
            loaded.remove(segment)
            await loadIfNeeded()
        }
    }

    // MARK: Header

    private var header: some View {
        SubjectHeaderBlock(
            kicker: "Collection",
            title: show?.collection.title ?? title,
            subtitle: subtitleLine,
            palette: palette,
            gutter: SubjectMetrics.accountGutter
        )
    }

    /// Spec 1ci: "saltandsilver, meridian · Coastal fic, all fandoms" — the
    /// maintainers and the collection's own one-line description.
    private var subtitleLine: String {
        guard let collection = show?.collection else { return "" }
        var parts: [String] = []
        if !collection.byline.isEmpty { parts.append(collection.byline) }
        if !collection.summary.isEmpty { parts.append(collection.summary) }
        return parts.joined(separator: " · ")
    }

    /// Works / Bookmarks / Members. Each cell is dropped when AO3 gave no figure,
    /// rather than shown as zero.
    private func statCells(for show: AO3CollectionShow) -> [SubjectStatStrip.Cell] {
        var cells: [SubjectStatStrip.Cell] = []
        if let works = show.collection.worksCount {
            cells.append(SubjectStatStrip.Cell(value: "\(works)", label: "Works"))
        }
        if let bookmarks = show.collection.bookmarksCount {
            cells.append(SubjectStatStrip.Cell(value: "\(bookmarks)", label: "Bookmarks"))
        }
        if !people.isEmpty {
            cells.append(SubjectStatStrip.Cell(value: "\(people.count)", label: "Members"))
        }
        return cells
    }

    private var segmentStrip: some View {
        SubjectSegmentedControl(
            options: Segment.allCases,
            title: \.title,
            selection: $segment
        )
    }

    private var palette: SubjectPalette {
        theme.appTheme.subjectPalette(
            hue: CoverArt.workHue(fandoms: [], title: show?.collection.title ?? title)
        )
    }

    // MARK: Segments

    @ViewBuilder
    private var segmentContent: some View {
        switch segment {
        case .works: workRows(works, emptyMessage: "This collection has no works yet.")
        case .bookmarks: workRows(bookmarks, emptyMessage: "This collection has no bookmarks yet.")
        case .people: peopleRows
        }
    }

    @ViewBuilder
    private func workRows(_ rows: [AO3WorkSummary], emptyMessage: String) -> some View {
        if rows.isEmpty {
            Section {
                emptyCard(emptyMessage).pageBodyRow(top: 14, gutter: SubjectMetrics.accountGutter)
            }
        } else {
            Section {
                SectionRuleHeader(title: segment.title, count: rows.count)
                    .pageBodyRow(top: 18, gutter: 0)
                ForEach(rows) { work in
                    EnrichingAO3WorkRow(
                        work: work, expandAll: expandAll, presentation: .searchLedger
                    )
                    .overlay(alignment: .topTrailing) {
                        collectionStateBadge(for: work).padding(10)
                    }
                    .cardRow(tintHue: CoverArt.workHue(fandoms: work.fandoms, title: work.title))
                }
            }
        }
    }

    /// The spec's card badge. Only Anonymous is derivable from the works page — AO3
    /// prints the byline as "Anonymous" and gives nothing else away.
    ///
    /// 1ci also draws a **Gift** badge. `AO3WorkSummary` carries no recipient, and
    /// the collection's works page does not print one, so it is not here rather than
    /// being guessed at. The gift recipient does reach the app through
    /// `AO3CollectionItem.recipient` on the maintainer's items page (1s), which is a
    /// different request and a different screen.
    @ViewBuilder
    private func collectionStateBadge(for work: AO3WorkSummary) -> some View {
        if isAnonymous(work) {
            Text("ANON")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(palette.accentOnFill)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(palette.chipFill)
                        .overlay(Capsule().strokeBorder(palette.chipStroke, lineWidth: 0.5))
                )
                .accessibilityLabel("Anonymous in this collection")
        }
    }

    /// AO3 renders an anonymous work's byline as the literal word. Matched
    /// case-insensitively against the whole byline rather than by substring, so a
    /// creator actually called "anonymously_yours" is not badged.
    private func isAnonymous(_ work: AO3WorkSummary) -> Bool {
        let byline = work.authors
            .joined(separator: ", ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return byline.compare("Anonymous", options: .caseInsensitive) == .orderedSame
    }

    @ViewBuilder
    private var peopleRows: some View {
        if people.isEmpty {
            Section {
                emptyCard("Nobody has joined this collection yet.")
                    .pageBodyRow(top: 14, gutter: SubjectMetrics.accountGutter)
            }
        } else {
            Section {
                SectionRuleHeader(title: "People", count: people.count)
                    .pageBodyRow(top: 18, gutter: 0)
                ForEach(people) { person in
                    AO3CollectionPersonRow(person: person, palette: palette)
                        .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
                }
            }
        }
    }

    // MARK: Chrome

    private var loadingRow: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
    }

    private func emptyCard(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .subjectPanel()
    }

    private func failureCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Couldn't load this collection")
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again") {
                loaded.remove(segment)
                Task { await loadIfNeeded() }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 13, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .subjectPanel()
    }

    // MARK: Loading

    /// Loads the collection header once, then only the segment being shown.
    ///
    /// Every request goes through the signed-in session when there is one and
    /// anonymously otherwise — a collection is public, and requiring a login to
    /// look at one would be a regression against the website.
    private func loadIfNeeded() async {
        guard !loaded.contains(segment) else { return }
        phase = .loading
        // Built from the collection's own URL when there is a session; the fetches
        // below each retarget it (`request.url = …`), which is the established
        // pattern in AO3Client+Collections. Nil when signed out, which is a normal
        // state here rather than a failure.
        let request: URLRequest? = {
            guard auth.isLoggedIn, let url = AO3CollectionURL.show(slug: slug) else { return nil }
            return try? auth.authenticatedRequest(for: url)
        }()
        do {
            if show == nil {
                show = try await AO3Client.shared.collectionShow(slug: slug, request: request)
            }
            switch segment {
            case .works:
                works = try await AO3Client.shared.collectionWorks(slug: slug, request: request).works
            case .bookmarks:
                bookmarks = try await AO3Client.shared
                    .collectionBookmarks(slug: slug, request: request).works
            case .people:
                people = try await AO3Client.shared.collectionPeople(slug: slug, request: request).people
            }
            loaded.insert(segment)
            phase = .loaded
        } catch let error as AO3Error {
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

/// One member of a collection — spec 1ci's People segment.
struct AO3CollectionPersonRow: View {
    let person: AO3CollectionPerson
    let palette: SubjectPalette

    var body: some View {
        HStack(spacing: 12) {
            Text(String(person.identity.displayName.prefix(1)).uppercased())
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(palette.accent)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.chipFill)
                )
                .accessibilityHidden(true)

            Text(person.identity.displayName)
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)

            if let count = person.workCount {
                Text("\(count) work\(count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .subjectCard(palette: palette)
    }
}
