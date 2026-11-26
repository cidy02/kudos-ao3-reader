import Foundation
import SwiftUI

/// Client-side validation for `ImportWorkView`, matching otwarchive `452391b6`
/// `config/config.yml` (`IMPORT_MAX_WORKS = 25`, `IMPORT_MAX_CHAPTERS = 200`).
nonisolated enum AO3ImportValidation {
    static let maxWorks = 25
    static let maxChapters = 200

    struct Verdict: Equatable, Sendable {
        let urls: [String]
        let limit: Int
        let isOverLimit: Bool
        let overLimitNote: String?
        let isLanguageMissing: Bool

        var canImport: Bool {
            !urls.isEmpty && !isOverLimit && !isLanguageMissing
        }
    }

    static func parsedURLs(from rawText: String) -> [String] {
        rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func limit(for mode: AO3ImportMode) -> Int {
        switch mode {
        case .works: maxWorks
        case .chapters: maxChapters
        }
    }

    static func evaluate(
        urlsText: String,
        mode: AO3ImportMode,
        languageID: String
    ) -> Verdict {
        let urls = parsedURLs(from: urlsText)
        let cap = limit(for: mode)
        let overLimit = urls.count > cap
        let note: String? = if overLimit {
            switch mode {
            case .works:
                "AO3 imports up to \(maxWorks) separate works at once. You entered \(urls.count)."
            case .chapters:
                "AO3 imports up to \(maxChapters) chapters at once. You entered \(urls.count)."
            }
        } else {
            nil
        }
        let missingLanguage = languageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Verdict(
            urls: urls,
            limit: cap,
            isOverLimit: overLimit,
            overLimitNote: note,
            isLanguageMissing: missingLanguage
        )
    }
}

/// Sheet for importing works from external URLs (`GET /works/new?import=true`
/// → `POST /works/import`, otwarchive `452391b6`).
struct ImportWorkView: View {
    let onOpenDraft: (Int) -> Void
    let onOpenWork: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var form: AO3ImportForm?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var reload = 0

    @State private var urlsText = ""
    @State private var importMode: AO3ImportMode = .works
    @State private var languageID = ""
    @State private var pseudToApply = ""
    @State private var encoding = ""
    @State private var tagMode: TagSourceMode = .fromPages
    @State private var tags = AO3WorkTagSet()
    @State private var restricted = false
    @State private var commentPermissions = "disable_anon"
    @State private var moderatedCommenting = false
    @State private var previewBeforePosting = true

    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var importedWorkIDs: [Int]?

    @ScaledMetric(relativeTo: .caption) private var footnoteSize: CGFloat = 11.5

    enum TagSourceMode: String, Hashable, CaseIterable {
        case fromPages
        case setHere

        var title: String {
            switch self {
            case .fromPages: "Find them in the pages"
            case .setHere: "Set them here"
            }
        }
    }

    private var gutter: CGFloat { SubjectMetrics.accountGutter }
    private var palette: SubjectPalette { theme.scopePalette }

    private var validation: AO3ImportValidation.Verdict {
        AO3ImportValidation.evaluate(
            urlsText: urlsText,
            mode: importMode,
            languageID: languageID
        )
    }

    var body: some View {
        NavigationStack {
            List {
                if let importedWorkIDs {
                    severalResultsSection(importedWorkIDs)
                } else if isLoading {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView().accentFill()
                            Text("Loading import form…")
                                .font(.footnote)
                                .foregroundStyle(.secondaryInk)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .subjectPanel()
                        .pageBodyRow(top: 16, gutter: gutter)
                    }
                } else if let loadError, form == nil {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(loadError)
                                .font(.footnote)
                                .foregroundStyle(theme.appTheme.errorColor)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Try Again") { reload += 1 }
                                .buttonStyle(.kudosSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .subjectPanel()
                        .pageBodyRow(top: 16, gutter: gutter)
                    }
                } else if let form {
                    importFormSections(form)
                }
            }
            .cardList()
            .environment(\.defaultMinListRowHeight, 0)
            .subjectScreenWash(title: "Import from a URL", palette: palette)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(importedWorkIDs == nil ? "Cancel" : "Done") { dismiss() }
                        .disabled(isSubmitting)
                }
                if importedWorkIDs == nil, form != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isSubmitting ? "Importing…" : "Import") {
                            Task { await submit() }
                        }
                        .sheetConfirmStyle()
                        .disabled(!validation.canImport || isSubmitting)
                    }
                }
            }
            .task(id: "\(auth.sessionGeneration):\(reload)") {
                await loadForm()
            }
        }
        .presentationDragIndicator(.visible)
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 580)
        #endif
    }

    // MARK: - Form sections

    @ViewBuilder
    private func importFormSections(_ form: AO3ImportForm) -> some View {
        if let submitError {
            Section {
                Text(submitError)
                    .font(.footnote)
                    .foregroundStyle(theme.appTheme.errorColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .subjectPanel()
                    .pageBodyRow(top: 12, gutter: gutter)
            }
        }

        Section {
            linksEditor
                .pageBodyRow(top: 8, gutter: gutter)
            if let note = validation.overLimitNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(theme.appTheme.errorColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .pageBodyRow(top: 8, gutter: gutter)
            }
        } header: {
            SectionRuleHeader(title: "Links, one per line")
                .pageBodyRow(top: 14, gutter: 0)
        }

        Section {
            importModeControl
                .pageBodyRow(top: 8, gutter: gutter)
            footnote(
                "Up to \(AO3ImportValidation.maxWorks) separate works, or up to "
                    + "\(AO3ImportValidation.maxChapters) chapters of one work."
            )
        } header: {
            SectionRuleHeader(title: "These links are")
                .pageBodyRow(top: 16, gutter: 0)
        }

        Section {
            detailsRows(form)
        } header: {
            SectionRuleHeader(title: "Details")
                .pageBodyRow(top: 16, gutter: 0)
        }

        Section {
            tagModeControl
                .pageBodyRow(top: 8, gutter: gutter)
        } header: {
            SectionRuleHeader(title: "Tags")
                .pageBodyRow(top: 16, gutter: 0)
        }

        if tagMode == .setHere {
            Section {
                overrideTagRows(form)
            }
        }

        Section {
            privacyRows(form)
        } header: {
            SectionRuleHeader(title: "Privacy and comments")
                .pageBodyRow(top: 16, gutter: 0)
        }

        Section {
            SubjectFormRow(label: "Preview before posting", arrangement: .control) {
                Toggle("Preview before posting", isOn: $previewBeforePosting)
                    .labelsHidden()
                    .accentFill()
            }
            .subjectPanel()
            .disabled(isSubmitting)
            .pageBodyRow(top: 14, gutter: gutter)

            footnote("It arrives as an AO3 draft, kept for 29 days, and shows in Drafts.")
            footnote("For your own work that's on another site. AO3 fetches the pages, not Kudos.")
        }
    }
}

private extension ImportWorkView {
    var linksEditor: some View {
        ZStack(alignment: .topLeading) {
            if urlsText.isEmpty {
                Text("https://example.com/story/1")
                    .font(.body)
                    .foregroundStyle(.secondary.opacity(0.6))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $urlsText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 112)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .accessibilityLabel("Links, one per line")
        }
        .subjectPanel()
        .disabled(isSubmitting)
    }

    @ViewBuilder
    var importModeControl: some View {
        let modes: [AO3ImportMode] = [.chapters, .works]
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 0) {
                ForEach(Array(modes.enumerated()), id: \.element) { index, mode in
                    if index > 0 { SubjectRowSeparator() }
                    let isSelected = importMode == mode
                    SubjectFormRow(label: modeLabel(mode), action: { importMode = mode }) {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.accentInk)
                        }
                    }
                    .accessibilityLabel(modeLabel(mode))
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
            .subjectPanel()
            .disabled(isSubmitting)
        } else {
            SubjectSegmentedControl(
                options: modes,
                title: modeLabel,
                selection: $importMode
            )
            .disabled(isSubmitting)
        }
    }

    @ViewBuilder
    var tagModeControl: some View {
        let modes = TagSourceMode.allCases
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 0) {
                ForEach(Array(modes.enumerated()), id: \.element) { index, mode in
                    if index > 0 { SubjectRowSeparator() }
                    let isSelected = tagMode == mode
                    SubjectFormRow(label: mode.title, action: { tagMode = mode }) {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.accentInk)
                        }
                    }
                    .accessibilityLabel(mode.title)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
            .subjectPanel()
            .disabled(isSubmitting)
        } else {
            SubjectSegmentedControl(
                options: modes,
                title: \.title,
                selection: $tagMode
            )
            .disabled(isSubmitting)
        }
    }

    @ViewBuilder
    func detailsRows(_ form: AO3ImportForm) -> some View {
        let hasPseuds = !form.pseudOptions.isEmpty
        let count = hasPseuds ? 3 : 2
        WritingChoiceRow(
            title: "Language",
            value: $languageID,
            options: form.languageOptions
        )
        .disabled(isSubmitting)
        .panelSegment(0, of: count, gutter: gutter)

        if hasPseuds {
            WritingChoiceRow(
                title: "Post as",
                value: $pseudToApply,
                options: form.pseudOptions
            )
            .disabled(isSubmitting)
            .panelSegment(1, of: count, gutter: gutter)
        }

        WritingChoiceRow(
            title: "Text encoding",
            value: $encoding,
            options: encodingOptions(from: form)
        )
        .disabled(isSubmitting)
        .panelSegment(hasPseuds ? 2 : 1, of: count, gutter: gutter)

        if validation.isLanguageMissing {
            footnote("Language is required before importing.")
        }
    }

    @ViewBuilder
    func overrideTagRows(_ form: AO3ImportForm) -> some View {
        let hasCategories = !form.categoryOptions.isEmpty
        let count = hasCategories ? 7 : 6
        WritingChoiceRow(
            title: "Rating",
            value: $tags.rating,
            options: ratingOptions(from: form)
        )
        .disabled(isSubmitting)
        .panelSegment(0, of: count, gutter: gutter)

        WritingTagsRow(
            title: "Archive Warnings",
            values: $tags.warnings,
            options: form.warningOptions,
            kind: nil
        )
        .disabled(isSubmitting)
        .panelSegment(1, of: count, gutter: gutter)

        if hasCategories {
            WritingTagsRow(
                title: "Categories",
                values: $tags.categories,
                options: form.categoryOptions,
                kind: nil
            )
            .disabled(isSubmitting)
            .panelSegment(2, of: count, gutter: gutter)
        }

        let offset = hasCategories ? 3 : 2
        WritingTagsRow(title: "Fandoms", values: $tags.fandoms, kind: .fandom)
            .disabled(isSubmitting)
            .panelSegment(offset, of: count, gutter: gutter)
        WritingTagsRow(title: "Relationships", values: $tags.relationships, kind: .relationship)
            .disabled(isSubmitting)
            .panelSegment(offset + 1, of: count, gutter: gutter)
        WritingTagsRow(title: "Characters", values: $tags.characters, kind: .character)
            .disabled(isSubmitting)
            .panelSegment(offset + 2, of: count, gutter: gutter)
        WritingTagsRow(title: "Additional Tags", values: $tags.additionalTags, kind: .freeform)
            .disabled(isSubmitting)
            .panelSegment(offset + 3, of: count, gutter: gutter)
    }

    @ViewBuilder
    func privacyRows(_ form: AO3ImportForm) -> some View {
        WritingChoiceRow(
            title: "Who can see it",
            value: Binding(
                get: { restricted ? "1" : "0" },
                set: { restricted = ($0 == "1") }
            ),
            options: [
                AO3FormOption(value: "0", title: "Anyone"),
                AO3FormOption(value: "1", title: "Registered users only")
            ]
        )
        .disabled(isSubmitting)
        .panelSegment(0, of: 3, gutter: gutter)

        WritingChoiceRow(
            title: "Who can comment",
            value: $commentPermissions,
            options: form.commentPermissionOptions
        )
        .disabled(isSubmitting)
        .panelSegment(1, of: 3, gutter: gutter)

        SubjectFormRow(label: "Approve comments first", arrangement: .control) {
            Toggle("Approve comments first", isOn: $moderatedCommenting)
                .labelsHidden()
                .accentFill()
        }
        .disabled(isSubmitting)
        .panelSegment(2, of: 3, gutter: gutter)
    }

    @ViewBuilder
    func severalResultsSection(_ ids: [Int]) -> some View {
        Section {
            Text("AO3 imported \(ids.count) works. Tap a work to open it.")
                .font(.subheadline)
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .pageBodyRow(top: 12, gutter: gutter)

            VStack(spacing: 0) {
                ForEach(Array(ids.enumerated()), id: \.element) { index, workID in
                    if index > 0 { SubjectRowSeparator() }
                    SubjectFormRow(
                        label: "Work #\(workID)",
                        value: "Open",
                        showsDisclosure: true
                    ) {
                        dismiss()
                        onOpenWork(workID)
                    }
                    .accessibilityLabel("Open imported work \(workID)")
                }
            }
            .subjectPanel()
            .pageBodyRow(top: 10, gutter: gutter)
        } header: {
            SectionRuleHeader(title: "Imported works", count: ids.count)
                .pageBodyRow(top: 14, gutter: 0)
        }
    }

    func modeLabel(_ mode: AO3ImportMode) -> String {
        switch mode {
        case .chapters: "Chapters of one work"
        case .works: "Separate works"
        }
    }

    func encodingOptions(from form: AO3ImportForm) -> [AO3FormOption] {
        var options = form.encodingOptions
        if let blank = options.firstIndex(where: { $0.value.isEmpty }) {
            if options[blank].title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                options[blank].title = "Detect automatically"
            }
            return options
        }
        return [AO3FormOption(value: "", title: "Detect automatically")] + options
    }

    func ratingOptions(from form: AO3ImportForm) -> [AO3FormOption] {
        var options = form.ratingOptions
        if let blank = options.firstIndex(where: { $0.value.isEmpty }) {
            if options[blank].title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                options[blank].title = "Not set"
            }
            return options
        }
        return [AO3FormOption(value: "", title: "Not set")] + options
    }

    func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: footnoteSize))
            .foregroundStyle(.secondary.opacity(0.75))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .pageBodyRow(top: 8, gutter: gutter)
    }

    func loadForm() async {
        isLoading = true
        loadError = nil
        let generation = auth.sessionGeneration
        do {
            let loaded = try await auth.loadImportForm()
            guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
            form = loaded
            languageID = loaded.selectedLanguageID
            pseudToApply = loaded.selectedPseud
            commentPermissions = loaded.defaultCommentPermissions
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
            loadError = UserFacingError.message(for: error)
        }
        isLoading = false
    }

    func submit() async {
        guard !isSubmitting, let form, validation.canImport else { return }
        isSubmitting = true
        submitError = nil
        let overrideTags = tagMode == .setHere
        let request = AO3ImportRequest(
            urls: validation.urls,
            importMultiple: importMode,
            languageID: languageID,
            encoding: encoding,
            pseudToApply: pseudToApply,
            postWithoutPreview: !previewBeforePosting,
            restricted: restricted,
            commentPermissions: commentPermissions,
            moderatedCommenting: moderatedCommenting,
            overrideTags: overrideTags,
            detectTags: !overrideTags,
            tags: tags,
            notes: ""
        )
        do {
            let result = try await auth.importWorks(request, form: form)
            isSubmitting = false
            switch result {
            case let .draft(workID):
                dismiss()
                onOpenDraft(workID)
            case let .posted(workID):
                dismiss()
                onOpenWork(workID)
            case let .several(ids):
                importedWorkIDs = ids
            case let .failed(message):
                submitError = message
            }
        } catch {
            isSubmitting = false
            submitError = UserFacingError.message(for: error)
        }
    }
}
