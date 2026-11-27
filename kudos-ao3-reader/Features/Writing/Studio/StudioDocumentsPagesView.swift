import SwiftUI

/// Writing Studio → Documents → Pages (`Studio-Documents`):
/// search field, filter chips (All / Drafts / Posted / Gifts), Recent 2-column
/// paper cards, Manuscripts (featured expanded manuscript with Add Chapter plus
/// remaining works), and Loose Drafts.
struct StudioDocumentsPagesView: View {
    let snapshot: StudioDocumentsSnapshot
    let store: WritingDocumentStore
    @Binding var selectedChip: StudioDocumentsFilterChip
    @Binding var searchQuery: String
    let isLoadingAO3: Bool
    let ao3Error: String?
    var onRetryAO3: () -> Void = {}
    var onChanged: () -> Void = {}

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var addedChapterRoute: AddedChapterRoute?
    @State private var addedAO3ChapterRoute: AddedAO3ChapterRoute?
    @State private var actionError: String?

    private struct AddedChapterRoute: Identifiable, Hashable {
        let workID: UUID
        let chapterID: UUID
        let workTitle: String
        var id: UUID { chapterID }
    }

    private struct AddedAO3ChapterRoute: Identifiable, Hashable {
        let workID: Int
        let workTitle: String
        let chapterCount: Int?
        var id: Int { workID }
    }

    private var filteredManuscripts: [StudioWorkItem] {
        StudioDocumentsCatalog.filter(snapshot.manuscripts, chip: selectedChip, query: searchQuery)
    }

    private var filteredLooseDrafts: [StudioWorkItem] {
        StudioDocumentsCatalog.filter(snapshot.looseDrafts, chip: selectedChip, query: searchQuery)
    }

    private var filteredRecent: [StudioRecentDocumentItem] {
        let visibleIDs = Set((filteredManuscripts + filteredLooseDrafts).map(\.id))
        return snapshot.recent.filter { visibleIDs.contains($0.workItemID) }
    }

    private var isFiltering: Bool {
        selectedChip != .all || !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            searchBar
            filterChipsRow

            if let ao3Error {
                ao3ErrorBanner(ao3Error)
            }

            if isLoadingAO3 && snapshot.allWorks.isEmpty {
                ProgressView("Loading your writing…")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 16)
                    .accentFill()
            } else if filteredManuscripts.isEmpty && filteredLooseDrafts.isEmpty {
                emptyStateCard
            } else {
                if !filteredRecent.isEmpty { recentSection }
                if !filteredManuscripts.isEmpty { manuscriptsSection }
                if !filteredLooseDrafts.isEmpty { looseDraftsSection }
            }
        }
        .navigationDestination(item: $addedChapterRoute) { route in
            LocalChapterEditorScreen(
                workID: route.workID,
                chapterID: route.chapterID,
                initialWorkTitle: route.workTitle,
                store: store
            )
        }
        .navigationDestination(item: $addedAO3ChapterRoute) { route in
            WritingChapterDestination(
                workID: route.workID,
                workTitle: route.workTitle,
                chapterID: nil,
                chapterCount: route.chapterCount
            ) {
                onChanged()
            }
        }
        .alert(
            "Couldn't Add Chapter",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: - Search & Chips

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(.secondaryInk)
                .accessibilityHidden(true)

            TextField(
                "Search your writing",
                text: $searchQuery,
                prompt: theme.appTheme.sepiaPrompt("Search your writing")
            )
            .textFieldStyle(.plain)
            .accessibilityLabel("Search your writing")

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondaryInk)
                }
                .buttonStyle(.plain)
                .minimumHitTarget(32)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.appTheme.glassFill(0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(theme.appTheme.glassStroke(0.13), lineWidth: 0.5)
                )
        )
    }

    private var filterChipsRow: some View {
        AccessibilityChipRail(spacing: 8) {
            ForEach(StudioDocumentsFilterChip.allCases) { chip in
                let isSelected = selectedChip == chip
                let count = snapshot.chipCounts[chip] ?? 0
                let labelText: String = if chip == .all || count == 0 {
                    chip.title
                } else {
                    "\(chip.title) \(count)"
                }
                Button {
                    selectedChip = chip
                } label: {
                    SubjectChip(
                        text: labelText,
                        style: .pill(isSelected: isSelected),
                        palette: theme.scopePalette,
                        fontWeight: .semibold
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    chip == .all ? "Show all writing" : "Show \(chip.title), \(count)"
                )
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func ao3ErrorBanner(_ message: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Try Again", action: onRetryAO3)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(theme.accentInk)
                .buttonStyle(.plain)
                .minimumHitTarget()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .subjectPanel()
    }

    // MARK: - Recent

    private var recentSection: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 14, alignment: .top),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
        )
        return VStack(alignment: .leading, spacing: 10) {
            Text("Recent")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.primary)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(filteredRecent) { item in
                    recentCardLink(item)
                }
            }
        }
    }

    @ViewBuilder
    private func recentCardLink(_ item: StudioRecentDocumentItem) -> some View {
        let cardLabel = StudioRecentPaperCard(item: item)
        let spoken = [item.badgeText, item.title, item.metaLine]
            .compactMap(\.self)
            .joined(separator: ", ")

        switch item.target {
        case let .localChapter(workID, chapterID, workTitle):
            NavigationLink {
                LocalChapterEditorScreen(
                    workID: workID,
                    chapterID: chapterID,
                    initialWorkTitle: workTitle,
                    store: store
                )
            } label: {
                cardLabel
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .accessibilityAddTraits(.isButton)

        case let .localWork(workID, workTitle):
            NavigationLink {
                LocalChapterEditorScreen(
                    workID: workID,
                    chapterID: nil,
                    initialWorkTitle: workTitle,
                    store: store
                )
            } label: {
                cardLabel
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .accessibilityAddTraits(.isButton)

        case let .ao3Draft(workID):
            if auth.isLoggedIn {
                NavigationLink {
                    WritingWorkDestination(workID: workID) { onChanged() }
                } label: {
                    cardLabel
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken)
                .accessibilityAddTraits(.isButton)
            } else {
                cardLabel
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spoken)
            }

        case .ao3PostedWork:
            if let workItem = snapshot.allWorks.first(where: { $0.id == item.workItemID }) {
                NavigationLink {
                    StudioWorkFilesView(work: workItem, store: store, onChanged: onChanged)
                } label: {
                    cardLabel
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken)
                .accessibilityAddTraits(.isButton)
            } else {
                cardLabel
            }
        }
    }

    // MARK: - Manuscripts & Loose Drafts

    private var manuscriptsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Manuscripts")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.primary)
                .accessibilityAddTraits(.isHeader)

            if let featured = filteredManuscripts.first {
                StudioFeaturedManuscriptCard(
                    work: featured,
                    store: store,
                    onChanged: onChanged,
                    onAddChapter: { Task { await addChapter(to: featured) } }
                )
            }

            let remaining = Array(filteredManuscripts.dropFirst())
            if !remaining.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(remaining.enumerated()), id: \.element.id) { index, work in
                        StudioManuscriptListRow(work: work, store: store, onChanged: onChanged)
                        if index < remaining.count - 1 {
                            SubjectRowSeparator(inset: 14)
                        }
                    }
                }
                .subjectPanel()
            }
        }
    }

    private var looseDraftsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Loose Drafts")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                NavigationLink {
                    LocalChapterEditorScreen(store: store)
                } label: {
                    Text("New Draft")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.accentInk)
                }
                .buttonStyle(.plain)
                .minimumHitTarget()
                .accessibilityLabel("New loose draft")
            }

            VStack(spacing: 0) {
                ForEach(Array(filteredLooseDrafts.enumerated()), id: \.element.id) { index, item in
                    StudioLooseDraftRow(item: item, store: store)
                    if index < filteredLooseDrafts.count - 1 {
                        SubjectRowSeparator(inset: 46)
                    }
                }
            }
            .subjectPanel()
        }
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isFiltering {
                Text("No matching documents")
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                Text("Try clearing your search or switching back to All.")
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Show All") {
                    selectedChip = .all
                    searchQuery = ""
                }
                .buttonStyle(.kudosSecondary)
            } else {
                Text("No documents yet")
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                Text(
                    "Start writing on this \(ThisDevice.name). "
                        + "Local drafts work without signing in to AO3."
                )
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                NavigationLink {
                    LocalChapterEditorScreen(store: store)
                } label: {
                    Label("New Document", systemImage: "square.and.pencil")
                }
                .buttonStyle(.kudosPrimary)
                .accessibilityLabel("New Document")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .subjectPanel()
    }

    private func addChapter(to work: StudioWorkItem) async {
        if let localWork = work.localWork {
            do {
                let chapter = try await store.addChapter(workID: localWork.id, title: "")
                onChanged()
                addedChapterRoute = AddedChapterRoute(
                    workID: localWork.id,
                    chapterID: chapter.id,
                    workTitle: work.title
                )
            } catch {
                actionError = UserFacingError.message(for: error)
            }
            return
        }

        if let ao3WorkID = work.ao3WorkID, work.isPostedOnAO3, auth.isLoggedIn {
            addedAO3ChapterRoute = AddedAO3ChapterRoute(
                workID: ao3WorkID,
                workTitle: work.title,
                chapterCount: work.chapterCountForDisplay
            )
            return
        }

        do {
            let createdWork = try await store.createWork(
                title: work.title,
                ao3WorkID: work.ao3WorkID
            )
            let chapter = try await store.addChapter(workID: createdWork.id, title: "")
            onChanged()
            addedChapterRoute = AddedChapterRoute(
                workID: createdWork.id,
                chapterID: chapter.id,
                workTitle: createdWork.title
            )
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }
}
