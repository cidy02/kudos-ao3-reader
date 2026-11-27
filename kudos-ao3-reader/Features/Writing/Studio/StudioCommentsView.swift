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
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }) private var localWorks: [SavedWork]

    @State private var model = StudioCommentsModel()
    @State private var observedGeneration: Int?

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
        .task(id: auth.sessionGeneration) {
            if observedGeneration != auth.sessionGeneration {
                if observedGeneration != nil {
                    model.resetForAccountChange()
                }
                observedGeneration = auth.sessionGeneration
            }
            inbox.activate(auth: auth)
        }
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
        let count = model.needsReplyCount(in: inbox.items)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                chipRow(count: count)
                if inbox.isShowingStaleCache {
                    Label("Showing saved comments from this iPhone", systemImage: "wifi.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondaryInk)
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
                }
                inboxLink
            }
            .padding(.horizontal, SubjectMetrics.gutter)
            .padding(.vertical, 8)
        }
        .refreshable { await inbox.refresh(auth: auth) }
        .subjectScreenSurface(.content, palette: theme.scopePalette)
    }

    /// The row stacks once the chips no longer fit. A horizontal scroller would
    /// leave Needs Reply's count off-screen at the largest text sizes.
    private func chipRow(count: Int) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips(count: count) }
            VStack(alignment: .leading, spacing: 8) { chips(count: count) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show comments")
    }

    private func chips(count: Int) -> some View {
        ForEach(StudioCommentsChip.allCases) { chip in
            StudioCommentsChipButton(
                chip: chip,
                count: chip == .needsReply ? count : nil,
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
            workList
        } else if model.visibleComments(in: inbox.items).isEmpty {
            Text(emptyMessage)
                .font(.body)
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 10) {
                ForEach(model.visibleComments(in: inbox.items)) { item in
                    commentLink(item, showsWork: true)
                }
            }
        }
    }

    @ViewBuilder
    private var workList: some View {
        let groups = model.workGroups(in: inbox.items)
        if groups.isEmpty {
            Text(emptyMessage)
                .font(.body)
                .foregroundStyle(.secondaryInk)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        workHeading(group)
                        ForEach(group.comments) { item in
                            commentLink(item, showsWork: false)
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

    private func commentLink(_ item: AO3InboxItem, showsWork: Bool) -> some View {
        NavigationLink(value: StudioCommentsRoute.thread(item.id)) {
            StudioCommentCard(item: item, showsWork: showsWork)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StudioCommentCard.summary(item))
        .accessibilityHint("Shows the thread and a reply box")
    }

    private var inboxLink: some View {
        NavigationLink(value: StudioCommentsRoute.inbox) {
            HStack(spacing: 6) {
                Text("Everything else in your AO3 Inbox")
                    .font(.body.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(theme.accentInk)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens your AO3 Inbox")
    }

    /// Needs Reply's empty list is the only one that means "nothing to answer".
    /// All and By Work share the broader empty line.
    private var emptyMessage: String {
        model.chip == .needsReply
            ? "No comments waiting for a reply."
            : "No comments on your works on this page."
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
        Button(action: action) {
            HStack(spacing: 5) {
                Text(chip.title)
                if let count {
                    Text(count.formatted())
                        .accessibilityHidden(true)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isOn ? ThemeManager.label(on: theme.effectiveTint) : Color.primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(
                isOn ? theme.effectiveTint : Color(.tertiarySystemFill),
                in: SubjectMetrics.controlShape(dynamicTypeSize)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "Selected" : "Not selected")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var label: String {
        guard let count, chip == .needsReply else { return chip.title }
        if pageNote { return "Needs Reply, \(count.formatted()) on this page" }
        return "Needs Reply, \(count.formatted())"
    }
}

/// Who, which work and chapter, when, and the comment text.
struct StudioCommentCard: View {
    let item: AO3InboxItem
    let showsWork: Bool

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !item.excerpt.isEmpty {
                Text(item.excerpt)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .subjectPanel()
        .accessibilityElement(children: .ignore)
    }

    /// Name and chapter share a line until accessibility sizes, where that line
    /// clips the chapter. Stack them so both stay visible.
    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            initial
            VStack(alignment: .leading, spacing: 2) {
                Text(item.commenterName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                Text(meta)
                    .font(.subheadline)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if item.isUnread {
                Circle()
                    .fill(theme.effectiveTint)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                    .accessibilityHidden(true)
            }
        }
    }

    private var initial: some View {
        let letter = item.commenterName.first.map { String($0).uppercased() } ?? "?"
        return Text(letter)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ThemeManager.label(on: theme.effectiveTint))
            .frame(width: 32, height: 32)
            .background(theme.effectiveTint, in: Circle())
            .accessibilityHidden(true)
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
