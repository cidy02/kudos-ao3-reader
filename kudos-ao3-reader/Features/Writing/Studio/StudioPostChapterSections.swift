import SwiftUI

// MARK: - Chapter details, actions, bindings & submission (`Studio-Post-Chapter`)

extension StudioPostChapterSheet {
    var chapterDetailsPanel: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Chapter title")
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                TextField(
                    "Optional",
                    text: chapterTitleBinding,
                    prompt: appTheme.sepiaPrompt("Optional")
                )
                .font(.body)
                .foregroundStyle(Color.primary)
                .accessibilityLabel("Chapter title")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            SubjectRowSeparator()

            noteInputBlock(
                label: "Notes at the beginning",
                placeholder: "Add notes shown before the chapter",
                text: beginNotesBinding
            )

            SubjectRowSeparator()

            if showingEndNotesField {
                noteInputBlock(
                    label: "Notes at the end",
                    placeholder: "Add notes shown after the chapter",
                    text: endNotesBinding
                )
            } else {
                Button {
                    showingEndNotesField = true
                } label: {
                    HStack(spacing: 10) {
                        Text("Notes at the end")
                            .font(.body)
                            .foregroundStyle(Color.primary)
                        Spacer(minLength: 8)
                        Text("Add")
                            .font(.subheadline)
                            .foregroundStyle(.secondaryInk)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add notes at the end")
            }

            SubjectRowSeparator()

            publicationDateBlock

            if showingChapterCountEditor {
                SubjectRowSeparator()
                chapterCountEditorBlock
            }
        }
        .subjectPanel()
    }

    private func noteInputBlock(
        label: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        let status = CharacterLimitStatus.evaluate(text: text.wrappedValue, field: .notes)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                Spacer(minLength: 8)
                if status.severity != .normal {
                    Text(status.counterText)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(status.severity == .exceeded ? appTheme.errorColor : warningAmber)
                }
            }
            TextField(
                placeholder,
                text: text,
                prompt: appTheme.sepiaPrompt(placeholder),
                axis: .vertical
            )
            .font(.subheadline)
            .foregroundStyle(Color.primary)
            .lineLimit(2 ... 8)
            .accessibilityLabel(label)
            if let overMessage = status.overLimitMessage {
                Text(overMessage)
                    .font(.caption)
                    .foregroundStyle(appTheme.errorColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var publicationDateBlock: some View {
        let hasCustomDate = !(chapterForm?.publishedYear.isEmpty ?? true)
        let dateLabel = (hasCustomDate ? currentPublicationDate.map { WorkStat.displayDate($0) } : nil) ?? "Today"

        return VStack(spacing: 0) {
            Button {
                showingPublicationDateEditor.toggle()
            } label: {
                HStack(spacing: 10) {
                    Text("Publication date")
                        .font(.body)
                        .foregroundStyle(Color.primary)
                    Spacer(minLength: 8)
                    Text(dateLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondaryInk)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Publication date, \(dateLabel)")

            if showingPublicationDateEditor {
                SubjectRowSeparator()
                SubjectFormRow(label: "Set a different publication date", arrangement: .control) {
                    Toggle("Set a different publication date", isOn: customPublicationDateToggle)
                        .labelsHidden()
                        .accentFill()
                }
                if hasCustomDate {
                    SubjectRowSeparator()
                    SubjectFormRow(label: "Date", arrangement: .control) {
                        DatePicker(
                            "Publication date",
                            selection: publicationDateBinding,
                            in: AO3PublicationDate.allowedRange,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accentFill()
                    }
                }
            }
        }
    }

    private var chapterCountEditorBlock: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Planned chapters", arrangement: .control) {
                HStack(spacing: 6) {
                    Text("\(resolvedPosition) of")
                        .foregroundStyle(.secondaryInk)
                    TextField("?", text: wipLengthBinding)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 64)
                        .disabled(isLastChapter)
                        .accessibilityLabel("Planned chapter total")
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "This is the last chapter", arrangement: .control) {
                Toggle("This is the last chapter", isOn: $isLastChapter)
                    .labelsHidden()
                    .accentFill()
                    .onChange(of: isLastChapter) { _, last in
                        if last {
                            chapterForm?.wipLength = String(resolvedPosition)
                        }
                    }
            }
        }
    }

    func ambiguousOutcomeBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(appTheme.errorColor)
                .fixedSize(horizontal: false, vertical: true)
            Button("Close") { dismiss() }
                .buttonStyle(.kudosSecondary)
                .accessibilityLabel("Close")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .subjectPanel()
    }

    var actionButtonsSection: some View {
        let canPost = StudioPostChapterChecker.canPost(checks: checks)
            && !isSubmitting
            && !isPreviewing
            && ambiguousOutcomeMessage == nil

        return VStack(spacing: 10) {
            if chapterSavedTotalRetryPending {
                Button {
                    Task { await retryTotalUpdate() }
                } label: {
                    Text("Retry Updating Work Total")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.kudosPrimaryConfirm)
                .disabled(isSubmitting)
                .accessibilityLabel("Retry updating the work chapter total on AO3")

                Text("The chapter was saved on AO3. Only the work's planned chapter total will be retried.")
                    .font(.caption)
                    .foregroundStyle(.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button {
                    showingPostConfirmation = true
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting { ProgressView().tint(ThemeManager.label(on: theme.effectiveTint)) }
                        Text(postButtonTitle)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.kudosPrimaryConfirm)
                .disabled(!canPost)
                .accessibilityLabel(postButtonTitle)

                secondaryActionButtons

                Text(
                    "An AO3 draft is deleted by AO3 \(DraftExpiry.noticeOffsetDays) days after it is created. "
                        + "Kudos keeps its own copy either way."
                )
                .font(.caption)
                .foregroundStyle(.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
            }
        }
    }

    @ViewBuilder
    private var secondaryActionButtons: some View {
        let saveDraftButton = Button {
            Task { await submit(.saveDraft) }
        } label: {
            Text("Save as AO3 Draft")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.kudosSecondary)
        .disabled(isSubmitting || isPreviewing || ambiguousOutcomeMessage != nil)
        .accessibilityLabel("Save as AO3 Draft")

        let keepLocalButton = Button {
            syncEditsBackToEditor()
            dismiss()
        } label: {
            Text("Keep on \(ThisDevice.name)")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.kudosSecondary)
        .disabled(isSubmitting || isPreviewing)
        .accessibilityLabel("Keep on \(ThisDevice.name)")

        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                saveDraftButton
                keepLocalButton
            }
        } else {
            HStack(spacing: 10) {
                saveDraftButton
                keepLocalButton
            }
        }
    }

    // MARK: - Bindings

    private var chapterTitleBinding: Binding<String> {
        Binding(
            get: { chapterForm?.title ?? chapterTitle },
            set: { chapterForm?.title = $0 }
        )
    }

    private var beginNotesBinding: Binding<String> {
        Binding(
            get: { chapterForm?.notes ?? notesBefore },
            set: { chapterForm?.notes = $0 }
        )
    }

    private var endNotesBinding: Binding<String> {
        Binding(
            get: { chapterForm?.endnotes ?? notesAfter },
            set: { chapterForm?.endnotes = $0 }
        )
    }

    private var wipLengthBinding: Binding<String> {
        Binding(
            get: { chapterForm?.wipLength ?? "" },
            set: { chapterForm?.wipLength = $0 }
        )
    }

    private var currentPublicationDate: Date? {
        guard let chapterForm else { return nil }
        return AO3PublicationDate.date(
            year: chapterForm.publishedYear,
            month: chapterForm.publishedMonth,
            day: chapterForm.publishedDay
        )
    }

    private var customPublicationDateToggle: Binding<Bool> {
        Binding(
            get: { !(chapterForm?.publishedYear.isEmpty ?? true) },
            set: { enabled in
                if enabled {
                    let fields = AO3PublicationDate.fields(for: Date())
                    chapterForm?.publishedYear = fields.year
                    chapterForm?.publishedMonth = fields.month
                    chapterForm?.publishedDay = fields.day
                } else {
                    chapterForm?.publishedYear = ""
                    chapterForm?.publishedMonth = ""
                    chapterForm?.publishedDay = ""
                }
            }
        )
    }

    private var publicationDateBinding: Binding<Date> {
        Binding(
            get: { currentPublicationDate ?? Date() },
            set: { date in
                let fields = AO3PublicationDate.fields(for: date)
                chapterForm?.publishedYear = fields.year
                chapterForm?.publishedMonth = fields.month
                chapterForm?.publishedDay = fields.day
            }
        )
    }

    // MARK: - Load, preview, submit

    func loadForms() async {
        isLoading = true
        loadError = nil
        let generation = auth.sessionGeneration
        do {
            var loadedChapter = try await auth.loadChapterForm(workID: workID, chapterID: chapterID)
            let loadedWork = try? await auth.loadWorkForm(workID: workID)
            guard !Task.isCancelled, generation == auth.sessionGeneration else { return }

            loadedChapter = StudioPostWorkTemplate.overlayChapterDraft(
                chapterTitle: chapterTitle,
                summary: summary,
                notesBefore: notesBefore,
                notesAfter: notesAfter,
                content: content,
                onto: loadedChapter
            )
            if loadedChapter.wipLength.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let workTotal = loadedWork?.chapterTotal,
               !workTotal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                loadedChapter.wipLength = workTotal
            }

            editingGeneration = generation
            chapterForm = loadedChapter
            workForm = loadedWork
            showingEndNotesField = !loadedChapter.endnotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            showingPublicationDateEditor = !loadedChapter.publishedYear.isEmpty
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
            loadError = UserFacingError.message(for: error)
            isLoading = false
        }
    }

    func reloadWorkFormOnly() async {
        let generation = auth.sessionGeneration
        if let fresh = try? await auth.loadWorkForm(workID: workID),
           !Task.isCancelled,
           generation == auth.sessionGeneration {
            workForm = fresh
        }
    }

    func syncEditsBackToEditor() {
        guard let chapterForm else { return }
        if chapterTitle != chapterForm.title { chapterTitle = chapterForm.title }
        if notesBefore != chapterForm.notes { notesBefore = chapterForm.notes }
        if notesAfter != chapterForm.endnotes { notesAfter = chapterForm.endnotes }
    }

    func openPreview() {
        guard let currentForm = chapterForm,
              !isSubmitting,
              !isPreviewing,
              ambiguousOutcomeMessage == nil
        else { return }
        guard editingGeneration == auth.sessionGeneration else {
            errorMessage = "Your AO3 session changed. Reopen this sheet before previewing."
            return
        }
        isPreviewing = true
        let authService = auth
        let expectedGen = editingGeneration
        Task {
            defer { isPreviewing = false }
            do {
                let page = try await AO3RequestCoordinator.shared.withSlot {
                    guard expectedGen == authService.sessionGeneration else {
                        throw AO3WorkWriteError.notSignedIn
                    }
                    return try await authService.previewChapter(currentForm)
                }
                chapterForm = try currentForm.adopting(page)
                preview = page
            } catch {
                // A preview that AO3 may have saved as a draft, without telling us
                // which one, must not be posted again — that creates a second chapter.
                if AO3WriteOutcomeClassifier.mayHaveGoneThrough(error) {
                    ambiguousOutcomeMessage = StudioPostChapterSubmissionFlow.mayHaveGoneThroughMessage
                } else {
                    errorMessage = UserFacingError.message(for: error)
                }
            }
        }
    }

    func postFromPreview() async throws {
        await submit(.post)
        if let errorMessage {
            throw AO3WorkWriteError.rejected(errorMessage)
        }
        if let ambiguousOutcomeMessage {
            throw AO3WorkWriteError.rejected(ambiguousOutcomeMessage)
        }
    }

    func submit(_ action: StudioPostChapterSubmissionFlow.Action) async {
        guard let currentForm = chapterForm,
              let expectedGen = editingGeneration,
              !isSubmitting,
              !isPreviewing,
              ambiguousOutcomeMessage == nil
        else { return }
        isSubmitting = true

        let targetTotal: Int? = if isLastChapter {
            resolvedPosition
        } else {
            StudioPostChapterChecker.positiveInt(currentForm.wipLength)
        }
        let authService = auth

        let outcome = await StudioPostChapterSubmissionFlow.run(
            action: action,
            chapterForm: currentForm,
            workForm: workForm,
            checks: checks,
            newWorkTotal: targetTotal,
            expectedGeneration: expectedGen,
            currentGeneration: { authService.sessionGeneration },
            createChapter: { form, submit in
                try await AO3RequestCoordinator.shared.withSlot {
                    guard expectedGen == authService.sessionGeneration else {
                        throw AO3WorkWriteError.notSignedIn
                    }
                    return try await authService.createChapter(form, submit: submit)
                }
            },
            updateChapter: { form, submit in
                try await AO3RequestCoordinator.shared.withSlot {
                    guard expectedGen == authService.sessionGeneration else {
                        throw AO3WorkWriteError.notSignedIn
                    }
                    return try await authService.updateChapter(form, submit: submit)
                }
            },
            updateWorkTotals: { workID, total in
                try await AO3RequestCoordinator.shared.withSlot {
                    guard expectedGen == authService.sessionGeneration else {
                        throw AO3WorkWriteError.notSignedIn
                    }
                    return try await authService.updateWorkTotals(workID: workID, posted: nil, total: total)
                }
            }
        )

        handleSubmissionOutcome(outcome, targetTotal: targetTotal)
        // Leave the lock set after success so a tap during dismiss cannot post
        // twice. Clear it otherwise: Close lives in the scroll this flag disables,
        // and the banner already blocks another post.
        if case .succeeded = outcome {
            return
        }
        isSubmitting = false
    }

    private func handleSubmissionOutcome(
        _ outcome: StudioPostChapterSubmissionFlow.Outcome,
        targetTotal: Int?
    ) {
        syncEditsBackToEditor()
        switch outcome {
        case let .succeeded(_, isDraft):
            StudioAO3LoadCache.shared.clear()
            preview = nil
            onCompleted(isDraft)
            dismiss()
        case let .savedChapterButTotalFailed(message):
            StudioAO3LoadCache.shared.clear()
            chapterSavedTotalRetryPending = true
            pendingTotalToRetry = targetTotal
            errorMessage = message
        case let .blockedByChecks(reason):
            errorMessage = reason
        case .sessionChanged:
            errorMessage = "Your AO3 session changed. Reopen this sheet before posting."
        case let .mayHaveGoneThrough(message):
            ambiguousOutcomeMessage = message
        case let .failed(message):
            errorMessage = message
        }
    }

    private func retryTotalUpdate() async {
        guard let total = pendingTotalToRetry,
              let expectedGen = editingGeneration,
              !isSubmitting
        else { return }
        guard expectedGen == auth.sessionGeneration else {
            errorMessage = "Your AO3 session changed. Reopen Work Details to update the chapter total."
            return
        }
        isSubmitting = true
        let authService = auth
        do {
            _ = try await AO3RequestCoordinator.shared.withSlot {
                guard expectedGen == authService.sessionGeneration else {
                    throw AO3WorkWriteError.notSignedIn
                }
                return try await authService.updateWorkTotals(workID: workID, posted: nil, total: total)
            }
            StudioAO3LoadCache.shared.clear()
            onCompleted(false)
            dismiss()
        } catch {
            isSubmitting = false
            errorMessage = "The work total still couldn't be updated. " + UserFacingError.message(for: error)
        }
    }
}
