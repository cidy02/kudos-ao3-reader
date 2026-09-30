import SwiftUI

/// Artboard **1cf** — Challenge settings (edit).
///
/// The maintainer's edit form for the same object `ChallengeSettingsView` (1by)
/// reads. Same collection/kind, same five dates, but here they are live fields:
/// load `AO3ChallengeSettingsForm`, mutate local copies of its fields, run
/// `.validated()` before posting, and surface `fieldErrors`/`generalErrors` the
/// way `ChallengeSignUpView` does for its own save — that screen is this
/// codebase's only existing example of an editable, validated AO3 form, so its
/// load/save/error shape is the one this view follows.
///
/// Name, Tagline, Introduction and FAQ are collection fields, read from the
/// collection's edit page and edited on 1cg (`AO3CollectionFormView`); the host
/// byline is not drawn because that page carries owner pseud ids, not names.
/// The moderation switches are collection preferences and save through the
/// collection form after the challenge form. Matching reads and posts AO3's
/// potential-match settings (see `ChallengeSettingsEditSections.swift`).
///
/// Matching itself (`potential_matches#generate`) and challenge deletion are not
/// client writes — AO3ChallengeActions never exposes them — so "Run matching"
/// and "Delete challenge" are Open-on-AO3 links, the second landing on the same
/// edit page a maintainer would delete a challenge from since
/// `AO3ChallengeURL` has no confirm-delete route for challenges the way it does
/// for sign-ups.
struct ChallengeSettingsEditView: View {
    let collectionSlug: String
    var collectionTitle: String = ""
    var viewerIsOwner: Bool

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(AppRouter.self) private var router

    @State var form: AO3ChallengeSettingsForm?
    /// The collection's own edit form (Basics, moderation switches), and the
    /// copy it loaded as, so Save posts it only when a switch changed.
    @State var collectionForm: AO3CollectionForm?
    @State var loadedCollectionForm: AO3CollectionForm?
    @State var collectionLoadFailed = false
    /// The AO3 session the collection form was read under.
    @State private var loadedGeneration: Int?
    @State private var confirmReveal = false
    @State private var tagSetLinks: [AO3CollectionTagSetLink] = []
    /// The challenge's total, not page 1's count; `nil` leaves it out.
    @State private var signUpTotal: Int?
    @State private var phase: Phase = .idle
    @State private var loadGeneration = 0
    @State private var isSaving: Bool = false
    @State private var saveNotice: String?

    private enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var gutter: CGFloat { SubjectMetrics.accountGutter }
    private var selfGuttered: CGFloat { 0 }

    var palette: SubjectPalette {
        theme.appTheme.subjectPalette(
            hue: CoverArt.workHue(fandoms: [], title: effectiveTitle)
        )
    }

    private var effectiveTitle: String {
        collectionTitle.isEmpty ? collectionSlug : collectionTitle
    }

    var settings: AO3ChallengeSettings {
        form?.settings ?? AO3ChallengeSettings(collectionSlug: collectionSlug, kind: .giftExchange)
    }

    static func canStartSave(isSaving: Bool, hasForm: Bool) -> Bool {
        !isSaving && hasForm
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            List {
                Section {
                    header.pageBodyRow(top: 20, gutter: selfGuttered)
                }

                if let saveNotice {
                    Section {
                        noticeCard(saveNotice).pageBodyRow(top: 8, gutter: gutter)
                    }
                }

                if let generalErrors = form?.generalErrors, !generalErrors.isEmpty {
                    Section {
                        ForEach(generalErrors, id: \.self) { error in
                            errorCard(error).pageBodyRow(top: 6, gutter: gutter)
                        }
                    }
                }

                switch phase {
                case .loading:
                    Section {
                        loadingRow.pageBodyRow(top: 20, gutter: gutter)
                    }
                case let .failed(message):
                    Section {
                        failureCard(message).pageBodyRow(top: 14, gutter: gutter)
                    }
                case .idle, .loaded:
                    contentSections
                }

                Section {
                    Spacer(minLength: 75)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .cardList()
            // Rows at their own padding, not the List minimum (L3-FORM-1).
            .environment(\.defaultMinListRowHeight, 0)
            #if os(macOS)
            .navigationTitle("Challenge settings")
            #endif
            .subjectScreenWash(palette: palette)

            bottomActionBar
        }
        .task(id: auth.sessionGeneration) { await load() }
        .refreshable { await load() }
        .alert("Reveal now?", isPresented: $confirmReveal) {
            Button("Save and reveal", role: .destructive) {
                Task { await save() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Turning off Unrevealed shows this collection's works to everyone, and turning off "
                + "Anonymous shows their creators. The app can't hide them again.")
        }
            .screenTint(palette)
    }

    // MARK: - Header

    private var kicker: String {
        switch settings.kind {
        case .giftExchange: "Gift exchange · moderator"
        case .promptMeme: "Prompt meme · moderator"
        }
    }

    private var header: some View {
        SubjectHeaderBlock(
            kicker: kicker,
            title: "Challenge settings",
            subtitle: signUpTotal.map { "\(effectiveTitle) · \(AO3ChallengeCountText.plural($0, "sign-up"))" }
                ?? effectiveTitle,
            palette: palette,
            gutter: SubjectMetrics.accountGutter
        )
    }

    // MARK: - Content Sections

    @ViewBuilder
    private var contentSections: some View {
        Section {
            SectionRuleHeader(title: "Basics")
                .padding(.bottom, 8)
                .pageBodyRow(top: 18, gutter: selfGuttered)
        }
        Section {
            basicsRows
            instructionsCard.pageBodyRow(top: 12, gutter: gutter)
        }

        Section {
            SectionRuleHeader(title: "Schedule")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            ForEach(scheduleErrors, id: \.self) { message in
                errorCard(message).pageBodyRow(top: 6, gutter: gutter)
            }
            schedulePanel.pageBodyRow(top: 8, gutter: gutter)
            scheduleFootnote.pageBodyRow(top: 8, gutter: gutter)
        }

        Section {
            SectionRuleHeader(title: "Sign-up limits")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            ForEach(limitsErrors, id: \.self) { message in
                errorCard(message).pageBodyRow(top: 6, gutter: gutter)
            }
            limitsPanel.pageBodyRow(top: 8, gutter: gutter)
            SubjectFieldLabel(text: "Request restrictions", style: .formGroup)
                .pageBodyRow(top: 12, gutter: gutter)
            requestRestrictionTogglesPanel.pageBodyRow(top: 8, gutter: gutter)
            if restrictionControlsLocked {
                restrictionLockNote.pageBodyRow(top: 8, gutter: gutter)
            }
        }

        if !tagSetLinks.isEmpty {
            Section {
                SectionRuleHeader(title: tagSetLinks.count == 1 ? "Tag set" : "Tag sets")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                tagSetsPanel.pageBodyRow(top: 8, gutter: gutter)
            }
        }

        Section {
            SectionRuleHeader(title: "Matching")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            matchSettingsPanels
            SubjectFieldLabel(text: "Request fandoms", style: .formGroup)
                .pageBodyRow(top: 12, gutter: gutter)
            matchingPanel.pageBodyRow(top: 8, gutter: gutter)
            matchingFootnote.pageBodyRow(top: 8, gutter: gutter)
        }

        Section {
            SectionRuleHeader(title: "Anonymity and moderation")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            moderationPanel.pageBodyRow(top: 8, gutter: gutter)
        }

        Section {
            SectionRuleHeader(title: "At AO3")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            atAO3Panel.pageBodyRow(top: 8, gutter: gutter)
        }
    }

    // MARK: - Basics

    private var instructionsBinding: Binding<String> {
        Binding(
            get: { form?.settings.signupInstructionsGeneral ?? "" },
            set: { form?.settings.signupInstructionsGeneral = $0 }
        )
    }

    /// The challenge's own prose: AO3's "General Sign-up Instructions"
    /// (`signup_instructions_general`). The collection's Introduction is a
    /// different field, shown in the rows above.
    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            SubjectFieldLabel(text: "Sign-up instructions", style: .formGroup)

            ZStack(alignment: .topLeading) {
                if instructionsBinding.wrappedValue.isEmpty {
                    Text("Describe the challenge for people signing up…")
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                }

                TextEditor(text: instructionsBinding)
                    .font(.system(size: 14, design: .serif))
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
        }
        .padding(14)
        .subjectPanel()
    }

    // MARK: - Schedule

    private var scheduleErrors: [String] {
        guard let fieldErrors = form?.fieldErrors else { return [] }
        return ["signups_close_at", "assignments_due_at", "works_reveal_at", "authors_reveal_at"]
            .compactMap { fieldErrors[$0] }
    }

    /// AO3's form shows each date as a wall clock in the challenge's zone, and the
    /// picker edits those same digits: it runs in UTC because `wallClock` carries
    /// them as UTC. A missing date says so; it is never filled in with today.
    private func dateRow(label: String, keyPath: WritableKeyPath<AO3ChallengeSettings, AO3ChallengeInstant>) -> some View {
        let instant = settings[keyPath: keyPath]
        return SubjectFormRow(label: label, arrangement: .control) {
            if !settings.scheduleIsEditable {
                Text(instant.wireString.isEmpty ? "Not set" : instant.wireString)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else if let wallClock = instant.wallClock {
                DatePicker("", selection: Binding(
                    get: { wallClock },
                    set: { form?.settings[keyPath: keyPath].wallClock = $0 }
                ), displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .datePickerStyle(.compact)
                .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            } else {
                // Unreadable text is shown as AO3 sent it and posted back unchanged.
                Text(instant.wireString.isEmpty ? "Not set" : instant.wireString)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                if instant.wireString.isEmpty {
                    Button("Set") { form?.settings[keyPath: keyPath].wallClock = Date() }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .buttonStyle(.plain)
                }
            }
        }
    }

    /// Spec order. A reveal date AO3 left off the form (the collection is not
    /// unrevealed / not anonymous) is not a field here either.
    private var schedulePanel: some View {
        let rows: [(label: String, keyPath: WritableKeyPath<AO3ChallengeSettings, AO3ChallengeInstant>?)] = [
            ("Sign-ups open", \.signupsOpenAt), ("Sign-ups close", \.signupsCloseAt),
            ("Assignments sent", nil),
            // assignments_due_at: AO3 prints "Assignments Due" and mails it as
            // the deadline for works.
            ("Works due", \.assignmentsDueAt),
            ("Works revealed", \.worksRevealAt), ("Creators revealed", \.authorsRevealAt)
        ].filter { $0.keyPath.map { settings[keyPath: $0].isOnForm } ?? true }
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { SubjectRowSeparator() }
                if let keyPath = row.keyPath {
                    dateRow(label: row.label, keyPath: keyPath)
                } else {
                    // AO3 stamps this when an owner sends assignments by hand; the
                    // form has no input for it, so it is read-only and usually unknown.
                    SubjectFormRow(
                        label: row.label,
                        value: settings.assignmentsSentAt?.formatted(date: .abbreviated, time: .shortened) ?? "Manual",
                        isMonospaced: settings.assignmentsSentAt != nil
                    )
                }
            }
            SubjectRowSeparator()
            SubjectFormRow(
                label: "Time zone",
                value: settings.scheduleIsEditable ? settings.timeZoneName : "Unavailable"
            )
        }
        .subjectPanel()
    }

    private var scheduleFootnote: some View {
        Text(settings.scheduleIsEditable
            ? "Dates are in the challenge’s time zone, as on AO3’s own form. AO3 runs reveals "
                + "server-side, so the app cannot bring a reveal forward once it has fired."
            : "AO3's time zone was missing or unreadable, so dates are read-only and won't be included in this save.")
            .font(.system(size: 11.5))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    // MARK: - Sign-up limits

    private var limitsErrors: [String] {
        guard let fieldErrors = form?.fieldErrors else { return [] }
        return ["requests_num_required", "requests_num_allowed", "offers_num_required", "offers_num_allowed"]
            .compactMap { fieldErrors[$0] }
    }

    private func stepperRow(
        label: String,
        value: Int,
        range: ClosedRange<Int>,
        isDisabled: Bool = false,
        onChange: @escaping (Int) -> Void
    ) -> some View {
        SubjectFormRow(label: label, arrangement: .value, isDisabled: isDisabled) {
            HStack(spacing: 10) {
                Text("\(value)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Stepper("", value: Binding(get: { value }, set: onChange), in: range)
                    .labelsHidden()
                    .disabled(isDisabled)
            }
        }
    }

    /// 1cf's "Requests · 1 to 3" / "Offers · 2 to 5": AO3's required and allowed
    /// counts as one range row each.
    private var limitsPanel: some View {
        VStack(spacing: 0) {
            rangeRow("Requests", required: \.requestsRequired, allowed: \.requestsAllowed)
            if settings.kind == .giftExchange {
                SubjectRowSeparator()
                rangeRow("Offers", required: \.offersRequired, allowed: \.offersAllowed)
            }
        }
        .subjectPanel()
    }

    private func rangeRow(
        _ label: String,
        required: WritableKeyPath<AO3ChallengeSignUpLimits, Int>,
        allowed: WritableKeyPath<AO3ChallengeSignUpLimits, Int>
    ) -> some View {
        SubjectFormRow(label: label, arrangement: .control) {
            countMenu("\(label) required", required)
            Text("to")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            countMenu("\(label) allowed", allowed)
        }
    }

    /// Two menus in one row: each answers only its own label.
    private func countMenu(_ title: String, _ keyPath: WritableKeyPath<AO3ChallengeSignUpLimits, Int>) -> some View {
        optionMenu(title, value: settings.limits[keyPath: keyPath], options: Array(0...20)) {
            form?.settings.limits[keyPath: keyPath] = $0
        }
    }

    private func requestRestrictionToggleBinding(
        _ keyPath: WritableKeyPath<AO3PromptRestrictionSnapshot, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { form?.settings.requestRestriction[keyPath: keyPath] ?? false },
            set: { form?.settings.requestRestriction[keyPath: keyPath] = $0 }
        )
    }

    private var requestRestrictionTogglesPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "URL allowed in a request", arrangement: .control) {
                Toggle("", isOn: requestRestrictionToggleBinding(\.urlAllowed))
                    .labelsHidden()
                    .tint(palette.tint)
                    .disabled(!restrictionIsEditable("url_allowed"))
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Description required", arrangement: .control) {
                Toggle("", isOn: requestRestrictionToggleBinding(\.descriptionRequired))
                    .labelsHidden()
                    .tint(palette.tint)
                    .disabled(!restrictionIsEditable("description_required"))
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Optional tags allowed", arrangement: .control) {
                Toggle("", isOn: requestRestrictionToggleBinding(\.optionalTagsAllowed))
                    .labelsHidden()
                    .tint(palette.tint)
                    .disabled(!restrictionIsEditable("optional_tags_allowed"))
            }
        }
        .subjectPanel()
    }

    private func restrictionIsEditable(_ field: String) -> Bool {
        settings.requestRestriction.isEditable(field)
    }

    private var restrictionControlsLocked: Bool {
        ["url_allowed", "description_required", "optional_tags_allowed",
         "fandom_num_required", "fandom_num_allowed", "allow_any_fandom"]
            .contains { settings.requestRestriction.controlState($0) == .disabled }
    }

    private var restrictionLockNote: some View {
        Text("Prompts have been added so these settings can no longer be changed.")
            .font(.system(size: 11.5))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    // MARK: - Tag sets

    /// The only route to artboard 1ch: `TagSetView` is addressed by a numeric id
    /// that AO3 publishes on the **collection profile** page, not on the
    /// collection show page. The fetch lives on the two challenge screens rather
    /// than on `AO3CollectionDetailView` deliberately — a tag set only means
    /// anything in a challenge context, and hanging the request off collection
    /// detail would spend an extra AO3 request on every collection anyone opens,
    /// the majority of which have no challenge at all.
    /// `docs/AO3_NETWORKING_POLICY.md` treats request politeness as a product
    /// requirement, so the cost sits on the screens that use it.
    ///
    /// `isModerator: true` here: this is the maintainer's edit form, only
    /// reachable by someone AO3 already let load `challengeSettings` for the
    /// collection, so "moderator" is the honest kicker. 1by, the owners' read
    /// view, passes `true` for the same reason.
    ///
    /// Editing the tag set's own fields stays on 1ch — `AO3TagSetSave` is the
    /// only tag-set write in the Services layer and it belongs to that screen.
    private var tagSetsPanel: some View {
        VStack(spacing: 0) {
            ForEach(Array(tagSetLinks.enumerated()), id: \.element.id) { index, link in
                if index > 0 { SubjectRowSeparator() }
                SubjectFormRow(label: link.title, showsDisclosure: true) { EmptyView() }
                    .subjectRowNavigation(accessibilityLabel: link.title) {
                        TagSetView(tagSetID: link.id, tagSetTitle: link.title, isModerator: true)
                    }
            }
        }
        .subjectPanel()
    }

    // MARK: - Matching
    //
    // The matcher's own settings are `matchSettingsPanels`; these are the
    // request restriction's fandom range and "Any", which also feed it.

    private var matchingPanel: some View {
        VStack(spacing: 0) {
            stepperRow(
                label: "Fandoms required per request",
                value: settings.requestRestriction.fandomRequired,
                range: 0...10,
                isDisabled: !restrictionIsEditable("fandom_num_required")
            ) {
                form?.settings.requestRestriction.fandomRequired = $0
            }
            SubjectRowSeparator()
            stepperRow(
                label: "Fandoms allowed per request",
                value: settings.requestRestriction.fandomAllowed,
                range: 0...10,
                isDisabled: !restrictionIsEditable("fandom_num_allowed")
            ) {
                form?.settings.requestRestriction.fandomAllowed = $0
            }
            SubjectRowSeparator()
            // The spec's caption; the caption is the toggle's own label.
            Toggle(isOn: requestRestrictionToggleBinding(\.allowAnyFandom)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow any fandom")
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    Text("Signing up with “any” matches a participant to everything in the tag set")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .tint(palette.tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .disabled(!restrictionIsEditable("allow_any_fandom"))
        }
        .subjectPanel()
    }

    private var matchingFootnote: some View {
        Text("Matching itself runs on AO3 and is not exposed to clients. These settings post to "
            + "the challenge; running the match is an Open on AO3 link. Changed after potential matches "
            + "were generated, they apply only once matches are regenerated on AO3.")
            .font(.system(size: 11.5))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    // MARK: - At AO3

    /// AO3ChallengeURL has no confirm-delete route for challenges (unlike
    /// `confirmDeleteSignUp` for sign-ups), so this opens the same edit page a
    /// maintainer would delete a challenge from on the website.
    private var deleteChallengeURL: URL {
        settings.kind == .giftExchange
            ? AO3ChallengeURL.giftExchangeEdit(slug: collectionSlug)
            : AO3ChallengeURL.promptMemeEdit(slug: collectionSlug)
    }

    private var atAO3Panel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Run matching", value: "Opens AO3", showsDisclosure: true) {
                router.open(settings.matchingOpenOnAO3)
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Delete challenge", value: "Opens AO3", showsDisclosure: true) {
                router.open(deleteChallengeURL)
            }
        }
        .subjectPanel()
    }

    // MARK: - Bottom action bar

    private var bottomActionBar: some View {
        Button {
            saveTapped()
        } label: {
            HStack(spacing: 6) {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .tint(palette.accentOnFill)
                }
                Text("Save changes")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.accentOnFill)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(palette.accent)
            )
        }
        .buttonStyle(.plain)
        .disabled(
            !AO3CollectionOwnerControls.areVisible(viewerIsOwner: viewerIsOwner)
                || !Self.canStartSave(isSaving: isSaving, hasForm: form != nil)
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 26)
        .background(
            LinearGradient(
                colors: [
                    theme.appTheme.cardBackdrop,
                    theme.appTheme.cardBackdrop.opacity(0.96),
                    theme.appTheme.cardBackdrop.opacity(0.0)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        )
    }

    // MARK: - State Cards

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading challenge settings…")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }

    private func failureCard(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Couldn't load challenge settings")
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await load() }
            }
            .buttonStyle(.bordered)
            .tint(palette.tint)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .subjectPanel()
    }

    private func noticeCard(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(palette.accent)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .subjectPanel()
    }

    private func errorCard(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color.red)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .subjectPanel()
    }

    // MARK: - Loading & Saving

    private func load() async {
        loadGeneration = AO3CollectionSessionReload.nextLoadGeneration(loadGeneration)
        let capturedLoadGeneration = loadGeneration
        let capturedSessionGeneration = auth.sessionGeneration
        if loadedGeneration != capturedSessionGeneration {
            clearLoadedState()
        }
        phase = .loading
        saveNotice = nil
        do {
            let request = try auth.authenticatedRequest(
                for: AO3ChallengeURL.giftExchangeEdit(slug: collectionSlug)
            )
            let loaded = try await AO3Client.shared.challengeSettings(slug: collectionSlug, request: request)
            try auth.requireSessionGeneration(capturedSessionGeneration)

            var loadedSignUpTotal: Int?
            if let signUpsRequest = try? auth.authenticatedRequest(
                for: AO3ChallengeURL.signUps(slug: collectionSlug)
            ), let firstPage = try? await AO3Client.shared.challengeSignUps(
                slug: collectionSlug, request: signUpsRequest
            ) {
                loadedSignUpTotal = try? await AO3Client.shared.challengeSignUpTotal(
                    slug: collectionSlug, firstPage: firstPage, request: signUpsRequest
                )
            }
            try auth.requireSessionGeneration(capturedSessionGeneration)

            // Best-effort: a challenge with no tag set is ordinary, and a failed
            // profile fetch must not take the whole form down with it.
            let profileRequest = try? auth.authenticatedRequest(
                for: AO3CollectionURL.profile(slug: collectionSlug)
            )
            let loadedTagSetLinks = (try? await AO3Client.shared.collectionTagSets(
                slug: collectionSlug, request: profileRequest
            )) ?? []
            try auth.requireSessionGeneration(capturedSessionGeneration)

            // Basics and the moderation switches. Best-effort: the challenge
            // form stays editable if the collection's page fails.
            let collection = try? await auth.collectionEditForm(slug: collectionSlug)
            try auth.requireSessionGeneration(capturedSessionGeneration)
            guard AO3CollectionSessionReload.shouldApplyLoad(
                capturedLoadGeneration: capturedLoadGeneration,
                loadGeneration: loadGeneration,
                capturedSessionGeneration: capturedSessionGeneration,
                sessionGeneration: auth.sessionGeneration
            ) else { return }
            form = loaded
            signUpTotal = loadedSignUpTotal
            tagSetLinks = loadedTagSetLinks
            collectionForm = collection
            loadedCollectionForm = collection
            collectionLoadFailed = collection == nil
            loadedGeneration = capturedSessionGeneration
            phase = .loaded
        } catch {
            guard AO3CollectionSessionReload.shouldApplyLoad(
                capturedLoadGeneration: capturedLoadGeneration,
                loadGeneration: loadGeneration,
                capturedSessionGeneration: capturedSessionGeneration,
                sessionGeneration: auth.sessionGeneration
            ) else { return }
            phase = .failed(UserFacingError.message(for: error))
        }
    }

    private func save() async {
        guard !isSaving else { return }
        guard AO3CollectionOwnerControls.areVisible(viewerIsOwner: viewerIsOwner) else { return }
        guard let current = form, let loadedGeneration else { return }
        saveNotice = nil
        let validated = current.validated()
        if !validated.isValid {
            form = validated
            return
        }

        isSaving = true
        defer { isSaving = false }
        do {
            let outcome = try await auth.updateChallengeSettings(
                validated, expectedGeneration: loadedGeneration
            )
            try auth.requireSessionGeneration(loadedGeneration)
            switch outcome {
            case let .saved(message, updatedForm):
                form = updatedForm
                saveNotice = message
                await saveCollectionSwitches()
            case let .invalid(invalidForm):
                form = invalidForm
            }
        } catch is CancellationError {
            return
        } catch {
            guard auth.sessionGeneration == loadedGeneration else { return }
            var updated = current
            updated.generalErrors = [UserFacingError.message(for: error)]
            form = updated
        }
    }

    private func clearLoadedState() {
        form = nil
        collectionForm = nil
        loadedCollectionForm = nil
        loadedGeneration = nil
        collectionLoadFailed = false
        tagSetLinks = []
        signUpTotal = nil
        saveNotice = nil
    }

    /// The moderation switches post through the collection's own form, and only
    /// when one changed. The session that loaded that form is re-checked.
    private func saveCollectionSwitches() async {
        guard collectionFormChanged, let collection = collectionForm, let loadedGeneration else { return }
        do {
            switch try await auth.updateCollection(
                slug: collectionSlug, form: collection, expectedGeneration: loadedGeneration
            ) {
            case let .saved(message, updated):
                collectionForm = updated
                loadedCollectionForm = updated
                saveNotice = [saveNotice, message].compactMap { $0 }.joined(separator: " ")
            case let .invalid(invalid):
                appendError(invalid.generalErrors.first ?? "AO3 didn't save the collection settings.")
            }
        } catch is CancellationError {
            return
        } catch {
            guard auth.sessionGeneration == loadedGeneration else { return }
            appendError("Collection settings: \(UserFacingError.message(for: error))")
        }
    }

    private func appendError(_ message: String) {
        form?.generalErrors.append(message)
    }

    /// Save, after a confirmation when it would reveal works or creators.
    private func saveTapped() {
        if saveRevealsSomething {
            confirmReveal = true
        } else {
            Task { await save() }
        }
    }
}
