import SwiftUI
import UniformTypeIdentifiers

/// Writing Studio → Documents → Files (`Studio-Files`):
/// import plain text/Markdown/HTML from Files, import a work to AO3 from a URL,
/// work folders with Posted / AO3 draft / device badges, Recently Deleted, and
/// on-device storage summary.
struct StudioFilesView: View {
    let works: [StudioWorkItem]
    let deletedCount: Int
    let storageSummary: StudioStorageSummary
    let store: WritingDocumentStore
    let sort: StudioFilesSort
    let isLoadingAO3: Bool
    var onChanged: () -> Void = {}
    var onAO3Write: () -> Void = {}
    var onOpenImported: (StudioImportedDocument) -> Void = { _ in }

    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showingFileImporter = false
    @State private var showingURLImporter = false
    @State private var importedAO3DraftID: Int?
    @State private var isImportingDocument = false
    @State private var importError: String?

    private var sortedWorks: [StudioWorkItem] {
        StudioDocumentsCatalog.sortFolders(works, by: sort)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            importDocumentCard
            importURLRow
            foldersSection
            recentlyDeletedRow
            storageFooterCard
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: StudioDocumentImporter.allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $showingURLImporter) {
            ImportWorkView(
                onOpenDraft: { workID in
                    onAO3Write()
                    importedAO3DraftID = workID
                },
                onOpenWork: { workID in
                    router.openAO3Link(AO3Client.workURL(workID: workID))
                }
            )
        }
        .navigationDestination(item: $importedAO3DraftID) { workID in
            WritingWorkDestination(workID: workID) {
                onAO3Write()
            }
        }
        .alert(
            "Couldn't Import Document",
            isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: - Import controls

    private var importDocumentCard: some View {
        let shape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
        return Button {
            showingFileImporter = true
        } label: {
            HStack(spacing: 12) {
                if isImportingDocument {
                    ProgressView()
                        .frame(width: 26, height: 26)
                        .accentFill()
                } else {
                    Image(systemName: "square.and.arrow.down")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(theme.accentInk)
                        .frame(width: 26, height: 26)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Import a Document")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    Text("Word, plain text, Markdown or HTML, from Files")
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                shape.strokeBorder(
                    theme.appTheme.glassStroke(0.32),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(isImportingDocument)
        .accessibilityLabel("Import a Document. Word, plain text, Markdown or HTML, from Files")
    }

    @ViewBuilder
    private var importURLRow: some View {
        if auth.isLoggedIn {
            Button {
                showingURLImporter = true
            } label: {
                HStack(spacing: 6) {
                    Text("Import a work to AO3 from a URL")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.accentInk)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.accentInk)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Import a work to AO3 from a URL")
        } else {
            Text("Sign in to AO3 to import a work from a URL or manage works on AO3.")
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Folders

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Folders")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.primary)
                    .accessibilityAddTraits(.isHeader)
                if !sortedWorks.isEmpty {
                    Text(sortedWorks.count.formatted())
                        .font(.subheadline)
                        .foregroundStyle(.secondaryInk)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }

            if sortedWorks.isEmpty {
                if isLoadingAO3 {
                    ProgressView("Loading folders…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .accentFill()
                } else {
                    emptyFoldersCard
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sortedWorks.enumerated()), id: \.element.id) { index, item in
                        folderRow(item)
                        if index < sortedWorks.count - 1 {
                            SubjectRowSeparator(inset: 66)
                        }
                    }
                }
                .subjectPanel()
            }
        }
    }

    private var emptyFoldersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No folders yet")
                .font(.headline)
                .foregroundStyle(Color.primary)
            Text("Each work gets its own folder on this \(ThisDevice.name) for chapters and story notes.")
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink {
                LocalChapterEditorScreen(store: store)
            } label: {
                Label("New Document", systemImage: "square.and.pencil")
            }
            .buttonStyle(.kudosPrimary)
            .accessibilityLabel("New Document")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .subjectPanel()
    }

    private func folderRow(_ item: StudioWorkItem) -> some View {
        let badges = item.folderBadges
        let meta = item.folderMetaLine()
        let badgeSummary = badges.map { $0.title(deviceName: ThisDevice.name) }.joined(separator: ", ")
        let accessibilityText = badgeSummary.isEmpty
            ? "\(item.title), \(meta)"
            : "\(item.title), \(meta), \(badgeSummary)"

        return NavigationLink {
            StudioWorkFilesView(
                work: item,
                store: store,
                onChanged: onChanged,
                onAO3Write: onAO3Write
            )
        } label: {
            HStack(spacing: 12) {
                folderIconTile(for: item)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                        .fixedSize(horizontal: false, vertical: true)

                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(meta)
                                .font(.caption)
                                .foregroundStyle(.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                            if !badges.isEmpty {
                                FlowLayout(spacing: 6, rowSpacing: 4) {
                                    ForEach(badges, id: \.self) { badge in
                                        StudioFolderBadgePill(badge: badge)
                                    }
                                }
                            }
                        }
                    } else {
                        FlowLayout(spacing: 6, rowSpacing: 4) {
                            Text(meta)
                                .font(.caption)
                                .foregroundStyle(.secondaryInk)
                            ForEach(badges, id: \.self) { badge in
                                StudioFolderBadgePill(badge: badge)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondaryInk)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private func folderIconTile(for item: StudioWorkItem) -> some View {
        let iconName = item.isLooseDraft ? "doc.text" : "folder"
        let tintColor: Color = if item.hasPostedBadge {
            theme.appTheme.statusSuccessColor
        } else if item.hasAO3DraftBadge {
            .orange
        } else {
            theme.accentInk
        }

        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(tintColor.opacity(theme.appTheme.isDarkFamily ? 0.22 : 0.14))
            .frame(width: 40, height: 32)
            .overlay {
                Image(systemName: iconName)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(tintColor)
            }
            .accessibilityHidden(true)
    }

    // MARK: - Recently Deleted

    private var recentlyDeletedRow: some View {
        let subtitle = if deletedCount == 0 {
            "Empty · kept for 30 days"
        } else {
            "\(deletedCount) \(deletedCount == 1 ? "document" : "documents") · kept for 30 days"
        }
        return NavigationLink {
            StudioFilesRecentlyDeletedView(store: store, onChanged: onChanged)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "trash")
                    .font(.body)
                    .foregroundStyle(.secondaryInk)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recently Deleted")
                        .font(.body)
                        .foregroundStyle(Color.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondaryInk)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 54)
            .subjectPanel()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recently Deleted, \(subtitle)")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Storage Footer

    private var storageFooterCard: some View {
        let device = ThisDevice.name
        let legendBadges: [StudioFolderBadge] = [.onDevice, .ao3Draft, .posted]
        return VStack(alignment: .leading, spacing: 10) {
            Text(storageSummary.summaryText(deviceName: device))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Local manuscripts and story notes stay on this \(device).")
                .font(.caption)
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 10, rowSpacing: 6) {
                ForEach(legendBadges, id: \.self) { badge in
                    HStack(spacing: 5) {
                        StudioFolderBadgePill(badge: badge)
                        Text(badge.legendDescription(deviceName: device))
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                    }
                    .combinedAccessibilityRow(
                        "\(badge.title(deviceName: device)): \(badge.legendDescription(deviceName: device))"
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .subjectPanel()
    }

    // MARK: - File Import Handler

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case let .failure(error):
            importError = UserFacingError.message(for: error)
        case let .success(urls):
            guard let url = urls.first else { return }
            isImportingDocument = true
            Task {
                defer { isImportingDocument = false }
                do {
                    let imported = try await StudioDocumentImporter.importFile(at: url, into: store)
                    onChanged()
                    onOpenImported(imported)
                } catch {
                    importError = UserFacingError.message(for: error)
                }
            }
        }
    }
}

/// Shared status pill for `Studio-Files` folder rows and legend.
struct StudioFolderBadgePill: View {
    let badge: StudioFolderBadge

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        let text = badge.title(deviceName: ThisDevice.name)
        switch badge {
        case .posted:
            SubjectStateBadge(title: text, color: theme.appTheme.statusSuccessColor)
        case .ao3Draft:
            SubjectStateBadge(title: text, color: .orange)
        case .onDevice:
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondaryInk)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(theme.appTheme.glassFill(0.12), in: Capsule())
                .accessibilityLabel(text)
        }
    }
}
