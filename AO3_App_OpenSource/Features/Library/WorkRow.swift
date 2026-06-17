import SwiftUI

/// One row representing a saved work, reused across Library and Bookmarks.
struct WorkRow: View {
    let work: SavedWork

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(work.title).font(.headline).lineLimit(2)
                if !work.author.isEmpty {
                    Text(work.author).font(.subheadline).foregroundStyle(.secondary)
                }
                if !work.tags.isEmpty {
                    Text(work.tags.map(\.name).sorted().joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if work.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, 2)
    }
}
