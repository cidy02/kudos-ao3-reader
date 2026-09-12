import SwiftUI

/// Artboard **1bx** — Moderated items.
///
/// Moderator queue for a collection: reviews works submitted to the collection,
/// offering Approve, Reject (with emailed reason via artboard 1ce), and Message
/// creator actions, plus tally figures for recently decided submissions.
struct ModeratedItemsView: View {
    let collectionSlug: String
    var collectionTitle: String = ""

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme

    @State private var waitingItems: [AO3CollectionItem] = []
    @State private var approvedCount: Int = 0
    @State private var rejectedCount: Int = 0
    @State private var phase: Phase = .idle
    @State private var itemInFlight: Int?
    @State private var actionErrorMessage: String?
    @State private var selectedItemForReject: AO3CollectionItem?

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
        .navigationTitle("Moderated items")
        #endif
        .subjectScreenWash(palette: palette)
        .task { await loadItemsIfNeeded() }
        .refreshable { await loadItems() }
        .sheet(item: $selectedItemForReject) { item in
            RejectReasonSheet(
                collectionSlug: collectionSlug,
                item: item,
                palette: palette
            ) {
                withAnimation {
                    waitingItems.removeAll { $0.id == item.id }
                    rejectedCount += 1
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        SubjectHeaderBlock(
            kicker: "AO3 Account",
            title: "Moderated items",
            subtitle: "\(effectiveTitle) · \(waitingItems.count) waiting",
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
            SectionRuleHeader(title: "Waiting for review")
                .pageBodyRow(top: 18, gutter: selfGuttered)

            if waitingItems.isEmpty {
                emptyWaitingCard.pageBodyRow(top: 8, gutter: gutter)
            } else {
                waitingItemsList.pageBodyRow(top: 8, gutter: gutter)
            }

            reviewFootnote.pageBodyRow(top: 8, gutter: gutter)
        }

        Section {
            SectionRuleHeader(title: "Recently decided")
                .pageBodyRow(top: 18, gutter: selfGuttered)
            recentlyDecidedPanel.pageBodyRow(top: 8, gutter: gutter)
        }
    }

    // MARK: - Waiting Items

    private var waitingItemsList: some View {
        VStack(spacing: 9) {
            ForEach(waitingItems) { item in
                waitingItemCard(item)
            }
        }
    }

    private func waitingItemCard(_ item: AO3CollectionItem) -> some View {
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

    private var emptyWaitingCard: some View {
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

    private var reviewFootnote: some View {
        Text("Rejecting asks for a reason, which AO3 emails to the creator. "
            + "The message button sends a comment on the work instead, for a fix rather than a refusal.")
            .font(.system(size: 11.5))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    // MARK: - Recently Decided

    private var recentlyDecidedPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(
                label: "Approved",
                value: "\(approvedCount)",
                showsDisclosure: true,
                isMonospaced: true
            )

            SubjectRowSeparator()

            SubjectFormRow(
                label: "Rejected",
                value: "\(rejectedCount)",
                showsDisclosure: true,
                isMonospaced: true
            )
        }
        .subjectPanel()
    }

    // MARK: - State Cards

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading review queue…")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }

    private func failureCard(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Couldn't load moderated items")
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadItems() }
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

    private func loadItemsIfNeeded() async {
        guard phase == .idle else { return }
        await loadItems()
    }

    private func loadItems() async {
        phase = .loading
        actionErrorMessage = nil
        do {
            let unreviewedRequest = try auth.authenticatedRequest(
                for: AO3CollectionURL.items(slug: collectionSlug, tab: .unreviewed, page: 1)
            )
            let unreviewedPage = try await AO3Client.shared.collectionItems(
                slug: collectionSlug, tab: .unreviewed, page: 1, request: unreviewedRequest
            )
            waitingItems = unreviewedPage.items

            // Probe approved and rejected pages for decided counts.
            if let approvedRequest = try? auth.authenticatedRequest(
                for: AO3CollectionURL.items(slug: collectionSlug, tab: .approved, page: 1)
            ), let approvedPage = try? await AO3Client.shared.collectionItems(
                slug: collectionSlug, tab: .approved, page: 1, request: approvedRequest
            ) {
                approvedCount = approvedPage.items.count
            }

            if let rejectedRequest = try? auth.authenticatedRequest(
                for: AO3CollectionURL.items(slug: collectionSlug, tab: .rejected, page: 1)
            ), let rejectedPage = try? await AO3Client.shared.collectionItems(
                slug: collectionSlug, tab: .rejected, page: 1, request: rejectedRequest
            ) {
                rejectedCount = rejectedPage.items.count
            }

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
                waitingItems.removeAll { $0.id == item.id }
                approvedCount += 1
            }
        } catch {
            actionErrorMessage = "Failed to approve: \(error.localizedDescription)"
        }
        itemInFlight = nil
    }
}
