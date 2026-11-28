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
    @ScaledMetric(relativeTo: .footnote) private var retryButtonSize: CGFloat = 14
    @ScaledMetric(relativeTo: .footnote) private var bannerTextSize: CGFloat = 14
    @ScaledMetric(relativeTo: .caption) private var footnoteSize: CGFloat = 11.5

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
                    .accentFill()
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
        .navigationTitle("AO3 Preferences")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().accentFill()
                    } else {
                        Text("Save")
                    }
                }
                .disabled(isSaving || phase != .ready || !hasEdits)
                .accessibilityLabel(isSaving ? "Saving preferences" : "Save")
            }
        }
        .sheet(item: $helpSheet) { state in
            helpSheetView(state)
        }
        .task { await load() }
        #if DEBUG
        .task {
            guard DebugLaunchRoute.takeSheet("prefhelp"),
                  let url = URL(string: "https://archiveofourown.org/help/preferences_privacy")
            else { return }
            openHelp(AO3PreferenceHelpRef(title: "Privacy", url: url))
        }
        #endif
    }

    @ViewBuilder
    private func formContent(_ snapshot: AO3PreferencesSnapshot) -> some View {
        List {
            let sections = Array(snapshot.sections.enumerated())
            ForEach(sections.filter { $0.element.title == "Display" }, id: \.element.id) { index, section in
                preferenceSection(section, at: index)
            }

            if !snapshot.selects.isEmpty || !snapshot.textFields.isEmpty {
                Section {
                    SubjectFieldLabel(text: "Your profile", style: .formGroup)
                        .pageBodyRow(top: 14, gutter: gutter)
                    VStack(spacing: 0) {
                        let selects = snapshot.selects.enumerated().sorted {
                            let first = AO3PreferencesBoardCopy.profileOrder($0.element.key)
                            let second = AO3PreferencesBoardCopy.profileOrder($1.element.key)
                            return first == second ? $0.offset < $1.offset : first < second
                        }
                        ForEach(selects, id: \.element.id) { index, select in
                            let title = AO3PreferencesBoardCopy.profileTitle(key: select.key, fallback: select.label)
                            if index != selects.first?.offset {
                                SubjectRowSeparator()
                            }
                            preferenceFormRow(title, icon: AO3PreferencesBoardCopy.symbol(for: title)) {
                                HStack(alignment: .center, spacing: 8) {
                                    // An empty label, not `.labelsHidden()`: the
                                    // navigation-link style ignores that and drew
                                    // "Your site skin" a second time beside the row's own.
                                    Picker(selection: bindingSelect(index)) {
                                        ForEach(select.options) { option in
                                            Text(option.title).tag(option.value)
                                        }
                                    } label: {
                                        EmptyView()
                                    }
                                    .accessibilityLabel(title)
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
                            let title = AO3PreferencesBoardCopy.profileTitle(key: field.key, fallback: field.label)
                            preferenceFormRow(title, icon: AO3PreferencesBoardCopy.symbol(for: title)) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    TextField(title, text: bindingText(index))
                                        .accessibilityLabel(title)
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
                    .pageBodyRow(top: 6, gutter: gutter)
                }
            }

            ForEach(sections.filter { $0.element.title != "Display" && $0.element.title != "Privacy" },
                    id: \.element.id) { index, section in
                preferenceSection(section, at: index)
            }
            ForEach(sections.filter { $0.element.title == "Privacy" }, id: \.element.id) { index, section in
                preferenceSection(section, at: index)
            }

            accountLinksSection

            Section {
                footnote.pageBodyRow(top: 10, gutter: gutter)
            }
        }
        .cardList()
        .subjectScreenWash(palette: accountPalette)
    }

    private func preferenceSection(_ section: AO3PreferenceSection, at index: Int) -> some View {
        let title = AO3PreferencesBoardCopy.sectionTitle(section)
        return Section {
            sectionHeader(title: title, id: section.id, help: section.help)
                .pageBodyRow(top: 14, gutter: gutter)
            if !collapsedSectionTitles.contains(section.id) {
                VStack(spacing: 0) {
                    let ordered = section.toggles.enumerated().sorted {
                        let first = AO3PreferencesBoardCopy.readingOrder($0.element)
                        let second = AO3PreferencesBoardCopy.readingOrder($1.element)
                        return first == second ? $0.offset < $1.offset : first < second
                    }
                    ForEach(ordered, id: \.element.id) { toggleIndex, toggle in
                        if toggleIndex != ordered.first?.offset {
                            SubjectRowSeparator()
                        }
                        preferenceToggleRow(
                            label: AO3PreferencesBoardCopy.toggleTitle(toggle),
                            key: toggle.key,
                            isOn: bindingToggle(section: index, toggle: toggleIndex),
                            help: toggle.help
                        )
                    }
                }
                .subjectPanel()
                .pageBodyRow(top: 6, gutter: gutter)

                if title == "Notifications by email" {
                    Text("These are AO3’s own settings, saved to your AO3 account. Kudos never sends email.")
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .pageBodyRow(top: 6, gutter: gutter)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(title: String, id: String, help: AO3PreferenceHelpRef?) -> some View {
        let isCollapsed = collapsedSectionTitles.contains(id)
        return HStack(spacing: 8) {
            SubjectFieldLabel(text: title, style: .formGroup)
            Spacer(minLength: 8)
            if let help {
                helpButton(help)
            }
            Button {
                if isCollapsed {
                    collapsedSectionTitles.remove(id)
                } else {
                    collapsedSectionTitles.insert(id)
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
        key: String,
        isOn: Binding<Bool>,
        help: AO3PreferenceHelpRef?
    ) -> some View {
        let symbol = AO3PreferencesBoardCopy.symbol(for: label, key: key)
        preferenceFormRow(label, icon: symbol) {
            HStack(alignment: .center, spacing: 8) {
                Toggle(label, isOn: isOn)
                    .labelsHidden()
                    .accentFill()
                if let help {
                    helpButton(help)
                }
            }
        }
    }

    private func preferenceFormRow<Control: View>(
        _ title: String, icon: String?, @ViewBuilder control: @escaping () -> Control
    ) -> some View {
        HStack(spacing: 0) {
            if let icon {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.accentInk)
                    .frame(width: 24, height: 24)
                    .background(themeManager.appTheme.nestedCardSurface, in: RoundedRectangle(cornerRadius: 6))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .padding(.leading, 14)
                    .accessibilityHidden(true)
            }
            SubjectFormRow(label: title, arrangement: .value) {
                control()
            }
        }
    }

    private func helpButton(_ help: AO3PreferenceHelpRef) -> some View {
        Button {
            openHelp(help)
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.body)
                .foregroundStyle(.secondaryInk)
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
                        .accentFill()
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
                    .sheetConfirmStyle()
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
        // No title card: the sheet's own title is the same words (`helpSheetTitle`), and a
        // second copy with a "?" pushed the help itself below the fold.
        List {
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
                                .foregroundStyle(.secondaryInk)
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
                        .foregroundStyle(.secondaryInk)
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
                            message: UserFacingError.message(for: error)
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
            phase = .failed(UserFacingError.message(for: error))
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
            banner = .error(UserFacingError.message(for: error))
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
                    Button("Try Again") { Task { await save() } }
                        .font(.system(size: retryButtonSize, weight: .semibold))
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
                .font(.system(size: bannerTextSize, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 44)
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
        Text("These preferences are saved to your AO3 account and follow you on AO3. "
            + "Settings that affect only Kudos are under Settings.")
            .font(.system(size: footnoteSize))
            .foregroundStyle(.secondaryInk)
            .lineSpacing(1.5)
    }

    /// Artboard 1z's own header, at the 16pt account gutter every subsection uses.
    /// 1z opens with an Account group of links to the AO3 pages this app does
    /// not implement natively.
    ///
    /// All seven of its rows. Blocked users and Muted users were once left out
    /// because `/users/<name>/blocked` and `/muted` answered 404 — those are not
    /// routes. otwarchive nests both as `blocked/users` and `muted/users` under the
    /// user (`config/routes.rb`, index only, owner or admin; otwarchive-facts-wave3
    /// Q16). Like the rest of this group they show no counts: the preferences page
    /// carries none.
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
                SubjectRowSeparator()
                AccountExternalNavCard(
                    title: "Blocked users",
                    systemImage: "hand.raised",
                    pathSuffix: "blocked/users",
                    isFormRow: true
                )
                SubjectRowSeparator()
                AccountExternalNavCard(
                    title: "Muted users",
                    systemImage: "speaker.slash",
                    pathSuffix: "muted/users",
                    isFormRow: true
                )
            }
            .subjectPanel()
            .pageBodyRow(top: 8, gutter: gutter)
        }
    }

    private var accountPalette: SubjectPalette {
        themeManager.scopePalette
    }

    private var gutter: CGFloat { SubjectMetrics.accountGutter }
}

/// Display labels for known fields. The parsed fields and their original indexes
/// continue to own every binding, help link and submitted value.
enum AO3PreferencesBoardCopy {
    static func sectionTitle(_ section: AO3PreferenceSection) -> String {
        switch section.title {
        case "Display": return "Reading on AO3"
        case "Privacy": return "Privacy on AO3"
        default:
            let emailKeys: Set<String> = ["comment_emails_off", "kudos_emails_off"]
            if !section.toggles.isEmpty && section.toggles.allSatisfy({ emailKeys.contains($0.key) }) {
                return "Notifications by email"
            }
            return section.title
        }
    }

    static func toggleTitle(_ toggle: AO3PreferenceToggle) -> String {
        switch toggle.key {
        case "adult": "Show adult content without asking"
        case "hide_warnings": "Hide warnings"
        case "view_full_works": "Show whole work by default"
        default: toggle.label == "Hide additional tags." ? "Hide additional tags" : toggle.label
        }
    }

    static func readingOrder(_ toggle: AO3PreferenceToggle) -> Int {
        switch toggleTitle(toggle) {
        case "Show adult content without asking": 0
        case "Hide warnings": 1
        case "Hide additional tags": 2
        case "Show whole work by default": 3
        default: 4
        }
    }

    static func symbol(for label: String, key: String = "") -> String? {
        switch label {
        case "Show adult content without asking": return "eye"
        case "Hide warnings": return "exclamationmark.triangle"
        case "Hide additional tags": return "tag"
        case "Show whole work by default": return "book"
        case "Time zone": return "globe"
        case "Skin": return "paintpalette"
        case "Browser title": return "textformat"
        default: break
        }
        return switch key {
        case "comment_emails_off": "bubble"
        case "kudos_emails_off": "heart"
        default: nil
        }
    }

    static func profileTitle(key: String, fallback: String) -> String {
        switch key {
        case "time_zone": "Time zone"
        case "skin_id": "Skin"
        case "work_title_format": "Browser title"
        default: fallback
        }
    }

    static func profileOrder(_ key: String) -> Int {
        switch key {
        case "time_zone": 0
        case "skin_id": 1
        default: 2
        }
    }
}
