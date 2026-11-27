import SwiftUI

/// Loads an AO3 work's edit form and presents `StudioWorkDetailsView`
/// (`Studio-Work-Details.dc.html`), keeping the loaded form across child pushes
/// (same `sessionGeneration` guard as `WritingWorkDestination`).
struct StudioWorkDetailsDestination: View {
    let workID: Int
    let workTitle: String
    let subtitleText: String?
    let onChanged: () -> Void

    @Environment(AO3AuthService.self) private var auth

    @State private var form: AO3WorkForm?
    @State private var loadedGeneration: Int?
    @State private var errorMessage: String?
    @State private var retry = 0

    init(
        workID: Int,
        workTitle: String = "",
        subtitleText: String? = nil,
        onChanged: @escaping () -> Void = {}
    ) {
        self.workID = workID
        self.workTitle = workTitle
        self.subtitleText = subtitleText
        self.onChanged = onChanged
    }

    var body: some View {
        Group {
            if let form, loadedGeneration == auth.sessionGeneration {
                StudioWorkDetailsView(
                    form: form,
                    subtitleText: subtitleText,
                    onChanged: onChanged
                )
                .id(auth.sessionGeneration)
            } else {
                WritingLoaderPage(title: "Work Details", message: errorMessage) {
                    retry += 1
                }
            }
        }
        .hidesFloatingTabBarInEditor()
        .task(id: "\(auth.sessionGeneration):\(retry)") {
            // Keep an already-loaded form across Back returns from pushed sub-editors
            // (tags, creators, series, collections, notes) so unsaved edits aren't wiped.
            if form != nil, loadedGeneration == auth.sessionGeneration { return }
            form = nil
            errorMessage = nil
            let generation = auth.sessionGeneration
            do {
                let loaded = try await auth.loadWorkForm(workID: workID)
                guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
                loadedGeneration = generation
                form = loaded
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }
}

/// Work Details screen in AO3's own edit-page order (`Studio-Work-Details.dc.html`):
/// About → Tags → Creators (Invite / Remove Me) → Connections → Who can see and comment →
/// Give up or delete (`OrphanSheet` and existing delete flow).
///
/// Reuses `AO3AuthService.saveWork`, `loadWorkForm`, `removeMeAsCoCreator`,
/// `loadDeleteImplications`, `deleteWork`, `deleteDraft`, `WorkCoCreatorRemovalFlow`,
/// `OrphanSheet`, `WritingTagsDestination`, `WorkCreatorsPickerView`, `WorkSeriesPickerView`,
/// `WorkCollectionsGiftsView`, `WorkParentWorkPickerView`, and `WritingTextEditor`.
struct StudioWorkDetailsView: View {
    let subtitleText: String?
    let onChanged: () -> Void

    @Environment(\.dismiss) var dismiss
    @Environment(ThemeManager.self) var theme
    @Environment(AO3AuthService.self) var auth
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    @State var form: AO3WorkForm
    @State var editingGeneration: Int?
    @State var isSaving = false
    /// Set when a write may already have reached AO3. Write actions stay disabled;
    /// the form itself stays scrollable so the writer's edits are not trapped.
    @State var ao3WriteUnconfirmed = false
    @State var isRemovingCoCreator = false
    @State var isCheckingDelete = false
    @State var errorMessage: String?

    @State var showRemoveMeConfirmation = false
    @State var showingOrphan = false
    @State var didOrphan = false
    @State var showOrphanedNotice = false
    @State var deleteImplications: AO3DeleteImplications?
    @State var showDeleteConfirmation = false

    /// Refreshes tags after `WritingTagsDestination` saves directly to AO3 so tapping
    /// Save here never writes stale tag fields back over the edit.
    @State var needsTagRefresh = false
    @State var tagRetry = 0

    init(
        form: AO3WorkForm,
        subtitleText: String? = nil,
        onChanged: @escaping () -> Void = {}
    ) {
        self.subtitleText = subtitleText
        self.onChanged = onChanged
        _form = State(initialValue: form)
    }

    var appTheme: ReaderTheme { theme.appTheme }
    var gutter: CGFloat { SubjectMetrics.accountGutter }
    var recoveryTarget: String { form.workID.map { "work:\($0)" } ?? "work:new" }

    var resolvedSubtitle: String {
        if let subtitleText, !subtitleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return subtitleText
        }
        return StudioWorkDetailsModel.defaultSubtitle(for: form)
    }

    var detailsModel: StudioWorkDetailsModel {
        StudioWorkDetailsModel.build(form: form, username: auth.username)
    }

    var isBusy: Bool {
        isSaving || isRemovingCoCreator || isCheckingDelete
    }

    var body: some View {
        scrollContent
            .environment(\.writingEditedWorkID, form.workID)
            .disabled(isBusy)
            .onAppear {
                if editingGeneration == nil {
                    editingGeneration = auth.sessionGeneration
                }
            }
            .subjectScreenWash(title: "Work Details", palette: theme.scopePalette)
            .wrappingInlineTitle("Work Details", isActive: dynamicTypeSize.isAccessibilitySize)
            .hidesFloatingTabBarInEditor()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        saveChanges()
                    }
                    .sheetConfirmStyle()
                    .disabled(isBusy || needsTagRefresh || ao3WriteUnconfirmed)
                    .accessibilityLabel("Save work details to AO3")
                }
            }
            .task(id: "\(needsTagRefresh):\(tagRetry)") {
                await reloadTagsIfNeeded()
            }
            .alert(
                "AO3 could not save the change",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .confirmationDialog(
                "Remove yourself as co-creator?",
                isPresented: $showRemoveMeConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove Me as Co-Creator", role: .destructive) {
                    removeMeAsCoCreator()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("AO3 removes you from every chapter of this work as well.")
            }
            .confirmationDialog(
                form.isDraft ? "Delete this draft?" : "Delete this work?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(form.isDraft ? "Delete" : "Delete on AO3", role: .destructive) {
                    deleteWork()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let implications = deleteImplications {
                    Text(implications.cautionText)
                }
            }
            .sheet(
                isPresented: $showingOrphan,
                onDismiss: {
                    guard didOrphan else { return }
                    didOrphan = false
                    showOrphanedNotice = true
                }
            ) {
                if let workID = form.workID {
                    OrphanSheet(
                        target: .work(workID),
                        fallbackTitles: [form.title]
                    ) { _ in
                        StudioAO3LoadCache.shared.clear()
                        onChanged()
                        didOrphan = true
                    }
                }
            }
            .alert("Orphaned.", isPresented: $showOrphanedNotice) {
                Button("OK") { dismiss() }
            }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(resolvedSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                ForEach(detailsModel.sections) { section in
                    sectionBlock(section)
                }
            }
            .padding(.horizontal, gutter)
            .padding(.top, 8)
            .padding(.bottom, 36)
        }
    }

    // MARK: - Section rendering

    private func sectionBlock(_ section: StudioWorkDetailsSectionDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(section.title.uppercased())
                    .font(.caption)
                    .tracking(0.3)
                    .foregroundStyle(.secondaryInk)
                    .accessibilityAddTraits(.isHeader)
                if section.id == .tags, needsTagRefresh {
                    Spacer(minLength: 8)
                    Button("Reload Tags") { tagRetry += 1 }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.accentInk)
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reload tags from AO3")
                }
            }
            .padding(.horizontal, 14)

            VStack(spacing: 0) {
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { SubjectRowSeparator() }
                    rowView(for: row)
                }
            }
            .subjectPanel()

            if let footer = section.footer, !footer.isEmpty {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
            }
        }
    }

    @ViewBuilder
    private func rowView(for row: StudioWorkDetailsRowDescriptor) -> some View {
        switch row.id {
        case .title, .summary, .notes, .language, .editTags:
            aboutOrTagRow(row)
        case .creatorPseud, .inviteCoCreator, .removeMeAsCoCreator,
             .series, .collections, .giftFor, .inspiredBy:
            creatorOrConnectionRow(row)
        case .whoCanSee, .whoCanComment, .approveComments, .orphanWork, .deleteWork:
            privacyOrDangerRow(row)
        }
    }

    @ViewBuilder
    private func aboutOrTagRow(_ row: StudioWorkDetailsRowDescriptor) -> some View {
        switch row.id {
        case .title:
            NavigationLink {
                StudioWorkTitleEditorView(title: $form.title)
            } label: {
                standardRowLabel(row)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rowAccessibilityLabel(row))

        case .summary:
            NavigationLink {
                WritingTextEditor(
                    text: $form.summary,
                    title: "Summary",
                    account: auth.username ?? "",
                    target: recoveryTarget,
                    field: "summary"
                )
            } label: {
                standardRowLabel(row)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rowAccessibilityLabel(row))

        case .notes:
            NavigationLink {
                StudioWorkNotesEditorView(
                    notes: $form.notes,
                    endnotes: $form.endnotes,
                    target: recoveryTarget
                )
            } label: {
                standardRowLabel(row)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rowAccessibilityLabel(row))

        case .language:
            Menu {
                Picker("Language", selection: $form.languageID) {
                    if !form.languageOptions.contains(where: { $0.value == form.languageID }) {
                        Text(row.value ?? "Not set").tag(form.languageID)
                    }
                    ForEach(form.languageOptions) { option in
                        Text(option.title).tag(option.value)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                standardRowLabel(row)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Language")
            .accessibilityValue(row.value ?? "")

        case .editTags:
            NavigationLink {
                if form.isPosted, let workID = form.workID {
                    WritingTagsDestination(workID: workID, workTitle: form.title) {
                        StudioAO3LoadCache.shared.clear()
                        needsTagRefresh = true
                        onChanged()
                    }
                } else {
                    StudioDraftTagsEditorView(form: $form)
                }
            } label: {
                standardRowLabel(row)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rowAccessibilityLabel(row))

        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func creatorOrConnectionRow(_ row: StudioWorkDetailsRowDescriptor) -> some View {
        switch row.id {
        case .creatorPseud, .inviteCoCreator:
            NavigationLink {
                WorkCreatorsPickerView(creators: $form.creators, workTitle: form.title)
            } label: {
                standardRowLabel(row)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rowAccessibilityLabel(row))

        case .removeMeAsCoCreator:
            Button(role: .destructive) {
                showRemoveMeConfirmation = true
            } label: {
                standardRowLabel(row)
            }
            .buttonStyle(.plain)
            .disabled(isBusy || ao3WriteUnconfirmed)
            .accessibilityLabel("Remove Me as Co-Creator")

        case .series:
            NavigationLink {
                WorkSeriesPickerView(
                    series: $form.series,
                    newSeriesTitle: $form.newSeriesTitle,
                    workTitle: form.title,
                    currentSeries: form.currentSeries
                )
            } label: {
                standardRowLabel(row)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rowAccessibilityLabel(row))

        case .collections, .giftFor:
            NavigationLink {
                WorkCollectionsGiftsView(
                    collections: $form.collections,
                    gifts: $form.gifts,
                    workTitle: form.title,
                    parentWorkCount: form.parentWork.url.isEmpty ? 0 : 1
                )
            } label: {
                standardRowLabel(row)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rowAccessibilityLabel(row))

        case .inspiredBy:
            NavigationLink {
                WorkParentWorkPickerView(
                    parentWork: $form.parentWork,
                    languageOptions: form.languageOptions
                )
            } label: {
                standardRowLabel(row)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(rowAccessibilityLabel(row))

        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func privacyOrDangerRow(_ row: StudioWorkDetailsRowDescriptor) -> some View {
        switch row.id {
        case .whoCanSee:
            Menu {
                Button {
                    form.restricted = false
                } label: {
                    Label("Everyone", systemImage: !form.restricted ? "checkmark" : "globe")
                }
                Button {
                    form.restricted = true
                } label: {
                    Label("Registered users only", systemImage: form.restricted ? "checkmark" : "lock")
                }
            } label: {
                standardRowLabel(row)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Who can see it")
            .accessibilityValue(row.value ?? "")

        case .whoCanComment:
            Menu {
                Picker("Who can comment", selection: $form.commentPermissions) {
                    if !form.commentPermissionOptions.contains(where: { $0.value == form.commentPermissions }) {
                        Text(row.value ?? "Registered users").tag(form.commentPermissions)
                    }
                    ForEach(form.commentPermissionOptions) { option in
                        Text(option.title).tag(option.value)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                standardRowLabel(row)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Who can comment")
            .accessibilityValue(row.value ?? "")

        case .approveComments:
            approveCommentsRow(row)

        case .orphanWork:
            Button(role: .destructive) {
                showingOrphan = true
            } label: {
                standardRowLabel(row)
            }
            .buttonStyle(.plain)
            .disabled(isBusy || ao3WriteUnconfirmed)
            .accessibilityLabel("Orphan Work")

        case .deleteWork:
            Button(role: .destructive) {
                confirmDelete()
            } label: {
                standardRowLabel(row)
            }
            .buttonStyle(.plain)
            .disabled(isBusy || ao3WriteUnconfirmed)
            .accessibilityLabel(row.label)

        default:
            EmptyView()
        }
    }
}
