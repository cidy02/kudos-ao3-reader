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
    /// Kind already read from the collection page. Nil keeps the gift-then-meme probe.
    var challengeKind: AO3ChallengeKind?

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme

    @ScaledMetric(relativeTo: .largeTitle) private var hubTitleSize: CGFloat = 30
    @ScaledMetric(relativeTo: .subheadline) private var hubSubtitleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .footnote) private var hubKickerSize: CGFloat = 13
    @ScaledMetric(relativeTo: .subheadline) private var loadingSize: CGFloat = 14
    @ScaledMetric(relativeTo: .headline) private var failureTitleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .footnote) private var failureBodySize: CGFloat = 13

    @State private var settingsForm: AO3ChallengeSettingsForm?
    @State private var tagSetLinks: [AO3CollectionTagSetLink] = []
    /// `nil` = that fetch failed; the row says so instead of showing 0.
    @State private var signUpTotal: Int?
    @State private var matchedCount: Int?
    @State private var unmatchedCount: Int?
    @State private var phase: Phase = .idle
    @State private var showingCollectionSettings = false
    #if DEBUG
    @State private var debugPresented: DebugPresented?
    #endif

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
            kind: challengeKind ?? .giftExchange
        )
    }

    var body: some View {
        List {
            Section {
                hubHeader.pageBodyRow(top: 12, gutter: gutter)
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
        .subjectScreenWash(title: "", palette: palette, role: .grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if AO3CollectionOwnerControls.areVisible(viewerIsOwner: viewerIsOwner) {
                        Button {
                            showingCollectionSettings = true
                        } label: {
                            Label("Collection Settings", systemImage: "slider.horizontal.3")
                        }
                    }
                    if !isPromptMeme {
                        Button {
                            openExternalURL(settings.matchingOpenOnAO3)
                        } label: {
                            Label("Run Matching on AO3", systemImage: "safari")
                        }
                    }
                    if let url = AO3CollectionURL.show(slug: collectionSlug) {
                        Button {
                            openExternalURL(url)
                        } label: {
                            Label("Open on AO3", systemImage: "arrow.up.right.square")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
        .navigationDestination(isPresented: $showingCollectionSettings) {
            AO3CollectionFormView(slug: collectionSlug)
        }
        .task { await loadSettingsIfNeeded() }
        #if DEBUG
        .task {
            guard DebugLaunchRoute.wantsPush("chsettingsedit") || DebugLaunchRoute.wantsPush("tagset") else { return }
            if let id = DebugLaunchRoute.takeFirstPush(["chsettingsedit", "tagset"]) {
                debugPresented = DebugPresented(id: id)
            }
        }
        .navigationDestination(item: $debugPresented) { presented in
            if presented.id == "tagset" {
                TagSetView(tagSetID: 42, tagSetTitle: "Winter Exchange Tags", isModerator: true)
            } else {
                ChallengeSettingsEditView(
                    collectionSlug: collectionSlug,
                    collectionTitle: effectiveTitle,
                    viewerIsOwner: viewerIsOwner,
                    challengeKind: challengeKind
                )
            }
        }
        #endif
        .refreshable { await loadSettings() }
        .onReceive(NotificationCenter.default.publisher(for: .ao3CollectionChanged)) { notification in
            guard notification.object as? String == collectionSlug else { return }
            Task { await loadSettings() }
        }
            .screenTint(palette)
    }

    // MARK: - Header (`Challenge.dc.html`)

    private var hubHeader: some View {
        let subtitle = ChallengesBoardCopy.challengeHubSubtitle(
            signupOpen: settings.signupOpen,
            closeDateText: settings.signupsCloseAt.dateText,
            signUpTotal: isPromptMeme ? nil : signUpTotal,
            isLoaded: phase == .loaded
        )
        return VStack(alignment: .leading, spacing: 4) {
            Text(ChallengesBoardCopy.challengeKindName(settings.kind))
                .font(.system(size: hubKickerSize))
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            Text(effectiveTitle)
                .font(.system(size: hubTitleSize, weight: .bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: hubSubtitleSize))
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    // MARK: - Hub Rows (`Challenge.dc.html`)

    private struct HubRowEntry {
        let id: String
        let systemImage: String
        let title: String
        let detail: String?
        let destination: () -> AnyView

        init<Destination: View>(
            id: String,
            systemImage: String,
            title: String,
            detail: String? = nil,
            @ViewBuilder destination: @escaping () -> Destination
        ) {
            self.id = id
            self.systemImage = systemImage
            self.title = title
            self.detail = detail
            self.destination = { AnyView(destination()) }
        }
    }

    private var hubEntries: [HubRowEntry] {
        var entries: [HubRowEntry] = [
            HubRowEntry(id: "items", systemImage: "doc.text", title: "Items") {
                AO3CollectionItemsView(slug: collectionSlug, title: effectiveTitle)
            }
        ]

        if isPromptMeme {
            entries.append(
                HubRowEntry(id: "prompts", systemImage: "bubble.left", title: "Prompts", detail: "Claim and fill") {
                    PromptMemeView(
                        collectionSlug: collectionSlug,
                        collectionTitle: effectiveTitle,
                        viewerIsOwner: viewerIsOwner,
                        challengeKind: challengeKind
                    )
                }
            )
        } else {
            entries.append(
                HubRowEntry(
                    id: "signups",
                    systemImage: "person",
                    title: "Sign-ups",
                    detail: phase == .loaded ? (signUpTotal.map { $0.formatted() } ?? "Couldn't load") : nil
                ) {
                    ChallengeSignUpsView(
                        collectionSlug: collectionSlug,
                        collectionTitle: effectiveTitle,
                        challengeKind: challengeKind
                    )
                }
            )
            entries.append(
                HubRowEntry(
                    id: "assignments",
                    systemImage: "envelope",
                    title: "Assignments",
                    detail: phase == .loaded ? assignmentsSummaryText : nil
                ) {
                    assignmentsView
                }
            )
        }

        if let firstTagSet = tagSetLinks.first {
            let tagDetail = tagSetLinks.count == 1 ? firstTagSet.title : "\(tagSetLinks.count) tag sets"
            entries.append(
                HubRowEntry(
                    id: "tagset",
                    systemImage: "tag",
                    title: "Prompts and tag set",
                    detail: tagDetail
                ) {
                    TagSetView(tagSetID: firstTagSet.id, tagSetTitle: firstTagSet.title, isModerator: true)
                }
            )
        }

        entries.append(
            HubRowEntry(
                id: "moderation",
                systemImage: "shield",
                title: "Moderation",
                detail: settings.isAnonymous ? "Anonymous" : nil
            ) {
                CollectionModerationView(
                    collectionSlug: collectionSlug,
                    collectionTitle: effectiveTitle,
                    viewerIsOwner: viewerIsOwner
                )
            }
        )

        entries.append(
            HubRowEntry(id: "maintainers", systemImage: "person.2", title: "Maintainers") {
                CollectionMaintainersView(collectionSlug: collectionSlug, collectionTitle: effectiveTitle)
            }
        )

        if AO3CollectionOwnerControls.areVisible(viewerIsOwner: viewerIsOwner) {
            entries.append(
                HubRowEntry(id: "settings", systemImage: "slider.horizontal.3", title: "Challenge settings") {
                    ChallengeSettingsEditView(
                        collectionSlug: collectionSlug,
                        collectionTitle: effectiveTitle,
                        viewerIsOwner: viewerIsOwner,
                        challengeKind: challengeKind
                    )
                }
            )
        }

        return entries
    }

    // MARK: - Content Sections

    @ViewBuilder
    private var contentSections: some View {
        let entries = hubEntries
        Section {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                let a11yParts: [String?] = [entry.title, entry.detail]
                let a11y = a11yParts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
                ChallengeBoardHubRow(
                    systemImage: entry.systemImage,
                    title: entry.title,
                    detail: entry.detail
                )
                .subjectRowNavigation(accessibilityLabel: a11y) {
                    entry.destination()
                }
                .panelSegment(index, of: entries.count, gutter: gutter)
            }
        }

        Section {
            ChallengeBoardSectionHeader(title: "Schedule")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            datesPanel.pageBodyRow(top: 6, gutter: gutter)
            datesFootnote.pageBodyRow(top: 6, gutter: gutter)
        }

        Section {
            ChallengeBoardSectionHeader(
                title: isPromptMeme ? "Prompt requirements" : "Sign-up requirements"
            )
            .pageBodyRow(top: 18, gutter: selfGuttered)
            requirementsPanel.pageBodyRow(top: 6, gutter: gutter)
        }

        if tagSetLinks.count > 1 {
            Section {
                ChallengeBoardSectionHeader(title: "Tag sets")
                    .padding(.bottom, 6)
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                ForEach(Array(tagSetLinks.enumerated()), id: \.element.id) { index, link in
                    SubjectFormRow(label: link.title, showsDisclosure: true) { EmptyView() }
                        .subjectRowNavigation(accessibilityLabel: link.title) {
                            TagSetView(tagSetID: link.id, tagSetTitle: link.title, isModerator: true)
                        }
                        .panelSegment(index, of: tagSetLinks.count, gutter: gutter)
                }
            }
        }

        if isPromptMeme {
            Section {
                promptsFootnote.pageBodyRow(top: 10, gutter: gutter)
            }
        } else {
            Section {
                ChallengeBoardSectionHeader(title: "At AO3")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                escapeHatchPanel.pageBodyRow(top: 6, gutter: gutter)
                assignmentsFootnote.pageBodyRow(top: 6, gutter: gutter)
            }
        }
    }

    private var isPromptMeme: Bool { settings.kind == .promptMeme }

    private var promptsFootnote: some View {
        ChallengeBoardSectionFooter(
            text: "A prompt meme has no matching or assignments. People post prompts and others claim them.",
            horizontalInset: 16
        )
    }

    // MARK: - Panels

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
        .challengeBoardCard()
    }

    private var datesFootnote: some View {
        ChallengeBoardSectionFooter(
            text: "AO3 doesn't close the collection when a deadline passes. You close it yourself "
                + "with the Closed setting.",
            horizontalInset: 16
        )
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
                    value: ChallengesBoardCopy.countRange(limits.requestsRequired, limits.requestsAllowed)
                )

                SubjectRowSeparator()
            } else {
                SubjectFormRow(
                    label: "Requests per person",
                    value: ChallengesBoardCopy.countRange(limits.requestsRequired, limits.requestsAllowed)
                )

                SubjectRowSeparator()

                SubjectFormRow(
                    label: "Offers per person",
                    value: ChallengesBoardCopy.countRange(limits.offersRequired, limits.offersAllowed)
                )

                SubjectRowSeparator()
            }

            SubjectFormRow(
                label: "Fandoms per \(noun)",
                value: ChallengesBoardCopy.countRange(restriction.fandomRequired, restriction.fandomAllowed)
            )

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Relationships per \(noun)",
                value: ChallengesBoardCopy.countRange(restriction.relationshipRequired, restriction.relationshipAllowed)
            )

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Characters per \(noun)",
                value: ChallengesBoardCopy.countRange(restriction.characterRequired, restriction.characterAllowed)
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
                    .accentFill()
            }

            if !isPromptMeme {
                SubjectRowSeparator()

                SubjectFormRow(label: "Require a fandom match", arrangement: .control) {
                    Toggle("", isOn: .constant(!restriction.allowAnyFandom))
                        .labelsHidden()
                        .disabled(true)
                        .accentFill()
                }
            }
        }
        .challengeBoardCard()
    }

    private var assignmentsFootnote: some View {
        ChallengeBoardSectionFooter(
            text: "AO3 matches participants. In Kudos, you can view sign-ups and assignments and ask for "
                + "a pinch hitter, but you can't run the match.",
            horizontalInset: 16
        )
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
        .challengeBoardCard()
    }
}

// MARK: - State Cards and loading

private extension ChallengeSettingsView {
    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .accentFill()
            Text("Loading challenge settings…")
                .font(.system(size: loadingSize))
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }

    private func failureCard(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Couldn't load challenge settings")
                .font(.system(size: failureTitleSize, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.system(size: failureBodySize))
                .foregroundStyle(.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again") {
                Task { await loadSettings() }
            }
            .buttonStyle(.kudosSecondary)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .challengeBoardCard()
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
            let form = try await AO3Client.shared.challengeSettings(
                slug: collectionSlug, request: request, kind: challengeKind
            )
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
            viewerIsOwner: viewerIsOwner,
            challengeKind: challengeKind
        )
    }

    private var assignmentsSummaryText: String {
        ChallengesBoardCopy.challengeAssignmentsSummary(
            matched: matchedCount,
            unmatched: unmatchedCount
        )
    }
}
