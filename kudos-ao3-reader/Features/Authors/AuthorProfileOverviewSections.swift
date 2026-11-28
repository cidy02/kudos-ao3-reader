import SwiftUI

/// Left-aligned identity header: author-colour wash lives on the screen, not
/// on these controls. Subscribe stays AO3 red (`accentFill`); Mute and Block
/// are labelled neutral pills beside it (`Author.dc.html`).
struct AuthorProfileOverviewHeader: View {
    var model: AO3AuthorProfileModel
    let isOwnProfile: Bool
    var muteAction: AO3AuthorWebAction?
    var blockAction: AO3AuthorWebAction?
    let onSubscription: () -> Void
    let onModeration: (AO3AuthorWebAction) -> Void
    let onSelectScope: (AO3AuthorRoute) -> Void
    var avatarSize: CGFloat = 72
    var topSpacing: CGFloat = 16

    @Environment(AO3AuthService.self) private var auth
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var usernameSize: CGFloat = 24

    private var showsAccountActions: Bool {
        !isOwnProfile && !model.route.isOrphanAccount
    }

    private var actionsBusy: Bool {
        model.isPerformingSubscription || model.isPerformingModeration
    }

    var body: some View {
        if let header = model.header {
            Section {
                VStack(alignment: .leading, spacing: isOwnProfile && avatarSize == 64 ? 14 : 12) {
                    identityRow(header)
                    if let about = model.about {
                        if !about.profileTitle.isEmpty {
                            Text(about.profileTitle)
                                .font(.subheadline.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let userID = about.userID {
                            LabeledContent("User ID", value: userID.formatted())
                                .font(.caption)
                                .foregroundStyle(.secondaryInk)
                        }
                        if !about.bio.isEmpty {
                            AO3RichTextView(document: about.bio, font: .subheadline, lineSpacing: 3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else if case let .failed(message) = model.contentPhase {
                        AuthorProfileOverviewFailure(
                            model: model,
                            section: .about,
                            title: "Couldn't load About",
                            message: message
                        )
                    }
                    if showsAccountActions {
                        actionRow(header)
                    }
                }
                .pageBodyRow(top: topSpacing, gutter: SubjectMetrics.accountGutter)
            }
            .onAppear { model.ensureSectionVisible(.about, auth: auth) }
        }
    }

    private func identityRow(_ header: AO3AuthorHeader) -> some View {
        HStack(alignment: .center, spacing: 14) {
            AO3AuthorAvatar(
                url: header.identity.avatarURL,
                name: model.route.displayName,
                size: avatarSize,
                isCircular: true,
                identityHue: CoverArt.hue(for: model.route.username)
            )
            VStack(alignment: .leading, spacing: 2) {
                pseudNameMenu(header)
                if let subtitle = identitySubtitle(header) {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    private func identitySubtitle(_ header: AO3AuthorHeader) -> String? {
        Self.identitySubtitle(
            about: model.about,
            pseudCount: header.pseuds.count,
            route: model.route
        )
    }

    static func identitySubtitle(
        about: AO3AuthorAbout?,
        pseudCount: Int,
        route: AO3AuthorRoute,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        var parts: [String] = []
        if let joined = about?.displayJoinedDate(locale: locale), !joined.isEmpty {
            parts.append("Joined \(joined)")
        }
        if pseudCount > 1 {
            parts.append("\(pseudCount) pseuds")
        }
        if route.pseud != nil {
            parts.append("Pseud of \(route.username)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func pseudAccessibilityValue(route: AO3AuthorRoute, pseudCount: Int) -> String {
        if let pseud = route.pseud { return pseud }
        return pseudCount > 1 ? "All \(pseudCount.formatted()) pseuds" : "All Pseuds"
    }

    @ViewBuilder
    private func pseudNameMenu(_ header: AO3AuthorHeader) -> some View {
        let showsChooser = header.pseuds.count > 1 || model.route.pseud != nil
        let name = Text(model.route.displayName)
            .font(.system(size: usernameSize, weight: .bold))
            .lineLimit(3)
            .minimumScaleFactor(0.75)
            .subjectOwnHeadingScrollEffect()
        if showsChooser {
            Menu {
                if let allPseuds = AO3AuthorRoute(username: model.route.username) {
                    Button {
                        onSelectScope(allPseuds)
                    } label: {
                        Label(
                            "All Pseuds",
                            systemImage: model.route.pseud == nil ? "checkmark" : "person.2"
                        )
                    }
                }
                ForEach(header.pseuds) { pseud in
                    Button {
                        onSelectScope(pseud.route)
                    } label: {
                        Label(
                            pseud.name,
                            systemImage: model.route == pseud.route ? "checkmark" : "person"
                        )
                    }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    // A title menu reads as the title (board 23: black name, grey chevron), not as a red link.
                    name.foregroundStyle(Color.primary)
                    // Same font as the name, so the symbol centres on its cap height.
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: usernameSize, weight: .medium))
                        .imageScale(.small)
                        .foregroundStyle(.secondaryInk)
                }
            }
            .accessibilityLabel("\(model.route.displayName). Choose a pseud")
            .accessibilityValue(Self.pseudAccessibilityValue(route: model.route, pseudCount: header.pseuds.count))
        } else {
            name.accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private func actionRow(_ header: AO3AuthorHeader) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            // At AX5 the labelled pills stack vertically so every action wraps cleanly.
            VStack(alignment: .leading, spacing: 8) {
                if let form = header.subscriptionForm {
                    subscribeButton(form, expands: true)
                }
                moderationButtons
            }
        } else {
            let hasModeration = muteAction != nil || blockAction != nil
            HStack(spacing: 8) {
                if let form = header.subscriptionForm {
                    subscribeButton(form, expands: !hasModeration)
                }
                moderationButtons
            }
        }
    }

    @ViewBuilder
    private var moderationButtons: some View {
        if let muteAction {
            moderationButton(muteAction, webKind: .mute)
        }
        if let blockAction {
            moderationButton(blockAction, webKind: .block)
        }
    }

    private func subscribeButton(_ form: AO3AuthorSubscriptionForm, expands: Bool) -> some View {
        Button(action: onSubscription) {
            HStack(spacing: 6) {
                if model.isPerformingSubscription {
                    ProgressView().controlSize(.small).accentFill()
                } else {
                    Image(systemName: form.isSubscribed ? "bell.slash" : "bell")
                }
                Text(form.isSubscribed ? "Unsubscribe" : "Subscribe")
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            }
            .fixedSize(horizontal: !expands, vertical: false)
            .frame(maxWidth: expands ? .infinity : nil)
        }
        .buttonStyle(.kudos(variant: .primary, dense: true))
        .disabled(actionsBusy)
        .accessibilityHint(
            model.route.pseud != nil
                ? "Applies to \(model.route.username)'s whole account, not only this pseud."
                : ""
        )
    }

    private func moderationButton(
        _ action: AO3AuthorWebAction,
        webKind: AO3AuthorWebAction.Kind
    ) -> some View {
        let isUndo = action.label.localizedCaseInsensitiveContains("un")
        let kind = AO3AuthorModerationKind(webAction: webKind, isUndo: isUndo)
        return Button {
            onModeration(action)
        } label: {
            HStack(spacing: 6) {
                if model.isPerformingModeration {
                    ProgressView().controlSize(.small).accentFill()
                } else {
                    Image(systemName: kind?.systemImage
                        ?? (webKind == .mute ? "speaker.slash" : "hand.raised"))
                }
                Text(action.label)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.85)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.kudos(variant: .secondary, dense: true))
        .disabled(actionsBusy)
        .accessibilityLabel(action.label)
    }
}

/// The profile tally strip shared by Author Profile and the Account sheet.
/// Callers supply destinations because Account's Subscriptions tally crosses to
/// Library while the author surface keeps all four destinations in its stack.
struct AuthorProfileCountStrip: View {
    struct Item: Identifiable {
        let id: String
        let title: String
        let countText: String?
        let action: () -> Void

        init(title: String, count: Int?, action: @escaping () -> Void) {
            id = title
            self.title = title
            countText = count?.compactCount
            self.action = action
        }

        init(title: String, countText: String?, action: @escaping () -> Void) {
            id = title
            self.title = title
            self.countText = countText
            self.action = action
        }
    }

    let items: [Item]
    var usesCardSurface = false
    var topSpacing: CGFloat = 12
    var stripAccessibilityLabel: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columns = dynamicTypeSize.isAccessibilitySize ? 2 : items.count
        Section {
            stripPanel(columns: columns)
                .pageBodyRow(top: topSpacing, gutter: SubjectMetrics.accountGutter)
        }
    }

    @ViewBuilder
    private func stripPanel(columns: Int) -> some View {
        let grid = LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: columns),
            spacing: 0
        ) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button(action: item.action) {
                    VStack(spacing: 1) {
                        Text(item.countText ?? "—")
                            .font(.title3.weight(.bold).monospacedDigit())
                        Text(item.title)
                            .font(.caption2)
                            .foregroundStyle(.secondaryInk)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(countLabel(item))
                .overlay(alignment: .leading) {
                    // An explicit vertical hairline: a bare Divider outside an
                    // HStack draws horizontally, across the middle of the cell.
                    if index % columns != 0 {
                        Rectangle()
                            .fill(.separator)
                            .frame(width: 0.5)
                            .padding(.vertical, 8)
                    }
                }
                .overlay(alignment: .top) {
                    if columns == 2, index >= columns {
                        Divider()
                    }
                }
            }
        }
        let styled = Group {
            if usesCardSurface {
                grid.accountSheetPanel()
            } else {
                grid.subjectPanel()
            }
        }
        if let stripAccessibilityLabel {
            styled
                .accessibilityElement(children: .contain)
                .accessibilityLabel(stripAccessibilityLabel)
        } else {
            styled
        }
    }

    private func countLabel(_ item: Item) -> String {
        guard let count = item.countText else { return item.title }
        return "\(count) \(item.title.lowercased())"
    }
}

private struct AuthorProfileOverviewFailure: View {
    var model: AO3AuthorProfileModel
    let section: AuthorProfileOverviewSection
    let title: String
    let message: String

    @Environment(AO3AuthService.self) private var auth

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondaryInk)
            Button("Retry") { model.retrySection(section, auth: auth) }
                .buttonStyle(.kudosSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .subjectPanel()
    }
}

struct AuthorProfileOverviewSections: View {
    var model: AO3AuthorProfileModel
    let onSeeAll: (AO3AuthorProfileTab) -> Void
    let onSeeAllMostKudos: () -> Void
    let onOpenFandom: (AO3AuthorFandom) -> Void

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(PrivacyGate.self) private var gate
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure
    @ScaledMetric(relativeTo: .body) private var moreCardWidth: CGFloat = 96

    var body: some View {
        if let header = model.header {
            AuthorProfileCountStrip(
                items: [
                    countItem(.works, content: .works, header: header),
                    countItem(.series, content: .series, header: header),
                    countItem(.bookmarks, content: .bookmarks, header: header),
                    countItem(.gifts, content: .gifts, header: header)
                ],
                topSpacing: 12,
                stripAccessibilityLabel: "On AO3"
            )
            fandoms(header)
        }
        latest
        mostKudos
        series
        bookmarks
    }

    static func worksCountText(_ count: Int) -> String {
        count == 1 ? "1 work" : "\(count.formatted()) works"
    }

    static func remainingCount(total: Int?, visible: Int) -> Int? {
        guard let total, total > visible else { return nil }
        return total - visible
    }

    static func moreWorksAccessibilityLabel(_ remaining: Int) -> String {
        remaining == 1 ? "1 more work" : "\(remaining.formatted()) more works"
    }

    static func moreSeriesText(_ remaining: Int) -> String {
        "\(remaining.formatted()) more"
    }

    static func fandomChipAccessibilityLabel(name: String, count: Int?) -> String {
        guard let count else { return name }
        return count == 1 ? "\(name), 1 work" : "\(name), \(count.formatted()) works"
    }

    private func countItem(
        _ tab: AO3AuthorProfileTab,
        content: AO3AuthorRoute.Content,
        header: AO3AuthorHeader
    ) -> AuthorProfileCountStrip.Item {
        AuthorProfileCountStrip.Item(
            title: tab.rawValue,
            count: header.listCount(for: content, route: model.route),
            action: { onSeeAll(tab) }
        )
    }

    @ViewBuilder
    private func fandoms(_ header: AO3AuthorHeader) -> some View {
        if !header.fandoms.isEmpty {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(header.fandoms) { fandom in
                            let bareName = FandomDisplayName.bareTitle(fandom.name)
                            Button { onOpenFandom(fandom) } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(
                                            theme.appTheme.subjectPalette(
                                                hue: CoverArt.hue(for: fandom.name)
                                            ).accent
                                        )
                                        .frame(width: 8, height: 8)
                                        .accessibilityHidden(true)
                                    Text(bareName)
                                        .font(.subheadline)
                                    if let count = fandom.workCount {
                                        Text(count.compactCount)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondaryInk)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(theme.appTheme.glassFill(0.09), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(fandom.url == nil)
                            .minimumHitTarget()
                            .accessibilityLabel(Self.fandomChipAccessibilityLabel(
                                name: bareName,
                                count: fandom.workCount
                            ))
                        }
                    }
                    .padding(.horizontal, SubjectMetrics.accountGutter)
                }
                .pageBodyRow(top: 12, gutter: 0)
            }
        }
    }

    private var latest: some View {
        Section {
            if let work = model.latestWork {
                if !gate.isHidden(work, enabled: hideMature, mode: matureMode) {
                    SectionRuleHeader(title: "Latest")
                        .pageBodyRow(top: 24, gutter: 0)
                    SensitiveRemoteWorkCard(work: work) {
                        AuthorProfileLatestCard(work: work)
                    }
                    .pageBodyRow(top: 10, gutter: SubjectMetrics.accountGutter)
                }
            } else if model.header?.recentWorks == nil {
                SectionRuleHeader(title: "Latest")
                    .pageBodyRow(top: 24, gutter: 0)
                overviewMessage("Couldn't read the latest work. Open Works to try again.")
            } else {
                SectionRuleHeader(title: "Latest")
                    .pageBodyRow(top: 24, gutter: 0)
                overviewMessage("No recent works visible on AO3.")
            }
        }
    }

    private var mostKudos: some View {
        let works = Array(model.overviewPopularWorks.prefix(AuthorProfileSeeAll.worksPreviewLimit))
        let total = model.header?.listCount(for: .works, route: model.route)
        let showSeeAll = AuthorProfileSeeAll.isShown(
            visibleCount: works.count,
            totalCount: total,
            hasMore: model.popularHasMore || (model.overviewPopularWorks.count > works.count)
        )
        let remaining = Self.remainingCount(total: total, visible: works.count)
        return Section {
            SectionRuleHeader(
                title: "Most Kudos",
                countText: total.map(Self.worksCountText),
                onSeeAll: showSeeAll ? onSeeAllMostKudos : nil
            )
            .pageBodyRow(top: 24, gutter: 0)
            Group {
                switch model.popularPhase {
                case .idle, .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .accentFill()
                case .unavailable:
                    overviewMessage("Most Kudos is unavailable.")
                case let .failed(message):
                    AuthorProfileOverviewFailure(
                        model: model,
                        section: .popular,
                        title: "Couldn't load Most Kudos",
                        message: message
                    )
                    .pageBodyRow(top: 10, gutter: SubjectMetrics.accountGutter)
                    if !works.isEmpty { popularShelf(works, remainingCount: remaining) }
                case .loaded:
                    if works.isEmpty {
                        overviewMessage("No works visible on AO3.")
                    } else {
                        popularShelf(works, remainingCount: remaining)
                    }
                }
            }
            .onAppear { model.ensureSectionVisible(.popular, auth: auth) }
        }
    }

    private func popularShelf(_ works: [AO3WorkSummary], remainingCount: Int?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(works) { work in
                    if gate.isBlurred(work, enabled: hideMature, mode: matureMode) {
                        SensitiveWorkCoverCard(work: work)
                    } else if !gate.isHidden(work, enabled: hideMature, mode: matureMode) {
                        // A wrapping link, not the background `cardNavigation` link: that one
                        // has an empty label, so outside a List row it has no hit area (BUG-12).
                        RemoteWorkLink(work: work) { SensitiveWorkCoverCard(work: work) }
                            .buttonStyle(.plain)
                    }
                }
                if let remaining = remainingCount {
                    Button(action: onSeeAllMostKudos) {
                        VStack(spacing: 4) {
                            Text("+\(remaining.formatted())")
                                .font(.title2.weight(.semibold))
                            Text("more")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.accentInk)
                        .frame(minWidth: moreCardWidth, maxWidth: moreCardWidth, minHeight: 166)
                        .subjectPanel(cornerRadius: 12)
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Self.moreWorksAccessibilityLabel(remaining))
                }
            }
            .padding(.horizontal, SubjectMetrics.accountGutter)
        }
        .pageBodyRow(top: 10, gutter: 0)
    }

    private var series: some View {
        let items = Array(model.overviewSeries.prefix(AuthorProfileSeeAll.seriesPreviewLimit))
        let total = model.header?.listCount(for: .series, route: model.route)
        let showSeeAll = AuthorProfileSeeAll.isShown(
            visibleCount: items.count,
            totalCount: total,
            hasMore: model.overviewSeries.count > items.count
                || (model.header?.recentSeries == nil && model.hasMore && model.selectedTab == .series)
        )
        let remaining = Self.remainingCount(total: total, visible: items.count)
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return Section {
            SectionRuleHeader(
                title: "Series",
                count: total,
                onSeeAll: showSeeAll ? { onSeeAll(.series) } : nil
            )
            .pageBodyRow(top: 24, gutter: 0)
            Group {
                if case let .failed(message) = model.seriesPhase {
                    AuthorProfileOverviewFailure(
                        model: model,
                        section: .series,
                        title: "Couldn't load Series",
                        message: message
                    )
                    .pageBodyRow(top: 10, gutter: SubjectMetrics.accountGutter)
                }
                if model.header?.recentSeries == nil, model.series.isEmpty {
                    if model.seriesPhase == .idle || model.seriesPhase == .loading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .accentFill()
                    } else if model.seriesPhase == .loaded {
                        overviewMessage("No series visible on AO3.")
                    }
                } else if items.isEmpty {
                    overviewMessage("No series visible on AO3.")
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(items) { item in
                            AuthorProfileSeriesCard(series: item)
                                .cardNavigation(to: item, accessibilityLabel: item.title)
                        }
                    }
                    .pageBodyRow(top: 10, gutter: SubjectMetrics.accountGutter)
                    if let remaining {
                        Button { onSeeAll(.series) } label: {
                            HStack(spacing: 6) {
                                Text(Self.moreSeriesText(remaining))
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .accessibilityHidden(true)
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.accentInk)
                        }
                        .buttonStyle(.plain)
                        .minimumHitTarget()
                        .accessibilityLabel("\(remaining.formatted()) more series")
                        .pageBodyRow(top: 10, gutter: SubjectMetrics.accountGutter)
                    }
                }
            }
            .onAppear { model.ensureSectionVisible(.series, auth: auth) }
        }
    }

    private var bookmarks: some View {
        let items = Array(
            model.overviewBookmarks.prefix(AuthorProfileSeeAll.bookmarksPreviewLimit)
        )
        let total = model.header?.listCount(for: .bookmarks, route: model.route)
        let showSeeAll = AuthorProfileSeeAll.isShown(
            visibleCount: items.count,
            totalCount: total,
            hasMore: model.overviewBookmarks.count > items.count
        )
        return Section {
            SectionRuleHeader(
                title: "Bookmarks",
                count: total,
                onSeeAll: showSeeAll ? { onSeeAll(.bookmarks) } : nil
            )
            .pageBodyRow(top: 24, gutter: 0)
            Group {
                if case let .failed(message) = model.bookmarksPhase {
                    AuthorProfileOverviewFailure(
                        model: model,
                        section: .bookmarks,
                        title: "Couldn't load Bookmarks",
                        message: message
                    )
                    .pageBodyRow(top: 10, gutter: SubjectMetrics.accountGutter)
                }
                if model.header?.recentBookmarks == nil, model.bookmarks.isEmpty {
                    if model.bookmarksPhase == .idle || model.bookmarksPhase == .loading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .accentFill()
                    } else if model.bookmarksPhase == .loaded {
                        overviewMessage("No bookmarks visible on AO3.")
                    }
                } else if items.isEmpty {
                    overviewMessage("No bookmarks visible on AO3.")
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(items) { bookmark in
                                SensitiveRemoteWorkCard(work: bookmark.work) {
                                    AuthorProfileBookmarkNoteCard(bookmark: bookmark)
                                }
                            }
                        }
                        .padding(.horizontal, SubjectMetrics.accountGutter)
                    }
                    .pageBodyRow(top: 10, gutter: 0)
                }
            }
            .onAppear { model.ensureSectionVisible(.bookmarks, auth: auth) }
        }
    }

    private func overviewMessage(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .subjectPanel()
            .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
    }

}

struct AuthorProfileLatestCard: View {
    enum Style: Equatable {
        case author
        case account
    }

    let work: AO3WorkSummary
    /// Board 23 (Author) draws a play disc; board 35 (Account) a chevron disc.
    var discSymbol = "play.fill"
    var style: Style = .author

    @Environment(PrivacyGate.self) private var gate
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var mode: MaturePrivacyMode = .obscure
    @ScaledMetric(relativeTo: .title) private var titleSize: CGFloat = 24
    @ScaledMetric(relativeTo: .subheadline) private var summarySize: CGFloat = 15

    var body: some View {
        let stats = Self.statsLine(for: work, style: style)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 12) {
                WorkStatusIconGrid(
                    rating: work.rating.isEmpty ? nil : work.rating,
                    categories: work.categories,
                    warnings: work.warnings,
                    completion: WorkCompletionStatus(isComplete: work.isComplete),
                    tileSize: 26,
                    announcesToVoiceOver: true,
                    // Author "Latest" and Account "Your Latest" paint their own dark
                    // backing container, so the grid keeps its own backing off.
                    backed: false
                )
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.black.opacity(0.22))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                )

                VStack(alignment: .leading, spacing: 3) {
                    if let kicker = Self.kicker(for: work) {
                        Text(kicker)
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .tracking(0.6)
                            .foregroundStyle(Color.white.opacity(0.88))
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    }
                    Text(work.title)
                        .font(.system(size: titleSize, weight: .semibold, design: .serif))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Room for the play / chevron disc (boards 23 and 35).
                .padding(.trailing, 44)
            }
            if style == .author, !work.summary.isEmpty {
                Text(work.summary)
                    .font(.system(size: summarySize))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !stats.isEmpty {
                Text(stats)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .overlay(alignment: .topTrailing) {
            // Board 23's play disc / board 35's chevron disc. Decorative: the whole card
            // is already the work's link (SensitiveRemoteWorkCard).
            Image(systemName: discSymbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.accentFill)
                .frame(width: 40, height: 40)
                .background(Color.white, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                .padding(14)
                .accessibilityHidden(true)
        }
        .background {
            WorkCoverCardBackground(recipe: work.generatedCoverRecipe,
                                    showsArt: !gate.isBlurred(work, enabled: hideMature, mode: mode))
        }
    }

    static func kicker(for work: AO3WorkSummary) -> String? {
        var parts: [String] = []
        if let fandom = work.fandoms.first, !fandom.isEmpty {
            parts.append(FandomDisplayName.bareTitle(fandom))
        }
        if let posted = chapterParts(from: work.chapters).posted, posted > 0 {
            parts.append("Chapter \(posted.formatted())")
        } else if !work.chapters.isEmpty {
            parts.append(work.chapters)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func chapterParts(from chapters: String) -> (posted: Int?, total: Int?) {
        let parts = chapters.split(separator: "/", omittingEmptySubsequences: false)
        guard let first = parts.first else { return (nil, nil) }
        let posted = parseChapterCount(String(first))
        let total = parts.count > 1 ? parseChapterCount(String(parts[1])) : nil
        return (posted, total)
    }

    static func chapterProgress(from chapters: String) -> String? {
        let (posted, total) = chapterParts(from: chapters)
        guard let posted, posted > 0 else { return nil }
        if let total, total > 0 {
            return total == 1 && posted == 1
                ? "1 chapter"
                : "\(posted.formatted()) of \(total.formatted())"
        }
        return posted == 1 ? "1 chapter" : "\(posted.formatted()) chapters"
    }

    static func statsLine(
        for work: AO3WorkSummary,
        style: Style = .author,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        var parts: [String] = []
        switch style {
        case .author:
            if !work.dateUpdated.isEmpty {
                parts.append("Updated \(WorkStat.displayDate(work.dateUpdated, locale: locale))")
            }
            if let words = work.words {
                parts.append(words == 1 ? "1 word" : "\(words.formatted()) words")
            }
            if let kudos = work.kudos { parts.append("♥ \(kudos.formatted())") }
            if let hits = work.hits {
                parts.append(hits == 1 ? "1 hit" : "\(hits.compactCount) hits")
            }
        case .account:
            // Blurb `p.datetime` is the revised date, so this stays "Updated".
            // The account board's "Posted" would name a date the summary does not have.
            if !work.dateUpdated.isEmpty {
                parts.append("Updated \(WorkStat.displayDate(work.dateUpdated, locale: locale))")
            }
            if let progress = chapterProgress(from: work.chapters) {
                parts.append(progress)
            }
            if let kudos = work.kudos { parts.append("♥ \(kudos.formatted())") }
            if let hits = work.hits {
                parts.append(hits == 1 ? "1 hit" : "\(hits.formatted()) hits")
            }
            if let comments = work.comments {
                parts.append(comments == 1 ? "1 comment" : "\(comments.formatted()) comments")
            }
        }
        return parts.joined(separator: " · ")
    }

    private static func parseChapterCount(_ raw: String) -> Int? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        return Int(cleaned)
    }
}

struct AuthorProfileSeriesCard: View {
    let series: AO3SeriesSummary

    @Environment(ThemeManager.self) private var theme
    @ScaledMetric(relativeTo: .callout) private var titleSize: CGFloat = 16

    private var palette: SubjectPalette {
        theme.appTheme.subjectPalette(
            hue: CoverArt.workHue(fandoms: series.fandoms, title: series.title)
        )
    }

    private var partCount: Int {
        min(max(series.workCount ?? 1, 1), AuthorProfileSeeAll.seriesPartsLimit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                ForEach(1...partCount, id: \.self) { index in
                    let recipe = GeneratedCoverRecipe(
                        id: series.id,
                        title: "\(series.title), part \(index)",
                        author: series.creatorNames.first ?? "",
                        fandoms: series.fandoms,
                        complete: series.isComplete == true || index < partCount,
                        seriesID: series.id,
                        part: index
                    )
                    GeometryReader { geometry in
                        GeneratedCoverView(
                            recipe: recipe,
                            width: max(geometry.size.width, 1),
                            height: 54,
                            showsWords: false,
                            cornerRadius: 5
                        )
                    }
                    .frame(height: 54)
                    .overlay(alignment: .bottomLeading) {
                        Text("\(index)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.white.opacity(0.92))
                            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                            .padding(.leading, 5)
                            .padding(.bottom, 3)
                    }
                    .accessibilityHidden(true)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                if let fandom = series.fandoms.first {
                    Text(FandomDisplayName.bareTitle(fandom))
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(palette.accent)
                        .lineLimit(1)
                }
                Text(series.title)
                    .font(.system(size: titleSize, weight: .semibold, design: .serif))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let meta = Self.metaText(for: series) {
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .subjectPanel()
        .accessibilityElement(children: .combine)
    }

    static func metaText(
        for series: AO3SeriesSummary,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        var parts: [String] = []
        if let count = series.workCount {
            parts.append(count == 1 ? "1 part" : "\(count.formatted()) parts")
        }
        if let words = series.words {
            parts.append(words == 1 ? "1 word" : "\(words.compactCount) words")
        }
        if series.isComplete == true {
            parts.append("complete")
        } else if !series.dateUpdated.isEmpty {
            parts.append(WorkStat.displayDate(series.dateUpdated, locale: locale))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct AuthorProfileBookmarkNoteCard: View {
    let bookmark: AO3AuthorBookmark

    @Environment(\.accentFill) private var accentFill
    @ScaledMetric(relativeTo: .body) private var noteSize: CGFloat = 17
    @ScaledMetric(relativeTo: .body) private var cardWidth: CGFloat = 262

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let note = Self.quotedNote(for: bookmark.notes) {
                Text(note)
                    .font(.system(size: noteSize, weight: .regular, design: .serif).italic())
                    .lineSpacing(3)
                    .foregroundStyle(.primary)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .center, spacing: 10) {
                GeneratedCoverView(
                    recipe: bookmark.work.generatedCoverRecipe,
                    width: 28,
                    height: 38,
                    showsWords: false,
                    cornerRadius: 4
                )
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(bookmark.work.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if bookmark.isRecommendation {
                            Text("Rec")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.accentInk)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(accentFill.opacity(0.12), in: Capsule())
                        }
                    }
                    if let meta = Self.metaText(for: bookmark.work) {
                        Text(meta)
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, bookmark.notes.isEmpty ? 0 : 10)
            .overlay(alignment: .top) {
                if !bookmark.notes.isEmpty {
                    Divider()
                }
            }
        }
        .padding(14)
        .frame(width: cardWidth, alignment: .leading)
        .subjectPanel()
        .accessibilityElement(children: .combine)
    }

    static func quotedNote(for notes: AO3RichText) -> String? {
        let plain = notes.plainText
        guard !plain.isEmpty else { return nil }
        return "“\(plain)”"
    }

    static func metaText(for work: AO3WorkSummary) -> String? {
        var parts: [String] = []
        if let author = work.authors.first, !author.isEmpty {
            parts.append(author)
        }
        if let fandom = work.fandoms.first {
            parts.append(FandomDisplayName.bareTitle(fandom))
        }
        if let words = work.words {
            parts.append(words == 1 ? "1 word" : "\(words.formatted()) words")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
