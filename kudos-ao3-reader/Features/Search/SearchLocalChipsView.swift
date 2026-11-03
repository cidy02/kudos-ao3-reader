import SwiftUI

/// A chip displayed in the "Your tags, collections, fandoms" section (Board 11).
struct SearchLocalChip: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case tag = "Tag"
        case collection = "Collection"
        case fandom = "Fandom"
    }

    enum Target: Hashable, Sendable {
        case tag(String)
        case collection(UUID, name: String)
        case fandom(String)
    }

    let id: String
    let kind: Kind
    let label: String
    let count: Int
    let target: Target
}

extension SearchLocalChip {
    static func makeChips(
        tags: [(name: String, workCount: Int)],
        collections: [(id: UUID, name: String, workCount: Int)],
        fandoms: [(name: String, workCount: Int)]
    ) -> [SearchLocalChip] {
        var chips: [SearchLocalChip] = []
        for tag in tags {
            chips.append(SearchLocalChip(
                id: "tag:\(tag.name)",
                kind: .tag,
                label: tag.name,
                count: tag.workCount,
                target: .tag(tag.name)
            ))
        }
        for collection in collections {
            chips.append(SearchLocalChip(
                id: "collection:\(collection.id.uuidString)",
                kind: .collection,
                label: collection.name,
                count: collection.workCount,
                target: .collection(collection.id, name: collection.name)
            ))
        }
        for fandom in fandoms {
            chips.append(SearchLocalChip(
                id: "fandom:\(fandom.name)",
                kind: .fandom,
                label: fandom.name,
                count: fandom.workCount,
                target: .fandom(fandom.name)
            ))
        }
        return chips
    }
}

/// Wraps chips representing matching local tags, collections, and fandoms (Board 11).
struct SearchLocalChipsView: View {
    let chips: [SearchLocalChip]
    let collections: [WorkCollection]
    let onTagTap: (String) -> Void
    let onFandomTap: (String) -> Void

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        FlowLayout(spacing: 8, rowSpacing: 8) {
            ForEach(chips) { chip in
                chipView(for: chip)
            }
        }
    }

    @ViewBuilder
    private func chipView(for chip: SearchLocalChip) -> some View {
        let chipLabel = HStack(spacing: 6) {
            Text(chip.kind.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(chip.label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.primary)
            Text("\(chip.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .background(themeManager.appTheme.glassFill(0.12))
        .clipShape(Capsule())

        switch chip.target {
        case .tag(let name):
            Button {
                onTagTap(name)
            } label: {
                chipLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tag: \(chip.label), \(chip.count) \(chip.count == 1 ? "work" : "works")")

        case .fandom(let name):
            Button {
                onFandomTap(name)
            } label: {
                chipLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fandom: \(chip.label), \(chip.count) \(chip.count == 1 ? "work" : "works")")

        case .collection(let id, _):
            if let col = collections.first(where: { $0.id == id }) {
                NavigationLink(value: col) {
                    chipLabel
                }
                .buttonStyle(.plain)
                .collectionCardMenu(col)
                .accessibilityLabel("Collection: \(chip.label), \(chip.count) \(chip.count == 1 ? "work" : "works")")
            } else {
                chipLabel
            }
        }
    }
}
