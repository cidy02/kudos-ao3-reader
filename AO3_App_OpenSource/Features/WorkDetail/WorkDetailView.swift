import SwiftUI
import SwiftData

/// Detail screen for a saved work: metadata, tag management, and entry to the reader.
struct WorkDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Bindable var work: SavedWork
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @Query private var allWorks: [SavedWork]

    @State private var newTagName = ""
    @State private var downloading = false
    @State private var loadError: String?
    @State private var goToReader = false

    /// Quick-add suggestions for My Tags: the user's other tags plus this work's
    /// own AO3 tags, minus any already applied (case-insensitive, de-duplicated).
    private var suggestions: [String] {
        let applied = Set(work.tags.map { $0.name.lowercased() })
        var seen = Set<String>()
        var result: [String] = []
        for name in allTags.map(\.name) + work.workTags {
            let key = name.lowercased()
            guard !applied.contains(key), seen.insert(key).inserted else { continue }
            result.append(name)
        }
        return result
    }

    /// Other downloaded works in the same series, ordered by series position.
    private var seriesWorks: [SavedWork] {
        guard !work.seriesTitle.isEmpty else { return [] }
        return allWorks
            .filter { $0.seriesTitle == work.seriesTitle && $0.id != work.id }
            .sorted { $0.seriesPosition < $1.seriesPosition }
    }

    /// The work's summary as readable plain text (EPUB descriptions arrive as HTML).
    private var summaryText: String { work.summary.strippingHTML() }

    private var statusFooter: String {
        if work.isSaved { return "Saved — kept on this device." }
        if !work.hasEPUB { return "Finished. The file was freed to save space; it re-downloads when you read it again." }
        if work.isFinished { return "Finished." }
        if work.isFavorite { return "Favorited, so its file is kept when finished." }
        return "Reading. When you finish, the file is freed unless you save or favorite it."
    }

    /// AO3 Work Tags split into per-category sections (empty categories hidden).
    /// Before the categorized AO3 refresh lands, falls back to one flat list built
    /// from the EPUB's subjects.
    @ViewBuilder
    private var workTagsSections: some View {
        if work.hasCategorizedWorkTags {
            workTagSection("Fandoms", work.workFandoms)
            workTagSection("Characters", work.workCharacters)
            workTagSection("Relationships", work.workRelationships)
            workTagSection("Additional Tags", work.workFreeforms,
                           footer: "Tags from AO3. Add your own below to organize and filter your Library.")
        } else if !work.workTags.isEmpty {
            workTagSection("Work Tags", work.workTags,
                           footer: "Tags from AO3. Add your own below to organize and filter your Library.")
        }
    }

    @ViewBuilder
    private func workTagSection(_ title: String, _ tags: [String], footer: String? = nil) -> some View {
        if !tags.isEmpty {
            Section {
                FlowLayout(spacing: 8, rowSpacing: 8) {
                    ForEach(tags, id: \.self) { TagChip(text: $0) }
                }
                .padding(.vertical, 2)
            } header: {
                Text(title)
            } footer: {
                if let footer { Text(footer) }
            }
        }
    }

    var body: some View {
        Form {
          // Group so .appThemedRows() reaches every section's rows (it doesn't
          // propagate from the Form container, only from a Group/Section/ForEach).
          Group {
            Section {
                Button(action: openReader) {
                    HStack {
                        Label(
                            work.hasEPUB ? "Read" : "Download & Read",
                            systemImage: work.hasEPUB ? "book" : "arrow.down.circle"
                        )
                        Spacer()
                        if downloading { ProgressView() }
                    }
                }
                .disabled(downloading)

                Button {
                    WorkLifecycle.setSaved(work, !work.isSaved, in: context)
                } label: {
                    Label(
                        work.isSaved ? "Saved" : "Save to Keep",
                        systemImage: work.isSaved ? "bookmark.fill" : "bookmark"
                    )
                }

                if work.hasEPUB && !work.isFinished {
                    Button {
                        WorkLifecycle.markFinished(work, in: context)
                    } label: {
                        Label("Mark as Finished", systemImage: "checkmark.circle")
                    }
                }
            } footer: {
                if let loadError {
                    Text(loadError).foregroundStyle(.red)
                } else {
                    Text(statusFooter)
                }
            }

            if !summaryText.isEmpty {
                Section("Summary") {
                    Text(summaryText)
                }
            }

            if !work.seriesTitle.isEmpty {
                Section {
                    LabeledContent("Series", value: work.seriesTitle)
                    if work.seriesPosition > 0 {
                        LabeledContent("Part", value: "\(work.seriesPosition)")
                    }

                    ForEach(seriesWorks) { other in
                        NavigationLink {
                            WorkDetailView(work: other)
                        } label: {
                            HStack {
                                if other.seriesPosition > 0 {
                                    Text("\(other.seriesPosition).")
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                Text(other.title).lineLimit(1)
                            }
                        }
                    }

                    if !work.seriesURL.isEmpty {
                        Button {
                            if let url = URL(string: work.seriesURL) { router.open(url) }
                        } label: {
                            Label("View Full Series on AO3", systemImage: "safari")
                        }
                    }
                } header: {
                    Text("Series")
                } footer: {
                    if seriesWorks.isEmpty {
                        Text("Other works in this series will appear here once you download them.")
                    }
                }
            }

            workTagsSections

            Section("My Tags") {
                if work.tags.isEmpty {
                    Text("No tags yet — add some to organize your Library.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(work.tags.sorted { $0.name < $1.name }) { tag in
                        HStack {
                            Text(tag.name)
                            Spacer()
                            Button {
                                removeTag(tag)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                HStack {
                    TextField("Add a tag", text: $newTagName)
                        .onSubmit(addTypedTag)
                    Button("Add", action: addTypedTag)
                        .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions, id: \.self) { name in
                                Button {
                                    apply(tag(named: name))
                                } label: {
                                    TagChip(text: name)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section("Details") {
                if !work.author.isEmpty {
                    LabeledContent("Author", value: work.author)
                }
                if !work.rating.isEmpty {
                    LabeledContent("Rating", value: work.rating)
                }
                LabeledContent("Added", value: work.dateAdded.formatted(date: .abbreviated, time: .shortened))
                if let url = URL(string: work.sourceURL), !work.sourceURL.isEmpty {
                    Button {
                        router.open(url)   // open in the in-app Browse tab, not the system browser
                    } label: {
                        Label("View on AO3", systemImage: "safari")
                    }
                }
            }
          }
          .appThemedRows()
        }
        .formStyle(.grouped)
        .appThemedScroll()
        .task(id: work.id) {
            backfillWorkTagsIfNeeded()
            await WorkTags.refreshFromAO3(for: work, in: context)
        }
        .navigationDestination(isPresented: $goToReader) {
            BookReaderView(work: work)
        }
        .navigationTitle(work.title)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                Button {
                    work.isFavorite.toggle()
                    try? context.save()
                } label: {
                    Label(
                        work.isFavorite ? "Unfavorite" : "Favorite",
                        systemImage: work.isFavorite ? "star.fill" : "star"
                    )
                }
                .tint(work.isFavorite ? .yellow : nil)
            }
        }
    }

    /// Opens the reader, re-downloading the EPUB first if this is a freed history
    /// entry. Reuses the work's stable id, so progress/tags stay attached.
    private func openReader() {
        if work.hasEPUB { goToReader = true; return }
        guard let id = WorkTags.ao3WorkID(from: work.sourceURL) else {
            loadError = "This work can't be re-downloaded automatically. Open it on AO3."
            return
        }
        Task {
            downloading = true
            loadError = nil
            do {
                let temp = try await AO3Client.shared.downloadEPUB(workID: id)
                try? FileManager.default.removeItem(at: work.fileURL)
                try FileManager.default.moveItem(at: temp, to: work.fileURL)
                work.hasEPUB = true
                work.isFinished = false
                work.lastSpineIndex = 0
                try? context.save()
                goToReader = true
            } catch let error as AO3Error {
                loadError = error.errorDescription
            } catch {
                loadError = error.localizedDescription
            }
            downloading = false
        }
    }

    /// Works imported before Work Tags existed get their tags filled in lazily from
    /// the on-disk EPUB the first time they're opened (history entries without a
    /// file are skipped — they re-populate on their next download).
    private func backfillWorkTagsIfNeeded() {
        guard work.workTags.isEmpty, work.hasEPUB else { return }
        guard let meta = EPUBDocument.metadata(ofEPUBAt: work.fileURL) else { return }
        let tags = SavedWork.normalizedWorkTags(meta.subjects, excludingRating: meta.rating)
        guard !tags.isEmpty else { return }
        work.workTags = tags
        if work.rating.isEmpty { work.rating = meta.rating }
        try? context.save()
    }

    private func addTypedTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        apply(tag(named: trimmed))
        newTagName = ""
    }

    private func apply(_ tag: Tag) {
        if !work.tags.contains(where: { $0.name == tag.name }) {
            work.tags.append(tag)
            try? context.save()
        }
    }

    private func removeTag(_ tag: Tag) {
        work.tags.removeAll { $0.name == tag.name }
        try? context.save()
    }

    /// Returns an existing tag with this name (case-insensitive) or creates one.
    private func tag(named name: String) -> Tag {
        if let existing = allTags.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        let created = Tag(name: name)
        context.insert(created)
        return created
    }
}
