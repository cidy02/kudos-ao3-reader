import SwiftData
import SwiftUI

/// Board `Subscriptions-Tags`: local followed tags tab shared by
/// `SubscriptionsView` (`.tags`) and `AO3SubscriptionsWorksBrowser` (`.tags`).
///
/// Works offline and when signed out; never sends a `?type=tags` request to AO3.
struct FollowedTagsListView: View {
    var palette: SubjectPalette?
    var showsStandaloneHeader: Bool = true
    var onRefresh: (() async -> Void)?
    var topRail: AnyView?

    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme
    @Environment(FollowedTagUpdateStore.self) private var updateStore

    @Query(sort: \FollowedTag.followedAt, order: .reverse)
    private var followedTags: [FollowedTag]

    @State private var editingTag: FollowedTag?
    @State private var pendingUnfollow: FollowedTag?

    @ScaledMetric(relativeTo: .headline) private var rowTitleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .footnote) private var rowSubtitleSize: CGFloat = 12.5

    private var activePalette: SubjectPalette {
        palette ?? theme.scopePalette
    }

    private var latestCheckDate: Date? {
        followedTags.compactMap(\.lastCheckedAt).max()
    }

    private var isAtLimit: Bool {
        followedTags.count >= FollowedTag.maxFollowedCount
    }

    var body: some View {
        List {
            if let topRail {
                Section {
                    if !followedTags.isEmpty {
                        SubjectPageFact(summaryLine, gutter: SubjectMetrics.accountGutter)
                            .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    topRail
                        .listRowInsets(
                            EdgeInsets(top: followedTags.isEmpty ? 12 : 4, leading: 0, bottom: 8, trailing: 0)
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else if showsStandaloneHeader {
                Section {
                    headerCard
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }

            if followedTags.isEmpty {
                Section {
                    emptyView
                        .bareListRow()
                }
            } else {
                if isAtLimit {
                    Section {
                        capNoticeBanner
                            .cardRow()
                    }
                }
                Section {
                    ForEach(followedTags) { tag in
                        tagRow(tag)
                    }
                }
                Section {
                    discoveryHint
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .cardList()
        .appThemedRows()
        .appThemedScroll()
        .refreshable {
            await onRefresh?()
        }
        .subjectScreenWash(palette: activePalette, role: .content)
        .sheet(item: $editingTag) { tag in
            FollowTagSheet(
                ao3TagID: tag.ao3TagID,
                tagName: tag.name,
                tagCategoryRaw: tag.tagCategoryRaw,
                tagURLString: tag.tagURLString,
                existingTag: tag
            )
        }
        .destructiveConfirmation(
            for: $pendingUnfollow,
            title: "Unfollow tag?",
            confirmLabel: "Unfollow",
            message: { tag in
                "Kudos will stop checking “\(tag.name)” and clear its unread tag updates."
            },
            perform: { tag in
                FollowedTagStore.unfollow(tag, in: context, updateStore: updateStore)
            }
        )
    }

    private var summaryLine: String {
        var parts = ["\(followedTags.count) of \(FollowedTag.maxFollowedCount) tags"]
        if let latestCheckDate {
            parts.append("Checked \(latestCheckDate.formatted(.relative(presentation: .named)))")
        }
        if isAtLimit {
            parts.append("Limit reached")
        }
        return parts.joined(separator: " · ")
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(followedTags.count) followed")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Text("of \(FollowedTag.maxFollowedCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondaryInk)
                Spacer(minLength: 0)
            }
            if let latestCheckDate {
                Text("Last checked \(latestCheckDate.formatted(.relative(presentation: .named)))")
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
            } else if !followedTags.isEmpty {
                Text("Checked at most every 6 hours while Home or Subscriptions is open")
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var capNoticeBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tag limit reached (\(FollowedTag.maxFollowedCount) of \(FollowedTag.maxFollowedCount))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text("Unfollow a tag below to follow another one.")
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No followed tags", systemImage: "tag")
        } description: {
            Text(
                "Open any fandom, character, relationship, or F/F tag on AO3 and tap Follow Tag. "
                    + "Kudos checks each tag's public Atom feed in the foreground."
            )
        }
    }

    private var discoveryHint: some View {
        Text(
            "Only Fandom, Character, Relationship, and F/F tags publish Atom feeds on AO3. "
                + "Open a tag's works page in Browse or Search to follow another."
        )
        .font(.footnote)
        .foregroundStyle(.secondaryInk)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func tagRow(_ tag: FollowedTag) -> some View {
        let unread = updateStore.unreadCount(forTagID: tag.ao3TagID)
        let worksRequest = tag.worksURL.map { AO3TagWorksRequest(url: $0, title: tag.name) }

        HStack(alignment: .center, spacing: 10) {
            if let worksRequest {
                NavigationLink(value: worksRequest) {
                    tagRowLabel(tag, unread: unread)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    updateStore.markSeen(tagID: tag.ao3TagID)
                })
                .accessibilityLabel(rowAccessibilityLabel(tag, unread: unread))
            } else {
                Button {
                    editingTag = tag
                } label: {
                    tagRowLabel(tag, unread: unread)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(rowAccessibilityLabel(tag, unread: unread))
            }

            Button {
                editingTag = tag
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.primary)
                    .frame(minWidth: 32, minHeight: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Follow settings for \(tag.name)")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingUnfollow = tag
            } label: {
                Label("Unfollow", systemImage: "bell.slash")
            }
            Button {
                editingTag = tag
            } label: {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
        }
        .contextMenu {
            Button {
                editingTag = tag
            } label: {
                Label("Follow Settings", systemImage: "slider.horizontal.3")
            }
            if unread > 0 {
                Button {
                    updateStore.markSeen(tagID: tag.ao3TagID)
                } label: {
                    Label("Mark Seen", systemImage: "checkmark.circle")
                }
            }
            Button(role: .destructive) {
                pendingUnfollow = tag
            } label: {
                Label("Unfollow", systemImage: "bell.slash")
            }
        }
        .cardRow()
    }

    @ViewBuilder
    private func tagRowLabel(_ tag: FollowedTag, unread: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    tagTitleBlock(tag)
                    if unread > 0 {
                        unreadBadge(unread)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    tagTitleBlock(tag)
                    Spacer(minLength: 4)
                    if unread > 0 {
                        unreadBadge(unread)
                    }
                }
            }

            Text(tag.settingsSummary)
                .font(.system(size: rowSubtitleSize))
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            if let checked = tag.lastCheckedAt {
                Text("Checked \(checked.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private func tagTitleBlock(_ tag: FollowedTag) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let category = tag.displayCategory {
                Text(category.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondaryInk)
            }
            Text(
                dynamicTypeSize.isAccessibilitySize
                    ? AccessibilitySoftBreak.opportunities(in: tag.name)
                    : tag.name
            )
            .font(.system(size: rowTitleSize, weight: .semibold))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func unreadBadge(_ unread: Int) -> some View {
        let label = unread >= FollowedTagFeedEvaluator.maxFeedEntries
            ? "\(unread)+ new"
            : "\(unread) new"
        return Text(label)
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(red: 0x25 / 255, green: 0x66 / 255, blue: 0x3C / 255), in: Capsule())
    }

    private func rowAccessibilityLabel(_ tag: FollowedTag, unread: Int) -> String {
        var parts = [tag.name]
        if let category = tag.displayCategory {
            parts.append(category)
        }
        if unread > 0 {
            parts.append("\(unread) new")
        }
        parts.append(tag.settingsSummary)
        return parts.joined(separator: ", ")
    }
}
