import Foundation
import SwiftUI

/// The full list behind the Library Collections shelf.
struct LibraryCollectionIndexView: View {
    let collections: [WorkCollection]
    let onNew: () -> Void

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        List {
            if collections.isEmpty {
                ContentUnavailableView(BrowseBoardCopy.emptyCollections, systemImage: "square.stack")
                    .bareListRow()
            } else {
                ForEach(collections) { collection in
                    NavigationLink(value: collection) {
                        LibraryCollectionIndexRow(collection: collection)
                    }
                    .collectionCardMenu(collection)
                    .appThemedRows()
                }
            }
        }
        .listStyle(.plain)
        .appThemedScroll()
        .subjectScreenWash(title: "Collections", palette: themeManager.scopePalette, role: .content)
        .toolbar {
            ActionToolbar(items: [
                AnyView(ToolbarIconButton(title: "New Collection", systemImage: "plus", action: onNew))
            ])
        }
    }
}

private struct LibraryCollectionIndexRow: View {
    let collection: WorkCollection

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    }

    private var detail: String {
        let updated = max(collection.lastModifiedAt, collection.lastMembershipChangedAt ?? collection.lastModifiedAt)
        let updatedLabel = Calendar.current.isDateInToday(updated)
            ? "updated today"
            : updated.formatted(.dateTime.month(.abbreviated).day())
        return BrowseBoardCopy.collectionRow(
            workCount: collection.works.count(where: { !$0.isPendingDeletion }),
            showsOnHome: collection.showsOnHome,
            updatedLabel: updatedLabel
        )
    }

    var body: some View {
        layout {
            let palette = themeManager.appTheme.subjectPalette(hue: collection.displayHue)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.accent)
                .frame(width: 40, height: 40)
                .overlay {
                    Text(String(collection.name.prefix(1)).uppercased())
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
    }
}
