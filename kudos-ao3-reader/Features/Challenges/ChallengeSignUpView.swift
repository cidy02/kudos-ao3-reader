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

    @State var form: AO3ChallengeSignUpForm?
    @State var phase: Phase = .idle
    @State var isSubmitting: Bool = false
    @State var isWithdrawing: Bool = false
    @State var confirmWithdraw: Bool = false
    @State var statusNotice: String?
    @State var editingPromptIndex: Int?
    @State var isEditingOffer: Bool = false

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

    var limits: AO3ChallengeSignUpLimits {
        form?.limits ?? AO3ChallengeSignUpLimits(
            requestsRequired: 1,
            requestsAllowed: 3,
            offersRequired: 1,
            offersAllowed: 5
        )
    }

    var liveRequests: [AO3ChallengePrompt] {
        form?.requests.filter { !$0.destroy } ?? []
    }

    var liveOffers: [AO3ChallengePrompt] {
        form?.offers.filter { !$0.destroy } ?? []
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                List {
                    Section {
                        header.pageBodyRow(top: 20, gutter: selfGuttered)
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

                    Section {
                        Spacer(minLength: 75)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                .cardList()
                #if os(macOS)
                .navigationTitle("Your sign-up")
                #endif
                .subjectScreenWash(palette: palette)

                bottomActionBar
            }
            .task { await loadSignUpIfNeeded() }
            .refreshable { await loadSignUp() }
            .confirmationDialog(
                "Withdraw this sign-up?",
                isPresented: $confirmWithdraw,
                titleVisibility: .visible
            ) {
                Button("Withdraw Sign-up", role: .destructive) {
                    Task { await performWithdraw() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Withdrawing removes your requests and offers from \(effectiveTitle). "
                    + "If sign-ups have closed, this will record a default on your assignment.")
            }
            .sheet(isPresented: Binding(
                get: { editingPromptIndex != nil },
                set: { if !$0 { editingPromptIndex = nil } }
            )) {
                if let index = editingPromptIndex {
                    promptTagsEditor(index: index, isOffer: isEditingOffer)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        SubjectHeaderBlock(
            kicker: effectiveTitle,
            title: "Your sign-up",
            subtitle: "Request \(liveRequests.count) of \(limits.requestsAllowed) · "
                + "Offer \(liveOffers.count) of \(limits.offersAllowed)",
            palette: palette,
            gutter: SubjectMetrics.accountGutter
        )
    }

    // MARK: - Content Sections

    @ViewBuilder
    private var contentSections: some View {
        if let requestError = form?.fieldErrors["requests"] {
            Section {
                errorCard(requestError).pageBodyRow(top: 8, gutter: gutter)
            }
        }

        ForEach(Array(liveRequests.enumerated()), id: \.element.id) { index, request in
            Section {
                SectionRuleHeader(title: "Request \(index + 1)")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                requestPanel(index: index, prompt: request)
                    .pageBodyRow(top: 8, gutter: gutter)
                promptDescriptionCard(index: index, isOffer: false)
                    .pageBodyRow(top: 8, gutter: gutter)
            }
        }

        Section {
            requestsFootnote.pageBodyRow(top: 8, gutter: gutter)
        }

        Section {
            SectionRuleHeader(title: "Offers")
                .pageBodyRow(top: 18, gutter: selfGuttered)

            if let offerError = form?.fieldErrors["offers"] {
                errorCard(offerError).pageBodyRow(top: 8, gutter: gutter)
            }

            offersPanel.pageBodyRow(top: 8, gutter: gutter)
            offersFootnote.pageBodyRow(top: 8, gutter: gutter)
        }

        if form?.signUpID != nil {
            Section {
                SectionRuleHeader(title: "Withdraw")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                withdrawPanel.pageBodyRow(top: 8, gutter: gutter)
            }
        }
    }
}

// MARK: - Panels and Rows

extension ChallengeSignUpView {

    func requestPanel(index: Int, prompt: AO3ChallengePrompt) -> some View {
        VStack(spacing: 0) {
            SubjectFormRow(
                label: "Fandoms",
                value: prompt.fandoms.isEmpty ? "None chosen" : prompt.fandoms.joined(separator: ", "),
                showsDisclosure: true
            ) {
                isEditingOffer = false
                editingPromptIndex = index
            }

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Relationships",
                value: prompt.relationships.isEmpty
                    ? "Optional"
                    : "\(prompt.relationships.count) chosen",
                showsDisclosure: true
            ) {
                isEditingOffer = false
                editingPromptIndex = index
            }

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Characters",
                value: prompt.characters.isEmpty
                    ? "Optional"
                    : "\(prompt.characters.count) chosen",
                showsDisclosure: true
            ) {
                isEditingOffer = false
                editingPromptIndex = index
            }

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Additional tags",
                value: prompt.freeforms.isEmpty
                    ? "Optional"
                    : "\(prompt.freeforms.count) chosen",
                showsDisclosure: true
            ) {
                isEditingOffer = false
                editingPromptIndex = index
            }

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Any of these is fine",
                arrangement: .control
            ) {
                Toggle("", isOn: Binding(
                    get: { form?.requests[index].anyRelationship ?? false },
                    set: { form?.requests[index].anyRelationship = $0 }
                ))
                .labelsHidden()
                .tint(palette.accent)
            }
        }
        .subjectPanel()
    }

    func promptDescriptionCard(index: Int, isOffer: Bool) -> some View {
        let binding = Binding<String>(
            get: {
                if isOffer {
                    return form?.offers[index].promptText ?? ""
                }
                return form?.requests[index].promptText ?? ""
            },
            set: {
                if isOffer {
                    form?.offers[index].promptText = $0
                } else {
                    form?.requests[index].promptText = $0
                }
            }
        )

        return VStack(alignment: .leading, spacing: 7) {
            SubjectFieldLabel(text: "Prompt", style: .formGroup)

            ZStack(alignment: .topLeading) {
                if binding.wrappedValue.isEmpty {
                    Text("Describe what you would love to receive…")
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                }

                TextEditor(text: binding)
                    .font(.system(size: 14, design: .serif))
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }

            HStack {
                Text("Visible to your recipient only")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary.opacity(0.8))

                Spacer()

                Text("\(binding.wrappedValue.count) / 1000")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.8))
            }
        }
        .padding(14)
        .subjectPanel()
    }

    var requestsFootnote: some View {
        Text("The challenge asks for \(limits.requestsRequired) to \(limits.requestsAllowed) requests "
            + "and \(limits.offersRequired) to \(limits.offersAllowed) offers per sign-up. "
            + "Those limits are checked locally before submit, so a rejected sign-up is not a round trip.")
            .font(.system(size: 11.5))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    var offersPanel: some View {
        VStack(spacing: 0) {
            ForEach(Array(liveOffers.enumerated()), id: \.element.id) { index, offer in
                if index > 0 {
                    SubjectRowSeparator()
                }

                SubjectFormRow(
                    label: "Offer \(index + 1)",
                    value: offerSummary(offer),
                    showsDisclosure: true
                ) {
                    isEditingOffer = true
                    editingPromptIndex = index
                }
            }

            if liveOffers.count < limits.offersAllowed {
                if !liveOffers.isEmpty {
                    SubjectRowSeparator()
                }

                Button {
                    addNewOffer()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 15))
                            .foregroundStyle(palette.accent)

                        Text("Add an offer")
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.secondary.opacity(0.42))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .subjectPanel()
    }

    func offerSummary(_ offer: AO3ChallengePrompt) -> String {
        let tagCount = offer.relationships.count + offer.characters.count + offer.freeforms.count
        let fandomName = offer.fandoms.first ?? "Any Fandom"
        if tagCount > 0 {
            return "\(fandomName) · \(tagCount) \(tagCount == 1 ? "tag" : "tags")"
        }
        return fandomName
    }

    var offersFootnote: some View {
        Text("Sign-ups can be edited until they close and withdrawn after, "
            + "which AO3 treats as two different writes.")
            .font(.system(size: 11.5))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    var withdrawPanel: some View {
        VStack(spacing: 0) {
            Button {
                confirmWithdraw = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.red)
                        .frame(width: 20)

                    Text("Withdraw sign-up")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.red)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isWithdrawing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isWithdrawing)
        }
        .subjectPanel()
    }

    var bottomActionBar: some View {
        HStack(spacing: 9) {
            Button {
                addNewRequest()
            } label: {
                Text("Add request")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(theme.appTheme.glassFill(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(theme.appTheme.glassStroke(0.16), lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(liveRequests.count >= limits.requestsAllowed || isSubmitting)

            Button {
                Task { await submitSignUp() }
            } label: {
                HStack(spacing: 6) {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(palette.accentOnFill)
                    }
                    Text("Submit sign-up")
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
            .disabled(isSubmitting)
        }
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

    func promptTagsEditor(index: Int, isOffer: Bool) -> some View {
        PromptTagsEditorView(
            prompt: Binding(
                get: {
                    if isOffer {
                        return form?.offers[index] ?? AO3ChallengePrompt(id: index, kind: .offer)
                    }
                    return form?.requests[index] ?? AO3ChallengePrompt(id: index, kind: .request)
                },
                set: {
                    if isOffer {
                        form?.offers[index] = $0
                    } else {
                        form?.requests[index] = $0
                    }
                }
            ),
            palette: palette,
            isOffer: isOffer,
            index: index
        )
    }

    func noticeCard(_ text: String) -> some View {
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

    func errorCard(_ text: String) -> some View {
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

    var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading sign-up…")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }

    func failureCard(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Couldn't load sign-up")
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadSignUp() }
            }
            .buttonStyle(.bordered)
            .tint(palette.accent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .subjectPanel()
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
            phase = .failed(error.localizedDescription)
        }
    }

    func ensureMinimumPrompts() {
        guard var currentForm = form else { return }
        if currentForm.requests.isEmpty {
            currentForm.requests.append(AO3ChallengePrompt(id: -1, kind: .request))
        }
        if currentForm.offers.isEmpty {
            currentForm.offers.append(AO3ChallengePrompt(id: -2, kind: .offer))
        }
        form = currentForm
    }

    func addNewRequest() {
        guard var currentForm = form else { return }
        let nextID = -(currentForm.requests.count + 1)
        currentForm.requests.append(AO3ChallengePrompt(id: nextID, kind: .request))
        form = currentForm
    }

    func addNewOffer() {
        guard var currentForm = form else { return }
        let nextID = -(currentForm.offers.count + 1)
        currentForm.offers.append(AO3ChallengePrompt(id: nextID, kind: .offer))
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
            }
        } catch {
            currentForm.generalErrors = [error.localizedDescription]
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
            dismiss()
        } catch {
            var updated = currentForm
            updated.generalErrors = [error.localizedDescription]
            form = updated
            isWithdrawing = false
        }
    }
}
