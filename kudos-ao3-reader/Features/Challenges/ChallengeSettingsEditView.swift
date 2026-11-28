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
    /// Kind already read from the collection page. Nil keeps the gift-then-meme probe.
    var challengeKind: AO3ChallengeKind?

    @Environment(AO3AuthService.self) private var auth
    /// Not private: the options menu in `ChallengeSettingsEditSections.swift` takes the app colour from it.
    @Environment(ThemeManager.self) var theme
    @Environment(AppRouter.self) private var router

    @ScaledMetric(relativeTo: .headline) private var stateTitleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .subheadline) private var toggleTitleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .body) private var actionRowSize: CGFloat = 16
    @ScaledMetric(relativeTo: .footnote) private var instructionsFontSize: CGFloat = 14
    @ScaledMetric(relativeTo: .footnote) private var loadingSize: CGFloat = 14
    @ScaledMetric(relativeTo: .footnote) var optionValueSize: CGFloat = 13
    @ScaledMetric(relativeTo: .footnote) private var bodySize: CGFloat = 13
    @ScaledMetric(relativeTo: .footnote) private var errorBodySize: CGFloat = 12.5
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 12

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
        List {
            Section {
                contextCard.pageBodyRow(top: 12, gutter: gutter)
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
        }
        .cardList()
        // Rows at their own padding, not the List minimum (L3-FORM-1).
        .environment(\.defaultMinListRowHeight, 0)
        .subjectScreenWash(title: "Challenge Settings", palette: palette, role: .grouped)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                ChallengeBoardConfirmToolbarButton(
                    title: "Save",
                    isBusy: isSaving,
                    isDisabled: !AO3CollectionOwnerControls.areVisible(viewerIsOwner: viewerIsOwner)
                        || !Self.canStartSave(isSaving: isSaving, hasForm: form != nil)
                ) {
                    saveTapped()
                }
            }
        }
        .task(id: auth.sessionGeneration) { await load() }
        .refreshable { await load() }
        .alert("Reveal now?", isPresented: $confirmReveal) {
            Button("Save and Reveal", role: .destructive) {
                Task { await save() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Turning off Unrevealed makes every work visible. Turning off Anonymous shows every "
                + "creator. You can't reverse either change in Kudos.")
        }
            .screenTint(palette)
    }

    // MARK: - Header (`Challenge-Settings.dc.html`)

    private var contextCard: some View {
        let baseMeta = ChallengesBoardCopy.challengeSettingsContextMeta(
            closeDateText: settings.signupsCloseAt.dateText,
            worksDueDateText: settings.worksDueAt.dateText
        )
        let metaParts: [String?] = [
            baseMeta.isEmpty ? nil : baseMeta,
            signUpTotal.map { "\($0.formatted()) signed up" }
        ]
        return ChallengeBoardContextCard(
            systemImage: settings.kind == .promptMeme ? "bubble.left" : "gift",
            kicker: ChallengesBoardCopy.challengeSettingsKicker(
                kind: settings.kind,
                isModerated: collectionForm?.isModerated
            ),
            title: effectiveTitle,
            meta: metaParts.compactMap { $0 }.joined(separator: " · "),
            palette: palette,
            surface: .form
        )
    }

    // MARK: - Content Sections (`Challenge-Settings.dc.html`: Schedule, Sign-ups, Matching, then Basics/Moderation/At AO3)

    @ViewBuilder
    private var contentSections: some View {
        Section {
            ChallengeBoardSectionHeader(title: "Schedule")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            ForEach(scheduleErrors, id: \.self) { message in
                errorCard(message).pageBodyRow(top: 6, gutter: gutter)
            }
            schedulePanel.pageBodyRow(top: 6, gutter: gutter)
            scheduleFootnote.pageBodyRow(top: 6, gutter: gutter)
        }

        Section {
            ChallengeBoardSectionHeader(title: "Sign-ups")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            ForEach(limitsErrors, id: \.self) { message in
                errorCard(message).pageBodyRow(top: 6, gutter: gutter)
            }
            limitsPanel.pageBodyRow(top: 6, gutter: gutter)
        }

        if !tagSetLinks.isEmpty {
            Section {
                ForEach(Array(tagSetLinks.enumerated()), id: \.element.id) { index, link in
                    SubjectFormRow(
                        label: tagSetLinks.count == 1 ? "Tag set" : link.title,
                        value: tagSetLinks.count == 1 ? link.title : "",
                        showsDisclosure: true
                    )
                    .subjectRowNavigation(accessibilityLabel: "Tag set, \(link.title)") {
                        TagSetView(tagSetID: link.id, tagSetTitle: link.title, isModerator: true)
                    }
                    .panelSegment(index, of: tagSetLinks.count, gutter: gutter)
                }
            }
        }

        Section {
            ChallengeBoardSectionHeader(title: "Request restrictions")
                .pageBodyRow(top: 14, gutter: selfGuttered)
            requestRestrictionTogglesPanel.pageBodyRow(top: 6, gutter: gutter)
            if restrictionControlsLocked {
                restrictionLockNote.pageBodyRow(top: 6, gutter: gutter)
            }
        }

        Section {
            ChallengeBoardSectionHeader(title: "Matching")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            matchSettingsPanels
            ChallengeBoardSectionHeader(title: "Request fandoms")
                .pageBodyRow(top: 12, gutter: selfGuttered)
            matchingPanel.pageBodyRow(top: 6, gutter: gutter)
            generateMatchesPanel.pageBodyRow(top: 10, gutter: gutter)
            matchingFootnote.pageBodyRow(top: 6, gutter: gutter)
        }

        Section {
            ChallengeBoardSectionHeader(title: "Basics")
                .padding(.bottom, 6)
                .pageBodyRow(top: 18, gutter: selfGuttered)
        }
        Section {
            basicsRows
            instructionsCard.pageBodyRow(top: 10, gutter: gutter)
        }

        Section {
            ChallengeBoardSectionHeader(title: "Anonymity and moderation")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            moderationPanel.pageBodyRow(top: 6, gutter: gutter)
        }

        Section {
            ChallengeBoardSectionHeader(title: "At AO3")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            atAO3Panel.pageBodyRow(top: 6, gutter: gutter)
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
            Text("Sign-up instructions")
                .font(.footnote)
                .foregroundStyle(.secondaryInk)

            ZStack(alignment: .topLeading) {
                if instructionsBinding.wrappedValue.isEmpty {
                    Text("Describe the challenge for people signing up…")
                        .font(.system(size: instructionsFontSize, design: .serif))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                }

                TextEditor(text: instructionsBinding)
                    .font(.system(size: instructionsFontSize, design: .serif))
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
        }
        .padding(14)
        .challengeBoardCard()
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
        let status = instant.instant.map { ChallengesBoardCopy.scheduleStatusMeta(for: $0) }
        return VStack(alignment: .leading, spacing: 2) {
            SubjectFormRow(label: label, arrangement: .control) {
                if !settings.scheduleIsEditable {
                    Text(instant.wireString.isEmpty ? "Not set" : instant.wireString)
                        .font(.system(size: bodySize))
                        .foregroundStyle(.secondaryInk)
                } else if let wallClock = instant.wallClock {
                    DatePicker("", selection: Binding(
                        get: { wallClock },
                        set: { form?.settings[keyPath: keyPath].wallClock = $0 }
                    ), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                    .accentFill()
                } else {
                    // Unreadable text is shown as AO3 sent it and posted back unchanged.
                    Text(instant.wireString.isEmpty ? "Not set" : instant.wireString)
                        .font(.system(size: bodySize))
                        .foregroundStyle(.secondaryInk)
                    if instant.wireString.isEmpty {
                        Button("Set") { form?.settings[keyPath: keyPath].wallClock = Date() }
                            .font(.system(size: bodySize, weight: .semibold))
                            .foregroundStyle(theme.accentInk)
                            .buttonStyle(.plain)
                    }
                }
            }

            if let status {
                Text(status.text)
                    .font(.system(size: captionSize, weight: .semibold))
                    .foregroundStyle(
                        status.isDone
                            ? theme.appTheme.statusSuccessColor
                            : ChallengeBoardColors.warningInk(for: theme.appTheme)
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
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
                        value: settings.assignmentsSentAt.map { WorkStat.displayDate($0, time: .shortened) } ?? "Manual",
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
        .challengeBoardCard()
    }

    private var scheduleFootnote: some View {
        ChallengeBoardSectionFooter(
            text: settings.scheduleIsEditable
                ? "Dates use the challenge’s time zone shown on AO3. After a reveal happens, you can't "
                    + "move it to an earlier time in Kudos."
                : "Kudos couldn't read the challenge's time zone. Dates are view-only and won't be saved.",
            horizontalInset: 16
        )
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
                    .font(.system(size: optionValueSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondaryInk)
                Stepper("", value: Binding(get: { value }, set: onChange), in: range)
                    .labelsHidden()
                    .disabled(isDisabled).accentFill()
            }
        }
    }

    /// `Challenge-Settings.dc.html`: Sign-up open (read-only status), Requests per person, Offers per person.
    private var limitsPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(
                label: "Sign-up open",
                value: settings.signupOpen ? "Open" : "Closed"
            )
            SubjectRowSeparator()
            rangeRow("Requests per person", required: \.requestsRequired, allowed: \.requestsAllowed)
            if settings.kind == .giftExchange {
                SubjectRowSeparator()
                rangeRow("Offers per person", required: \.offersRequired, allowed: \.offersAllowed)
            }
        }
        .challengeBoardCard()
    }

    private func rangeRow(
        _ label: String,
        required: WritableKeyPath<AO3ChallengeSignUpLimits, Int>,
        allowed: WritableKeyPath<AO3ChallengeSignUpLimits, Int>
    ) -> some View {
        SubjectFormRow(label: label, arrangement: .control) {
            countMenu("\(label) required", required)
            Text("–")
                .font(.system(size: bodySize))
                .foregroundStyle(.secondaryInk)
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
        .challengeBoardCard()
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
        ChallengeBoardSectionFooter(
            text: "Prompts have been added so these settings can no longer be changed.",
            horizontalInset: 16
        )
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
                        .font(.system(size: toggleTitleSize))
                        .foregroundStyle(.primary)
                    Text("Choosing “any” can match you with anything in the tag set.")
                        .font(.system(size: captionSize))
                        .foregroundStyle(.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .tint(palette.tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .disabled(!restrictionIsEditable("allow_any_fandom"))
        }
        .challengeBoardCard()
    }

    private var generateMatchesPanel: some View {
        Button {
            router.open(settings.matchingOpenOnAO3)
        } label: {
            Text(ChallengesBoardCopy.challengeSettingsGenerateMatchesLabel)
                .font(.system(size: actionRowSize, weight: .semibold))
                .foregroundStyle(theme.accentInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ChallengesBoardCopy.challengeSettingsGenerateMatchesLabel)
        .accessibilityHint("Opens AO3")
        .challengeBoardCard()
    }

    private var matchingFootnote: some View {
        ChallengeBoardSectionFooter(
            text: "AO3 does the matching. Save these settings here, then use Generate Potential Matches "
                + "to run or rerun the match on AO3.",
            horizontalInset: 16
        )
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
            SubjectFormRow(label: "Delete challenge", value: "Opens AO3", showsDisclosure: true, isDestructive: true) {
                router.open(deleteChallengeURL)
            }
        }
        .challengeBoardCard()
    }

    // MARK: - State Cards

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .accentFill()
            Text("Loading challenge settings…")
                .font(.system(size: loadingSize))
                .foregroundStyle(.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }

    private func failureCard(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Couldn't load challenge settings")
                .font(.system(size: stateTitleSize, weight: .semibold))
            Text(message)
                .font(.system(size: bodySize))
                .foregroundStyle(.secondaryInk)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await load() }
            }
            .buttonStyle(.kudosSecondary)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .challengeBoardCard()
    }

    private func noticeCard(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(palette.accent)
            Text(text)
                .font(.system(size: bodySize, weight: .medium))
                .foregroundStyle(palette.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .challengeBoardCard()
    }

    private func errorCard(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(theme.appTheme.errorColor)
            Text(text)
                .font(.system(size: errorBodySize))
                .foregroundStyle(theme.appTheme.errorColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .challengeBoardCard()
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
            let loaded = try await AO3Client.shared.challengeSettings(
                slug: collectionSlug, request: request, kind: challengeKind
            )
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
                // After both requests: the settings page behind, and the collection's own, showed
                // the dates and switches from before the save.
                NotificationCenter.default.post(name: .ao3CollectionChanged, object: collectionSlug)
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
