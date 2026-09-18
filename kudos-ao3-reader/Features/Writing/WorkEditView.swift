import SwiftUI
import SwiftData

struct WorkEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @Environment(AO3AuthService.self) private var auth

    @State private var form: AO3WorkForm
    @State private var editingGeneration: Int?
    @State private var isSaving = false
    @State private var isPosting = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var deleteImplications: AO3DeleteImplications?
    @State private var isCheckingDelete = false
    @State private var needsPublicationRefresh = false
    @State private var publicationRetry = 0
    /// Set when the pushed Edit tags screen saves. That screen writes tags to
    /// AO3 on its own, and this form's Save posts every tag string it holds —
    /// so keeping the pre-edit tags would silently undo the tag edit on the
    /// next Save. Same shape as `needsPublicationRefresh` for Add chapter: only
    /// the tag fields are refreshed, every other unsaved edit is kept, and Save
    /// waits until the refresh lands.
    @State private var needsTagRefresh = false
    @State private var tagRetry = 0

    init(form: AO3WorkForm) {
        self._form = State(initialValue: form)
    }

    private var accountPalette: SubjectPalette {
        theme.scopePalette
    }

    private var gutter: CGFloat { SubjectMetrics.accountGutter }
    private var selfGuttered: CGFloat { 0 }

    var body: some View {
        List {
            Section {
                SubjectHeaderBlock(
                    kicker: "AO3 Account",
                    title: form.kind == .new ? "New work" : "Edit work",
                    subtitle: form.title.isEmpty ? "Untitled" : form.title,
                    palette: accountPalette,
                    gutter: gutter
                )
                .pageBodyRow(top: 20, gutter: selfGuttered)
            }

            Section {
                // The bottom padding is the 8pt a `.pageBodyRow(top: 8)` card
                // below gets; segment rows sit flush and cannot carry it.
                SectionRuleHeader(title: "Required")
                    .padding(.bottom, 8)
                    .pageBodyRow(top: 18, gutter: selfGuttered)
            }
            Section { requiredRows }

            Section {
                SectionRuleHeader(title: "Tags")
                    .padding(.bottom, 8)
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                if needsTagRefresh {
                    Button("Reload tags") { tagRetry += 1 }
                        .pageBodyRow(top: 4, gutter: gutter)
                }
            }
            Section {
                tagsRows
                Text("Tags can also be edited separately from the work text.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Association")
                    .padding(.bottom, 8)
                    .pageBodyRow(top: 18, gutter: selfGuttered)
            }
            Section { associationRows }

            Section {
                SectionRuleHeader(title: "Text")
                    .padding(.bottom, 8)
                    .pageBodyRow(top: 18, gutter: selfGuttered)
            }
            Section { textRows }

            Section {
                SectionRuleHeader(title: "Publication")
                    .padding(.bottom, 8)
                    .pageBodyRow(top: 18, gutter: selfGuttered)
            }
            Section {
                // Rows only, no links — converted so the screen keeps one card
                // style rather than because this card could misfire.
                Group { publicationRows }.disabled(needsPublicationRefresh)
                if needsPublicationRefresh {
                    Button("Reload chapter totals") { publicationRetry += 1 }
                        .pageBodyRow(top: 8, gutter: gutter)
                }
                Text("Chapters posted of total is AO3’s own field — setting a total above what is "
                    + "posted is what marks a work in progress, and Complete writes the same value.")

                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .pageBodyRow(top: 8, gutter: gutter)
            }

            if form.workID != nil {
                Section {
                    SectionRuleHeader(title: "Delete")
                        .pageBodyRow(top: 18, gutter: selfGuttered)
                    deletePanel.pageBodyRow(top: 8, gutter: gutter)
                }
            }
        }
        .cardList()
        .disabled(isSaving || isPosting)
        .onAppear { if editingGeneration == nil { editingGeneration = auth.sessionGeneration } }
        #if os(macOS)
        .navigationTitle(form.kind == .new ? "New work" : "Edit work")
        #endif
        .subjectScreenWash(palette: accountPalette)
        .task(id: "\(needsPublicationRefresh):\(publicationRetry)") {
            guard needsPublicationRefresh, let workID = form.workID else { return }
            let generation = auth.sessionGeneration
            do {
                let fresh = try await auth.loadWorkForm(workID: workID)
                guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
                form.chapterTotal = fresh.chapterTotal
                form.chaptersPosted = fresh.chaptersPosted
                form.isChaptered = fresh.isChaptered
                needsPublicationRefresh = false
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "Reload chapter totals before saving this work. " + error.localizedDescription
            }
        }
        .task(id: "\(needsTagRefresh):\(tagRetry)") {
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
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "Reload tags before saving this work. " + error.localizedDescription
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save(submit: form.isPosted ? .update : .saveDraft)
                }
                .disabled(isSaving || isPosting || needsPublicationRefresh || needsTagRefresh)
            }
            if !form.isPosted {
                ToolbarItem(placement: .primaryAction) {
                    Button("Post") {
                        save(submit: .postWithoutPreview)
                    }
                    .disabled(isSaving || isPosting)
                }
            }
        }
        .alert("AO3 could not save the change", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .confirmationDialog(
            "Delete Work?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete work on AO3", role: .destructive) {
                deleteWork()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let imp = deleteImplications {
                Text(imp.cautionText)
            }
        }
    }

    /// One `List` row per field, drawn as segments of one card. These were a
    /// `VStack` in a single row, and a `List` row fires EVERY navigation link
    /// inside it: tapping Fandoms pushed Archive warnings and Fandoms both, and
    /// tapping Relationships landed on Additional tags (measured on the
    /// simulator). A row holding one link fires only that one.
    @ViewBuilder
    private var requiredRows: some View {
        SubjectFormRow(label: "Title", arrangement: .control) {
            TextField("Title", text: $form.title).multilineTextAlignment(.trailing)
        }
        .panelSegment(0, of: 5, gutter: gutter)
        WritingChoiceRow(title: "Rating", value: $form.rating, options: form.ratingOptions)
            .panelSegment(1, of: 5, gutter: gutter)
        WritingTagsRow(title: "Archive warnings", values: $form.warnings, options: form.warningOptions)
            .panelSegment(2, of: 5, gutter: gutter)
        WritingTagsRow(title: "Fandoms", values: $form.fandoms, kind: .fandom)
            .panelSegment(3, of: 5, gutter: gutter)
        WritingChoiceRow(title: "Language", value: $form.languageID, options: form.languageOptions)
            .panelSegment(4, of: 5, gutter: gutter)
    }

    /// See `requiredRows` — four links in one row pushed the wrong screen.
    @ViewBuilder
    private var tagsRows: some View {
        WritingTagsRow(title: "Categories", values: $form.categories, options: form.categoryOptions)
            .panelSegment(0, of: 4, gutter: gutter)
        WritingTagsRow(title: "Relationships", values: $form.relationships, kind: .relationship)
            .panelSegment(1, of: 4, gutter: gutter)
        WritingTagsRow(title: "Characters", values: $form.characters, kind: .character)
            .panelSegment(2, of: 4, gutter: gutter)
        WritingTagsRow(title: "Additional tags", values: $form.additionalTags, kind: .freeform)
            .panelSegment(3, of: 4, gutter: gutter)
    }

    /// 1bw's pushes, one `List` row each. They were one `VStack` row, and a
    /// `List` row fires every `NavigationLink` inside it — tapping Series would
    /// have pushed all five pickers. See `requiredRows`.
    @ViewBuilder
    private var associationRows: some View {
        // These three rows drew a chevron and opened nothing until 1bw; the form
        // already carries every option they need, so the pickers edit what it
        // will post back rather than fetching anything.
        SubjectFormRow(label: "Series", value: seriesValue, showsDisclosure: true)
            .subjectRowNavigation(accessibilityLabel: "Series") {
                WorkSeriesPickerView(series: $form.series, workTitle: form.title)
            }
            .panelSegment(0, of: 5, gutter: gutter)
        SubjectFormRow(label: "Add to collections", value: collectionsValue, showsDisclosure: true)
            .subjectRowNavigation(accessibilityLabel: "Add to collections") {
                collectionsAndGifts
            }
            .panelSegment(1, of: 5, gutter: gutter)
        SubjectFormRow(
            label: "Gift recipients",
            value: form.gifts.isEmpty ? "None" : "\(form.gifts.count)",
            showsDisclosure: true
        )
        .subjectRowNavigation(accessibilityLabel: "Gift recipients") {
            collectionsAndGifts
        }
        .panelSegment(2, of: 5, gutter: gutter)
        SubjectFormRow(label: "Co-creators", value: creatorsValue, showsDisclosure: true)
            .subjectRowNavigation(accessibilityLabel: "Co-creators") {
                WorkCreatorsPickerView(creators: $form.creators, workTitle: form.title)
            }
            .panelSegment(3, of: 5, gutter: gutter)
        SubjectFormRow(
            label: "Inspired by",
            value: form.parentWork.url.isEmpty ? "None" : "1",
            showsDisclosure: true
        )
        .subjectRowNavigation(accessibilityLabel: "Inspired by") {
            WorkParentWorkPickerView(
                parentWork: $form.parentWork,
                languageOptions: form.languageOptions
            )
        }
        .panelSegment(4, of: 5, gutter: gutter)
    }

    /// One screen behind two rows — 1bw draws collections and gifts together,
    /// because both are "who else this work belongs to" and both post on the same
    /// save.
    private var collectionsAndGifts: some View {
        WorkCollectionsGiftsView(
            collections: $form.collections,
            gifts: $form.gifts,
            workTitle: form.title,
            parentWorkCount: form.parentWork.url.isEmpty ? 0 : 1
        )
    }

    /// Selected, not offered: the form carries every collection AO3 offers this
    /// work, so counting the array would read "None" as a number of choices
    /// rather than of memberships.
    private var collectionsValue: String {
        let count = form.collections.filter(\.isSelected).count
        return count == 0 ? "None" : "\(count)"
    }

    private var creatorsValue: String {
        let pseuds = form.creators.selectedPseudIDs.count
        let invited = form.creators.coauthorByline.isEmpty ? 0 : 1
        if pseuds == 0 && invited == 0 { return "None" }
        if invited == 0 { return "\(pseuds)" }
        return "\(pseuds) + 1 invited"
    }

    /// "No skin" is a real choice, and it needs a name. AO3's select DOES carry
    /// a blank entry — otwarchive's `_standard_form` builds it with
    /// `collection_select ... include_blank: true`, an `<option value="">` with
    /// no text — so the old note here ("has no blank entry") was wrong, the
    /// prepend never ran, and the row showed no value at all (seen on the
    /// simulator). The blank entry is named; a list without one gets one.
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

    private var seriesValue: String {
        let count = form.series.filter(\.isSelected).count
        return count == 0 ? "None" : "\(count)"
    }

    private var recoveryTarget: String { form.workID.map { "work:\($0)" } ?? "work:new" }

    /// One `List` row per editor — see `associationRows`. The rows are
    /// conditional (Work text only before posting; Add chapter and Edit tags
    /// only after), so the segment positions are counted, not fixed.
    @ViewBuilder
    private var textRows: some View {
        let showsWorkText = form.kind == .new || form.isDraft
        let postedWorkID: Int? = form.isPosted ? form.workID : nil
        let count = 4 + (showsWorkText ? 1 : 0) + (postedWorkID == nil ? 0 : 2)
        let afterNotes = showsWorkText ? 4 : 3
        WritingTextEditorRow(title: "Summary", text: $form.summary, target: recoveryTarget, field: "summary")
            .panelSegment(0, of: count, gutter: gutter)
        WritingTextEditorRow(title: "Beginning notes", text: $form.notes, target: recoveryTarget, field: "notes")
            .panelSegment(1, of: count, gutter: gutter)
        WritingTextEditorRow(title: "End notes", text: $form.endnotes, target: recoveryTarget, field: "endnotes")
            .panelSegment(2, of: count, gutter: gutter)
        if showsWorkText {
            WritingTextEditorRow(title: "Work text", text: Binding(
                get: { form.chapter?.content ?? "" },
                set: { value in
                    if form.chapter == nil { form.chapter = AO3WorkChapterDraft() }
                    form.chapter?.content = value
                }
            ), target: recoveryTarget, field: "content")
            .panelSegment(3, of: count, gutter: gutter)
        }
        if let workID = postedWorkID {
            SubjectFormRow(label: "Add chapter", value: "", showsDisclosure: true)
                .subjectRowNavigation(accessibilityLabel: "Add chapter") {
                    WritingChapterDestination(workID: workID, workTitle: form.title) {
                        needsPublicationRefresh = true
                    }
                }
                .panelSegment(afterNotes, of: count, gutter: gutter)
            // 1bp's own page, reachable at last. Gated exactly like Add chapter
            // rather than on `workID` alone: AO3 keeps `/works/<id>/edit_tags`
            // for a work that exists publicly, and a draft's tags are already
            // editable in the form above this row.
            SubjectFormRow(label: "Edit tags", value: "", showsDisclosure: true)
                .subjectRowNavigation(accessibilityLabel: "Edit tags") {
                    WritingTagsDestination(workID: workID) { needsTagRefresh = true }
                }
                .panelSegment(afterNotes + 1, of: count, gutter: gutter)
        }
        WritingChoiceRow(
            title: "Work skin",
            value: $form.workSkinID,
            options: defaultFirst(form.workSkinOptions, label: "Default")
        )
        .panelSegment(count - 1, of: count, gutter: gutter)
    }

    /// Segments, for one card style across the screen. The toggles are titled
    /// even though the titles are hidden: `labelsHidden` hides a title from the
    /// eye, not from VoiceOver, and these four announced as a bare "switch".
    @ViewBuilder
    private var publicationRows: some View {
        // 1bo: "setting a total above what is posted is what marks a work in
        // progress". The posted count is AO3's to report, the total is the
        // writer's to set — so only one half of this row is editable.
        SubjectFormRow(label: "Chapters posted", arrangement: .control) {
            HStack(spacing: 6) {
                Text("\(form.chaptersPosted ?? 1) of")
                    .foregroundStyle(.secondary)
                TextField("?", text: $form.chapterTotal)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 64)
                    #if os(iOS)
                        .keyboardType(.numberPad)
                    #endif
            }
        }
        .panelSegment(0, of: 6, gutter: gutter)
        SubjectFormRow(label: "Work is complete", arrangement: .control) {
            Toggle("Work is complete", isOn: Binding(
                get: { form.chapterTotal == "\(form.chaptersPosted ?? 1)" },
                set: { form.chapterTotal = $0 ? "\(form.chaptersPosted ?? 1)" : "" }
            ))
            .labelsHidden()
        }
        .panelSegment(1, of: 6, gutter: gutter)
        SubjectFormRow(label: "Set a different publication date", arrangement: .control) {
            Toggle("Set a different publication date", isOn: $form.backdate)
                .labelsHidden()
        }
        .panelSegment(2, of: 6, gutter: gutter)
        SubjectFormRow(label: "Only show to registered users", arrangement: .control) {
            Toggle("Only show to registered users", isOn: $form.restricted)
                .labelsHidden()
        }
        .panelSegment(3, of: 6, gutter: gutter)
        SubjectFormRow(label: "Enable comment moderation", arrangement: .control) {
            Toggle("Enable comment moderation", isOn: $form.moderatedCommenting)
                .labelsHidden()
        }
        .panelSegment(4, of: 6, gutter: gutter)
        WritingChoiceRow(
            title: "Who can comment",
            value: $form.commentPermissions,
            options: form.commentPermissionOptions
        )
        .panelSegment(5, of: 6, gutter: gutter)
    }

    private var deletePanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Delete work on AO3", value: "", isDestructive: true) {
                Task {
                    guard let workID = form.workID else { return }
                    isCheckingDelete = true
                    do {
                        deleteImplications = try await auth.loadDeleteImplications(workID: workID)
                        showDeleteConfirmation = true
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    isCheckingDelete = false
                }
            }
        }
        .subjectPanel()
    }

    private func save(submit: AO3WorkSubmitAction) {
        guard !isSaving && !isPosting && !needsPublicationRefresh && !needsTagRefresh else { return }
        guard editingGeneration == auth.sessionGeneration else {
            errorMessage = "Your AO3 session changed. Reopen this form before saving."
            return
        }
        let isPost = submit == .post || submit == .postWithoutPreview
        if isPost { isPosting = true } else { isSaving = true }

        Task {
            do {
                guard editingGeneration == auth.sessionGeneration else { throw AO3WorkWriteError.notSignedIn }
                try await auth.saveWork(form, submit: submit)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                if isPost { isPosting = false } else { isSaving = false }
            }
        }
    }

    private func deleteWork() {
        guard let workID = form.workID else { return }
        Task {
            do {
                guard editingGeneration == auth.sessionGeneration else { throw AO3WorkWriteError.notSignedIn }
                if form.isDraft {
                    try await auth.deleteDraft(workID: workID)
                } else {
                    try await auth.deleteWork(workID: workID)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
