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
    /// 1z's section disclosure chevrons. Kept in memory only, not
    /// `@AppStorage`: AO3's own preference-page headings ("Privacy",
    /// "Skins", …) are parsed text, not a fixed set this app owns — a
    /// per-title persisted key would survive AO3 renaming or reordering
    /// them and collect stale entries forever. Collapsed by title, so a
    /// remount (pull to refresh) keeps what the reader had open or shut.
    @State private var collapsedSectionTitles: Set<String> = []

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
        // 1bb: the confirmation is "a transient toast above the tab bar — no
        // row-level spinner, no banner that pushes content down. It sits over
        // everything and leaves on its own." It used to be a row inside the list,
        // which is the one thing that board rules out.
        .overlay(alignment: .bottom) { toastOverlay }
        #if os(macOS)
        .navigationTitle("My Preferences")
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
        List {
            Section {
                header.pageBodyRow(top: 20, gutter: selfGuttered)
            }

            accountLinksSection

            ForEach(Array(snapshot.sections.enumerated()), id: \.element.id) { sectionIndex, section in
                Section {
                    sectionHeader(title: section.title, help: section.help)
                        .pageBodyRow(top: 18, gutter: gutter)
                    if !collapsedSectionTitles.contains(section.title) {
                        VStack(spacing: 0) {
                            ForEach(Array(section.toggles.enumerated()), id: \.element.id) { toggleIndex, toggle in
                                if toggleIndex > 0 {
                                    SubjectRowSeparator()
                                }
                                preferenceToggleRow(
                                    label: toggle.label,
                                    isOn: bindingToggle(section: sectionIndex, toggle: toggleIndex),
                                    help: toggle.help
                                )
                            }
                        }
                        .subjectPanel()
                        .pageBodyRow(top: 8, gutter: gutter)
                    }
                }
            }

            if !snapshot.selects.isEmpty || !snapshot.textFields.isEmpty {
                Section {
                    SubjectFieldLabel(text: "Display options", style: .formGroup)
                        .pageBodyRow(top: 18, gutter: gutter)
                    VStack(spacing: 0) {
                        ForEach(Array(snapshot.selects.enumerated()), id: \.element.id) { index, select in
                            if index > 0 {
                                SubjectRowSeparator()
                            }
                            SubjectFormRow(label: select.label, arrangement: .value) {
                                HStack(alignment: .center, spacing: 8) {
                                    Picker(select.label, selection: bindingSelect(index)) {
                                        ForEach(select.options) { option in
                                            Text(option.title).tag(option.value)
                                        }
                                    }
                                    .labelsHidden()
                                    #if os(iOS)
                                    .pickerStyle(.navigationLink)
                                    #endif
                                    if let help = select.help {
                                        helpButton(help)
                                    }
                                }
                            }
                        }

                        ForEach(Array(snapshot.textFields.enumerated()), id: \.element.id) { index, field in
                            if !snapshot.selects.isEmpty || index > 0 {
                                SubjectRowSeparator()
                            }
                            SubjectFormRow(label: field.label, arrangement: .value) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    TextField(field.label, text: bindingText(index))
                                        .multilineTextAlignment(.trailing)
                                    #if os(iOS)
                                        .textInputAutocapitalization(.never)
                                    #endif
                                        .autocorrectionDisabled()
                                    if let help = field.help {
                                        helpButton(help)
                                    }
                                }
                            }
                        }
                    }
                    .subjectPanel()
                    .pageBodyRow(top: 8, gutter: gutter)
                }
            }

            Section {
                footnote.pageBodyRow(top: 10, gutter: gutter)
            }
        }
        .cardList()
        .subjectScreenWash(palette: accountPalette)
    }

    @ViewBuilder
    private func sectionHeader(title: String, help: AO3PreferenceHelpRef?) -> some View {
        let isCollapsed = collapsedSectionTitles.contains(title)
        return HStack(spacing: 8) {
            SubjectFieldLabel(text: title, style: .formGroup)
            Spacer(minLength: 8)
            if let help {
                helpButton(help)
            }
            Button {
                if isCollapsed {
                    collapsedSectionTitles.remove(title)
                } else {
                    collapsedSectionTitles.insert(title)
                }
            } label: {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .minimumHitTarget()
            .accessibilityLabel(isCollapsed ? "Expand \(title)" : "Collapse \(title)")
        }
    }

    @ViewBuilder
    private func preferenceToggleRow(
        label: String,
        isOn: Binding<Bool>,
        help: AO3PreferenceHelpRef?
    ) -> some View {
        SubjectFormRow(label: label, arrangement: .value) {
            HStack(alignment: .center, spacing: 8) {
                Toggle(label, isOn: isOn)
                    .labelsHidden()
                if let help {
                    helpButton(help)
                }
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
                .frame(minWidth: 44, minHeight: 44)
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
                    Button { helpSheet = nil } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Done")
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
        let expectedSessionGeneration = auth.sessionGeneration
        phase = .loading
        banner = nil
        hasEdits = false
        do {
            let loadedSnapshot = try await auth.loadPreferences()
            guard auth.sessionGeneration == expectedSessionGeneration else { return }
            snapshot = loadedSnapshot
            phase = .ready
        } catch AO3Error.authenticationRequired {
            guard auth.sessionGeneration == expectedSessionGeneration else { return }
            phase = .failed("Your AO3 session expired. Sign in again from Account.")
            await auth.sessionDidExpire(expectedGeneration: expectedSessionGeneration)
        } catch let error as AO3Error {
            guard auth.sessionGeneration == expectedSessionGeneration else { return }
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch let error as AO3WriteError {
            guard auth.sessionGeneration == expectedSessionGeneration else { return }
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch {
            guard auth.sessionGeneration == expectedSessionGeneration else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private func save() async {
        guard let snapshot else { return }
        let expectedSessionGeneration = auth.sessionGeneration
        isSaving = true
        banner = nil
        defer { isSaving = false }
        do {
            let message = try await auth.savePreferences(snapshot)
            guard auth.sessionGeneration == expectedSessionGeneration else { return }
            hasEdits = false
            banner = .success(message)
            if let refreshed = try? await auth.loadPreferences() {
                guard auth.sessionGeneration == expectedSessionGeneration else { return }
                self.snapshot = refreshed
            }
        } catch AO3Error.authenticationRequired {
            guard auth.sessionGeneration == expectedSessionGeneration else { return }
            banner = .error("Your AO3 session expired. Sign in again from Account.")
            await auth.sessionDidExpire(expectedGeneration: expectedSessionGeneration)
        } catch let error as AO3WriteError {
            guard auth.sessionGeneration == expectedSessionGeneration else { return }
            banner = .error(error.errorDescription ?? "Couldn't save preferences.")
        } catch let error as AO3Error {
            guard auth.sessionGeneration == expectedSessionGeneration else { return }
            banner = .error(error.errorDescription ?? "Couldn't save preferences.")
        } catch {
            guard auth.sessionGeneration == expectedSessionGeneration else { return }
            banner = .error(error.localizedDescription)
        }
    }
}

// MARK: - 1z page furniture

extension AO3PreferencesView {
    /// Floats over the content and clears itself. A success leaves on its own —
    /// 1bb's "leaves on its own" — while a failure stays until it is dismissed or
    /// retried, because a save that did not happen is not something to let slide
    /// past unread.
    @ViewBuilder
    private var toastOverlay: some View {
        if let banner {
            HStack(spacing: 10) {
                bannerView(banner)
                if !bannerIsSuccess(banner) {
                    Button("Retry") { Task { await save() } }
                        .font(.system(size: 14, weight: .semibold))
                        .disabled(isSaving)
                }
            }
            .padding(.horizontal, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(themeManager.appTheme.glassStroke(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: bannerToastID) {
                guard bannerIsSuccess(banner) else { return }
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                withAnimation { self.banner = nil }
            }
            .accessibilityAddTraits(.isStaticText)
        }
    }

    /// Restarts the dismissal timer when a second save replaces the first toast,
    /// rather than letting the original timer clear the new one early.
    private var bannerToastID: String {
        switch banner {
        case let .success(text): "success:\(text)"
        case let .error(text): "error:\(text)"
        case nil: "none"
        }
    }

    private func bannerView(_ banner: Banner) -> some View {
        HStack(spacing: 9) {
            Image(systemName: bannerIsSuccess(banner) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(bannerIsSuccess(banner) ? Color.green : Color.red)
            Text(bannerText(banner))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(
            Capsule()
                .fill(themeManager.appTheme.glassFill(0.86))
                .overlay(Capsule().strokeBorder(themeManager.appTheme.glassStroke(0.14), lineWidth: 0.5))
                .shadow(color: Color.black.opacity(0.5), radius: 14, y: 5)
        )
    }

    private func bannerIsSuccess(_ banner: Banner) -> Bool {
        if case .success = banner { return true }
        return false
    }

    private func bannerText(_ banner: Banner) -> String {
        switch banner {
        case .success(let msg): return msg
        case .error(let msg): return msg
        }
    }

    private var footnote: some View {
        Text("Every switch here is a field on AO3’s own preferences form, in AO3’s own "
            + "groups. App-only settings live in Settings.")
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .lineSpacing(1.5)
    }

    /// Artboard 1z's own header, at the 16pt account gutter every subsection uses.
    /// 1z opens with an Account group of links to the AO3 pages this app does
    /// not implement natively.
    ///
    /// Five of its seven rows are here. Blocked users and Muted users are not:
    /// `/users/<name>/blocked` and `/muted` both answer 404 unauthenticated, and
    /// so do their `/index` variants — which is genuinely ambiguous, because
    /// `/change_password` *redirects* to login rather than 404ing, so a 404 here
    /// may mean "not your account" rather than "no such page". Every row that is
    /// here was confirmed to exist by probe; a row that drops someone on a 404
    /// in Browse is worse than a row that is missing.
    @ViewBuilder
    private var accountLinksSection: some View {
        Section {
            SubjectFieldLabel(text: "Account", style: .formGroup)
                .pageBodyRow(top: 18, gutter: gutter)
            VStack(spacing: 0) {
                AccountExternalNavCard(
                    title: "Edit profile",
                    systemImage: "person.text.rectangle",
                    pathSuffix: "profile/edit",
                    isFormRow: true
                )
                SubjectRowSeparator()
                AccountExternalNavCard(
                    title: "Manage pseuds",
                    systemImage: "person.2",
                    pathSuffix: "pseuds",
                    isFormRow: true
                )
                SubjectRowSeparator()
                AccountExternalNavCard(
                    title: "Change username",
                    systemImage: "at",
                    pathSuffix: "change_username",
                    isFormRow: true
                )
                SubjectRowSeparator()
                AccountExternalNavCard(
                    title: "Change password",
                    systemImage: "key",
                    pathSuffix: "change_password",
                    isFormRow: true
                )
                SubjectRowSeparator()
                AccountExternalNavCard(
                    title: "Change email",
                    systemImage: "envelope",
                    pathSuffix: "change_email",
                    isFormRow: true
                )
            }
            .subjectPanel()
            .pageBodyRow(top: 8, gutter: gutter)
        }
    }

    private var header: some View {
        SubjectHeaderBlock(
            kicker: "AO3 Account",
            title: "AO3 Preferences",
            subtitle: "Stored on AO3 · applies everywhere you read",
            palette: accountPalette,
            gutter: SubjectMetrics.accountGutter
        )
    }

    private var accountPalette: SubjectPalette {
        themeManager.scopePalette
    }

    private var gutter: CGFloat { SubjectMetrics.accountGutter }

    /// For a block that pads itself — here the header block at its own gutter.
    private var selfGuttered: CGFloat { 0 }
}
