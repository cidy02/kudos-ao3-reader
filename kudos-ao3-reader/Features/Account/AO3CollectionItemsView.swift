import SwiftUI

/// Navigation value for a collection's manage-items screen.
/// `slug == nil` is the account-wide page, `GET /users/:login/collection_items`.
struct AO3CollectionItemsDestination: Hashable {
    var slug: String?
    var title: String
}

/// Artboard **1s** — AO3's manage-collection-items screen, one card per item
/// instead of a table row.
///
/// The collection is the eyebrow with the item's role beside it, the work is the
/// title, and the four settings AO3 stacks in a control strip become labelled rows:
/// creator and moderator approval as chips you tap to change, Unrevealed and
/// Anonymous as switches. A control AO3 rendered `disabled` is a fact, not a
/// control, and is left out of the POST. Remove is destructive and explicit.
///
/// **Changes stage rather than apply.** AO3 takes the whole items form in one POST,
/// so four settings across a dozen works would otherwise be a dozen round trips,
/// each able to fail on its own. The toolbar counts what is staged and the
/// checkmark submits. The rules for what counts as a change live in
/// `AO3CollectionItemStaging`.
struct AO3CollectionItemsView: View {
    /// Nil opens every collection's items for the signed-in user.
    let slug: String?
    let title: String

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme

    @State private var tab: AO3CollectionItemTab = .unreviewed
    @State private var items: [AO3CollectionItem] = []
    @State private var currentPage = 1
    @State private var totalPages = 1
    @State private var staging = AO3CollectionItemStaging()
    @State private var phase: Phase = .idle
    @State private var loadGeneration = 0
    @State private var submitError: String?

    private enum Phase: Equatable { case idle, loading, loaded, submitting, failed(String) }

    /// The spec's four pills. `rejectedByUser` is deliberately not one: AO3 keeps
    /// it as a separate tab, but a creator who declined their own work has made a
    /// decision rather than one waiting on them, and the spec draws four.
    private static let tabs: [AO3CollectionItemTab] = [
        .unreviewed, .invited, .rejected, .approved
    ]

    /// Drafts AO3 will actually store. A field the page disables does not count,
    /// and does not get cleared off another page when this one submits.
    private var submittableDrafts: [AO3CollectionItemDraft] {
        staging.pendingDrafts(for: items).compactMap { draft in
            guard let item = items.first(where: { $0.id == draft.itemID }) else { return nil }
            let stored = AO3CollectionItemSubmission.draftAO3WillStore(draft, item: item)
            return AO3CollectionItemSubmission.isSubmittable(stored) ? stored : nil
        }
    }

    private var pendingCount: Int { submittableDrafts.count }

    private var showPagination: Bool { totalPages > 1 }

    var body: some View {
        List {
            Section {
                header.pageBodyRow(top: 20, gutter: 0)
                tabStrip.pageBodyRow(top: 14, gutter: SubjectMetrics.accountGutter)
                if let submitError {
                    errorCard(submitError).pageBodyRow(top: 12, gutter: SubjectMetrics.accountGutter)
                }
            }

            switch phase {
            case .idle, .loading where items.isEmpty:
                Section { loadingRow.pageBodyRow(top: 20, gutter: SubjectMetrics.accountGutter) }
            case let .failed(message) where items.isEmpty:
                Section {
                    errorCard(message).pageBodyRow(top: 14, gutter: SubjectMetrics.accountGutter)
                }
            case let .failed(message):
                Section {
                    errorCard(message).pageBodyRow(top: 14, gutter: SubjectMetrics.accountGutter)
                }
                itemSections
            default:
                itemSections
            }

            if showPagination {
                Section {
                    paginationBar.pageBodyRow(top: 14, gutter: SubjectMetrics.accountGutter)
                }
            }
        }
        .cardList()
        .subjectScreenWash(palette: palette)
        .toolbar {
            if pendingCount > 0 {
                ToolbarItem(placement: .primaryAction) {
                    Text("\(pendingCount) staged")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(
                            "\(pendingCount) staged change\(pendingCount == 1 ? "" : "s")"
                        )
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await submit() }
                } label: {
                    Label("Submit staged changes", systemImage: "checkmark")
                }
                .disabled(pendingCount == 0 || phase == .submitting)
                .accessibilityLabel(
                    pendingCount == 0
                        ? "Submit staged changes"
                        : "Submit \(pendingCount) staged change\(pendingCount == 1 ? "" : "s")"
                )
            }
            if pendingCount > 0 {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") { staging.clearAll() }
                }
            }
        }
        .task(id: tab) { await load(page: 1, replacing: true) }
        .refreshable { await load(page: currentPage, replacing: false) }
    }

    // MARK: Header

    private var header: some View {
        SubjectHeaderBlock(
            kicker: "AO3 Account › Collections",
            title: "Collection items",
            subtitle: tallyLine,
            palette: palette,
            gutter: SubjectMetrics.accountGutter
        )
    }

    /// Spec 1s: "Your works in AO3 collections · 3 need a decision". The staged
    /// count lives in the toolbar, not in this line.
    private var tallyLine: String {
        let scope = slug == nil ? "Your works in AO3 collections" : title
        let decisions = AO3CollectionItemSubmission.decisionsNeeded(items)
        if let phrase = AO3CollectionItemSubmission.decisionPhrase(for: decisions), !items.isEmpty {
            return pageSuffix("\(scope) · \(phrase)")
        }
        let count = items.count
        return pageSuffix("\(scope) · \(count) item\(count == 1 ? "" : "s")")
    }

    private func pageSuffix(_ line: String) -> String {
        guard totalPages > 1 else { return line }
        return "\(line) · page \(currentPage) of \(totalPages)"
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.tabs, id: \.self) { option in
                    Button {
                        tab = option
                    } label: {
                        SubjectChip(
                            text: Self.tabTitle(option),
                            style: .pill(isSelected: tab == option),
                            palette: palette
                        )
                    }
                    .buttonStyle(.plain)
                    .minimumHitTarget(28)
                }
                Button {
                    if tab != .unreviewed {
                        tab = .unreviewed
                    }
                } label: {
                    SubjectChip(
                        text: "Reset",
                        style: .pill(isSelected: false),
                        systemImage: "xmark"
                    )
                    .opacity(tab == .unreviewed ? 0.45 : 0.7)
                }
                .buttonStyle(.plain)
                .minimumHitTarget(28)
                .disabled(tab == .unreviewed)
                .accessibilityLabel("Reset filters")
            }
            .padding(.horizontal, 16)
        }
    }

    private var paginationBar: some View {
        SearchPaginationBar(
            currentPage: currentPage,
            totalPages: totalPages,
            isLoading: phase == .loading,
            palette: palette
        ) { page in
            Task { await load(page: page, replacing: false) }
        }
    }

    private static func tabTitle(_ tab: AO3CollectionItemTab) -> String {
        switch tab {
        case .unreviewed: "Awaiting collection"
        case .invited: "Awaiting you"
        case .rejected: "Rejected"
        case .rejectedByUser: "Declined"
        case .approved: "Approved"
        }
    }

    private var palette: SubjectPalette {
        theme.scopePalette
    }

    // MARK: Items

    @ViewBuilder
    private var itemSections: some View {
        if items.isEmpty {
            Section {
                emptyCard.pageBodyRow(top: 14, gutter: SubjectMetrics.accountGutter)
            }
        } else {
            Section {
                SectionRuleHeader(title: Self.tabTitle(tab), count: items.count)
                    .pageBodyRow(top: 18, gutter: 0)
                ForEach(items) { item in
                    AO3CollectionItemCard(
                        item: item,
                        staging: $staging,
                        palette: palette
                    )
                    .pageBodyRow(top: 10, gutter: SubjectMetrics.accountGutter)
                }
            }
        }
    }

    private var emptyCard: some View {
        Text("Nothing in this tab.")
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .subjectPanel()
    }

    private var loadingRow: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
    }

    private func errorCard(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12.5))
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .subjectPanel()
    }

    // MARK: Loading and submitting

    /// `replacing` clears the rows first. A tab change must not keep the previous
    /// tab's works on screen. A page change keeps them until the next page arrives.
    /// Staging is left alone either way: a draft for a row that is not on this
    /// page is not submitted (`pendingDrafts` drops it) and is not discarded.
    private func load(page requestedPage: Int, replacing: Bool) async {
        guard auth.isLoggedIn else {
            phase = .failed("Log in to AO3 to manage collection items.")
            return
        }
        let expectedSessionGeneration = auth.sessionGeneration
        let requestedTab = tab
        loadGeneration += 1
        let generation = loadGeneration
        if replacing {
            items = []
            totalPages = 1
        }
        currentPage = requestedPage
        phase = .loading
        do {
            let fetched: AO3CollectionItemsPage
            if let slug {
                let request = try auth.authenticatedRequest(
                    for: AO3CollectionURL.items(slug: slug, tab: tab, page: requestedPage)
                )
                fetched = try await AO3Client.shared.collectionItems(
                    slug: slug, tab: tab, page: requestedPage, request: request
                )
            } else if let username = auth.username,
                      let url = AO3CollectionURL.userItems(
                        username: username, tab: tab, page: requestedPage
                      ) {
                let request = try auth.authenticatedRequest(for: url)
                fetched = try await AO3Client.shared.userCollectionItems(
                    username: username, tab: tab, page: requestedPage, request: request
                )
            } else {
                phase = .failed("Log in to AO3 to manage collection items.")
                return
            }
            guard generation == loadGeneration, tab == requestedTab,
                  auth.sessionGeneration == expectedSessionGeneration else { return }
            items = fetched.items
            currentPage = fetched.currentPage
            totalPages = max(fetched.totalPages, 1)
            phase = .loaded
        } catch AO3Error.authenticationRequired {
            guard generation == loadGeneration else { return }
            guard await auth.sessionDidExpire(expectedGeneration: expectedSessionGeneration) else { return }
            items = []
            phase = .failed("Log in to AO3 to manage collection items.")
        } catch is CancellationError {
        } catch let urlError as URLError where urlError.code == .cancelled {
        } catch let error as AO3Error {
            guard generation == loadGeneration,
                  auth.sessionGeneration == expectedSessionGeneration else { return }
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch {
            guard generation == loadGeneration,
                  auth.sessionGeneration == expectedSessionGeneration else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// Sends everything staged in one POST, then reloads.
    ///
    /// **The staging is only cleared after a successful send.** A failure that
    /// discarded the edits would lose work the reader cannot see anywhere else, so
    /// a failed submit leaves every change exactly where it was and says why.
    private func submit() async {
        let drafts = submittableDrafts
        guard !drafts.isEmpty else { return }
        phase = .submitting
        submitError = nil
        do {
            if let slug {
                try await auth.updateCollectionItems(slug: slug, drafts: drafts)
            } else if let username = auth.username {
                try await auth.updateUserCollectionItems(username: username, drafts: drafts)
            } else {
                throw AO3CollectionWriteError.notSignedIn
            }
            staging.clear(itemIDs: drafts.map(\.itemID))
            await load(page: currentPage, replacing: false)
        } catch let error as AO3CollectionWriteError {
            submitError = error.errorDescription ?? "Those changes could not be sent."
            phase = .loaded
        } catch {
            submitError = error.localizedDescription
            phase = .loaded
        }
    }
}

/// One item card — spec 1s's per-item layout.
struct AO3CollectionItemCard: View {
    let item: AO3CollectionItem
    @Binding var staging: AO3CollectionItemStaging
    let palette: SubjectPalette

    private var isRemoved: Bool { staging.isRemoved(item) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            Text(item.workTitle)
                .font(.system(size: 16.5, weight: .semibold))
                .lineLimit(2)
                .strikethrough(isRemoved)

            if isRemoved {
                removalNotice
            } else {
                settingsPanel
            }

            footerRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .subjectCard(palette: palette)
        .opacity(isRemoved ? 0.7 : 1)
    }

    /// The collection is the eyebrow, with the item's role beside it.
    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            SubjectKicker(
                text: item.collectionTitle,
                palette: palette,
                ruleWidth: SubjectMetrics.kickerRuleWidth,
                ruleSpacing: 5
            )
            Spacer(minLength: 6)
            if !item.role.isEmpty {
                Text(item.role)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            if staging.hasChanges(for: item) {
                Circle()
                    .fill(palette.accent)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("Has unsent changes")
            }
        }
    }

    private var settingsPanel: some View {
        VStack(spacing: 0) {
            if item.creatorApprovalIsEditable {
                approvalRow(
                    "Approved by creator",
                    value: staging.creatorApproval(for: item),
                    set: { staging.setCreatorApproval($0, for: item) }
                )
            } else {
                readOnlyApproval("Approved by creator", value: item.creatorApproval)
            }
            SubjectRowSeparator()
            if item.moderatorApprovalIsEditable {
                approvalRow(
                    "Approved by moderators",
                    value: staging.moderatorApproval(for: item),
                    set: { staging.setModeratorApproval($0, for: item) }
                )
            } else {
                readOnlyApproval("Approved by moderators", value: item.moderatorApproval)
            }
            SubjectRowSeparator()
            flagRow(
                "Unrevealed",
                isOn: staging.isUnrevealed(for: item),
                isEditable: item.unrevealedIsEditable,
                set: { staging.setUnrevealed($0, for: item) }
            )
            SubjectRowSeparator()
            flagRow(
                "Anonymous",
                isOn: staging.isAnonymous(for: item),
                isEditable: item.anonymousIsEditable,
                set: { staging.setAnonymous($0, for: item) }
            )
        }
        .subjectPanel()
    }

    /// Approval is three states on AO3, not a switch, so it is a three-way control
    /// rather than a toggle that would have to pretend Unreviewed is Rejected.
    private func approvalRow(
        _ label: String,
        value: AO3CollectionItemApproval,
        set: @escaping (AO3CollectionItemApproval) -> Void
    ) -> some View {
        SubjectFormRow(
            label: label,
            arrangement: .control,
            trailing: {
                SubjectSegmentedControl(
                    options: [.unreviewed, .approved, .rejected],
                    title: { Self.approvalTitle($0) },
                    selection: Binding(get: { value }, set: set)
                )
            }
        )
    }

    private func readOnlyApproval(
        _ label: String,
        value: AO3CollectionItemApproval
    ) -> some View {
        SubjectFormRow(
            label: label,
            arrangement: .control,
            trailing: {
                Text(Self.approvalTitle(value))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        )
    }

    private func flagRow(
        _ label: String,
        isOn: Bool,
        isEditable: Bool,
        set: @escaping (Bool) -> Void
    ) -> some View {
        SubjectFormRow(
            label: label,
            arrangement: .control,
            trailing: {
                if isEditable {
                    Toggle("", isOn: Binding(get: { isOn }, set: set))
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    Text(isOn ? "On" : "Off")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        )
    }

    private static func approvalTitle(_ approval: AO3CollectionItemApproval) -> String {
        switch approval {
        case .unreviewed: "Awaiting"
        case .approved: "Approved"
        case .rejected: "Rejected"
        }
    }

    private var removalNotice: some View {
        Text("Staged for removal from this collection. The work stays on AO3.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footerRow: some View {
        HStack(spacing: 12) {
            if !item.creatorByline.isEmpty {
                Text(item.creatorByline)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if item.removeIsEditable || isRemoved {
                Button {
                    staging.setRemoved(!isRemoved, for: item)
                } label: {
                    Text(isRemoved ? "Keep" : "Remove from collection")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isRemoved ? Color.accentColor : .red)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 6)
            if !item.itemDateText.isEmpty {
                Text(item.itemDateText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
