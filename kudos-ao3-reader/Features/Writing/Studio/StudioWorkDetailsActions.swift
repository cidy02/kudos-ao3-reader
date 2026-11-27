import SwiftUI

// MARK: - Row chrome & AO3 actions (`Studio-Work-Details`)

extension StudioWorkDetailsView {
    func approveCommentsRow(_ row: StudioWorkDetailsRowDescriptor) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text(row.label)
                        .font(.body)
                        .foregroundStyle(Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle(row.label, isOn: $form.moderatedCommenting)
                        .labelsHidden()
                        .accentFill()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 10) {
                    Text(row.label)
                        .font(.body)
                        .foregroundStyle(Color.primary)
                    Spacer(minLength: 8)
                    Toggle(row.label, isOn: $form.moderatedCommenting)
                        .labelsHidden()
                        .accentFill()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 48)
    }

    func standardRowLabel(_ row: StudioWorkDetailsRowDescriptor) -> some View {
        let titleStyle = rowTitleStyle(for: row.tone)
        return HStack(spacing: 10) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.label)
                        .font(.body)
                        .foregroundStyle(titleStyle)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle = row.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let value = row.value, !value.isEmpty {
                        Text(value)
                            .font(.subheadline)
                            .foregroundStyle(.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .font(.body)
                        .foregroundStyle(titleStyle)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle = row.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondaryInk)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let value = row.value, !value.isEmpty {
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(.secondaryInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }

            if row.showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.secondary.opacity(0.7))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }

    private func rowTitleStyle(for tone: StudioWorkDetailsRowTone) -> AnyShapeStyle {
        switch tone {
        case .standard: AnyShapeStyle(Color.primary)
        case .accent: AnyShapeStyle(theme.accentInk)
        case .destructive: AnyShapeStyle(appTheme.errorColor)
        }
    }

    func rowAccessibilityLabel(_ row: StudioWorkDetailsRowDescriptor) -> String {
        let parts: [String?] = [row.label, row.value, row.subtitle]
        return parts
            .compactMap { part in
                guard let part, !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                return part
            }
            .joined(separator: ", ")
    }

    // MARK: - Actions (reusing existing AO3WorkActions & WritingSubmissionFlows)

    func reloadTagsIfNeeded() async {
        guard needsTagRefresh, let workID = form.workID else { return }
        let generation = auth.sessionGeneration
        do {
            let fresh = try await auth.loadWorkForm(workID: workID)
            guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
            form.rating = fresh.rating
            form.warnings = fresh.warnings
            form.categories = fresh.categories
            form.fandoms = fresh.fandoms
            form.relationships = fresh.relationships
            form.characters = fresh.characters
            form.additionalTags = fresh.additionalTags
            needsTagRefresh = false
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "Reload tags before saving this work. " + UserFacingError.message(for: error)
        }
    }

    func saveChanges() {
        guard !isBusy, !needsTagRefresh else { return }
        guard editingGeneration == auth.sessionGeneration else {
            errorMessage = "Your AO3 session changed. Reopen Work Details before saving."
            return
        }
        isSaving = true
        let submitAction: AO3WorkSubmitAction = form.isPosted ? .update : .saveDraft
        Task {
            do {
                _ = try await auth.saveWork(form, submit: submitAction)
                StudioAO3LoadCache.shared.clear()
                onChanged()
                dismiss()
            } catch {
                isSaving = false
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }

    func removeMeAsCoCreator() {
        guard let workID = form.workID, !isRemovingCoCreator else { return }
        guard editingGeneration == auth.sessionGeneration else {
            errorMessage = AO3WorkWriteError.notSignedIn.localizedDescription
            return
        }
        isRemovingCoCreator = true
        Task {
            let outcome = await WorkCoCreatorRemovalFlow.run(
                kind: .work,
                remove: { try await auth.removeMeAsCoCreator(workID: workID) },
                onRemoved: {
                    StudioAO3LoadCache.shared.clear()
                    onChanged()
                    dismiss()
                }
            )
            isRemovingCoCreator = false
            switch outcome {
            case .removed:
                break
            case let .onlyCreator(message), let .failed(message):
                errorMessage = message
            }
        }
    }

    func confirmDelete() {
        guard let workID = form.workID, !isCheckingDelete else { return }
        isCheckingDelete = true
        Task {
            do {
                deleteImplications = try await auth.loadDeleteImplications(workID: workID)
                showDeleteConfirmation = true
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
            isCheckingDelete = false
        }
    }

    func deleteWork() {
        guard let workID = form.workID else { return }
        isSaving = true
        Task {
            do {
                guard editingGeneration == auth.sessionGeneration else {
                    throw AO3WorkWriteError.notSignedIn
                }
                if form.isDraft {
                    _ = try await auth.deleteDraft(workID: workID)
                } else {
                    _ = try await auth.deleteWork(workID: workID)
                }
                StudioAO3LoadCache.shared.clear()
                onChanged()
                dismiss()
            } catch {
                isSaving = false
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }
}

// MARK: - Draft tag editor (when `/works/<id>/edit_tags` isn't available yet)

struct StudioDraftTagsEditorView: View {
    @Binding var form: AO3WorkForm

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var gutter: CGFloat { SubjectMetrics.accountGutter }

    var body: some View {
        List {
            Section {
                WritingChoiceRow(
                    title: "Rating",
                    value: $form.rating,
                    options: form.ratingOptions
                )
                .panelSegment(0, of: 3, gutter: gutter)

                tagNavigationRow(title: "Archive Warnings", values: form.warnings) {
                    WritingTagsEditor(
                        title: "Archive Warnings",
                        values: $form.warnings,
                        options: form.warningOptions,
                        kind: nil
                    )
                }
                .panelSegment(1, of: 3, gutter: gutter)

                tagNavigationRow(title: "Fandoms", values: form.fandoms) {
                    WritingTagsEditor(
                        title: "Fandoms",
                        values: $form.fandoms,
                        options: [],
                        kind: .fandom
                    )
                }
                .panelSegment(2, of: 3, gutter: gutter)
            }

            Section {
                tagNavigationRow(title: "Categories", values: form.categories) {
                    WritingTagsEditor(
                        title: "Categories",
                        values: $form.categories,
                        options: form.categoryOptions,
                        kind: nil
                    )
                }
                .panelSegment(0, of: 4, gutter: gutter)

                tagNavigationRow(title: "Relationships", values: form.relationships) {
                    WritingTagsEditor(
                        title: "Relationships",
                        values: $form.relationships,
                        options: [],
                        kind: .relationship
                    )
                }
                .panelSegment(1, of: 4, gutter: gutter)

                tagNavigationRow(title: "Characters", values: form.characters) {
                    WritingTagsEditor(
                        title: "Characters",
                        values: $form.characters,
                        options: [],
                        kind: .character
                    )
                }
                .panelSegment(2, of: 4, gutter: gutter)

                tagNavigationRow(title: "Additional Tags", values: form.additionalTags) {
                    WritingTagsEditor(
                        title: "Additional Tags",
                        values: $form.additionalTags,
                        options: [],
                        kind: .freeform
                    )
                }
                .panelSegment(3, of: 4, gutter: gutter)
            }
        }
        .cardList()
        .environment(\.defaultMinListRowHeight, 0)
        .subjectScreenWash(title: "Edit Tags", palette: theme.scopePalette)
        .wrappingInlineTitle("Edit Tags", isActive: dynamicTypeSize.isAccessibilitySize)
        .hidesFloatingTabBarInEditor()
    }

    private func tagNavigationRow<Destination: View>(
        title: String,
        values: [String],
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        let summary = values.isEmpty ? "None" : values.joined(separator: ", ")
        return SubjectFormRow(label: title, value: summary, showsDisclosure: true)
            .subjectRowNavigation(accessibilityLabel: "\(title), \(summary)", destination: destination)
    }
}
