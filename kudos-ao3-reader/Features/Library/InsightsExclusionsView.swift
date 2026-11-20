import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

/// Manages excluded fandoms, tags, and individual works ("Left Out of Insights").
struct InsightsExclusionsView: View {
    struct ExcludedWorkOption: Identifiable {
        let id: String
        let title: String
        let subtitle: String
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var theme

    /// Main Insights scope: filters out live, soft-deleted, and hard-deleted hidden
    /// mature works so their fandoms, tags, and titles never appear as choices.
    let scope: InsightsScopeSelection
    @Binding var excludedFandoms: [String]
    @Binding var excludedTags: [String]
    @Binding var excludedWorkIDs: [String]
    let onChange: (InsightsOptions.ExclusionKind) -> Void

    private var works: [SavedWork] {
        scope.readingWorks
    }

    @State private var searchText = ""
    @State private var sessions: [ReadingSession] = []

    private var availableFandoms: [String] {
        let allRaw = works.flatMap(\.workFandoms)
            + sessions.flatMap(\.fandoms)
            + excludedFandoms
        return uniqueSortedNames(from: allRaw)
    }

    private var availableTags: [String] {
        let workTags = works.flatMap {
            $0.workFreeforms + $0.workRelationships + $0.workCharacters + $0.workTags
        }
        let sessionTags = sessions.flatMap {
            $0.freeformTags + $0.relationships + $0.characters
        }
        return uniqueSortedNames(from: workTags + sessionTags + excludedTags)
    }

    private var availableWorks: [ExcludedWorkOption] {
        var seen: Set<String> = []
        var items: [ExcludedWorkOption] = []
        let sortedWorks = works.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        for work in sortedWorks {
            let key = work.id.uuidString.lowercased()
            guard seen.insert(key).inserted else { continue }
            items.append(ExcludedWorkOption(
                id: key,
                title: work.title,
                subtitle: work.workFandoms.first ?? ""
            ))
        }
        for id in excludedWorkIDs where !seen.contains(id.lowercased()) {
            let sessionTitle = sessions.first {
                $0.workID.uuidString.lowercased() == id.lowercased()
            }?.workTitle
            let title = (sessionTitle?.isEmpty == false ? sessionTitle : nil)
                ?? "Deleted Work (\(id.prefix(8)))"
            items.append(ExcludedWorkOption(
                id: id.lowercased(),
                title: title,
                subtitle: "Not in Library"
            ))
        }
        return items
    }

    private var filteredFandoms: [String] {
        filterBySearch(availableFandoms)
    }

    private var filteredTags: [String] {
        filterBySearch(availableTags)
    }

    private var filteredWorks: [ExcludedWorkOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return availableWorks }
        return availableWorks.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    private var totalExcluded: Int {
        excludedFandoms.count + excludedTags.count + excludedWorkIDs.count
    }

    var body: some View {
        List {
            if availableFandoms.isEmpty && availableTags.isEmpty && availableWorks.isEmpty {
                Section {
                    Text("No fandoms, tags or works available to exclude yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                }
                .appThemedRows()
            } else {
                fandomSection
                worksSection
                tagsSection
            }
        }
        .appThemedScroll()
        .searchable(text: $searchText, prompt: "Filter fandoms, tags or works")
        .navigationTitle("Left Out of Insights")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .wrappingInlineTitle("Left Out of Insights", isActive: dynamicTypeSize.isAccessibilitySize)
        .toolbar {
            if totalExcluded > 0 {
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear All") {
                        excludedFandoms = []
                        excludedTags = []
                        excludedWorkIDs = []
                        onChange(.all)
                    }
                    .foregroundStyle(theme.accentInk)
                }
            }
        }
        .onAppear {
            let allSessions = (try? modelContext.fetch(FetchDescriptor<ReadingSession>())) ?? []
            sessions = scope.sessions(allSessions, in: modelContext)
        }
    }

    @ViewBuilder
    private var fandomSection: some View {
        if !filteredFandoms.isEmpty {
            Section("Fandoms") {
                ForEach(filteredFandoms, id: \.self) { fandom in
                    let selected = isSelected(fandom, in: excludedFandoms)
                    exclusionToggleRow(title: fandom, subtitle: nil, isExcluded: selected) {
                        toggleName(fandom, in: &excludedFandoms, kind: .fandoms)
                    }
                }
            }
            .appThemedRows()
        }
    }

    @ViewBuilder
    private var worksSection: some View {
        if !filteredWorks.isEmpty {
            Section("Works") {
                ForEach(filteredWorks) { item in
                    let selected = isSelected(item.id, in: excludedWorkIDs)
                    exclusionToggleRow(
                        title: item.title,
                        subtitle: item.subtitle.isEmpty ? nil : item.subtitle,
                        isExcluded: selected
                    ) {
                        toggleWorkID(item.id)
                    }
                }
            }
            .appThemedRows()
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        if !filteredTags.isEmpty {
            Section("Tags & Ships") {
                ForEach(filteredTags, id: \.self) { tag in
                    let selected = isSelected(tag, in: excludedTags)
                    exclusionToggleRow(title: tag, subtitle: nil, isExcluded: selected) {
                        toggleName(tag, in: &excludedTags, kind: .tags)
                    }
                }
            }
            .appThemedRows()
        }
    }

    private func exclusionToggleRow(
        title: String,
        subtitle: String?,
        isExcluded: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isExcluded ? "minus.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(isExcluded ? theme.accentInk : Color.secondary.opacity(0.4))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isExcluded ? "Left out of Insights" : "Included in Insights")
        .accessibilityAddTraits(isExcluded ? [.isButton, .isSelected] : .isButton)
    }

    private func uniqueSortedNames(from raw: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for entry in raw {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed.lowercased()).inserted {
                result.append(trimmed)
            }
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func filterBySearch(_ items: [String]) -> [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private func isSelected(_ value: String, in list: [String]) -> Bool {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return list.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key }
    }

    private func toggleName(
        _ value: String,
        in list: inout [String],
        kind: InsightsOptions.ExclusionKind
    ) {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let index = list.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key
        }) {
            list.remove(at: index)
        } else {
            list.append(value)
        }
        onChange(kind)
    }

    private func toggleWorkID(_ id: String) {
        let key = id.lowercased()
        if let index = excludedWorkIDs.firstIndex(where: { $0.lowercased() == key }) {
            excludedWorkIDs.remove(at: index)
        } else {
            excludedWorkIDs.append(key)
        }
        onChange(.workIDs)
    }
}

struct InsightsShareItem: Identifiable, Sendable {
    let id = UUID()
    let url: URL

    static func cleanUp(_ url: URL) {
        let parent = url.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: parent)
    }
}

#if os(iOS)
struct InsightsExportActivitySheet: UIViewControllerRepresentable {
    let url: URL
    let onComplete: @MainActor @Sendable () -> Void

    final class Coordinator {
        var onComplete: (@MainActor @Sendable () -> Void)?

        init(onComplete: @escaping @MainActor @Sendable () -> Void) {
            self.onComplete = onComplete
        }

        func finish() {
            let action = onComplete
            onComplete = nil
            action?()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        let coordinator = context.coordinator
        controller.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in coordinator.finish() }
        }
        return controller
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}

    static func dismantleUIViewController(_: UIActivityViewController, coordinator: Coordinator) {
        coordinator.finish()
    }
}
#else
struct InsightsExportFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .json] }
    var data: Data

    init(data: Data, contentType: UTType) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#endif
