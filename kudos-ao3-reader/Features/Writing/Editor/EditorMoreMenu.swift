import Foundation
import SwiftUI

/// Export formats offered in the `Export As` submenu (`Editor-Menu.dc.html`).
nonisolated enum EditorExportFormat: String, CaseIterable, Identifiable, Hashable, Sendable {
    case epub
    case pdf
    case word
    case html
    case markdown
    case plainText

    var id: String { rawValue }

    var title: String {
        switch self {
        case .epub: "EPUB"
        case .pdf: "PDF"
        case .word: "Word"
        case .html: "HTML"
        case .markdown: "Markdown"
        case .plainText: "Plain Text"
        }
    }

    var systemImage: String {
        switch self {
        case .epub: "book.closed"
        case .pdf: "doc.richtext"
        case .word: "doc.text"
        case .html: "chevron.left.forwardslash.chevron.right"
        case .markdown: "number"
        case .plainText: "doc.plaintext"
        }
    }
}

/// Identifiers for every action in `EditorMoreMenu`, used for both UI dispatch and tests.
nonisolated enum EditorMoreMenuActionID: Hashable, Sendable {
    case postOrUpdate
    case preview
    case share
    case find
    case saveAsAO3Draft
    case compareWithPosted
    case discardChanges
    case chapterMetadata
    case workDetails
    case editTags
    case exportFormat(EditorExportFormat)
    case copyAsAO3HTML
    case sendToBeta
    case print
    case versionHistory
    case writingTools
    case addNote
    case format
    case deleteChapter
}

/// Pure, testable descriptor of the `•••` menu's structure (`Editor-Menu.dc.html`,
/// `Studio-Edit-Posted.dc.html`). `EditorMoreMenu` renders directly from this model so
/// tests verify the same titles, roles, and section membership shown on screen.
nonisolated struct EditorMoreMenuModel: Equatable, Sendable {
    struct Item: Identifiable, Equatable, Sendable {
        let id: EditorMoreMenuActionID
        let title: String
        let subtitle: String?
        let systemImage: String
        let isDestructive: Bool
        let isEnabled: Bool

        init(
            id: EditorMoreMenuActionID,
            title: String,
            subtitle: String? = nil,
            systemImage: String,
            isDestructive: Bool = false,
            isEnabled: Bool = true
        ) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.systemImage = systemImage
            self.isDestructive = isDestructive
            self.isEnabled = isEnabled
        }
    }

    let isPosted: Bool
    let hasUnpostedChanges: Bool
    let topRow: [Item]
    let ao3Items: [Item]
    let exportFormats: [EditorExportFormat]
    let exportItems: [Item]
    let documentItems: [Item]
    let deleteItem: Item
    let showsDeleteItem: Bool

    var allVisibleActionIDs: Set<EditorMoreMenuActionID> {
        var ids = Set(
            (topRow + ao3Items + exportItems + documentItems).map(\.id)
        )
        for format in exportFormats {
            ids.insert(.exportFormat(format))
        }
        if showsDeleteItem {
            ids.insert(deleteItem.id)
        }
        return ids
    }

    var showsUnpostedDot: Bool {
        Self.showsUnpostedDot(isPosted: isPosted, hasUnpostedChanges: hasUnpostedChanges)
    }

    var triggerAccessibilityLabel: String {
        Self.triggerAccessibilityLabel(isPosted: isPosted, hasUnpostedChanges: hasUnpostedChanges)
    }

    static func showsUnpostedDot(isPosted: Bool, hasUnpostedChanges: Bool) -> Bool {
        isPosted && hasUnpostedChanges
    }

    static func triggerAccessibilityLabel(isPosted: Bool, hasUnpostedChanges: Bool) -> String {
        if isPosted {
            let base = "More: Update on AO3, AO3 actions, export"
            return hasUnpostedChanges ? "\(base). Changes not yet on AO3" : base
        }
        return "More: Post, AO3 actions, export"
    }

    static func build(
        isPosted: Bool,
        hasUnpostedChanges: Bool,
        savedVersionCount: Int? = nil,
        deviceName: String = "iPhone",
        visibleActions: Set<EditorMoreMenuActionID>? = nil,
        availableExportFormats: [EditorExportFormat]? = nil
    ) -> EditorMoreMenuModel {
        let primaryTitle = isPosted ? "Update on AO3" : "Post"
        let allTopRow: [Item] = [
            Item(id: .postOrUpdate, title: primaryTitle, systemImage: "arrow.up.circle"),
            Item(id: .preview, title: "Preview", systemImage: "eye"),
            Item(id: .share, title: "Share", systemImage: "square.and.arrow.up"),
            Item(id: .find, title: "Find", systemImage: "magnifyingglass")
        ]
        let allAO3Items = buildAO3Items(isPosted: isPosted, hasUnpostedChanges: hasUnpostedChanges)
        let allExportItems: [Item] = [
            Item(
                id: .copyAsAO3HTML,
                title: "Copy as AO3 HTML",
                systemImage: "chevron.left.forwardslash.chevron.right"
            ),
            Item(id: .sendToBeta, title: "Send to a Beta", systemImage: "person"),
            Item(id: .print, title: "Print", systemImage: "printer")
        ]
        let allDocumentItems = buildDocumentItems(
            savedVersionCount: savedVersionCount,
            deviceName: deviceName,
            includesAddNote: visibleActions?.contains(.addNote) == true,
            includesFormat: visibleActions?.contains(.format) == true
        )
        let deleteItem = Item(
            id: .deleteChapter,
            title: "Delete Chapter",
            systemImage: "trash",
            isDestructive: true
        )

        let filter: ([Item]) -> [Item] = { items in
            guard let visibleActions else { return items }
            return items.filter { visibleActions.contains($0.id) }
        }
        let resolvedExportFormats: [EditorExportFormat]
        if let availableExportFormats {
            resolvedExportFormats = availableExportFormats
        } else if let visibleActions {
            resolvedExportFormats = EditorExportFormat.allCases.filter {
                visibleActions.contains(.exportFormat($0))
            }
        } else {
            resolvedExportFormats = EditorExportFormat.allCases
        }

        return EditorMoreMenuModel(
            isPosted: isPosted,
            hasUnpostedChanges: hasUnpostedChanges,
            topRow: filter(allTopRow),
            ao3Items: filter(allAO3Items),
            exportFormats: resolvedExportFormats,
            exportItems: filter(allExportItems),
            documentItems: filter(allDocumentItems),
            deleteItem: deleteItem,
            showsDeleteItem: visibleActions?.contains(.deleteChapter) ?? true
        )
    }

    private static func buildAO3Items(isPosted: Bool, hasUnpostedChanges: Bool) -> [Item] {
        var items: [Item] = []
        if isPosted {
            items.append(
                Item(
                    id: .compareWithPosted,
                    title: "Compare with Posted",
                    systemImage: "arrow.left.arrow.right",
                    isEnabled: hasUnpostedChanges
                )
            )
            items.append(
                Item(
                    id: .discardChanges,
                    title: "Discard Changes",
                    systemImage: "arrow.uturn.backward",
                    isDestructive: true,
                    isEnabled: hasUnpostedChanges
                )
            )
        } else {
            items.append(
                Item(
                    id: .saveAsAO3Draft,
                    title: "Save as AO3 Draft",
                    subtitle: "AO3 keeps drafts for \(DraftExpiry.noticeOffsetDays) days",
                    systemImage: "square.and.arrow.down"
                )
            )
        }
        items.append(contentsOf: [
            Item(
                id: .chapterMetadata,
                title: "Chapter Title, Summary and Notes",
                systemImage: "doc.text"
            ),
            Item(id: .workDetails, title: "Work Details", systemImage: "info.circle"),
            Item(id: .editTags, title: "Edit Tags", systemImage: "tag")
        ])
        return items
    }

    private static func buildDocumentItems(
        savedVersionCount: Int?,
        deviceName: String,
        includesAddNote: Bool,
        includesFormat: Bool
    ) -> [Item] {
        let versionSubtitle = savedVersionCount.map { count in
            "\(count.formatted()) saved \(count == 1 ? "version" : "versions") on this \(deviceName)"
        }
        var items: [Item] = []
        if includesAddNote {
            items.append(Item(id: .addNote, title: "Add Note", systemImage: "note.text.badge.plus"))
        }
        if includesFormat {
            items.append(Item(id: .format, title: "Format", systemImage: "textformat"))
        }
        items.append(contentsOf: [
            Item(
                id: .versionHistory,
                title: "Version History",
                subtitle: versionSubtitle,
                systemImage: "clock.arrow.circlepath"
            ),
            Item(id: .writingTools, title: "Writing Tools", systemImage: "textformat.abc")
        ])
        return items
    }
}

/// Callback bundle for `EditorMoreMenu`. All handlers default to no-ops so callers can wire
/// actions incrementally.
struct EditorMoreMenuActions {
    var onPostOrUpdate: () -> Void = {}
    var onPreview: () -> Void = {}
    var onShare: () -> Void = {}
    var onFind: () -> Void = {}
    var onSaveAsAO3Draft: () -> Void = {}
    var onCompareWithPosted: () -> Void = {}
    var onDiscardChanges: () -> Void = {}
    var onChapterMetadata: () -> Void = {}
    var onWorkDetails: () -> Void = {}
    var onEditTags: () -> Void = {}
    var onExport: (EditorExportFormat) -> Void = { _ in }
    var onCopyAsAO3HTML: () -> Void = {}
    var onSendToBeta: () -> Void = {}
    var onPrint: () -> Void = {}
    var onVersionHistory: () -> Void = {}
    var onWritingTools: () -> Void = {}
    var onAddNote: () -> Void = {}
    var onFormat: () -> Void = {}
    var onDeleteChapter: () -> Void = {}

    func dispatch(_ actionID: EditorMoreMenuActionID) {
        if dispatchPrimaryOrAO3(actionID) { return }
        dispatchExportOrDocument(actionID)
    }

    private func dispatchPrimaryOrAO3(_ actionID: EditorMoreMenuActionID) -> Bool {
        switch actionID {
        case .postOrUpdate: onPostOrUpdate()
        case .preview: onPreview()
        case .share: onShare()
        case .find: onFind()
        case .saveAsAO3Draft: onSaveAsAO3Draft()
        case .compareWithPosted: onCompareWithPosted()
        case .discardChanges: onDiscardChanges()
        case .chapterMetadata: onChapterMetadata()
        case .workDetails: onWorkDetails()
        case .editTags: onEditTags()
        default: return false
        }
        return true
    }

    private func dispatchExportOrDocument(_ actionID: EditorMoreMenuActionID) {
        switch actionID {
        case let .exportFormat(format): onExport(format)
        case .copyAsAO3HTML: onCopyAsAO3HTML()
        case .sendToBeta: onSendToBeta()
        case .print: onPrint()
        case .versionHistory: onVersionHistory()
        case .writingTools: onWritingTools()
        case .addNote: onAddNote()
        case .format: onFormat()
        case .deleteChapter: onDeleteChapter()
        default: break
        }
    }
}

/// Native `Menu` for the editor's `•••` button (`Editor-Menu.dc.html`,
/// `Studio-Edit-Posted.dc.html`).
struct EditorMoreMenu<LabelContent: View>: View {
    let isPosted: Bool
    let hasUnpostedChanges: Bool
    let savedVersionCount: Int?
    let visibleActions: Set<EditorMoreMenuActionID>?
    let availableExportFormats: [EditorExportFormat]?
    let actions: EditorMoreMenuActions
    @ViewBuilder let label: (Bool) -> LabelContent

    init(
        isPosted: Bool = false,
        hasUnpostedChanges: Bool = false,
        savedVersionCount: Int? = nil,
        visibleActions: Set<EditorMoreMenuActionID>? = nil,
        availableExportFormats: [EditorExportFormat]? = nil,
        actions: EditorMoreMenuActions = EditorMoreMenuActions(),
        @ViewBuilder label: @escaping (_ showsUnpostedDot: Bool) -> LabelContent
    ) {
        self.isPosted = isPosted
        self.hasUnpostedChanges = hasUnpostedChanges
        self.savedVersionCount = savedVersionCount
        self.visibleActions = visibleActions
        self.availableExportFormats = availableExportFormats
        self.actions = actions
        self.label = label
    }

    private var model: EditorMoreMenuModel {
        EditorMoreMenuModel.build(
            isPosted: isPosted,
            hasUnpostedChanges: hasUnpostedChanges,
            savedVersionCount: savedVersionCount,
            deviceName: ThisDevice.name,
            visibleActions: visibleActions,
            availableExportFormats: availableExportFormats
        )
    }

    var body: some View {
        let current = model
        Menu {
            if !current.topRow.isEmpty {
                MenuTopRow {
                    ForEach(current.topRow) { item in
                        Button {
                            actions.dispatch(item.id)
                        } label: {
                            Label(item.title, systemImage: item.systemImage)
                        }
                        .disabled(!item.isEnabled)
                    }
                }
            }

            if !current.ao3Items.isEmpty {
                Section("AO3") {
                    ForEach(current.ao3Items) { item in
                        menuButton(for: item)
                    }
                }
            }

            if !current.exportFormats.isEmpty || !current.exportItems.isEmpty {
                Section("Export") {
                    if !current.exportFormats.isEmpty {
                        Menu {
                            ForEach(current.exportFormats) { format in
                                Button {
                                    actions.onExport(format)
                                } label: {
                                    Label(format.title, systemImage: format.systemImage)
                                }
                            }
                        } label: {
                            Text("Export As")
                            Text(current.exportFormats.map(\.title).joined(separator: ", "))
                            Image(systemName: "arrow.down.doc")
                        }
                    }

                    ForEach(current.exportItems) { item in
                        menuButton(for: item)
                    }
                }
            }

            if !current.documentItems.isEmpty {
                Section("This document") {
                    ForEach(current.documentItems) { item in
                        menuButton(for: item)
                    }
                }
            }

            if current.showsDeleteItem {
                Section {
                    menuButton(for: current.deleteItem)
                }
            }
        } label: {
            label(current.showsUnpostedDot)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel(current.triggerAccessibilityLabel)
    }

    private func menuButton(for item: EditorMoreMenuModel.Item) -> some View {
        Button(role: item.isDestructive ? .destructive : nil) {
            actions.dispatch(item.id)
        } label: {
            if let subtitle = item.subtitle {
                Text(item.title)
                Text(subtitle)
                Image(systemName: item.systemImage)
            } else {
                Label(item.title, systemImage: item.systemImage)
            }
        }
        .disabled(!item.isEnabled)
    }
}

extension EditorMoreMenu where LabelContent == EditorMoreTriggerLabel {
    /// Standard `•••` trigger matching `EditorHeader`'s glass capsule.
    init(
        isPosted: Bool = false,
        hasUnpostedChanges: Bool = false,
        savedVersionCount: Int? = nil,
        visibleActions: Set<EditorMoreMenuActionID>? = nil,
        availableExportFormats: [EditorExportFormat]? = nil,
        actions: EditorMoreMenuActions = EditorMoreMenuActions()
    ) {
        self.init(
            isPosted: isPosted,
            hasUnpostedChanges: hasUnpostedChanges,
            savedVersionCount: savedVersionCount,
            visibleActions: visibleActions,
            availableExportFormats: availableExportFormats,
            actions: actions,
            label: { showsDot in
                EditorMoreTriggerLabel(showsUnpostedDot: showsDot)
            }
        )
    }
}

#Preview("Draft Chapter Menu") {
    EditorMoreMenu(
        isPosted: false,
        hasUnpostedChanges: false,
        savedVersionCount: 14
    )
    .glassEffect(.regular, in: Circle())
    .padding()
    .environment(ThemeManager())
}

#Preview("Posted Chapter Menu (Unposted Changes)") {
    EditorMoreMenu(
        isPosted: true,
        hasUnpostedChanges: true,
        savedVersionCount: 14
    )
    .glassEffect(.regular, in: Circle())
    .padding()
    .environment(ThemeManager())
}
