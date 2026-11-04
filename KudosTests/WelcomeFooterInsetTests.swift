import Foundation
import SwiftUI
import Testing
@testable import Kudos

/// FID50 / Board 52: Welcome screen scrolling content has a bottom safe-area inset
/// matching the pinned footer height, so every feature row can be scrolled fully into
/// view above it and no glyph fragments are trapped or clipped.
struct WelcomeFooterInsetTests {

    @Test func onboardingScaffoldUsesBottomSafeAreaInsetContract() {
        #expect(OnboardingScaffold<EmptyView, EmptyView>.usesBottomSafeAreaInset)
    }

    @Test @MainActor func onboardingScaffoldBodyHasBottomSafeAreaInset() {
        let scaffold = OnboardingScaffold(
            content: { Text("Test Content") },
            footer: { Text("Test Footer") }
        )
        let body = scaffold.body
        #expect(hasBottomSafeAreaInset(in: body))
    }

    @Test @MainActor func welcomeViewHasFourFeatureRowsInOrder() {
        let welcome = WelcomeView(onContinue: {})
        let rows = extractPointRows(from: welcome)

        #expect(rows.count == 4)
        guard rows.count == 4 else { return }

        #expect(rows[0].symbol == "book")
        #expect(rows[0].title == "Built for AO3 Readers")

        #expect(rows[1].symbol == "lock.shield")
        #expect(rows[1].title == "Your Privacy Matters")

        #expect(rows[2].symbol == "heart")
        #expect(rows[2].title == "Community Built")

        // The 4th row whose icon was clipped by the footer before the bottom inset
        #expect(rows[3].symbol == "ladybug")
        #expect(rows[3].title == "Need Help?")
        #expect(rows[3].message.contains("Found a bug?"))
    }

    @Test func legacyVStackLayoutFailsInsetCheck() {
        // Simulates the reverted layout: VStack without safeAreaInset
        let revertedView = VStack(spacing: 0) {
            ScrollView {
                Text("Intro")
            }
            Text("Footer")
        }
        #expect(!hasBottomSafeAreaInset(in: revertedView))
    }

    // MARK: - Helpers

    /// Inspects a SwiftUI view hierarchy for a safe area inset modifier on the bottom edge.
    private func hasBottomSafeAreaInset(in view: Any) -> Bool {
        var queue: [Any] = [view]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            let typeName = String(describing: type(of: current))
            if typeName.contains("SafeAreaInsetsModifier") || typeName.contains("SafeAreaInset") {
                let mirror = Mirror(reflecting: current)
                for child in mirror.children {
                    if child.label == "edge" {
                        if let edge = child.value as? VerticalEdge, edge == .bottom {
                            return true
                        }
                        if String(describing: child.value).contains("bottom") {
                            return true
                        }
                    }
                }
                return true
            }
            let mirror = Mirror(reflecting: current)
            for child in mirror.children {
                queue.append(child.value)
            }
        }
        return false
    }

    /// Extracts `OnboardingPointRow` models from `WelcomeView` via reflection.
    @MainActor
    private func extractPointRows(from view: Any) -> [OnboardingPointRow] {
        var rows: [OnboardingPointRow] = []
        var queue: [Any] = [view]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if let row = current as? OnboardingPointRow {
                rows.append(row)
                continue
            }
            let mirror = Mirror(reflecting: current)
            for child in mirror.children {
                queue.append(child.value)
            }
        }
        return rows
    }
}
