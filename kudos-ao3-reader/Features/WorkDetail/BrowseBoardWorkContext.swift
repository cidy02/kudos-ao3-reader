import SwiftUI

/// A work's identity above a form that edits one of its attributes.
struct BrowseBoardWorkContext: View {
    let title: String
    let kicker: String?
    let fandoms: [String]
    let metadata: String

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(CoverArt.workGradient(fandoms: fandoms, title: title))
                .frame(width: 36, height: 50)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                if let kicker, !kicker.isEmpty {
                    Text(kicker)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(themeManager.accentInk)
                }
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if !metadata.isEmpty {
                    Text(metadata)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
