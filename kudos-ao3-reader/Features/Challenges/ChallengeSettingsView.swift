import SwiftUI

/// Artboard **1by** — Challenge settings.
///
/// Read-only inspection of a collection's challenge object in AO3's order:
/// type (Gift Exchange vs Prompt Meme), the schedule dates in the challenge's own
/// time zone (as AO3 prints them), sign-up requirements, and assignment tallies.
/// Matching is AO3's own algorithm, so matching actions are drawn as "Open on AO3"
/// escape hatches rather than fake local controls.
struct ChallengeSettingsView: View {
    let collectionSlug: String
    var collectionTitle: String = ""
    var viewerIsOwner: Bool

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme

    @State private var settingsForm: AO3ChallengeSettingsForm?
    @State private var tagSetLinks: [AO3CollectionTagSetLink] = []
    /// `nil` = that fetch failed; the row says so instead of showing 0.
    @State private var signUpTotal: Int?
    @State private var matchedCount: Int?
    @State private var unmatchedCount: Int?
    @State private var defaultsCount: Int?
    @State private var phase: Phase = .idle

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
            hue: CoverArt.workHue(fandoms: [], title: collectionTitle.isEmpty ? collectionSlug : collectionTitle)
        )
    }

    private var effectiveTitle: String {
        collectionTitle.isEmpty ? collectionSlug : collectionTitle
    }

    private var settings: AO3ChallengeSettings {
        settingsForm?.settings ?? AO3ChallengeSettings(
            collectionSlug: collectionSlug,
            kind: .giftExchange
        )
    }

    var body: some View {
        List {
            Section {
                header.pageBodyRow(top: 20, gutter: selfGuttered)
                introCard.pageBodyRow(top: 8, gutter: gutter)
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
        #if os(macOS)
        .navigationTitle("Challenge")
        #endif
        .subjectScreenWash(palette: palette)
        .task { await loadSettingsIfNeeded() }
        .refreshable { await loadSettings() }
            .screenTint(palette)
    }

    // MARK: - Header & Intro

    private var header: some View {
        SubjectHeaderBlock(
            kicker: "AO3 Account",
            title: "Challenge",
            subtitle: "\(effectiveTitle) · \(settings.kind.displayName)",
            palette: palette,
            gutter: SubjectMetrics.accountGutter
        )
    }

    private var introCard: some View {
        Text("AO3 keeps challenges as a second object on top of the collection, with sign-ups, "
            + "assignments and deadlines of their own. This screen is the app’s read of it — "
            + "the fields AO3 asks for, in AO3’s order.")
            .font(.system(size: 11.5))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    // MARK: - Content Sections

    @ViewBuilder
    private var contentSections: some View {
        // Only collection owners reach this read (AO3CollectionDetailView), and
        // the edit form (1cf) is theirs as well.
        if AO3CollectionOwnerControls.areVisible(viewerIsOwner: viewerIsOwner) {
            Section {
                SubjectFormRow(label: "Edit settings", showsDisclosure: true) { EmptyView() }
                    .subjectRowNavigation(accessibilityLabel: "Edit settings") {
                        ChallengeSettingsEditView(
                            collectionSlug: collectionSlug,
                            collectionTitle: effectiveTitle,
                            viewerIsOwner: viewerIsOwner
                        )
                    }
                    .subjectPanel()
                    .pageBodyRow(top: 14, gutter: gutter)
            }
        }

        Section {
            SectionRuleHeader(title: "Type")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            typePanel.pageBodyRow(top: 8, gutter: gutter)
        }

        Section {
            SectionRuleHeader(title: "Dates")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            datesPanel.pageBodyRow(top: 8, gutter: gutter)
            datesFootnote.pageBodyRow(top: 8, gutter: gutter)
        }

        Section {
            SectionRuleHeader(title: isPromptMeme ? "Prompt requirements" : "Sign-up requirements")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            requirementsPanel.pageBodyRow(top: 8, gutter: gutter)
        }

        if !tagSetLinks.isEmpty {
            Section {
                SectionRuleHeader(title: tagSetLinks.count == 1 ? "Tag set" : "Tag sets")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                tagSetsPanel.pageBodyRow(top: 8, gutter: gutter)
            }
        }

        // Prompt Meme replaces the whole lower half (the spec's second layout):
        // no sign-up matching, no assignments, nothing to run on AO3.
        if isPromptMeme {
            Section {
                SectionRuleHeader(title: "Prompts")
                    .padding(.bottom, 8)
                    .pageBodyRow(top: 18, gutter: selfGuttered)
            }
            Section {
                promptsRows
                promptsFootnote.pageBodyRow(top: 8, gutter: gutter)
            }
        } else {
            Section {
                SectionRuleHeader(title: "Assignments")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                assignmentsPanel.pageBodyRow(top: 8, gutter: gutter)
                assignmentsFootnote.pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "At AO3")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                escapeHatchPanel.pageBodyRow(top: 8, gutter: gutter)
            }
        }
    }

    private var isPromptMeme: Bool { settings.kind == .promptMeme }

    /// Two `List` rows so only the first pushes.
    @ViewBuilder
    private var promptsRows: some View {
        SubjectFormRow(label: "Prompts", value: "Claim and fill", showsDisclosure: true) { EmptyView() }
            .subjectRowNavigation(accessibilityLabel: "Prompts") {
                PromptMemeView(collectionSlug: collectionSlug, collectionTitle: effectiveTitle)
            }
            .panelSegment(0, of: 2, gutter: gutter)
        SubjectFormRow(label: "Prompts posted anonymously", value: settings.isAnonymous ? "Yes" : "No")
            .panelSegment(1, of: 2, gutter: gutter)
    }

    private var promptsFootnote: some View {
        Text("A Prompt Meme has no matching and no assignments: prompts are posted to the meme "
            + "and claimed freely, so there is nothing to match or send.")
            .font(.system(size: 11.5))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    // MARK: - Panels

    private var typePanel: some View {
        VStack(spacing: 0) {
            typeRow(
                title: "Gift Exchange",
                subtitle: "Sign-ups are matched into assignments",
                isSelected: settings.kind == .giftExchange
            )

            SubjectRowSeparator()

            typeRow(
                title: "Prompt Meme",
                subtitle: "Prompts are claimed freely",
                isSelected: settings.kind == .promptMeme
            )
        }
        .subjectPanel()
    }

    private func typeRow(title: String, subtitle: String, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var datesPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(
                label: "Sign-ups open",
                value: formatDate(settings.signupsOpenAt)
            )

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Sign-ups close",
                value: formatDate(settings.signupsCloseAt)
            )

            SubjectRowSeparator()

            // AO3 prints assignments_due_at as "Assignments Due" and mails it as
            // the deadline for works; works_reveal_at and authors_reveal_at are
            // the two reveals, never a due date.
            SubjectFormRow(
                label: "Works due",
                value: formatDate(settings.worksDueAt)
            )

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Works revealed",
                value: formatDate(settings.worksRevealAt)
            )

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Creators revealed",
                value: formatDate(settings.authorsRevealAt)
            )
        }
        .subjectPanel()
    }

    private var datesFootnote: some View {
        Text("AO3 does not close the collection on a deadline — closing is manual, "
            + "which is why collection settings keeps Closed as its own switch.")
            .font(.system(size: 11.5))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    /// The request restriction's own ranges. A prompt meme's prompts are its
    /// requests, so it also says how many one sign-up may post.
    private var requirementsPanel: some View {
        let limits = settings.limits
        let restriction = settings.requestRestriction
        let noun = isPromptMeme ? "prompt" : "request"

        return VStack(spacing: 0) {
            if isPromptMeme {
                SubjectFormRow(
                    label: "Prompts per sign-up",
                    value: "\(limits.requestsRequired) to \(limits.requestsAllowed)"
                )

                SubjectRowSeparator()
            }

            SubjectFormRow(
                label: "Fandoms per \(noun)",
                value: "\(restriction.fandomRequired) to \(restriction.fandomAllowed)"
            )

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Relationships per \(noun)",
                value: "\(restriction.relationshipRequired) to \(restriction.relationshipAllowed)"
            )

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Characters per \(noun)",
                value: "\(restriction.characterRequired) to \(restriction.characterAllowed)"
            )

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Additional tags",
                value: restriction.optionalTagsAllowed ? "Optional" : "Not allowed"
            )

            SubjectRowSeparator()

            SubjectFormRow(label: "Allow any prompt", arrangement: .control) {
                Toggle("", isOn: .constant(restriction.allowsAnyTag))
                    .labelsHidden()
                    .disabled(true)
            }

            if !isPromptMeme {
                SubjectRowSeparator()

                SubjectFormRow(label: "Require a fandom match", arrangement: .control) {
                    Toggle("", isOn: .constant(!restriction.allowAnyFandom))
                        .labelsHidden()
                        .disabled(true)
                }
            }
        }
        .subjectPanel()
    }

    /// The only route to artboard 1ch: `TagSetView` is addressed by a numeric id
    /// that AO3 publishes on the **collection profile** page, not on the
    /// collection show page. The fetch lives here rather than on
    /// `AO3CollectionDetailView` deliberately — a tag set only means anything in
    /// a challenge context, and hanging the request off collection detail would
    /// spend an extra AO3 request on every collection anyone opens, the majority
    /// of which have no challenge at all. `docs/AO3_NETWORKING_POLICY.md` treats
    /// request politeness as a product requirement, so the cost sits on the two
    /// screens that use it.
    ///
    /// `isModerator: true`, as on 1cf: only a collection owner reaches this read
    /// (AO3 prints the Challenge Settings link for owners alone and refuses the
    /// edit page this screen loads to everyone else, otwarchive Q5), so the
    /// viewer runs the challenge the tag set belongs to.
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

    private var assignmentsPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(
                label: "Sign-ups",
                value: signUpTotal.map(String.init) ?? "Couldn't load",
                showsDisclosure: true
            )
            .subjectRowNavigation(accessibilityLabel: "Sign-ups") {
                ChallengeSignUpsView(
                    collectionSlug: collectionSlug,
                    collectionTitle: effectiveTitle
                )
            }
            .buttonStyle(.plain)

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Assignments",
                value: assignmentsSummaryText,
                showsDisclosure: true
            )
            .subjectRowNavigation(accessibilityLabel: "Assignments") { assignmentsView }
            .buttonStyle(.plain)

            SubjectRowSeparator()

            // Defaults and pinch hits are listed on the same AO3 assignments page.
            SubjectFormRow(
                label: "Defaults and pinch hits",
                value: defaultsCount.map(String.init) ?? "Couldn't load",
                showsDisclosure: true
            )
            .subjectRowNavigation(accessibilityLabel: "Defaults and pinch hits") { assignmentsView }
            .buttonStyle(.plain)

        }
        .subjectPanel()
    }

    private var assignmentsFootnote: some View {
        Text("Matching is AO3’s own algorithm and runs on their side. "
            + "The app can show sign-ups and assignments and send a pinch-hit request; it cannot match.")
            .font(.system(size: 11.5))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private var escapeHatchPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(
                label: "Run matching",
                value: "Opens AO3",
                showsDisclosure: true
            ) {
                openExternalURL(settings.matchingOpenOnAO3)
            }
        }
        .subjectPanel()
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
            Button("Try Again") {
                Task { await loadSettings() }
            }
            .buttonStyle(.bordered)
            .tint(palette.tint)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .subjectPanel()
    }

    // MARK: - Helpers & Actions

    /// The date in the challenge's own zone, as AO3 prints it.
    private func formatDate(_ instant: AO3ChallengeInstant) -> String {
        instant.dateText ?? "Not set"
    }

    private func openExternalURL(_ url: URL) {
        #if os(iOS)
        UIApplication.shared.open(url)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }

    private func loadSettingsIfNeeded() async {
        guard phase == .idle else { return }
        await loadSettings()
    }

    private func loadSettings() async {
        phase = .loading
        do {
            let request = try auth.authenticatedRequest(
                for: AO3ChallengeURL.giftExchangeEdit(slug: collectionSlug)
            )
            let form = try await AO3Client.shared.challengeSettings(slug: collectionSlug, request: request)
            settingsForm = form

            // Best-effort: a collection with no tag set is the common case, and a
            // failed profile fetch must not take the whole screen down with it.
            let profileRequest = try? auth.authenticatedRequest(
                for: AO3CollectionURL.profile(slug: collectionSlug)
            )
            tagSetLinks = (try? await AO3Client.shared.collectionTagSets(
                slug: collectionSlug, request: profileRequest
            )) ?? []

            // A prompt meme has no sign-up rows or assignments to count.
            guard form.settings.kind == .giftExchange else {
                phase = .loaded
                return
            }

            signUpTotal = try? await loadSignUpTotal()

            // The same lists as 1cb, every page. Matched = Complete + Open;
            // unmatched = defaulted and uncovered; a covered default reappears in
            // Open with a pinch hitter, so defaults + covered counts each once.
            let sent = try? await assignmentRows(AO3ChallengeAssignmentList.sent)
            let defaults = try? await assignmentRows([.defaults])
            matchedCount = sent?.count
            unmatchedCount = defaults?.count
            if let sent, let defaults {
                defaultsCount = defaults.count + sent.filter(\.isCovered).count
            } else {
                defaultsCount = nil
            }

            phase = .loaded
        } catch {
            phase = .failed(UserFacingError.message(for: error))
        }
    }

    /// Every page counted, not page 1's twenty.
    private func loadSignUpTotal() async throws -> Int {
        let request = try auth.authenticatedRequest(for: AO3ChallengeURL.signUps(slug: collectionSlug))
        let firstPage = try await AO3Client.shared.challengeSignUps(slug: collectionSlug, request: request)
        return try await AO3Client.shared.challengeSignUpTotal(
            slug: collectionSlug, firstPage: firstPage, request: request
        )
    }

    private func assignmentRows(_ lists: [AO3ChallengeAssignmentList]) async throws -> [AO3ChallengeAssignment] {
        let request = try auth.authenticatedRequest(
            for: AO3ChallengeURL.assignments(slug: collectionSlug, list: lists[0])
        )
        return try await AO3Client.shared.allChallengeAssignments(
            slug: collectionSlug, lists: lists, request: request
        )
    }
}

extension ChallengeSettingsView {
    private var assignmentsView: some View {
        ChallengeAssignmentsView(
            collectionSlug: collectionSlug,
            collectionTitle: effectiveTitle,
            viewerIsOwner: viewerIsOwner
        )
    }

    private var assignmentsSummaryText: String {
        guard let matchedCount, let unmatchedCount else { return "Couldn't load" }
        // Every list empty means nothing has been sent, not that nobody matched.
        if matchedCount == 0, unmatchedCount == 0 { return "None sent yet" }
        return "\(matchedCount) matched, \(unmatchedCount) unmatched"
    }
}
