import Foundation
import SwiftUI

/// Options for hosting `WritingTextEditor` inside a parent chapter editor screen
/// so the parent reuses its `DraftSession`, `RichEditorHost`, checkpointing, and
/// recovery copies without creating a second session.
struct WritingTextEditorEmbedOptions {
    /// Starts in Rich Text mode immediately after the session is created when the
    /// Rich Text feature flag is enabled and the field supports Rich Text.
    var startsInRichMode: Bool = true
    /// Called once `WritingTextEditor` creates its `DraftSession`.
    var onSessionReady: ((DraftSession) -> Void)?
    /// Called once `WritingTextEditor` creates or claims its `RichEditorHost`.
    var onRichHostReady: ((RichEditorHost) -> Void)?
    /// Intercepts `RichEditorHostCommand`s before `WritingTextEditor`'s default handler.
    /// Return `true` if handled by the parent; return `false` to fall through to the session.
    var onHostCommand: ((RichEditorHostCommand) -> Bool)?
}

/// Which editor opens from `AddChapterView` and `WorkEditView` depending on
/// `RichEditorFeatureFlag.isEnabled`.
nonisolated enum ChapterEditorEntryDestination: Equatable, Hashable, Sendable {
    case legacyFieldEditor
    case richChapterEditor
}

/// Pure flag-gating policy shared by `AddChapterView`, `WorkEditView`, and tests.
nonisolated enum ChapterEditorEntryPolicy {
    static func addChapterDestination(flagEnabled: Bool) -> ChapterEditorEntryDestination {
        flagEnabled ? .richChapterEditor : .legacyFieldEditor
    }

    static func workEditChapter1Destination(
        flagEnabled: Bool,
        contentServed: Bool
    ) -> ChapterEditorEntryDestination {
        guard flagEnabled, contentServed else { return .legacyFieldEditor }
        return .richChapterEditor
    }
}

/// Declares which actions are implemented and available in the current `ChapterEditorScreen`
/// context. Anything unavailable is hidden from `EditorMoreMenu` rather than shown disabled.
nonisolated struct ChapterEditorMenuCapabilities: Equatable, Hashable, Sendable {
    var isPosted: Bool = false
    var hasUnpostedChanges: Bool = false
    var canPostOrUpdate: Bool = false
    var canSaveAsAO3Draft: Bool = false
    var canPreview: Bool = false
    var canFind: Bool = false
    var canFormat: Bool = true
    var canEditChapterMetadata: Bool = true
    var canOpenWorkDetails: Bool = false
    var canEditTags: Bool = false
    var canCopyAsAO3HTML: Bool = true
    var availableExportFormats: [EditorExportFormat] = []
    var canDeleteChapter: Bool = false
    var savedVersionCount: Int?

    /// Exact set of implemented actions shown in `EditorMoreMenu`.
    /// Unimplemented actions (Share, Compare with Posted, Discard Changes, Export As formats
    /// without an exporter, Send to a Beta, Print, Version History, Writing Tools) are excluded.
    var visibleActions: Set<EditorMoreMenuActionID> {
        var actions: Set<EditorMoreMenuActionID> = []
        if canPostOrUpdate { actions.insert(.postOrUpdate) }
        if canPreview { actions.insert(.preview) }
        if canFind { actions.insert(.find) }
        if canSaveAsAO3Draft, !isPosted { actions.insert(.saveAsAO3Draft) }
        if canEditChapterMetadata { actions.insert(.chapterMetadata) }
        if canOpenWorkDetails { actions.insert(.workDetails) }
        if canEditTags { actions.insert(.editTags) }
        if canCopyAsAO3HTML { actions.insert(.copyAsAO3HTML) }
        if canFormat { actions.insert(.format) }
        if canDeleteChapter { actions.insert(.deleteChapter) }
        for format in availableExportFormats {
            actions.insert(.exportFormat(format))
        }
        return actions
    }

    func menuModel(deviceName: String = "iPhone") -> EditorMoreMenuModel {
        EditorMoreMenuModel.build(
            isPosted: isPosted,
            hasUnpostedChanges: hasUnpostedChanges,
            savedVersionCount: savedVersionCount,
            deviceName: deviceName,
            visibleActions: visibleActions,
            availableExportFormats: availableExportFormats
        )
    }
}

/// Callback targets for every implemented `EditorMoreMenu` action wired by `ChapterEditorScreen`.
struct ChapterEditorMoreMenuHandlers {
    var postOrUpdate: () -> Void = {}
    var preview: () -> Void = {}
    var find: () -> Void = {}
    var saveAsAO3Draft: () -> Void = {}
    var chapterMetadata: () -> Void = {}
    var workDetails: () -> Void = {}
    var editTags: () -> Void = {}
    var exportFormat: (EditorExportFormat) -> Void = { _ in }
    var copyAsAO3HTML: () -> Void = {}
    var format: () -> Void = {}
    var deleteChapter: () -> Void = {}
}

/// Shared menu wiring used by both `ChapterEditorScreen` and unit tests: builds the filtered
/// `EditorMoreMenuModel` and dispatches only visible, implemented actions to their handlers.
struct ChapterEditorMoreMenuWiring {
    let capabilities: ChapterEditorMenuCapabilities
    let handlers: ChapterEditorMoreMenuHandlers

    func model(deviceName: String = "iPhone") -> EditorMoreMenuModel {
        capabilities.menuModel(deviceName: deviceName)
    }

    func actions() -> EditorMoreMenuActions {
        let visible = capabilities.visibleActions
        var actions = EditorMoreMenuActions()
        if visible.contains(.postOrUpdate) { actions.onPostOrUpdate = handlers.postOrUpdate }
        if visible.contains(.preview) { actions.onPreview = handlers.preview }
        if visible.contains(.find) { actions.onFind = handlers.find }
        if visible.contains(.saveAsAO3Draft) { actions.onSaveAsAO3Draft = handlers.saveAsAO3Draft }
        if visible.contains(.chapterMetadata) { actions.onChapterMetadata = handlers.chapterMetadata }
        if visible.contains(.workDetails) { actions.onWorkDetails = handlers.workDetails }
        if visible.contains(.editTags) { actions.onEditTags = handlers.editTags }
        if !capabilities.availableExportFormats.isEmpty {
            let allowed = Set(capabilities.availableExportFormats)
            actions.onExport = { format in
                if allowed.contains(format) {
                    handlers.exportFormat(format)
                }
            }
        }
        if visible.contains(.copyAsAO3HTML) { actions.onCopyAsAO3HTML = handlers.copyAsAO3HTML }
        if visible.contains(.format) { actions.onFormat = handlers.format }
        if visible.contains(.deleteChapter) { actions.onDeleteChapter = handlers.deleteChapter }
        return actions
    }
}

/// Tracks `DraftSession.lastPaste` sequence numbers so `PasteReportCard` appears only
/// for a genuinely new paste and never reappears for the same sequence after dismissal.
nonisolated struct ChapterEditorPasteTracker: Equatable, Sendable {
    private(set) var lastSeenSequence: Int?
    private(set) var activeSequence: Int?
    private(set) var activeReport: PasteLossReport?

    init(lastSeenSequence: Int? = nil) {
        self.lastSeenSequence = lastSeenSequence
    }

    /// Processes the session's latest paste report. Returns `true` when a new card is shown.
    @discardableResult
    mutating func receive(_ paste: DraftPasteReport?) -> Bool {
        guard let paste else { return false }
        guard paste.sequence != lastSeenSequence else { return false }
        lastSeenSequence = paste.sequence
        activeSequence = paste.sequence
        activeReport = Self.makeLossReport(from: paste.event)
        return true
    }

    /// Dismisses the visible paste card while remembering its sequence so it stays hidden.
    mutating func dismiss() {
        activeSequence = nil
        activeReport = nil
    }

    /// Converts a bridge `RichEditorPasteEvent` into a native `PasteLossReport`.
    /// Never invents a clipboard source app name.
    static func makeLossReport(from event: RichEditorPasteEvent) -> PasteLossReport {
        var removed: [PasteChangeItem] = []
        for tag in event.loss.dropped.elements.keys.sorted() {
            guard let count = event.loss.dropped.elements[tag], count > 0 else { continue }
            let label = count == 1 ? "<\(tag)> tag" : "<\(tag)> tags"
            removed.append(PasteChangeItem(id: "elem:\(tag)", label: label, count: count))
        }
        for attribute in event.loss.dropped.attributes.keys.sorted() {
            guard let count = event.loss.dropped.attributes[attribute], count > 0 else { continue }
            let label = count == 1 ? "\(attribute) attribute" : "\(attribute) attributes"
            removed.append(PasteChangeItem(id: "attr:\(attribute)", label: label, count: count))
        }

        var normalized: [PasteChangeItem] = []
        for tag in event.loss.unwrapped.keys.sorted() {
            guard let count = event.loss.unwrapped[tag], count > 0 else { continue }
            let label = count == 1 ? "<\(tag)> wrapper" : "<\(tag)> wrappers"
            normalized.append(PasteChangeItem(id: "unwrap:\(tag)", label: label, count: count))
        }
        if event.loss.normalized > 0 {
            let count = event.loss.normalized
            let label = count == 1 ? "markup detail" : "markup details"
            normalized.append(PasteChangeItem(id: "normalized", label: label, count: count))
        }

        var kept: [PasteChangeItem] = []
        if event.loss.preserved > 0 {
            let count = event.loss.preserved
            let label = count == 1 ? "preserved HTML block" : "preserved HTML blocks"
            kept.append(PasteChangeItem(id: "preserved", label: label, count: count))
        }

        return PasteLossReport(
            wordCount: event.words,
            sourceName: nil,
            kept: kept,
            removed: removed,
            normalized: normalized
        )
    }
}
