#if os(iOS)
import SwiftUI
import Testing
@testable import Kudos

@MainActor
struct WideLayoutTests {
    @Test func regularWidthAndHeightAllowWideLayout() {
        #expect(WideLayout.isAvailable(horizontal: .regular, vertical: .regular))
    }

    @Test func compactWidthUsesCompactLayout() {
        #expect(!WideLayout.isAvailable(horizontal: .compact, vertical: .regular))
    }

    @Test func compactHeightUsesCompactLayoutEvenWithRegularWidth() {
        #expect(!WideLayout.isAvailable(horizontal: .regular, vertical: .compact))
    }

    @Test func bothCompactUsesCompactLayout() {
        #expect(!WideLayout.isAvailable(horizontal: .compact, vertical: .compact))
    }

    @Test func unspecifiedSizeClassesUseCompactLayout() {
        #expect(!WideLayout.isAvailable(horizontal: nil, vertical: .regular))
        #expect(!WideLayout.isAvailable(horizontal: .regular, vertical: nil))
        #expect(!WideLayout.isAvailable(horizontal: nil, vertical: nil))
    }
}
#endif
