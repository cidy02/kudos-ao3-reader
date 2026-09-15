import SwiftUI

/// Artboard **1by** — Challenge settings.
///
/// Read-only inspection of a collection's challenge object in AO3's order:
/// type (Gift Exchange vs Prompt Meme), the five UTC schedule dates round-tripped
/// to the device timezone, sign-up requirements, and assignment tallies.
/// Matching is AO3's own algorithm, so matching actions are drawn as "Open on AO3"
/// escape hatches rather than fake local controls.
struct ChallengeSettingsView: View {
    let collectionSlug: String
    var collectionTitle: String = ""

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme

    @State private var settingsForm: AO3ChallengeSettingsForm?
    @State private var tagSetLinks: [AO3CollectionTagSetLink] = []
    @State private var signUpCount: Int = 0
    @State private var matchedCount: Int = 0
    @State private var unmatchedCount: Int = 0
    @State private var defaultsCount: Int = 0
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
        #if os(macOS)
        .navigationTitle("Challenge")
        #endif
        .subjectScreenWash(palette: palette)
        .task { await loadSettingsIfNeeded() }
        .refreshable { await loadSettings() }
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
            SectionRuleHeader(title: "Sign-up requirements")
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
                value: formatDate(settings.signupsOpenAt),
                isMonospaced: true
            )

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Sign-ups close",
                value: formatDate(settings.signupsCloseAt),
                isMonospaced: true
            )

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Assignments due",
                value: formatDate(settings.assignmentsDueAt),
                isMonospaced: true
            )

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Works due",
                value: formatDate(settings.worksRevealAt),
                isMonospaced: true
            )

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Reveal",
                value: formatDate(settings.authorsRevealAt),
                isMonospaced: true
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

    private var requirementsPanel: some View {
        let limits = settings.limits
        let restriction = settings.requestRestriction
        let fandomReq = restriction.fandomRequired > 0 ? restriction.fandomRequired : limits.requestsRequired
        let fandomAllowed = restriction.fandomAllowed > 0 ? restriction.fandomAllowed : limits.requestsAllowed
        let relReq = restriction.relationshipRequired
        let relAllowed = restriction.relationshipAllowed
        let charReq = restriction.characterRequired
        let charAllowed = restriction.characterAllowed

        return VStack(spacing: 0) {
            SubjectFormRow(
                label: "Fandoms per request",
                value: "\(fandomReq) to \(fandomAllowed)",
                isMonospaced: true
            )

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Relationships per request",
                value: "\(relReq) to \(relAllowed)",
                isMonospaced: true
            )

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Characters per request",
                value: "\(charReq) to \(charAllowed)",
                isMonospaced: true
            )

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Additional tags",
                value: restriction.optionalTagsAllowed ? "Optional" : "Required"
            )

            SubjectRowSeparator()

            SubjectFormRow(label: "Allow any prompt", arrangement: .control) {
                Toggle("", isOn: .constant(!restriction.descriptionRequired))
                    .labelsHidden()
                    .disabled(true)
            }

            SubjectRowSeparator()

            SubjectFormRow(label: "Require a fandom match", arrangement: .control) {
                Toggle("", isOn: .constant(!restriction.allowAnyFandom))
                    .labelsHidden()
                    .disabled(true)
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
    /// `isModerator: false` here: 1by is the read-only view of the challenge,
    /// reachable by anyone who can see the collection, so it cannot honestly
    /// claim the reader moderates the tag set. The kicker says "owner", which is
    /// what `TagSetView` shows for a plain reader. 1cf passes `true` instead.
    private var tagSetsPanel: some View {
        VStack(spacing: 0) {
            ForEach(Array(tagSetLinks.enumerated()), id: \.element.id) { index, link in
                if index > 0 { SubjectRowSeparator() }
                SubjectFormRow(label: link.title, showsDisclosure: true) { EmptyView() }
                    .subjectRowNavigation(accessibilityLabel: link.title) {
                        TagSetView(tagSetID: link.id, tagSetTitle: link.title, isModerator: false)
                    }
            }
        }
        .subjectPanel()
    }

    private var assignmentsPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(
                label: "Sign-ups",
                value: "\(signUpCount)",
                showsDisclosure: true,
                isMonospaced: true
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
                value: assignmentsSummaryText
            )

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Defaults and pinch hits",
                value: "\(defaultsCount)",
                isMonospaced: true
            )

        }
        .subjectPanel()
    }

    private var assignmentsSummaryText: String {
        if matchedCount == 0 && unmatchedCount == 0 {
            return "No assignments found"
        }
        return "\(matchedCount) matched, \(unmatchedCount) unmatched"
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

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Edit challenge on AO3",
                value: "Opens AO3",
                showsDisclosure: true
            ) {
                let editURL = settings.kind == .giftExchange
                    ? AO3ChallengeURL.giftExchangeEdit(slug: collectionSlug)
                    : AO3ChallengeURL.promptMemeEdit(slug: collectionSlug)
                openExternalURL(editURL)
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
            Button("Retry") {
                Task { await loadSettings() }
            }
            .buttonStyle(.bordered)
            .tint(palette.accent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .subjectPanel()
    }

    // MARK: - Helpers & Actions

    private func formatDate(_ instant: AO3ChallengeInstant) -> String {
        if let date = instant.date {
            let formatter = DateFormatter()
            formatter.locale = Locale.autoupdatingCurrent
            formatter.timeZone = TimeZone.autoupdatingCurrent
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
        return instant.wireString.isEmpty ? "Not set" : instant.wireString
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

            // Load signups count
            if let signUpsRequest = try? auth.authenticatedRequest(
                for: AO3ChallengeURL.signUps(slug: collectionSlug, page: 1)
            ), let signUpsPage = try? await AO3Client.shared.challengeSignUps(
                slug: collectionSlug, page: 1, request: signUpsRequest
            ) {
                signUpCount = signUpsPage.signUps.count
            }

            // KNOWN DEFECT work-around: parseChallengeAssignmentsPage does not match real
            // otwarchive markup. If it fails to parse, degrade gracefully to 0 rather than throwing.
            if let assignmentsRequest = try? auth.authenticatedRequest(
                for: AO3ChallengeURL.assignments(slug: collectionSlug, list: .assignments, page: 1)
            ), let assignmentsPage = try? await AO3Client.shared.challengeAssignments(
                slug: collectionSlug, list: .assignments, page: 1, request: assignmentsRequest
            ) {
                matchedCount = assignmentsPage.assignments.filter(\.isMatched).count
                unmatchedCount = assignmentsPage.assignments.filter { !$0.isMatched }.count
            }

            if let defaultsRequest = try? auth.authenticatedRequest(
                for: AO3ChallengeURL.assignments(slug: collectionSlug, list: .defaults, page: 1)
            ), let defaultsPage = try? await AO3Client.shared.challengeAssignments(
                slug: collectionSlug, list: .defaults, page: 1, request: defaultsRequest
            ) {
                defaultsCount = defaultsPage.assignments.count
            }

            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
