import SwiftData
import SwiftUI

/// Writing Studio's Comments section: inbox comments on your works.
///
/// Sits in the shell's `NavigationStack`. Signed out, the shell draws its own
/// panel; this view stays quiet and does not touch the network.
struct StudioCommentsView: View {
    @Environment(AO3AuthService.self) private var auth
    @Environment(AO3InboxModel.self) private var inbox
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }) private var localWorks: [SavedWork]

    @State private var model = StudioCommentsModel()
    @State private var observedActivationKey: String?

    init() {}

    var body: some View {
        Group {
            if auth.isLoggedIn {
                comments
            } else {
                signedOut
            }
        }
        .navigationDestination(for: StudioCommentsRoute.self) { route in
            switch route {
            case .thread(let id):
                StudioCommentsThreadView(commentID: id, model: model)
            case .inbox:
                StudioCommentsInboxPage(workContext: workContext(for:))
            }
        }
        .task(id: activationKey) {
            if observedActivationKey != activationKey {
                if observedActivationKey != nil {
                    model.resetForAccountChange()
                }
                observedActivationKey = activationKey
            }
            inbox.activate(auth: auth)
        }
        .onChange(of: inbox.metadataRevision) { _, _ in
            if !inbox.isShowingStaleCache {
                model.reconcile(with: inbox.items)
            }
        }
    }

    private var activationKey: String {
        "\(auth.sessionGeneration)|\(auth.isLoggedIn)|\(auth.username ?? "")"
    }

    private var signedOut: some View {
        ContentUnavailableView {
            Label("Not signed in", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Sign in to AO3 to see comments on your works.")
        }
        .accessibilityElement(children: .combine)
    }

    private var comments: some View {
        let needsReplyCount = model.needsReplyCount(in: inbox.items)
        let unreadCount = model.unreadCount(in: inbox.items)
        let allCount = model.allWorkCommentsCount(in: inbox.items)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    chipRow(needsReply: needsReplyCount, unread: unreadCount, all: allCount)
                    if let pageNote = StudioCommentsBoard.pageNote(
                        currentPage: inbox.currentPage, totalPages: inbox.totalPages
                    ) {
                        Text(pageNote)
                            .font(.footnote)
                            .foregroundStyle(.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let filterNotice = StudioCommentsBoard.activeInboxFilterNotice(
                        in: inbox.currentFilterValues
                    ) {
                        inboxFilterBanner(filterNotice)
                    }
                }
                if inbox.isShowingStaleCache {
                    Label("Showing saved comments from this \(ThisDevice.name)", systemImage: "wifi.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                feed()
                if let failure, !inbox.items.isEmpty {
                    Text(failure)
                        .font(.subheadline)
                        .foregroundStyle(theme.appTheme.errorColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if inbox.totalPages > 1 {
                    SearchPaginationBar(
                        currentPage: inbox.currentPage,
                        totalPages: inbox.totalPages,
                        isLoading: isLoadingPage,
                        palette: theme.scopePalette
                    ) { page in
                        inbox.goToPage(page, auth: auth)
                    }
                    .disabled(isWriteInFlight)
                }
                inboxLink
            }
            .padding(.horizontal, SubjectMetrics.gutter)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .refreshable { await inbox.refresh(auth: auth) }
        .subjectScreenSurface(.content, palette: theme.scopePalette)
    }

    private func inboxFilterBanner(_ notice: String) -> some View {
        let canReset = AO3InboxPill.available(in: inbox.filterForm).contains(.all)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                if canReset {
                    showAllInboxButton
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                if canReset {
                    showAllInboxButton
                }
            }
        }
    }

    private var showAllInboxButton: some View {
        Button("Show All") {
            inbox.applyFilters(AO3InboxPill.all.values, auth: auth)
        }
        .buttonStyle(.plain)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(theme.accentInk)
        .disabled(isWriteInFlight)
        .accessibilityLabel("Show all AO3 Inbox comments")
    }

    /// Horizontal chip rail at regular sizes; stacks vertically at accessibility sizes
    /// so Needs Reply's count never scrolls off-screen at AX5.
    @ViewBuilder
    private func chipRow(needsReply: Int, unread: Int, all: Int) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    chips(needsReply: needsReply, unread: unread, all: all)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chips(needsReply: needsReply, unread: unread, all: all)
                    }
                }
                .horizontalScrollViewport()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show comments")
    }

    private func chips(needsReply: Int, unread: Int, all: Int) -> some View {
        ForEach(StudioCommentsChip.allCases) { chip in
            let chipCount: Int? = switch chip {
            case .needsReply: needsReply
            case .unread: unread
            case .all: all
            case .byWork: nil
            }
            StudioCommentsChipButton(
                chip: chip,
                count: chipCount,
                pageNote: inbox.totalPages > 1,
                isOn: model.chip == chip
            ) {
                model.chip = chip
            }
        }
    }

    @ViewBuilder
    private func feed() -> some View {
        if showsLoading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityLabel("Loading comments")
        } else if let failure, inbox.items.isEmpty {
            ContentUnavailableView {
                Label("Couldn't load comments", systemImage: "bubble.left")
            } description: {
                Text(failure)
            } actions: {
                Button("Try Again") { inbox.retry(auth: auth) }
                    .buttonStyle(.kudosSecondary)
                    .accessibilityLabel("Try Again")
            }
        } else if model.chip == .byWork {
            groupedFeed(model.workGroups(in: inbox.items))
        } else if model.chip == .needsReply || model.chip == .unread {
            groupedFeed(StudioCommentsBoard.groups(model.visibleComments(in: inbox.items)))
        } else {
            let visible = model.visibleComments(in: inbox.items)
            if visible.isEmpty {
                Text(emptyMessage)
                    .font(.body)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 10) {
                    ForEach(visible) { item in
                        commentCardRow(item, showsWork: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func groupedFeed(_ groups: [StudioCommentWorkGroup]) -> some View {
        if groups.isEmpty {
            Text(emptyMessage)
                .font(.body)
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        workHeading(group)
                        ForEach(group.comments) { item in
                            commentCardRow(item, showsWork: false)
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        }
    }

    private func workHeading(_ group: StudioCommentWorkGroup) -> some View {
        let count = group.comments.count
        let spoken = count == 1 ? "1 comment" : "\(count.formatted()) comments"
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(group.title)
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(count.formatted())
                .font(.subheadline)
                .foregroundStyle(.secondaryInk)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.title), \(spoken)")
        .accessibilityAddTraits(.isHeader)
    }

    private func commentCardRow(_ item: AO3InboxItem, showsWork: Bool) -> some View {
        let cardShape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
        let border = theme.appTheme.isDarkFamily
            ? theme.appTheme.glassStroke(0.14)
            : theme.appTheme.cardBorder
        let shadowRadius: CGFloat = theme.appTheme.cardShadow.radius > 0 ? 1.5 : 0
        let shadowY: CGFloat = theme.appTheme.cardShadow.radius > 0 ? 1 : 0

        return VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: StudioCommentsRoute.thread(item.id)) {
                StudioCommentCardContent(item: item, showsWork: showsWork)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(StudioCommentCard.summary(item))
            .accessibilityHint("Shows the thread and a reply box")
            .accessibilityAddTraits(.isButton)

            commentActionRow(item)

            if model.statusCommentID == item.id, model.statusIsError, let message = model.statusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(theme.appTheme.errorColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.appTheme.cardSurface, in: cardShape)
        .overlay(cardShape.strokeBorder(border, lineWidth: 0.5))
        .shadow(color: theme.appTheme.cardShadow.color, radius: shadowRadius, y: shadowY)
    }

    private func commentActionRow(_ item: AO3InboxItem) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                replyActionPill(item)
                markReadActionPill(item)
            }
            VStack(alignment: .leading, spacing: 6) {
                replyActionPill(item)
                markReadActionPill(item)
            }
        }
    }

    private func replyActionPill(_ item: AO3InboxItem) -> some View {
        let isReply = item.canReply && !item.isReplied
        let label = isReply ? "Reply" : "Thread"
        let shape = SubjectMetrics.controlShape(dynamicTypeSize)
        return NavigationLink(value: StudioCommentsRoute.thread(item.id)) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.accentInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(minHeight: 32)
                .background(StudioTonePalette.softAccentFill(for: theme), in: shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isReply ? "Reply to \(item.commenterName)" : "View thread with \(item.commenterName)"
        )
    }

    @ViewBuilder
    private func markReadActionPill(_ item: AO3InboxItem) -> some View {
        if showsMarkRead(item) {
            let shape = SubjectMetrics.controlShape(dynamicTypeSize)
            let isBusy = isWriteInFlight
            Button {
                startMarkRead(item)
            } label: {
                Text("Mark Read")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(minHeight: 32)
                    .background(theme.appTheme.glassFill(0.10), in: shape)
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
            .opacity(isBusy ? 0.5 : 1)
            .disabled(isBusy)
            .layoutFreeHitTarget {
                guard !isBusy else { return }
                startMarkRead(item)
            }
            .accessibilityLabel("Mark comment from \(item.commenterName) read")
        }
    }

    private func showsMarkRead(_ item: AO3InboxItem) -> Bool {
        guard item.isUnread, auth.isLoggedIn, let form = inbox.bulkForm else { return false }
        return form.parameters(for: [item], action: .markRead) != nil
    }

    private func startMarkRead(_ item: AO3InboxItem) {
        guard auth.isLoggedIn, !isWriteInFlight, let form = inbox.bulkForm else { return }
        let auth = auth
        let inbox = inbox
        let model = model
        let request = StudioCommentsThreadView.MarkReadRequest(
            item: item,
            form: form,
            username: auth.username,
            cacheScope: AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth),
            generation: auth.sessionGeneration
        )
        Task {
            await StudioCommentsThreadView.performMarkRead(
                request,
                auth: auth,
                inbox: inbox,
                model: model
            )
        }
    }

    private var inboxLink: some View {
        NavigationLink(value: StudioCommentsRoute.inbox) {
            HStack(spacing: 6) {
                Text("Everything else in your AO3 Inbox")
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(theme.accentInk)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Everything else in your AO3 Inbox")
        .accessibilityHint("Opens your AO3 Inbox")
    }

    /// Needs Reply's empty list is the only one that means "nothing to answer".
    /// All and By Work share the broader empty line.
    private var emptyMessage: String {
        StudioCommentsBoard.emptyMessage(chip: model.chip, totalPages: inbox.totalPages)
    }

    private var isWriteInFlight: Bool {
        inbox.isPerformingBulkAction
            || model.postingID != nil
            || model.markingReadID != nil
            || model.submissionPhase.isBusy
    }

    private var showsLoading: Bool {
        inbox.items.isEmpty && (inbox.phase == .idle || inbox.phase == .loading)
    }

    private var isLoadingPage: Bool {
        if case .loading = inbox.phase { return true }
        return false
    }

    private var failure: String? {
        if case .failed(let message) = inbox.phase { return message }
        if case .paginationFailed(_, let message) = inbox.phase { return message }
        return nil
    }

    private func workContext(for item: AO3InboxItem) -> AO3CommentsWorkContext {
        guard let workID = item.workID else {
            return AO3CommentsWorkContext(title: item.workTitle, authors: [])
        }
        if let cached = inbox.workContext(for: workID) { return cached }
        if let saved = localWorks.first(where: { $0.ao3WorkID == workID }) {
            return AO3CommentsWorkContext(savedWork: saved)
        }
        return AO3CommentsWorkContext(title: item.workTitle, authors: [])
    }
}

/// One filter chip. The count is part of the control's name, not a second element.
private struct StudioCommentsChipButton: View {
    let chip: StudioCommentsChip
    let count: Int?
    let pageNote: Bool
    let isOn: Bool
    let action: () -> Void

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let shape = SubjectMetrics.controlShape(dynamicTypeSize)
        return Button(action: action) {
            HStack(spacing: 5) {
                Text(chip.title)
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                if let count {
                    Text(count.formatted())
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .opacity(0.85)
                        .accessibilityHidden(true)
                }
            }
            .font(.subheadline)
            .foregroundStyle(isOn ? ThemeManager.label(on: theme.effectiveTint) : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
            .background {
                if isOn {
                    shape.fill(theme.effectiveTint)
                } else {
                    shape
                        .fill(theme.appTheme.glassFill(0.09))
                        .overlay(shape.strokeBorder(theme.appTheme.glassStroke(0.13), lineWidth: 0.5))
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .layoutFreeHitTarget(action: action)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "Selected" : "Not selected")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var label: String {
        guard let count else { return chip.title }
        if pageNote { return "\(chip.title), \(count.formatted()) on this page" }
        return "\(chip.title), \(count.formatted())"
    }
}

/// Who, which work and chapter, when, and the comment text (white bordered card matching `Studio-Comments`).
struct StudioCommentCard: View {
    let item: AO3InboxItem
    let showsWork: Bool

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        let cardShape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
        let border = theme.appTheme.isDarkFamily
            ? theme.appTheme.glassStroke(0.14)
            : theme.appTheme.cardBorder
        let shadowRadius: CGFloat = theme.appTheme.cardShadow.radius > 0 ? 1.5 : 0
        let shadowY: CGFloat = theme.appTheme.cardShadow.radius > 0 ? 1 : 0

        StudioCommentCardContent(item: item, showsWork: showsWork)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.appTheme.cardSurface, in: cardShape)
            .overlay(cardShape.strokeBorder(border, lineWidth: 0.5))
            .shadow(color: theme.appTheme.cardShadow.color, radius: shadowRadius, y: shadowY)
            .accessibilityElement(children: .ignore)
    }

    static func summary(_ item: AO3InboxItem) -> String {
        var parts: [String] = []
        if item.isUnread { parts.append("Unread") }
        parts.append(item.commenterName)
        let title = item.workTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { parts.append(title) }
        if let chapter = item.chapterIndicatorTitle { parts.append(chapter) }
        if let when = AO3InboxTimeLabel.label(for: item.postedAgo) {
            parts.append(when.spoken)
        } else if !item.postedAgo.isEmpty {
            parts.append(item.postedAgo)
        }
        if !item.excerpt.isEmpty { parts.append(item.excerpt) }
        if item.isReplied { parts.append("Replied") }
        return parts.joined(separator: ". ")
    }
}

/// Inner comment header and body shared by feed cards and `StudioCommentCard`.
struct StudioCommentCardContent: View {
    let item: AO3InboxItem
    let showsWork: Bool

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !item.excerpt.isEmpty {
                Text(item.excerpt)
                    .font(.subheadline)
                    .lineSpacing(2)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Name and chapter share a line until accessibility sizes, where that line
    /// clips the chapter. Stack them so both stay visible.
    private var header: some View {
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 10) {
            AO3AuthorAvatar(
                url: item.avatarURL,
                name: item.commenterName,
                size: 32,
                isCircular: true
            )
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.commenterName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !meta.isEmpty {
                        Text(meta)
                            .font(.subheadline)
                            .foregroundStyle(.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let nameText = Text(item.commenterName)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.primary)
                let metaText = meta.isEmpty
                    ? Text("")
                    : Text(" · \(meta)").foregroundStyle(.secondaryInk)
                Text("\(nameText)\(metaText)")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if item.isUnread {
                Circle()
                    .fill(theme.accentInk)
                    .frame(width: 8, height: 8)
                    .padding(.top, dynamicTypeSize.isAccessibilitySize ? 6 : 0)
                    .accessibilityHidden(true)
            }
        }
    }

    private var meta: String {
        var parts: [String] = []
        if showsWork {
            let title = item.workTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { parts.append(title) }
        }
        if let chapter = item.chapterIndicatorTitle { parts.append(chapter) }
        if let when = AO3InboxTimeLabel.label(for: item.postedAgo) {
            parts.append(when.display)
        } else if !item.postedAgo.isEmpty {
            parts.append(item.postedAgo)
        }
        if item.isReplied { parts.append("Replied") }
        return parts.joined(separator: " · ")
    }
}
