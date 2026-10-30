import SwiftUI

/// The spacing shared by Account navigation and submenu triggers. Their corner
/// is every card's, `SubjectMetrics.cornerRadius` (T-484).
enum AccountControlMetrics {
    static let verticalPadding: CGFloat = 6
    static let interCardSpacing: CGFloat = 8
    static let compactSpacing: CGFloat = 12
}

extension View {
    func accountControlCardRow() -> some View {
        cardRow(
            verticalPadding: AccountControlMetrics.verticalPadding,
            interCardSpacing: AccountControlMetrics.interCardSpacing
        )
    }
}
