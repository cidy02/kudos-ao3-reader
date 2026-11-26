import Foundation
import SwiftUI
import Testing
import WebKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif
@testable import Kudos

struct RichEditorBridgeEncodingTests {
    private let hostileText = "</script><script>alert('xss')</script>\"'\\`\n${1+1}<!-- c -->👩🏽‍💻"

    @Test func bridgeCallsNeverSpliceTextIntoScriptSourceAndUseJSONArgumentsOnly() throws {
        let theme = RichEditorTheme(
            background: "#FFFFFF",
            text: "#1E1E1E",
            accent: "#821019",
            link: "#0B66C2",
            fontFamily: RichEditorTheme.defaultFontFamily,
            fontSizePx: 15.5,
            lineHeight: 1.62
        )
        let calls: [RichEditorBridgeCall] = [
            .configure(RichEditorConfigureArgs(variant: .content, theme: theme, locale: "en_US")),
            .load(RichEditorLoadArgs(html: hostileText, revision: 7)),
            .activate(RichEditorActivateArgs(caret: nil, focus: true)),
            .freeze,
            .snapshot(RichEditorSnapshotArgs(caret: true)),
            .command(RichEditorCommandArgs(name: "link", attrs: ["href": .string(hostileText)])),
            .lint(RichEditorLintArgs(html: hostileText)),
            .setTheme(theme),
            .dispose,
            .verifySwitch(RichEditorSwitchCheckArgs(direction: .sourceToRich, html: hostileText)),
        ]

        for call in calls {
            let invocation = try RichEditorBridgeEncoder.encode(call)
            #expect(invocation.script == RichEditorBridgeEncoder.callScript)
            #expect(!invocation.script.contains(hostileText))
            #expect(!invocation.script.contains("</script>"))
            #expect(!invocation.script.contains("alert"))
            #expect(invocation.callName == call.name)

            let jsArgs = try invocation.javaScriptArguments()
            #expect(jsArgs["name"] as? String == call.name)
            #expect(jsArgs["args"] is [String: Any])
        }

        // Verify exact payload fidelity for text-carrying calls.
        let loadInvocation = try RichEditorBridgeEncoder.encode(
            .load(RichEditorLoadArgs(html: hostileText, revision: 7))
        )
        let loadArgs = try #require(try loadInvocation.javaScriptArguments()["args"] as? [String: Any])
        #expect(loadArgs["html"] as? String == hostileText)
        #expect(loadArgs["revision"] as? Int == 7)

        // `activate` with `caret: nil` must explicitly serialize JSON `null` (§7.2).
        let activateInvocation = try RichEditorBridgeEncoder.encode(
            .activate(RichEditorActivateArgs(caret: nil, focus: true))
        )
        let activateArgs = try #require(try activateInvocation.javaScriptArguments()["args"] as? [String: Any])
        #expect(activateArgs["caret"] is NSNull)
        #expect(activateArgs["focus"] as? Bool == true)
    }

    @Test func callTimeoutsMatchArchitectureSpec() {
        let theme = RichEditorTheme(
            background: "#FFFFFF", text: "#1E1E1E", accent: "#821019", link: "#0B66C2",
            fontFamily: "ui-serif", fontSizePx: 15.5, lineHeight: 1.62
        )
        let configureCall = RichEditorBridgeCall.configure(
            RichEditorConfigureArgs(variant: .content, theme: theme)
        )
        let loadCall = RichEditorBridgeCall.load(RichEditorLoadArgs(html: "", revision: 0))
        let lintCall = RichEditorBridgeCall.lint(RichEditorLintArgs(html: ""))
        let snapshotCall = RichEditorBridgeCall.snapshot(RichEditorSnapshotArgs(caret: false))
        let verifyCall = RichEditorBridgeCall.verifySwitch(
            RichEditorSwitchCheckArgs(direction: .richToSource, html: "")
        )
        let activateCall = RichEditorBridgeCall.activate(RichEditorActivateArgs(caret: nil, focus: true))
        let commandCall = RichEditorBridgeCall.command(RichEditorCommandArgs(name: "undo"))

        #expect(configureCall.timeout == .seconds(5))
        #expect(loadCall.timeout == .seconds(5))
        #expect(lintCall.timeout == .seconds(5))
        #expect(snapshotCall.timeout == .seconds(2))
        #expect(verifyCall.timeout == .seconds(2))
        #expect(activateCall.timeout == .seconds(1))
        #expect(RichEditorBridgeCall.freeze.timeout == .seconds(1))
        #expect(commandCall.timeout == .seconds(1))
        #expect(RichEditorBridgeCall.setTheme(theme).timeout == .seconds(1))
        #expect(RichEditorBridgeCall.dispose.timeout == .seconds(1))
    }

    @Test func replyDecoderUnwrapsValuesAndStructuredJavaScriptErrors() throws {
        let okPayload: [String: Any] = [
            "ok": true,
            "value": ["caretFound": true],
        ]
        let decoded = try RichEditorBridgeEncoder.decodeResult(
            RichEditorActivateResult.self,
            from: okPayload,
            callName: "activate"
        )
        #expect(decoded == RichEditorActivateResult(caretFound: true))

        let errorPayload: [String: Any] = [
            "ok": false,
            "error": ["code": "parse-failed", "message": "Unexpected token"],
        ]
        #expect(throws: RichEditorBridgeError.javaScript(
            call: "load",
            code: "parse-failed",
            message: "Unexpected token"
        )) {
            _ = try RichEditorBridgeEncoder.decodeResult(
                RichEditorLoadResult.self,
                from: errorPayload,
                callName: "load"
            )
        }
    }

    @Test func eventDecoderHandlesEverySpecEventAndRejectsMalformedPayloads() throws {
        #expect(
            try RichEditorEvent.decode(from: [
                "type": "ready", "bundleVersion": "1.2.0", "schemaVersion": 1,
            ]) == .ready(bundleVersion: "1.2.0", schemaVersion: 1)
        )
        #expect(
            try RichEditorEvent.decode(from: ["type": "edited", "revision": 42])
                == .edited(revision: 42)
        )
        #expect(
            try RichEditorEvent.decode(from: [
                "type": "toolbarState",
                "marks": ["strong", "em"],
                "block": "blockquote",
                "align": "center",
                "dir": NSNull(),
                "canUndo": true,
                "canRedo": false,
            ]) == .toolbarState(RichEditorToolbarState(
                marks: ["strong", "em"],
                block: "blockquote",
                align: "center",
                dir: nil,
                canUndo: true,
                canRedo: false
            ))
        )
        #expect(
            try RichEditorEvent.decode(from: [
                "type": "journal",
                "schemaVersion": 1,
                "fromRevision": 1,
                "toRevision": 2,
                "steps": [["stepType": "replace"]],
            ]) == .journal(RichEditorJournalPayload(
                schemaVersion: 1,
                fromRevision: 1,
                toRevision: 2,
                steps: [.object(["stepType": .string("replace")])]
            ))
        )
        #expect(
            try RichEditorEvent.decode(from: [
                "type": "error", "code": "composition-timeout", "message": "Timed out",
            ]) == .error(code: "composition-timeout", message: "Timed out")
        )
        #expect(throws: (any Error).self) {
            _ = try RichEditorEvent.decode(from: ["type": "unknown"])
        }
        #expect(throws: (any Error).self) {
            _ = try RichEditorEvent.decode(from: "not json")
        }
    }

    @Test func lossReportConfirmationAndNonBlockingSummaries() {
        #expect(!RichEditorLossReport.empty.hasDropped)
        #expect(!RichEditorLossReport.empty.hasNonBlockingChanges)

        let nonBlocking = RichEditorLossReport(unwrapped: ["span": 2], normalized: 3, preserved: 1)
        #expect(!nonBlocking.hasDropped)
        #expect(nonBlocking.hasNonBlockingChanges)
        #expect(nonBlocking.nonBlockingChangesSummary.contains("<span> ×2"))
        #expect(nonBlocking.nonBlockingChangesSummary.contains("Normalized: 3"))
        #expect(nonBlocking.nonBlockingChangesSummary.contains("Preserved verbatim"))

        let blocking = RichEditorLossReport(
            dropped: RichEditorLossReport.Dropped(elements: ["font": 3], attributes: ["style": 42])
        )
        #expect(blocking.hasDropped)
        #expect(
            blocking.droppedConfirmationMessage
                == "AO3 would remove these when you save: <font> ×3, style ×42"
        )
    }
}

@MainActor
struct RichEditorHostAndNavigationTests {
    @Test func navigationPolicyAllowsOnlyKudosEditorBundleURLs() throws {
        let allowed = [
            "kudos-editor://editor/index.html",
            "kudos-editor://editor/editor-stub.js",
            "kudos-editor://editor/assets/style.css",
            "kudos-editor://editor/",
        ]
        for raw in allowed {
            let url = try #require(URL(string: raw))
            #expect(RichEditorNavigationPolicy.allows(url: url, navigationType: .other))
            #expect(
                RichEditorNavigationPolicy.decidePolicy(
                    url: url, navigationType: .other, isMainFrame: true
                ) == .allow
            )
            // Tapped links, subframes, and missing target frames always cancel (§11).
            #expect(!RichEditorNavigationPolicy.allows(url: url, navigationType: .linkActivated))
            #expect(
                RichEditorNavigationPolicy.decidePolicy(
                    url: url, navigationType: .linkActivated, isMainFrame: true
                ) == .cancel
            )
            #expect(
                RichEditorNavigationPolicy.decidePolicy(
                    url: url, navigationType: .other, isMainFrame: false
                ) == .cancel
            )
            #expect(
                RichEditorNavigationPolicy.decidePolicy(
                    url: url, navigationType: .other, isMainFrame: nil
                ) == .cancel
            )
        }

        let blocked = [
            "https://archiveofourown.org/works/1",
            "http://127.0.0.1:8080/index.html",
            "file:///etc/passwd",
            "about:blank",
            "javascript:alert(1)",
            "data:text/html,<script>alert(1)</script>",
            "blob:https://example.com/abc",
            "mailto:writer@example.com",
            "kudos-editor://other-host/index.html",
            "kudos-editor:///index.html",
            "kudos-editor://editor:8080/index.html",
            "kudos-editor://user@editor/index.html",
            "kudos-editor://editor/../secret.html",
            "kudos-editor://editor/assets/../secret.html",
            "kudos-editor://editor/./index.html",
            "kudos-editor://editor/%2e%2e/secret.html",
            "kudos-editor://editor/.hidden.js",
        ]
        for raw in blocked {
            let url = try #require(URL(string: raw))
            #expect(!RichEditorNavigationPolicy.allows(url: url, navigationType: .other))
            #expect(
                RichEditorNavigationPolicy.decidePolicy(
                    url: url, navigationType: .other, isMainFrame: true
                ) == .cancel
            )
        }
    }

    @Test func hostNavigationDelegateCancelsNonBundleAndNewWindowNavigations() throws {
        let host = RichEditorHost(backgroundColor: .white)
        defer { host.teardown() }

        func decide(
            url raw: String,
            type: WKNavigationType = .other
        ) throws -> WKNavigationActionPolicy {
            let url = try #require(URL(string: raw))
            let action = EditorTestNavigationAction(url: url, navigationType: type)
            var result: WKNavigationActionPolicy?
            host.webView(host.webView, decidePolicyFor: action) { result = $0 }
            return try #require(result)
        }

        // `targetFrame == nil` (e.g. target="_blank") and every off-origin URL cancel.
        #expect(try decide(url: "kudos-editor://editor/index.html") == .cancel)
        #expect(try decide(url: "kudos-editor://editor/index.html", type: .linkActivated) == .cancel)
        #expect(try decide(url: "https://archiveofourown.org/") == .cancel)
        #expect(try decide(url: "javascript:alert(1)") == .cancel)
        #expect(try decide(url: "about:blank") == .cancel)
    }

    @Test func schemeHandlerServesAllowedBundleAssetsAndBlocksTraversalAndDisallowedTypes() throws {
        let root = URL.temporaryDirectory
            .appendingPathComponent("editor-bundle-\(UUID().uuidString)", isDirectory: true)
        let outside = URL.temporaryDirectory
            .appendingPathComponent("outside-\(UUID().uuidString).html")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        try Data("<!doctype html>".utf8).write(to: root.appendingPathComponent("index.html"))
        try Data("console.log(1);".utf8).write(to: root.appendingPathComponent("editor-stub.js"))
        try Data("<plist/>".utf8).write(to: root.appendingPathComponent("Info.plist"))
        try Data("secret".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escape.html"),
            withDestinationURL: outside
        )

        let handler = RichEditorURLSchemeHandler(overrideRootDirectory: root)
        let html = try handler.resolve(url: URL(string: "kudos-editor://editor/index.html")).get()
        #expect(html.mimeType == "text/html; charset=utf-8")
        #expect(String(decoding: html.data, as: UTF8.self) == "<!doctype html>")

        let script = try handler.resolve(url: URL(string: "kudos-editor://editor/editor-stub.js")).get()
        #expect(script.mimeType == "application/javascript; charset=utf-8")

        #expect(throws: RichEditorURLSchemeHandler.ResourceError.unsupportedFileType) {
            _ = try handler.resolve(url: URL(string: "kudos-editor://editor/Info.plist")).get()
        }
        #expect(throws: RichEditorURLSchemeHandler.ResourceError.forbiddenURL) {
            _ = try handler.resolve(url: URL(string: "kudos-editor://editor/../secret.html")).get()
        }
        #expect(throws: RichEditorURLSchemeHandler.ResourceError.notFound("escape.html")) {
            _ = try handler.resolve(url: URL(string: "kudos-editor://editor/escape.html")).get()
        }
    }

    @Test func bundledStubPageResolvesAndEnforcesSecurityPolicy() throws {
        let handler = RichEditorURLSchemeHandler(bundle: .main)
        let html = try handler.resolve(url: RichEditorBundleLocation.entryURL).get()
        let htmlString = String(decoding: html.data, as: UTF8.self)
        #expect(htmlString.contains(RichEditorBundleLocation.contentSecurityPolicy))
        #expect(htmlString.contains("editor-stub.js"))

        let script = try handler.resolve(url: URL(string: "kudos-editor://editor/editor-stub.js")).get()
        let scriptString = String(decoding: script.data, as: UTF8.self)
        #expect(scriptString.contains("window.KudosEditor"))
        #expect(!scriptString.contains("innerHTML"))
    }

    @Test func webViewHostConfiguresNonPersistentStoreNoLinkPreviewAndPrePaintBackground() {
        let background = ReaderTheme.sepia.backgroundColor
        let host = RichEditorHost(backgroundColor: background)
        defer { host.teardown() }

        let store = host.webView.configuration.websiteDataStore
        #expect(!store.isPersistent)
        #expect(store !== WKWebsiteDataStore.default())
        #expect(store !== ReaderWebIsolation.isolatedDataStore)
        #expect(!host.webView.allowsLinkPreview)
        #expect(host.webView.navigationDelegate === host)
        #expect(host.webView.uiDelegate === host)
        #expect(host.webView.nativeBackgroundColor == background)
        #if os(iOS)
        #expect(!host.webView.isOpaque)
        #expect(host.webView.backgroundColor == UIColor(background))
        #expect(host.webView.scrollView.backgroundColor == UIColor(background))
        #else
        #expect(host.webView.underPageBackgroundColor == NSColor(background))
        #endif
    }

    @Test func featureFlagIsOffByDefaultAndOnlyEnablesChapterContentField() throws {
        let suiteName = "RichEditorFeatureFlagTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(!RichEditorFeatureFlag.isEnabled(in: defaults))
        #expect(!RichEditorFeatureFlag.showsRichTextSwitch(field: "content", enabled: false))

        RichEditorFeatureFlag.setEnabled(true, in: defaults)
        #expect(RichEditorFeatureFlag.isEnabled(in: defaults))
        #expect(RichEditorFeatureFlag.showsRichTextSwitch(field: "content", enabled: true))
        #expect(!RichEditorFeatureFlag.showsRichTextSwitch(field: "summary", enabled: true))
        #expect(!RichEditorFeatureFlag.showsRichTextSwitch(field: "notes", enabled: true))
        #expect(!RichEditorFeatureFlag.showsRichTextSwitch(field: "endnotes", enabled: true))
    }
}

private final class EditorTestNavigationAction: WKNavigationAction {
    private let urlRequest: URLRequest
    private let type: WKNavigationType

    override var request: URLRequest { urlRequest }
    override var navigationType: WKNavigationType { type }

    init(url: URL, navigationType: WKNavigationType) {
        self.urlRequest = URLRequest(url: url)
        self.type = navigationType
        super.init()
    }
}
