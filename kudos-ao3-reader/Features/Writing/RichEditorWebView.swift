import Foundation
import SwiftUI
import WebKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
import QuartzCore
#endif

/// Feature flag gating the Rich Text / HTML switch on the chapter editor (off by default).
/// Device-local experimental switch — not carried in backups or folder sync.
nonisolated enum RichEditorFeatureFlag {
    static let storageKey = "experimentalRichTextEditorEnabled"

    static var isEnabled: Bool {
        isEnabled(in: .standard)
    }

    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: storageKey)
    }

    static func setEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: storageKey)
    }

    /// Rich Text / HTML toggle appears only when the feature flag is on and the
    /// field is the chapter text field (`content`).
    static func showsRichTextSwitch(field: String, enabled: Bool) -> Bool {
        enabled && field == "content"
    }
}

/// Single source of truth for the bundled Rich Text page location.
/// Replacing `EditorStub` with the built `editor-core` bundle changes only `bundleDirectory`.
nonisolated enum RichEditorBundleLocation {
    static let scheme = "kudos-editor"
    static let host = "editor"
    /// Replace with the real `editor-core` resource folder when it lands.
    static let bundleDirectory = "EditorStub"
    static let entryFile = "index.html"

    /// Normative §11 Content Security Policy (remote images off by default, no inline scripts).
    static let contentSecurityPolicy =
        "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:"

    static let entryURL: URL = {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/\(entryFile)"
        return components.url ?? URL(filePath: "/")
    }()
}

/// Pure navigation gate for the Rich Text WebView (§10.1, §11).
/// Only the app's own `kudos-editor://editor/...` bundle origin may load; links
/// and every other scheme (`http`, `https`, `file`, `javascript`, `data`, `about`, …) cancel.
nonisolated enum RichEditorNavigationPolicy {
    static func allows(url: URL?, navigationType: WKNavigationType = .other) -> Bool {
        guard let url, navigationType != .linkActivated else { return false }
        return safeRelativePath(for: url) != nil
    }

    /// Validates a `kudos-editor://` URL and returns its normalized relative path
    /// inside the editor bundle, or nil if it is off-origin or attempts traversal.
    static func safeRelativePath(for url: URL) -> String? {
        guard url.scheme?.lowercased() == RichEditorBundleLocation.scheme,
              url.host?.lowercased() == RichEditorBundleLocation.host,
              url.port == nil,
              url.user == nil,
              url.password == nil
        else { return nil }

        let raw = url.absoluteString.lowercased()
        let forbiddenEncoded = ["%2e", "%2f", "%5c", "%00"]
        if forbiddenEncoded.contains(where: { raw.contains($0) }) { return nil }

        // Check raw dot segments before Foundation's URL path normalization can fold `..`.
        let expectedPrefix = "\(RichEditorBundleLocation.scheme)://\(RichEditorBundleLocation.host)"
        guard raw.hasPrefix(expectedPrefix) else { return nil }
        let afterHost = raw.dropFirst(expectedPrefix.count)
        let rawPath = afterHost.prefix { $0 != "?" && $0 != "#" }
        if !rawPath.isEmpty, !rawPath.hasPrefix("/") { return nil }
        let rawSegments = rawPath.split(separator: "/").map(String.init)
        if rawSegments.contains(where: { $0 == "." || $0 == ".." || $0.hasPrefix(".") }) {
            return nil
        }

        let decodedPath = url.path
        if decodedPath.contains("\\") || decodedPath.contains("\0") { return nil }

        let segments = decodedPath.split(separator: "/").map(String.init)
        if segments.isEmpty { return RichEditorBundleLocation.entryFile }
        for segment in segments {
            if segment.isEmpty || segment == "." || segment == ".." || segment.hasPrefix(".") {
                return nil
            }
        }
        return segments.joined(separator: "/")
    }

    /// Pure policy decision testable without instantiating `WKFrameInfo`.
    static func decidePolicy(
        url: URL?,
        navigationType: WKNavigationType,
        isMainFrame: Bool?
    ) -> WKNavigationActionPolicy {
        guard isMainFrame == true else { return .cancel }
        return allows(url: url, navigationType: navigationType) ? .allow : .cancel
    }

    static func decidePolicy(for navigationAction: WKNavigationAction) -> WKNavigationActionPolicy {
        decidePolicy(
            url: navigationAction.request.url,
            navigationType: navigationAction.navigationType,
            isMainFrame: navigationAction.targetFrame?.isMainFrame
        )
    }
}

/// Serves bundled editor files for `kudos-editor://` without touching the network (§10.1).
final class RichEditorURLSchemeHandler: NSObject, WKURLSchemeHandler {
    nonisolated enum ResourceError: LocalizedError, Equatable, Sendable {
        case forbiddenURL
        case unsupportedFileType
        case notFound(String)

        var errorDescription: String? {
            switch self {
            case .forbiddenURL: "Blocked off-bundle editor request."
            case .unsupportedFileType: "Unsupported editor bundle resource."
            case let .notFound(path): "Editor bundle resource missing: \(path)."
            }
        }
    }

    nonisolated static let allowedMIMETypes: [String: String] = [
        "html": "text/html; charset=utf-8",
        "js": "application/javascript; charset=utf-8",
        "mjs": "application/javascript; charset=utf-8",
        "css": "text/css; charset=utf-8",
        "svg": "image/svg+xml",
        "woff2": "font/woff2",
        "png": "image/png",
    ]

    private let bundle: Bundle
    private let bundleDirectory: String
    private let overrideRootDirectory: URL?

    init(
        bundle: Bundle = .main,
        bundleDirectory: String = RichEditorBundleLocation.bundleDirectory,
        overrideRootDirectory: URL? = nil
    ) {
        self.bundle = bundle
        self.bundleDirectory = bundleDirectory
        self.overrideRootDirectory = overrideRootDirectory
        super.init()
    }

    /// Resolves a `kudos-editor://` URL to its bundled bytes and MIME type.
    /// Exposed for direct unit testing without needing a live `WKURLSchemeTask`.
    func resolve(url: URL?) -> Result<(data: Data, mimeType: String), Error> {
        guard let url, let relativePath = RichEditorNavigationPolicy.safeRelativePath(for: url) else {
            return .failure(ResourceError.forbiddenURL)
        }
        let pathURL = URL(fileURLWithPath: relativePath)
        let ext = pathURL.pathExtension.lowercased()
        guard let mimeType = Self.allowedMIMETypes[ext] else {
            return .failure(ResourceError.unsupportedFileType)
        }
        guard let fileURL = locateFile(relativePath: relativePath, extension: ext) else {
            return .failure(ResourceError.notFound(relativePath))
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return .success((data: data, mimeType: mimeType))
        } catch {
            return .failure(error)
        }
    }

    func webView(_: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let requestURL = urlSchemeTask.request.url
        switch resolve(url: requestURL) {
        case let .success((data, mimeType)):
            guard let responseURL = requestURL,
                  let response = HTTPURLResponse(
                      url: responseURL,
                      statusCode: 200,
                      httpVersion: "HTTP/1.1",
                      headerFields: [
                          "Content-Type": mimeType,
                          "Content-Length": "\(data.count)",
                          "Cache-Control": "no-store",
                          "Content-Security-Policy": RichEditorBundleLocation.contentSecurityPolicy,
                      ]
                  )
            else {
                urlSchemeTask.didFailWithError(ResourceError.forbiddenURL)
                return
            }
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        case let .failure(error):
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_: WKWebView, stop _: any WKURLSchemeTask) {}

    private func locateFile(relativePath: String, extension ext: String) -> URL? {
        if let root = overrideRootDirectory {
            let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath().path
            let prefix = resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/"
            let candidate = root
                .appendingPathComponent(relativePath)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard candidate.path.hasPrefix(prefix),
                  FileManager.default.fileExists(atPath: candidate.path)
            else { return nil }
            return candidate
        }

        let components = relativePath.split(separator: "/").map(String.init)
        guard let fileName = components.last else { return nil }
        let stem = (fileName as NSString).deletingPathExtension
        let nestedDirs = components.dropLast().joined(separator: "/")

        let candidates: [String?] = [
            nestedDirs.isEmpty ? bundleDirectory : "\(bundleDirectory)/\(nestedDirs)",
            nestedDirs.isEmpty ? "Resources/\(bundleDirectory)" : "Resources/\(bundleDirectory)/\(nestedDirs)",
            // Xcode's PBXFileSystemSynchronizedRootGroup flattens subfolder resources
            // into the bundle root unless configured as a folder reference.
            nestedDirs.isEmpty ? nil : nestedDirs,
        ]
        for subdirectory in candidates {
            if let found = bundle.url(forResource: stem, withExtension: ext, subdirectory: subdirectory) {
                return found
            }
        }
        return nil
    }
}

/// `WKWebView` subclass hosting the Rich Text editor (§10.1, §10.3 N2–N8, N10).
/// Configures pre-paint background, N2 edit menu, N3 keys accessory, N4 scroll
/// behavior, N5 trait appearance forwarding, N6 system undo, N7 hardware
/// keyboard shortcuts, and N8 system Find.
@MainActor
final class RichEditorWebView: WKWebView {
    private(set) var nativeBackgroundColor: Color
    var onCommand: (@MainActor (RichEditorHostCommand) -> Void)?
    var onAppearanceChange: (@MainActor (RichEditorAppearance) -> Void)?

    var scrollMode: RichEditorScrollMode = .followCaret
    var typewriterAnchorFraction: Double = RichEditorScrollCalculator.defaultTypewriterFraction
    var typographyFontFamily: String = RichEditorTheme.defaultFontFamily
    var typographyBaseFontSize: Double = 15.5
    var typographyLineHeight: Double = RichEditorTheme.defaultLineHeight
    var ownsRichUndo = false

    let richUndoManager = RichEditorUndoManager()
    var inputAccessoryStatus: RichEditorInputAccessoryStatus?

    #if os(iOS)
    var keysAccessoryView: WritingKeysInputAccessoryView?
    var traitChangeRegistration: (any UITraitChangeRegistration)?
    #endif

    init(
        frame: CGRect = .zero,
        configuration: WKWebViewConfiguration,
        backgroundColor: Color
    ) {
        self.nativeBackgroundColor = backgroundColor
        super.init(frame: frame, configuration: configuration)
        allowsLinkPreview = false
        applyNativeBackgroundColor(backgroundColor)
        configureNativeFeel()
    }

    required init?(coder: NSCoder) {
        nativeBackgroundColor = .clear
        super.init(coder: coder)
        allowsLinkPreview = false
        configureNativeFeel()
    }

    /// Sets the native backing color before first paint and on theme changes (N10).
    func applyNativeBackgroundColor(_ color: Color) {
        nativeBackgroundColor = color
        #if os(iOS)
        let uiColor = UIColor(color)
        isOpaque = false
        backgroundColor = uiColor
        scrollView.backgroundColor = uiColor
        underPageBackgroundColor = uiColor
        #else
        let nsColor = NSColor(color)
        underPageBackgroundColor = nsColor
        wantsLayer = true
        layer?.backgroundColor = nsColor.cgColor
        setValue(false, forKey: "drawsBackground")
        #endif
    }

    /// Moves first responder to the web view (§7.7).
    func focusEditor() {
        #if os(iOS)
        _ = becomeFirstResponder()
        #else
        window?.makeFirstResponder(self)
        #endif
    }

    // MARK: Platform responder overrides (delegated to RichEditorWebView+NativeFeel.swift)

    override var undoManager: UndoManager? {
        ownsRichUndo ? richUndoManager : super.undoManager
    }

    #if os(iOS)
    override var editingInteractionConfiguration: UIEditingInteractionConfiguration {
        ownsRichUndo ? .default : super.editingInteractionConfiguration
    }

    override var keyCommands: [UIKeyCommand]? {
        makeEditorKeyCommands()
    }

    override func buildMenu(with builder: any UIMenuBuilder) {
        super.buildMenu(with: builder)
        configureEditMenu(using: UIKitMenuBuilderAdapter(builder: builder))
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if let handled = canPerformEditorAction(action) {
            return handled
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func validate(_ command: UICommand) {
        super.validate(command)
        validateEditorCommand(command)
    }
    #else
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        notifyAppearanceChanged()
    }
    #endif
}

#if os(iOS)
struct RichEditorWebViewContainer: UIViewRepresentable {
    let webView: RichEditorWebView

    func makeUIView(context _: Context) -> RichEditorWebView { webView }
    func updateUIView(_: RichEditorWebView, context _: Context) {}
}
#else
struct RichEditorWebViewContainer: NSViewRepresentable {
    let webView: RichEditorWebView

    func makeNSView(context _: Context) -> RichEditorWebView { webView }
    func updateNSView(_: RichEditorWebView, context _: Context) {}
}
#endif
