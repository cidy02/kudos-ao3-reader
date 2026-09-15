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

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme

    @State private var awaitingReview: [AO3CollectionItem] = []
    @State private var membershipRequests: [AO3CollectionParticipant] = []
    @State private var maintainers: [AO3CollectionParticipant] = []
    @State private var revealScheduleText: String = ""
    @State private var phase: Phase = .idle
    @State private var itemInFlight: Int?
    @State private var participantInFlight: Int?
    @State private var actionErrorMessage: String?
    @State private var selectedItemForReject: AO3CollectionItem?
    @State private var confirmReveal = false
    @State private var confirmUnanon = false
    @State private var isRevealing = false
    @State private var isUnanonymizing = false
    @State private var revealErrorMessage: String?

    private enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private var gutter: CGFloat { SubjectMetrics.accountGutter }
    private var selfGuttered: CGFloat { 0 }

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
                header.pageBodyRow(top: 20, gutter: selfGuttered)
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
        .navigationTitle("Moderation")
        #endif
        .subjectScreenWash(palette: palette)
        .task { await loadIfNeeded() }
        .refreshable { await load() }
        .sheet(item: $selectedItemForReject) { item in
            RejectReasonSheet(
                collectionSlug: collectionSlug,
                item: item,
                palette: palette
            ) {
                withAnimation {
                    awaitingReview.removeAll { $0.id == item.id }
                }
            }
        }
        .alert("Reveal this collection?", isPresented: $confirmReveal) {
            Button("Reveal", role: .destructive) {
                Task { await performReveal() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Unrevealed works and their creators become visible to everyone. "
                + "This can't be undone from the app.")
        }
        .alert("Remove anonymity?", isPresented: $confirmUnanon) {
            Button("Remove Anonymity", role: .destructive) {
                Task { await performUnanon() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Creators become visible to everyone instead of just maintainers. "
                + "This can't be undone from the app.")
        }
    }

    // MARK: - Header

    private var subtitleText: String {
        let workPhrase = awaitingReview.count == 1
            ? "1 work awaiting review" : "\(awaitingReview.count) works awaiting review"
        let requestPhrase = membershipRequests.count == 1
            ? "1 membership request" : "\(membershipRequests.count) membership requests"
        return "\(workPhrase) · \(requestPhrase)"
    }

    private var header: some View {
        SubjectHeaderBlock(
            kicker: effectiveTitle,
            title: "Moderation",
            subtitle: subtitleText,
            palette: palette,
            gutter: SubjectMetrics.accountGutter
        )
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
            SectionRuleHeader(title: "Awaiting review", count: awaitingReview.count)
                .pageBodyRow(top: 18, gutter: selfGuttered)

            if awaitingReview.isEmpty {
                emptyReviewCard.pageBodyRow(top: 8, gutter: gutter)
            } else {
                awaitingReviewList.pageBodyRow(top: 8, gutter: gutter)
            }
        }

        Section {
            SectionRuleHeader(title: "Membership requests", count: membershipRequests.count)
                .pageBodyRow(top: 18, gutter: selfGuttered)

            if membershipRequests.isEmpty {
                emptyRequestsCard.pageBodyRow(top: 8, gutter: gutter)
            } else {
                membershipRequestsList.pageBodyRow(top: 8, gutter: gutter)
            }
        }

        Section {
            SectionRuleHeader(title: "Maintainers")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            maintainersPanel.pageBodyRow(top: 8, gutter: gutter)
            maintainersFootnote.pageBodyRow(top: 8, gutter: gutter)
        }

        Section {
            SectionRuleHeader(title: "Reveal and anonymity")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            revealInfoPanel.pageBodyRow(top: 8, gutter: gutter)
            if isUnrevealed || isAnonymous {
                revealActionsPanel.pageBodyRow(top: 8, gutter: gutter)
            }
            if let revealErrorMessage {
                errorNotice(revealErrorMessage).pageBodyRow(top: 8, gutter: gutter)
            }
        }
    }

    // MARK: - Awaiting Review

    private var awaitingReviewList: some View {
        VStack(spacing: 9) {
            ForEach(awaitingReview) { item in
                awaitingReviewCard(item)
            }
        }
    }

    /// Title, creator/submission line, and the three side-by-side actions —
    /// the same card `ModeratedItemsView.waitingItemCard` already draws.
    /// `AO3CollectionItem` carries no word count, submission date, or tag
    /// summary (see the model, and how `ModeratedItemsView` itself renders
    /// this same row), so this matches what actually exists rather than
    /// inventing those figures.
    private func awaitingReviewCard(_ item: AO3CollectionItem) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.itemType.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(9 * 0.11)
                    .foregroundStyle(palette.accent)

                Text(item.workTitle)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("\(item.creatorByline) · submitted to \(effectiveTitle)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                approveButton(for: item)
                rejectButton(for: item)
                messageCreatorButton(for: item)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .subjectPanel()
    }

    private func approveButton(for item: AO3CollectionItem) -> some View {
        let isCurrentInFlight = itemInFlight == item.id
        return Button {
            Task { await approveItem(item) }
        } label: {
            HStack(spacing: 6) {
                if isCurrentInFlight {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.green)
                }
                Text("Approve")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.green)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 99, style: .continuous)
                    .fill(Color.green.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 99, style: .continuous)
                            .strokeBorder(Color.green.opacity(0.34), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(itemInFlight != nil)
    }

    private func rejectButton(for item: AO3CollectionItem) -> some View {
        Button {
            selectedItemForReject = item
        } label: {
            Text("Reject")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.red)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 99, style: .continuous)
                        .fill(Color.red.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 99, style: .continuous)
                                .strokeBorder(Color.red.opacity(0.32), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(itemInFlight != nil)
    }

    /// Same behavior as `ModeratedItemsView.messageCreatorButton`: opens the
    /// work itself, since AO3's own moderator queue offers no separate
    /// messaging endpoint — a comment on the work is the fix-it channel.
    private func messageCreatorButton(for item: AO3CollectionItem) -> some View {
        GlassCircleButton(
            palette: palette,
            accessibilityName: "Message creator"
        ) {
            if let workURL = item.workURL {
                #if os(iOS)
                UIApplication.shared.open(workURL)
                #elseif os(macOS)
                NSWorkspace.shared.open(workURL)
                #endif
            }
        } label: {
            Image(systemName: "bubble.left")
                .font(.system(size: 13))
        }
    }

    private var emptyReviewCard: some View {
        VStack(spacing: 6) {
            Text("No works waiting for review")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            Text("All submissions to this collection have been reviewed.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .subjectPanel()
    }

    // MARK: - Membership Requests

    private var membershipRequestsList: some View {
        VStack(spacing: 9) {
            ForEach(membershipRequests) { participant in
                membershipRequestCard(participant)
            }
        }
    }

    /// `AO3CollectionParticipant` carries no request date or per-user work
    /// count (that figure lives on the unrelated `AO3CollectionPerson`, from
    /// the separate `/people` listing) — so the secondary line states the
    /// request itself rather than inventing either figure.
    private func membershipRequestCard(_ participant: AO3CollectionParticipant) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 4) {
                Text(participant.pseud)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Wants to join \(effectiveTitle)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                acceptButton(for: participant)
                declineButton(for: participant)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .subjectPanel()
    }

    private func acceptButton(for participant: AO3CollectionParticipant) -> some View {
        let isCurrentInFlight = participantInFlight == participant.id
        return Button {
            Task { await acceptRequest(participant) }
        } label: {
            HStack(spacing: 6) {
                if isCurrentInFlight {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.green)
                }
                Text("Accept")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.green)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 99, style: .continuous)
                    .fill(Color.green.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 99, style: .continuous)
                            .strokeBorder(Color.green.opacity(0.34), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(participantInFlight != nil)
    }

    private func declineButton(for participant: AO3CollectionParticipant) -> some View {
        Button {
            Task { await declineRequest(participant) }
        } label: {
            Text("Decline")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.red)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 99, style: .continuous)
                        .fill(Color.red.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 99, style: .continuous)
                                .strokeBorder(Color.red.opacity(0.32), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(participantInFlight != nil)
    }

    private var emptyRequestsCard: some View {
        VStack(spacing: 6) {
            Text("No membership requests")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Nobody is waiting to join \(effectiveTitle).")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
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
    private var maintainersPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(
                label: "Owners and moderators",
                value: maintainers.count == 1 ? "1 person" : "\(maintainers.count) people",
                showsDisclosure: true
            )
            .subjectRowNavigation(accessibilityLabel: "Owners and moderators") {
                CollectionMaintainersView(collectionSlug: collectionSlug, collectionTitle: effectiveTitle)
            }

            SubjectRowSeparator()

            NavigationLink {
                CollectionMaintainersView(collectionSlug: collectionSlug, collectionTitle: effectiveTitle)
            } label: {
                Text("Invite a maintainer")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .subjectPanel()
    }

    private var maintainersFootnote: some View {
        Text("Roles, invitations, and the last-owner rule live on Maintainers — this is just the headcount.")
            .font(.system(size: 11.5))
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
                value: isUnrevealed ? "Unrevealed until reveal" : "Revealed"
            )

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Creators",
                value: isAnonymous ? "Anonymous until reveal" : "Credited"
            )
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
                            .font(.system(size: 15))
                            .foregroundStyle(Color.red)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if isRevealing {
                            ProgressView()
                                .controlSize(.small)
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
                            .font(.system(size: 15))
                            .foregroundStyle(Color.red)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if isUnanonymizing {
                            ProgressView()
                                .controlSize(.small)
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
            .font(.system(size: 11.5))
            .foregroundStyle(Color.red)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    // MARK: - State Cards

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading moderation…")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }

    private func failureCard(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Couldn't load moderation")
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

    private func actionErrorCard(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color.red)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                actionErrorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .subjectPanel()
    }

    // MARK: - Actions

    private func loadIfNeeded() async {
        guard phase == .idle else { return }
        await load()
    }

    private func load() async {
        phase = .loading
        actionErrorMessage = nil
        do {
            let request = try auth.authenticatedRequest(for: AO3CollectionURL.participants(slug: collectionSlug))
            let moderation = try await AO3Client.shared.collectionModeration(slug: collectionSlug, request: request)
            awaitingReview = moderation.awaitingReview
            membershipRequests = moderation.membershipRequests
            maintainers = moderation.maintainers
            revealScheduleText = moderation.revealScheduleText
            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func approveItem(_ item: AO3CollectionItem) async {
        itemInFlight = item.id
        actionErrorMessage = nil
        do {
            try await auth.approveCollectionItem(slug: collectionSlug, itemID: item.id)
            withAnimation {
                awaitingReview.removeAll { $0.id == item.id }
            }
        } catch {
            actionErrorMessage = "Failed to approve: \(error.localizedDescription)"
        }
        itemInFlight = nil
    }

    private func acceptRequest(_ participant: AO3CollectionParticipant) async {
        participantInFlight = participant.id
        actionErrorMessage = nil
        do {
            try await auth.acceptMember(slug: collectionSlug, participantID: participant.id)
            withAnimation {
                membershipRequests.removeAll { $0.id == participant.id }
            }
        } catch {
            actionErrorMessage = "Failed to accept: \(error.localizedDescription)"
        }
        participantInFlight = nil
    }

    private func declineRequest(_ participant: AO3CollectionParticipant) async {
        participantInFlight = participant.id
        actionErrorMessage = nil
        do {
            try await auth.declineMember(slug: collectionSlug, participantID: participant.id)
            withAnimation {
                membershipRequests.removeAll { $0.id == participant.id }
            }
        } catch {
            actionErrorMessage = "Failed to decline: \(error.localizedDescription)"
        }
        participantInFlight = nil
    }

    private func performReveal() async {
        isRevealing = true
        revealErrorMessage = nil
        do {
            _ = try await auth.revealCollection(slug: collectionSlug)
            await load()
        } catch {
            revealErrorMessage = error.localizedDescription
        }
        isRevealing = false
    }

    private func performUnanon() async {
        isUnanonymizing = true
        revealErrorMessage = nil
        do {
            _ = try await auth.unanonCollection(slug: collectionSlug)
            await load()
        } catch {
            revealErrorMessage = error.localizedDescription
        }
        isUnanonymizing = false
    }
}
