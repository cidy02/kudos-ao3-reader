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
        deviceName: String = "iPhone"
    ) -> EditorMoreMenuModel {
        let primaryTitle = isPosted ? "Update on AO3" : "Post"
        let topRow: [Item] = [
            Item(id: .postOrUpdate, title: primaryTitle, systemImage: "arrow.up.circle"),
            Item(id: .preview, title: "Preview", systemImage: "eye"),
            Item(id: .share, title: "Share", systemImage: "square.and.arrow.up"),
            Item(id: .find, title: "Find", systemImage: "magnifyingglass")
        ]

        var ao3Items: [Item] = []
        if isPosted {
            ao3Items.append(
                Item(
                    id: .compareWithPosted,
                    title: "Compare with Posted",
                    systemImage: "arrow.left.arrow.right",
                    isEnabled: hasUnpostedChanges
                )
            )
            ao3Items.append(
                Item(
                    id: .discardChanges,
                    title: "Discard Changes",
                    systemImage: "arrow.uturn.backward",
                    isDestructive: true,
                    isEnabled: hasUnpostedChanges
                )
            )
        } else {
            ao3Items.append(
                Item(
                    id: .saveAsAO3Draft,
                    title: "Save as AO3 Draft",
                    subtitle: "AO3 keeps drafts for \(DraftExpiry.noticeOffsetDays) days",
                    systemImage: "square.and.arrow.down"
                )
            )
        }
        ao3Items.append(contentsOf: [
            Item(
                id: .chapterMetadata,
                title: "Chapter Title, Summary and Notes",
                systemImage: "doc.text"
            ),
            Item(id: .workDetails, title: "Work Details", systemImage: "info.circle"),
            Item(id: .editTags, title: "Edit Tags", systemImage: "tag")
        ])

        let exportItems: [Item] = [
            Item(
                id: .copyAsAO3HTML,
                title: "Copy as AO3 HTML",
                systemImage: "chevron.left.forwardslash.chevron.right"
            ),
            Item(id: .sendToBeta, title: "Send to a Beta", systemImage: "person"),
            Item(id: .print, title: "Print", systemImage: "printer")
        ]

        let versionSubtitle = savedVersionCount.map { count in
            "\(count.formatted()) saved \(count == 1 ? "version" : "versions") on this \(deviceName)"
        }
        let documentItems: [Item] = [
            Item(
                id: .versionHistory,
                title: "Version History",
                subtitle: versionSubtitle,
                systemImage: "clock.arrow.circlepath"
            ),
            Item(id: .writingTools, title: "Writing Tools", systemImage: "textformat.abc")
        ]

        let deleteItem = Item(
            id: .deleteChapter,
            title: "Delete Chapter",
            systemImage: "trash",
            isDestructive: true
        )

        return EditorMoreMenuModel(
            isPosted: isPosted,
            hasUnpostedChanges: hasUnpostedChanges,
            topRow: topRow,
            ao3Items: ao3Items,
            exportFormats: EditorExportFormat.allCases,
            exportItems: exportItems,
            documentItems: documentItems,
            deleteItem: deleteItem
        )
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
    let actions: EditorMoreMenuActions
    @ViewBuilder let label: (Bool) -> LabelContent

    init(
        isPosted: Bool = false,
        hasUnpostedChanges: Bool = false,
        savedVersionCount: Int? = nil,
        actions: EditorMoreMenuActions = EditorMoreMenuActions(),
        @ViewBuilder label: @escaping (_ showsUnpostedDot: Bool) -> LabelContent
    ) {
        self.isPosted = isPosted
        self.hasUnpostedChanges = hasUnpostedChanges
        self.savedVersionCount = savedVersionCount
        self.actions = actions
        self.label = label
    }

    private var model: EditorMoreMenuModel {
        EditorMoreMenuModel.build(
            isPosted: isPosted,
            hasUnpostedChanges: hasUnpostedChanges,
            savedVersionCount: savedVersionCount,
            deviceName: ThisDevice.name
        )
    }

    var body: some View {
        let current = model
        Menu {
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

            Section("AO3") {
                ForEach(current.ao3Items) { item in
                    menuButton(for: item)
                }
            }

            Section("Export") {
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
                    Text("EPUB, PDF, Word, HTML, Markdown, Plain Text")
                    Image(systemName: "arrow.down.doc")
                }

                ForEach(current.exportItems) { item in
                    menuButton(for: item)
                }
            }

            Section("This document") {
                ForEach(current.documentItems) { item in
                    menuButton(for: item)
                }
            }

            Section {
                menuButton(for: current.deleteItem)
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
        actions: EditorMoreMenuActions = EditorMoreMenuActions()
    ) {
        self.init(
            isPosted: isPosted,
            hasUnpostedChanges: hasUnpostedChanges,
            savedVersionCount: savedVersionCount,
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
