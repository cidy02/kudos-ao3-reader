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
/// A few rows the mockup shows are not here on purpose:
/// - Name, Host byline and Tagline are collection fields, not challenge fields —
///   `AO3ChallengeSettings` carries no `name`/owner/tagline of its own, and this
///   screen does not invent them. The collection's own name is already in the
///   header subtitle above.
/// - FAQ lives on `collection[collection_profile_attributes][faq]`
///   (`AO3CollectionForm.faq`), so its "edit" affordance opens
///   `AO3CollectionFormView` (1bl/1cg) rather than duplicating that state here.
/// - "Unrevealed until reveal", "Moderated sign-ups" and "Closed to new sign-ups"
///   are `AO3CollectionForm.isUnrevealed/isModerated/isClosed` — collection
///   preferences, not challenge settings — so they stay on 1cg too.
/// - "Match on" has no backing field on `AO3PromptRestrictionSnapshot` at all,
///   so it is dropped rather than faked.
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

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(AppRouter.self) private var router

    @State private var form: AO3ChallengeSettingsForm?
    @State private var signUpCount: Int = 0
    @State private var phase: Phase = .idle
    @State private var isSaving: Bool = false
    @State private var saveNotice: String?

    private enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private var gutter: CGFloat { SubjectMetrics.accountGutter }
    private var selfGuttered: CGFloat { 0 }

    private var palette: SubjectPalette {
        theme.appTheme.subjectPalette(
            hue: CoverArt.workHue(fandoms: [], title: effectiveTitle)
        )
    }

    private var effectiveTitle: String {
        collectionTitle.isEmpty ? collectionSlug : collectionTitle
    }

    private var settings: AO3ChallengeSettings {
        form?.settings ?? AO3ChallengeSettings(collectionSlug: collectionSlug, kind: .giftExchange)
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
            #if os(macOS)
            .navigationTitle("Challenge settings")
            #endif
            .subjectScreenWash(palette: palette)

            bottomActionBar
        }
        .task { await loadIfNeeded() }
        .refreshable { await load() }
    }

    // MARK: - Header

    private var kicker: String {
        switch settings.kind {
        case .giftExchange: "Gift exchange - moderator"
        case .promptMeme: "Prompt meme - moderator"
        }
    }

    private var header: some View {
        SubjectHeaderBlock(
            kicker: kicker,
            title: "Challenge settings",
            subtitle: "\(effectiveTitle) - \(signUpCount) sign-ups",
            palette: palette,
            gutter: SubjectMetrics.accountGutter
        )
    }

    // MARK: - Content Sections

    @ViewBuilder
    private var contentSections: some View {
        Section {
            SectionRuleHeader(title: "Basics")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            introductionCard.pageBodyRow(top: 8, gutter: gutter)
            faqPanel.pageBodyRow(top: 8, gutter: gutter)
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
            SubjectFieldLabel(text: "Requests", style: .formGroup)
                .pageBodyRow(top: 8, gutter: gutter)
            requestLimitsPanel.pageBodyRow(top: 8, gutter: gutter)
            if settings.kind == .giftExchange {
                SubjectFieldLabel(text: "Offers", style: .formGroup)
                    .pageBodyRow(top: 12, gutter: gutter)
                offerLimitsPanel.pageBodyRow(top: 8, gutter: gutter)
            }
            SubjectFieldLabel(text: "Request restrictions", style: .formGroup)
                .pageBodyRow(top: 12, gutter: gutter)
            requestRestrictionTogglesPanel.pageBodyRow(top: 8, gutter: gutter)
        }

        Section {
            SectionRuleHeader(title: "Matching")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            matchingPanel.pageBodyRow(top: 8, gutter: gutter)
            matchingFootnote.pageBodyRow(top: 8, gutter: gutter)
        }

        Section {
            SectionRuleHeader(title: "Anonymity and moderation")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            anonymityPanel.pageBodyRow(top: 8, gutter: gutter)
        }

        Section {
            SectionRuleHeader(title: "At AO3")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            atAO3Panel.pageBodyRow(top: 8, gutter: gutter)
        }
    }

    // MARK: - Basics

    private var introductionBinding: Binding<String> {
        Binding(
            get: { form?.settings.signupInstructionsGeneral ?? "" },
            set: { form?.settings.signupInstructionsGeneral = $0 }
        )
    }

    private var introductionCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            SubjectFieldLabel(text: "Introduction", style: .formGroup)

            ZStack(alignment: .topLeading) {
                if introductionBinding.wrappedValue.isEmpty {
                    Text("Describe the challenge for people signing up…")
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                }

                TextEditor(text: introductionBinding)
                    .font(.system(size: 14, design: .serif))
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
        }
        .padding(14)
        .subjectPanel()
    }

    /// FAQ is a collection-profile field (`AO3CollectionForm.faq`), not a
    /// challenge field, so editing it opens the collection's own form rather
    /// than a duplicate control here.
    private var faqPanel: some View {
        NavigationLink {
            AO3CollectionFormView(slug: collectionSlug)
        } label: {
            SubjectFormRow(label: "FAQ", value: "Edit on collection", showsDisclosure: true)
        }
        .buttonStyle(.plain)
        .subjectPanel()
    }

    // MARK: - Schedule

    private var scheduleErrors: [String] {
        guard let fieldErrors = form?.fieldErrors else { return [] }
        return ["signups_close_at", "assignments_due_at", "works_reveal_at", "authors_reveal_at"]
            .compactMap { fieldErrors[$0] }
    }

    private func instantBinding(_ keyPath: WritableKeyPath<AO3ChallengeSettings, AO3ChallengeInstant>) -> Binding<Date> {
        Binding(
            get: { form?.settings[keyPath: keyPath].date ?? Date() },
            set: { form?.settings[keyPath: keyPath].date = $0 }
        )
    }

    private func dateRow(label: String, keyPath: WritableKeyPath<AO3ChallengeSettings, AO3ChallengeInstant>) -> some View {
        SubjectFormRow(label: label, arrangement: .control) {
            DatePicker("", selection: instantBinding(keyPath), displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .datePickerStyle(.compact)
        }
    }

    private var schedulePanel: some View {
        VStack(spacing: 0) {
            dateRow(label: "Sign-ups open", keyPath: \.signupsOpenAt)
            SubjectRowSeparator()
            dateRow(label: "Sign-ups close", keyPath: \.signupsCloseAt)
            SubjectRowSeparator()
            dateRow(label: "Assignments due", keyPath: \.assignmentsDueAt)
            SubjectRowSeparator()
            dateRow(label: "Works revealed", keyPath: \.worksRevealAt)
            SubjectRowSeparator()
            dateRow(label: "Creators revealed", keyPath: \.authorsRevealAt)
        }
        .subjectPanel()
    }

    private var scheduleFootnote: some View {
        Text("AO3 stores every date in UTC and runs reveals server-side, so the app shows the "
            + "local equivalent and cannot bring a reveal forward once it has fired.")
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
        onChange: @escaping (Int) -> Void
    ) -> some View {
        SubjectFormRow(label: label, arrangement: .value) {
            HStack(spacing: 10) {
                Text("\(value)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Stepper("", value: Binding(get: { value }, set: onChange), in: range)
                    .labelsHidden()
            }
        }
    }

    private var requestLimitsPanel: some View {
        VStack(spacing: 0) {
            stepperRow(label: "Required", value: settings.limits.requestsRequired, range: 0...20) {
                form?.settings.limits.requestsRequired = $0
            }
            SubjectRowSeparator()
            stepperRow(label: "Allowed", value: settings.limits.requestsAllowed, range: 0...20) {
                form?.settings.limits.requestsAllowed = $0
            }
        }
        .subjectPanel()
    }

    private var offerLimitsPanel: some View {
        VStack(spacing: 0) {
            stepperRow(label: "Required", value: settings.limits.offersRequired, range: 0...20) {
                form?.settings.limits.offersRequired = $0
            }
            SubjectRowSeparator()
            stepperRow(label: "Allowed", value: settings.limits.offersAllowed, range: 0...20) {
                form?.settings.limits.offersAllowed = $0
            }
        }
        .subjectPanel()
    }

    private func requestRestrictionToggleBinding(_ keyPath: WritableKeyPath<AO3PromptRestrictionSnapshot, Bool>) -> Binding<Bool> {
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
                    .tint(palette.accent)
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Description required", arrangement: .control) {
                Toggle("", isOn: requestRestrictionToggleBinding(\.descriptionRequired))
                    .labelsHidden()
                    .tint(palette.accent)
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Optional tags allowed", arrangement: .control) {
                Toggle("", isOn: requestRestrictionToggleBinding(\.optionalTagsAllowed))
                    .labelsHidden()
                    .tint(palette.accent)
            }
        }
        .subjectPanel()
    }

    // MARK: - Matching
    //
    // AO3PromptRestrictionSnapshot has no "match on" field at all — the mockup's
    // row is dropped rather than invented. What it does carry are the fandom
    // per-request range and `allowAnyFandom`, which is what actually feeds the
    // matcher on AO3's side.

    private var matchingPanel: some View {
        VStack(spacing: 0) {
            stepperRow(
                label: "Fandoms required per request",
                value: settings.requestRestriction.fandomRequired,
                range: 0...10
            ) {
                form?.settings.requestRestriction.fandomRequired = $0
            }
            SubjectRowSeparator()
            stepperRow(
                label: "Fandoms allowed per request",
                value: settings.requestRestriction.fandomAllowed,
                range: 0...10
            ) {
                form?.settings.requestRestriction.fandomAllowed = $0
            }
            SubjectRowSeparator()
            SubjectFormRow(label: "Allow any fandom", arrangement: .control) {
                Toggle("", isOn: requestRestrictionToggleBinding(\.allowAnyFandom))
                    .labelsHidden()
                    .tint(palette.accent)
            }
        }
        .subjectPanel()
    }

    private var matchingFootnote: some View {
        Text("Matching itself runs on AO3 and is not exposed to clients. These settings post to "
            + "the challenge; running the match is an Open on AO3 link.")
            .font(.system(size: 11.5))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    // MARK: - Anonymity and moderation
    //
    // "Unrevealed until reveal", "Moderated sign-ups" and "Closed to new
    // sign-ups" are collection preferences (AO3CollectionForm.isUnrevealed /
    // isModerated / isClosed) — not fields on AO3ChallengeSettings — so they
    // are not duplicated here. They belong on 1cg (AO3CollectionFormView).

    private var anonymousBinding: Binding<Bool> {
        Binding(
            get: { form?.settings.isAnonymous ?? false },
            set: { form?.settings.isAnonymous = $0 }
        )
    }

    private var anonymityPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Anonymous until reveal", arrangement: .control) {
                Toggle("", isOn: anonymousBinding)
                    .labelsHidden()
                    .tint(palette.accent)
            }
        }
        .subjectPanel()
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
            Task { await save() }
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
        .disabled(isSaving || form == nil)
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
            .tint(palette.accent)
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

    private func loadIfNeeded() async {
        guard phase == .idle else { return }
        await load()
    }

    private func load() async {
        phase = .loading
        saveNotice = nil
        do {
            let request = try auth.authenticatedRequest(
                for: AO3ChallengeURL.giftExchangeEdit(slug: collectionSlug)
            )
            let loaded = try await AO3Client.shared.challengeSettings(slug: collectionSlug, request: request)
            form = loaded

            if let signUpsRequest = try? auth.authenticatedRequest(
                for: AO3ChallengeURL.signUps(slug: collectionSlug, page: 1)
            ), let signUpsPage = try? await AO3Client.shared.challengeSignUps(
                slug: collectionSlug, page: 1, request: signUpsRequest
            ) {
                signUpCount = signUpsPage.signUps.count
            }

            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func save() async {
        guard let current = form else { return }
        saveNotice = nil
        let validated = current.validated()
        if !validated.isValid {
            form = validated
            return
        }

        isSaving = true
        do {
            let outcome = try await auth.updateChallengeSettings(validated)
            switch outcome {
            case let .saved(message, updatedForm):
                form = updatedForm
                saveNotice = message
            case let .invalid(invalidForm):
                form = invalidForm
            }
        } catch {
            var updated = current
            updated.generalErrors = [error.localizedDescription]
            form = updated
        }
        isSaving = false
    }
}
