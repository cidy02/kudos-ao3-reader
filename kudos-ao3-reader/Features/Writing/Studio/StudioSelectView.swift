import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Capabilities computed from the currently selected works in `StudioSelectView`.
/// Each bulk action is enabled strictly where it applies to what is selected.
nonisolated struct StudioSelectCapabilities: Equatable, Sendable {
    let selectedCount: Int
    let postedCount: Int
    let ao3DraftCount: Int
    let localOnlyCount: Int

    let editTogetherWorkIDs: [Int]
    let orphanWorkIDs: [Int]
    let orphanFallbackTitles: [String]
    let exportableLocalWorkIDs: [UUID]
    let deleteAO3WorkIDs: [Int]
    let deleteLocalWorkIDs: [UUID]
    let deleteTitles: [String]

    let canEditTogether: Bool
    let canExport: Bool
    let canOrphan: Bool
    let canDelete: Bool
    let isOverOrphanCap: Bool
    let isSignedIn: Bool

    func summaryText(deviceName: String) -> String {
        guard selectedCount > 0 else {
            return "Select works to edit, export, orphan, or delete."
        }
        var breakdown: [String] = []
        if postedCount > 0 {
            breakdown.append(postedCount == 1 ? "1 posted work" : "\(postedCount) posted works")
        }
        if ao3DraftCount > 0 {
            breakdown.append(ao3DraftCount == 1 ? "1 AO3 draft" : "\(ao3DraftCount) AO3 drafts")
        }
        if localOnlyCount > 0 {
            breakdown.append(
                localOnlyCount == 1
                    ? "1 on this \(deviceName)"
                    : "\(localOnlyCount) on this \(deviceName)"
            )
        }
        let counts = Self.joinedList(breakdown)

        if !isSignedIn, !deleteAO3WorkIDs.isEmpty || postedCount > 0 || ao3DraftCount > 0 {
            return "\(counts) · Sign in to AO3 to edit, orphan, or delete AO3 works."
        }
        if isOverOrphanCap {
            return "\(counts) · Orphan supports up to \(StudioSelectPolicy.maxOrphanWorks) works at a time."
        }
        if canEditTogether {
            return "\(counts) · Edit Together changes them all at once on AO3."
        }
        if localOnlyCount == selectedCount {
            return "\(counts) · Export or move to Recently Deleted."
        }
        return "\(counts) · Deselect on-device works to edit on AO3."
    }

    private static func joinedList(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        case 2: "\(items[0]) and \(items[1])"
        default: items.dropLast().joined(separator: ", ") + ", and " + (items.last ?? "")
        }
    }
}

/// Pure applicability rules for `Studio-Select`.
nonisolated enum StudioSelectPolicy {
    /// Matches `EditMultipleWorksView.maxOrphanWorks` (URL length safety cap).
    static let maxOrphanWorks = 100

    static func evaluate(
        selected: [StudioWorkItem],
        isSignedIn: Bool
    ) -> StudioSelectCapabilities {
        var postedIDs: [Int] = []
        var postedTitles: [String] = []
        var ao3IDs: [Int] = []
        var ao3DraftOnlyCount = 0
        var localOnlyCount = 0
        var exportableLocalIDs: [UUID] = []
        var localIDs: [UUID] = []

        for item in selected {
            if let posted = item.ao3PostedWork {
                postedIDs.append(posted.id)
                postedTitles.append(item.title)
                ao3IDs.append(posted.id)
            } else if let draft = item.ao3DraftWork {
                ao3DraftOnlyCount += 1
                ao3IDs.append(draft.id)
            } else {
                localOnlyCount += 1
            }

            if let localWork = item.localWork {
                localIDs.append(localWork.id)
                exportableLocalIDs.append(localWork.id)
            }
        }

        let allOnAO3 = !selected.isEmpty && localOnlyCount == 0 && !ao3IDs.isEmpty
        let allPosted = !selected.isEmpty && ao3DraftOnlyCount == 0 && localOnlyCount == 0 && !postedIDs.isEmpty
        let overOrphanCap = allPosted && postedIDs.count > maxOrphanWorks

        let canEditTogether = isSignedIn && allOnAO3
        let canExport = !exportableLocalIDs.isEmpty
        let canOrphan = isSignedIn && allPosted && postedIDs.count <= maxOrphanWorks
        let canDelete = !selected.isEmpty && (isSignedIn || ao3IDs.isEmpty)

        return StudioSelectCapabilities(
            selectedCount: selected.count,
            postedCount: postedIDs.count,
            ao3DraftCount: ao3DraftOnlyCount,
            localOnlyCount: localOnlyCount,
            editTogetherWorkIDs: canEditTogether ? ao3IDs : [],
            orphanWorkIDs: canOrphan ? postedIDs : [],
            orphanFallbackTitles: canOrphan ? postedTitles : [],
            exportableLocalWorkIDs: exportableLocalIDs,
            deleteAO3WorkIDs: isSignedIn ? ao3IDs : [],
            deleteLocalWorkIDs: localIDs,
            deleteTitles: selected.map(\.title),
            canEditTogether: canEditTogether,
            canExport: canExport,
            canOrphan: canOrphan,
            canDelete: canDelete,
            isOverOrphanCap: overOrphanCap,
            isSignedIn: isSignedIn
        )
    }
}

/// Cross-platform `FileDocument` exporting selected local manuscripts as clean HTML.
nonisolated struct StudioExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.html] }

    var html: String

    init(html: String) {
        self.html = html
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let text = String(data: data, encoding: .utf8) {
            self.html = text
        } else {
            self.html = ""
        }
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(html.utf8))
    }
}

/// Renders local `WritingDocumentStore` manuscripts into an exportable HTML document.
/// Private story notes and annotations are never included.
nonisolated enum StudioWorkExporter {
    struct ExportableWork: Sendable {
        var work: WritingWork
        var chapters: [WritingChapterDocument]
    }

    static func renderHTML(works: [ExportableWork]) -> String {
        let documentTitle = works.count == 1
            ? (works[0].work.title.isEmpty ? "Untitled" : works[0].work.title)
            : "Exported Works"
        var sections: [String] = []
        for entry in works {
            let workTitle = entry.work.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let heading = workTitle.isEmpty ? "Untitled" : workTitle
            var parts: [String] = ["<article>", "<h1>\(escape(heading))</h1>"]
            for (index, chapterDoc) in entry.chapters.enumerated() {
                let rawChapterTitle = chapterDoc.chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if entry.chapters.count > 1 || !rawChapterTitle.isEmpty {
                    let chapterHeading = rawChapterTitle.isEmpty
                        ? "Chapter \(index + 1)"
                        : "\(index + 1). \(rawChapterTitle)"
                    parts.append("<h2>\(escape(chapterHeading))</h2>")
                }
                parts.append(chapterDoc.bodyHTML)
            }
            parts.append("</article>")
            sections.append(parts.joined(separator: "\n"))
        }
        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <title>\(escape(documentTitle))</title>
        </head>
        <body>
        \(sections.joined(separator: "\n<hr>\n"))
        </body>
        </html>
        """
    }

    static func defaultFilename(for works: [WritingWork]) -> String {
        let base: String = if works.count == 1 {
            works[0].title.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            "Kudos-Writing-Export"
        }
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:?*\"<>|"))
        let cleaned = base.unicodeScalars.map { forbidden.contains($0) ? "-" : String($0) }.joined()
        let trimmed = String(cleaned.prefix(64)).trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty ? "Untitled" : trimmed) + ".html"
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// Multi-select management view for Writing Studio works (`Studio-Select`).
struct StudioSelectView: View {
    let works: [StudioWorkItem]
    let store: WritingDocumentStore
    var onChanged: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme

    @State private var selectedIDs: Set<String> = []
    @State private var bulkEditRoute: BulkEditRoute?
    @State private var orphanRoute: OrphanRoute?
    @State private var showingDeleteConfirm = false
    @State private var deleteGeneration: Int?
    @State private var isWorking = false
    @State private var exportDocument: StudioExportDocument?
    @State private var exportFilename = "Export.html"
    @State private var showingExporter = false
    @State private var errorMessage: String?

    private struct BulkEditRoute: Identifiable, Hashable {
        let id = UUID()
        let workIDs: [Int]
    }

    private struct OrphanRoute: Identifiable {
        let id = UUID()
        let workIDs: [Int]
        let fallbackTitles: [String]
    }

    private var selectedWorks: [StudioWorkItem] {
        works.filter { selectedIDs.contains($0.id) }
    }

    private var capabilities: StudioSelectCapabilities {
        StudioSelectPolicy.evaluate(selected: selectedWorks, isSignedIn: auth.isLoggedIn)
    }

    private var allSelected: Bool {
        !works.isEmpty && selectedIDs.count == works.count
    }

    private var navigationTitleText: String {
        selectedIDs.isEmpty ? "Select Works" : "\(selectedIDs.count) Selected"
    }

    var body: some View {
        ScrollView {
            if works.isEmpty {
                ContentUnavailableView(
                    "No Works to Select",
                    systemImage: "checklist",
                    description: Text("Create or import a document first.")
                )
                .padding(.top, 48)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(works.enumerated()), id: \.element.id) { index, item in
                        selectRow(item)
                        if index < works.count - 1 {
                            SubjectRowSeparator(inset: 52)
                        }
                    }
                }
                .padding(.horizontal, SubjectMetrics.gutter)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
        }
        .background(theme.appTheme.contentBackdrop.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            actionFooter
        }
        .navigationTitle(navigationTitleText)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(isWorking)
            }
            if !works.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(allSelected ? "Deselect All" : "Select All") {
                        toggleSelectAll()
                    }
                    .disabled(isWorking)
                }
            }
        }
        .navigationDestination(item: $bulkEditRoute) { route in
            WritingBulkEditDestination(workIDs: route.workIDs) {
                onChanged()
                dismiss()
            }
        }
        .sheet(item: $orphanRoute) { route in
            OrphanSheet(
                target: .works(route.workIDs),
                fallbackTitles: route.fallbackTitles
            ) { _ in
                onChanged()
                dismiss()
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument ?? StudioExportDocument(html: ""),
            contentType: .html,
            defaultFilename: exportFilename
        ) { result in
            if case let .failure(error) = result {
                errorMessage = UserFacingError.message(for: error)
            }
        }
        .alert(deleteAlertTitle, isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) { deleteGeneration = nil }
            Button("Delete", role: .destructive) {
                Task { await performDelete() }
            }
        } message: {
            Text(deleteAlertMessage)
        }
        .alert(
            "Couldn't Complete Action",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func selectRow(_ item: StudioWorkItem) -> some View {
        let isSelected = selectedIDs.contains(item.id)
        let meta = item.selectMetaLine(deviceName: ThisDevice.name)
        return Button {
            toggleSelection(item.id)
        } label: {
            HStack(spacing: 12) {
                selectionCircle(isSelected: isSelected)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(meta)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 12)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title), \(meta)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func selectionCircle(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isSelected ? theme.effectiveTint : Color.clear)
                .overlay(
                    Circle().strokeBorder(
                        isSelected ? Color.clear : theme.appTheme.glassStroke(0.35),
                        lineWidth: 1.5
                    )
                )
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ThemeManager.label(on: theme.effectiveTint))
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }

    private var actionFooter: some View {
        VStack(spacing: 10) {
            if isWorking {
                ProgressView("Working…")
                    .font(.footnote)
                    .accentFill()
            } else {
                Text(capabilities.summaryText(deviceName: ThisDevice.name))
                    .font(.caption)
                    .foregroundStyle(.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        editTogetherButton
                        exportButton
                    }
                    HStack(spacing: 8) {
                        orphanButton
                        deleteButton
                    }
                }
            } else {
                HStack(spacing: 4) {
                    editTogetherButton
                    exportButton
                    orphanButton
                    deleteButton
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(theme.appTheme.cardSurface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.appTheme.appSeparator ?? theme.appTheme.glassStroke(0.16))
                .frame(height: 0.5)
        }
    }

    private var editTogetherButton: some View {
        toolbarAction(
            title: "Edit Together",
            systemImage: "pencil",
            isDestructive: false,
            isEnabled: capabilities.canEditTogether && !isWorking,
            accessibilityHint: "Opens AO3's Edit Multiple Works form for the selected works"
        ) {
            guard !capabilities.editTogetherWorkIDs.isEmpty else { return }
            bulkEditRoute = BulkEditRoute(workIDs: capabilities.editTogetherWorkIDs)
        }
    }

    private var exportButton: some View {
        toolbarAction(
            title: "Export",
            systemImage: "square.and.arrow.up",
            isDestructive: false,
            isEnabled: capabilities.canExport && !isWorking,
            accessibilityHint: "Exports the selected on-device works as HTML"
        ) {
            Task { await prepareExport() }
        }
    }

    private var orphanButton: some View {
        toolbarAction(
            title: "Orphan",
            systemImage: "person.crop.circle.badge.xmark",
            isDestructive: true,
            isEnabled: capabilities.canOrphan && !isWorking,
            accessibilityHint: "Opens AO3's permanent orphan confirmation for the selected posted works"
        ) {
            guard !capabilities.orphanWorkIDs.isEmpty else { return }
            orphanRoute = OrphanRoute(
                workIDs: capabilities.orphanWorkIDs,
                fallbackTitles: capabilities.orphanFallbackTitles
            )
        }
    }

    private var deleteButton: some View {
        toolbarAction(
            title: "Delete",
            systemImage: "trash",
            isDestructive: true,
            isEnabled: capabilities.canDelete && !isWorking,
            accessibilityHint: "Deletes the selected works after confirmation"
        ) {
            deleteGeneration = auth.sessionGeneration
            showingDeleteConfirm = true
        }
    }

    private func toolbarAction(
        title: String,
        systemImage: String,
        isDestructive: Bool,
        isEnabled: Bool,
        accessibilityHint: String,
        action: @escaping () -> Void
    ) -> some View {
        let activeColor = isDestructive ? theme.appTheme.errorColor : theme.accentInk
        return Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.body.weight(.medium))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(activeColor)
            .opacity(isEnabled ? 1 : 0.35)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
    }

    private func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func toggleSelectAll() {
        if allSelected {
            selectedIDs.removeAll()
        } else {
            selectedIDs = Set(works.map(\.id))
        }
    }

    private var deleteAlertTitle: String {
        let count = capabilities.selectedCount
        if !capabilities.deleteAO3WorkIDs.isEmpty {
            return count == 1 ? "Delete 1 work?" : "Delete \(count) works?"
        }
        return count == 1 ? "Move 1 work to Recently Deleted?" : "Move \(count) works to Recently Deleted?"
    }

    private var deleteAlertMessage: String {
        let previewTitles = capabilities.deleteTitles.prefix(3).joined(separator: ", ")
        let overflow = capabilities.deleteTitles.count - 3
        let named = overflow > 0 ? "\(previewTitles), and \(overflow) more" : previewTitles

        let ao3Count = capabilities.deleteAO3WorkIDs.count
        let localCount = capabilities.deleteLocalWorkIDs.count
        if ao3Count > 0 && localCount > 0 {
            return "\(named). Deleting on AO3 is permanent and cannot be undone. "
                + "Local copies on this \(ThisDevice.name) will move to Recently Deleted for 30 days."
        }
        if ao3Count > 0 {
            return "\(named). This permanently deletes the selected works from AO3 and cannot be undone."
        }
        return "\(named). Local works stay in Recently Deleted for 30 days before permanent removal."
    }

    private func prepareExport() async {
        let localIDs = capabilities.exportableLocalWorkIDs
        guard !localIDs.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            var exportables: [StudioWorkExporter.ExportableWork] = []
            for workID in localIDs {
                let work = try await store.openWork(workID)
                let chapters = try await store.listChapters(workID: workID)
                var loadedChapters: [WritingChapterDocument] = []
                for chapter in chapters {
                    let doc = try await store.loadChapter(workID: workID, chapterID: chapter.id)
                    loadedChapters.append(doc)
                }
                exportables.append(.init(work: work, chapters: loadedChapters))
            }
            let html = StudioWorkExporter.renderHTML(works: exportables)
            exportDocument = StudioExportDocument(html: html)
            exportFilename = StudioWorkExporter.defaultFilename(for: exportables.map(\.work))
            showingExporter = true
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func performDelete() async {
        let ao3IDs = capabilities.deleteAO3WorkIDs
        let localIDs = capabilities.deleteLocalWorkIDs
        let expectedGeneration = deleteGeneration ?? auth.sessionGeneration
        deleteGeneration = nil

        isWorking = true
        defer { isWorking = false }

        do {
            if !ao3IDs.isEmpty {
                _ = try await auth.deleteWorks(
                    workIDs: ao3IDs,
                    expectedGeneration: expectedGeneration
                )
            }
            for localID in localIDs {
                try await store.deleteWork(localID)
            }
            selectedIDs.removeAll()
            onChanged()
            dismiss()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}
