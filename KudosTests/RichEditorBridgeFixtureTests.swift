import Foundation
import Testing
@testable import Kudos

/// The bridge contract, checked against the fixtures the page itself produced
/// (`editor-core/test/bridge-fixtures/bridge.json`, written by `editor-core/test-web/bridge-fixtures.ts` from a scripted
/// session through the real page code; editor-core's own test fails if the page stops producing exactly that file).
/// So the native side decodes what the page sends, and sends what the page accepts (docs §7.2).
@MainActor
struct RichEditorBridgeFixtureTests {
    private enum FixtureError: Error { case malformed(String) }

    private static func fixtures() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("editor-core/test/bridge-fixtures/bridge.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        guard let dictionary = object as? [String: Any] else { throw FixtureError.malformed("root") }
        return dictionary
    }

    private static func list(_ key: String) throws -> [[String: Any]] {
        guard let items = try fixtures()[key] as? [[String: Any]] else { throw FixtureError.malformed(key) }
        return items
    }

    private static func jsonObject<T: Encodable>(_ value: T) throws -> NSDictionary {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
        guard let dictionary = object as? NSDictionary else { throw FixtureError.malformed("encoded") }
        return dictionary
    }

    /// Decodes fixture JSON into a native type and encodes it again: the keys must survive both ways.
    private static func roundTrip<T: Codable>(_ type: T.Type, _ object: Any) throws -> NSDictionary {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try jsonObject(JSONDecoder().decode(type, from: data))
    }

    @Test func everyEventThePageSentDecodes() throws {
        let events = try Self.list("events")
        #expect(!events.isEmpty)
        var mirror = HTMLMirrorDocument()
        var sawToolbar = false
        for event in events {
            let decoded = try RichEditorEvent.decode(from: event)
            switch decoded {
            case let .toolbarState(state):
                sawToolbar = true
                let format = state.toFormatState()
                let marks = (event["marks"] as? [String]) ?? []
                #expect(format.activeMarks.map(\.rawValue).sorted() == marks.sorted())
                #expect(format.block.rawValue == event["block"] as? String)
                #expect(format.alignment.rawValue == event["align"] as? String)
                #expect(format.direction.rawValue == event["dir"] as? String)
            case let .mirrorBlocks(update):
                let applied = mirror.apply(update)
                #expect(applied)
                #expect(!mirror.needsReset)
            case let .caretRect(rect):
                #expect(rect.block != nil)
            case let .paste(paste):
                #expect(paste.kind == "html")
                #expect(paste.loss.hasDropped)
            case .edited, .ready, .journal, .error:
                break
            }
        }
        #expect(sawToolbar)
        // The page's mirror splices, applied natively, rebuild exactly the text the snapshot returned.
        let calls = try Self.list("calls")
        let snapshot = try #require(calls.last { $0["name"] as? String == "snapshot" }?["result"] as? [String: Any])
        #expect(mirror.fullHTML == snapshot["html"] as? String)
    }

    @Test func everyCallResultThePageReturnedDecodes() throws {
        for call in try Self.list("calls") {
            let name = try #require(call["name"] as? String)
            if let error = call["error"] as? [String: Any] {
                let envelope: [String: Any] = ["ok": false, "error": error]
                let expected = RichEditorBridgeError.javaScript(
                    call: name,
                    code: error["code"] as? String ?? "",
                    message: error["message"] as? String ?? ""
                )
                #expect(throws: expected) {
                    _ = try RichEditorBridgeEncoder.decodeResult(RichEditorEmptyResult.self, from: envelope, callName: name)
                }
                continue
            }
            let envelope: [String: Any] = ["ok": true, "value": call["result"] ?? [:]]
            func decode<T: Decodable>(_ type: T.Type) throws {
                _ = try RichEditorBridgeEncoder.decodeResult(type, from: envelope, callName: name)
            }
            switch name {
            case "configure": try decode(RichEditorConfigureResult.self)
            case "load": try decode(RichEditorLoadResult.self)
            case "activate": try decode(RichEditorActivateResult.self)
            case "freeze": try decode(RichEditorFreezeResult.self)
            case "snapshot": try decode(RichEditorSnapshotResult.self)
            case "command": try decode(RichEditorCommandResult.self)
            case "lint": try decode(RichEditorLintResult.self)
            case "verifySwitch": try decode(RichEditorSwitchCheckResult.self)
            default: try decode(RichEditorEmptyResult.self)
            }
        }
    }

    @Test func everyCallTheNativeSideMakesEncodesAsThePageExpects() throws {
        var checked: Set<String> = []
        for call in try Self.list("calls") where call["error"] == nil {
            let name = try #require(call["name"] as? String)
            let args = call["args"] ?? [:]
            let expected = try #require(args as? NSDictionary)
            var encoded: NSDictionary?
            switch name {
            case "configure": encoded = try Self.roundTrip(RichEditorConfigureArgs.self, args)
            case "setAppearance": encoded = try Self.roundTrip(RichEditorAppearance.self, args)
            case "setTheme": encoded = try Self.roundTrip(RichEditorTheme.self, args)
            case "load": encoded = try Self.roundTrip(RichEditorLoadArgs.self, args)
            case "activate": encoded = try Self.roundTrip(RichEditorActivateArgs.self, args)
            case "snapshot": encoded = try Self.roundTrip(RichEditorSnapshotArgs.self, args)
            case "lint": encoded = try Self.roundTrip(RichEditorLintArgs.self, args)
            case "verifySwitch": encoded = try Self.roundTrip(RichEditorSwitchCheckArgs.self, args)
            case "setMirror": encoded = try Self.roundTrip(RichEditorMirrorArgs.self, args)
            case "freeze", "dispose": encoded = try Self.jsonObject(RichEditorEmptyArgs())
            default: encoded = nil
            }
            guard let encoded else { continue }
            #expect(encoded == expected, "\(name)")
            checked.insert(name)
        }
        #expect(checked.isSuperset(of: ["configure", "setAppearance", "load", "activate", "snapshot", "verifySwitch", "setMirror"]))
        // Every call name the native side can make is one the page answered in the session.
        let answered = Set(try Self.list("calls").compactMap { $0["name"] as? String })
        for call in [
            RichEditorBridgeCall.freeze, .dispose,
            .setMirror(RichEditorMirrorArgs(enabled: true)),
            .snapshot(RichEditorSnapshotArgs(caret: true)),
        ] {
            #expect(answered.contains(call.name), "\(call.name)")
        }
    }

    @Test func everyFormatCommandMapsToThePageCommandInTheFixtures() throws {
        var expected: [String: NSDictionary] = [:]
        for entry in try Self.list("commands") {
            let id = try #require(entry["id"] as? String)
            expected[id] = ["name": entry["name"] ?? "", "attrs": entry["attrs"] ?? [:]] as NSDictionary
        }
        var native: [(String, RichEditorCommandArgs?)] = []
        native += FormatMark.allCases.map { ("toggleMark.\($0.rawValue)", FormatCommand.toggleMark($0).bridgeCommand) }
        native += FormatBlock.allCases.map { ("setBlock.\($0.rawValue)", FormatCommand.setBlock($0).bridgeCommand) }
        native += FormatAlignment.allCases.map { ("setAlignment.\($0.rawValue)", FormatCommand.setAlignment($0).bridgeCommand) }
        native += FormatDirection.allCases.map { ("setDirection.\($0.rawValue)", FormatCommand.setDirection($0).bridgeCommand) }
        native += SceneBreakStyle.allCases.map { ("insertSceneBreak.\($0.rawValue)", FormatCommand.insertSceneBreak($0).bridgeCommand) }
        native += [
            ("setLink", FormatCommand.setLink(url: "https://example.com/").bridgeCommand),
            ("unlink", FormatCommand.unlink.bridgeCommand),
            ("insertImage", FormatCommand.insertImage(FormatImageSpec(
                address: "https://example.com/a.png", description: "A cat", width: 200, height: 100
            )).bridgeCommand),
            ("insertImage.noSize", FormatCommand.insertImage(FormatImageSpec(address: "https://example.com/a.png")).bridgeCommand),
            ("insertFootnote", FormatCommand.insertFootnote.bridgeCommand),
            ("undo", FormatCommand.undo.bridgeCommand),
            ("redo", FormatCommand.redo.bridgeCommand),
            ("clearFormatting", FormatCommand.clearFormatting.bridgeCommand),
            ("host.moveCaret.left", RichEditorHostCommand.moveCaret(.left).bridgeCommand),
            ("host.moveCaret.right", RichEditorHostCommand.moveCaret(.right).bridgeCommand),
            ("host.insertEmDash", RichEditorHostCommand.insertEmDash.bridgeCommand),
            ("host.insertQuotationMarks", RichEditorHostCommand.insertQuotationMarks.bridgeCommand),
            ("tag.lineBreak", AO3MarkupTag.lineBreak.richCommand),
        ]
        #expect(Set(native.map { $0.0 }) == Set(expected.keys), "every fixture command has a native source, and back")
        for (id, args) in native {
            let args = try #require(args, "\(id) maps to a page command")
            #expect(try Self.jsonObject(args) == expected[id], "\(id)")
        }
        // Native-only commands send nothing to the page.
        #expect(FormatCommand.openTableInHTML.bridgeCommand == nil)
        #expect(RichEditorHostCommand.openFormatPanel.bridgeCommand == nil)
        #expect(RichEditorHostCommand.requestLink.bridgeCommand == nil)
        #expect(AO3MarkupTag.link.richCommand == nil)
    }

    @Test func toolbarStateDecodesWithoutTheOptionalFields() throws {
        let decoded = try RichEditorEvent.decode(from: [
            "type": "toolbarState", "marks": ["italic"], "block": "quote", "align": "centre",
            "dir": "rightToLeft", "canUndo": true, "canRedo": false,
        ])
        guard case let .toolbarState(state) = decoded else { throw FixtureError.malformed("toolbarState") }
        let format = state.toFormatState()
        #expect(format.activeMarks == [.italic])
        #expect(format.block == .quote)
        #expect(format.alignment == .centre)
        #expect(format.direction == .rightToLeft)
        #expect(!format.isInLink)
        #expect(state.undoMenuTitle == "Undo")
    }
}
