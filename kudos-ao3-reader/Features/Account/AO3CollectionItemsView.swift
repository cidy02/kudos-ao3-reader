import SwiftUI

/// Navigation value for a collection's manage-items screen.
struct AO3CollectionItemsDestination: Hashable {
    let slug: String
    let title: String
}

/// Artboard **1s** — AO3's manage-collection-items screen, one card per item
/// instead of a table row.
///
/// The collection is the eyebrow with the item's role beside it, the work is the
/// title, and the four settings AO3 stacks in a control strip become labelled rows:
/// creator and moderator approval as chips you tap to change, Unrevealed and
/// Anonymous as switches. Remove is destructive and explicit.
///
/// **Changes stage rather than apply.** AO3 takes the whole items form in one POST,
/// so four settings across a dozen works would otherwise be a dozen round trips,
/// each able to fail on its own. The toolbar counts what is staged and the
/// checkmark submits. The rules for what counts as a change live in
/// `AO3CollectionItemStaging`.
struct AO3CollectionItemsView: View {
    let slug: String
    let title: String

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme

    @State private var tab: AO3CollectionItemTab = .unreviewed
    @State private var items: [AO3CollectionItem] = []
    @State private var staging = AO3CollectionItemStaging()
    @State private var phase: Phase = .idle
    @State private var submitError: String?

    private enum Phase: Equatable { case idle, loading, loaded, submitting, failed(String) }

    /// The spec's four pills. `rejectedByUser` is deliberately not one: AO3 keeps
    /// it as a separate tab, but a creator who declined their own work has made a
    /// decision rather than one waiting on them, and the spec draws four.
    private static let tabs: [AO3CollectionItemTab] = [
        .unreviewed, .invited, .rejected, .approved
    ]

    private var pendingCount: Int { staging.pendingCount(for: items) }

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
            case .idle, .loading:
                Section { loadingRow.pageBodyRow(top: 20, gutter: SubjectMetrics.accountGutter) }
            case let .failed(message):
                Section {
                    errorCard(message).pageBodyRow(top: 14, gutter: SubjectMetrics.accountGutter)
                }
            default:
                itemSections
            }
        }
        .cardList()
        .subjectScreenWash(palette: palette)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await submit() }
                } label: {
                    Label("Submit \(pendingCount) staged change\(pendingCount == 1 ? "" : "s")",
                          systemImage: "checkmark")
                }
                .disabled(pendingCount == 0 || phase == .submitting)
            }
            if pendingCount > 0 {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") { staging.clearAll() }
                }
            }
        }
        .task(id: tab) { await load() }
        .refreshable { await load() }
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

    /// Spec 1s: "Your works in AO3 collections · 3 need a decision". The second half
    /// is the whole reason to open this screen, so it leads once anything is staged.
    private var tallyLine: String {
        if pendingCount > 0 {
            return "\(title) · \(pendingCount) staged, not yet sent"
        }
        let count = items.count
        return "\(title) · \(count) item\(count == 1 ? "" : "s")"
    }

    private var tabStrip: some View {
        SubjectSegmentedControl(
            options: Self.tabs,
            title: { Self.tabTitle($0) },
            selection: $tab
        )
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
        theme.appTheme.subjectPalette(hue: theme.scopeHue)
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

    private func load() async {
        guard auth.isLoggedIn else {
            phase = .failed("Log in to AO3 to manage collection items.")
            return
        }
        phase = .loading
        do {
            let request = try auth.authenticatedRequest(for: AO3CollectionURL.edit(slug: slug))
            let page = try await AO3Client.shared.collectionItems(
                slug: slug, tab: tab, page: 1, request: request
            )
            items = page.items
            phase = .loaded
        } catch let error as AO3Error {
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Sends everything staged in one POST, then reloads.
    ///
    /// **The staging is only cleared after a successful send.** A failure that
    /// discarded the edits would lose work the reader cannot see anywhere else, so
    /// a failed submit leaves every change exactly where it was and says why.
    private func submit() async {
        let drafts = staging.pendingDrafts(for: items)
        guard !drafts.isEmpty else { return }
        phase = .submitting
        submitError = nil
        do {
            try await auth.updateCollectionItems(slug: slug, drafts: drafts)
            staging.clearAll()
            await load()
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
            approvalRow(
                "Approved by creator",
                value: staging.creatorApproval(for: item),
                set: { staging.setCreatorApproval($0, for: item) }
            )
            SubjectRowSeparator()
            approvalRow(
                "Approved by moderators",
                value: staging.moderatorApproval(for: item),
                set: { staging.setModeratorApproval($0, for: item) }
            )
            SubjectRowSeparator()
            SubjectFormRow(
                label: "Unrevealed",
                arrangement: .control,
                trailing: {
                    Toggle("", isOn: Binding(
                        get: { staging.isUnrevealed(for: item) },
                        set: { staging.setUnrevealed($0, for: item) }
                    ))
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            )
            SubjectRowSeparator()
            SubjectFormRow(
                label: "Anonymous",
                arrangement: .control,
                trailing: {
                    Toggle("", isOn: Binding(
                        get: { staging.isAnonymous(for: item) },
                        set: { staging.setAnonymous($0, for: item) }
                    ))
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
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
            Spacer(minLength: 6)
            Button {
                staging.setRemoved(!isRemoved, for: item)
            } label: {
                Text(isRemoved ? "Keep" : "Remove from collection")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isRemoved ? Color.accentColor : .red)
            }
            .buttonStyle(.plain)
        }
    }
}
