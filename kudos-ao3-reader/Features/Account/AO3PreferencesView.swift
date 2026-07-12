import SwiftUI

/// Native editor for the signed-in user's AO3 Preferences (the form at
/// `/users/:login/preferences`). Loads live field values from AO3, edits them
/// in-app, and saves with a single authenticated write. Account-security pages
/// (password, email, username) remain one-tap web links. Section/field `?`
/// controls open AO3's matching help content in a sheet.
struct AO3PreferencesView: View {
    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var themeManager

    @State private var snapshot: AO3PreferencesSnapshot?
    @State private var phase: Phase = .loading
    @State private var isSaving = false
    @State private var banner: Banner?
    @State private var hasEdits = false
    @State private var helpSheet: HelpSheetState?

    private enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private enum Banner: Equatable {
        case success(String)
        case error(String)
    }

    private struct HelpSheetState: Identifiable, Equatable {
        enum Content: Equatable {
            case loading(title: String)
            case ready(AO3PreferenceHelpContent)
            case failed(title: String, message: String)
        }

        let ref: AO3PreferenceHelpRef
        var content: Content

        var id: String { ref.id }
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView("Loading preferences…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView {
                    Label("Couldn't load preferences", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            case .ready:
                if let snapshot {
                    formContent(snapshot)
                }
            }
        }
        .navigationTitle("My Preferences")
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save")
                    }
                }
                .disabled(isSaving || phase != .ready || !hasEdits)
            }
        }
        .sheet(item: $helpSheet) { state in
            helpSheetView(state)
        }
        .task { await load() }
    }

    @ViewBuilder
    private func formContent(_ snapshot: AO3PreferencesSnapshot) -> some View {
        Form {
            if let banner {
                Section {
                    switch banner {
                    case let .success(message):
                        Label(message, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case let .error(message):
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }

            ForEach(Array(snapshot.sections.enumerated()), id: \.element.id) { sectionIndex, section in
                Section {
                    ForEach(Array(section.toggles.enumerated()), id: \.element.id) { toggleIndex, toggle in
                        preferenceToggleRow(
                            label: toggle.label,
                            isOn: bindingToggle(section: sectionIndex, toggle: toggleIndex),
                            help: toggle.help
                        )
                    }
                } header: {
                    sectionHeader(title: section.title, help: section.help)
                }
            }

            if !snapshot.selects.isEmpty || !snapshot.textFields.isEmpty {
                Section {
                    ForEach(Array(snapshot.selects.enumerated()), id: \.element.id) { index, select in
                        HStack(alignment: .center, spacing: 8) {
                            Picker(select.label, selection: bindingSelect(index)) {
                                ForEach(select.options) { option in
                                    Text(option.title).tag(option.value)
                                }
                            }
                            #if os(iOS)
                            .pickerStyle(.navigationLink)
                            #endif
                            if let help = select.help {
                                helpButton(help)
                            }
                        }
                    }
                    ForEach(Array(snapshot.textFields.enumerated()), id: \.element.id) { index, field in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(field.label)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 4)
                                if let help = field.help {
                                    helpButton(help)
                                }
                            }
                            TextField(field.label, text: bindingText(index))
                            #if os(iOS)
                                .textInputAutocapitalization(.never)
                            #endif
                                .autocorrectionDisabled()
                        }
                    }
                } header: {
                    Text("Display options")
                }
            }

        }
        .formStyle(.grouped)
        .appThemedScroll()
        .appThemedRows()
    }

    @ViewBuilder
    private func sectionHeader(title: String, help: AO3PreferenceHelpRef?) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            if let help {
                helpButton(help)
            }
        }
        // Keep header controls tappable inside List/Form.
        .textCase(nil)
    }

    @ViewBuilder
    private func preferenceToggleRow(
        label: String,
        isOn: Binding<Bool>,
        help: AO3PreferenceHelpRef?
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Toggle(isOn: isOn) {
                Text(label)
            }
            if let help {
                helpButton(help)
            }
        }
    }

    private func helpButton(_ help: AO3PreferenceHelpRef) -> some View {
        Button {
            openHelp(help)
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(help.title)
        .accessibilityHint("Shows help for this preference")
    }

    @ViewBuilder
    private func helpSheetView(_ state: HelpSheetState) -> some View {
        NavigationStack {
            Group {
                switch state.content {
                case .loading:
                    ProgressView("Loading help…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .ready(content):
                    helpContentList(content)
                case let .failed(_, message):
                    ContentUnavailableView {
                        Label("Couldn't load help", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") { openHelp(state.ref) }
                        Button("Open on AO3") { router.open(state.ref.url) }
                    }
                }
            }
            .navigationTitle(helpSheetTitle(state))
            #if os(iOS)
            .toolbarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { helpSheet = nil }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground {
            // Match Account / Library card lists instead of a bare system sheet.
            themeManager.appTheme.cardBackdrop
                .ignoresSafeArea()
        }
        #endif
    }

    @ViewBuilder
    private func helpContentList(_ content: AO3PreferenceHelpContent) -> some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Text(content.title)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "questionmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
                .cardRow()
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(content.title)
            }

            Section {
                ForEach(content.entries) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.heading)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !entry.body.isEmpty {
                            Text(entry.body)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardRow()
                }
            }

            if let footer = content.footer, !footer.isEmpty {
                Section {
                    Text(footer)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .cardRow()
                }
            }
        }
        .cardList()
    }

    private func helpSheetTitle(_ state: HelpSheetState) -> String {
        switch state.content {
        case let .loading(title), let .failed(title, _):
            return title
        case let .ready(content):
            return content.title
        }
    }

    // MARK: Bindings

    private func bindingToggle(section: Int, toggle: Int) -> Binding<Bool> {
        Binding(
            get: {
                guard let snapshot,
                      snapshot.sections.indices.contains(section),
                      snapshot.sections[section].toggles.indices.contains(toggle)
                else { return false }
                return snapshot.sections[section].toggles[toggle].isOn
            },
            set: { newValue in
                guard var snapshot else { return }
                guard snapshot.sections.indices.contains(section),
                      snapshot.sections[section].toggles.indices.contains(toggle)
                else { return }
                snapshot.sections[section].toggles[toggle].isOn = newValue
                self.snapshot = snapshot
                hasEdits = true
                banner = nil
            }
        )
    }

    private func bindingSelect(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard let snapshot, snapshot.selects.indices.contains(index)
                else { return "" }
                return snapshot.selects[index].selectedValue
            },
            set: { newValue in
                guard var snapshot, snapshot.selects.indices.contains(index) else { return }
                snapshot.selects[index].selectedValue = newValue
                self.snapshot = snapshot
                hasEdits = true
                banner = nil
            }
        )
    }

    private func bindingText(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard let snapshot, snapshot.textFields.indices.contains(index)
                else { return "" }
                return snapshot.textFields[index].value
            },
            set: { newValue in
                guard var snapshot, snapshot.textFields.indices.contains(index) else { return }
                snapshot.textFields[index].value = newValue
                self.snapshot = snapshot
                hasEdits = true
                banner = nil
            }
        )
    }

    // MARK: Load / save / help

    private func openHelp(_ ref: AO3PreferenceHelpRef) {
        helpSheet = HelpSheetState(ref: ref, content: .loading(title: ref.title))
        Task {
            do {
                let content = try await auth.loadPreferenceHelp(ref)
                if helpSheet?.ref == ref {
                    helpSheet = HelpSheetState(ref: ref, content: .ready(content))
                }
            } catch {
                if helpSheet?.ref == ref {
                    helpSheet = HelpSheetState(
                        ref: ref,
                        content: .failed(
                            title: ref.title,
                            message: error.localizedDescription
                        )
                    )
                }
            }
        }
    }

    private func load() async {
        phase = .loading
        banner = nil
        hasEdits = false
        do {
            snapshot = try await auth.loadPreferences()
            phase = .ready
        } catch AO3Error.authenticationRequired {
            phase = .failed("Your AO3 session expired. Sign in again from Account.")
            await auth.sessionDidExpire()
        } catch let error as AO3Error {
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch let error as AO3WriteError {
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func save() async {
        guard let snapshot else { return }
        isSaving = true
        banner = nil
        defer { isSaving = false }
        do {
            let message = try await auth.savePreferences(snapshot)
            hasEdits = false
            banner = .success(message)
            if let refreshed = try? await auth.loadPreferences() {
                self.snapshot = refreshed
            }
        } catch AO3Error.authenticationRequired {
            banner = .error("Your AO3 session expired. Sign in again from Account.")
            await auth.sessionDidExpire()
        } catch let error as AO3WriteError {
            banner = .error(error.errorDescription ?? "Couldn't save preferences.")
        } catch let error as AO3Error {
            banner = .error(error.errorDescription ?? "Couldn't save preferences.")
        } catch {
            banner = .error(error.localizedDescription)
        }
    }
}
