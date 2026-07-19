import SwiftUI

/// The tighter, softly rounded shape shared by Account navigation and submenu
/// triggers. Work cards deliberately retain the library's standard geometry.
enum AccountControlMetrics {
    static let cornerRadius: CGFloat = CardRadius.accountControl
    static let inlineCornerRadius: CGFloat = CardRadius.accountInlineControl
    static let verticalPadding: CGFloat = 6
    static let interCardSpacing: CGFloat = 8
    static let compactSpacing: CGFloat = 12
}

extension View {
    func accountControlCardRow() -> some View {
        cardRow(
            cornerRadius: AccountControlMetrics.cornerRadius,
            verticalPadding: AccountControlMetrics.verticalPadding,
            interCardSpacing: AccountControlMetrics.interCardSpacing
        )
    }
}
