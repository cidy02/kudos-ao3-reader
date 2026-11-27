import SwiftUI

// MARK: - Preface, More, Actions, Bindings & Submission (`Studio-Post-New-Work`)

extension StudioPostNewWorkSheet {
    // MARK: - Section 3: Preface

    func prefaceSection(_ currentForm: AO3WorkForm) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("PREFACE")

            VStack(spacing: 0) {
                summaryBlock(currentForm)
                SubjectRowSeparator()

                NavigationLink {
                    WorkCreatorsPickerView(
                        creators: formBinding(\.creators, fallback: AO3CreatorDraft()),
                        workTitle: currentForm.title
                    )
                } label: {
                    valueDisclosureRow(label: "Creators", value: creatorsSummary(for: currentForm))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Creators, \(creatorsSummary(for: currentForm))")

                SubjectRowSeparator()

                NavigationLink {
                    StudioWorkNotesEditorView(
                        notes: formBinding(\.notes, fallback: ""),
                        endnotes: formBinding(\.endnotes, fallback: ""),
                        target: recoveryTarget
                    )
                } label: {
                    valueDisclosureRow(
                        label: "Notes",
                        value: StudioWorkDetailsModel.notesValue(
                            notes: currentForm.notes,
                            endnotes: currentForm.endnotes
                        )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Notes")

                SubjectRowSeparator()

                chaptersBlock(currentForm)
            }
            .subjectPanel()
        }
    }

    private func summaryBlock(_ currentForm: AO3WorkForm) -> some View {
        let summaryStatus = CharacterLimitStatus.evaluate(text: currentForm.summary, field: .summary)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Summary")
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                Spacer(minLength: 8)
                if summaryStatus.severity != .normal {
                    Text(summaryStatus.counterText)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(
                            summaryStatus.severity == .exceeded ? appTheme.errorColor : warningAmber
                        )
                }
            }
            TextField(
                "Add a summary",
                text: formBinding(\.summary, fallback: ""),
                prompt: appTheme.sepiaPrompt("Add a summary"),
                axis: .vertical
            )
            .font(.subheadline)
            .foregroundStyle(Color.primary)
            .lineLimit(2 ... 8)
            .accessibilityLabel("Summary")
            if let over = summaryStatus.overLimitMessage {
                Text(over)
                    .font(.caption)
                    .foregroundStyle(appTheme.errorColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private func chaptersBlock(_ currentForm: AO3WorkForm) -> some View {
        Button {
            showingChaptersEditor.toggle()
        } label: {
            valueDisclosureRow(label: "Chapters", value: chaptersSummary(for: currentForm))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chapters, \(chaptersSummary(for: currentForm))")

        if showingChaptersEditor {
            SubjectRowSeparator()
            SubjectFormRow(label: "This work has multiple chapters", arrangement: .control) {
                Toggle("This work has multiple chapters", isOn: formBinding(\.isChaptered, fallback: false))
                    .labelsHidden()
                    .accentFill()
            }
            if currentForm.isChaptered {
                SubjectRowSeparator()
                SubjectFormRow(label: "Expected total", arrangement: .control) {
                    HStack(spacing: 6) {
                        Text("1 of")
                            .foregroundStyle(.secondaryInk)
                        TextField("?", text: formBinding(\.chapterTotal, fallback: ""))
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 64)
                            .accessibilityLabel("Expected chapter total")
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                }
                SubjectRowSeparator()
                SubjectFormRow(label: "Chapter 1 title", arrangement: .control) {
                    TextField("Optional", text: chapterTitleBinding)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel("Chapter 1 title")
                }
            }
        }
    }

    // MARK: - Section 4: More

    func moreSection(_ currentForm: AO3WorkForm) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("MORE")

            VStack(spacing: 0) {
                moreAssociationsRows(currentForm)
                SubjectRowSeparator()
                moreSettingsRows(currentForm)
            }
            .subjectPanel()
        }
    }

    @ViewBuilder
    private func moreAssociationsRows(_ currentForm: AO3WorkForm) -> some View {
        NavigationLink {
            WorkSeriesPickerView(
                series: formBinding(\.series, fallback: []),
                newSeriesTitle: formBinding(\.newSeriesTitle, fallback: ""),
                workTitle: currentForm.title,
                currentSeries: currentForm.currentSeries
            )
        } label: {
            valueDisclosureRow(label: "Series", value: StudioWorkDetailsModel.seriesValue(for: currentForm))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Series, \(StudioWorkDetailsModel.seriesValue(for: currentForm))")

        SubjectRowSeparator()

        NavigationLink {
            WorkCollectionsGiftsView(
                collections: formBinding(\.collections, fallback: []),
                gifts: formBinding(\.gifts, fallback: []),
                workTitle: currentForm.title,
                parentWorkCount: currentForm.parentWork.url.isEmpty ? 0 : 1
            )
        } label: {
            valueDisclosureRow(
                label: "Collections & challenges",
                subtitle: "Also fulfils an assignment or a claim",
                value: StudioWorkDetailsModel.collectionsValue(for: currentForm)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Collections and challenges, \(StudioWorkDetailsModel.collectionsValue(for: currentForm))"
        )

        SubjectRowSeparator()

        NavigationLink {
            WorkCollectionsGiftsView(
                collections: formBinding(\.collections, fallback: []),
                gifts: formBinding(\.gifts, fallback: []),
                workTitle: currentForm.title,
                parentWorkCount: currentForm.parentWork.url.isEmpty ? 0 : 1
            )
        } label: {
            let giftsText = currentForm.gifts.isEmpty
                ? "Nobody"
                : StudioWorkDetailsModel.giftsValue(for: currentForm)
            valueDisclosureRow(label: "Gift to", value: giftsText)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Gift to")

        SubjectRowSeparator()

        NavigationLink {
            WorkParentWorkPickerView(
                parentWork: formBinding(\.parentWork, fallback: AO3ParentWorkDraft()),
                languageOptions: currentForm.languageOptions
            )
        } label: {
            valueDisclosureRow(
                label: "Inspired by",
                subtitle: "Another work, or a translation of one",
                value: StudioWorkDetailsModel.inspiredByValue(for: currentForm)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Inspired by, \(StudioWorkDetailsModel.inspiredByValue(for: currentForm))")
    }

    @ViewBuilder
    private func moreSettingsRows(_ currentForm: AO3WorkForm) -> some View {
        let skinOptions = defaultFirst(currentForm.workSkinOptions, label: "Basic Formatting")
        let currentSkinTitle = skinOptions.first { $0.value == currentForm.workSkinID }?.title
            ?? "Basic Formatting"
        let pubDateText = (currentForm.backdate ? currentPublicationDate.map { WorkStat.displayDate($0) } : nil)
            ?? "Today"

        Menu {
            Button {
                form?.restricted = false
            } label: {
                Label("Everyone", systemImage: !currentForm.restricted ? "checkmark" : "globe")
            }
            Button {
                form?.restricted = true
            } label: {
                Label("Registered users only", systemImage: currentForm.restricted ? "checkmark" : "lock")
            }
        } label: {
            valueDisclosureRow(
                label: "Who can see it",
                value: currentForm.restricted ? "Registered users" : "Everyone"
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Who can see it")
        .accessibilityValue(currentForm.restricted ? "Registered users" : "Everyone")

        SubjectRowSeparator()

        Button {
            showingCommentSettings.toggle()
        } label: {
            valueDisclosureRow(
                label: "Who can comment",
                subtitle: currentForm.moderatedCommenting ? "Moderation on" : "Moderation off",
                value: StudioWorkDetailsModel.commentPermissionTitle(for: currentForm)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Who can comment")

        if showingCommentSettings {
            SubjectRowSeparator()
            WritingChoiceRow(
                title: "Comment permissions",
                value: formBinding(\.commentPermissions, fallback: ""),
                options: currentForm.commentPermissionOptions
            )
            SubjectRowSeparator()
            SubjectFormRow(label: "Enable comment moderation", arrangement: .control) {
                Toggle("Enable comment moderation", isOn: formBinding(\.moderatedCommenting, fallback: false))
                    .labelsHidden()
                    .accentFill()
            }
        }

        SubjectRowSeparator()

        Button {
            showingPublicationDate.toggle()
        } label: {
            valueDisclosureRow(label: "Publication date", value: pubDateText)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Publication date, \(pubDateText)")

        if showingPublicationDate {
            SubjectRowSeparator()
            SubjectFormRow(label: "Set a different publication date", arrangement: .control) {
                Toggle("Set a different publication date", isOn: backdateBinding)
                    .labelsHidden()
                    .accentFill()
            }
            if currentForm.backdate {
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

        SubjectRowSeparator()

        Menu {
            Picker("Work skin", selection: formBinding(\.workSkinID, fallback: "")) {
                ForEach(skinOptions) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            valueDisclosureRow(label: "Work skin", value: currentSkinTitle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Work skin")
        .accessibilityValue(currentSkinTitle)
    }

    // MARK: - Actions & shared row chrome

    func ambiguousBanner(_ message: String) -> some View {
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

    func actionsSection(requirements: StudioNewWorkRequirements) -> some View {
        let canPost = requirements.canPost
            && !isSubmitting
            && !isPreviewing
            && ambiguousOutcomeMessage == nil

        return VStack(spacing: 10) {
            Button {
                showingPostConfirmation = true
            } label: {
                HStack(spacing: 8) {
                    if isSubmitting { ProgressView().tint(ThemeManager.label(on: theme.effectiveTint)) }
                    Text(requirements.postButtonTitle)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.kudosPrimaryConfirm)
            .disabled(!canPost)
            .accessibilityLabel(requirements.postButtonTitle)

            Button {
                Task { await submit(.saveDraft) }
            } label: {
                Text("Save as AO3 Draft")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.kudosSecondary)
            .disabled(isSubmitting || isPreviewing || ambiguousOutcomeMessage != nil)
            .accessibilityLabel("Save as AO3 Draft")

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

    func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .tracking(0.5)
            .foregroundStyle(.secondaryInk)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }

    func valueDisclosureRow(
        label: String,
        subtitle: String? = nil,
        value: String
    ) -> some View {
        HStack(spacing: 10) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.body)
                        .foregroundStyle(Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.body)
                        .foregroundStyle(Color.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondaryInk)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }

            disclosureChevron
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }

    var disclosureChevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .accessibilityHidden(true)
    }

    // MARK: - Derived strings & bindings

    private func creatorsSummary(for currentForm: AO3WorkForm) -> String {
        let selected = Set(currentForm.creators.selectedPseudIDs)
        let titles = currentForm.creators.availablePseuds
            .filter { selected.contains($0.value) }
            .map(\.title)
        let base = titles.isEmpty ? (auth.username ?? "Default") : titles.joined(separator: ", ")
        let invited = currentForm.creators.coauthorByline.trimmingCharacters(in: .whitespacesAndNewlines)
        return invited.isEmpty ? base : "\(base) + \(invited)"
    }

    private func chaptersSummary(for currentForm: AO3WorkForm) -> String {
        guard currentForm.isChaptered else { return "1 of 1" }
        let total = currentForm.chapterTotal.trimmingCharacters(in: .whitespacesAndNewlines)
        return total.isEmpty ? "1 of ?" : "1 of \(total)"
    }

    private func defaultFirst(_ options: [AO3FormOption], label: String) -> [AO3FormOption] {
        guard let blank = options.firstIndex(where: { $0.value.isEmpty }) else {
            return [AO3FormOption(value: "", title: label)] + options
        }
        var named = options
        if named[blank].title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            named[blank].title = label
        }
        return named
    }

    func formBinding<Value>(
        _ keyPath: WritableKeyPath<AO3WorkForm, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: { form?[keyPath: keyPath] ?? fallback },
            set: { form?[keyPath: keyPath] = $0 }
        )
    }

    var chapterContentBinding: Binding<String> {
        Binding(
            get: { form?.chapter?.content ?? content },
            set: { newValue in
                if form?.chapter == nil { form?.chapter = AO3WorkChapterDraft() }
                form?.chapter?.content = newValue
            }
        )
    }

    private var chapterTitleBinding: Binding<String> {
        Binding(
            get: { form?.chapter?.title ?? "" },
            set: { newValue in
                if form?.chapter == nil { form?.chapter = AO3WorkChapterDraft() }
                form?.chapter?.title = newValue
            }
        )
    }

    private var currentPublicationDate: Date? {
        form?.chapter.flatMap {
            AO3PublicationDate.date(
                year: $0.publishedYear,
                month: $0.publishedMonth,
                day: $0.publishedDay
            )
        }
    }

    private var backdateBinding: Binding<Bool> {
        Binding(
            get: { form?.backdate ?? false },
            set: { enabled in
                form?.backdate = enabled
                if enabled {
                    if form?.chapter == nil { form?.chapter = AO3WorkChapterDraft() }
                    if form?.chapter?.publishedYear.isEmpty == true {
                        let fields = AO3PublicationDate.fields(for: Date())
                        form?.chapter?.publishedYear = fields.year
                        form?.chapter?.publishedMonth = fields.month
                        form?.chapter?.publishedDay = fields.day
                    }
                }
            }
        )
    }

    private var publicationDateBinding: Binding<Date> {
        Binding(
            get: { currentPublicationDate ?? Date() },
            set: { date in
                if form?.chapter == nil { form?.chapter = AO3WorkChapterDraft() }
                let fields = AO3PublicationDate.fields(for: date)
                form?.chapter?.publishedYear = fields.year
                form?.chapter?.publishedMonth = fields.month
                form?.chapter?.publishedDay = fields.day
            }
        )
    }

    // MARK: - Load, preview, submit

    func loadForm() async {
        isLoading = true
        loadError = nil
        let generation = auth.sessionGeneration
        do {
            var loaded: AO3WorkForm
            if let existingDraftWorkID {
                loaded = try await auth.loadWorkForm(workID: existingDraftWorkID)
            } else {
                loaded = try await auth.loadNewWorkForm()
            }
            guard !Task.isCancelled, generation == auth.sessionGeneration else { return }

            var banner: String?
            if existingDraftWorkID != nil {
                let title = loaded.title.trimmingCharacters(in: .whitespacesAndNewlines)
                banner = StudioPostWorkTemplate.bannerText(
                    sourceTitle: title.isEmpty ? workTitle : title,
                    copiedLabels: []
                )
            } else if let template {
                let applied = template.applying(to: loaded)
                loaded = applied.form
                if !applied.copiedLabels.isEmpty {
                    banner = StudioPostWorkTemplate.bannerText(
                        sourceTitle: template.sourceTitle,
                        copiedLabels: applied.copiedLabels
                    )
                }
            }

            loaded = StudioPostWorkTemplate.overlayChapterDraft(
                workTitle: workTitle,
                chapterTitle: chapterTitle,
                summary: summary,
                notesBefore: notesBefore,
                notesAfter: notesAfter,
                content: content,
                onto: loaded
            )

            editingGeneration = generation
            startedFromBanner = banner
            form = loaded
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
            loadError = UserFacingError.message(for: error)
            isLoading = false
        }
    }

    private func syncEditsBackToEditor() {
        guard let currentForm = form else { return }
        if summary != currentForm.summary { summary = currentForm.summary }
        if notesBefore != currentForm.notes { notesBefore = currentForm.notes }
        if notesAfter != currentForm.endnotes { notesAfter = currentForm.endnotes }
        if let chapterText = currentForm.chapter?.content,
           currentForm.chapter?.contentServed != false,
           content != chapterText {
            content = chapterText
        }
    }

    func openPreview() {
        guard let currentForm = form, !isSubmitting, !isPreviewing else { return }
        guard editingGeneration == auth.sessionGeneration else {
            errorMessage = "Your AO3 session changed. Reopen this sheet before previewing."
            return
        }
        isPreviewing = true
        let authService = auth
        Task {
            defer { isPreviewing = false }
            do {
                let page = try await authService.previewWork(currentForm)
                form = try currentForm.adopting(page)
                preview = page
            } catch {
                errorMessage = UserFacingError.message(for: error)
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

    func submit(_ action: StudioPostNewWorkSubmissionFlow.Action) async {
        guard let currentForm = form,
              let expectedGen = editingGeneration,
              !isSubmitting,
              !isPreviewing
        else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        let authService = auth
        let outcome = await StudioPostNewWorkSubmissionFlow.run(
            action: action,
            form: currentForm,
            expectedGeneration: expectedGen,
            currentGeneration: { authService.sessionGeneration },
            saveWork: { workForm, submitAction in
                try await authService.saveWork(workForm, submit: submitAction)
            }
        )

        switch outcome {
        case let .succeeded(_, isDraft):
            syncEditsBackToEditor()
            StudioAO3LoadCache.shared.clear()
            preview = nil
            onCompleted(isDraft)
            dismiss()
        case let .missingRequired(missing):
            errorMessage = WorkEditView.postConfirmationMessage(missing: missing)
        case .sessionChanged:
            errorMessage = "Your AO3 session changed. Reopen this sheet before saving."
        case let .mayHaveGoneThrough(message):
            ambiguousOutcomeMessage = message
        case let .failed(message):
            errorMessage = message
        }
    }
}
