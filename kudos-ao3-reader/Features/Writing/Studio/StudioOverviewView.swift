import SwiftUI

/// Writing Studio › Overview (`Studio-Overview.dc.html` and `Studio-Offline.dc.html`).
///
/// Renders device-local writing progress (Today ring, goal, streak, 7-day strip), Continue
/// writing card, signed-in Comments and Stats glances, Recent documents strip, and either
/// Manage links (signed in) or the "Ready to share it?" prompt (signed out).
///
/// Challenge assignments are intentionally omitted: `AO3Client+Challenges` only exposes
/// collection-maintainer assignment endpoints, not a user's personal assignments due list.
struct StudioOverviewView: View {
    let daySnapshot: StudioDayLogSnapshot
    let localDocuments: [StudioLocalDocumentSummary]
    let drafts: AO3DraftsPage?
    let isLoadingDrafts: Bool
    let draftsError: String?
    let stats: AO3UserStats?
    let isLoadingStats: Bool
    let statsError: String?
    let recentPostedWorks: [AO3WorkSummary]
    let cachedCount: (AO3AccountListKind) -> String?
    let now: Date
    let onTapGoal: () -> Void
    let onStartNewDocument: () -> Void
    let onOpenLocalDocument: (StudioLocalDocumentTarget) -> Void
    let onOpenAO3Draft: (Int) -> Void
    let onOpenAO3Work: (AO3WorkSummary) -> Void
    let onSelectSection: (StudioSection) -> Void
    let onOpenRequests: () -> Void
    let onOpenYourWorks: () -> Void
    let onOpenAO3Drafts: () -> Void
    let onOpenSeries: () -> Void
    let onOpenCollections: () -> Void
    let onOpenGifts: () -> Void
    let onOpenImport: () -> Void
    let onRetryDrafts: () -> Void
    let onRetryStats: () -> Void
    let onSignIn: () -> Void
    let onRefresh: () async -> Void

    @Environment(AO3AuthService.self) private var auth
    @Environment(AO3InboxModel.self) private var inboxModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @AppStorage(StudioWritingGoal.storageKey) private var storedDailyGoal: Int = StudioWritingGoal.defaultGoal

    private var dailyGoal: Int? {
        StudioWritingGoal.resolvedGoal(fromStored: storedDailyGoal)
    }

    private var gutter: CGFloat { SubjectMetrics.accountGutter }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                StudioTodayCard(
                    snapshot: daySnapshot,
                    dailyGoal: dailyGoal,
                    onTapGoal: onTapGoal
                )
                .padding(.horizontal, gutter)

                continueCard
                    .padding(.horizontal, gutter)

                if auth.isLoggedIn {
                    commentsSection
                        .padding(.horizontal, gutter)

                    statsSection
                        .padding(.horizontal, gutter)
                }

                recentDocumentsSection

                if auth.isLoggedIn {
                    manageSection
                        .padding(.horizontal, gutter)
                } else {
                    signedOutShareCard
                        .padding(.horizontal, gutter)
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .refreshable { await onRefresh() }
    }

    // MARK: - Continue writing card

    private var continueTarget: StudioContinueItem? {
        var candidates: [StudioContinueItem] = []
        if let latestLocal = localDocuments.first {
            candidates.append(.local(latestLocal))
        }
        if auth.isLoggedIn, let latestDraft = drafts?.page.works.first {
            candidates.append(.ao3Draft(
                work: latestDraft,
                deletion: drafts?.deletionDates[latestDraft.id]
            ))
        }
        return candidates.max { $0.sortDate < $1.sortDate }
    }

    @ViewBuilder
    private var continueCard: some View {
        if let target = continueTarget {
            StudioContinueCard(
                item: target,
                now: now,
                onContinue: {
                    switch target {
                    case let .local(doc): onOpenLocalDocument(doc.target)
                    case let .ao3Draft(work, _): onOpenAO3Draft(work.id)
                    }
                }
            )
        } else if auth.isLoggedIn && isLoadingDrafts {
            HStack(spacing: 10) {
                ProgressView().accentFill()
                Text("Loading your latest draft…")
                    .font(.subheadline)
                    .foregroundStyle(.secondaryInk)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .subjectPanel()
        } else if auth.isLoggedIn, let draftsError {
            VStack(alignment: .leading, spacing: 10) {
                Text("Couldn't load AO3 drafts")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(draftsError)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                HStack(spacing: 10) {
                    Button("Try Again", action: onRetryDrafts)
                        .buttonStyle(.kudosSecondary)
                    Button("New Document", action: onStartNewDocument)
                        .buttonStyle(.kudosPrimary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .subjectPanel()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Start writing")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(
                    "Your manuscripts stay on this \(ThisDevice.name) as you write. "
                        + "Post to AO3 whenever you're ready."
                )
                .font(.subheadline)
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                Button(action: onStartNewDocument) {
                    Label("New Document", systemImage: "square.and.pencil")
                }
                .buttonStyle(.kudosPrimary)
                .accessibilityLabel("Start a new document")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .subjectPanel()
        }
    }

    // MARK: - Comments glance (signed in)

    private var commentsNeedingReply: [AO3InboxItem] {
        let awaiting = inboxModel.items.filter { $0.canReply && !$0.isReplied && !$0.isUnavailable }
        if !awaiting.isEmpty { return awaiting }
        return inboxModel.items.filter { $0.isUnread && !$0.isUnavailable }
    }

    private var awaitingReplyCount: Int {
        AO3InboxTally.awaitingReplyCount(inboxModel.items)
    }

    private var commentsSubtitle: String? {
        switch inboxModel.phase {
        case .idle, .loading, .failed:
            return nil
        case .loaded, .paginationFailed:
            if awaitingReplyCount > 0 {
                if awaitingReplyCount == 1 { return "1 needs a reply" }
                return "\(awaitingReplyCount.formatted()) need a reply"
            }
            if let unread = inboxModel.unreadCount, unread > 0 {
                return "\(unread.formatted()) unread"
            }
            return "All caught up"
        }
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Comments",
                subtitle: commentsSubtitle,
                actionTitle: "Open",
                actionAccessibilityLabel: "Open Comments"
            ) {
                onSelectSection(.comments)
            }

            switch inboxModel.phase {
            case .idle, .loading:
                HStack(spacing: 10) {
                    ProgressView().accentFill()
                    Text("Loading comments…")
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .subjectPanel()

            case let .failed(message):
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                    Button("Open Comments") { onSelectSection(.comments) }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.accentInk)
                        .buttonStyle(.plain)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .subjectPanel()

            case .loaded, .paginationFailed:
                let previews = Array(commentsNeedingReply.prefix(2))
                if previews.isEmpty {
                    Button { onSelectSection(.comments) } label: {
                        HStack {
                            Text("No comments waiting for a reply.")
                                .font(.subheadline)
                                .foregroundStyle(.secondaryInk)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .subjectPanel()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Comments, none waiting for a reply. Open Comments")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(previews.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { SubjectRowSeparator() }
                            StudioOverviewCommentRow(item: item, now: now) {
                                onSelectSection(.comments)
                            }
                        }
                    }
                    .subjectPanel()
                }
            }
        }
    }

    // MARK: - Stats glance (signed in)

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Stats",
                subtitle: "All Years",
                actionTitle: "Open",
                actionAccessibilityLabel: "Open Stats"
            ) {
                onSelectSection(.stats)
            }

            if let stats, !stats.isEmpty {
                Button { onSelectSection(.stats) } label: {
                    StudioStatsGlanceGrid(stats: stats)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(statsAccessibilityLabel(stats))
                .accessibilityHint("Opens the Stats section")
            } else if isLoadingStats {
                HStack(spacing: 10) {
                    ProgressView().accentFill()
                    Text("Loading stats…")
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .subjectPanel()
            } else if let statsError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(statsError)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                    Button("Try Again", action: onRetryStats)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.accentInk)
                        .buttonStyle(.plain)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .subjectPanel()
            } else {
                Button { onSelectSection(.stats) } label: {
                    Text("AO3 has no posted-work statistics yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondaryInk)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .subjectPanel()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stats, no posted-work statistics yet. Open Stats")
            }
        }
    }

    private func statsAccessibilityLabel(_ stats: AO3UserStats) -> String {
        var parts = ["Stats, All Years"]
        if let kudos = stats.kudos { parts.append("\(kudos.formatted()) Kudos") }
        if let hits = stats.hits { parts.append("\(hits.formatted()) Hits") }
        if let bookmarks = stats.bookmarks { parts.append("\(bookmarks.formatted()) Bookmarks") }
        return parts.joined(separator: ", ")
    }
}

private extension StudioOverviewView {
    // MARK: - Recent documents strip

    var recentEntries: [StudioRecentEntry] {
        var entries: [StudioRecentEntry] = []
        var seenAO3IDs = Set<Int>()

        for doc in localDocuments {
            if let ao3ID = doc.ao3WorkID { seenAO3IDs.insert(ao3ID) }
            let title = doc.totalChapters > 1
                ? "\(doc.displayWorkTitle) · Ch. \(doc.chapterNumber)"
                : doc.displayWorkTitle
            entries.append(StudioRecentEntry(
                id: "local:\(doc.workID.uuidString)",
                title: title,
                subtitle: doc.totalWordCount > 0 ? "\(doc.totalWordCount.formatted()) words" : "Draft",
                wordCount: doc.totalWordCount,
                editedAt: doc.updatedAt,
                editedFallback: nil,
                lineWidths: StudioRecentEntry.lineWidths(forWordCount: doc.totalWordCount),
                action: .local(doc.target)
            ))
        }

        if auth.isLoggedIn {
            for draft in drafts?.page.works.prefix(5) ?? [] where !seenAO3IDs.contains(draft.id) {
                seenAO3IDs.insert(draft.id)
                entries.append(StudioRecentEntry(
                    id: "draft:\(draft.id)",
                    title: draft.title.isEmpty ? "Untitled" : draft.title,
                    subtitle: draft.words.map { "\($0.formatted()) words" } ?? "AO3 draft",
                    wordCount: draft.words,
                    editedAt: WorkStat.date(from: draft.dateUpdated),
                    editedFallback: draft.dateUpdated.isEmpty ? nil : draft.dateUpdated,
                    lineWidths: StudioRecentEntry.lineWidths(forWordCount: draft.words),
                    action: .ao3Draft(draft.id)
                ))
            }
            for work in recentPostedWorks.prefix(5) where !seenAO3IDs.contains(work.id) {
                seenAO3IDs.insert(work.id)
                entries.append(StudioRecentEntry(
                    id: "work:\(work.id)",
                    title: work.title.isEmpty ? "Untitled" : work.title,
                    subtitle: work.words.map { "\($0.formatted()) words" } ?? "Posted",
                    wordCount: work.words,
                    editedAt: WorkStat.date(from: work.dateUpdated),
                    editedFallback: work.dateUpdated.isEmpty ? nil : work.dateUpdated,
                    lineWidths: StudioRecentEntry.lineWidths(forWordCount: work.words),
                    action: .ao3Work(work)
                ))
            }
        }

        return Array(
            entries
                .sorted { ($0.editedAt ?? .distantPast) > ($1.editedAt ?? .distantPast) }
                .prefix(8)
        )
    }

    var recentDocumentsSection: some View {
        let entries = recentEntries
        let title = auth.isLoggedIn ? "Recent" : "Documents"
        let subtitle = auth.isLoggedIn ? nil : (entries.isEmpty ? nil : "\(entries.count)")
        let actionTitle = auth.isLoggedIn ? "All Documents" : "All"

        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: title,
                subtitle: subtitle,
                actionTitle: actionTitle,
                actionAccessibilityLabel: "Open all documents"
            ) {
                onSelectSection(.documents)
            }
            .padding(.horizontal, gutter)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(entries) { entry in
                        StudioRecentPaperCard(entry: entry) {
                            switch entry.action {
                            case let .local(target): onOpenLocalDocument(target)
                            case let .ao3Draft(workID): onOpenAO3Draft(workID)
                            case let .ao3Work(work): onOpenAO3Work(work)
                            }
                        }
                    }

                    StudioNewDocumentPaperTile(action: onStartNewDocument)
                }
                .padding(.horizontal, gutter)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Manage links (signed in, per Studio-Overview & Studio-Coverage)

    var draftsCountText: String? {
        if let page = drafts?.page {
            if let total = page.summary?.total { return total.formatted() }
            if page.totalPages == 1 { return page.works.count.formatted() }
        }
        return cachedCount(.drafts)
    }

    var manageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Manage",
                subtitle: nil,
                actionTitle: nil,
                actionAccessibilityLabel: nil,
                action: nil
            )

            VStack(spacing: 0) {
                manageRow(
                    title: "Requests",
                    systemImage: "tray.and.arrow.down",
                    count: nil,
                    action: onOpenRequests
                )
                SubjectRowSeparator()
                manageRow(
                    title: "Your Works",
                    systemImage: "books.vertical",
                    count: cachedCount(.myWorks),
                    action: onOpenYourWorks
                )
                SubjectRowSeparator()
                manageRow(
                    title: "AO3 Drafts",
                    systemImage: "doc.badge.clock",
                    count: draftsCountText,
                    action: onOpenAO3Drafts
                )
                SubjectRowSeparator()
                manageRow(
                    title: "Series",
                    systemImage: "square.stack.3d.up",
                    count: cachedCount(.series),
                    action: onOpenSeries
                )
                SubjectRowSeparator()
                manageRow(
                    title: "Collections & Challenges",
                    systemImage: "person.3.sequence",
                    count: cachedCount(.collections),
                    action: onOpenCollections
                )
                SubjectRowSeparator()
                manageRow(
                    title: "Gifts",
                    systemImage: "gift",
                    count: nil,
                    action: onOpenGifts
                )
                SubjectRowSeparator()
                manageRow(
                    title: "Import a Work from a URL",
                    systemImage: "square.and.arrow.down",
                    count: nil,
                    action: onOpenImport
                )
            }
            .subjectPanel()
        }
    }

    func manageRow(
        title: String,
        systemImage: String,
        count: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            AccountNavCardLabel(title: title, systemImage: systemImage, count: count)
                .padding(.horizontal, 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
    }

    // MARK: - Signed-out share prompt (Studio-Offline)

    var signedOutShareCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ready to share it?")
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Text(
                "Sign in to AO3 to post your documents, save AO3 drafts, answer comments "
                    + "and follow your stats. Writing, editing and goals work without an account."
            )
            .font(.subheadline)
            .foregroundStyle(.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)

            Button("Sign In to AO3", action: onSignIn)
                .buttonStyle(.kudosSecondary)
                .accessibilityLabel("Sign In to AO3")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .subjectPanel()
    }

    @ViewBuilder
    func sectionHeader(
        title: String,
        subtitle: String?,
        actionTitle: String?,
        actionAccessibilityLabel: String?,
        action: (() -> Void)?
    ) -> some View {
        let heading = HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondaryInk)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            }
        }

        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                heading
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.body)
                        .foregroundStyle(.accentInk)
                        .buttonStyle(.plain)
                        .accessibilityLabel(actionAccessibilityLabel ?? actionTitle)
                }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                heading
                Spacer(minLength: 8)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.body)
                        .foregroundStyle(.accentInk)
                        .buttonStyle(.plain)
                        .accessibilityLabel(actionAccessibilityLabel ?? actionTitle)
                }
            }
        }
    }
}
