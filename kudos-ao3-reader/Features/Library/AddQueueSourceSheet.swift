import SwiftData
import SwiftUI

/// Picker for attaching any of the four queue source kinds (saved search,
/// author, series, or tag) without making any network call. Shared between
/// `QueueSourcesSheet` (live queue edits) and `EditReadingQueueSheet` (draft edits).
struct AddQueueSourceSheet: View {
    let queueName: String
    let existingSearchIDs: Set<UUID>
    let existingSourceKeys: Set<String>
    let onAddSearch: (SavedSearch) -> Void
    let onAddSource: (QueueSourceDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme
    @Environment(PrivacyGate.self) private var gate
    @AppStorage("hideMatureContent") private var hideMature = true
    @Query(sort: \SavedSearch.name) private var savedSearches: [SavedSearch]
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }, sort: \SavedWork.title)
    private var allLibraryWorks: [SavedWork]
    @Query(sort: \SavedSeries.title) private var allSavedSeries: [SavedSeries]
    @Query(sort: \FollowedTag.name) private var followedTags: [FollowedTag]
    @Query(sort: \ReadingFavorite.displayName) private var favorites: [ReadingFavorite]

    @State private var selectedKind: QueueSourceKind = .savedSearch
    @State private var authorInput = ""
    @State private var authorPseudInput = ""
    @State private var seriesInput = ""
    @State private var seriesTitleInput = ""
    @State private var tagInput = ""
    @State private var tagCategory = ""

    /// Works Hide Mature has not concealed; the lists below never surface an
    /// author, series or tag that only a concealed work carries.
    private var libraryWorks: [SavedWork] {
        allLibraryWorks.filter { !gate.isConcealed($0, enabled: hideMature) }
    }

    private static func seriesID(of work: SavedWork) -> Int? {
        work.ao3SeriesID ?? ReadingQueueService.ao3SeriesID(from: work.seriesURL)
    }

    private var savedSeries: [SavedSeries] {
        let visible = Set(libraryWorks.compactMap(Self.seriesID(of:)))
        let concealed = Set(allLibraryWorks.compactMap { work in
            gate.isConcealed(work, enabled: hideMature) ? Self.seriesID(of: work) : nil
        })
        return allSavedSeries.filter { visible.contains($0.ao3SeriesID) || !concealed.contains($0.ao3SeriesID) }
    }

    private static let tagCategories = ["", "Fandom", "Relationship", "Character", "Freeform"]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    kindPicker
                        .accessibilityLabel("Source kind")
                        .appThemedRows()
                }

                switch selectedKind {
                case .savedSearch:
                    savedSearchSections
                case .author:
                    authorSections
                case .series:
                    seriesSections
                case .tag:
                    tagSections
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .appThemedScroll()
            .navigationTitle("Add a Source")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .screenTint(theme.scopePalette)
    }

    /// Four segments clip to one letter each at accessibility sizes, where a menu
    /// shows the whole word.
    @ViewBuilder
    private var kindPicker: some View {
        let picker = Picker("Source kind", selection: $selectedKind) {
            Text("Search").tag(QueueSourceKind.savedSearch)
            Text("Author").tag(QueueSourceKind.author)
            Text("Series").tag(QueueSourceKind.series)
            Text("Tag").tag(QueueSourceKind.tag)
        }
        if dynamicTypeSize.isAccessibilitySize {
            picker.pickerStyle(.menu)
        } else {
            picker.pickerStyle(.segmented)
        }
    }

    // MARK: - Saved Searches

    @ViewBuilder
    private var savedSearchSections: some View {
        if savedSearches.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("No Saved Searches", systemImage: "magnifyingglass")
                } description: {
                    Text("Save a search from the Search tab, then add it to \(queueName).")
                }
                .appThemedRows()
            }
        } else {
            Section("Saved Searches") {
                ForEach(savedSearches) { search in
                    let alreadyAdded = existingSearchIDs.contains(search.id)
                    let labels = search.filters.summaryLabels()
                    Button {
                        if !alreadyAdded {
                            onAddSearch(search)
                        }
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondaryInk)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(search.name)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if !labels.isEmpty {
                                    Text(labels.prefix(3).map(\.text).joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondaryInk)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 8)
                            if alreadyAdded {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.accentInk)
                                    .accessibilityLabel("Already added")
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(alreadyAdded)
                    .accessibilityLabel(
                        alreadyAdded
                            ? "Saved search \(search.name), already added"
                            : "Add saved search \(search.name)"
                    )
                    .appThemedRows()
                }
            }
        }
    }

    // MARK: - Authors

    private var parsedAuthorDraft: QueueSourceDraft? {
        let trimmed = authorInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // AO3 usernames are letters, digits and underscores: anything with a
        // slash, dot or colon is a link (or nothing), never a literal name.
        if QueueSourceDraft.isURLInput(trimmed) || trimmed.contains(where: { "/.:".contains($0) }) {
            guard let draft = QueueSourceDraft.fromAO3URL(trimmed), draft.kind == .author,
                  let username = draft.authorUsername
            else { return nil }
            return QueueSourceDraft.author(username: username, pseud: draft.authorPseud ?? authorPseudInput)
        }
        return QueueSourceDraft.author(username: trimmed, pseud: authorPseudInput)
    }

    private var knownAuthorDrafts: [QueueSourceDraft] {
        var seen = Set<String>()
        var result: [QueueSourceDraft] = []
        for favorite in favorites where favorite.kind == .author {
            let parts = favorite.targetKey.split(separator: "|", maxSplits: 1).map(String.init)
            guard let username = parts.first, !username.isEmpty else { continue }
            let pseud = parts.count > 1 && parts[1] != "*" ? parts[1] : nil
            if let draft = QueueSourceDraft.author(
                username: username,
                pseud: pseud,
                displayName: favorite.displayName.isEmpty ? nil : favorite.displayName
            ), seen.insert(draft.dedupKey).inserted {
                result.append(draft)
            }
        }
        for work in libraryWorks {
            for identity in work.verifiedAuthorIdentities {
                guard let route = identity.route else { continue }
                if let draft = QueueSourceDraft.author(
                    username: route.username,
                    pseud: route.pseud,
                    displayName: identity.displayName
                ), seen.insert(draft.dedupKey).inserted {
                    result.append(draft)
                }
            }
        }
        return result.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    @ViewBuilder
    private var authorSections: some View {
        Section {
            TextField("AO3 username or author URL", text: $authorInput)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .appThemedRows()
            TextField("Pseud (optional)", text: $authorPseudInput)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .appThemedRows()
            Button("Add Author") {
                guard let draft = parsedAuthorDraft else { return }
                onAddSource(draft)
                dismiss()
            }
            .disabled(parsedAuthorDraft.map { existingSourceKeys.contains($0.dedupKey) } ?? true)
            .appThemedRows()
        } header: {
            Text("AO3 Author")
        } footer: {
            Text("Enter an AO3 username or paste an author or pseud URL.")
                .foregroundStyle(.secondaryInk)
        }

        if !knownAuthorDrafts.isEmpty {
            Section("Authors in Your Library") {
                ForEach(knownAuthorDrafts) { draft in
                    draftRow(draft)
                }
            }
        }
    }

    // MARK: - Series

    private var parsedSeriesDraft: QueueSourceDraft? {
        let trimmed = seriesInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let customTitle = seriesTitleInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleOverride = customTitle.isEmpty ? nil : customTitle
        if let numericID = Int(trimmed), numericID > 0 {
            return QueueSourceDraft.series(id: numericID, title: titleOverride ?? "Series \(numericID)")
        }
        if let draft = QueueSourceDraft.fromAO3URL(trimmed, fallbackTitle: titleOverride),
           draft.kind == .series {
            return draft
        }
        return nil
    }

    private var knownSeriesDrafts: [QueueSourceDraft] {
        var seen = Set<String>()
        var result: [QueueSourceDraft] = []
        for entry in savedSeries where entry.ao3SeriesID > 0 {
            let subtitle = ReadingQueueFacts.seriesSourceSubtitle(
                partCount: entry.snapshot.effectivePartCount,
                isComplete: entry.snapshot.isComplete
            )
            if let draft = QueueSourceDraft.series(
                id: entry.ao3SeriesID,
                title: entry.title,
                subtitle: subtitle
            ), seen.insert(draft.dedupKey).inserted {
                result.append(draft)
            }
        }
        for work in libraryWorks {
            let id = work.ao3SeriesID ?? ReadingQueueService.ao3SeriesID(from: work.seriesURL)
            guard let id, id > 0 else { continue }
            if let draft = QueueSourceDraft.series(
                id: id,
                title: work.seriesTitle.isEmpty ? "Series \(id)" : work.seriesTitle
            ), seen.insert(draft.dedupKey).inserted {
                result.append(draft)
            }
        }
        return result.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    @ViewBuilder
    private var seriesSections: some View {
        Section {
            TextField("AO3 series URL or ID", text: $seriesInput)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .appThemedRows()
            TextField("Series title (optional)", text: $seriesTitleInput)
                .appThemedRows()
            Button("Add Series") {
                guard let draft = parsedSeriesDraft else { return }
                onAddSource(draft)
                dismiss()
            }
            .disabled(parsedSeriesDraft.map { existingSourceKeys.contains($0.dedupKey) } ?? true)
            .appThemedRows()
        } header: {
            Text("AO3 Series")
        } footer: {
            Text("Paste an AO3 series link or enter its numeric ID.")
                .foregroundStyle(.secondaryInk)
        }

        if !knownSeriesDrafts.isEmpty {
            Section("Series in Your Library") {
                ForEach(knownSeriesDrafts) { draft in
                    draftRow(draft)
                }
            }
        }
    }

    // MARK: - Tags

    private var parsedTagDraft: QueueSourceDraft? {
        let trimmed = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let category = tagCategory.isEmpty ? nil : tagCategory
        if QueueSourceDraft.isURLInput(trimmed) {
            if var draft = QueueSourceDraft.fromAO3URL(trimmed), draft.kind == .tag {
                draft.tagCategoryRaw = category
                draft.subtitle = category
                return draft
            }
            return nil
        }
        return QueueSourceDraft.tag(name: trimmed, category: category)
    }

    private var knownTagDrafts: [QueueSourceDraft] {
        var seen = Set<String>()
        var result: [QueueSourceDraft] = []
        for followed in followedTags {
            let url = followed.tagURLString.flatMap { URL(string: $0) }
            if let draft = QueueSourceDraft.tag(
                name: followed.name,
                category: followed.tagCategoryRaw,
                url: url
            ), seen.insert(draft.dedupKey).inserted {
                result.append(draft)
            }
        }
        for favorite in favorites where favorite.kind == .fandom || favorite.kind == .tag {
            let name = favorite.displayName.isEmpty ? favorite.targetKey : favorite.displayName
            let category = favorite.kind == .fandom ? "Fandom" : nil
            if let draft = QueueSourceDraft.tag(name: name, category: category),
               seen.insert(draft.dedupKey).inserted {
                result.append(draft)
            }
        }
        var tagCounts: [String: (name: String, category: String, count: Int)] = [:]
        func note(_ values: [String], category: String) {
            for value in values {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let key = trimmed.lowercased()
                let existing = tagCounts[key]
                tagCounts[key] = (existing?.name ?? trimmed, existing?.category ?? category, (existing?.count ?? 0) + 1)
            }
        }
        for work in libraryWorks {
            note(work.workFandoms, category: "Fandom")
            note(work.workRelationships, category: "Relationship")
            note(work.workCharacters, category: "Character")
            note(work.workFreeforms, category: "Freeform")
        }
        let topLibrary = tagCounts.values.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        for item in topLibrary.prefix(40) {
            if let draft = QueueSourceDraft.tag(name: item.name, category: item.category),
               seen.insert(draft.dedupKey).inserted {
                result.append(draft)
            }
        }
        return result
    }

    @ViewBuilder
    private var tagSections: some View {
        Section {
            TextField("AO3 tag name or tag URL", text: $tagInput)
                .autocorrectionDisabled()
                .appThemedRows()
            Picker("Kind", selection: $tagCategory) {
                ForEach(Self.tagCategories, id: \.self) { category in
                    Text(category.isEmpty ? "Tag" : category).tag(category)
                }
            }
            .appThemedRows()
            Button("Add Tag") {
                guard let draft = parsedTagDraft else { return }
                onAddSource(draft)
                dismiss()
            }
            .disabled(parsedTagDraft.map { existingSourceKeys.contains($0.dedupKey) } ?? true)
            .appThemedRows()
        } header: {
            Text("AO3 Tag")
        } footer: {
            Text("Enter any fandom, relationship, character, or freeform tag, or paste an AO3 tag link.")
                .foregroundStyle(.secondaryInk)
        }

        if !knownTagDrafts.isEmpty {
            Section("Tags in Your Library") {
                ForEach(knownTagDrafts) { draft in
                    draftRow(draft)
                }
            }
        }
    }

    private func draftRow(_ draft: QueueSourceDraft) -> some View {
        let alreadyAdded = existingSourceKeys.contains(draft.dedupKey)
        return Button {
            if !alreadyAdded {
                onAddSource(draft)
            }
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: draft.kind.symbolName)
                    .foregroundStyle(.secondaryInk)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.displayName)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle = draft.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if alreadyAdded {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.accentInk)
                        .accessibilityLabel("Already added")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(alreadyAdded)
        .accessibilityLabel(
            alreadyAdded
                ? "\(draft.kind.kindLabel) \(draft.displayName), already added"
                : "Add \(draft.kind.kindLabel.lowercased()) \(draft.displayName)"
        )
        .appThemedRows()
    }
}
