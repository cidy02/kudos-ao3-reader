import SwiftUI
import SwiftData

// swiftlint:disable file_length
struct WorkEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @Environment(AO3AuthService.self) private var auth
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .subheadline) private var actionRowTitleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var footnoteSize: CGFloat = 11.5

    @State private var form: AO3WorkForm
    @State private var editingGeneration: Int?
    @State private var isSaving = false
    @State private var isPosting = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var showPostConfirmation = false
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
    #if DEBUG
    @State private var debugPresented: DebugPresented?
    #endif
    @State private var preview: AO3PreviewHTML?
    /// Chapter 1 as AO3 last gave it to this form — what `refreshedChapter`
    /// tells an unsaved backdate apart from a date nobody touched here by.
    @State private var loadedChapter: AO3WorkChapterDraft?

    /// Called once AO3 has confirmed a save, a post or a delete, before the form closes: the list
    /// it was opened from showed the old title, or a work that no longer exists, until pulled.
    let onChanged: () -> Void

    init(form: AO3WorkForm, onChanged: @escaping () -> Void = {}) {
        self.onChanged = onChanged
        self._form = State(initialValue: form)
        self._loadedChapter = State(initialValue: form.chapter)
    }

    private var accountPalette: SubjectPalette {
        theme.scopePalette
    }

    private var gutter: CGFloat { SubjectMetrics.accountGutter }
    private var isDarkTheme: Bool { theme.appTheme == .dark || theme.appTheme == .oled }

    /// Board 42 draws no tab bar on the full-screen work editor.
    static var hidesTabBar: Bool {
        FloatingTabBarPolicy.hidesTabBar(isEditor: true)
    }

    var body: some View {
        List {
            Section {
                // The text editors checkpoint into the form and a device-local
                // recovery copy after 1.5 seconds idle or 20 seconds of typing.
                Text("Saved as you type · recovery copy on this device")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .pageBodyRow(top: 12, gutter: gutter)
                if form.isDraft {
                    footnote("This draft isn't public yet. Options that apply only after posting "
                        + "will appear once you post it.")
                }
            }

            Section { sectionHeader("Required Tags") }
            Section { requiredRows }

            Section {
                sectionHeader("Tags")
                if needsTagRefresh {
                    Button("Reload Tags") { tagRetry += 1 }
                        .pageBodyRow(top: 4, gutter: gutter)
                }
            }
            Section {
                tagsRows
                footnote("Suggestions come from AO3 as you type.")
            }

            Section { sectionHeader("Preface") }
            Section { prefaceRows }

            Section { sectionHeader("Associations") }
            Section { associationRows }

            Section { sectionHeader("Chapters and Publishing") }
            Section { chapterRows }
            Section {
                // Rows only, no links — converted so the screen keeps one card
                // style rather than because this card could misfire.
                Group { publicationRows }.disabled(needsPublicationRefresh)
                if needsPublicationRefresh {
                    Button("Reload Chapter Totals") { publicationRetry += 1 }
                        .pageBodyRow(top: 8, gutter: gutter)
                }
                if form.isPosted {
                    footnote("AO3 marks a work in progress when its total chapters are higher than the number "
                        + "posted. Complete sets both numbers to the same value.")
                }
            }

            // 1bs: an unposted work posts and deletes from its own group, and
            // the toolbar keeps only Save, as the board draws it.
            if !form.isPosted {
                Section {
                    postPanel.pageBodyRow(top: 14, gutter: gutter)
                    if form.workID != nil {
                        footnote("AO3 deletes an unposted draft 30 days after it is created.")
                    }
                }
            } else if form.workID != nil {
                Section {
                    deletePanel.pageBodyRow(top: 14, gutter: gutter)
                }
            }
        }
        .cardList()
        // Form rows at their own 11–12pt padding; the List's minimum row
        // height was holding each at ~52pt (L3-FORM-1).
        .environment(\.defaultMinListRowHeight, 0)
        .environment(\.writingEditedWorkID, form.workID)
        .disabled(isSaving || isPosting)
        .onAppear { if editingGeneration == nil { editingGeneration = auth.sessionGeneration } }
        .subjectScreenWash(title: screenTitle, palette: accountPalette)
        .wrappingInlineTitle(screenTitle, isActive: dynamicTypeSize.isAccessibilitySize)
        #if os(iOS)
        .navigationBarBackButtonHidden(true)
        #endif
        .hidesFloatingTabBarInEditor()
        .task(id: "\(needsPublicationRefresh):\(publicationRetry)") {
            guard needsPublicationRefresh, let workID = form.workID else { return }
            let generation = auth.sessionGeneration
            do {
                let fresh = try await auth.loadWorkForm(workID: workID)
                guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
                form.chapterTotal = fresh.chapterTotal
                form.chaptersPosted = fresh.chaptersPosted
                form.isChaptered = fresh.isChaptered
                // Save posts `work[chapter_attributes]` for a one-chapter work,
                // so a chapter just edited from Chapters would be put back.
                form.chapter = Self.refreshedChapter(form.chapter, loaded: loadedChapter, fresh: fresh.chapter)
                loadedChapter = fresh.chapter
                needsPublicationRefresh = false
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "Reload chapter totals before saving this work. " + UserFacingError.message(for: error)
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
                errorMessage = "Reload tags before saving this work. " + UserFacingError.message(for: error)
            }
        }
        .toolbar { headerToolbar }
        .alert("AO3 could not save the change", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        // 1bs's post confirmation. Posting is the one write here that cannot
        // be taken back, so it is asked first; when AO3 would reject the post,
        // the confirm button is replaced by the board's "Fill in what is missing".
        .alert("Post this work?", isPresented: $showPostConfirmation) {
            if form.missingRequiredFields().isEmpty {
                Button("Post Work") { save(submit: Self.postSubmit) }
            } else {
                Button("Fill in what is missing") {}
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.postConfirmationMessage(missing: form.missingRequiredFields()))
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
            if let imp = deleteImplications {
                Text(imp.cautionText)
            }
        }
        #if DEBUG
        .task {
            if editingGeneration == nil { editingGeneration = auth.sessionGeneration }
            if DebugLaunchRoute.takeSheet("writingpreview") { openPreview() }
            if let id = DebugLaunchRoute.takeFirstPush([
                "chapters", "chapterform", "edittags", "texteditor", "recovery",
                "seriespicker", "collectionsgifts", "creatorspicker", "parentpicker"
            ]) {
                debugPresented = DebugPresented(id: id)
            }
        }
        .navigationDestination(item: $debugPresented) { presented in
            debugWorkChild(presented.id)
        }
        #endif
        .navigationDestination(isPresented: Binding(
            get: { preview != nil }, set: { if !$0 { preview = nil } }
        )) {
            if let preview {
                WritingPreviewView(
                    preview: preview,
                    subtitle: Self.subtitle(for: form),
                    postTitle: form.isPosted ? "Update" : "Post Work",
                    confirmation: form.isPosted ? nil : (
                        "Post this work?", Self.postConfirmationMessage(missing: form.missingRequiredFields())
                    ),
                    post: { try await perform(submit: form.isPosted ? .update : Self.postSubmit) }
                )
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 14)
            .pageBodyRow(top: 18, gutter: gutter)
    }

    private func fieldLabel(_ title: String, isRequired: Bool = false) -> Text {
        if isRequired {
            Text("\(title) \(Text("∗").foregroundStyle(.accentInk))")
        } else {
            Text(title)
        }
    }

    private func choiceRow(
        title: String,
        value: Binding<String>,
        options: [AO3FormOption]
    ) -> some View {
        let currentTitle = options.first { $0.value == value.wrappedValue }?.title
            ?? (value.wrappedValue.isEmpty ? "Select…" : value.wrappedValue)
        return SubjectFormRow(label: title, arrangement: .control) {
            Menu {
                Picker(title, selection: value) {
                    if !options.contains(where: { $0.value == value.wrappedValue }) {
                        Text(currentTitle).tag(value.wrappedValue)
                    }
                    ForEach(options) { Text($0.title).tag($0.value) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                HStack(spacing: 6) {
                    if dynamicTypeSize.isAccessibilitySize {
                        Text(currentTitle)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                        Spacer(minLength: 0)
                    } else {
                        Spacer(minLength: 0)
                        Text(currentTitle)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                    disclosureChevron
                }
                .frame(maxWidth: .infinity)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(currentTitle)
        }
    }

    private func symbolChoiceRow(
        title: String,
        value: Binding<String>,
        options: [AO3FormOption],
        symbol: WorkSymbolTile
    ) -> some View {
        let currentTitle = options.first { $0.value == value.wrappedValue }?.title
            ?? (value.wrappedValue.isEmpty ? "Select…" : value.wrappedValue)
        return Menu {
            Picker(title, selection: value) {
                if !options.contains(where: { $0.value == value.wrappedValue }) {
                    Text(currentTitle).tag(value.wrappedValue)
                }
                ForEach(options) { Text($0.title).tag($0.value) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            symbolRowContent(title: title, value: currentTitle, symbol: symbol)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(currentTitle)
    }

    private func symbolDisclosureRow(
        title: String,
        value: String,
        symbol: WorkSymbolTile,
        isRequired: Bool = false
    ) -> some View {
        symbolRowContent(title: title, value: value, symbol: symbol, isRequired: isRequired)
    }

    private func symbolRowContent(
        title: String,
        value: String,
        symbol: WorkSymbolTile,
        isRequired: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            WorkSymbolTileView(symbol: symbol, side: 22)
                .accessibilityHidden(true)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    fieldLabel(title, isRequired: isRequired)
                        .foregroundStyle(.primary)
                    Text(value)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                fieldLabel(title, isRequired: isRequired)
                    .foregroundStyle(.primary)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
            disclosureChevron
        }
        .font(.system(size: actionRowTitleSize))
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var disclosureChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .accessibilityHidden(true)
    }

    private func tagChipsRow(
        title: String,
        values: Binding<[String]>,
        isRequired: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(title, isRequired: isRequired)
                .font(.system(size: actionRowTitleSize))
                .foregroundStyle(.primary)
                .accessibilityLabel(isRequired ? "\(title), required" : title)
            FlowLayout(spacing: 6, rowSpacing: 6) {
                ForEach(values.wrappedValue, id: \.self) { value in
                    SubjectChip(
                        text: value,
                        style: .neutral,
                        palette: accountPalette,
                        horizontalPadding: 10,
                        verticalPadding: 4
                    )
                }
                Text("Add…")
                    .font(.footnote)
                    .foregroundStyle(.accentInk)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// One `List` row per field, drawn as segments of one card. These were a
    /// `VStack` in a single row, and a `List` row fires EVERY navigation link
    /// inside it: tapping Fandoms pushed Archive warnings and Fandoms both, and
    /// tapping Relationships landed on Additional tags (measured on the
    /// simulator). A row holding one link fires only that one.
    @ViewBuilder
    private var requiredRows: some View {
        symbolChoiceRow(
            title: "Rating",
            value: $form.rating,
            options: form.ratingOptions,
            symbol: WorkSymbolTile.rating(form.rating, dark: isDarkTheme)
        )
        .panelSegment(0, of: 4, gutter: gutter)
        symbolDisclosureRow(
            title: "Archive Warnings",
            value: form.warnings.isEmpty ? "None" : form.warnings.joined(separator: ", "),
            symbol: WorkSymbolTile.warnings(WorkWarningStatus(rawWarnings: form.warnings), dark: isDarkTheme),
            isRequired: true
        )
        .subjectRowNavigation(accessibilityLabel: "Archive warnings, required") {
            WritingTagsEditor(
                title: "Archive warnings",
                values: $form.warnings,
                options: form.warningOptions,
                kind: nil
            )
        }
        .panelSegment(1, of: 4, gutter: gutter)
        symbolDisclosureRow(
            title: "Category",
            value: form.categories.isEmpty ? "None" : form.categories.joined(separator: ", "),
            symbol: WorkSymbolTile.category(form.categories, dark: isDarkTheme)
        )
        .subjectRowNavigation(accessibilityLabel: "Category") {
            WritingTagsEditor(
                title: "Category",
                values: $form.categories,
                options: form.categoryOptions,
                kind: nil
            )
        }
        .panelSegment(2, of: 4, gutter: gutter)
        tagChipsRow(title: "Fandoms", values: $form.fandoms, isRequired: true)
            .subjectRowNavigation(accessibilityLabel: "Add Fandoms, required") {
                WritingTagsEditor(
                    title: "Fandoms", values: $form.fandoms, options: [], kind: .fandom
                )
            }
            .panelSegment(3, of: 4, gutter: gutter)
    }

    /// See `requiredRows` — four links in one row pushed the wrong screen.
    @ViewBuilder
    private var tagsRows: some View {
        tagChipsRow(title: "Relationships", values: $form.relationships)
            .subjectRowNavigation(accessibilityLabel: "Add Relationships") {
                WritingTagsEditor(
                    title: "Relationships", values: $form.relationships, options: [], kind: .relationship
                )
            }
            .panelSegment(0, of: 3, gutter: gutter)
        tagChipsRow(title: "Characters", values: $form.characters)
            .subjectRowNavigation(accessibilityLabel: "Add Characters") {
                WritingTagsEditor(title: "Characters", values: $form.characters, options: [], kind: .character)
            }
            .panelSegment(1, of: 3, gutter: gutter)
        tagChipsRow(title: "Additional Tags", values: $form.additionalTags)
            .subjectRowNavigation(accessibilityLabel: "Add Additional tags") {
                WritingTagsEditor(
                    title: "Additional Tags", values: $form.additionalTags, options: [], kind: .freeform
                )
            }
            .panelSegment(2, of: 3, gutter: gutter)
    }

    @ViewBuilder
    private var prefaceRows: some View {
        SubjectFormRow(label: "Title", arrangement: .control, isRequired: true) {
            TextField("Title", text: $form.title).multilineTextAlignment(.trailing)
        }
        .panelSegment(0, of: 6, gutter: gutter)
        SubjectFormRow(label: "Co-creators", value: creatorsValue, showsDisclosure: true)
            .subjectRowNavigation(accessibilityLabel: "Co-creators") {
                WorkCreatorsPickerView(creators: $form.creators, workTitle: form.title)
            }
            .panelSegment(1, of: 6, gutter: gutter)
        WritingTextEditorRow(
            title: "Summary", text: $form.summary, target: recoveryTarget, field: "summary", previewsText: true
        )
        .panelSegment(2, of: 6, gutter: gutter)
        WritingTextEditorRow(title: "Beginning Notes", text: $form.notes, target: recoveryTarget, field: "notes")
            .panelSegment(3, of: 6, gutter: gutter)
        WritingTextEditorRow(title: "End Notes", text: $form.endnotes, target: recoveryTarget, field: "endnotes")
            .panelSegment(4, of: 6, gutter: gutter)
        choiceRow(
            title: "Work Skin",
            value: $form.workSkinID,
            options: defaultFirst(form.workSkinOptions, label: "Default")
        )
        .panelSegment(5, of: 6, gutter: gutter)
    }

    /// 1bw's pushes, one `List` row each. They were one `VStack` row, and a
    /// `List` row fires every `NavigationLink` inside it — tapping Series would
    /// have pushed all five pickers. See `requiredRows`.
    @ViewBuilder
    private var associationRows: some View {
        // These three rows drew a chevron and opened nothing until 1bw; the form
        // already carries every option they need, so the pickers edit what it
        // will post back rather than fetching anything.
        // 1bo's "Series": the series AO3's form lists as Current Series, then
        // what this save adds. It read "Add to series" / "No addition" while
        // the form carried only the pending-add select.
        SubjectFormRow(label: "Series", value: seriesValue, showsDisclosure: true)
            .subjectRowNavigation(accessibilityLabel: "Series") {
                WorkSeriesPickerView(
                    series: $form.series, newSeriesTitle: $form.newSeriesTitle, workTitle: form.title,
                    currentSeries: form.currentSeries
                )
            }
            .panelSegment(0, of: 5, gutter: gutter)
        SubjectFormRow(label: "Collections and Gifts", value: collectionsValue, showsDisclosure: true)
            .subjectRowNavigation(accessibilityLabel: "Collections and gifts") {
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
        SubjectFormRow(
            label: "Inspired By",
            value: form.parentWork.url.isEmpty ? "None" : "1",
            showsDisclosure: true
        )
        .subjectRowNavigation(accessibilityLabel: "Inspired by") {
            WorkParentWorkPickerView(
                parentWork: $form.parentWork,
                languageOptions: form.languageOptions
            )
        }
        .panelSegment(3, of: 5, gutter: gutter)
        choiceRow(title: "Language", value: $form.languageID, options: form.languageOptions)
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
        Self.seriesValue(
            current: form.currentSeries.map(\.title),
            adding: form.series.first(where: \.isSelected)?.title ?? AO3WorkForm.newSeriesTitle(form.newSeriesTitle)
        )
    }

    private var recoveryTarget: String { form.workID.map { "work:\($0)" } ?? "work:new" }

    /// 1bo's "The Weight of Water · 12 chapters · posted 4 Mar 2024", less the
    /// date: the edit form's only dates are the backdate inputs, which are not
    /// when the work was posted.
    static func subtitle(for form: AO3WorkForm) -> String {
        var parts = [form.title.isEmpty ? "Untitled" : form.title]
        if form.isDraft { parts.append("never posted") }
        if form.isPosted, let posted = form.chaptersPosted {
            parts.append("\(posted) \(posted == 1 ? "chapter" : "chapters")")
        }
        return parts.joined(separator: " · ")
    }

    /// One `List` row per editor — see `associationRows`. The rows are
    /// conditional (Work text only before posting; Add chapter and Edit tags
    /// only after), so the segment positions are counted, not fixed.
    @ViewBuilder
    private var chapterRows: some View {
        // Not for a draft with several chapters: AO3 serves no text box there, and
        // this row would be an empty one that replaces chapter 1 (audit A4-1).
        let showsWorkText = (form.kind == .new || form.isDraft) && form.chapter?.contentServed != false
        let postedWorkID: Int? = form.isPosted ? form.workID : nil
        let count = (showsWorkText ? 1 : 0) + (postedWorkID == nil ? 0 : 3)
        let afterText = showsWorkText ? 1 : 0
        if showsWorkText {
            WritingTextEditorRow(title: "Chapter 1 text", text: Binding(
                get: { form.chapter?.content ?? "" },
                set: { value in
                    if form.chapter == nil { form.chapter = AO3WorkChapterDraft() }
                    form.chapter?.content = value
                }
            ), target: recoveryTarget, field: "content")
            .panelSegment(0, of: count, gutter: gutter)
        }
        if let workID = postedWorkID {
            // 1bo's Chapters row. Posted works only, like the two below: a
            // draft's text is its Work text row, and a second way into chapter
            // 1 would let this form's Save put back what the chapter form saved.
            SubjectFormRow(
                label: "Chapters", value: form.chaptersPosted.map(String.init) ?? "", showsDisclosure: true
            )
            .subjectRowNavigation(accessibilityLabel: "Chapters") {
                WritingChaptersView(workID: workID, workTitle: form.title) { needsPublicationRefresh = true }
            }
            .panelSegment(afterText, of: count, gutter: gutter)
            SubjectFormRow(label: "Add Chapter", value: "", showsDisclosure: true)
                .subjectRowNavigation(accessibilityLabel: "Add chapter") {
                    WritingChapterDestination(workID: workID, workTitle: form.title) {
                        needsPublicationRefresh = true
                    }
                }
                .panelSegment(afterText + 1, of: count, gutter: gutter)
            // 1bp's own page, reachable at last. Gated exactly like Add chapter
            // rather than on `workID` alone: AO3 keeps `/works/<id>/edit_tags`
            // for a work that exists publicly, and a draft's tags are already
            // editable in the form above this row.
            SubjectFormRow(label: "Edit Tags", value: "", showsDisclosure: true)
                .subjectRowNavigation(accessibilityLabel: "Edit tags") {
                    WritingTagsDestination(workID: workID, workTitle: form.title) {
                        needsTagRefresh = true
                    }
                }
                .panelSegment(afterText + 2, of: count, gutter: gutter)
        }
    }

    /// Segments, for one card style across the screen. The toggles are titled
    /// even though the titles are hidden: `labelsHidden` hides a title from the
    /// eye, not from VoiceOver, and these four announced as a bare "switch".
    /// 1bs: a draft has no posted chapters to count, so those two rows are
    /// posted-only. The date row appears with the backdate switch, and only
    /// when AO3's form carried the chapter fields its `published_at` belongs to.
    @ViewBuilder
    private var publicationRows: some View {
        let first = form.isPosted ? 2 : 0
        let showsDate = form.backdate && form.chapter != nil
        let afterDate = first + (showsDate ? 2 : 1)
        let count = afterDate + 3
        if form.isPosted { chapterTotalRows(of: count) }
        SubjectFormRow(label: "Set a different publication date", arrangement: .control) {
            Toggle("Set a different publication date", isOn: backdate)
                .labelsHidden()
                .accentFill()
        }
        .panelSegment(first, of: count, gutter: gutter)
        if showsDate {
            SubjectFormRow(label: "Publication Date", arrangement: .control) {
                DatePicker(
                    "Publication Date",
                    selection: publicationDate,
                    in: AO3PublicationDate.allowedRange,
                    displayedComponents: .date
                )
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .trailing).accentFill()
            }
            .panelSegment(first + 1, of: count, gutter: gutter)
        }
        SubjectFormRow(label: "Only show to registered users", arrangement: .control) {
            Toggle("Only show to registered users", isOn: $form.restricted)
                .labelsHidden()
                .accentFill()
        }
        .panelSegment(afterDate, of: count, gutter: gutter)
        SubjectFormRow(label: "Enable comment moderation", arrangement: .control) {
            Toggle("Enable comment moderation", isOn: $form.moderatedCommenting)
                .labelsHidden()
                .accentFill()
        }
        .panelSegment(afterDate + 1, of: count, gutter: gutter)
        choiceRow(
            title: "Who Can Comment",
            value: $form.commentPermissions,
            options: form.commentPermissionOptions
        )
        .panelSegment(afterDate + 2, of: count, gutter: gutter)
    }

    private var deletePanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Delete Work on AO3", value: "", isDestructive: true) { confirmDelete() }
        }
        .subjectPanel()
    }

    private func save(submit: AO3WorkSubmitAction) {
        guard !isSaving && !isPosting && !needsPublicationRefresh && !needsTagRefresh else { return }
        Task {
            do { try await perform(submit: submit) } catch { errorMessage = UserFacingError.message(for: error) }
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
                onChanged()
                dismiss()
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }
}

// MARK: - Save path and AO3's preview

extension WorkEditView {
    /// The one save path, for the toolbar, the Post group and the preview's
    /// Post alike. Closes the form — and a preview above it — on success.
    private func perform(submit: AO3WorkSubmitAction) async throws {
        // Checked here, not only in `save`: its Task starts a beat after the
        // tap, and a second tap in that beat must not post twice.
        guard !isSaving && !isPosting else { return }
        guard editingGeneration == auth.sessionGeneration else {
            throw AO3WorkWriteError.rejected("Your AO3 session changed. Reopen this form before saving.")
        }
        let isPost = submit == .post || submit == .postWithoutPreview
        if isPost { isPosting = true } else { isSaving = true }
        do {
            try await auth.saveWork(form, submit: submit)
            preview = nil
            onChanged()
            dismiss()
        } catch {
            if isPost { isPosting = false } else { isSaving = false }
            throw error
        }
    }

    #if DEBUG
    @ViewBuilder
    private func debugWorkChild(_ id: String) -> some View {
        switch id {
        case "chapters":
            if let workID = form.workID {
                WritingChaptersView(workID: workID, workTitle: form.title) { needsPublicationRefresh = true }
            }
        case "chapterform":
            if let workID = form.workID {
                WritingChapterDestination(workID: workID, workTitle: form.title) { needsPublicationRefresh = true }
            }
        case "edittags":
            if let workID = form.workID {
                WritingTagsDestination(workID: workID, workTitle: form.title) { needsTagRefresh = true }
            }
        case "texteditor":
            WritingTextEditor(
                text: Binding(
                    get: {
                        let text = form.chapter?.content ?? ""
                        if text.isEmpty {
                            return "<p>The lantern drifted past the mill. 星 &amp; water.</p>"
                        }
                        return text
                    },
                    set: { value in
                        if form.chapter == nil { form.chapter = AO3WorkChapterDraft() }
                        form.chapter?.content = value
                    }
                ),
                title: "Chapter text",
                ruleTitle: "Chapter 1",
                account: auth.username ?? "",
                target: recoveryTarget,
                field: "content",
                chapterActions: WritingChapterEditorActions(
                    preview: { openPreview() },
                    deleteName: nil,
                    delete: {}
                )
            )
        case "recovery":
            WritingTextEditor(
                text: $form.notes, title: "Beginning notes",
                account: auth.username ?? "", target: recoveryTarget, field: "notes"
            )
        case "seriespicker":
            WorkSeriesPickerView(
                series: $form.series, newSeriesTitle: $form.newSeriesTitle, workTitle: form.title,
                currentSeries: form.currentSeries
            )
        case "collectionsgifts":
            collectionsAndGifts
        case "creatorspicker":
            WorkCreatorsPickerView(creators: $form.creators, workTitle: form.title)
        case "parentpicker":
            WorkParentWorkPickerView(parentWork: $form.parentWork, languageOptions: form.languageOptions)
        default:
            EmptyView()
        }
    }
    #endif

    /// AO3's preview path for an unposted work. A NEW work is saved by AO3
    /// as a draft to preview it (`works#create` redirects to its preview), so
    /// the form adopts that draft first — Post from the preview then updates
    /// it instead of creating a second work.
    private func openPreview() {
        guard !isSaving && !isPosting && !needsPublicationRefresh && !needsTagRefresh else { return }
        guard editingGeneration == auth.sessionGeneration else {
            errorMessage = "Your AO3 session changed. Reopen this form before saving."
            return
        }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let page = try await auth.previewWork(form)
                form = try form.adopting(page)
                preview = page
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }
}

// MARK: - 1bo backdate and 1bs draft posting

extension WorkEditView {
    /// The backdate switch used to bind `form.backdate` alone, so a backdate
    /// posted whatever date AO3 had prefilled. Turning it on now also fills
    /// an empty date with today — what AO3's own `date_select` defaults to.
    private var backdate: Binding<Bool> {
        Binding(
            get: { form.backdate },
            set: { isOn in
                form.backdate = isOn
                if isOn, form.chapter?.publishedYear.isEmpty == true { publicationDate.wrappedValue = Date() }
            }
        )
    }

    /// Reads and writes the chapter's `published_at` strings in AO3's own
    /// format (`AO3PublicationDate`), which the payload already posts.
    private var publicationDate: Binding<Date> {
        Binding(
            get: {
                form.chapter.flatMap {
                    AO3PublicationDate.date(year: $0.publishedYear, month: $0.publishedMonth, day: $0.publishedDay)
                } ?? Date()
            },
            set: { date in
                let fields = AO3PublicationDate.fields(for: date)
                form.chapter?.publishedYear = fields.year
                form.chapter?.publishedMonth = fields.month
                form.chapter?.publishedDay = fields.day
            }
        )
    }

    @ViewBuilder
    private func chapterTotalRows(of count: Int) -> some View {
        // 1bo: "setting a total above what is posted is what marks a work in
        // progress". The posted count is AO3's to report, the total is the
        // writer's to set — so only one half of this row is editable.
        SubjectFormRow(label: "Chapters Posted", arrangement: .control) {
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
        .panelSegment(0, of: count, gutter: gutter)
        SubjectFormRow(label: "Work is complete", arrangement: .control) {
            Toggle("Work is complete", isOn: Binding(
                get: { form.chapterTotal == "\(form.chaptersPosted ?? 1)" },
                set: { form.chapterTotal = $0 ? "\(form.chaptersPosted ?? 1)" : "" }
            ))
            .labelsHidden()
            .accentFill()
        }
        .panelSegment(1, of: count, gutter: gutter)
    }

    /// AO3's work form has no `post_without_preview_button` — that name is
    /// the chapter form's. `works#create` and `#update` post only on
    /// `post_button` (`@work.posted = … if params[:post_button]`) and save
    /// anything else as a draft, which is what "Post work" used to do.
    static let postSubmit = AO3WorkSubmitAction.post

    /// Chapter 1 after a chapter write: AO3's, except a publication date
    /// picked on this form and not yet saved (it differs from `loaded`, the
    /// date this form was given). Taking AO3's date always threw that pick
    /// away; keeping this form's always wrote the old date back over one the
    /// chapter screen had just saved for chapter 1.
    static func refreshedChapter(
        _ current: AO3WorkChapterDraft?, loaded: AO3WorkChapterDraft?, fresh: AO3WorkChapterDraft?
    ) -> AO3WorkChapterDraft? {
        guard let current, var kept = fresh else { return fresh }
        let date = { (chapter: AO3WorkChapterDraft?) in
            [chapter?.publishedYear, chapter?.publishedMonth, chapter?.publishedDay]
        }
        if date(current) != date(loaded) {
            kept.publishedYear = current.publishedYear
            kept.publishedMonth = current.publishedMonth
            kept.publishedDay = current.publishedDay
        }
        return kept
    }

    /// "Water", "Water + Salt", "Adding Salt", "None". The addition is a name:
    /// AO3's form adds one series per save (see `WorkSeriesPickerView`). 1bo's
    /// ", 2 of 3" is left off — the edit form carries no position.
    static func seriesValue(current: [String], adding: String?) -> String {
        let now = current.joined(separator: ", ")
        switch (now.isEmpty, adding) {
        case (true, nil): return "None"
        case let (true, adding?): return "Adding \(adding)"
        case (false, nil): return now
        case let (false, adding?): return "\(now) + \(adding)"
        }
    }

    /// 1bs's Post group: "Post work", AO3's "Preview", then "Delete draft"
    /// once AO3 has the draft. Post asks first (`showPostConfirmation`).
    private var postPanel: some View {
        VStack(spacing: 0) {
            postPanelRow("Post Work", icon: "arrow.up.circle.fill", color: theme.accentInk) {
                showPostConfirmation = true
            }
            SubjectRowSeparator()
            postPanelRow("Preview on AO3", icon: "eye", color: theme.accentInk) { openPreview() }
            if form.workID != nil {
                SubjectRowSeparator()
                postPanelRow("Delete Draft", icon: "trash.fill", color: .red) { confirmDelete() }
            }
        }
        .subjectPanel()
    }

    /// `AddChapterView.postPanel`'s row shape.
    private func postPanelRow(
        _ title: String, icon: String, color: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: actionRowTitleSize))
                Spacer()
            }
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSaving || isPosting || isCheckingDelete)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: footnoteSize))
            .foregroundStyle(.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .pageBodyRow(top: 8, gutter: gutter)
    }

    private var screenTitle: String {
        switch form.kind {
        case .new: "New Work"
        case .draft: "Draft"
        case .edit, .editTags: "Edit Work"
        }
    }

    enum HeaderActionKind: Equatable, Sendable {
        case cancel
        case preview
        case save
    }

    struct HeaderAction: Equatable, Sendable {
        let kind: HeaderActionKind
        let title: String
        let systemImage: String?
        let isEnabled: Bool
    }

    /// Board 42's header chrome: circular `xmark` dismiss on the leading edge,
    /// circular `eye` preview button, and the filled primary action pill.
    static func headerActions(
        isSaving: Bool = false,
        isPosting: Bool = false,
        needsPublicationRefresh: Bool = false,
        needsTagRefresh: Bool = false
    ) -> [HeaderAction] {
        let canAct = !(isSaving || isPosting || needsPublicationRefresh || needsTagRefresh)
        return [
            HeaderAction(
                kind: .cancel,
                title: "Cancel",
                systemImage: "xmark",
                isEnabled: !(isSaving || isPosting)
            ),
            HeaderAction(
                kind: .preview,
                title: "Preview",
                systemImage: "eye",
                isEnabled: canAct
            ),
            HeaderAction(
                kind: .save,
                title: "Save",
                systemImage: nil,
                isEnabled: canAct
            )
        ]
    }

    static func headerAction(
        _ kind: HeaderActionKind,
        isSaving: Bool = false,
        isPosting: Bool = false,
        needsPublicationRefresh: Bool = false,
        needsTagRefresh: Bool = false
    ) -> HeaderAction? {
        headerActions(
            isSaving: isSaving,
            isPosting: isPosting,
            needsPublicationRefresh: needsPublicationRefresh,
            needsTagRefresh: needsTagRefresh
        ).first { $0.kind == kind }
    }

    @ToolbarContentBuilder
    private var headerToolbar: some ToolbarContent {
        let cancelAction = Self.headerAction(
            .cancel,
            isSaving: isSaving,
            isPosting: isPosting,
            needsPublicationRefresh: needsPublicationRefresh,
            needsTagRefresh: needsTagRefresh
        )
        let previewAction = Self.headerAction(
            .preview,
            isSaving: isSaving,
            isPosting: isPosting,
            needsPublicationRefresh: needsPublicationRefresh,
            needsTagRefresh: needsTagRefresh
        )
        let saveAction = Self.headerAction(
            .save,
            isSaving: isSaving,
            isPosting: isPosting,
            needsPublicationRefresh: needsPublicationRefresh,
            needsTagRefresh: needsTagRefresh
        )
        if let cancelAction, let systemImage = cancelAction.systemImage {
            ToolbarItem(placement: .cancellationAction) {
                ToolbarIconButton(
                    title: cancelAction.title,
                    systemImage: systemImage,
                    tint: .primary,
                    isDisabled: !cancelAction.isEnabled
                ) {
                    dismiss()
                }
                .labelStyle(.iconOnly)
            }
        }
        if let previewAction, let systemImage = previewAction.systemImage {
            ActionToolbar(items: [
                AnyView(
                    ToolbarIconButton(
                        title: previewAction.title,
                        systemImage: systemImage,
                        tint: .primary,
                        isDisabled: !previewAction.isEnabled
                    ) {
                        openPreview()
                    }
                )
            ])
        }
        if let saveAction {
            ToolbarItem(placement: .confirmationAction) {
                Button(saveAction.title) {
                    save(submit: form.isPosted ? .update : .saveDraft)
                }
                .sheetConfirmStyle()
                .disabled(!saveAction.isEnabled)
            }
        }
    }

    /// 1bs's confirmation copy. The board's "your 412 subscribers" is dropped:
    /// the form does not carry a subscriber count.
    static func postConfirmationMessage(missing: [String]) -> String {
        let consequence = "notifies your subscribers and can't be undone. You can edit a posted work, "
            + "but you can't return it to a draft."
        guard !missing.isEmpty else { return "Posting " + consequence }
        let things = missing.map { requirementPhrases[$0] ?? $0.lowercased() }
        let list = ListFormatter.localizedString(byJoining: things)
        let (lead, requires) = switch missing.count {
        case 1: ("One thing is missing", "it")
        case 2: ("Two things are missing", "both")
        default: ("\(missing.count) things are missing", "all of them")
        }
        return "\(lead). Add \(list). AO3 requires \(requires). Posting also " + consequence
    }

    /// `AO3WorkForm.missingRequiredFields()`'s names, as the board phrases them.
    private static let requirementPhrases = [
        "Title": "a title", "Rating": "a rating", "Archive Warning": "an archive warning",
        "Fandoms": "a fandom", "Language": "a language", "Work Text": "the work text"
    ]

    private func confirmDelete() {
        Task {
            guard let workID = form.workID else { return }
            isCheckingDelete = true
            do {
                deleteImplications = try await auth.loadDeleteImplications(workID: workID)
                showDeleteConfirmation = true
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
            isCheckingDelete = false
        }
    }
}
