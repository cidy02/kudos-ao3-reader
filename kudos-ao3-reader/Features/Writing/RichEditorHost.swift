import Foundation
import OSLog
import SwiftUI
import WebKit

/// Owns the `RichEditorWebView`, non-persistent data store, `kudos-editor://`
/// scheme handler, navigation delegate, script message handler, and JSON-only
/// `callAsyncJavaScript` bridge (§7.2, §10.1).
@MainActor @Observable
final class RichEditorHost: NSObject, RichEditorBridgeTransport {
    private(set) var webView: RichEditorWebView
    /// Incremented whenever the WebView is rebuilt after process termination so
    /// SwiftUI swaps in the new instance cleanly.
    private(set) var webViewGeneration = 0

    @ObservationIgnored
    var onEvent: (@MainActor (RichEditorEvent) -> Void)?
    @ObservationIgnored
    var onProcessTerminated: (@MainActor () -> Void)?

    @ObservationIgnored
    private let bundle: Bundle
    @ObservationIgnored
    private let bundleDirectory: String
    @ObservationIgnored
    private let overrideRootDirectory: URL?
    @ObservationIgnored
    private let clock: any WritingClock
    @ObservationIgnored
    private var backgroundColor: Color
    @ObservationIgnored
    private let schemeHandler: RichEditorURLSchemeHandler
    @ObservationIgnored
    private let scriptProxy = RichEditorScriptMessageProxy()
    @ObservationIgnored
    private var hasStartedLoad = false
    @ObservationIgnored
    private var isPageReady = false
    @ObservationIgnored
    private var readyWaiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    @ObservationIgnored
    private var activeCallFailers: [UUID: (Error) -> Void] = [:]

    init(
        backgroundColor: Color,
        bundle: Bundle = .main,
        bundleDirectory: String = RichEditorBundleLocation.bundleDirectory,
        overrideRootDirectory: URL? = nil,
        clock: any WritingClock = SystemWritingClock()
    ) {
        self.bundle = bundle
        self.bundleDirectory = bundleDirectory
        self.overrideRootDirectory = overrideRootDirectory
        self.clock = clock
        self.backgroundColor = backgroundColor
        self.schemeHandler = RichEditorURLSchemeHandler(
            bundle: bundle,
            bundleDirectory: bundleDirectory,
            overrideRootDirectory: overrideRootDirectory
        )
        self.webView = Self.buildWebView(
            schemeHandler: schemeHandler,
            scriptProxy: scriptProxy,
            backgroundColor: backgroundColor
        )
        super.init()
        scriptProxy.host = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func applyNativeBackgroundColor(_ color: Color) {
        backgroundColor = color
        webView.applyNativeBackgroundColor(color)
    }

    /// Loads the bundled editor page if it has not been requested yet.
    func startLoadingIfNeeded() {
        guard !hasStartedLoad else { return }
        hasStartedLoad = true
        webView.load(URLRequest(url: RichEditorBundleLocation.entryURL))
    }

    // MARK: RichEditorBridgeTransport

    func configure(_ args: RichEditorConfigureArgs) async throws -> RichEditorConfigureResult {
        try await ensurePageReady(timeout: RichEditorBridgeCall.configure(args).timeout)
        return try await performCall(.configure(args), as: RichEditorConfigureResult.self)
    }

    func load(_ args: RichEditorLoadArgs) async throws -> RichEditorLoadResult {
        try await performCall(.load(args), as: RichEditorLoadResult.self)
    }

    func activate(_ args: RichEditorActivateArgs) async throws -> RichEditorActivateResult {
        try await performCall(.activate(args), as: RichEditorActivateResult.self)
    }

    func freeze() async throws -> RichEditorFreezeResult {
        try await performCall(.freeze, as: RichEditorFreezeResult.self)
    }

    func snapshot(_ args: RichEditorSnapshotArgs) async throws -> RichEditorSnapshotResult {
        try await performCall(.snapshot(args), as: RichEditorSnapshotResult.self)
    }

    func command(_ args: RichEditorCommandArgs) async throws -> RichEditorCommandResult {
        try await performCall(.command(args), as: RichEditorCommandResult.self)
    }

    func lint(_ args: RichEditorLintArgs) async throws -> RichEditorLintResult {
        try await performCall(.lint(args), as: RichEditorLintResult.self)
    }

    func setTheme(_ theme: RichEditorTheme) async throws {
        _ = try await performCall(.setTheme(theme), as: RichEditorEmptyResult.self)
    }

    func dispose() async throws {
        _ = try await performCall(.dispose, as: RichEditorEmptyResult.self)
    }

    func verifySwitch(_ args: RichEditorSwitchCheckArgs) async throws -> RichEditorSwitchCheckResult {
        try await performCall(.verifySwitch(args), as: RichEditorSwitchCheckResult.self)
    }

    func focusWebView() {
        webView.focusEditor()
    }

    /// Rebuilds the WebView cleanly after the content process dies so it can be
    /// reused once the 60 s cooldown ends (§7.8).
    func resetAfterTermination() {
        failAllInFlight(with: RichEditorBridgeError.processTerminated)
        detach(webView)
        hasStartedLoad = false
        isPageReady = false
        let replacement = Self.buildWebView(
            schemeHandler: schemeHandler,
            scriptProxy: scriptProxy,
            backgroundColor: backgroundColor
        )
        replacement.navigationDelegate = self
        replacement.uiDelegate = self
        webView = replacement
        webViewGeneration += 1
    }

    /// Breaks message-handler and delegate cycles when the editor closes.
    func teardown() {
        onEvent = nil
        onProcessTerminated = nil
        failAllInFlight(with: CancellationError())
        detach(webView)
        hasStartedLoad = false
        isPageReady = false
    }

    // MARK: Internals

    private static func buildWebView(
        schemeHandler: RichEditorURLSchemeHandler,
        scriptProxy: RichEditorScriptMessageProxy,
        backgroundColor: Color
    ) -> RichEditorWebView {
        let configuration = WKWebViewConfiguration()
        // Dedicated non-persistent store: isolated from AO3 cookies AND distinct
        // from `ReaderWebIsolation.isolatedDataStore` so Readium's delegate hook
        // never wraps this editor with a `readium:` policy.
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: RichEditorBundleLocation.scheme)
        configuration.userContentController.add(scriptProxy, name: RichEditorBridgeProtocol.messageHandlerName)
        return RichEditorWebView(
            frame: .zero,
            configuration: configuration,
            backgroundColor: backgroundColor
        )
    }

    private func detach(_ view: WKWebView) {
        view.stopLoading()
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.configuration.userContentController.removeScriptMessageHandler(
            forName: RichEditorBridgeProtocol.messageHandlerName
        )
    }

    private func ensurePageReady(timeout: Duration) async throws {
        if isPageReady { return }
        startLoadingIfNeeded()
        let race = RichEditorTimeoutRace<Void>()
        let id = UUID()
        activeCallFailers[id] = { [weak race] error in race?.fail(with: error) }
        defer { activeCallFailers.removeValue(forKey: id) }

        try await race.run(timeout: timeout, callName: "ready", clock: clock) { [weak self] in
            guard let self else { throw CancellationError() }
            if self.isPageReady { return }
            let waiterID = UUID()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    if self.isPageReady {
                        continuation.resume()
                    } else {
                        self.readyWaiters[waiterID] = continuation
                    }
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    if let continuation = self?.readyWaiters.removeValue(forKey: waiterID) {
                        continuation.resume(throwing: CancellationError())
                    }
                }
            }
        }
    }

    private func performCall<Value: Decodable & Sendable>(
        _ call: RichEditorBridgeCall,
        as type: Value.Type
    ) async throws -> Value {
        let invocation = try RichEditorBridgeEncoder.encode(call)
        let race = RichEditorTimeoutRace<Value>()
        let id = UUID()
        activeCallFailers[id] = { [weak race] error in race?.fail(with: error) }
        defer { activeCallFailers.removeValue(forKey: id) }

        return try await race.run(timeout: invocation.timeout, callName: invocation.callName, clock: clock) {
            [weak self] in
            guard let self else { throw CancellationError() }
            let arguments = try invocation.javaScriptArguments()
            let raw = try await self.webView.callAsyncJavaScript(
                invocation.script,
                arguments: arguments,
                in: nil,
                contentWorld: .page
            )
            return try RichEditorBridgeEncoder.decodeResult(type, from: raw, callName: invocation.callName)
        }
    }

    fileprivate func handleScriptMessage(_ body: Any) {
        do {
            let event = try RichEditorEvent.decode(from: body)
            if case .ready = event {
                markPageReady()
            }
            onEvent?(event)
        } catch {
            writingEditorLog.error(
                "Ignored malformed editor bridge event: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func markPageReady() {
        isPageReady = true
        let waiters = readyWaiters.values
        readyWaiters.removeAll()
        for continuation in waiters {
            continuation.resume()
        }
    }

    private func failAllInFlight(with error: Error) {
        let waiters = readyWaiters.values
        readyWaiters.removeAll()
        for continuation in waiters {
            continuation.resume(throwing: error)
        }
        let failers = activeCallFailers.values
        activeCallFailers.removeAll()
        for fail in failers {
            fail(error)
        }
    }
}

extension RichEditorHost: WKNavigationDelegate {
    func webView(
        _: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(RichEditorNavigationPolicy.decidePolicy(for: navigationAction))
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        // The stub and editor-core both emit `ready`; if `didFinish` lands after
        // the script already ran without a `ready` message, wake waiters so
        // `configure` can probe `window.KudosEditor.call` directly.
        if !isPageReady {
            markPageReady()
        }
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        hasStartedLoad = false
        failAllInFlight(with: RichEditorBridgeError.notReady(error.localizedDescription))
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        hasStartedLoad = false
        failAllInFlight(with: RichEditorBridgeError.notReady(error.localizedDescription))
    }

    func webViewWebContentProcessDidTerminate(_: WKWebView) {
        writingEditorLog.notice("Rich Text WebView content process terminated")
        isPageReady = false
        hasStartedLoad = false
        failAllInFlight(with: RichEditorBridgeError.processTerminated)
        onProcessTerminated?()
    }
}

extension RichEditorHost: WKUIDelegate {
    func webView(
        _: WKWebView,
        createWebViewWith _: WKWebViewConfiguration,
        for _: WKNavigationAction,
        windowFeatures _: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }
}

/// Weak forwarder so `WKUserContentController` does not retain `RichEditorHost`.
private final class RichEditorScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var host: RichEditorHost?

    func userContentController(
        _: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        host?.handleScriptMessage(message.body)
    }
}

/// One-shot timeout race that returns immediately when a deadline expires, even
/// if a hung `WKWebView.callAsyncJavaScript` call never resolves.
@MainActor
private final class RichEditorTimeoutRace<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Error>?
    private var preCancelledError: Error?
    private var workTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?

    func run(
        timeout: Duration,
        callName: String,
        clock: any WritingClock,
        operation: @escaping @MainActor () async throws -> Value
    ) async throws -> Value {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, Error>) in
                if let preCancelledError {
                    continuation.resume(throwing: preCancelledError)
                    return
                }
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                self.workTask = Task { [weak self] in
                    do {
                        let value = try await operation()
                        self?.finish(.success(value))
                    } catch {
                        self?.finish(.failure(error))
                    }
                }
                self.timerTask = Task { [weak self] in
                    do {
                        try await clock.sleep(for: timeout)
                        self?.finish(.failure(RichEditorBridgeError.timeout(
                            call: callName,
                            duration: timeout
                        )))
                    } catch {
                        // Cancelled when work completes first.
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.fail(with: CancellationError())
            }
        }
    }

    func fail(with error: Error) {
        if continuation == nil {
            preCancelledError = error
        } else {
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<Value, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        workTask?.cancel()
        workTask = nil
        timerTask?.cancel()
        timerTask = nil
        continuation.resume(with: result)
    }
}
