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
    /// Live story-note name suggestions rendered in the iOS fallback keys bar when active.
    var nameSuggestions: [String] = []
    /// Called when the writer taps a name chip in the iOS fallback keys bar.
    var onSelectNameSuggestion: ((String) -> Void)?
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
    var canAddNote: Bool = false
    var canFormat: Bool = true
    var canEditChapterMetadata: Bool = true
    var canOpenWorkDetails: Bool = false
    var canEditTags: Bool = false
    var canCopyAsAO3HTML: Bool = true
    var canSendToBeta: Bool = false
    var availableExportFormats: [EditorExportFormat] = []
    var canDeleteChapter: Bool = false
    var savedVersionCount: Int?

    /// Exact set of implemented actions shown in `EditorMoreMenu`.
    /// Unimplemented actions (Share, Compare with Posted, Discard Changes, Export As formats
    /// without an exporter, Print, Version History, Writing Tools) are excluded.
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
        if canSendToBeta { actions.insert(.sendToBeta) }
        if canAddNote { actions.insert(.addNote) }
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
    var sendToBeta: () -> Void = {}
    var addNote: () -> Void = {}
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
        if visible.contains(.sendToBeta) { actions.onSendToBeta = handlers.sendToBeta }
        if visible.contains(.addNote) { actions.onAddNote = handlers.addNote }
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

        // Styles the source app used that AO3 can't show (the page's paste cleaner counts them, §6.8).
        for property in (event.styles ?? [:]).keys.sorted() {
            guard let count = event.styles?[property], count > 0 else { continue }
            removed.append(PasteChangeItem(id: "style:\(property)", label: Self.styleLabel(property), count: count))
        }

        var kept: [PasteChangeItem] = []
        if let pasteKept = event.kept {
            for kind in Self.keptOrder where (pasteKept[kind] ?? 0) > 0 {
                let count = pasteKept[kind] ?? 0
                kept.append(PasteChangeItem(id: "kept:\(kind)", label: Self.keptLabel(kind, count: count), count: count))
            }
        } else if event.loss.preserved > 0 {
            let count = event.loss.preserved
            let label = count == 1 ? "preserved HTML block" : "preserved HTML blocks"
            kept.append(PasteChangeItem(id: "preserved", label: label, count: count))
        }

        return PasteLossReport(
            wordCount: event.words,
            sourceName: Self.sourceName(event.source),
            kept: kept,
            removed: removed,
            normalized: normalized
        )
    }

    /// The app a paste came from, as the page told it apart (`editor-core/src/paste/`); nil when it can't be told.
    static func sourceName(_ source: String?) -> String? {
        switch source {
        case "google-docs": "Google Docs"
        case "word": "Word"
        case "apple": "Pages or Notes"
        case "ao3": "an AO3 work"
        case "web": "a web page"
        default: nil
        }
    }

    /// Formatting first, in the Format panel's order, then structure.
    static let keptOrder = [
        "italic", "bold", "underline", "strikethrough", "superscript", "subscript", "smaller", "code", "link",
        "paragraph", "heading", "quote", "list", "sceneBreak", "centred", "aligned", "foldOut", "image", "preserved",
    ]

    static func keptLabel(_ kind: String, count: Int) -> String {
        let one = count == 1
        return switch kind {
        case "italic": "italics"
        case "bold": "bold"
        case "underline": "underline"
        case "strikethrough": "strikethrough"
        case "superscript": "superscript"
        case "subscript": "subscript"
        case "smaller": "smaller text"
        case "code": "code"
        case "link": one ? "link" : "links"
        case "paragraph": one ? "paragraph" : "paragraphs"
        case "heading": one ? "heading" : "headings"
        case "quote": one ? "quote" : "quotes"
        case "list": one ? "list" : "lists"
        case "sceneBreak": one ? "scene break" : "scene breaks"
        case "centred": one ? "centred line" : "centred lines"
        case "aligned": one ? "aligned paragraph" : "aligned paragraphs"
        case "foldOut": one ? "fold-out section" : "fold-out sections"
        case "image": one ? "image" : "images"
        case "preserved": one ? "preserved HTML block" : "preserved HTML blocks"
        default: kind
        }
    }

    static func styleLabel(_ property: String) -> String {
        switch property {
        case "color": "text colours"
        case "background", "background-color": "highlight colours"
        case "font-family": "fonts"
        case "font-size": "text sizes"
        case "font-variant", "text-transform": "small caps and capitals"
        case "letter-spacing": "letter spacing"
        case "text-shadow": "text shadows"
        default: property
        }
    }
}
