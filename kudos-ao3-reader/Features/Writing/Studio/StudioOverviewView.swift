import SwiftUI

/// Writing Studio › Overview (`Studio-Overview.dc.html` and `Studio-Offline.dc.html`).
///
/// Renders device-local writing progress (Today ring, goal, streak, 7-day strip), Continue
/// writing card, signed-in Comments and Stats glances, Recent documents strip, and either
/// Manage links (signed in) or the "Ready to share it?" prompt (signed out).
///
/// Challenge assignments are intentionally omitted: `AO3Client+Challenges` only exposes
/// collection-maintainer assignment endpoints, not a user's personal assignments due list.
/// Pure copy helpers for `StudioOverviewView` (`Studio-Overview`, `Studio-Offline`).
nonisolated enum StudioOverviewCopy {
    static func commentsSubtitle(awaitingReplyCount: Int, unreadCount: Int?) -> String {
        if awaitingReplyCount > 0 {
            return awaitingReplyCount == 1
                ? "1 needs a reply"
                : "\(awaitingReplyCount.formatted()) need a reply"
        }
        if let unreadCount, unreadCount > 0 {
            return "\(unreadCount.formatted()) unread"
        }
        return "All caught up"
    }

    static func statsSubtitle(
        baselineDate: Date?,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        guard let baselineDate else { return "All Years" }
        let short = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
            .locale(locale)
            .month(.abbreviated)
            .day()
            .format(baselineDate)
        return "since \(short)"
    }

    static func statsGlanceValue(total: Int, change: Int?) -> String {
        guard let change else { return total.formatted() }
        if change == 0 { return "0" }
        return change.formatted(.number.sign(strategy: .always()))
    }

    /// Recent-strip meta. `editedFallback` is the GMT calendar date for an AO3
    /// `dateUpdated` (`WorkStat.date` is midnight GMT, so a local `shortDate`
    /// of that instant is the previous evening west of UTC). A nil fallback is
    /// a real local timestamp and can say `yesterday`.
    static func recentMetaLine(
        subtitle: String,
        editedAt: Date?,
        editedFallback: String?,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let fallback = editedFallback?.trimmingCharacters(in: .whitespacesAndNewlines)
        let datePart: String?
        if let fallback, !fallback.isEmpty {
            datePart = fallback
        } else if let editedAt {
            datePart = StudioDateCopy.shortDate(editedAt, now: now, calendar: calendar, locale: locale)
        } else {
            datePart = nil
        }
        guard let datePart else { return subtitle }
        if subtitle.isEmpty { return datePart }
        return "\(subtitle) · \(datePart)"
    }
}

extension StudioOverviewCopy {
    /// Comments glance for the rows on this page. The inbox heading's unread
    /// total includes gifts and news the glance does not show.
    @MainActor
    static func commentsGlanceSubtitle(items: [AO3InboxItem]) -> String {
        commentsSubtitle(
            awaitingReplyCount: StudioCommentsBoard.needsReplyCount(items),
            unreadCount: StudioCommentsBoard.unreadCount(items)
        )
    }
}

struct StudioOverviewView: View {
    let daySnapshot: StudioDayLogSnapshot
    let localDocuments: [StudioLocalDocumentSummary]
    let drafts: AO3DraftsPage?
    let isLoadingDrafts: Bool
    let draftsError: String?
    let stats: AO3UserStats?
    let statsHistory: [StudioStatsSnapshot]
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
    let onOpenSeries: () -> Void
    let onOpenCollections: () -> Void
    let onOpenGifts: () -> Void
    let onRetryDrafts: () -> Void
    let onRetryStats: () -> Void
    let onSignIn: () -> Void
    let onRefresh: () async -> Void

    @Environment(AO3AuthService.self) private var auth
    @Environment(AO3InboxModel.self) private var inboxModel
    @Environment(ThemeManager.self) private var theme
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
        let awaiting = StudioCommentsBoard.comments(inboxModel.items, chip: .needsReply)
        if !awaiting.isEmpty { return awaiting }
        return inboxModel.items.filter { StudioCommentsBoard.isOnYourWork($0) && $0.isUnread }
    }

    private var commentsSubtitle: String? {
        switch inboxModel.phase {
        case .idle, .loading, .failed:
            return nil
        case .loaded, .paginationFailed:
            return StudioOverviewCopy.commentsGlanceSubtitle(items: inboxModel.items)
        }
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
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
                            if index > 0 { SubjectRowSeparator(inset: 0) }
                            StudioOverviewCommentRow(item: item, now: now) {
                                onSelectSection(.comments)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Stats glance (signed in)

    private var allYearsHistory: [StudioStatsSnapshot] {
        StudioStatsHistory.snapshots(statsHistory, year: nil)
    }

    private var statsBaseline: StudioStatsSnapshot? {
        StudioStatsHistory.baseline(allYearsHistory, now: now)
    }

    private var statsSection: some View {
        let baseline = statsBaseline
        let subtitle = StudioOverviewCopy.statsSubtitle(baselineDate: baseline?.date)
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Stats",
                subtitle: subtitle,
                actionTitle: "Open",
                actionAccessibilityLabel: "Open Stats"
            ) {
                onSelectSection(.stats)
            }

            if let stats, !stats.isEmpty {
                let kudosSparkline = StudioStatsHistory.sparkline(
                    allYearsHistory, metric: .kudos, points: 7
                )
                let hitsSparkline = StudioStatsHistory.sparkline(
                    allYearsHistory, metric: .hits, points: 7
                )
                Button { onSelectSection(.stats) } label: {
                    StudioStatsGlanceGrid(
                        stats: stats,
                        baseline: baseline,
                        kudosSparkline: kudosSparkline,
                        hitsSparkline: hitsSparkline
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(statsAccessibilityLabel(stats, baseline: baseline, subtitle: subtitle))
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

    private func statsAccessibilityLabel(
        _ stats: AO3UserStats,
        baseline: StudioStatsSnapshot?,
        subtitle: String
    ) -> String {
        var parts = ["Stats, \(subtitle)"]
        if let kudos = stats.kudos {
            let change = StudioStatsHistory.change(kudos, since: baseline?.total(.kudos))
            parts.append("\(StudioOverviewCopy.statsGlanceValue(total: kudos, change: change)) Kudos")
        }
        if let hits = stats.hits {
            let change = StudioStatsHistory.change(hits, since: baseline?.total(.hits))
            parts.append("\(StudioOverviewCopy.statsGlanceValue(total: hits, change: change)) Hits")
        }
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
                subtitle: doc.totalWordCount > 0 ? StudioWorkItem.wordCountLabel(doc.totalWordCount) : "Draft",
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
                let draftDate = draft.dateUpdated.isEmpty
                    ? nil
                    : StudioDateCopy.shortAO3Date(draft.dateUpdated, now: now)
                entries.append(StudioRecentEntry(
                    id: "draft:\(draft.id)",
                    title: draft.title.isEmpty ? "Untitled" : draft.title,
                    subtitle: draft.words.map(StudioWorkItem.wordCountLabel) ?? "AO3 draft",
                    wordCount: draft.words,
                    editedAt: WorkStat.date(from: draft.dateUpdated),
                    editedFallback: draftDate,
                    lineWidths: StudioRecentEntry.lineWidths(forWordCount: draft.words),
                    action: .ao3Draft(draft.id)
                ))
            }
            for work in recentPostedWorks.prefix(5) where !seenAO3IDs.contains(work.id) {
                seenAO3IDs.insert(work.id)
                let workDate = work.dateUpdated.isEmpty
                    ? nil
                    : StudioDateCopy.shortAO3Date(work.dateUpdated, now: now)
                entries.append(StudioRecentEntry(
                    id: "work:\(work.id)",
                    title: work.title.isEmpty ? "Untitled" : work.title,
                    subtitle: work.words.map(StudioWorkItem.wordCountLabel) ?? "Posted",
                    wordCount: work.words,
                    editedAt: WorkStat.date(from: work.dateUpdated),
                    editedFallback: workDate,
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
        let showsNewTile = !auth.isLoggedIn || entries.isEmpty

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
                        StudioRecentPaperCard(entry: entry, now: now) {
                            switch entry.action {
                            case let .local(target): onOpenLocalDocument(target)
                            case let .ao3Draft(workID): onOpenAO3Draft(workID)
                            case let .ao3Work(work): onOpenAO3Work(work)
                            }
                        }
                    }

                    if showsNewTile {
                        StudioNewDocumentPaperTile(action: onStartNewDocument)
                    }
                }
                .padding(.horizontal, gutter)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Manage links (signed in, per Studio-Overview)

    var manageSection: some View {
        VStack(spacing: 0) {
            manageRow(
                title: "Requests",
                systemImage: "envelope",
                count: nil,
                action: onOpenRequests
            )
            SubjectRowSeparator(inset: 36)
            manageRow(
                title: "Series",
                systemImage: "list.bullet",
                count: cachedCount(.series),
                action: onOpenSeries
            )
            SubjectRowSeparator(inset: 36)
            manageRow(
                title: "Collections & Challenges",
                systemImage: "square.stack",
                count: cachedCount(.collections),
                action: onOpenCollections
            )
            SubjectRowSeparator(inset: 36)
            manageRow(
                title: "Gifts",
                systemImage: "gift",
                count: nil,
                action: onOpenGifts
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Manage")
    }

    func manageRow(
        title: String,
        systemImage: String,
        count: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.regular))
                    .foregroundStyle(.accentInk)
                    .frame(width: 22, alignment: .center)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let count {
                    Text(count)
                        .font(.body)
                        .monospacedDigit()
                        .foregroundStyle(.secondaryInk)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
    }

    // MARK: - Signed-out share prompt (Studio-Offline)

    var signedOutShareCard: some View {
        let buttonShape = SubjectMetrics.controlShape(dynamicTypeSize)
        return VStack(alignment: .leading, spacing: 10) {
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

            Button(action: onSignIn) {
                Text("Sign In to AO3")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.accentInk)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(minHeight: 40)
                    .background(StudioTonePalette.softAccentFill(for: theme), in: buttonShape)
                    .contentShape(buttonShape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sign In to AO3")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .subjectPanel(cornerRadius: 18, isFilled: false)
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
