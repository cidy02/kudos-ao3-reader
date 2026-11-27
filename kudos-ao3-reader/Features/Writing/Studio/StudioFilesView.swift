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
            VStack(alignment: .leading, spacing: 12) {
                importDocumentCard
                importURLRow
            }
            foldersSection
            recentlyDeletedRow
                .padding(.top, -8)
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Folders")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.primary)
                .accessibilityAddTraits(.isHeader)

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
                    ForEach(sortedWorks) { item in
                        folderRow(item)
                        SubjectRowSeparator(inset: 0)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Folders")
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

                VStack(alignment: .leading, spacing: 2) {
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
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
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
        let tileFill: Color = item.isLooseDraft
            ? StudioTonePalette.draftAmberFill(for: theme.appTheme)
            : StudioTonePalette.workFolderFill(for: theme.appTheme)
        let iconInk: Color = item.isLooseDraft
            ? StudioTonePalette.draftAmberInk(for: theme.appTheme)
            : StudioTonePalette.workFolderInk(for: theme.appTheme)

        return RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(tileFill)
            .frame(width: 40, height: 32)
            .overlay {
                Image(systemName: iconName)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(iconInk)
            }
            .accessibilityHidden(true)
    }

    // MARK: - Recently Deleted

    private var recentlyDeletedRow: some View {
        let subtitle = StudioRecentlyDeletedHelper.rowSubtitle(count: deletedCount)
        return NavigationLink {
            StudioFilesRecentlyDeletedView(store: store, onChanged: onChanged)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "trash")
                    .font(.body)
                    .foregroundStyle(.secondaryInk)
                    .frame(width: 24)
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
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 8)
            .frame(minHeight: 52)
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
        let leadText = Text(storageSummary.summaryText(deviceName: device))
            .fontWeight(.semibold)
            .foregroundStyle(Color.primary)
        let noteText = Text(" Local manuscripts and story notes stay on this \(device).")
            .foregroundStyle(.secondaryInk)
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(leadText)\(noteText)")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 10, rowSpacing: 6) {
                ForEach(legendBadges, id: \.self) { badge in
                    HStack(spacing: 4) {
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
        .subjectPanel(cornerRadius: 14)
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

    var body: some View {
        let text = badge.title(deviceName: ThisDevice.name)
        switch badge {
        case .posted:
            StudioStatusPill(text: text, tone: .posted)
        case .ao3Draft:
            StudioStatusPill(text: text, tone: .draft)
        case .onDevice:
            StudioStatusPill(text: text, tone: .onDevice)
        }
    }
}
