import SwiftUI

/// A small uppercase state pill in one colour: 15 % fill, 35 % hairline, radius
/// 7, 9.5pt semibold. The series card's "Complete" / "In progress" badge, and
/// 1x's "3 days left" on a draft, which the board draws in the same metrics.
struct SubjectStateBadge: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.5)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(color.opacity(0.35), lineWidth: 0.5)
            )
            .accessibilityLabel(title)
    }
}
