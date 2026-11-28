import SwiftUI

/// Artboard **1cd** — Collection moderation, in full.
///
/// Everything AO3 gives a maintainer in one scroll: the review queue, membership
/// requests, a headcount of the maintainer roster, and the collection's
/// reveal/anonymity state. Deliberately does NOT repeat the full maintainer
/// roster or invite flow — artboard 1bx (`CollectionMaintainersView`) already
/// owns those, and this screen shows a one-line summary with a link across to
/// it rather than re-drawing an invite text field of its own.
///
/// Every action drawn here — approve, reject, accept, decline, invite, reveal,
/// un-anonymize — has a real write behind it in `AO3CollectionActions.swift`,
/// so nothing on this screen falls back to Open on AO3.
struct CollectionModerationView: View {
    let collectionSlug: String
    var collectionTitle: String = ""
    var viewerIsOwner: Bool

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .body) private var reviewTitleSize: CGFloat = 17
    @ScaledMetric(relativeTo: .body) private var rowTitleSize: CGFloat = 16
    @ScaledMetric(relativeTo: .headline) private var stateTitleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .subheadline) private var loadingSize: CGFloat = 14
    @ScaledMetric(relativeTo: .footnote) private var bodySize: CGFloat = 13
    @ScaledMetric(relativeTo: .footnote) private var failureBodySize: CGFloat = 13
    @ScaledMetric(relativeTo: .footnote) private var subSize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var kickerSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 12
    @ScaledMetric(relativeTo: .body) private var actionLabelSize: CGFloat = 15

    @State private var awaitingReview: [AO3CollectionItem] = []
    /// The review queue is AO3's paged Awaiting list; only this page is held.
    @State private var reviewPage = 1
    @State private var reviewTotalPages = 1
    @State private var isLoadingReviewPage = false
    @State private var membershipRequests: [AO3CollectionParticipant] = []
    @State private var maintainers: [AO3CollectionParticipant] = []
    @State private var revealScheduleText: String = ""
    @State private var phase: Phase = .idle
    @State private var itemInFlight: Int?
    @State private var participantInFlight: Int?
    @State private var actionErrorMessage: String?
    @State private var itemToReject: AO3CollectionItem?
    /// 1cd's Message creator: the work's comment composer, "for a fix rather
    /// than a refusal". It used to open the work in the browser instead.
    @State private var commentsRoute: AO3CommentsRoute?
    @State private var itemsDestinationTab: AO3CollectionItemTab?
    @State private var participantToDecline: AO3CollectionParticipant?
    @State private var confirmReveal = false
    @State private var confirmUnanon = false
    @State private var isRevealing = false
    @State private var isUnanonymizing = false
    @State private var revealErrorMessage: String?
    @State private var loadedGeneration: Int?
    @State private var loadGeneration = 0

    private enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private var gutter: CGFloat { SubjectMetrics.accountGutter }

    private var palette: SubjectPalette {
        theme.appTheme.subjectPalette(hue: CoverArt.workHue(fandoms: [], title: effectiveTitle))
    }

    private var effectiveTitle: String { collectionTitle.isEmpty ? collectionSlug : collectionTitle }

    /// The only two flags `revealScheduleText` actually carries (see
    /// `AO3Client.revealScheduleText(from:)`) — a comma-joined "Unrevealed"
    /// and/or "Anonymous", never a date. Derived here rather than kept as
    /// separate stored bools, since the text itself is the only backing state.
    private var isUnrevealed: Bool { revealScheduleText.localizedCaseInsensitiveContains("unrevealed") }
    private var isAnonymous: Bool { revealScheduleText.localizedCaseInsensitiveContains("anonymous") }

    var body: some View {
        List {
            Section {
                contextCard.pageBodyRow(top: 12, gutter: gutter)
                if phase == .loaded {
                    ChallengeBoardStatStrip(cells: statCells, surface: .list)
                        .pageBodyRow(top: 14, gutter: gutter)
                }
                statusChipRail.pageBodyRow(top: 14, gutter: 0)
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
        .subjectScreenWash(title: "Moderation", palette: palette, role: .content)
        .navigationDestination(item: $commentsRoute) { route in
            CommentsView(
                workID: route.workID,
                context: route.context,
                initialFocusesChapter: false,
                initialComposes: route.composes
            )
        }
        .navigationDestination(item: $itemsDestinationTab) { tab in
            AO3CollectionItemsView(slug: collectionSlug, title: effectiveTitle, initialTab: tab)
        }
        .task(id: auth.sessionGeneration) { await load() }
        .refreshable { await load() }
        // AO3 has no reason field and sends no mail on rejection (Q6), so this
        // is a plain confirmation rather than a reason sheet.
        .alert(
            "Reject this work?",
            isPresented: Binding(get: { itemToReject != nil }, set: { if !$0 { itemToReject = nil } }),
            presenting: itemToReject
        ) { item in
            Button("Reject", role: .destructive) {
                Task { await rejectItem(item) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text("This rejects “\(item.workTitle)” from the collection. The work stays on AO3, and its "
                + "creator receives no reason or email.")
        }
        .alert(
            participantToDecline.map { CollectionModerationCopy.declineTitle(participant: $0.pseud) } ?? "",
            isPresented: Binding(
                get: { participantToDecline != nil },
                set: { if !$0 { participantToDecline = nil } }
            ),
            presenting: participantToDecline
        ) { participant in
            Button("Decline", role: .destructive) {
                Task { await declineRequest(participant) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { participant in
            Text("This removes \(participant.pseud)'s membership request. They will need to apply again.")
        }
        .alert("Reveal this collection?", isPresented: $confirmReveal) {
            Button("Reveal", role: .destructive) {
                Task { await performReveal() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Unrevealed works and their creators become visible to everyone. "
                + "You can't undo this in Kudos.")
        }
        .alert("Remove anonymity?", isPresented: $confirmUnanon) {
            Button("Remove Anonymity", role: .destructive) {
                Task { await performUnanon() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Creators become visible to everyone instead of only maintainers. "
                + "You can't undo this in Kudos.")
        }
            .screenTint(palette)
    }

    // MARK: - Header (`AO3-Collection-Moderation.dc.html`)

    private var contextCard: some View {
        ChallengeBoardContextCard(
            systemImage: "archivebox",
            kicker: ChallengesBoardCopy.moderationKicker,
            title: effectiveTitle,
            meta: ChallengesBoardCopy.moderationContextMeta(
                viewerIsOwner: viewerIsOwner,
                isUnrevealed: isUnrevealed,
                isAnonymous: isAnonymous
            ),
            palette: palette,
            surface: .list
        )
    }

    private var statCells: [ChallengeBoardStatStrip.Cell] {
        let waitingValue = reviewTotalPages > 1
            ? "\(awaitingReview.count.formatted())+"
            : awaitingReview.count.formatted()
        return [
            ChallengeBoardStatStrip.Cell(
                value: waitingValue,
                label: "Waiting",
                tint: awaitingReview.isEmpty ? nil : ChallengeBoardColors.warningInk(for: theme.appTheme)
            ),
            ChallengeBoardStatStrip.Cell(value: membershipRequests.count.formatted(), label: "Requests"),
            ChallengeBoardStatStrip.Cell(value: maintainers.count.formatted(), label: "Maintainers")
        ]
    }

    /// Board filter chips: Waiting (current queue) + Approved / Rejected (pushes
    /// `AO3CollectionItemsView` on that tab per `REDESIGN_DECISIONS.md` 1cd without
    /// inventing totals AO3 did not send).
    private var statusChipRail: some View {
        let waitingLabel = ChallengesBoardCopy.moderationWaitingChipLabel(
            count: awaitingReview.count,
            totalPages: reviewTotalPages
        )
        return AccessibilityChipRail(horizontalPadding: gutter) {
            ChallengeBoardChipLabel(text: waitingLabel, isSelected: true)
                .accessibilityAddTraits(.isSelected)

            Button {
                itemsDestinationTab = .approved
            } label: {
                ChallengeBoardChipLabel(text: "Approved", isSelected: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Approved")

            Button {
                itemsDestinationTab = .rejected
            } label: {
                ChallengeBoardChipLabel(text: "Rejected", isSelected: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rejected")
        }
    }

    // MARK: - Content Sections

    @ViewBuilder
    private var contentSections: some View {
        if let actionErrorMessage {
            Section {
                actionErrorCard(actionErrorMessage)
                    .pageBodyRow(top: 8, gutter: gutter)
            }
        }

        Section {
            if awaitingReview.isEmpty {
                emptyReviewCard.pageBodyRow(top: 10, gutter: gutter)
            } else {
                ForEach(Array(awaitingReview.enumerated()), id: \.element.id) { index, item in
                    VStack(spacing: 0) {
                        if index > 0 { SubjectRowSeparator(inset: dynamicTypeSize.isAccessibilitySize ? 0 : 46) }
                        awaitingReviewCard(item)
                    }
                    .pageBodyRow(top: 0, gutter: gutter)
                }
            }
            if reviewTotalPages > 1 {
                SearchPaginationBar(
                    currentPage: reviewPage,
                    totalPages: reviewTotalPages,
                    isLoading: isLoadingReviewPage,
                    palette: palette
                ) { page in
                    Task { await loadReviewPage(page) }
                }
                .pageBodyRow(top: 6, gutter: gutter)
            }
            reviewFootnote.pageBodyRow(top: 8, gutter: gutter)
        }

        Section {
            ChallengeBoardListSectionHeader(title: "Membership requests", count: membershipRequests.count)
                .pageBodyRow(top: 18, gutter: gutter)

            if membershipRequests.isEmpty {
                emptyRequestsCard.pageBodyRow(top: 8, gutter: gutter)
            } else {
                membershipRequestsList.pageBodyRow(top: 8, gutter: gutter)
            }
        }

        Section {
            ChallengeBoardListSectionHeader(title: "Maintainers")
                .padding(.bottom, 6)
                .pageBodyRow(top: 18, gutter: gutter)
        }
        Section {
            maintainersRows
            maintainersFootnote.pageBodyRow(top: 8, gutter: gutter)
        }

        Section {
            ChallengeBoardListSectionHeader(title: "Reveal and anonymity")
                .pageBodyRow(top: 18, gutter: gutter)
            revealInfoPanel.pageBodyRow(top: 8, gutter: gutter)
            if isUnrevealed || isAnonymous,
               AO3CollectionOwnerControls.areVisible(viewerIsOwner: viewerIsOwner) {
                revealActionsPanel.pageBodyRow(top: 8, gutter: gutter)
            }
            if let revealErrorMessage {
                errorNotice(revealErrorMessage).pageBodyRow(top: 8, gutter: gutter)
            }
            footnote("Reveal and Remove anonymity are separate actions. You confirm each one, "
                + "and neither can be undone in Kudos.")
                .pageBodyRow(top: 8, gutter: gutter)
        }
    }

    private var reviewFootnote: some View {
        footnote("AO3 doesn't send the creator a reason or email when you reject a work. "
            + "The work stays on AO3 and only leaves this collection.")
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: captionSize))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    // MARK: - Awaiting Review (`AO3-Collection-Moderation.dc.html`)

    /// Leading cover swatch, kicker, title, creator/submission line, and inline
    /// Approve / Reject / Message creator pills. `AO3CollectionItem` carries no
    /// word count, rating, or tag summary, so none is invented.
    private func awaitingReviewCard(_ item: AO3CollectionItem) -> some View {
        let isBookmark = item.itemType.localizedCaseInsensitiveContains("bookmark")
        return HStack(alignment: .top, spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                ChallengeBoardCoverTile(seed: item.workTitle)
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.itemType.uppercased())
                    .font(.system(size: kickerSize, weight: .semibold))
                    .lineLimit(1)
                    .tracking(0.6)
                    .foregroundStyle(isBookmark ? AnyShapeStyle(.secondaryInk) : AnyShapeStyle(palette.accent))

                Text(item.workTitle)
                    .font(.system(size: reviewTitleSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(CollectionModerationCopy.byline(creator: item.creatorByline, dateText: item.itemDateText))
                    .font(.system(size: subSize))
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                FlowLayout(spacing: 8, rowSpacing: 8) {
                    approveButton(for: item)
                    rejectButton(for: item)
                    messageCreatorButton(for: item)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }

    private func approveButton(for item: AO3CollectionItem) -> some View {
        ChallengeBoardInlineActionButton(
            title: "Approve",
            role: .primary,
            isBusy: itemInFlight == item.id,
            isDisabled: itemInFlight != nil
        ) {
            Task { await approveItem(item) }
        }
    }

    private func rejectButton(for item: AO3CollectionItem) -> some View {
        ChallengeBoardInlineActionButton(
            title: "Reject",
            role: .destructive,
            isDisabled: itemInFlight != nil
        ) {
            itemToReject = item
        }
    }

    /// Opens the work itself, since AO3's own moderator queue offers no separate
    /// messaging endpoint — a comment on the work is the fix-it channel.
    private func messageCreatorButton(for item: AO3CollectionItem) -> some View {
        ChallengeBoardInlineActionButton(
            title: "Message creator",
            role: .secondary
        ) {
            if let workID = item.workID ?? item.workURL.flatMap({ WorkTags.ao3WorkID(from: $0.absoluteString) }) {
                commentsRoute = AO3CommentsRoute(
                    workID: workID,
                    context: AO3CommentsWorkContext(title: item.workTitle, authors: []),
                    composes: true
                )
            }
        }
    }

    private var emptyReviewCard: some View {
        VStack(spacing: 6) {
            Text(ChallengesBoardCopy.moderationEmptyReviewTitle)
                .font(.system(size: stateTitleSize, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(ChallengesBoardCopy.moderationEmptyReviewBody)
                .font(.system(size: bodySize))
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .subjectPanel()
    }

    // MARK: - Membership Requests

    private var membershipRequestsList: some View {
        VStack(spacing: 0) {
            ForEach(
                Array(membershipRequests.enumerated()), id: \.element.id
            ) { index, participant in
                if index > 0 { SubjectRowSeparator() }
                membershipRequestRow(participant)
            }
        }
        .subjectPanel()
    }

    /// `AO3CollectionParticipant` carries no request date or per-user work
    /// count (that figure lives on the unrelated `AO3CollectionPerson`, from
    /// the separate `/people` listing) — so the secondary line states the
    /// request itself rather than inventing either figure.
    private func membershipRequestRow(_ participant: AO3CollectionParticipant) -> some View {
        // Beside the two buttons, which do not shrink, the name had a column one letter wide
        // at the accessibility sizes ("p / a / r / …"): there the buttons go under it.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        return layout {
            VStack(alignment: .leading, spacing: 4) {
                Text(participant.pseud)
                    .font(.system(size: rowTitleSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Wants to join \(effectiveTitle)")
                    .font(.system(size: captionSize))
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                acceptButton(for: participant)
                declineButton(for: participant)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func acceptButton(for participant: AO3CollectionParticipant) -> some View {
        ChallengeBoardInlineActionButton(
            title: "Accept",
            role: .primary,
            isBusy: participantInFlight == participant.id,
            isDisabled: participantInFlight != nil
        ) {
            Task { await acceptRequest(participant) }
        }
    }

    private func declineButton(for participant: AO3CollectionParticipant) -> some View {
        ChallengeBoardInlineActionButton(
            title: "Decline",
            role: .secondary,
            isDisabled: participantInFlight != nil
        ) {
            participantToDecline = participant
        }
    }

    private var emptyRequestsCard: some View {
        VStack(spacing: 6) {
            Text("No membership requests")
                .font(.system(size: stateTitleSize, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Nobody is waiting to join \(effectiveTitle).")
                .font(.system(size: bodySize))
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .subjectPanel()
    }

    // MARK: - Maintainers

    /// A headcount, not the roster — the roster and its invite flow live at
    /// artboard 1bx. Both rows push the same destination: one reads as "see
    /// who", the other as "add someone", but neither duplicates the roster
    /// or the invite text field here.
    ///
    /// One `List` row each: as one `VStack` row, a tap fired both links, so
    /// either row pushed the roster twice and Back had to be pressed twice.
    @ViewBuilder
    private var maintainersRows: some View {
        SubjectFormRow(
            label: "Owners and Moderators",
            value: "\(maintainers.count)",
            showsDisclosure: true,
            isMonospaced: true
        )
        .subjectRowNavigation(accessibilityLabel: "Owners and Moderators") {
            CollectionMaintainersView(collectionSlug: collectionSlug, collectionTitle: effectiveTitle)
        }
        .panelSegment(0, of: 2, gutter: gutter)

        SubjectFormRow(label: "Invite a Maintainer", showsDisclosure: true) { EmptyView() }
            .subjectRowNavigation(accessibilityLabel: "Invite a Maintainer") {
                CollectionMaintainersView(collectionSlug: collectionSlug, collectionTitle: effectiveTitle)
            }
            .panelSegment(1, of: 2, gutter: gutter)
    }

    private var maintainersFootnote: some View {
        Text("This shows how many maintainers there are. Manage roles, invitations and the last-owner "
            + "rule under Maintainers.")
            .font(.system(size: captionSize))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    // MARK: - Reveal and Anonymity

    /// `revealScheduleText` is a comma-joined "Unrevealed"/"Anonymous" flag
    /// pair, not a pair of dates (see `AO3Client.revealScheduleText(from:)`),
    /// so these two rows state the current flag rather than a date this data
    /// does not carry.
    private var revealInfoPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(
                label: "Works",
                value: isUnrevealed ? "Unrevealed Until Reveal" : "Revealed"
            )

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Creators",
                value: isAnonymous ? "Anonymous Until Reveal" : "Credited"
            )

            if isAnonymous {
                Text("Creators are hidden from everyone but maintainers.")
                    .font(.system(size: captionSize))
                    .foregroundStyle(.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 11)
            }
        }
        .subjectPanel()
    }

    /// Each row only appears while its flag is actually set — a "Reveal now"
    /// button on an already-revealed collection is dead weight, not a control.
    private var revealActionsPanel: some View {
        VStack(spacing: 0) {
            if isUnrevealed {
                Button {
                    confirmReveal = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "eye")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.red)
                            .frame(width: 20)

                        Text("Reveal now")
                            .font(.system(size: actionLabelSize))
                            .foregroundStyle(Color.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)

                        if isRevealing {
                            ProgressView()
                                .controlSize(.small)
                                .accentFill()
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isRevealing || isUnanonymizing)
            }

            if isUnrevealed && isAnonymous {
                SubjectRowSeparator()
            }

            if isAnonymous {
                Button {
                    confirmUnanon = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.fill.questionmark")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.red)
                            .frame(width: 20)

                        Text("Remove anonymity")
                            .font(.system(size: actionLabelSize))
                            .foregroundStyle(Color.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)

                        if isUnanonymizing {
                            ProgressView()
                                .controlSize(.small)
                                .accentFill()
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isRevealing || isUnanonymizing)
            }
        }
        .subjectPanel()
    }

    private func errorNotice(_ text: String) -> some View {
        Text(text)
            .font(.system(size: captionSize))
            .foregroundStyle(Color.red)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    // MARK: - State Cards

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .accentFill()
            Text("Loading moderation…")
                .font(.system(size: loadingSize))
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }

    private func failureCard(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Couldn't load moderation")
                .font(.system(size: stateTitleSize, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.system(size: failureBodySize))
                .foregroundStyle(.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again") {
                Task { await load() }
            }
            .buttonStyle(.kudosSecondary)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .subjectPanel()
    }

    private func actionErrorCard(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color.red)
            Text(message)
                .font(.system(size: bodySize))
                .foregroundStyle(Color.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                actionErrorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondaryInk)
            }
            .accessibilityLabel("Dismiss error")
            .buttonStyle(.plain)
        }
        .padding(12)
        .subjectPanel()
    }

    // MARK: - Actions

    private func load() async {
        loadGeneration = AO3CollectionSessionReload.nextLoadGeneration(loadGeneration)
        let capturedLoadGeneration = loadGeneration
        let capturedSessionGeneration = auth.sessionGeneration
        clearLoadedState()
        phase = .loading
        actionErrorMessage = nil
        do {
            let request = try auth.authenticatedRequest(for: AO3CollectionURL.participants(slug: collectionSlug))
            let moderation = try await AO3Client.shared.collectionModeration(slug: collectionSlug, request: request)
            guard shouldApply(capturedLoadGeneration, capturedSessionGeneration) else { return }
            awaitingReview = moderation.awaitingReview
            reviewPage = moderation.itemsForm?.currentPage ?? 1
            reviewTotalPages = moderation.itemsForm?.totalPages ?? 1
            membershipRequests = moderation.membershipRequests
            maintainers = moderation.maintainers
            revealScheduleText = moderation.revealScheduleText
            loadedGeneration = capturedSessionGeneration
            phase = .loaded
        } catch {
            guard shouldApply(capturedLoadGeneration, capturedSessionGeneration) else { return }
            phase = .failed(UserFacingError.message(for: error))
        }
    }

    /// Only the review queue's page: participants and the show page are not
    /// refetched for a page change.
    private func loadReviewPage(_ page: Int) async {
        loadGeneration = AO3CollectionSessionReload.nextLoadGeneration(loadGeneration)
        let capturedLoadGeneration = loadGeneration
        let capturedSessionGeneration = auth.sessionGeneration
        isLoadingReviewPage = true
        defer {
            if shouldApply(capturedLoadGeneration, capturedSessionGeneration) {
                isLoadingReviewPage = false
            }
        }
        do {
            let request = try auth.authenticatedRequest(
                for: AO3CollectionURL.items(slug: collectionSlug, tab: .unreviewed, page: page)
            )
            let items = try await AO3Client.shared.collectionItems(
                slug: collectionSlug, tab: .unreviewed, page: page, request: request
            )
            guard shouldApply(capturedLoadGeneration, capturedSessionGeneration) else { return }
            awaitingReview = items.items
            reviewPage = items.currentPage
            reviewTotalPages = items.totalPages
        } catch {
            guard shouldApply(capturedLoadGeneration, capturedSessionGeneration) else { return }
            actionErrorMessage = "Couldn't load that page: \(UserFacingError.message(for: error))"
        }
    }

    /// A decided item leaves the page; an emptied page moves to the nearest
    /// page AO3 still has.
    private func removeDecided(_ item: AO3CollectionItem) async {
        withAnimation {
            awaitingReview.removeAll { $0.id == item.id }
        }
        if awaitingReview.isEmpty, reviewTotalPages > 1 {
            await loadReviewPage(
                CollectionModerationCopy.pageAfterEmptying(page: reviewPage, totalPages: reviewTotalPages)
            )
        }
    }

    private func approveItem(_ item: AO3CollectionItem) async {
        itemInFlight = item.id
        actionErrorMessage = nil
        do {
            try await auth.approveCollectionItem(slug: collectionSlug, itemID: item.id)
            await removeDecided(item)
        } catch {
            actionErrorMessage = "Failed to approve: \(UserFacingError.message(for: error))"
        }
        itemInFlight = nil
    }

    /// On failure the item stays in the queue.
    private func rejectItem(_ item: AO3CollectionItem) async {
        itemInFlight = item.id
        actionErrorMessage = nil
        do {
            try await auth.rejectCollectionItem(slug: collectionSlug, itemID: item.id)
            await removeDecided(item)
        } catch {
            actionErrorMessage = "Failed to reject: \(UserFacingError.message(for: error))"
        }
        itemInFlight = nil
    }

    private func acceptRequest(_ participant: AO3CollectionParticipant) async {
        guard let loadedGeneration else { return }
        participantInFlight = participant.id
        actionErrorMessage = nil
        do {
            try await auth.acceptMember(
                slug: collectionSlug,
                participantID: participant.id,
                expectedGeneration: loadedGeneration
            )
            try auth.requireSessionGeneration(loadedGeneration)
            withAnimation {
                membershipRequests.removeAll { $0.id == participant.id }
            }
        } catch is CancellationError {
            return
        } catch {
            actionErrorMessage = "Failed to accept: \(UserFacingError.message(for: error))"
        }
        participantInFlight = nil
    }

    private func declineRequest(_ participant: AO3CollectionParticipant) async {
        guard let loadedGeneration else { return }
        participantInFlight = participant.id
        actionErrorMessage = nil
        do {
            try await auth.declineMember(
                slug: collectionSlug,
                participantID: participant.id,
                expectedGeneration: loadedGeneration
            )
            try auth.requireSessionGeneration(loadedGeneration)
            withAnimation {
                membershipRequests.removeAll { $0.id == participant.id }
            }
        } catch is CancellationError {
            return
        } catch {
            actionErrorMessage = "Failed to decline: \(UserFacingError.message(for: error))"
        }
        participantInFlight = nil
    }

    private func performReveal() async {
        guard AO3CollectionOwnerControls.areVisible(viewerIsOwner: viewerIsOwner) else { return }
        isRevealing = true
        revealErrorMessage = nil
        do {
            _ = try await auth.revealCollection(slug: collectionSlug)
            await load()
        } catch {
            revealErrorMessage = UserFacingError.message(for: error)
        }
        isRevealing = false
    }

    private func performUnanon() async {
        guard AO3CollectionOwnerControls.areVisible(viewerIsOwner: viewerIsOwner) else { return }
        isUnanonymizing = true
        revealErrorMessage = nil
        do {
            _ = try await auth.unanonCollection(slug: collectionSlug)
            await load()
        } catch {
            revealErrorMessage = UserFacingError.message(for: error)
        }
        isUnanonymizing = false
    }

    private func shouldApply(_ capturedLoad: Int, _ capturedSession: Int) -> Bool {
        AO3CollectionSessionReload.shouldApplyLoad(
            capturedLoadGeneration: capturedLoad,
            loadGeneration: loadGeneration,
            capturedSessionGeneration: capturedSession,
            sessionGeneration: auth.sessionGeneration
        )
    }

    private func clearLoadedState() {
        awaitingReview = []
        reviewPage = 1
        reviewTotalPages = 1
        isLoadingReviewPage = false
        membershipRequests = []
        maintainers = []
        revealScheduleText = ""
        loadedGeneration = nil
        itemInFlight = nil
        participantInFlight = nil
        itemToReject = nil
        participantToDecline = nil
        actionErrorMessage = nil
        revealErrorMessage = nil
    }
}

/// 1cd's wording, kept pure so it can be pinned by tests.
enum CollectionModerationCopy {
    static func declineTitle(participant: String) -> String {
        "Decline \(participant)?"
    }

    /// Page one's rows are not the queue: a paged queue says which page.
    static func reviewTally(count: Int, page: Int, totalPages: Int) -> String {
        let works = count == 1 ? "1 work awaiting review" : "\(count) works awaiting review"
        return totalPages > 1 ? "\(works) on this page · page \(page) of \(totalPages)" : works
    }

    /// The spec's "kestrelmoon · submitted 3 Nov", without a date AO3 did not print.
    static func byline(creator: String, dateText: String) -> String {
        let date = dateText.trimmingCharacters(in: .whitespacesAndNewlines)
        return date.isEmpty ? creator : "\(creator) · submitted \(WorkStat.displayDate(date))"
    }

    /// After the last item on a page is decided: AO3 moves later items up, so
    /// the same page still exists unless it was the last one.
    static func pageAfterEmptying(page: Int, totalPages: Int) -> Int {
        page < totalPages ? page : max(1, page - 1)
    }
}
