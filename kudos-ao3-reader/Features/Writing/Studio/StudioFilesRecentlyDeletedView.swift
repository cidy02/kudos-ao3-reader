import SwiftUI

/// Local Writing Studio trash (`Studio-Files` → Recently Deleted).
/// Backed directly by `WritingDocumentStore`'s 30-day Recently Deleted folder.
struct StudioFilesRecentlyDeletedView: View {
    let store: WritingDocumentStore
    var onChanged: () -> Void = {}

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var items: [WritingDeletedItem] = []
    @State private var isLoading = true
    @State private var itemToDeleteNow: WritingDeletedItem?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Text(
                    "Deleted works and chapters stay on this \(ThisDevice.name) for 30 days "
                        + "before they are removed permanently."
                )
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            }
            .appThemedRows()

            if isLoading {
                Section {
                    ProgressView("Loading Recently Deleted…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accentFill()
                }
                .appThemedRows()
            } else if items.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Recently Deleted Is Empty",
                        systemImage: "trash",
                        description: Text("Works and chapters you delete stay here for 30 days.")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(items) { item in
                        deletedRow(item)
                    }
                }
                .appThemedRows()
            }
        }
        .appThemedScroll()
        .navigationTitle("Recently Deleted")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await reload(sweepExpired: true) }
        .refreshable { await reload(sweepExpired: true) }
        .alert(
            "Delete Permanently?",
            isPresented: Binding(
                get: { itemToDeleteNow != nil },
                set: { if !$0 { itemToDeleteNow = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { itemToDeleteNow = nil }
            Button("Delete Now", role: .destructive) {
                guard let item = itemToDeleteNow else { return }
                itemToDeleteNow = nil
                Task { await performDeleteNow(item) }
            }
        } message: {
            let title = displayTitle(for: itemToDeleteNow)
            Text("\"\(title)\" will be removed from this \(ThisDevice.name) immediately and cannot be recovered.")
        }
        .alert(
            "Couldn't Update Recently Deleted",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func deletedRow(_ item: WritingDeletedItem) -> some View {
        let title = displayTitle(for: item)
        let kindText = kindLabel(for: item.kind)
        let countdown = StudioRecentlyDeletedHelper.countdownText(deletedAt: item.deletedAt)
        let isUrgent = StudioRecentlyDeletedHelper.isUrgent(deletedAt: item.deletedAt)

        let countdownStyle: AnyShapeStyle = isUrgent
            ? AnyShapeStyle(theme.appTheme.errorColor)
            : AnyShapeStyle(.secondaryInk)

        return HStack(spacing: 12) {
            Image(systemName: symbolName(for: item.kind))
                .font(.body)
                .foregroundStyle(.secondaryInk)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kindText)
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                        Text(countdown)
                            .font(.caption.weight(isUrgent ? .semibold : .regular))
                            .foregroundStyle(countdownStyle)
                    }
                } else {
                    HStack(spacing: 6) {
                        Text(kindText)
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                            .accessibilityHidden(true)
                        Text(countdown)
                            .font(.caption.weight(isUrgent ? .semibold : .regular))
                            .foregroundStyle(countdownStyle)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                rowActions(item)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body)
                    .foregroundStyle(theme.accentInk)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .minimumHitTarget()
            .accessibilityLabel("Actions for \(title)")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Restore") {
            Task { await performRestore(item) }
        }
        .accessibilityAction(named: "Delete Now") {
            itemToDeleteNow = item
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task { await performRestore(item) }
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(theme.effectiveTint)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                itemToDeleteNow = item
            } label: {
                Label("Delete Now", systemImage: "trash")
            }
        }
        .contextMenu {
            rowActions(item)
        }
    }

    @ViewBuilder
    private func rowActions(_ item: WritingDeletedItem) -> some View {
        Button {
            Task { await performRestore(item) }
        } label: {
            Label("Restore", systemImage: "arrow.uturn.backward")
        }
        Button(role: .destructive) {
            itemToDeleteNow = item
        } label: {
            Label("Delete Now", systemImage: "trash")
        }
    }

    private func reload(sweepExpired: Bool) async {
        do {
            if sweepExpired {
                _ = try await store.emptyRecentlyDeleted()
            }
            items = try await store.listRecentlyDeleted()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
        isLoading = false
    }

    private func performRestore(_ item: WritingDeletedItem) async {
        do {
            switch item.kind {
            case .work:
                _ = try await store.restoreWork(item.id)
            case .chapter:
                _ = try await store.restoreChapter(item.id)
            }
            await reload(sweepExpired: false)
            onChanged()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func performDeleteNow(_ item: WritingDeletedItem) async {
        do {
            try await store.deleteNow(item.id)
            await reload(sweepExpired: false)
            onChanged()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func displayTitle(for item: WritingDeletedItem?) -> String {
        let trimmed = item?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    private func kindLabel(for kind: WritingDeletedItem.Kind) -> String {
        switch kind {
        case .work: "Work"
        case .chapter: "Chapter"
        }
    }

    private func symbolName(for kind: WritingDeletedItem.Kind) -> String {
        switch kind {
        case .work: "folder"
        case .chapter: "doc.text"
        }
    }
}
