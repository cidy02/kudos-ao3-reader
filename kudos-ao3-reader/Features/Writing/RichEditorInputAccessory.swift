import Foundation
import OSLog
#if os(iOS)
import ObjectiveC
import UIKit
import WebKit
#endif

/// Outcome of installing `WritingKeysInputAccessoryView` over WebKit's private
/// form accessory bar (docs/WRITING_EDITOR_ARCHITECTURE.md §10.3 N3).
nonisolated enum RichEditorInputAccessoryStatus: Equatable, Sendable {
    /// Dynamic subclass replaced `WKContentView.inputAccessoryView` and passed
    /// the launch-time verification check.
    case replaced
    /// Replacement did not take (for example, a future iOS renamed the internal
    /// content view or ignored the override); Kudos renders its keys bar natively
    /// above WebKit's bar instead (§7.7 fallback).
    case fallback(reason: String)

    var usesFallbackBar: Bool {
        if case .fallback = self { return true }
        return false
    }
}

/// Isolated Objective-C runtime hook that replaces `WKContentView`'s
/// `inputAccessoryView` (Capacitor keyboard plugin pattern) and routes its
/// `undoManager` to the owning `RichEditorWebView` while Rich Text owns the
/// text (§10.3 N3, N6).
///
/// Always confirms the replacement took by reading `target.inputAccessoryView`
/// back; on failure it reports `.fallback` and logs once per launch.
@MainActor
enum RichEditorInputAccessoryInstaller {
    private static var didLogFallback = false

    /// Logs a fallback reason at most once per process launch.
    @discardableResult
    static func logFallbackOnce(
        reason: String,
        sink: ((String) -> Void)? = nil
    ) -> Bool {
        guard !didLogFallback else { return false }
        didLogFallback = true
        let message = "Rich Text inputAccessoryView replacement fell back to native bar (\(reason))"
        if let sink {
            sink(message)
        } else {
            writingEditorLog.notice("\(message, privacy: .public)")
        }
        return true
    }

    /// Resets the log-once latch for unit tests.
    static func resetFallbackLogForTesting() {
        didLogFallback = false
    }

    #if os(iOS)
    private static let subclassPrefix = "KudosRichInputAccessory_"
    private static let accessories = NSMapTable<UIView, UIView>.weakToStrongObjects()
    private static let undoOwners = NSMapTable<UIView, RichEditorWebView>.weakToWeakObjects()

    /// Locates WebKit's internal editable content view inside `webView.scrollView`.
    static func findContentView(in webView: WKWebView) -> UIView? {
        webView.scrollView.subviews.first { subview in
            NSStringFromClass(type(of: subview)).hasPrefix("WKContentView")
        }
    }

    /// Replaces `WKContentView`'s `inputAccessoryView` with `accessoryView` and
    /// verifies the override took. Falls back cleanly (logging once) on failure.
    @discardableResult
    static func install(
        accessoryView: UIView,
        on webView: WKWebView,
        undoOwner: RichEditorWebView? = nil,
        contentViewProvider: ((WKWebView) -> UIView?)? = nil,
        verify: ((UIView, UIView) -> Bool)? = nil,
        fallbackLogSink: ((String) -> Void)? = nil
    ) -> RichEditorInputAccessoryStatus {
        let provider = contentViewProvider ?? { findContentView(in: $0) }
        guard let contentView = provider(webView) else {
            let reason = "content-view-missing"
            logFallbackOnce(reason: reason, sink: fallbackLogSink)
            return .fallback(reason: reason)
        }
        return install(
            accessoryView: accessoryView,
            onTarget: contentView,
            undoOwner: undoOwner,
            verify: verify,
            fallbackLogSink: fallbackLogSink
        )
    }

    /// Installs and verifies the dynamic `inputAccessoryView` subclass on a
    /// specific `UIView` target (exposed for direct testing on plain `UIView`s).
    @discardableResult
    static func install(
        accessoryView: UIView,
        onTarget target: UIView,
        undoOwner: RichEditorWebView? = nil,
        verify: ((UIView, UIView) -> Bool)? = nil,
        fallbackLogSink: ((String) -> Void)? = nil
    ) -> RichEditorInputAccessoryStatus {
        accessories.setObject(accessoryView, forKey: target)
        if let undoOwner {
            undoOwners.setObject(undoOwner, forKey: target)
        }

        guard applySubclass(to: target, attachUndoProxy: undoOwner != nil) else {
            accessories.removeObject(forKey: target)
            undoOwners.removeObject(forKey: target)
            let reason = "runtime-subclass-failed"
            logFallbackOnce(reason: reason, sink: fallbackLogSink)
            return .fallback(reason: reason)
        }

        let confirmed = verify?(target, accessoryView) ?? (target.inputAccessoryView === accessoryView)
        guard confirmed else {
            accessories.removeObject(forKey: target)
            undoOwners.removeObject(forKey: target)
            let reason = "verification-mismatch"
            logFallbackOnce(reason: reason, sink: fallbackLogSink)
            return .fallback(reason: reason)
        }

        if target.isFirstResponder {
            target.reloadInputViews()
        }
        return .replaced
    }

    private static func applySubclass(to target: UIView, attachUndoProxy: Bool) -> Bool {
        let targetClass: AnyClass = type(of: target)
        let originalName = NSStringFromClass(targetClass)
        if originalName.hasPrefix(subclassPrefix) {
            return true
        }

        let subclassName = subclassPrefix + originalName
        if let existingClass = NSClassFromString(subclassName) {
            object_setClass(target, existingClass)
            return true
        }

        guard let newClass = objc_allocateClassPair(targetClass, subclassName, 0) else {
            return false
        }

        let accessoryBlock: @convention(block) (AnyObject) -> AnyObject? = { instance in
            guard let view = instance as? UIView else { return nil }
            return MainActor.assumeIsolated {
                RichEditorInputAccessoryInstaller.accessories.object(forKey: view)
            }
        }
        let accessorySelector = #selector(getter: UIResponder.inputAccessoryView)
        let accessoryAdded = class_addMethod(
            newClass,
            accessorySelector,
            imp_implementationWithBlock(accessoryBlock),
            "@@:"
        )
        guard accessoryAdded else {
            objc_disposeClassPair(newClass)
            return false
        }

        if attachUndoProxy {
            let undoBlock: @convention(block) (AnyObject) -> AnyObject? = { instance in
                guard let view = instance as? UIView else { return nil }
                return MainActor.assumeIsolated {
                    RichEditorInputAccessoryInstaller.undoOwners.object(forKey: view)?.undoManager
                }
            }
            let undoSelector = #selector(getter: UIResponder.undoManager)
            _ = class_addMethod(
                newClass,
                undoSelector,
                imp_implementationWithBlock(undoBlock),
                "@@:"
            )
        }

        objc_registerClassPair(newClass)
        object_setClass(target, newClass)
        return true
    }
    #endif
}
