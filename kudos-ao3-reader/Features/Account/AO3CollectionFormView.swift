import SwiftUI

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
/// **Closing and deleting stay on AO3.** Neither is reversible from the app, and
/// the spec says so too. Both open the website rather than being offered here as a
/// button that cannot be undone.
struct AO3CollectionFormView: View {
    /// Editing an existing collection, or creating one.
    let slug: String?

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var form: AO3CollectionForm?
    @State private var phase: Phase = .idle
    @State private var saveMessage: String?
    @State private var nameAvailability: AO3CollectionNameAvailability?
    @State private var nameCheckTask: Task<Void, Never>?

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
    }

    // MARK: Header

    private var header: some View {
        SubjectHeaderBlock(
            kicker: "AO3 Account › Collections",
            title: isNew ? "New collection" : "Edit collection",
            subtitle: "Every row is a field on AO3's own form",
            palette: palette,
            gutter: SubjectMetrics.accountGutter
        )
    }

    private var palette: SubjectPalette {
        theme.appTheme.subjectPalette(hue: theme.scopeHue)
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
                    .font(.system(size: 12))
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
            .font(.system(size: 11.5))
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
    }

    private func noticeCard(_ message: String, isError: Bool) -> some View {
        Text(message)
            .font(.system(size: 12.5))
            .foregroundStyle(isError ? Color.red : .secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .subjectPanel()
    }

    // MARK: Notes

    private var nameNote: String {
        "Collection name is used in the address — letters, numbers and underscores, and "
            + (isNew
                ? "AO3 locks it after creation."
                : "AO3 has locked it, so it cannot be changed here.")
    }

    private var preferencesNote: String {
        "These four are independent on AO3, so they are four switches rather than one "
            + "choice. Unrevealed shows works as Mystery Work; anonymous hides creators."
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

    /// Closing and deleting are irreversible from the app, so they leave for the
    /// website rather than being offered as a button here. Spec 1bl says the same.
    private var openOnAO3Card: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Closing and deleting stay on AO3")
                .font(.system(size: 15, weight: .semibold))
            Text("Neither can be undone from the app, so both open the website signed in.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let slug {
                Button("Open Collection Settings on AO3") {
                    router.open(AO3CollectionURL.edit(slug: slug))
                }
                    .buttonStyle(.borderless)
                    .font(.system(size: 13, weight: .semibold))
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
        do {
            if let slug {
                form = try await auth.collectionEditForm(slug: slug)
            } else {
                form = try await auth.collectionNewForm()
            }
            phase = .ready
        } catch let error as AO3Error {
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func save() async {
        guard let current = form else { return }
        phase = .saving
        saveMessage = nil
        do {
            let outcome: AO3CollectionSaveOutcome
            if let slug {
                outcome = try await auth.updateCollection(slug: slug, form: current)
            } else {
                outcome = try await auth.createCollection(current)
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
        } catch let error as AO3CollectionWriteError {
            phase = .failed(error.errorDescription ?? "The collection could not be saved.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
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
