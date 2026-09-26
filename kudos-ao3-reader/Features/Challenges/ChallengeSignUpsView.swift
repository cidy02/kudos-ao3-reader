import SwiftUI

/// Artboard **1bz** — Challenge sign-ups.
///
/// Moderator view of participants who signed up for the challenge, showing matched
/// state joined client-side with assignment records. Provides All / Matched /
/// Unmatched segmented filtering, a single-line request tag summary per row, and
/// shortcuts to view or create your own sign-up.
struct ChallengeSignUpsView: View {
    let collectionSlug: String
    var collectionTitle: String = ""

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme

    @State private var signUps: [AO3ChallengeSignUp] = []
    @State private var currentPage: Int = 1
    @State private var totalPages: Int = 1
    @State private var filterSelection: SignUpFilter = .all
    @State private var phase: Phase = .idle
    @State private var closeDateText: String = ""
    /// Every assignment the rows are joined to, read once per refresh. `nil`
    /// means the fetch failed, so match state is unknown rather than unmatched.
    @State private var assignments: [AO3ChallengeAssignment]?
    @State private var matchError: String?
    /// The challenge's total, not the pages fetched; `nil` until known.
    @State private var signUpTotal: Int?

    enum SignUpFilter: String, CaseIterable, Hashable, Sendable {
        case all = "All"
        case matched = "Matched"
        case unmatched = "Unmatched"
    }

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

    private func matchState(_ signUp: AO3ChallengeSignUp) -> AO3ChallengeSignUpMatching.State {
        AO3ChallengeSignUpMatching.state(of: signUp, assignmentsLoaded: assignments != nil)
    }

    private var filteredSignUps: [AO3ChallengeSignUp] {
        switch filterSelection {
        case .all:
            return signUps
        case .matched:
            return signUps.filter { matchState($0) == .matched }
        case .unmatched:
            return signUps.filter { matchState($0) == .unmatched }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            List {
                Section {
                    header.pageBodyRow(top: 20, gutter: selfGuttered)
                    filterSegment.pageBodyRow(top: 14, gutter: gutter)
                }

                switch phase {
                case .loading where signUps.isEmpty:
                    Section {
                        loadingRow.pageBodyRow(top: 20, gutter: gutter)
                    }
                case let .failed(message) where signUps.isEmpty:
                    Section {
                        failureCard(message).pageBodyRow(top: 14, gutter: gutter)
                    }
                default:
                    contentSections
                }

                // Space for floating bottom action bar
                Section {
                    Spacer(minLength: 70)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .cardList()
            #if os(macOS)
            .navigationTitle("Sign-ups")
            #endif
            .subjectScreenWash(palette: palette)

            bottomActionBar
        }
        .task { await loadSignUpsIfNeeded() }
        .refreshable { await loadSignUps(resetPage: true) }
    }

    // MARK: - Header & Filter

    private var subtitleText: String {
        var parts: [String] = []
        if let signUpTotal {
            parts.append(AO3ChallengeCountText.plural(signUpTotal, "sign-up"))
        }
        if !closeDateText.isEmpty {
            parts.append(closeDateText)
        }
        return parts.joined(separator: " · ")
    }

    private var header: some View {
        SubjectHeaderBlock(
            kicker: effectiveTitle,
            title: "Sign-ups",
            subtitle: subtitleText,
            palette: palette,
            gutter: SubjectMetrics.accountGutter
        )
    }

    private var filterSegment: some View {
        SubjectSegmentedControl(
            options: SignUpFilter.allCases,
            title: \.rawValue,
            selection: $filterSelection
        )
    }

    // MARK: - Content Sections

    @ViewBuilder
    private var contentSections: some View {
        Section {
            SectionRuleHeader(title: "Sign-ups", count: filteredSignUps.count)
                .padding(.bottom, 8)
                .pageBodyRow(top: 18, gutter: selfGuttered)

            if let matchError {
                matchUnavailableNote(matchError).padding(.bottom, 8).pageBodyRow(top: 0, gutter: gutter)
            }

            if filteredSignUps.isEmpty {
                emptyFilteredCard.pageBodyRow(top: 0, gutter: gutter)
            } else {
                signUpRows
            }

            footnoteText.pageBodyRow(top: 8, gutter: gutter)
        }

        if currentPage < totalPages {
            Section {
                loadMoreRow.pageBodyRow(top: 10, gutter: gutter)
            }
        }
    }

    /// One `List` row per sign-up: a row is one tap target, so a card holding
    /// every sign-up in a single row would push them all at once.
    private var signUpRows: some View {
        let rows = PanelSegment.keyed(filteredSignUps, id: \.id)
        return ForEach(rows, id: \.key) { row in
            signUpRow(row.element)
                .subjectRowNavigation(accessibilityLabel: row.element.pseud) {
                    ChallengeSignUpDetailView(signUp: row.element, collectionTitle: effectiveTitle, palette: palette)
                }
                .panelSegment(row.offset, of: rows.count, gutter: gutter)
        }
    }

    private func signUpRow(_ signUp: AO3ChallengeSignUp) -> some View {
        HStack(alignment: .top, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center, spacing: 7) {
                    Text(signUp.pseud)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    matchedStatusBadge(matchState(signUp))
                }

                Text(AO3ChallengeCountText.plural(signUp.requests.count, "request")
                    + " · " + AO3ChallengeCountText.plural(signUp.offers.count, "offer"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.secondary.opacity(0.85))
                    .monospacedDigit()

                if !signUp.requestTagSummary.isEmpty {
                    Text(signUp.requestTagSummary)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary.opacity(0.65))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(0.42))
                .padding(.top, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    /// No chip at all when the state is unknown: a guess would be a false claim.
    @ViewBuilder
    private func matchedStatusBadge(_ state: AO3ChallengeSignUpMatching.State) -> some View {
        if state != .unknown {
            statusChip(isMatched: state == .matched)
        }
    }

    private func statusChip(isMatched: Bool) -> some View {
        Text(isMatched ? "MATCHED" : "UNMATCHED")
            .font(.system(size: 8.5, weight: .bold))
            .tracking(8.5 * 0.07)
            .foregroundStyle(isMatched ? palette.accent : Color.secondary.opacity(0.7))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isMatched ? palette.accent.opacity(0.18) : Color.white.opacity(0.10))
            )
    }

    private func matchUnavailableNote(_ message: String) -> some View {
        Label("Match state unavailable: AO3 shows assignments to maintainers once sign-ups close. "
            + message, systemImage: "exclamationmark.triangle")
            .font(.system(size: 11.5))
            .foregroundStyle(Color.secondary.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private var emptyFilteredCard: some View {
        let unknown = assignments == nil && filterSelection != .all
        return VStack(spacing: 6) {
            Text(unknown ? "Match state unavailable" : "No \(filterSelection.rawValue.lowercased()) sign-ups")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            Text(unknown
                ? "Assignments couldn't be loaded, so no sign-up can be shown as matched or unmatched."
                : "No sign-ups in this page match the \"\(filterSelection.rawValue)\" filter.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .subjectPanel()
    }

    private var footnoteText: some View {
        Text("AO3 pages sign-ups twenty to a page, so the list is fetched a page at a time "
            + "and the segment filters what has been fetched, not the whole challenge. "
            + "The tag summary is the sign-up’s own requests, truncated to one line.")
            .font(.system(size: 11.5))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private var loadMoreRow: some View {
        Button {
            Task { await loadNextPage() }
        } label: {
            HStack {
                if phase == .loading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                }
                Text("Load page \(currentPage + 1) of \(totalPages)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.accent)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .disabled(phase == .loading)
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        HStack(spacing: 9) {
            NavigationLink {
                ChallengeSignUpView(
                    collectionSlug: collectionSlug,
                    collectionTitle: effectiveTitle,
                    existingSignUpID: AO3ChallengeSignUpMatching.ownSignUpID(
                        in: signUps, login: auth.username ?? ""
                    )
                )
            } label: {
                Text("Your sign-up")
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

            NavigationLink {
                ChallengeSignUpView(collectionSlug: collectionSlug, collectionTitle: effectiveTitle)
            } label: {
                Text("Create sign-up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.accentOnFill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(palette.accent)
                    )
            }
            .buttonStyle(.plain)
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

    // MARK: - State Cards

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading sign-ups…")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }

    private func failureCard(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Couldn't load sign-ups")
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadSignUps(resetPage: true) }
            }
            .buttonStyle(.bordered)
            .tint(palette.accent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .subjectPanel()
    }

    // MARK: - Actions

    private func loadSignUpsIfNeeded() async {
        guard phase == .idle else { return }
        await loadSignUps(resetPage: true)
    }

    private func loadSignUps(resetPage: Bool) async {
        if resetPage {
            currentPage = 1
        }
        phase = .loading

        if resetPage {
            await loadSchedule()
            await loadAssignments()
        }

        do {
            let request = try auth.authenticatedRequest(
                for: AO3ChallengeURL.signUps(slug: collectionSlug, page: currentPage)
            )
            let page = try await AO3Client.shared.challengeSignUps(
                slug: collectionSlug, page: currentPage, request: request
            )
            let rows = assignments.map {
                AO3ChallengeSignUpMatching.joining(page.signUps, assignments: $0)
            } ?? page.signUps
            if resetPage {
                signUps = rows
                // No total rather than page 1's count passed off as one.
                signUpTotal = try? await AO3Client.shared.challengeSignUpTotal(
                    slug: collectionSlug, firstPage: page, request: request
                )
            } else {
                signUps.append(contentsOf: rows)
            }
            totalPages = page.totalPages
            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Owner-only edit form, so a moderator just gets no date. AO3's own form
    /// says its dates do nothing and sign-ups open and close by hand, so the
    /// switch decides "open", not the close date.
    private func loadSchedule() async {
        guard let request = try? auth.authenticatedRequest(
            for: AO3ChallengeURL.giftExchangeEdit(slug: collectionSlug)
        ), let form = try? await AO3Client.shared.challengeSettings(slug: collectionSlug, request: request)
        else { return }
        if !form.settings.signupOpen {
            closeDateText = "closed"
        } else if let closeDate = form.settings.signupsCloseAt.date {
            closeDateText = "open until \(closeDate.formatted(date: .abbreviated, time: .omitted))"
        } else {
            closeDateText = "open"
        }
    }

    private func loadAssignments() async {
        do {
            let request = try auth.authenticatedRequest(
                for: AO3ChallengeURL.assignments(slug: collectionSlug, list: .defaults)
            )
            assignments = try await AO3Client.shared.allChallengeAssignments(
                slug: collectionSlug, lists: [.assignments, .unfulfilled, .defaults], request: request
            )
            matchError = nil
        } catch {
            assignments = nil
            matchError = error.localizedDescription
        }
    }

    private func loadNextPage() async {
        guard currentPage < totalPages, phase != .loading else { return }
        currentPage += 1
        await loadSignUps(resetPage: false)
    }
}

/// A maintainer's read of one sign-up (1bz row). otwarchive lets any
/// maintainer see another participant's sign-up, and its sign-ups index
/// already renders every request and offer inline, so this shows the row's
/// parsed prompts rather than fetching and parsing /signups/<id> again.
private struct ChallengeSignUpDetailView: View {
    let signUp: AO3ChallengeSignUp
    let collectionTitle: String
    let palette: SubjectPalette

    private var gutter: CGFloat { SubjectMetrics.accountGutter }

    var body: some View {
        List {
            Section {
                SubjectHeaderBlock(
                    kicker: collectionTitle,
                    title: signUp.pseud,
                    subtitle: AO3ChallengeCountText.plural(signUp.requests.count, "request")
                        + " · " + AO3ChallengeCountText.plural(signUp.offers.count, "offer"),
                    palette: palette,
                    gutter: gutter
                )
                .pageBodyRow(top: 20, gutter: 0)
            }
            promptSections(signUp.requests, noun: "Request")
            promptSections(signUp.offers, noun: "Offer")
        }
        .cardList()
        #if os(macOS)
        .navigationTitle(signUp.pseud)
        #endif
        .subjectScreenWash(palette: palette)
    }

    private func promptSections(_ prompts: [AO3ChallengePrompt], noun: String) -> some View {
        ForEach(Array(prompts.enumerated()), id: \.offset) { index, prompt in
            Section {
                SectionRuleHeader(title: "\(noun) \(index + 1)")
                    .pageBodyRow(top: 18, gutter: 0)
                // "Any <type>" choices are not parsed, so a prompt with nothing
                // else shows no panel rather than claiming it chose nothing.
                let tags = tagRows(prompt)
                if !tags.isEmpty || !prompt.promptText.isEmpty {
                    promptPanel(tags: tags, text: prompt.promptText).pageBodyRow(top: 8, gutter: gutter)
                }
            }
        }
    }

    private func tagRows(_ prompt: AO3ChallengePrompt) -> [(title: String, tags: [String])] {
        [
            ("Fandoms", prompt.fandoms), ("Relationships", prompt.relationships),
            ("Characters", prompt.characters), ("Additional tags", prompt.freeforms)
        ].filter { !$0.tags.isEmpty }
    }

    /// Two-line rows, as in 1by's Type panel: a tag list does not fit a value column.
    private func promptPanel(tags: [(title: String, tags: [String])], text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(tags.enumerated()), id: \.offset) { index, row in
                if index > 0 { SubjectRowSeparator() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    Text(row.tags.joined(separator: ", "))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
            if !text.isEmpty {
                if !tags.isEmpty { SubjectRowSeparator() }
                Text(text)
                    .font(.system(size: 13.5, design: .serif))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }
        .subjectPanel()
    }
}
