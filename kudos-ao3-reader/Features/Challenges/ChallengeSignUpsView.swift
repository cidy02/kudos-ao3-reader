import SwiftUI

/// Artboard **1bz** — Challenge sign-ups.
///
/// Moderator view of participants who signed up for the challenge, showing matched
/// state joined client-side with assignment records. Provides All / Matched /
/// Unmatched segmented filtering, a single-line request tag summary per row, and
/// shortcuts to view or create your own sign-up.
struct ChallengeSignUpsView: View { // swiftlint:disable:this type_body_length
    let collectionSlug: String
    var collectionTitle: String = ""
    /// Kind already read from the collection page. Nil keeps the gift-then-meme probe.
    var challengeKind: AO3ChallengeKind?

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .body) private var rowTitleSize: CGFloat = 17
    @ScaledMetric(relativeTo: .subheadline) private var buttonLabelSize: CGFloat = 14
    @ScaledMetric(relativeTo: .subheadline) private var loadingSize: CGFloat = 14
    @ScaledMetric(relativeTo: .footnote) private var bodySize: CGFloat = 13
    @ScaledMetric(relativeTo: .footnote) private var loadMoreSize: CGFloat = 13
    @ScaledMetric(relativeTo: .footnote) private var failureBodySize: CGFloat = 13
    @ScaledMetric(relativeTo: .footnote) private var subSize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 12

    @State private var pages = AO3LoadMorePages<AO3ChallengeSignUp>()
    @State private var filterSelection: SignUpFilter = .all
    @State private var phase: Phase = .idle
    @State private var closeDateText: String = ""
    @State private var rawCloseDateText: String?
    @State private var worksDueDateText: String?
    @State private var closeDateInstant: Date?
    @State private var signUpsAreOpen: Bool = false
    /// Every assignment the rows are joined to, read once per refresh. `nil`
    /// means the fetch failed, so match state is unknown rather than unmatched.
    @State private var assignments: [AO3ChallengeAssignment]?
    @State private var matchError: String?
    /// The challenge's total, not the pages fetched; `nil` until known.
    @State private var signUpTotal: Int?
    #if DEBUG
    @State private var debugSignUp: AO3ChallengeSignUp?
    #endif

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

    private var palette: SubjectPalette {
        theme.appTheme.subjectPalette(
            hue: CoverArt.workHue(fandoms: [], title: collectionTitle.isEmpty ? collectionSlug : collectionTitle)
        )
    }

    private var effectiveTitle: String {
        collectionTitle.isEmpty ? collectionSlug : collectionTitle
    }

    private var signUps: [AO3ChallengeSignUp] { pages.rows }

    private func matchState(_ signUp: AO3ChallengeSignUp) -> AO3ChallengeSignUpMatching.State {
        AO3ChallengeSignUpMatching.state(of: signUp, assignments: assignments)
    }

    /// Why no chip shows, when none can.
    private var matchNote: String? {
        if let matchError {
            return "Kudos can't tell which sign-ups are matched. AO3 shows assignments to maintainers "
                + "after sign-ups close. "
                + matchError
        }
        return assignments?.isEmpty == true
            ? "No assignments have been sent yet, so no sign-up is matched or unmatched."
            : nil
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
        List {
            Section {
                contextCard.pageBodyRow(top: 12, gutter: gutter)
                if !statCells.isEmpty {
                    ChallengeBoardStatStrip(cells: statCells, surface: .list)
                        .pageBodyRow(top: 14, gutter: gutter)
                }
                filterChipRail.pageBodyRow(top: 14, gutter: 0)
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
        }
        .cardList()
        // Rows at their own padding, not the List minimum (L3-FORM-1).
        .environment(\.defaultMinListRowHeight, 0)
        .subjectScreenWash(title: ChallengesBoardCopy.signUpsTitle, palette: palette, role: .content)
        .safeAreaBar(edge: .bottom, spacing: 0) { bottomActionBar }
        .task { await loadSignUpsIfNeeded() }
        #if DEBUG
        .task {
            guard DebugLaunchRoute.wantsPush("chsignupdetail") else { return }
            for _ in 0..<40 {
                if let first = pages.rows.first {
                    if DebugLaunchRoute.takePush("chsignupdetail") { debugSignUp = first }
                    return
                }
                if case .failed = phase { return }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        .navigationDestination(item: $debugSignUp) { signUp in
            ChallengeSignUpDetailView(signUp: signUp, collectionTitle: effectiveTitle, palette: palette)
        }
        #endif
        .refreshable { await loadSignUps(resetPage: true) }
            .screenTint(palette)
    }

    // MARK: - Header & Filter (`Challenge-SignUps.dc.html`)

    private var contextCard: some View {
        let scheduleMeta = ChallengesBoardCopy.challengeSettingsContextMeta(
            closeDateText: rawCloseDateText,
            worksDueDateText: worksDueDateText
        )
        let meta = scheduleMeta.isEmpty ? (closeDateText.isEmpty ? nil : closeDateText) : scheduleMeta
        return ChallengeBoardContextCard(
            systemImage: "gift",
            kicker: ChallengesBoardCopy.challengeSettingsKicker(
                kind: challengeKind ?? .giftExchange,
                isModerated: nil
            ),
            title: effectiveTitle,
            meta: meta,
            palette: palette,
            surface: .list
        )
    }

    private var statCells: [ChallengeBoardStatStrip.Cell] {
        var cells: [ChallengeBoardStatStrip.Cell] = []
        if let total = signUpTotal {
            cells.append(ChallengeBoardStatStrip.Cell(value: total.formatted(), label: "Sign-ups"))
        } else if phase == .loaded, !pages.hasMore {
            cells.append(ChallengeBoardStatStrip.Cell(value: signUps.count.formatted(), label: "Sign-ups"))
        }
        if let assignments, !assignments.isEmpty, !pages.hasMore {
            let matchedCount = signUps.filter { matchState($0) == .matched }.count
            let unmatchedCount = signUps.filter { matchState($0) == .unmatched }.count
            cells.append(ChallengeBoardStatStrip.Cell(value: matchedCount.formatted(), label: "Matched"))
            cells.append(
                ChallengeBoardStatStrip.Cell(
                    value: unmatchedCount.formatted(),
                    label: "Unmatched",
                    tint: unmatchedCount > 0 ? ChallengeBoardColors.warningInk(for: theme.appTheme) : nil
                )
            )
        }
        if signUpsAreOpen, let closeDateInstant {
            cells.append(
                ChallengeBoardStatStrip.Cell(
                    value: ChallengesBoardCopy.daysUntilText(target: closeDateInstant),
                    label: "Left"
                )
            )
        }
        return cells
    }

    private func chipLabel(for option: SignUpFilter) -> String {
        guard option != .all, !pages.hasMore, let assignments, !assignments.isEmpty else {
            return option.rawValue
        }
        let count = signUps.filter {
            option == .matched ? matchState($0) == .matched : matchState($0) == .unmatched
        }.count
        return count > 0 ? "\(option.rawValue) \(count)" : option.rawValue
    }

    private var filterChipRail: some View {
        AccessibilityChipRail(horizontalPadding: gutter) {
            ForEach(SignUpFilter.allCases, id: \.self) { option in
                let selected = filterSelection == option
                let label = chipLabel(for: option)
                Button {
                    filterSelection = option
                } label: {
                    ChallengeBoardChipLabel(text: label, isSelected: selected)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    // MARK: - Content Sections

    @ViewBuilder
    private var contentSections: some View {
        Section {
            // A failed page (refresh or Load more) is reported above the rows
            // already loaded, which stay.
            if case let .failed(message) = phase {
                note("Couldn't load sign-ups: \(message)").padding(.bottom, 8).pageBodyRow(top: 10, gutter: gutter)
            }

            if let matchNote {
                note(matchNote).padding(.bottom, 8).pageBodyRow(top: 10, gutter: gutter)
            }

            if filteredSignUps.isEmpty {
                emptyFilteredCard.pageBodyRow(top: 10, gutter: gutter)
            } else {
                signUpRows
            }

            footnoteText.pageBodyRow(top: 8, gutter: gutter)
        }

        if pages.hasMore {
            Section {
                loadMoreRow.pageBodyRow(top: 10, gutter: gutter)
            }
        }
    }

    /// One `List` row per sign-up: a row is one tap target, so a card holding
    /// every sign-up in a single row would push them all at once.
    private var signUpRows: some View {
        ForEach(Array(filteredSignUps.enumerated()), id: \.element.id) { index, signUp in
            VStack(spacing: 0) {
                if index > 0 { SubjectRowSeparator(inset: 48) }
                signUpRow(signUp)
            }
            .subjectRowNavigation(accessibilityLabel: signUp.pseud) {
                ChallengeSignUpDetailView(signUp: signUp, collectionTitle: effectiveTitle, palette: palette)
            }
            .pageBodyRow(top: 0, gutter: gutter)
        }
    }

    private func signUpRow(_ signUp: AO3ChallengeSignUp) -> some View {
        let requestChips = ChallengesBoardCopy.signUpRequestChips(for: signUp, limit: 3)
        let offerMeta = ChallengesBoardCopy.signUpOfferMeta(
            offers: signUp.offers,
            takesOffers: challengeKind != .promptMeme
        )
        let avatarColor = theme.appTheme.subjectPalette(hue: CoverArt.hue(for: signUp.pseud)).accent
        let state = matchState(signUp)

        return HStack(alignment: .top, spacing: 12) {
            ChallengeBoardAvatar(
                text: ChallengesBoardCopy.personInitial(for: signUp.pseud),
                color: avatarColor,
                shapeKind: .circle(size: 36)
            )
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(signUp.pseud)
                    .font(.system(size: rowTitleSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if !requestChips.isEmpty {
                    Text("Requests")
                        .font(.system(size: subSize))
                        .foregroundStyle(.secondaryInk)

                    FlowLayout(spacing: 4, rowSpacing: 4) {
                        ForEach(requestChips) { chip in
                            ChallengeBoardTagPill(text: chip.label, isTinted: chip.isTinted)
                        }
                    }
                    .padding(.top, 1)
                }

                if let offerMeta {
                    Text(offerMeta.text)
                        .font(.system(size: captionSize, weight: offerMeta.isWarning ? .semibold : .regular))
                        .foregroundStyle(
                            offerMeta.isWarning
                                ? AnyShapeStyle(ChallengeBoardColors.warningInk(for: theme.appTheme))
                                : AnyShapeStyle(.secondaryInk)
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 1)
                }

                if dynamicTypeSize.isAccessibilitySize, state != .unknown {
                    matchedStatusBadge(state)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !dynamicTypeSize.isAccessibilitySize, state != .unknown {
                matchedStatusBadge(state)
                    .padding(.top, 3)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// No chip at all when the state is unknown: a guess would be a false claim.
    @ViewBuilder
    private func matchedStatusBadge(_ state: AO3ChallengeSignUpMatching.State) -> some View {
        switch state {
        case .matched:
            let info = ChallengeBoardColors.infoBadge(for: theme.appTheme)
            ChallengeBoardBadge(
                text: "Matched",
                style: .tinted(foreground: info.foreground, background: info.background)
            )
        case .unmatched:
            let warn = ChallengeBoardColors.warningBadge(for: theme.appTheme)
            ChallengeBoardBadge(
                text: "Unmatched",
                style: .tinted(foreground: warn.foreground, background: warn.background)
            )
        case .unknown:
            EmptyView()
        }
    }

    private func note(_ text: String) -> some View {
        Label {
            Text(text)
                .font(.system(size: captionSize))
        } icon: {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11.5))
        }
            .foregroundStyle(Color.secondary.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private var emptyFilteredCard: some View {
        let unknown = matchNote != nil && filterSelection != .all
        return VStack(spacing: 6) {
            Text(
                ChallengesBoardCopy.signUpsEmptyTitle(
                    filterName: filterSelection.rawValue,
                    isAllFilter: filterSelection == .all,
                    matchUnavailable: unknown
                )
            )
            .font(.system(size: rowTitleSize, weight: .semibold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)

            Text(
                ChallengesBoardCopy.signUpsEmptyBody(
                    filterName: filterSelection.rawValue,
                    isAllFilter: filterSelection == .all,
                    matchUnavailable: unknown
                )
            )
            .font(.system(size: bodySize))
            .foregroundStyle(.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .subjectPanel()
    }

    private var footnoteText: some View {
        Text("AO3 shows 20 sign-ups per page, so these filters apply only to the pages you have loaded. "
            + "Each tag summary shows one line from that person's sign-up requests.")
            .font(.system(size: captionSize))
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
                        .accentFill()
                }
                Text("Load page \(pages.loadedPages + 1) of \(pages.totalPages)")
                    .font(.system(size: loadMoreSize, weight: .medium))
                    .foregroundStyle(theme.accentInk)
                    .fixedSize(horizontal: false, vertical: true)
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
                    .font(.system(size: buttonLabelSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(
                        SubjectMetrics.controlShape(dynamicTypeSize)
                            .fill(theme.appTheme.glassFill(0.10))
                            .overlay(
                                SubjectMetrics.controlShape(dynamicTypeSize)
                                    .strokeBorder(theme.appTheme.glassStroke(0.16), lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(.plain)

            NavigationLink {
                ChallengeSignUpView(collectionSlug: collectionSlug, collectionTitle: effectiveTitle)
            } label: {
                Text("Create sign-up")
                    .font(.system(size: buttonLabelSize, weight: .semibold))
                    .foregroundStyle(theme.onEffectiveTint)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(
                        SubjectMetrics.controlShape(dynamicTypeSize)
                            .fill(theme.effectiveTint)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - State Cards

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .accentFill()
            Text("Loading sign-ups…")
                .font(.system(size: loadingSize))
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }

    private func failureCard(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Couldn't load sign-ups")
                .font(.system(size: rowTitleSize, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.system(size: failureBodySize))
                .foregroundStyle(.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again") {
                Task { await loadSignUps(resetPage: true) }
            }
            .buttonStyle(.kudosSecondary)
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

    /// A refresh starts a fresh pager and Load more continues this one; either
    /// way `pages` only changes once the page arrives, so a failure keeps the
    /// rows on screen and Load more still offers the same page.
    private func loadSignUps(resetPage: Bool) async {
        phase = .loading

        if resetPage {
            await loadSchedule()
            await loadAssignments()
        }

        var next = resetPage ? AO3LoadMorePages<AO3ChallengeSignUp>() : pages
        do {
            try await next.loadNext { number in
                let request = try auth.authenticatedRequest(
                    for: AO3ChallengeURL.signUps(slug: collectionSlug, page: number)
                )
                let page = try await AO3Client.shared.challengeSignUps(
                    slug: collectionSlug, page: number, request: request
                )
                if number == 1 {
                    // No total rather than page 1's count passed off as one.
                    signUpTotal = try? await AO3Client.shared.challengeSignUpTotal(
                        slug: collectionSlug, firstPage: page, request: request
                    )
                }
                let rows = assignments.map {
                    AO3ChallengeSignUpMatching.joining(page.signUps, assignments: $0)
                } ?? page.signUps
                return (rows, page.totalPages)
            }
            pages = next
            phase = .loaded
        } catch {
            phase = .failed(UserFacingError.message(for: error))
        }
    }

    /// Owner-only edit form, so a moderator just gets no date. AO3's own form
    /// says its dates do nothing and sign-ups open and close by hand, so the
    /// switch decides "open", not the close date.
    private func loadSchedule() async {
        guard let request = try? auth.authenticatedRequest(
            for: AO3ChallengeURL.giftExchangeEdit(slug: collectionSlug)
        ), let form = try? await AO3Client.shared.challengeSettings(
            slug: collectionSlug, request: request, kind: challengeKind
        )
        else { return }
        signUpsAreOpen = form.settings.signupOpen
        rawCloseDateText = form.settings.signupsCloseAt.dateText
        worksDueDateText = form.settings.worksDueAt.dateText
        closeDateInstant = form.settings.signupsCloseAt.instant
        if !form.settings.signupOpen {
            closeDateText = "Sign-ups closed"
        } else if let closeDate = form.settings.signupsCloseAt.dateText {
            closeDateText = "Sign-ups open until \(closeDate)"
        } else {
            closeDateText = "Sign-ups open"
        }
    }

    private func loadAssignments() async {
        do {
            let request = try auth.authenticatedRequest(
                for: AO3ChallengeURL.assignments(slug: collectionSlug, list: .defaults)
            )
            assignments = try await AO3Client.shared.allChallengeAssignments(
                slug: collectionSlug, lists: AO3ChallengeAssignmentList.sent + [.defaults], request: request
            )
            matchError = nil
        } catch {
            assignments = nil
            matchError = UserFacingError.message(for: error)
        }
    }

    private func loadNextPage() async {
        guard pages.hasMore, phase != .loading else { return }
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

    @ScaledMetric(relativeTo: .body) private var rowTitleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .subheadline) private var promptSize: CGFloat = 13.5
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 11.5

    private var gutter: CGFloat { SubjectMetrics.accountGutter }

    var body: some View {
        List {
            Section {
                SubjectPageFact(
                    [
                        collectionTitle,
                        AO3ChallengeCountText.plural(signUp.requests.count, "request"),
                        AO3ChallengeCountText.plural(signUp.offers.count, "offer")
                    ].filter { !$0.isEmpty }.joined(separator: " · "),
                    gutter: gutter
                )
                .pageBodyRow(top: 12, gutter: 0)
            }
            promptSections(signUp.requests, noun: "Request")
            promptSections(signUp.offers, noun: "Offer")
        }
        .cardList()
        // Rows at their own padding, not the List minimum (L3-FORM-1).
        .environment(\.defaultMinListRowHeight, 0)
        .subjectScreenWash(title: signUp.pseud, palette: palette)
            .screenTint(palette)
    }

    private func promptSections(_ prompts: [AO3ChallengePrompt], noun: String) -> some View {
        ForEach(Array(prompts.enumerated()), id: \.offset) { index, prompt in
            Section {
                SectionRuleHeader(title: "\(noun) \(index + 1)")
                    .pageBodyRow(top: 18, gutter: 0)
                let tags = tagRows(prompt)
                if !tags.isEmpty || !prompt.promptText.isEmpty {
                    promptPanel(tags: tags, text: prompt.promptText).pageBodyRow(top: 8, gutter: gutter)
                }
            }
        }
    }

    /// AO3's "Any <type>" choice reads as "Any" in that type's row.
    private func tagRows(_ prompt: AO3ChallengePrompt) -> [(title: String, tags: [String])] {
        func with(_ tags: [String], any: Bool) -> [String] { tags + (any ? ["Any"] : []) }
        return [
            ("Fandoms", with(prompt.fandoms, any: prompt.anyFandom)),
            ("Relationships", with(prompt.relationships, any: prompt.anyRelationship)),
            ("Characters", with(prompt.characters, any: prompt.anyCharacter)),
            ("Additional tags", with(prompt.freeforms, any: prompt.anyFreeform)),
            ("Optional tags", prompt.optionalTags)
        ].filter { !$0.tags.isEmpty }
    }

    /// Two-line rows, as in 1by's Type panel: a tag list does not fit a value column.
    private func promptPanel(tags: [(title: String, tags: [String])], text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(tags.enumerated()), id: \.offset) { index, row in
                if index > 0 { SubjectRowSeparator() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.system(size: rowTitleSize))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(row.tags.joined(separator: ", "))
                        .font(.system(size: captionSize))
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
            if !text.isEmpty {
                if !tags.isEmpty { SubjectRowSeparator() }
                Text(text)
                    .font(.system(size: promptSize, design: .serif))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
            }
        }
        .subjectPanel()
    }
}
