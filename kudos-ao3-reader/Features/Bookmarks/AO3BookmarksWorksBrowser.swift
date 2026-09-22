import SwiftUI

// MARK: - Pills and copy

/// 1q's All / Recs / Private / With notes pills. They narrow the loaded page.
///
/// AO3's bookmarks index is described as offering these as filters. The author
/// profile's Bookmarks tab does not implement them, and this screen does not
/// send a bookmark-search query: the parameter names were not confirmed from
/// here. A pill keeps or drops rows already fetched, the same way History's
/// progress pills do.
enum AO3BookmarksFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case recs
    case `private`
    case withNotes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .recs: "Recs"
        case .`private`: "Private"
        case .withNotes: "With notes"
        }
    }

    /// `notes` is the model, not a precomputed flag, so "with notes" is
    /// `AO3RichText.isEmpty`. A note element that parsed as whitespace is not
    /// a note. A row matches every pill it qualifies for; the pills are
    /// alternatives, not a partition.
    func includes(isRecommendation: Bool, isPrivate: Bool, notes: AO3RichText) -> Bool {
        switch self {
        case .all:
            true
        case .recs:
            isRecommendation
        case .`private`:
            isPrivate
        case .withNotes:
            !notes.isEmpty
        }
    }
}

/// Whether the bookmark footnote has to stay off the card.
///
/// `SensitiveWorkRow` blurs only its own body. The note, the bookmark tags,
/// the date, and the private or rec mark are drawn beside that row, so they
/// need the same predicate. A private note under "Tap to reveal" is the leak.
/// A remote-only row has no local work. The view returns before calling
/// this, and the footnote stays. That is the list's existing rule for
/// remote rows.
enum AO3BookmarksMatureBlur {
    static func isBlurred(
        isAdult: Bool,
        hideMature: Bool,
        mode: MaturePrivacyMode,
        isRevealed: Bool
    ) -> Bool {
        hideMature && isAdult && mode == .obscure && !isRevealed
    }
}

enum AO3BookmarksCopy {
    /// What this list is. Page numbers are the pagination bar's, clamped the
    /// way `AO3MarkedForLaterCopy.footer` clamps them.
    static func footer(currentPage: Int, totalPages: Int) -> String {
        let pages = max(totalPages, 1)
        let page = min(max(currentPage, 1), pages)
        let noun = pages == 1 ? "page" : "pages"
        return "Your bookmarks on AO3. Each row's note, tags, date, and private "
            + "or rec mark are that bookmark's own. The pills narrow this page: "
            + "\(page) of \(pages) \(noun)."
    }
}

// MARK: - Screen

/// Bookmarks' own list inside `AO3AccountWorksList`. Other account lists do
/// not come through here.
///
/// Compact is not the cover grid the other lists use. A cover has nowhere to
/// put the note, the bookmark tags, the date, and the private or rec mark,
/// and compact is the account default — the grid would have kept the gap this
/// screen exists to close. Compact is the ledger row in a scroll view, with
/// those facts under it. Detailed and ledger stay in the list.
struct AO3BookmarksWorksBrowser: View {
    let entries: [CanonicalWork]
    let bookmarks: [Int: AO3AuthorBookmark]
    let displayMode: WorkListDisplayMode
    let expandAll: Bool
    let palette: SubjectPalette
    let kicker: String
    let showPagination: Bool
    let currentPage: Int
    let totalPages: Int
    let isLoading: Bool
    @Binding var filter: AO3BookmarksFilter
    let onPage: (Int) -> Void

    @Environment(ThemeManager.self) private var theme
    @Environment(PrivacyGate.self) private var gate
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure

    private var shownEntries: [CanonicalWork] {
        entries.filter { entry in
            guard let bookmark = bookmark(for: entry) else { return filter == .all }
            return filter.includes(
                isRecommendation: bookmark.isRecommendation,
                isPrivate: bookmark.isPrivate,
                notes: bookmark.notes
            )
        }
    }

    var body: some View {
        Group {
            if displayMode == .compact {
                compactBody
            } else {
                detailedBody
            }
        }
    }

    private var compactBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header.padding(.top, 20)
                AO3BookmarksFilterRail(selection: $filter, palette: palette)
                if showPagination { paginationBar.padding(.horizontal, CardListMetrics.sideMargin) }
                if shownEntries.isEmpty {
                    filterEmpty
                } else {
                    VStack(spacing: 10) {
                        ForEach(shownEntries) { entry in
                            compactRow(entry)
                        }
                    }
                }
                footer.padding(.horizontal, SubjectMetrics.gutter)
                if showPagination { paginationBar.padding(.horizontal, CardListMetrics.sideMargin) }
            }
            .padding(.vertical, 8)
        }
        .subjectScreenWash(palette: palette)
    }

    private var detailedBody: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 20, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                AO3BookmarksFilterRail(selection: $filter, palette: palette)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if showPagination {
                Section { paginationBar.bareListRow() }
            }
            if shownEntries.isEmpty {
                Section { filterEmpty.bareListRow() }
            } else {
                Section {
                    ForEach(shownEntries) { entry in
                        detailedRow(entry)
                    }
                }
            }
            Section { footer.bareListRow() }
            if showPagination {
                Section { paginationBar.bareListRow() }
            }
        }
        .cardList()
        .subjectScreenWash(palette: palette)
    }

    private var header: some View {
        SubjectHeaderBlock(
            kicker: kicker,
            title: "Bookmarks",
            subtitle: subtitle,
            palette: palette,
            gutter: SubjectMetrics.accountGutter
        )
    }

    private var subtitle: String {
        let count = shownEntries.count
        var line = count == 1 ? "1 work" : "\(count) works"
        if totalPages > 1 {
            line += " · page \(currentPage) of \(totalPages)"
        }
        return line
    }

    private var paginationBar: some View {
        SearchPaginationBar(
            currentPage: currentPage,
            totalPages: totalPages,
            isLoading: isLoading
        ) { page in
            onPage(page)
        }
    }

    private var footer: some View {
        Text(AO3BookmarksCopy.footer(currentPage: currentPage, totalPages: totalPages))
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    private var filterEmpty: some View {
        ContentUnavailableView {
            Label("No matching works", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("No works on this page are \(filter.title.lowercased()).")
        } actions: {
            Button("Reset") { filter = .all }
        }
    }

    /// Ledger content draws no card of its own. This branch is a `ScrollView`,
    /// so the wash is `subjectCard` rather than `.cardRow` — the same reason
    /// Marked for Later's ledger rows are wrapped that way.
    private func compactRow(_ entry: CanonicalWork) -> some View {
        rowStack(entry, ledger: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .subjectCard(palette: theme.appTheme.subjectPalette(hue: hue(for: entry)))
            .padding(.horizontal, CardListMetrics.sideMargin)
    }

    private func detailedRow(_ entry: CanonicalWork) -> some View {
        rowStack(entry, ledger: displayMode == .ledger)
            .cardRow(tintHue: hue(for: entry))
    }

    private func rowStack(_ entry: CanonicalWork, ledger: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            rowBody(entry, ledger: ledger)
            if let bookmark = bookmark(for: entry), !isBlurred(entry) {
                AO3BookmarkFootnote(bookmark: bookmark)
            }
        }
    }

    @ViewBuilder
    private func rowBody(_ entry: CanonicalWork, ledger: Bool) -> some View {
        if let work = entry.local {
            SensitiveWorkRow(
                work: work,
                expandAll: expandAll,
                presentation: ledger ? .ledger : .standard
            )
        } else if let remote = entry.remote {
            EnrichingAO3WorkRow(
                work: remote,
                expandAll: expandAll,
                presentation: ledger ? .searchLedger : .standard
            )
        }
    }

    /// Remote rows are not blurred on this screen. Only a saved local work
    /// can be behind `SensitiveWorkRow`'s own gate.
    private func isBlurred(_ entry: CanonicalWork) -> Bool {
        guard let work = entry.local else { return false }
        return AO3BookmarksMatureBlur.isBlurred(
            isAdult: work.isAdult,
            hideMature: hideMature,
            mode: matureMode,
            isRevealed: gate.isRevealed(work)
        )
    }

    private func bookmark(for entry: CanonicalWork) -> AO3AuthorBookmark? {
        guard let id = entry.ao3WorkID else { return nil }
        return bookmarks[id]
    }

    private func hue(for entry: CanonicalWork) -> Double {
        if let work = entry.local {
            return CoverArt.workHue(fandoms: work.workFandoms, title: work.title)
        }
        if let remote = entry.remote {
            return CoverArt.workHue(fandoms: remote.fandoms, title: remote.title)
        }
        return 0
    }
}

/// The same pill row History and Marked for Later use, including the quieter Reset.
struct AO3BookmarksFilterRail: View {
    @Binding var selection: AO3BookmarksFilter
    let palette: SubjectPalette

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AO3BookmarksFilter.allCases) { option in
                    Button {
                        selection = option
                    } label: {
                        SubjectChip(
                            text: option.title,
                            style: .pill(isSelected: selection == option),
                            palette: palette
                        )
                    }
                    .buttonStyle(.plain)
                    .minimumHitTarget(28)
                }
                Button {
                    selection = .all
                } label: {
                    SubjectChip(
                        text: "Reset",
                        style: .pill(isSelected: false),
                        systemImage: "xmark"
                    )
                    .opacity(selection == .all ? 0.45 : 0.7)
                }
                .buttonStyle(.plain)
                .minimumHitTarget(28)
                .accessibilityLabel("Reset filters")
            }
            .padding(.horizontal, 16)
        }
    }
}

/// Note, bookmark tags, date, and the private / rec mark, under the work card.
///
/// The work's own tags already sit on the card. Bookmark tags are a second
/// list, so they keep the caption the author-profile row uses. The note is
/// `AO3RichTextView`, the renderer that already draws `AO3AuthorBookmark.notes`.
/// Collections are parsed and not drawn here: 1q names the note, the tags, the
/// date, and the privacy flag.
struct AO3BookmarkFootnote: View {
    let bookmark: AO3AuthorBookmark

    private var showsStatus: Bool {
        bookmark.isRecommendation || bookmark.isPrivate || !bookmark.date.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsStatus {
                FlowLayout(spacing: 8, rowSpacing: 5) {
                    if bookmark.isRecommendation {
                        WorkStateBadge(text: "Rec", symbol: "hand.thumbsup.fill")
                    }
                    if bookmark.isPrivate {
                        WorkStateBadge(text: "Private", symbol: "lock.fill")
                    }
                    if !bookmark.date.isEmpty {
                        WorkStateBadge(text: bookmark.date, symbol: "calendar")
                    }
                }
                .font(.caption2)
            }
            if !bookmark.tags.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bookmark Tags")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    FlowLayout(spacing: 6, rowSpacing: 6) {
                        ForEach(bookmark.tags, id: \.self) { TagChip(text: $0) }
                    }
                }
            }
            if !bookmark.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bookmark Notes")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    AO3RichTextView(document: bookmark.notes)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }
}
