import SwiftUI

/// Temporary section placeholders so the S1 shell lane compiles standalone.
/// Replaced when the S2 (Documents), S3 (Comments), and S4 (Stats) lanes merge.
struct StudioDocumentsView: View {
    init() {}

    var body: some View {
        StudioSectionComingSoonView(
            title: "Documents",
            systemImage: "doc.text",
            description: "Coming in this build."
        )
    }
}

struct StudioCommentsView: View {
    init() {}

    var body: some View {
        StudioSectionComingSoonView(
            title: "Comments",
            systemImage: "bubble.left.and.bubble.right",
            description: "Coming in this build."
        )
    }
}

struct StudioStatsView: View {
    init() {}

    var body: some View {
        StudioSectionComingSoonView(
            title: "Stats",
            systemImage: "chart.bar",
            description: "Coming in this build."
        )
    }
}

private struct StudioSectionComingSoonView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        ScrollView {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text(description)
            )
            .padding(.top, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
