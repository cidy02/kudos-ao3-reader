import SwiftUI

/// Artboard **1bx** — Collection maintainers.
///
/// Displays owners and moderators for a collection, lets maintainers invite new
/// accounts by username, and provides the step-down/leave action subject to the
/// last-owner rule ("the last owner cannot remove themselves").
struct CollectionMaintainersView: View {
    let collectionSlug: String
    var collectionTitle: String = ""

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .body) private var rowTitleSize: CGFloat = 17
    @ScaledMetric(relativeTo: .subheadline) private var buttonLabelSize: CGFloat = 14
    @ScaledMetric(relativeTo: .footnote) private var subSize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 12
    @ScaledMetric(relativeTo: .headline) private var stateTitleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .subheadline) private var loadingSize: CGFloat = 14
    @ScaledMetric(relativeTo: .footnote) private var failureBodySize: CGFloat = 13

    @State private var participants: [AO3CollectionParticipant] = []
    @State private var phase: Phase = .idle
    @State private var showingInviteSheet: Bool = false
    @State private var inviteUsername: String = ""
    @State private var inviteRole: AO3CollectionParticipantRole = .moderator
    @State private var isInviting: Bool = false
    @State private var inviteErrorMessage: String?
    @State private var inviteSuccessNotice: String?
    @State private var confirmLeave: Bool = false
    @State private var leaveErrorMessage: String?
    @State private var isLeaving: Bool = false
    @State private var showLastOwnerAlert: Bool = false

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

    private var owners: [AO3CollectionParticipant] {
        participants.filter { $0.role == .owner }
    }

    private var moderators: [AO3CollectionParticipant] {
        participants.filter { $0.role == .moderator }
    }

    private var invitedParticipants: [AO3CollectionParticipant] {
        participants.filter { $0.role == .invited }
    }

    private var members: [AO3CollectionParticipant] {
        participants.filter { $0.role == .member }
    }

    private var maintainerRoster: [AO3CollectionParticipant] {
        owners + moderators + invitedParticipants
    }

    private var totalMaintainersCount: Int {
        owners.count + moderators.count
    }

    private var currentParticipant: AO3CollectionParticipant? {
        let loggedInPseud = auth.username?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !loggedInPseud.isEmpty else { return nil }
        return participants.first { $0.pseud.lowercased() == loggedInPseud }
    }

    private var isCurrentUserOwner: Bool {
        currentParticipant?.role == .owner
    }

    var body: some View {
        List {
            Section {
                contextCard.pageBodyRow(top: 12, gutter: gutter)
                if phase == .loaded {
                    ChallengeBoardStatStrip(cells: statCells, surface: .list)
                        .pageBodyRow(top: 14, gutter: gutter)
                }
            }

            if let inviteSuccessNotice {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(palette.accent)
                        Text(inviteSuccessNotice)
                            .font(.system(size: subSize, weight: .medium))
                            .foregroundStyle(palette.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .subjectPanel()
                    .pageBodyRow(top: 8, gutter: gutter)
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
        .subjectScreenWash(title: "Maintainers", palette: palette, role: .content)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    inviteErrorMessage = nil
                    showingInviteSheet = true
                } label: {
                    Label("Invite", systemImage: "plus")
                }
                .accessibilityLabel("Invite")
            }
        }
        .sheet(isPresented: $showingInviteSheet) {
            inviteSheet
        }
        .task { await loadMaintainersIfNeeded() }
        .refreshable { await loadMaintainers() }
        .alert("Cannot Step Down", isPresented: $showLastOwnerAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You're the last owner. Appoint another owner before you step down.")
        }
        .confirmationDialog(
            isCurrentUserOwner ? "Step down as owner?" : "Leave collection?",
            isPresented: $confirmLeave,
            titleVisibility: .visible
        ) {
            Button(isCurrentUserOwner ? "Step Down" : "Leave", role: .destructive) {
                Task { await performLeave() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(isCurrentUserOwner
                ? "You will relinquish owner privileges for \(effectiveTitle). "
                    + "Another owner must maintain the collection."
                : "You will no longer be a moderator for \(effectiveTitle).")
        }
            .screenTint(palette)
    }

    // MARK: - Header (`AO3-Collection-Maintainers.dc.html`)

    private var effectiveTitle: String {
        collectionTitle.isEmpty ? collectionSlug : collectionTitle
    }

    private var contextCard: some View {
        ChallengeBoardContextCard(
            systemImage: "archivebox",
            kicker: ChallengesBoardCopy.maintainersKicker,
            title: effectiveTitle,
            meta: ChallengesBoardCopy.maintainersContextMeta(
                isOwner: isCurrentUserOwner,
                isModerator: currentParticipant?.role == .moderator,
                maintainerCount: totalMaintainersCount
            ),
            palette: palette,
            surface: .list
        )
    }

    private var statCells: [ChallengeBoardStatStrip.Cell] {
        var cells = [
            ChallengeBoardStatStrip.Cell(value: totalMaintainersCount.formatted(), label: "Maintainers"),
            ChallengeBoardStatStrip.Cell(value: members.count.formatted(), label: "Members")
        ]
        if !invitedParticipants.isEmpty {
            cells.append(
                ChallengeBoardStatStrip.Cell(
                    value: invitedParticipants.count.formatted(),
                    label: "Invited",
                    tint: ChallengeBoardColors.warningInk(for: theme.appTheme)
                )
            )
        }
        return cells
    }

    // MARK: - Content Sections (`AO3-Collection-Maintainers.dc.html`)

    @ViewBuilder
    private var contentSections: some View {
        if !maintainerRoster.isEmpty {
            Section {
                ChallengeBoardListSectionHeader(
                    title: ChallengesBoardCopy.maintainersSectionTitle,
                    count: maintainerRoster.count
                )
                .pageBodyRow(top: 18, gutter: gutter)

                ForEach(Array(maintainerRoster.enumerated()), id: \.element.id) { index, participant in
                    VStack(spacing: 0) {
                        if index > 0 { SubjectRowSeparator(inset: 48) }
                        maintainerRow(for: participant)
                    }
                    .pageBodyRow(top: 0, gutter: gutter)
                }
            }
        }

        if !members.isEmpty {
            Section {
                ChallengeBoardListSectionHeader(
                    title: ChallengesBoardCopy.maintainersMembersSectionTitle,
                    count: members.count
                )
                .pageBodyRow(top: 18, gutter: gutter)

                ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                    VStack(spacing: 0) {
                        if index > 0 { SubjectRowSeparator(inset: 48) }
                        memberRow(member)
                    }
                    .pageBodyRow(top: 0, gutter: gutter)
                }
            }
        }

        Section {
            ChallengeBoardListSectionHeader(title: "Leave")
                .pageBodyRow(top: 18, gutter: gutter)
            leavePanel.pageBodyRow(top: 8, gutter: gutter)
            if let leaveErrorMessage {
                errorNotice(leaveErrorMessage).pageBodyRow(top: 8, gutter: gutter)
            }
        }
    }

    // MARK: - Rows & Invite Sheet

    private func maintainerRow(for participant: AO3CollectionParticipant) -> some View {
        // The role under the name at the accessibility sizes: beside it, a name of one word
        // broke in the middle ("AO3_Reade / r").
        let large = dynamicTypeSize.isAccessibilitySize
        let avatarColor = theme.appTheme.subjectPalette(hue: CoverArt.hue(for: participant.pseud)).accent
        let subtitle: String?
        let isWarningMeta: Bool
        switch participant.role {
        case .owner:
            subtitle = isCurrentAuthor(participant.pseud) ? ChallengesBoardCopy.maintainerOwnerSelfSubtitle : nil
            isWarningMeta = false
        case .moderator:
            subtitle = ChallengesBoardCopy.maintainerModeratorSubtitle
            isWarningMeta = false
        case .invited:
            subtitle = ChallengesBoardCopy.maintainerInvitedMeta
            isWarningMeta = true
        case .member, .none:
            subtitle = nil
            isWarningMeta = false
        }

        return HStack(alignment: large ? .top : .center, spacing: 12) {
            ChallengeBoardAvatar(
                text: ChallengesBoardCopy.personInitial(for: participant.pseud),
                color: avatarColor,
                shapeKind: .circle(size: 36)
            )
            .padding(.top, large ? 2 : 0)

            VStack(alignment: .leading, spacing: 2) {
                Text(participant.pseud)
                    .font(.system(size: rowTitleSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(
                            size: isWarningMeta ? captionSize : subSize,
                            weight: isWarningMeta ? .semibold : .regular
                        ))
                        .foregroundStyle(
                            isWarningMeta
                                ? AnyShapeStyle(ChallengeBoardColors.warningInk(for: theme.appTheme))
                                : AnyShapeStyle(.secondaryInk)
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
                if large { roleBadge(for: participant.role).padding(.top, 4) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !large { roleBadge(for: participant.role) }
        }
        .padding(.vertical, 10)
    }

    private func memberRow(_ participant: AO3CollectionParticipant) -> some View {
        let avatarColor = theme.appTheme.subjectPalette(hue: CoverArt.hue(for: participant.pseud)).accent
        return HStack(spacing: 12) {
            ChallengeBoardAvatar(
                text: ChallengesBoardCopy.personInitial(for: participant.pseud),
                color: avatarColor,
                shapeKind: .circle(size: 36)
            )

            Text(participant.pseud)
                .font(.system(size: rowTitleSize, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func roleBadge(for role: AO3CollectionParticipantRole) -> some View {
        switch role {
        case .owner:
            ChallengeBoardBadge(text: "Owner", style: .accentFill)
        case .moderator:
            let info = ChallengeBoardColors.infoBadge(for: theme.appTheme)
            ChallengeBoardBadge(
                text: "Moderator",
                style: .tinted(foreground: info.foreground, background: info.background)
            )
        case .invited:
            ChallengeBoardBadge(text: "Invited", style: .neutral)
        case .member, .none:
            EmptyView()
        }
    }

    private var inviteSheet: some View {
        NavigationStack {
            List {
                Section {
                    ChallengeBoardSectionHeader(title: "Invite a maintainer")
                        .padding(.bottom, 6)
                        .pageBodyRow(top: 14, gutter: selfGuttered)
                }
                Section {
                    invitationRows
                    invitationsFootnote.pageBodyRow(top: 8, gutter: gutter)
                }
            }
            .cardList()
            .environment(\.defaultMinListRowHeight, 0)
            .subjectScreenWash(title: "Invite", palette: palette, role: .grouped)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showingInviteSheet = false
                    } label: {
                        #if os(iOS)
                        Image(systemName: "xmark")
                        #else
                        Text("Close")
                        #endif
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .screenTint(palette)
    }

    /// One `List` row per field. The card was one row holding a bare `Picker`,
    /// and a `Picker` in a `List` row claims a tap anywhere in that row — so a
    /// tap meant for "Send invitation" could open the role menu instead. The
    /// role is `WritingChoiceRow`'s `Menu`, which answers only its own label.
    @ViewBuilder
    private var invitationRows: some View {
        let username = inviteUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = username.isEmpty ? 2 : 3
        SubjectFormRow(label: "Invite by Username", arrangement: .control) {
            TextField("Add a username", text: $inviteUsername)
                .font(.system(size: rowTitleSize))
                .foregroundStyle(.primary)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .multilineTextAlignment(.trailing)
        }
        .panelSegment(0, of: count, gutter: gutter)

        WritingChoiceRow(
            title: "Invite As",
            value: Binding(
                get: { inviteRole.rawValue },
                set: { inviteRole = AO3CollectionParticipantRole(rawValue: $0) ?? .moderator }
            ),
            options: [
                AO3FormOption(value: AO3CollectionParticipantRole.moderator.rawValue, title: "Moderator"),
                AO3FormOption(value: AO3CollectionParticipantRole.owner.rawValue, title: "Owner"),
            ]
        )
        .screenTint(palette)
        .panelSegment(1, of: count, gutter: gutter)

        if !username.isEmpty {
            Button {
                Task { await sendInvitation() }
            } label: {
                HStack {
                    if isInviting {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                            .accentFill()
                    }
                    Text("Send invitation to \(username)")
                        .font(.system(size: buttonLabelSize, weight: .semibold))
                        .foregroundStyle(theme.accentInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .disabled(isInviting)
            .panelSegment(2, of: count, gutter: gutter)
        }
    }

    private var invitationsFootnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let inviteSuccessNotice {
                Text(inviteSuccessNotice)
                    .font(.system(size: captionSize, weight: .medium))
                    .foregroundStyle(palette.accent)
                    .padding(.bottom, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let inviteErrorMessage {
                Text(inviteErrorMessage)
                    .font(.system(size: captionSize, weight: .medium))
                    .foregroundStyle(Color.red)
                    .padding(.bottom, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("AO3 sends the other account an invitation. Nothing changes until they accept it. "
                + "An owner can remove a moderator, but the last owner can't step down.")
                .font(.system(size: captionSize))
                .foregroundStyle(Color.secondary.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private var leavePanel: some View {
        VStack(spacing: 0) {
            Button {
                handleLeaveTap()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.red)
                        .frame(width: 20)

                    Text(isCurrentUserOwner ? "Step down as owner" : "Leave collection")
                        .font(.system(size: rowTitleSize))
                        .foregroundStyle(Color.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if isLeaving {
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
            .disabled(isLeaving)
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
            Text("Loading maintainers…")
                .font(.system(size: loadingSize))
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }

    private func failureCard(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Couldn't load maintainers")
                .font(.system(size: stateTitleSize, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.system(size: failureBodySize))
                .foregroundStyle(.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again") {
                Task { await loadMaintainers() }
            }
            .buttonStyle(.kudosSecondary)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .subjectPanel()
    }

    // MARK: - Actions

    private func isCurrentAuthor(_ pseud: String) -> Bool {
        let loggedIn = auth.username?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return !loggedIn.isEmpty && pseud.lowercased() == loggedIn
    }

    private func loadMaintainersIfNeeded() async {
        guard phase == .idle else { return }
        await loadMaintainers()
    }

    private func loadMaintainers() async {
        phase = .loading
        do {
            let request = try auth.authenticatedRequest(for: AO3CollectionURL.participants(slug: collectionSlug))
            let loaded = try await AO3Client.shared.collectionParticipants(slug: collectionSlug, request: request)
            participants = loaded
            phase = .loaded
        } catch {
            phase = .failed(UserFacingError.message(for: error))
        }
    }

    private func sendInvitation() async {
        let username = inviteUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else { return }
        isInviting = true
        inviteErrorMessage = nil
        inviteSuccessNotice = nil
        do {
            try await auth.inviteMaintainer(slug: collectionSlug, byline: username)
            inviteSuccessNotice = "Invitation sent to \(username)."
            inviteUsername = ""
            showingInviteSheet = false
            await loadMaintainers()
        } catch {
            inviteErrorMessage = UserFacingError.message(for: error)
        }
        isInviting = false
    }

    private func handleLeaveTap() {
        if isCurrentUserOwner && owners.count <= 1 {
            showLastOwnerAlert = true
            return
        }
        confirmLeave = true
    }

    private func performLeave() async {
        guard let participant = currentParticipant else {
            leaveErrorMessage = "Could not identify your maintainer record."
            return
        }
        isLeaving = true
        leaveErrorMessage = nil
        do {
            try await auth.leaveCollection(slug: collectionSlug, participantID: participant.id)
            NotificationCenter.default.post(name: .ao3CollectionChanged, object: collectionSlug)
            dismiss()
        } catch {
            leaveErrorMessage = UserFacingError.message(for: error)
            isLeaving = false
        }
    }
}
