import SwiftUI

/// Artboard **1ca** — Your sign-up.
///
/// Participant editor for challenge sign-ups: displays requests and offers as
/// separate groups, binds prompts directly to their parent request, validates
/// requirements locally against challenge limits before posting, and supports
/// sign-up submission and withdrawal.
struct ChallengeSignUpView: View {
    let collectionSlug: String
    var collectionTitle: String = ""
    var existingSignUpID: Int?

    @Environment(AO3AuthService.self) var auth
    @Environment(ThemeManager.self) var theme
    @Environment(\.dismiss) var dismiss
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    @ScaledMetric(relativeTo: .headline) private var stateTitleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .body) private var rowTitleSize: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var promptEditorSize: CGFloat = 16
    @ScaledMetric(relativeTo: .footnote) private var loadingSize: CGFloat = 14
    @ScaledMetric(relativeTo: .footnote) private var noticeTextSize: CGFloat = 13
    @ScaledMetric(relativeTo: .footnote) private var failureBodySize: CGFloat = 13
    @ScaledMetric(relativeTo: .footnote) private var errorTextSize: CGFloat = 12.5
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) private var promptFootnoteSize: CGFloat = 11.5

    @State var form: AO3ChallengeSignUpForm?
    @State var phase: Phase = .idle
    @State var isSubmitting: Bool = false
    @State var isWithdrawing: Bool = false
    @State var confirmWithdraw: Bool = false
    @State var statusNotice: String?
    @State var editingPrompt: EditingPrompt?

    /// The prompt whose tags sheet is open, by id: a row's position among the
    /// live prompts is not its position in the form's arrays.
    struct EditingPrompt: Identifiable {
        let promptID: Int
        let kind: AO3ChallengePromptKind
        /// 0-based position among the live prompts, for the sheet's "Request 2".
        let position: Int
        var id: String { "\(kind.rawValue)\(promptID)" }
    }

    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var gutter: CGFloat { SubjectMetrics.accountGutter }
    var selfGuttered: CGFloat { 0 }

    var palette: SubjectPalette {
        theme.appTheme.subjectPalette(
            hue: CoverArt.workHue(fandoms: [], title: collectionTitle.isEmpty ? collectionSlug : collectionTitle)
        )
    }

    var effectiveTitle: String {
        collectionTitle.isEmpty ? collectionSlug : collectionTitle
    }

    /// AO3's own counts from the form; `nil` (not loaded, or not printed) caps nothing.
    var limits: AO3ChallengeSignUpLimits? { form?.limits }

    /// A prompt meme's sign-up is requests only.
    var takesOffers: Bool { form?.takesOffers ?? true }

    var liveRequests: [AO3ChallengePrompt] {
        form?.requests.filter { !$0.destroy } ?? []
    }

    var liveOffers: [AO3ChallengePrompt] {
        form?.offers.filter { !$0.destroy } ?? []
    }

    var body: some View {
        List {
            Section {
                contextCard.pageBodyRow(top: 12, gutter: gutter)
            }

            if let notice = statusNotice {
                Section {
                    noticeCard(notice).pageBodyRow(top: 8, gutter: gutter)
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
        .subjectScreenWash(title: ChallengesBoardCopy.signUpTitle, palette: palette, role: .grouped)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                ChallengeBoardConfirmToolbarButton(
                    title: "Submit",
                    isBusy: isSubmitting,
                    isDisabled: form == nil || isSubmitting
                ) {
                    Task { await submitSignUp() }
                }
            }
        }
        .task { await loadSignUpIfNeeded() }
        #if DEBUG
        .task { await openPromptTagsIfRequested() }
        #endif
        .refreshable { await loadSignUp() }
        .confirmationDialog(
            "Withdraw this sign-up?",
            isPresented: $confirmWithdraw,
            titleVisibility: .visible
        ) {
            Button("Withdraw Sign-Up", role: .destructive) {
                Task { await performWithdraw() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            // Withdrawing after close is a different AO3 write (a default on the
            // assignment) that this screen does not make yet, so it isn't promised.
            Text("Withdrawing removes your requests and offers from \(effectiveTitle).")
        }
        .sheet(item: $editingPrompt) { editing in
            promptTagsEditor(editing)
        }
            .screenTint(palette)
    }

    /// A live binding to one prompt, found by id. A prompt that has gone reads
    /// as a blank draft with the same id and writes nowhere.
    #if DEBUG
    private func openPromptTagsIfRequested() async {
        guard DebugLaunchRoute.wantsSheet("prompttags") else { return }
        for _ in 0..<40 {
            if phase == .loaded {
                guard DebugLaunchRoute.takeSheet("prompttags") else { return }
                if let prompt = liveRequests.first {
                    editingPrompt = EditingPrompt(promptID: prompt.id, kind: .request, position: 0)
                } else if let offer = liveOffers.first {
                    editingPrompt = EditingPrompt(promptID: offer.id, kind: .offer, position: 0)
                }
                return
            }
            if case .failed = phase { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }
    #endif

    func promptBinding(id: Int, kind: AO3ChallengePromptKind) -> Binding<AO3ChallengePrompt> {
        Binding(
            get: { form?.prompt(id: id, kind: kind) ?? AO3ChallengePrompt(id: id, kind: kind) },
            set: { form?.updatePrompt($0) }
        )
    }

    // MARK: - Header (`Challenge-SignUp.dc.html`)

    private var contextCard: some View {
        ChallengeBoardContextCard(
            systemImage: takesOffers ? "gift" : "bubble.left",
            kicker: ChallengesBoardCopy.challengeKindName(takesOffers ? .giftExchange : .promptMeme),
            title: effectiveTitle,
            meta: ChallengesBoardCopy.signUpContextMeta(
                limits: limits,
                takesOffers: takesOffers,
                requestCount: liveRequests.count,
                offerCount: liveOffers.count
            ),
            palette: palette,
            surface: .form
        )
    }

    // MARK: - Content Sections (`Challenge-SignUp.dc.html`)

    @ViewBuilder
    private var contentSections: some View {
        if let requestError = form?.fieldErrors["requests"] {
            Section {
                errorCard(requestError).pageBodyRow(top: 8, gutter: gutter)
            }
        }

        ForEach(Array(liveRequests.enumerated()), id: \.element.id) { index, request in
            Section {
                ChallengeBoardSectionHeader(title: "Request \(index + 1)")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                if let tagError = form?.fieldErrors[AO3ChallengeSignUpForm.errorKey(for: request)] {
                    errorCard(tagError).pageBodyRow(top: 6, gutter: gutter)
                }
                requestPanel(position: index, prompt: request)
                    .pageBodyRow(top: 6, gutter: gutter)
            }
        }

        if liveRequests.count < (limits?.requestsAllowed ?? .max) {
            Section {
                addPromptButtonCard(title: ChallengesBoardCopy.signUpAddRequestLabel) {
                    addNewRequest()
                }
                .disabled(form == nil || isSubmitting)
                .pageBodyRow(top: 12, gutter: gutter)
            }
        }

        Section {
            requestsFootnote.pageBodyRow(top: 6, gutter: gutter)
        }

        if takesOffers {
            if let offerError = form?.fieldErrors["offers"] {
                Section {
                    errorCard(offerError).pageBodyRow(top: 8, gutter: gutter)
                }
            }

            ForEach(Array(liveOffers.enumerated()), id: \.element.id) { index, offer in
                Section {
                    ChallengeBoardSectionHeader(title: "Offer \(index + 1)")
                        .pageBodyRow(top: 18, gutter: selfGuttered)
                    if let tagError = form?.fieldErrors[AO3ChallengeSignUpForm.errorKey(for: offer)] {
                        errorCard(tagError).pageBodyRow(top: 6, gutter: gutter)
                    }
                    offerPanel(position: index, prompt: offer)
                        .pageBodyRow(top: 6, gutter: gutter)
                }
            }

            if liveOffers.count < (limits?.offersAllowed ?? .max) {
                Section {
                    addPromptButtonCard(title: ChallengesBoardCopy.signUpAddOfferLabel) {
                        addNewOffer()
                    }
                    .disabled(form == nil || isSubmitting)
                    .pageBodyRow(top: 12, gutter: gutter)
                }
            }

            Section {
                offersFootnote.pageBodyRow(top: 6, gutter: gutter)
            }
        }

        if !(auth.username?.isEmpty ?? true) || form?.signUpID != nil {
            Section {
                ChallengeBoardSectionHeader(title: ChallengesBoardCopy.signUpYourSectionTitle)
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                yourSignUpPanel.pageBodyRow(top: 6, gutter: gutter)
            }
        }
    }
}

// MARK: - Panels and Rows

extension ChallengeSignUpView {

    func requestPanel(position: Int, prompt: AO3ChallengePrompt) -> some View {
        let editTags = { editingPrompt = EditingPrompt(promptID: prompt.id, kind: .request, position: position) }
        return VStack(spacing: 0) {
            promptTagChipsRow(
                label: "Fandom",
                tags: prompt.fandoms,
                includesAny: prompt.anyFandom,
                placeholder: "None chosen",
                isTinted: false,
                action: editTags
            )

            SubjectRowSeparator()

            promptTagChipsRow(
                label: "Relationship",
                tags: prompt.relationships,
                includesAny: prompt.anyRelationship,
                placeholder: "Optional",
                isTinted: true,
                action: editTags
            )

            SubjectRowSeparator()

            promptTagChipsRow(
                label: "Characters",
                tags: prompt.characters,
                includesAny: prompt.anyCharacter,
                placeholder: "Optional",
                isTinted: false,
                action: editTags
            )

            SubjectRowSeparator()

            promptTagChipsRow(
                label: "Additional tags",
                tags: prompt.freeforms,
                includesAny: prompt.anyFreeform,
                placeholder: "Optional",
                isTinted: false,
                action: editTags
            )

            SubjectRowSeparator()

            // AO3's any_relationship: the request takes any relationship, not
            // only the ones chosen above. The caption is the toggle's own label,
            // so it names the switch for VoiceOver and on the Mac.
            Toggle(isOn: promptBinding(id: prompt.id, kind: .request).anyRelationship) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Any of these is fine")
                        .font(.system(size: rowTitleSize))
                        .foregroundStyle(.primary)
                    Text("Any relationship matches, not only the ones chosen")
                        .font(.system(size: captionSize))
                        .foregroundStyle(.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .tint(palette.tint)
            .accessibilityLabel("Any of these is fine")
            .accessibilityHint("Any relationship matches, not only the ones chosen")
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            SubjectRowSeparator()

            promptDescriptionSection(prompt: prompt)
        }
        .challengeBoardCard()
    }

    func offerPanel(position: Int, prompt: AO3ChallengePrompt) -> some View {
        let editTags = { editingPrompt = EditingPrompt(promptID: prompt.id, kind: .offer, position: position) }
        return VStack(spacing: 0) {
            promptTagChipsRow(
                label: "Fandom",
                tags: prompt.fandoms,
                includesAny: prompt.anyFandom,
                placeholder: "None chosen",
                isTinted: false,
                action: editTags
            )

            SubjectRowSeparator()

            promptTagChipsRow(
                label: "Relationship",
                tags: prompt.relationships,
                includesAny: prompt.anyRelationship,
                placeholder: "Optional",
                isTinted: true,
                action: editTags
            )

            SubjectRowSeparator()

            promptTagChipsRow(
                label: "Characters",
                tags: prompt.characters,
                includesAny: prompt.anyCharacter,
                placeholder: "Optional",
                isTinted: false,
                action: editTags
            )

            SubjectRowSeparator()

            promptTagChipsRow(
                label: "Additional tags",
                tags: prompt.freeforms,
                includesAny: prompt.anyFreeform,
                placeholder: "Optional",
                isTinted: false,
                action: editTags
            )
        }
        .challengeBoardCard()
    }

    private func promptTagChipsRow(
        label: String,
        tags: [String],
        includesAny: Bool,
        placeholder: String,
        isTinted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let displayTags = tags + (includesAny ? ["Any"] : [])
        return SubjectFormRow(
            label: label,
            arrangement: .control,
            showsDisclosure: true,
            action: action
        ) {
            if displayTags.isEmpty {
                Text(placeholder)
                    .font(.system(size: rowTitleSize))
                    .foregroundStyle(.secondaryInk)
            } else {
                FlowLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(Array(displayTags.enumerated()), id: \.offset) { _, tag in
                        ChallengeBoardTagPill(
                            text: label == "Fandom" ? FandomDisplayName.bareTitle(tag) : tag,
                            isTinted: isTinted && tag != "Any"
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
            }
        }
    }

    func promptDescriptionSection(prompt: AO3ChallengePrompt) -> some View {
        let binding = promptBinding(id: prompt.id, kind: prompt.kind).promptText

        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if binding.wrappedValue.isEmpty {
                    Text("Describe what you would love to receive…")
                        .font(.system(size: promptEditorSize))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                }

                TextEditor(text: binding)
                    .font(.system(size: promptEditorSize))
                    .frame(minHeight: 72)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .accessibilityLabel("Prompt notes")
            }

            // One under the other at the accessibility sizes: beside the count the sentence was
            // cut ("Visible to your recipient o…").
            let footer = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout())
            footer {
                Text("Visible to your recipient only")
                    .font(.system(size: promptFootnoteSize))
                    .foregroundStyle(.secondary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)

                if !dynamicTypeSize.isAccessibilitySize { Spacer() }

                Text("\(binding.wrappedValue.count) / 1000")
                    .font(.system(size: promptFootnoteSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.8))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func addPromptButtonCard(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: rowTitleSize, weight: .semibold))
                .foregroundStyle(theme.accentInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .challengeBoardCard()
    }

    /// The spec's "3 to 5 fandoms and 1 to 3 relationships per request", from
    /// the form's own labels; a limit AO3 did not print is not claimed.
    var requestsFootnote: some View {
        var sentences: [String] = []
        if let limits {
            var counts = "\(limits.requestsRequired) to \(limits.requestsAllowed) requests"
            if takesOffers { counts += " and \(limits.offersRequired) to \(limits.offersAllowed) offers" }
            sentences.append("The challenge asks for \(counts) per sign-up.")
        }
        if let tags = form?.requestTagLimits {
            let perType = AO3PromptTagType.allCases.compactMap { type -> String? in
                guard let range = tags[type], range.upperBound > 0 else { return nil }
                return range.lowerBound == range.upperBound
                    ? "\(range.lowerBound) \(type.plural)"
                    : "\(range.lowerBound) to \(range.upperBound) \(type.plural)"
            }
            if !perType.isEmpty {
                sentences.append("Each request takes \(perType.joined(separator: ", ")).")
            }
        }
        sentences.append("Kudos checks these limits before you submit your sign-up.")
        return ChallengeBoardSectionFooter(text: sentences.joined(separator: " "), horizontalInset: 16)
    }

    var offersFootnote: some View {
        ChallengeBoardSectionFooter(
            text: "You can edit your sign-up until sign-ups close. After they close, you can only withdraw it.",
            horizontalInset: 16
        )
    }

    var yourSignUpPanel: some View {
        let username = auth.username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return VStack(spacing: 0) {
            if !username.isEmpty {
                SubjectFormRow(label: "Pseud", value: username)
                if form?.signUpID != nil {
                    SubjectRowSeparator()
                }
            }
            if form?.signUpID != nil {
                Button {
                    confirmWithdraw = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 15))
                            .foregroundStyle(theme.appTheme.errorColor)
                            .frame(width: 20)

                        Text("Withdraw Sign-Up")
                            .font(.system(size: rowTitleSize, weight: .semibold))
                            .foregroundStyle(theme.appTheme.errorColor)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if isWithdrawing {
                            ProgressView()
                                .controlSize(.small)
                                .accentFill()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isWithdrawing)
                .accessibilityLabel("Withdraw Sign-Up")
            }
        }
        .challengeBoardCard()
    }

    func promptTagsEditor(_ editing: EditingPrompt) -> some View {
        PromptTagsEditorView(
            prompt: promptBinding(id: editing.promptID, kind: editing.kind),
            palette: palette,
            isOffer: editing.kind == .offer,
            index: editing.position
        )
    }

    func noticeCard(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(palette.accent)
            Text(text)
                .font(.system(size: noticeTextSize, weight: .medium))
                .foregroundStyle(palette.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .challengeBoardCard()
    }

    func errorCard(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(theme.appTheme.errorColor)
            Text(text)
                .font(.system(size: errorTextSize))
                .foregroundStyle(theme.appTheme.errorColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .challengeBoardCard()
    }

    var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .accentFill()
            Text("Loading sign-up…")
                .font(.system(size: loadingSize))
                .foregroundStyle(.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }

    func failureCard(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Couldn't load sign-up")
                .font(.system(size: stateTitleSize, weight: .semibold))
            Text(message)
                .font(.system(size: failureBodySize))
                .foregroundStyle(.secondaryInk)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await loadSignUp() }
            }
            .buttonStyle(.kudosSecondary)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .challengeBoardCard()
    }
}

// MARK: - Actions

extension ChallengeSignUpView {

    func loadSignUpIfNeeded() async {
        guard phase == .idle else { return }
        await loadSignUp()
    }

    func loadSignUp() async {
        phase = .loading
        statusNotice = nil
        do {
            if let existingID = existingSignUpID {
                let request = try auth.authenticatedRequest(
                    for: AO3ChallengeURL.editSignUp(slug: collectionSlug, id: existingID)
                )
                form = try await AO3Client.shared.challengeSignUpForm(
                    slug: collectionSlug, id: existingID, request: request
                )
            } else {
                let request = try auth.authenticatedRequest(
                    for: AO3ChallengeURL.newSignUp(slug: collectionSlug)
                )
                form = try await AO3Client.shared.ownChallengeSignUp(
                    slug: collectionSlug, request: request
                )
            }
            ensureMinimumPrompts()
            phase = .loaded
        } catch {
            phase = .failed(UserFacingError.message(for: error))
        }
    }

    func ensureMinimumPrompts() {
        guard var currentForm = form else { return }
        if currentForm.requests.isEmpty {
            currentForm.requests.append(AO3ChallengePrompt(id: currentForm.nextDraftPromptID, kind: .request))
        }
        if currentForm.offers.isEmpty, currentForm.takesOffers {
            currentForm.offers.append(AO3ChallengePrompt(id: currentForm.nextDraftPromptID, kind: .offer))
        }
        form = currentForm
    }

    func addNewRequest() {
        guard var currentForm = form else { return }
        currentForm.requests.append(AO3ChallengePrompt(id: currentForm.nextDraftPromptID, kind: .request))
        form = currentForm
    }

    func addNewOffer() {
        guard var currentForm = form else { return }
        currentForm.offers.append(AO3ChallengePrompt(id: currentForm.nextDraftPromptID, kind: .offer))
        form = currentForm
    }

    func submitSignUp() async {
        guard var currentForm = form else { return }
        statusNotice = nil
        let validated = currentForm.validated()
        if !validated.isValid {
            form = validated
            return
        }

        isSubmitting = true
        do {
            let result = try await auth.saveChallengeSignUp(validated)
            form = result
            if result.isValid {
                statusNotice = "Sign-up submitted successfully!"
                NotificationCenter.default.post(name: .ao3CollectionChanged, object: collectionSlug)
            }
        } catch {
            currentForm.generalErrors = [UserFacingError.message(for: error)]
            form = currentForm
        }
        isSubmitting = false
    }

    func performWithdraw() async {
        guard let currentForm = form, let signUpID = currentForm.signUpID else { return }
        isWithdrawing = true
        statusNotice = nil
        do {
            try await auth.withdrawSignUp(slug: collectionSlug, signUpID: signUpID)
            statusNotice = "Sign-up withdrawn."
            NotificationCenter.default.post(name: .ao3CollectionChanged, object: collectionSlug)
            dismiss()
        } catch {
            var updated = currentForm
            updated.generalErrors = [UserFacingError.message(for: error)]
            form = updated
            isWithdrawing = false
        }
    }
}
