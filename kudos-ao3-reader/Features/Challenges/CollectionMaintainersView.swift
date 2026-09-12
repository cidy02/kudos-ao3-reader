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

    @State private var participants: [AO3CollectionParticipant] = []
    @State private var phase: Phase = .idle
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
        .navigationTitle("Maintainers")
        #endif
        .subjectScreenWash(palette: palette)
        .task { await loadMaintainersIfNeeded() }
        .refreshable { await loadMaintainers() }
        .alert("Cannot Step Down", isPresented: $showLastOwnerAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The last owner cannot remove themselves. Appoint another owner before stepping down.")
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
    }

    // MARK: - Header

    private var effectiveTitle: String {
        collectionTitle.isEmpty ? collectionSlug : collectionTitle
    }

    private var subtitleText: String {
        let countString = totalMaintainersCount == 1 ? "1 person" : "\(totalMaintainersCount) people"
        return "\(effectiveTitle) · \(countString)"
    }

    private var header: some View {
        SubjectHeaderBlock(
            kicker: "AO3 Account",
            title: "Maintainers",
            subtitle: subtitleText,
            palette: palette,
            gutter: SubjectMetrics.accountGutter
        )
    }

    // MARK: - Content Sections

    @ViewBuilder
    private var contentSections: some View {
        if !owners.isEmpty {
            Section {
                SectionRuleHeader(title: "Owners")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                ownersPanel.pageBodyRow(top: 8, gutter: gutter)
            }
        }

        if !moderators.isEmpty {
            Section {
                SectionRuleHeader(title: "Moderators")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                moderatorsPanel.pageBodyRow(top: 8, gutter: gutter)
            }
        }

        Section {
            SectionRuleHeader(title: "Invitations")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            invitationsPanel.pageBodyRow(top: 8, gutter: gutter)
            invitationsFootnote.pageBodyRow(top: 8, gutter: gutter)
        }

        Section {
            SectionRuleHeader(title: "Leave")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            leavePanel.pageBodyRow(top: 8, gutter: gutter)
            if let leaveErrorMessage {
                errorNotice(leaveErrorMessage).pageBodyRow(top: 8, gutter: gutter)
            }
        }
    }

    // MARK: - Panels

    private var ownersPanel: some View {
        VStack(spacing: 0) {
            ForEach(Array(owners.enumerated()), id: \.element.id) { index, owner in
                if index > 0 {
                    SubjectRowSeparator()
                }
                maintainerRow(
                    participant: owner,
                    roleText: "Owner",
                    subtitleText: isCurrentAuthor(owner.pseud) ? "You · created the collection" : "Owner"
                )
            }
        }
        .subjectPanel()
    }

    private var moderatorsPanel: some View {
        VStack(spacing: 0) {
            ForEach(Array(moderators.enumerated()), id: \.element.id) { index, moderator in
                if index > 0 {
                    SubjectRowSeparator()
                }
                maintainerRow(
                    participant: moderator,
                    roleText: "Moderator",
                    subtitleText: "Can approve works, cannot delete the collection"
                )
            }
        }
        .subjectPanel()
    }

    private func maintainerRow(
        participant: AO3CollectionParticipant,
        roleText: String,
        subtitleText: String
    ) -> some View {
        HStack(spacing: 11) {
            avatarCircle(for: participant.pseud)

            VStack(alignment: .leading, spacing: 2) {
                Text(participant.pseud)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)

                Text(subtitleText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(roleText.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(10.5 * 0.04)
                .foregroundStyle(Color.secondary.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 99, style: .continuous)
                        .fill(theme.appTheme.glassFill(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 99, style: .continuous)
                                .strokeBorder(theme.appTheme.glassStroke(0.12), lineWidth: 0.5)
                        )
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func avatarCircle(for pseud: String) -> some View {
        let initial = String(pseud.prefix(1)).uppercased()
        let theme = theme.appTheme
        return ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            palette.accent.opacity(0.35),
                            theme.cardBackdrop.opacity(0.8)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(Circle().strokeBorder(theme.glassStroke(0.16), lineWidth: 0.5))

            Text(initial)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.accentOnFill)
        }
        .frame(width: 32, height: 32)
    }

    private var invitationsPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(label: "Invite by username", arrangement: .control) {
                TextField("Add a username", text: $inviteUsername)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .multilineTextAlignment(.trailing)
            }

            SubjectRowSeparator()

            SubjectFormRow(label: "Invite as", arrangement: .value) {
                Picker("Invite as", selection: $inviteRole) {
                    Text("Moderator").tag(AO3CollectionParticipantRole.moderator)
                    Text("Owner").tag(AO3CollectionParticipantRole.owner)
                }
                .pickerStyle(.menu)
                .tint(palette.accent)
            }

            if !inviteUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                SubjectRowSeparator()

                Button {
                    Task { await sendInvitation() }
                } label: {
                    HStack {
                        if isInviting {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 4)
                        }
                        Text("Send invitation to \(inviteUsername.trimmingCharacters(in: .whitespacesAndNewlines))")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .disabled(isInviting)
            }
        }
        .subjectPanel()
    }

    private var invitationsFootnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let inviteSuccessNotice {
                Text(inviteSuccessNotice)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(palette.accent)
                    .padding(.bottom, 2)
            }
            if let inviteErrorMessage {
                Text(inviteErrorMessage)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.red)
                    .padding(.bottom, 2)
            }
            Text("AO3 sends an invitation the other account accepts; until then nothing changes. "
                + "An owner can remove a moderator, but the last owner cannot remove themselves.")
                .font(.system(size: 11.5))
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
                        .font(.system(size: 15))
                        .foregroundStyle(Color.red)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isLeaving {
                        ProgressView()
                            .controlSize(.small)
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
            Text("Loading maintainers…")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }

    private func failureCard(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Couldn't load maintainers")
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadMaintainers() }
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
            phase = .failed(error.localizedDescription)
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
            await loadMaintainers()
        } catch {
            inviteErrorMessage = error.localizedDescription
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
            dismiss()
        } catch {
            leaveErrorMessage = error.localizedDescription
            isLeaving = false
        }
    }
}
