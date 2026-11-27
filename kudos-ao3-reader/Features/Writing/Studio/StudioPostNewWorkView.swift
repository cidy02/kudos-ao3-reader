import SwiftUI

/// Streamlined sheet for posting a new work or unposted draft (`Studio-Post-New-Work.dc.html`),
/// opened from `ChapterEditorScreen`'s `••• → Post` for a chapter not yet posted on AO3.
///
/// Reuses `AO3AuthService.loadNewWorkForm`, `loadWorkForm`, `saveWork`, `previewWork`,
/// `WritingTagsEditor`, `WritingTextEditor`, `WorkCreatorsPickerView`, `WorkSeriesPickerView`,
/// `WorkCollectionsGiftsView`, `WorkParentWorkPickerView`, and `WritingPreviewView`.
struct StudioPostNewWorkSheet: View {
    let existingDraftWorkID: Int?
    let workTitle: String
    @Binding var chapterTitle: String
    @Binding var summary: String
    @Binding var notesBefore: String
    @Binding var notesAfter: String
    @Binding var content: String
    var template: StudioPostWorkTemplate?
    var onCompleted: (_ isDraft: Bool) -> Void = { _ in }

    @Environment(\.dismiss) var dismiss
    @Environment(AO3AuthService.self) var auth
    @Environment(ThemeManager.self) var theme
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    @State var form: AO3WorkForm?
    @State var editingGeneration: Int?
    @State var startedFromBanner: String?
    @State var isLoading = true
    @State var loadError: String?
    @State var reloadToken = 0

    @State var showingChaptersEditor = false
    @State var showingCommentSettings = false
    @State var showingPublicationDate = false

    @State var isSubmitting = false
    @State var isPreviewing = false
    @State var preview: AO3PreviewHTML?
    @State var showingPostConfirmation = false
    @State var errorMessage: String?
    @State var ambiguousOutcomeMessage: String?

    var appTheme: ReaderTheme { theme.appTheme }

    var warningAmber: Color {
        appTheme.isDarkFamily ? .subjectAmber : Color(red: 0.698, green: 0.369, blue: 0.0)
    }

    var warningPillFill: Color {
        appTheme.isDarkFamily ? Color.subjectAmber.opacity(0.20) : Color(red: 1.0, green: 0.957, blue: 0.898)
    }

    var warningPillInk: Color {
        appTheme.isDarkFamily ? .subjectAmber : Color(red: 0.420, green: 0.227, blue: 0.0)
    }

    var recoveryTarget: String {
        form?.workID.map { "work:\($0)" } ?? "work:new"
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Preparing new work form…")
                        .accentFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError, form == nil {
                    loadErrorView(loadError)
                } else if let currentForm = form {
                    formContent(currentForm)
                }
            }
            .background(appTheme.contentBackdrop.ignoresSafeArea())
            .navigationTitle("Post a New Work")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { sheetToolbar }
            .navigationDestination(isPresented: Binding(
                get: { preview != nil },
                set: { if !$0 { preview = nil } }
            )) {
                previewDestination
            }
            .task(id: "\(auth.sessionGeneration):\(reloadToken)") {
                await loadForm()
            }
            .alert("Post this work?", isPresented: $showingPostConfirmation) {
                Button("Post Work") {
                    Task { await submit(.post) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(WorkEditView.postConfirmationMessage(missing: form?.missingRequiredFields() ?? []))
            }
            .alert(
                "AO3 could not save the work",
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
        .interactiveDismissDisabled(isSubmitting || isPreviewing)
        .presentationDragIndicator(.visible)
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 680)
        #endif
    }

    @ToolbarContentBuilder
    private var sheetToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", role: .cancel) { dismiss() }
                .disabled(isSubmitting || isPreviewing)
                .accessibilityLabel("Cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Preview") { openPreview() }
                .disabled(
                    form == nil || isLoading || isSubmitting || isPreviewing
                        || ambiguousOutcomeMessage != nil
                )
                .accessibilityLabel("Preview work on AO3")
        }
    }

    @ViewBuilder
    private var previewDestination: some View {
        if let preview, let currentForm = form {
            WritingPreviewView(
                preview: preview,
                subtitle: WorkEditView.subtitle(for: currentForm),
                postTitle: "Post Work",
                confirmation: (
                    "Post this work?",
                    WorkEditView.postConfirmationMessage(missing: currentForm.missingRequiredFields())
                ),
                post: { try await postFromPreview() }
            )
        }
    }

    // MARK: - Main content

    private func loadErrorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't Load New Work Form", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { reloadToken += 1 }
                .buttonStyle(.kudosPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formContent(_ currentForm: AO3WorkForm) -> some View {
        let requirements = StudioNewWorkRequirements.evaluate(currentForm)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let startedFromBanner {
                    startedFromCard(startedFromBanner)
                }

                requiredSection(currentForm, requirements: requirements)
                tagsSection(currentForm)
                prefaceSection(currentForm)
                moreSection(currentForm)

                if let ambiguousOutcomeMessage {
                    ambiguousBanner(ambiguousOutcomeMessage)
                }

                actionsSection(requirements: requirements)
            }
            .padding(.horizontal, SubjectMetrics.gutter)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .environment(\.writingEditedWorkID, currentForm.workID)
        .disabled(isSubmitting || isPreviewing)
    }

    private func startedFromCard(_ text: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "doc.on.doc")
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.accentInk)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .subjectPanel()
    }

    // MARK: - Section 1: Required

    private func requiredSection(
        _ currentForm: AO3WorkForm,
        requirements: StudioNewWorkRequirements
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("REQUIRED")
                    .font(.caption.weight(.semibold))
                    .tracking(0.5)
                    .foregroundStyle(.secondaryInk)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let remainingText = requirements.remainingBadgeText {
                    Text(remainingText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(warningPillInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(warningPillFill, in: Capsule())
                        .accessibilityLabel("\(remainingText) required")
                } else {
                    Text("Ready")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(appTheme.statusSuccessColor)
                        .accessibilityLabel("All required fields complete")
                }
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(requirements.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { SubjectRowSeparator(inset: 46) }
                    requiredRow(item, form: currentForm)
                }
            }
            .subjectPanel()
        }
    }

    @ViewBuilder
    private func requiredRow(
        _ item: StudioNewWorkRequiredItem,
        form currentForm: AO3WorkForm
    ) -> some View {
        switch item.kind {
        case .title:
            NavigationLink {
                StudioWorkTitleEditorView(title: formBinding(\.title, fallback: ""))
            } label: {
                requiredRowLabel(item)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.label), \(item.value)")

        case .rating:
            Menu {
                Picker("Rating", selection: formBinding(\.rating, fallback: "")) {
                    if !currentForm.ratingOptions.contains(where: { $0.value == currentForm.rating }) {
                        Text(item.value).tag(currentForm.rating)
                    }
                    ForEach(currentForm.ratingOptions) { option in
                        Text(option.title).tag(option.value)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                requiredRowLabel(item)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rating")
            .accessibilityValue(item.value)

        case .warnings:
            NavigationLink {
                WritingTagsEditor(
                    title: "Archive Warnings",
                    values: formBinding(\.warnings, fallback: []),
                    options: currentForm.warningOptions,
                    kind: nil
                )
            } label: {
                requiredRowLabel(item)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Archive Warnings, \(item.value)")

        case .fandom:
            NavigationLink {
                WritingTagsEditor(
                    title: "Fandoms",
                    values: formBinding(\.fandoms, fallback: []),
                    options: [],
                    kind: .fandom
                )
            } label: {
                requiredRowLabel(item)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fandom, \(item.value)")

        case .language:
            Menu {
                Picker("Language", selection: formBinding(\.languageID, fallback: "")) {
                    if !currentForm.languageOptions.contains(where: { $0.value == currentForm.languageID }) {
                        Text(item.value).tag(currentForm.languageID)
                    }
                    ForEach(currentForm.languageOptions) { option in
                        Text(option.title).tag(option.value)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                requiredRowLabel(item)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Language")
            .accessibilityValue(item.value)

        case .text:
            NavigationLink {
                WritingTextEditor(
                    text: chapterContentBinding,
                    title: "Work Text",
                    account: auth.username ?? "",
                    target: recoveryTarget,
                    field: "content"
                )
            } label: {
                requiredRowLabel(item)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Text, \(item.value)")
        }
    }

    private func requiredRowLabel(_ item: StudioNewWorkRequiredItem) -> some View {
        let valueStyle: AnyShapeStyle = item.isComplete
            ? AnyShapeStyle(Color.primary)
            : AnyShapeStyle(warningAmber)

        return HStack(spacing: 12) {
            requiredStatusDot(isComplete: item.isComplete)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondaryInk)
                    Text(item.value)
                        .font(.subheadline)
                        .foregroundStyle(valueStyle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(item.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondaryInk)
                    .frame(minWidth: 84, alignment: .leading)
                Spacer(minLength: 8)
                Text(item.value)
                    .font(.subheadline)
                    .foregroundStyle(valueStyle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.trailing)
            }

            disclosureChevron
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func requiredStatusDot(isComplete: Bool) -> some View {
        if isComplete {
            Image(systemName: "checkmark")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Color.white)
                .frame(width: 20, height: 20)
                .background(appTheme.statusSuccessColor, in: Circle())
                .accessibilityHidden(true)
        } else {
            Circle()
                .strokeBorder(warningAmber, lineWidth: 2)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Section 2: Tags

    private func tagsSection(_ currentForm: AO3WorkForm) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("TAGS")

            VStack(alignment: .leading, spacing: 14) {
                tagGroupRow(label: "Categories", tags: currentForm.categories) {
                    WritingTagsEditor(
                        title: "Categories",
                        values: formBinding(\.categories, fallback: []),
                        options: currentForm.categoryOptions,
                        kind: nil
                    )
                }
                tagGroupRow(label: "Relationships", tags: currentForm.relationships) {
                    WritingTagsEditor(
                        title: "Relationships",
                        values: formBinding(\.relationships, fallback: []),
                        options: [],
                        kind: .relationship
                    )
                }
                tagGroupRow(label: "Characters", tags: currentForm.characters) {
                    WritingTagsEditor(
                        title: "Characters",
                        values: formBinding(\.characters, fallback: []),
                        options: [],
                        kind: .character
                    )
                }
                tagGroupRow(label: "Additional tags", tags: currentForm.additionalTags) {
                    WritingTagsEditor(
                        title: "Additional Tags",
                        values: formBinding(\.additionalTags, fallback: []),
                        options: [],
                        kind: .freeform
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .subjectPanel()
        }
    }

    private func tagGroupRow<Destination: View>(
        label: String,
        tags: [String],
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
            FlowLayout(spacing: 6, rowSpacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    SubjectChip(
                        text: tag,
                        style: .neutral,
                        palette: theme.scopePalette,
                        horizontalPadding: 10,
                        verticalPadding: 4
                    )
                }
                NavigationLink {
                    destination()
                } label: {
                    SubjectChip(
                        text: "Add",
                        style: .dashed,
                        systemImage: "plus",
                        palette: theme.scopePalette,
                        fontWeight: .semibold,
                        horizontalPadding: 10,
                        verticalPadding: 4
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(label)")
            }
        }
    }
}
