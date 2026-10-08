import SwiftUI

extension Notification.Name {
    static let ao3CollectionDeleted = Notification.Name("AO3CollectionDeleted")
}

extension Notification {
    func deletesCollection(slug: String?) -> Bool {
        guard let slug else { return false }
        return name == .ao3CollectionDeleted && object as? String == slug
    }
}

/// Navigation value for the collection form. `slug == nil` is New Collection.
struct AO3CollectionFormDestination: Hashable {
    var slug: String?
}

/// Artboards **1bl** — AO3's New Collection and Edit Collection forms.
///
/// The spec's own framing, kept: *"Every row here is a field on AO3's own New
/// Collection form, in AO3's three sections. Nothing dropped, nothing invented."*
/// So the sections below are AO3's (Header, Images, Preferences, Challenge,
/// Profile) and every row maps to a field `AO3CollectionForm` already carries and
/// `AO3Client.collectionFormParameters` already posts.
///
/// Closing stays on AO3. Owners can delete after a destructive confirmation;
/// AO3's owner-gated edit form is what makes that action available here.
struct AO3CollectionFormView: View {
    /// Editing an existing collection, or creating one.
    let slug: String?
    var onDeleted: (() -> Void)?

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .caption) private var groupNoteSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) private var fieldErrorSize: CGFloat = 11.5
    @ScaledMetric(relativeTo: .footnote) private var noticeCardSize: CGFloat = 12.5
    @ScaledMetric(relativeTo: .headline) private var actionTitleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .footnote) private var actionButtonSize: CGFloat = 13

    @State private var form: AO3CollectionForm?
    /// The session `form` was loaded under, and its account. Save posts only
    /// under that session, or a later one of the same account, so a form filled
    /// in as one account is never sent as another. Not a `.task` key: re-keying
    /// would discard typed edits on a same-user cookie rotation, and the
    /// save-time check is enough.
    @State private var formGeneration: Int?
    @State private var formUsername: String?
    @State private var phase: Phase = .idle
    @State private var saveMessage: String?
    @State private var nameAvailability: AO3CollectionNameAvailability?
    @State private var nameCheckTask: Task<Void, Never>?
    @State private var showingDeleteConfirmation = false
    /// 1bl: the name, typed, before Delete on AO3 enables.
    @State private var deleteConfirmationText = ""
    @State private var isDeleting = false

    init(slug: String?, onDeleted: (() -> Void)? = nil) {
        self.slug = slug
        self.onDeleted = onDeleted
    }

    private enum Phase: Equatable { case idle, loading, ready, saving, failed(String) }

    private var isNew: Bool { slug == nil }

    var body: some View {
        Group {
            switch phase {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView {
                    Label("Couldn't open the form", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await loadForm() } }
                }
            default:
                if form != nil { formBody } else { EmptyView() }
            }
        }
        .subjectScreenWash(palette: palette)
        .task { if phase == .idle { await loadForm() } }
        .onDisappear { nameCheckTask?.cancel() }
        // 1bl: the alert says what AO3 actually does — including to other
        // people's privacy — and asks for the name typed before it will.
        .alert(
            "Delete \u{201c}\(deletionName)\u{201d}?",
            isPresented: $showingDeleteConfirmation
        ) {
            TextField(deletionName, text: $deleteConfirmationText)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { deleteConfirmationText = "" }
            Button("Delete on AO3", role: .destructive) {
                deleteConfirmationText = ""
                Task { await deleteCollection() }
            }
            .disabled(!Self.confirmsDeletion(typed: deleteConfirmationText, name: deletionName))
        } message: {
            Text(Self.deletionMessage)
        }
    }

    @ViewBuilder
    private var formBody: some View {
        // `AO3CollectionForm.blank` is the fallback rather than a force-unwrap: this
        // branch is only reached with a non-nil form, but a crash here would be a
        // crash on a network race, and a blank form is a harmless thing to bind to
        // for the frame it would take.
        let binding = Binding(
            get: { form ?? AO3CollectionForm.blank },
            set: { form = $0 }
        )
        List {
            Section {
                header.pageBodyRow(top: 20, gutter: 0)
                if let saveMessage {
                    noticeCard(saveMessage, isError: false)
                        .pageBodyRow(top: 12, gutter: SubjectMetrics.accountGutter)
                }
                if let errors = form?.generalErrors, !errors.isEmpty {
                    noticeCard(errors.joined(separator: "\n"), isError: true)
                        .pageBodyRow(top: 12, gutter: SubjectMetrics.accountGutter)
                }
            }

            group("Header", note: nameNote) {
                textRow("Display title", text: binding.title,
                        placeholder: "Required", errorKey: AO3CollectionParam.title)
                SubjectRowSeparator()
                nameRow(binding)
                SubjectRowSeparator()
                textRow("Parent collection", text: binding.parentName,
                        placeholder: "None", errorKey: AO3CollectionParam.parentName)
                SubjectRowSeparator()
                textRow("Contact email", text: binding.email,
                        placeholder: "Optional", errorKey: AO3CollectionParam.email)
                SubjectRowSeparator()
                textRow("Tagline", text: binding.description,
                        placeholder: "Optional", errorKey: AO3CollectionParam.description)
            }

            group("Images", note: nil) {
                textRow("Header image URL", text: binding.headerImageURL,
                        placeholder: "Optional", errorKey: AO3CollectionParam.headerImageURL)
                SubjectRowSeparator()
                textRow("Header image alt text", text: binding.headerImageAlt,
                        placeholder: "Optional", errorKey: nil)
                SubjectRowSeparator()
                textRow("Icon alt text", text: binding.iconAlt,
                        placeholder: "Optional", errorKey: AO3CollectionParam.iconAlt)
                SubjectRowSeparator()
                textRow("Icon comment", text: binding.iconComment,
                        placeholder: "Optional", errorKey: AO3CollectionParam.iconComment)
            }

            group("Preferences", note: preferencesNote) {
                toggleRow("Closed to new items", isOn: binding.isClosed)
                SubjectRowSeparator()
                toggleRow("Moderated", isOn: binding.isModerated)
                SubjectRowSeparator()
                toggleRow("Unrevealed", isOn: binding.isUnrevealed)
                SubjectRowSeparator()
                toggleRow("Anonymous", isOn: binding.isAnonymous)
                SubjectRowSeparator()
                // AO3's `email_notify` mails the contact email when an item is
                // added (CollectionMailer#item_added_notification), not members.
                toggleRow("Email new items", isOn: binding.emailNotify)
            }

            // AO3 prints the select only while it offers one; no field, no row.
            if !binding.wrappedValue.challengeOptions.isEmpty {
                group("Challenge", note: nil) {
                    SubjectFormRow(
                        label: "Set up a challenge",
                        arrangement: .control,
                        trailing: {
                            Picker("Set up a challenge", selection: binding.challengeType) {
                                ForEach(binding.wrappedValue.challengeOptions) { option in
                                    // AO3's blank option may print no text.
                                    Text(option.title.isEmpty ? "None" : option.title)
                                        .tag(option.value)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    )
                }
            }

            group("Profile", note: nil) {
                textRow("Introduction", text: binding.introduction,
                        placeholder: "Optional", errorKey: AO3CollectionParam.intro, isMultiline: true)
                SubjectRowSeparator()
                textRow("FAQ", text: binding.faq,
                        placeholder: "Optional", errorKey: AO3CollectionParam.faq, isMultiline: true)
                SubjectRowSeparator()
                textRow("Rules", text: binding.rules,
                        placeholder: "Optional", errorKey: AO3CollectionParam.rules, isMultiline: true)
            }

            Section {
                saveButton.pageBodyRow(top: 18, gutter: SubjectMetrics.accountGutter)
                if !isNew {
                    openOnAO3Card.pageBodyRow(top: 12, gutter: SubjectMetrics.accountGutter)
                }
            }
        }
        .cardList()
        // Rows at their own padding, not the List minimum (L3-FORM-1).
        .environment(\.defaultMinListRowHeight, 0)
    }

    // MARK: Header

    private var header: some View {
        SubjectHeaderBlock(
            kicker: "AO3 Account › Collections",
            title: isNew ? "New collection" : "Edit collection",
            subtitle: "Your changes are saved to AO3",
            palette: palette,
            gutter: SubjectMetrics.accountGutter
        )
    }

    private var palette: SubjectPalette {
        theme.scopePalette
    }

    private var deletionName: String {
        let title = form?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !title.isEmpty { return title }
        return form?.name ?? "collection"
    }

    // MARK: Rows

    @ViewBuilder
    private func group(
        _ title: String,
        note: String?,
        @ViewBuilder rows: () -> some View
    ) -> some View {
        Section {
            SubjectFieldLabel(text: title, style: .formGroup)
                .pageBodyRow(top: 18, gutter: SubjectMetrics.accountGutter)
            VStack(spacing: 0) { rows() }
                .subjectPanel()
                .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
            if let note {
                Text(note)
                    .font(.system(size: groupNoteSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
            }
        }
    }

    private func textRow(
        _ label: String,
        text: Binding<String>,
        placeholder: String,
        errorKey: String?,
        isMultiline: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SubjectFormRow(
                label: label,
                arrangement: .control,
                trailing: {
                    TextField(placeholder, text: text, axis: isMultiline ? .vertical : .horizontal)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(isMultiline ? .leading : .trailing)
                        .lineLimit(isMultiline ? 2...6 : 1...1)
                        .frame(maxWidth: .infinity, alignment: isMultiline ? .leading : .trailing)
                }
            )
            if let errorKey, let message = form?.fieldErrors[errorKey], !message.isEmpty {
                fieldError(message)
            }
        }
    }

    /// The collection name gets its own row because it is the only field AO3
    /// validates for availability before the form can post, and the only one it
    /// locks after creation.
    @ViewBuilder
    private func nameRow(_ binding: Binding<AO3CollectionForm>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SubjectFormRow(
                label: "Collection name",
                arrangement: .control,
                isDisabled: form?.nameIsLocked == true,
                trailing: {
                    HStack(spacing: 8) {
                        TextField("Required", text: binding.name)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                        #endif
                            .onChange(of: binding.wrappedValue.name) { _, newValue in
                                scheduleNameCheck(newValue)
                            }
                        availabilityMark
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            )
            if let message = form?.fieldErrors[AO3CollectionParam.name], !message.isEmpty {
                fieldError(message)
            }
        }
    }

    @ViewBuilder
    private var availabilityMark: some View {
        switch nameAvailability {
        case .available:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Name is available")
        case .taken:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Name is taken")
        case .invalid:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .accessibilityLabel("Name is not a valid collection name")
        case .unknown, nil:
            EmptyView()
        }
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        SubjectFormRow(
            label: label,
            arrangement: .control,
            trailing: {
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        )
    }

    private func fieldError(_ message: String) -> some View {
        Text(message)
            .font(.system(size: fieldErrorSize))
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
    }

    private func noticeCard(_ message: String, isError: Bool) -> some View {
        Text(message)
            .font(.system(size: noticeCardSize))
            .foregroundStyle(isError ? Color.red : .secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .subjectPanel()
    }

    // MARK: Notes

    private var nameNote: String {
        "The collection name is part of its web address. Use letters, numbers and underscores. "
            + "You can't change it after creating the collection."
    }

    private var preferencesNote: String {
        "You can turn on any combination of these settings. Unrevealed shows each work as "
            + "Mystery Work, Anonymous hides its creators, and new-item emails go to the contact email."
    }

    // MARK: Actions

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            Text(isNew ? "Create Collection" : "Save Changes")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .prominentLabel()
        .disabled(phase == .saving || !canSave)
    }

    /// AO3 rejects a nameless or titleless collection server-side and hands the
    /// whole form back, losing nothing but a round trip and the reader's patience.
    /// Checking here is the cheaper half of the same rule.
    private var canSave: Bool {
        guard let form else { return false }
        let hasTitle = !form.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasName = !form.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasTitle && hasName && nameAvailability != .taken && nameAvailability != .invalid
    }

    /// Closing remains on AO3; deletion is shown only when the fetched form carries
    /// AO3's owner-only delete control.
    private var openOnAO3Card: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Collection actions")
                .font(.system(size: actionTitleSize, weight: .semibold))
            Text("Open AO3 to close this collection. Deleting the collection leaves its works on AO3.")
                .font(.system(size: noticeCardSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let slug {
                Button("Open Collection Settings on AO3") {
                    router.open(AO3CollectionURL.edit(slug: slug))
                }
                    .buttonStyle(.borderless)
                    .font(.system(size: actionButtonSize, weight: .semibold))
                if AO3CollectionDeleteDecision.canStart(
                    allowsDelete: form?.allowsDelete == true,
                    isDeleting: false,
                    isSaving: false
                ) {
                    Button("Delete Collection", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                        .buttonStyle(.borderless)
                        .font(.system(size: actionButtonSize, weight: .semibold))
                        .disabled(phase == .saving || isDeleting)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .subjectPanel()
    }

    // MARK: Loading and saving

    private func loadForm() async {
        phase = .loading
        let generation = auth.sessionGeneration
        let username = auth.username
        do {
            let loaded = if let slug {
                try await auth.collectionEditForm(slug: slug)
            } else {
                try await auth.collectionNewForm()
            }
            // Fetched under an account that has since changed: not this
            // session's form to fill in.
            guard generation == auth.sessionGeneration else {
                phase = .failed("Your AO3 session changed while the form was loading.")
                return
            }
            form = loaded
            formGeneration = generation
            formUsername = username
            phase = .ready
        } catch let error as AO3Error {
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch {
            phase = .failed(UserFacingError.message(for: error))
        }
    }

    private func save() async {
        // Set with `form` in `loadForm`.
        guard let loaded = formGeneration else { return }
        let generation = AO3CollectionSessionReload.formSaveGeneration(
            loaded: loaded, loadedUsername: formUsername,
            current: auth.sessionGeneration, currentUsername: auth.username
        )
        formGeneration = generation
        // This attempt reports its own errors; AO3 re-sends any that still apply.
        form?.generalErrors = []
        guard let current = form else { return }
        phase = .saving
        saveMessage = nil
        do {
            let outcome: AO3CollectionSaveOutcome
            if let slug {
                outcome = try await auth.updateCollection(
                    slug: slug, form: current, expectedGeneration: generation
                )
            } else {
                outcome = try await auth.createCollection(current, expectedGeneration: generation)
            }
            switch outcome {
            case let .saved(message, savedForm):
                form = savedForm
                saveMessage = message
                phase = .ready
            case let .invalid(returned):
                // AO3 hands the whole form back on failure with its errors attached,
                // which is why the edit is never discarded here.
                form = returned
                phase = .ready
            }
        } catch is CancellationError {
            saveFailed(
                "Not saved: your AO3 session changed since this form opened. Your edits are still "
                    + "here, and Save works again once \(formUsername ?? "that account") is signed in. "
                    + "To edit as another account, reopen the form."
            )
        } catch let error as AO3CollectionWriteError {
            saveFailed(error.errorDescription ?? "The collection could not be saved.")
        } catch {
            saveFailed(UserFacingError.message(for: error))
        }
    }

    /// Inline, over the fields as typed. The failed screen's Try Again reloads
    /// AO3's copy, which would throw every unsaved edit away.
    private func saveFailed(_ message: String) {
        form?.generalErrors = [message]
        phase = .ready
    }

    /// Availability is one request per settled name, not per keystroke. AO3 has to
    /// be asked because the name is the address and it collides server-side, but
    /// asking on every character would be the rudest thing this screen could do.
    private func scheduleNameCheck(_ name: String) {
        nameCheckTask?.cancel()
        nameAvailability = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isNew, !trimmed.isEmpty else { return }
        guard AO3Client.collectionNameFormatIsValid(trimmed) else {
            nameAvailability = .invalid
            return
        }
        nameCheckTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            let result = try? await AO3Client.shared.collectionNameAvailable(trimmed)
            guard !Task.isCancelled else { return }
            nameAvailability = result
        }
    }
}

// Out of the struct body only for its length; `private` state is file-scoped.
extension AO3CollectionFormView {
    private func deleteCollection() async {
        guard AO3CollectionDeleteDecision.canStart(
            allowsDelete: form?.allowsDelete == true,
            isDeleting: isDeleting,
            isSaving: phase == .saving
        ),
              let slug, let loaded = formGeneration else { return }
        isDeleting = true
        defer { isDeleting = false }
        let generation = AO3CollectionSessionReload.formSaveGeneration(
            loaded: loaded, loadedUsername: formUsername,
            current: auth.sessionGeneration, currentUsername: auth.username
        )
        formGeneration = generation
        phase = .saving
        do {
            _ = try await auth.deleteCollection(slug: slug, expectedGeneration: generation)
            // The collection is gone whoever is signed in now, so the form
            // always closes; only the same account's list drops the row.
            if let formUsername,
               auth.username?.caseInsensitiveCompare(formUsername) == .orderedSame {
                NotificationCenter.default.post(name: .ao3CollectionDeleted, object: slug)
            }
            if let onDeleted {
                onDeleted()
            } else {
                dismiss()
            }
        } catch is CancellationError {
            saveFailed("Not deleted: your AO3 session changed since this form opened.")
        } catch let error as AO3CollectionWriteError {
            saveFailed(error.errorDescription ?? "The collection could not be deleted.")
        } catch {
            saveFailed(UserFacingError.message(for: error))
        }
    }
}

extension AO3CollectionFormView {
    /// 1bl's alert body, verbatim in substance: what goes, what stays, and
    /// what the deletion reveals about other people's works.
    static let deletionMessage = "This removes the collection, its challenge settings and any gift assignments "
        + "from AO3. The works stay with their creators. Unrevealed works become visible, and anonymous works "
        + "show their creators. Type the collection name to confirm."

    static func confirmsDeletion(typed: String, name: String) -> Bool {
        let typed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return !typed.isEmpty && typed == name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
