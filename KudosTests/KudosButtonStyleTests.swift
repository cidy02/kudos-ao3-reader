import SwiftUI
import Testing
@testable import Kudos

struct KudosButtonStyleTests {
    @Test func buttonSizesFollowRuleI9() {
        #expect(KudosButtonStyle.Size.regular.minHeight == 44)
        #expect(KudosButtonStyle.Size.confirm.minHeight == 50)
    }

    @Test func defaultInitializationUsesPrimaryAndRegular() {
        let style = KudosButtonStyle()
        #expect(style.variant == .primary)
        #expect(style.size == .regular)
    }

    @Test func explicitVariantAndSizeArePreserved() {
        let confirm = KudosButtonStyle(variant: .primary, size: .confirm)
        #expect(confirm.variant == .primary)
        #expect(confirm.size == .confirm)

        let secondary = KudosButtonStyle(variant: .secondary, size: .regular)
        #expect(secondary.variant == .secondary)
        #expect(secondary.size == .regular)

        let secondaryCircle = KudosButtonStyle(variant: .secondaryCircle, size: .regular)
        #expect(secondaryCircle.variant == .secondaryCircle)

        let onGradient = KudosButtonStyle(variant: .onGradient, size: .confirm)
        #expect(onGradient.variant == .onGradient)
        #expect(onGradient.size == .confirm)
    }

    @Test func typealiasParity() {
        let appStyle = AppCapsuleButtonStyle(variant: .primary, size: .confirm)
        #expect(appStyle.size.minHeight == 50)
        #expect(AppButtonSize.confirm.minHeight == 50)
        #expect(AppButtonSize.regular.minHeight == 44)
    }
}
