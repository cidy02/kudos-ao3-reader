import Foundation
import OSLog
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Minimal lifecycle surface needed by `RichEditorPrewarmPool` so pre-warm
/// reuse and memory-warning eviction can be tested without spinning up WebKit.
@MainActor
protocol RichEditorPrewarmableHost: AnyObject {
    var hasStartedLoading: Bool { get }
    func startLoadingIfNeeded()
    func applyNativeBackgroundColor(_ color: Color)
    func teardown()
}

/// Holds at most one hidden pre-warmed Rich Text WebView host while the user
/// is on the Writing screens (docs/WRITING_EDITOR_ARCHITECTURE.md §9.3, §10.3 N10).
///
/// - **Pre-warm:** when a Writing screen appears and the Rich Text feature flag
///   is on, creates one hidden host and loads `kudos-editor://editor/editor.html`.
/// - **Reuse:** when `WritingTextEditor` opens, claims the warm host so opening
///   a chapter pays no page-load cost.
/// - **W4:** on a memory warning, immediately drops and tears down the hidden
///   host and observes a 60 s cooldown before pre-warming again.
@MainActor @Observable
final class RichEditorPrewarmPool: NSObject {
    nonisolated static let memoryWarningCooldown: Duration = .seconds(60)

    static let shared = RichEditorPrewarmPool()

    /// Unclaimed hidden warm host waiting for the next editor open.
    private(set) var warmHost: (any RichEditorPrewarmableHost)?
    private(set) var reuseCount = 0
    private(set) var memoryWarningDropCount = 0
    private(set) var lastMemoryWarningAt: Duration?

    @ObservationIgnored
    private let clock: any WritingClock
    @ObservationIgnored
    private let makeHost: @MainActor (Color) -> any RichEditorPrewarmableHost

    /// Underlying `RichEditorWebView` when the warm slot holds a real `RichEditorHost`,
    /// mounted invisibly (1×1) so WebKit does not throttle its load.
    var warmWebView: RichEditorWebView? {
        (warmHost as? RichEditorHost)?.webView
    }

    var hasWarmHost: Bool { warmHost != nil }

    var isWithinMemoryWarningCooldown: Bool {
        guard let lastMemoryWarningAt else { return false }
        return clock.now < lastMemoryWarningAt + Self.memoryWarningCooldown
    }

    init(
        clock: any WritingClock = SystemWritingClock(),
        observeMemoryWarnings: Bool = true,
        makeHost: @escaping @MainActor (Color) -> any RichEditorPrewarmableHost = { color in
            RichEditorHost(backgroundColor: color)
        }
    ) {
        self.clock = clock
        self.makeHost = makeHost
        super.init()
        #if os(iOS)
        if observeMemoryWarnings {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(didReceiveMemoryWarningNotification),
                name: UIApplication.didReceiveMemoryWarningNotification,
                object: nil
            )
        }
        #endif
    }

    /// Ensures at most one hidden host is loaded and ready with `backgroundColor`.
    func prewarmIfNeeded(
        backgroundColor: Color,
        isFeatureEnabled: Bool = RichEditorFeatureFlag.isEnabled
    ) {
        guard isFeatureEnabled else {
            dropWarmHost()
            return
        }
        guard !isWithinMemoryWarningCooldown else { return }
        if let existing = warmHost {
            existing.applyNativeBackgroundColor(backgroundColor)
            existing.startLoadingIfNeeded()
            return
        }
        let host = makeHost(backgroundColor)
        host.startLoadingIfNeeded()
        warmHost = host
    }

    /// Claims the warm host if available, otherwise creates a fresh one.
    func takeOrCreateHost(backgroundColor: Color) -> any RichEditorPrewarmableHost {
        if let existing = warmHost {
            warmHost = nil
            existing.applyNativeBackgroundColor(backgroundColor)
            reuseCount += 1
            return existing
        }
        return makeHost(backgroundColor)
    }

    /// Typed convenience for `WritingTextEditor` claiming a real `RichEditorHost`.
    func takeOrCreateRichEditorHost(backgroundColor: Color) -> RichEditorHost {
        if let claimed = takeOrCreateHost(backgroundColor: backgroundColor) as? RichEditorHost {
            return claimed
        }
        return RichEditorHost(backgroundColor: backgroundColor)
    }

    /// W4: drops any idle hidden WebView on memory warning and starts the 60 s cooldown.
    func handleMemoryWarning() {
        lastMemoryWarningAt = clock.now
        if warmHost != nil {
            dropWarmHost()
            memoryWarningDropCount += 1
            writingEditorLog.notice("Dropped pre-warmed Rich Text WebView on memory warning")
        }
    }

    /// Tears down and clears the idle warm host without setting a memory-warning cooldown.
    func dropWarmHost() {
        guard let existing = warmHost else { return }
        warmHost = nil
        existing.teardown()
    }

    #if os(iOS)
    @objc private func didReceiveMemoryWarningNotification() {
        handleMemoryWarning()
    }
    #endif
}

/// Mounts the unclaimed pre-warmed `RichEditorWebView` invisibly while a Writing
/// screen is visible so WebKit completes the bundle load without throttling.
private struct RichEditorPrewarmModifier: ViewModifier {
    let backgroundColor: Color
    @AppStorage(RichEditorFeatureFlag.storageKey) private var richEditorEnabled = false
    private let pool = RichEditorPrewarmPool.shared

    func body(content: Content) -> some View {
        content
            .background {
                if richEditorEnabled, let webView = pool.warmWebView {
                    RichEditorWebViewContainer(webView: webView)
                        .frame(width: 1, height: 1)
                        .opacity(0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onAppear {
                pool.prewarmIfNeeded(
                    backgroundColor: backgroundColor,
                    isFeatureEnabled: richEditorEnabled
                )
            }
            .onChange(of: richEditorEnabled) { _, enabled in
                pool.prewarmIfNeeded(backgroundColor: backgroundColor, isFeatureEnabled: enabled)
            }
            .onChange(of: backgroundColor) { _, nextColor in
                pool.prewarmIfNeeded(backgroundColor: nextColor, isFeatureEnabled: richEditorEnabled)
            }
    }
}

extension View {
    /// Pre-warms one hidden Rich Text WebView when a Writing screen appears (§9.3).
    func richEditorPrewarm(backgroundColor: Color) -> some View {
        modifier(RichEditorPrewarmModifier(backgroundColor: backgroundColor))
    }
}
