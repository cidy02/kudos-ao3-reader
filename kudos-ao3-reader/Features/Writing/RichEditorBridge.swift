import Foundation
import OSLog

/// Logger for the Rich Text editor host, bridge, and hand-off state machine.
nonisolated let writingEditorLog = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Kudos",
    category: "writing"
)

/// Normative bridge constants (docs/WRITING_EDITOR_ARCHITECTURE.md §7.2).
nonisolated enum RichEditorBridgeProtocol {
    static let bridgeVersion = 1
    static let schemaVersion = 1
    static let messageHandlerName = "kudos"
}

/// Per-field schema variant and AO3 character limit (§6.6).
nonisolated enum DraftFieldVariant: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case content
    case notes
    case summary

    var maxCharacters: Int {
        switch self {
        case .content: 510_000
        case .notes: 5_000
        case .summary: 1_250
        }
    }

    static func from(field: String) -> DraftFieldVariant {
        switch field.lowercased() {
        case "content": .content
        case "summary": .summary
        default: .notes
        }
    }
}

/// Theme variables sent in `configure` and `setTheme` (§7.2).
nonisolated struct RichEditorTheme: Codable, Equatable, Sendable {
    var background: String
    var text: String
    var accent: String
    var link: String
    var fontFamily: String
    var fontSizePx: Double
    var lineHeight: Double

    static let defaultFontFamily = "'New York', ui-serif, Georgia, serif"
    static let defaultLineHeight = 1.62
}

/// Typed JSON value for open-ended bridge payloads (`command.attrs`, `journal.steps`).
nonisolated enum RichEditorJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([RichEditorJSONValue])
    case object([String: RichEditorJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([RichEditorJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: RichEditorJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}

/// What `load` or `lint` removed, unwrapped, normalized, or preserved (§6.9).
nonisolated struct RichEditorLossReport: Codable, Equatable, Sendable {
    struct Dropped: Codable, Equatable, Sendable {
        var elements: [String: Int]
        var attributes: [String: Int]

        init(elements: [String: Int] = [:], attributes: [String: Int] = [:]) {
            self.elements = elements
            self.attributes = attributes
        }

        var isEmpty: Bool {
            !elements.values.contains { $0 > 0 } && !attributes.values.contains { $0 > 0 }
        }
    }

    var dropped: Dropped
    var unwrapped: [String: Int]
    var normalized: Int
    var preserved: Int

    init(
        dropped: Dropped = Dropped(),
        unwrapped: [String: Int] = [:],
        normalized: Int = 0,
        preserved: Int = 0
    ) {
        self.dropped = dropped
        self.unwrapped = unwrapped
        self.normalized = normalized
        self.preserved = preserved
    }

    static let empty = RichEditorLossReport()

    /// Non-empty `dropped` MUST be confirmed by the writer before switching (§6.9).
    var hasDropped: Bool { !dropped.isEmpty }

    /// Non-blocking changes shown in the "What changed" disclosure (§6.9).
    var hasNonBlockingChanges: Bool {
        unwrapped.values.contains { $0 > 0 } || normalized > 0 || preserved > 0
    }

    /// Confirmation prompt matching §6.9's wording.
    var droppedConfirmationMessage: String {
        var items: [String] = []
        for tag in dropped.elements.keys.sorted() {
            guard let count = dropped.elements[tag], count > 0 else { continue }
            items.append("<\(tag)> ×\(count)")
        }
        for attribute in dropped.attributes.keys.sorted() {
            guard let count = dropped.attributes[attribute], count > 0 else { continue }
            items.append("\(attribute) ×\(count)")
        }
        guard !items.isEmpty else {
            return "AO3 would remove unsupported formatting when you save."
        }
        return "AO3 would remove these when you save: \(items.joined(separator: ", "))"
    }

    /// Summary for the non-blocking "What changed" disclosure (§6.9).
    var nonBlockingChangesSummary: String {
        var parts: [String] = []
        let unwrappedItems = unwrapped.keys.sorted().compactMap { tag -> String? in
            guard let count = unwrapped[tag], count > 0 else { return nil }
            return "<\(tag)> ×\(count)"
        }
        if !unwrappedItems.isEmpty {
            parts.append("Unwrapped (text kept): \(unwrappedItems.joined(separator: ", "))")
        }
        if normalized > 0 {
            parts.append("Normalized: \(normalized)")
        }
        if preserved > 0 {
            parts.append("Preserved verbatim (edit in HTML mode): \(preserved)")
        }
        return parts.joined(separator: "\n")
    }
}

// MARK: - §7.2 Call payloads & results

nonisolated struct RichEditorConfigureArgs: Codable, Equatable, Sendable {
    var bridgeVersion: Int
    var schemaVersion: Int
    var variant: DraftFieldVariant
    var theme: RichEditorTheme
    var locale: String

    init(
        bridgeVersion: Int = RichEditorBridgeProtocol.bridgeVersion,
        schemaVersion: Int = RichEditorBridgeProtocol.schemaVersion,
        variant: DraftFieldVariant,
        theme: RichEditorTheme,
        locale: String = Locale.current.identifier
    ) {
        self.bridgeVersion = bridgeVersion
        self.schemaVersion = schemaVersion
        self.variant = variant
        self.theme = theme
        self.locale = locale
    }
}

nonisolated struct RichEditorConfigureResult: Codable, Equatable, Sendable {
    var bridgeVersion: Int
    var schemaVersion: Int
    var bundleVersion: String
}

nonisolated struct RichEditorLoadArgs: Codable, Equatable, Sendable {
    var html: String
    var revision: Int
}

nonisolated struct RichEditorLoadTiming: Codable, Equatable, Sendable {
    var parseMs: Double
    var buildMs: Double
    var renderMs: Double

    static let zero = RichEditorLoadTiming(parseMs: 0, buildMs: 0, renderMs: 0)
}

nonisolated struct RichEditorLoadResult: Codable, Equatable, Sendable {
    var revision: Int
    var loss: RichEditorLossReport
    var timing: RichEditorLoadTiming
}

nonisolated struct RichEditorActivateArgs: Codable, Equatable, Sendable {
    var caret: Int?
    var focus: Bool

    private enum CodingKeys: String, CodingKey {
        case caret
        case focus
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let caret {
            try container.encode(caret, forKey: .caret)
        } else {
            try container.encodeNil(forKey: .caret)
        }
        try container.encode(focus, forKey: .focus)
    }
}

nonisolated struct RichEditorActivateResult: Codable, Equatable, Sendable {
    var caretFound: Bool
}

nonisolated struct RichEditorEmptyArgs: Codable, Equatable, Sendable {}

nonisolated struct RichEditorEmptyResult: Codable, Equatable, Sendable {}

nonisolated struct RichEditorFreezeResult: Codable, Equatable, Sendable {
    var revision: Int
}

nonisolated struct RichEditorSnapshotArgs: Codable, Equatable, Sendable {
    var caret: Bool
}

nonisolated struct RichEditorSnapshotResult: Codable, Equatable, Sendable {
    var revision: Int
    var html: String
    var caretOffset: Int?
    var words: Int
}

nonisolated struct RichEditorCommandArgs: Codable, Equatable, Sendable {
    var name: String
    var attrs: [String: RichEditorJSONValue]

    init(name: String, attrs: [String: RichEditorJSONValue] = [:]) {
        self.name = name
        self.attrs = attrs
    }
}

nonisolated struct RichEditorCommandResult: Codable, Equatable, Sendable {
    var applied: Bool
}

nonisolated struct RichEditorLintArgs: Codable, Equatable, Sendable {
    var html: String
}

nonisolated struct RichEditorLintResult: Codable, Equatable, Sendable {
    var loss: RichEditorLossReport
}

/// Direction of a §7.11 switch check before a hand-off out of an edited view commits.
nonisolated enum RichEditorSwitchCheckDirection: String, Codable, Equatable, Sendable {
    case sourceToRich
    case richToSource
}

/// §7.11 verification call asking JS to confirm the round trip before commit.
nonisolated struct RichEditorSwitchCheckArgs: Codable, Equatable, Sendable {
    var direction: RichEditorSwitchCheckDirection
    var html: String
}

/// §7.11 verification result. On mismatch (`ok == false`), `candidateHtml` carries
/// the round-tripped text so both texts can be written to recovery copies.
nonisolated struct RichEditorSwitchCheckResult: Codable, Equatable, Sendable {
    var ok: Bool
    var candidateHtml: String
    var reason: String?
}

// MARK: - §7.2 Events (JS -> native)

nonisolated struct RichEditorToolbarState: Codable, Equatable, Sendable {
    var marks: [String]
    var block: String
    var align: String?
    var dir: String?
    var canUndo: Bool
    var canRedo: Bool
    /// Optional page-supplied step name for the system Undo menu item (§10.3 N6),
    /// e.g. `"Typing"` or `"Bold"`.
    var undoTitle: String?
    /// Optional page-supplied step name for the system Redo menu item (§10.3 N6).
    var redoTitle: String?
    /// The selection is in a link (a caret just after one counts), and that link's address.
    var inLink: Bool
    var linkURL: String?

    init(
        marks: [String],
        block: String,
        align: String?,
        dir: String?,
        canUndo: Bool,
        canRedo: Bool,
        undoTitle: String? = nil,
        redoTitle: String? = nil,
        inLink: Bool = false,
        linkURL: String? = nil
    ) {
        self.marks = marks
        self.block = block
        self.align = align
        self.dir = dir
        self.canUndo = canUndo
        self.canRedo = canRedo
        self.undoTitle = undoTitle
        self.redoTitle = redoTitle
        self.inLink = inLink
        self.linkURL = linkURL
    }

    private enum CodingKeys: String, CodingKey {
        case marks, block, align, dir, canUndo, canRedo, undoTitle, redoTitle, inLink, linkURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        marks = try c.decode([String].self, forKey: .marks)
        block = try c.decode(String.self, forKey: .block)
        align = try c.decodeIfPresent(String.self, forKey: .align)
        dir = try c.decodeIfPresent(String.self, forKey: .dir)
        canUndo = try c.decode(Bool.self, forKey: .canUndo)
        canRedo = try c.decode(Bool.self, forKey: .canRedo)
        undoTitle = try c.decodeIfPresent(String.self, forKey: .undoTitle)
        redoTitle = try c.decodeIfPresent(String.self, forKey: .redoTitle)
        inLink = try c.decodeIfPresent(Bool.self, forKey: .inLink) ?? false
        linkURL = try c.decodeIfPresent(String.self, forKey: .linkURL)
    }

    static let empty = RichEditorToolbarState(
        marks: [], block: "body", align: "left", dir: "leftToRight", canUndo: false, canRedo: false
    )
}

/// What the page's paste hook inserted (§6.8, §6.9): sent after every paste or drop into Rich Text.
nonisolated struct RichEditorPasteEvent: Codable, Equatable, Sendable {
    /// What AO3's cleaning removed, unwrapped or normalized in the pasted HTML.
    var loss: RichEditorLossReport
    /// Words pasted, by AO3's count (§3.6).
    var words: Int
    /// `"html"` (the clipboard's rich text) or `"text"` (plain text, paragraphed as AO3 does).
    var kind: String
    /// Where it came from when that can be told: `google-docs`, `word`, `apple` (Pages, Notes, TextEdit), `ao3`
    /// (a copied work page), `web`, or `text`.
    var source: String?
    /// What was kept: FormatMark names for marks (counted as runs of text) and block kinds (`paragraph`, `heading`,
    /// `quote`, `list`, `sceneBreak`, `centred`, `link`, `image`, `preserved`, ...).
    var kept: [String: Int]?
    /// Styles turned into structure before AO3's cleaning, by what they became (`strong`, `em`, `align`, `li`, ...).
    var converted: [String: Int]?
    /// Style properties AO3 can't show (`color`, `font-family`, `font-size`, ...).
    var styles: [String: Int]?
    /// A few removed things, most frequent first, as the writer reads them (`"<font> ×3"`, `"color ×4"`).
    var examples: [String]?
}

nonisolated struct RichEditorJournalPayload: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var fromRevision: Int
    var toRevision: Int
    var steps: [RichEditorJSONValue]
}

nonisolated enum RichEditorEvent: Equatable, Sendable {
    case ready(bundleVersion: String, schemaVersion: Int)
    case edited(revision: Int)
    case toolbarState(RichEditorToolbarState)
    case journal(RichEditorJournalPayload)
    case caretRect(RichEditorCaretRect)
    case mirrorBlocks(RichEditorMirrorBlocksEvent)
    case paste(RichEditorPasteEvent)
    case error(code: String, message: String)

    private struct ReadyPayload: Decodable {
        var bundleVersion: String
        var schemaVersion: Int
    }

    private struct EditedPayload: Decodable {
        var revision: Int
    }

    private struct ErrorPayload: Decodable {
        var code: String
        var message: String
    }

    /// Decodes a `WKScriptMessage.body` JSON object into a typed event.
    /// Supports both flat `{type, ...}` (matching §7.6) and `{type, payload: {...}}`.
    static func decode(from messageBody: Any) throws -> RichEditorEvent {
        let dictionary: [String: Any]
        if let dict = messageBody as? [String: Any] {
            dictionary = dict
        } else if let jsonString = messageBody as? String,
                  let data = jsonString.data(using: .utf8),
                  let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dictionary = dict
        } else {
            throw RichEditorBridgeError.invalidEvent("Expected JSON object")
        }

        guard let type = dictionary["type"] as? String else {
            throw RichEditorBridgeError.invalidEvent("Missing event type")
        }
        let payloadObject = (dictionary["payload"] as? [String: Any]) ?? dictionary
        guard JSONSerialization.isValidJSONObject(payloadObject) else {
            throw RichEditorBridgeError.invalidEvent("Event payload is not valid JSON")
        }
        let data = try JSONSerialization.data(withJSONObject: payloadObject)
        let decoder = JSONDecoder()

        switch type {
        case "ready":
            let payload = try decoder.decode(ReadyPayload.self, from: data)
            return .ready(bundleVersion: payload.bundleVersion, schemaVersion: payload.schemaVersion)
        case "edited":
            let payload = try decoder.decode(EditedPayload.self, from: data)
            return .edited(revision: payload.revision)
        case "toolbarState":
            let payload = try decoder.decode(RichEditorToolbarState.self, from: data)
            return .toolbarState(payload)
        case "journal":
            let payload = try decoder.decode(RichEditorJournalPayload.self, from: data)
            return .journal(payload)
        case "caretRect":
            let payload = try decoder.decode(RichEditorCaretRect.self, from: data)
            return .caretRect(payload)
        case "mirrorBlocks":
            let payload = try decoder.decode(RichEditorMirrorBlocksEvent.self, from: data)
            return .mirrorBlocks(payload)
        case "paste":
            let payload = try decoder.decode(RichEditorPasteEvent.self, from: data)
            return .paste(payload)
        case "error":
            let payload = try decoder.decode(ErrorPayload.self, from: data)
            return .error(code: payload.code, message: payload.message)
        default:
            throw RichEditorBridgeError.invalidEvent("Unknown event type: \(type)")
        }
    }
}

// MARK: - Bridge errors

nonisolated enum RichEditorBridgeError: LocalizedError, Equatable, Sendable {
    case invalidArguments(call: String)
    case invalidResponse(call: String)
    case invalidEvent(String)
    case javaScript(call: String, code: String, message: String)
    case timeout(call: String, duration: Duration)
    case versionMismatch(expectedBridge: Int, actualBridge: Int, expectedSchema: Int, actualSchema: Int)
    case processTerminated
    case notReady(String)
    case bridgeUnavailable

    var errorDescription: String? {
        switch self {
        case let .invalidArguments(call):
            "Couldn't encode arguments for \(call)."
        case let .invalidResponse(call):
            "Unexpected response from \(call)."
        case let .invalidEvent(detail):
            "Invalid editor event: \(detail)."
        case let .javaScript(call, code, message):
            "Editor \(call) failed (\(code)): \(message)"
        case let .timeout(call, _):
            "Editor \(call) timed out."
        case let .versionMismatch(expectedBridge, actualBridge, expectedSchema, actualSchema):
            "Editor bundle mismatch (bridge \(actualBridge) != \(expectedBridge), "
                + "schema \(actualSchema) != \(expectedSchema))."
        case .processTerminated:
            "The Rich Text process ended unexpectedly."
        case let .notReady(reason):
            "Rich Text isn't ready: \(reason)"
        case .bridgeUnavailable:
            "Rich Text isn't available."
        }
    }
}

// MARK: - Typed calls & JSON-only encoder (§7.2)

nonisolated enum RichEditorBridgeCall: Equatable, Sendable {
    case configure(RichEditorConfigureArgs)
    case load(RichEditorLoadArgs)
    case activate(RichEditorActivateArgs)
    case freeze
    case snapshot(RichEditorSnapshotArgs)
    case command(RichEditorCommandArgs)
    case lint(RichEditorLintArgs)
    case setTheme(RichEditorTheme)
    case setAppearance(RichEditorAppearance)
    case setMirror(RichEditorMirrorArgs)
    case dispose
    case verifySwitch(RichEditorSwitchCheckArgs)

    var name: String {
        switch self {
        case .configure: "configure"
        case .load: "load"
        case .activate: "activate"
        case .freeze: "freeze"
        case .snapshot: "snapshot"
        case .command: "command"
        case .lint: "lint"
        case .setTheme: "setTheme"
        case .setAppearance: "setAppearance"
        case .setMirror: "setMirror"
        case .dispose: "dispose"
        case .verifySwitch: "verifySwitch"
        }
    }

    /// Per-call timeouts from §7.2 (and 2 s for §7.11 switch verification).
    var timeout: Duration {
        switch self {
        case .configure, .load, .lint: .seconds(5)
        case .snapshot, .verifySwitch: .seconds(2)
        case .activate, .freeze, .command, .setTheme, .setAppearance, .setMirror, .dispose: .seconds(1)
        }
    }
}

/// Encoded call passed to `WKWebView.callAsyncJavaScript`.
/// `script` is always a compile-time constant; user text travels only inside `argumentsJSON`.
nonisolated struct RichEditorBridgeInvocation: Equatable, Sendable {
    let script: String
    let callName: String
    let argumentsJSON: Data
    let timeout: Duration

    /// Foundation arguments dictionary for `WKWebView.callAsyncJavaScript(_:arguments:in:contentWorld:)`.
    func javaScriptArguments() throws -> [String: Any] {
        let jsonObject = try JSONSerialization.jsonObject(with: argumentsJSON)
        guard let dictionary = jsonObject as? [String: Any] else {
            throw RichEditorBridgeError.invalidArguments(call: callName)
        }
        return [
            "name": callName,
            "args": dictionary,
        ]
    }
}

/// Builds JSON-only `callAsyncJavaScript` invocations and decodes their replies (§7.2).
/// Text is never interpolated into JavaScript source.
nonisolated enum RichEditorBridgeEncoder {
    /// Constant function body for every native → JS call. Wraps `window.KudosEditor.call(name, args)`
    /// so `{code, message}` promise rejections survive WebKit bridging intact instead of collapsing
    /// to `"[object Object]"`.
    static let callScript = """
    try {
      if (!window.KudosEditor || typeof window.KudosEditor.call !== "function") {
        return {
          ok: false,
          error: { code: "bridge-missing", message: "window.KudosEditor.call is not available" }
        };
      }
      const value = await window.KudosEditor.call(name, args);
      return { ok: true, value: value == null ? {} : value };
    } catch (error) {
      const code = (error && typeof error.code === "string") ? error.code : "js-error";
      const message = (error && typeof error.message === "string")
        ? error.message
        : String(error ?? "Unknown error");
      return { ok: false, error: { code, message } };
    }
    """

    static func encode(_ call: RichEditorBridgeCall) throws -> RichEditorBridgeInvocation {
        let encoder = JSONEncoder()
        let data: Data
        switch call {
        case let .configure(args): data = try encoder.encode(args)
        case let .load(args): data = try encoder.encode(args)
        case let .activate(args): data = try encoder.encode(args)
        case .freeze: data = try encoder.encode(RichEditorEmptyArgs())
        case let .snapshot(args): data = try encoder.encode(args)
        case let .command(args): data = try encoder.encode(args)
        case let .lint(args): data = try encoder.encode(args)
        case let .setTheme(theme): data = try encoder.encode(theme)
        case let .setAppearance(appearance): data = try encoder.encode(appearance)
        case let .setMirror(args): data = try encoder.encode(args)
        case .dispose: data = try encoder.encode(RichEditorEmptyArgs())
        case let .verifySwitch(args): data = try encoder.encode(args)
        }
        return RichEditorBridgeInvocation(
            script: callScript,
            callName: call.name,
            argumentsJSON: data,
            timeout: call.timeout
        )
    }

    private struct ReplyEnvelope<Value: Decodable>: Decodable {
        struct ErrorBody: Decodable {
            var code: String
            var message: String
        }

        var ok: Bool
        var value: Value?
        var error: ErrorBody?
    }

    static func decodeResult<Value: Decodable>(
        _ type: Value.Type,
        from rawValue: Any?,
        callName: String
    ) throws -> Value {
        guard let rawValue, JSONSerialization.isValidJSONObject(rawValue) else {
            throw RichEditorBridgeError.invalidResponse(call: callName)
        }
        let data = try JSONSerialization.data(withJSONObject: rawValue)
        let envelope = try JSONDecoder().decode(ReplyEnvelope<Value>.self, from: data)
        if envelope.ok {
            guard let value = envelope.value else {
                throw RichEditorBridgeError.invalidResponse(call: callName)
            }
            return value
        }
        let code = envelope.error?.code ?? "js-error"
        let message = envelope.error?.message ?? "Unknown error"
        throw RichEditorBridgeError.javaScript(call: callName, code: code, message: message)
    }
}

// MARK: - Transport protocol (implemented by RichEditorHost and test fakes)

@MainActor
protocol RichEditorBridgeTransport: AnyObject {
    var onEvent: (@MainActor (RichEditorEvent) -> Void)? { get set }
    var onProcessTerminated: (@MainActor () -> Void)? { get set }

    func configure(_ args: RichEditorConfigureArgs) async throws -> RichEditorConfigureResult
    func load(_ args: RichEditorLoadArgs) async throws -> RichEditorLoadResult
    func activate(_ args: RichEditorActivateArgs) async throws -> RichEditorActivateResult
    func freeze() async throws -> RichEditorFreezeResult
    func snapshot(_ args: RichEditorSnapshotArgs) async throws -> RichEditorSnapshotResult
    func command(_ args: RichEditorCommandArgs) async throws -> RichEditorCommandResult
    func lint(_ args: RichEditorLintArgs) async throws -> RichEditorLintResult
    func setTheme(_ theme: RichEditorTheme) async throws
    func setAppearance(_ appearance: RichEditorAppearance) async throws
    func setMirror(_ args: RichEditorMirrorArgs) async throws
    func dispose() async throws
    func verifySwitch(_ args: RichEditorSwitchCheckArgs) async throws -> RichEditorSwitchCheckResult
    func focusWebView()
    func resetAfterTermination()
}

extension RichEditorBridgeTransport {
    /// Default for transports without a mirror (test fakes): nothing to show.
    func setMirror(_ args: RichEditorMirrorArgs) async throws {}
}
