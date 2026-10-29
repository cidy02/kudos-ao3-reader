import SwiftUI

/// Left-aligned identity header: author-colour wash lives on the screen, not
/// on these controls. Subscribe / Mute / Block stay AO3 red (`accentFill`).
struct AuthorProfileOverviewHeader: View {
    var model: AO3AuthorProfileModel
    let isOwnProfile: Bool
    var muteAction: AO3AuthorWebAction?
    var blockAction: AO3AuthorWebAction?
    let onSubscription: () -> Void
    let onModeration: (AO3AuthorWebAction) -> Void
    let onSelectScope: (AO3AuthorRoute) -> Void

    @Environment(AO3AuthService.self) private var auth
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var showsAccountActions: Bool {
        !isOwnProfile && !model.route.isOrphanAccount
    }

    private var actionsBusy: Bool {
        model.isPerformingSubscription || model.isPerformingModeration
    }

    var body: some View {
        if let header = model.header {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    identityRow(header)
                    if let about = model.about, !about.bio.isEmpty {
                        AO3RichTextView(document: about.bio, font: .subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if showsAccountActions {
                        actionRow(header)
                    }
                }
                .pageBodyRow(top: 16, gutter: SubjectMetrics.accountGutter)
            }
            .onAppear { model.ensureSectionVisible(.about, auth: auth) }
        }
    }

    private func identityRow(_ header: AO3AuthorHeader) -> some View {
        HStack(alignment: .center, spacing: 14) {
            AO3AuthorAvatar(
                url: header.identity.avatarURL,
                name: model.route.displayName,
                isCircular: true
            )
            VStack(alignment: .leading, spacing: 2) {
                pseudNameMenu(header)
                if let subtitle = identitySubtitle(header) {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    private func identitySubtitle(_ header: AO3AuthorHeader) -> String? {
        var parts: [String] = []
        if let joined = model.about?.joinedDate, !joined.isEmpty {
            parts.append("Joined \(joined)")
        }
        if header.pseuds.count > 1 {
            parts.append("\(header.pseuds.count) pseuds")
        }
        if model.route.pseud != nil {
            parts.append("Pseud of \(model.route.username)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func pseudNameMenu(_ header: AO3AuthorHeader) -> some View {
        let showsChooser = header.pseuds.count > 1 || model.route.pseud != nil
        let name = Text(model.route.displayName)
            .font(.title2.weight(.bold))
            .lineLimit(3)
            .minimumScaleFactor(0.75)
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
                    name
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("\(model.route.displayName). Choose a pseud")
            .accessibilityValue(model.route.pseud ?? "All Pseuds")
        } else {
            name.accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private func actionRow(_ header: AO3AuthorHeader) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        layout {
            if let form = header.subscriptionForm {
                subscribeButton(form)
            }
            if let muteAction {
                moderationButton(muteAction, webKind: .mute)
            }
            if let blockAction {
                moderationButton(blockAction, webKind: .block)
            }
        }
    }

    private func subscribeButton(_ form: AO3AuthorSubscriptionForm) -> some View {
        Button(action: onSubscription) {
            HStack(spacing: 5) {
                if model.isPerformingSubscription {
                    ProgressView().controlSize(.small).accentFill()
                } else {
                    Image(systemName: form.isSubscribed ? "bell.slash" : "bell")
                }
                Text(form.isSubscribed ? "Unsubscribe" : "Subscribe")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .accentFill()
        .prominentLabel()
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
            HStack(spacing: 5) {
                if model.isPerformingModeration {
                    ProgressView().controlSize(.small).accentFill()
                } else {
                    Image(systemName: kind?.systemImage
                        ?? (webKind == .mute ? "speaker.slash" : "hand.raised"))
                }
                Text(action.label)
            }
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
        }
        .buttonStyle(.bordered)
        .foregroundStyle(.accentInk)
        .accentFill()
        .disabled(actionsBusy)
        .accessibilityLabel(action.label)
    }
}

struct AuthorProfileOverviewSections: View {
    var model: AO3AuthorProfileModel
    let onSeeAll: (AO3AuthorProfileTab) -> Void
    let onOpenFandom: (AO3AuthorFandom) -> Void

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let header = model.header {
            countStrip(header)
            fandoms(header)
        }
        latest
        mostKudos
        series
        bookmarks
    }

    private func countStrip(_ header: AO3AuthorHeader) -> some View {
        let items: [(AO3AuthorProfileTab, AO3AuthorRoute.Content)] = [
            (.works, .works), (.series, .series), (.bookmarks, .bookmarks), (.gifts, .gifts)
        ]
        let columns = dynamicTypeSize.isAccessibilitySize ? 2 : 4
        return Section {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: columns),
                spacing: 0
            ) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    let (tab, content) = item
                    let count = header.listCount(for: content, route: model.route)
                    Button { onSeeAll(tab) } label: {
                        VStack(spacing: 1) {
                            Text(count?.compactCount ?? "—")
                                .font(.title3.weight(.bold).monospacedDigit())
                            Text(tab.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(countLabel(tab: tab, count: count))
                    .overlay(alignment: .leading) {
                        if index % columns != 0 {
                            Divider().padding(.vertical, 8)
                        }
                    }
                }
            }
            .subjectPanel(cornerRadius: 16)
            .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
        }
    }

    private func countLabel(tab: AO3AuthorProfileTab, count: Int?) -> String {
        guard let count else { return tab.rawValue }
        return "\(count.compactCount) \(tab.rawValue.lowercased())"
    }

    @ViewBuilder
    private func fandoms(_ header: AO3AuthorHeader) -> some View {
        if !header.fandoms.isEmpty {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(header.fandoms) { fandom in
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
                                    Text(FandomDisplayName.bareTitle(fandom.name))
                                        .font(.subheadline)
                                    if let count = fandom.workCount {
                                        Text(count.compactCount)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color(.quaternarySystemFill), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(fandom.url == nil)
                            .minimumHitTarget()
                        }
                    }
                }
                .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
            }
        }
    }

    private var latest: some View {
        Section {
            SectionRuleHeader(title: "Latest")
                .pageBodyRow(top: 18, gutter: 0)
            if let work = model.latestWork {
                AuthorProfileLatestCard(work: work)
                    .cardNavigation(to: work, accessibilityLabel: work.title)
                    .pageBodyRow(top: 10, gutter: SubjectMetrics.accountGutter)
            } else if model.header?.recentWorks == nil {
                overviewMessage("Couldn't read the latest work. Open Works to try again.")
            } else {
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
        return Section {
            SectionRuleHeader(
                title: "Most Kudos",
                count: total,
                onSeeAll: showSeeAll ? { onSeeAll(.works) } : nil
            )
            .pageBodyRow(top: 18, gutter: 0)
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
                    if works.isEmpty {
                        overviewMessage(message)
                    } else {
                        popularShelf(works)
                    }
                case .loaded:
                    if works.isEmpty {
                        overviewMessage("No works visible on AO3.")
                    } else {
                        popularShelf(works)
                    }
                }
            }
            .onAppear { model.ensureSectionVisible(.popular, auth: auth) }
        }
    }

    private func popularShelf(_ works: [AO3WorkSummary]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(works) { work in
                    AO3WorkCoverCard(work: work)
                        .cardNavigation(to: work, accessibilityLabel: work.title)
                }
            }
        }
        .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
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
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return Section {
            SectionRuleHeader(
                title: "Series",
                count: total,
                onSeeAll: showSeeAll ? { onSeeAll(.series) } : nil
            )
            .pageBodyRow(top: 18, gutter: 0)
            Group {
                if model.header?.recentSeries == nil, model.series.isEmpty {
                    if model.contentPhase == .loading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .accentFill()
                    } else {
                        overviewMessage("Couldn't read series. Open the full list to try again.")
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
                    .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
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
            .pageBodyRow(top: 18, gutter: 0)
            Group {
                if model.header?.recentBookmarks == nil, model.bookmarks.isEmpty {
                    if model.contentPhase == .loading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .accentFill()
                    } else {
                        overviewMessage("Couldn't read bookmarks. Open the full list to try again.")
                    }
                } else if items.isEmpty {
                    overviewMessage("No bookmarks visible on AO3.")
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(items) { bookmark in
                                AuthorProfileBookmarkNoteCard(bookmark: bookmark)
                                    .cardNavigation(
                                        to: bookmark.work,
                                        accessibilityLabel: bookmark.work.title
                                    )
                            }
                        }
                    }
                    .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
                }
            }
            .onAppear { model.ensureSectionVisible(.bookmarks, auth: auth) }
        }
    }

    private func overviewMessage(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .subjectPanel(cornerRadius: 16)
            .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
    }
}

struct AuthorProfileLatestCard: View {
    let work: AO3WorkSummary

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var titleSize: CGFloat = 24
    @ScaledMetric(relativeTo: .subheadline) private var summarySize: CGFloat = 15

    private var palette: SubjectPalette {
        theme.appTheme.subjectPalette(
            hue: CoverArt.workHue(fandoms: work.fandoms, title: work.title)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                WorkStatusIconGrid(
                    rating: work.rating.isEmpty ? nil : work.rating,
                    categories: work.categories,
                    warnings: work.warnings,
                    completion: WorkCompletionStatus(isComplete: work.isComplete),
                    tileSize: 22,
                    announcesToVoiceOver: true,
                    showsTray: true
                )
                VStack(alignment: .leading, spacing: 3) {
                    if let kicker = latestKicker {
                        Text(kicker)
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .tracking(0.6)
                            .foregroundStyle(.primary.opacity(0.88))
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    }
                    Text(work.title)
                        .font(.system(size: titleSize, weight: .semibold, design: .serif))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !work.summary.isEmpty {
                Text(work.summary)
                    .font(.system(size: summarySize))
                    .foregroundStyle(.primary.opacity(0.92))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !statsLine.isEmpty {
                Text(statsLine)
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: SubjectMetrics.heroRadius, style: .continuous)
                .fill(theme.appTheme.carouselCardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: SubjectMetrics.heroRadius, style: .continuous)
                        .fill(palette.cardWash)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SubjectMetrics.heroRadius, style: .continuous)
                        .strokeBorder(palette.cardBorder, lineWidth: 0.5)
                )
        }
    }

    private var latestKicker: String? {
        var parts: [String] = []
        if let fandom = work.fandoms.first, !fandom.isEmpty {
            parts.append(FandomDisplayName.bareTitle(fandom))
        }
        if !work.chapters.isEmpty {
            parts.append(work.chapters.contains("/") ? "Ch. \(work.chapters)" : work.chapters)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var statsLine: String {
        var parts: [String] = []
        if !work.dateUpdated.isEmpty { parts.append("Updated \(work.dateUpdated)") }
        if let words = work.words { parts.append("\(words.formatted()) words") }
        if let kudos = work.kudos { parts.append("♥ \(kudos.compactCount)") }
        if let hits = work.hits { parts.append("\(hits.compactCount) hits") }
        return parts.joined(separator: " · ")
    }
}

struct AuthorProfileSeriesCard: View {
    let series: AO3SeriesSummary

    @Environment(ThemeManager.self) private var theme

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
                    let hue = CoverArt.hue(for: "\(series.title)#\(index)")
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(theme.appTheme.subjectPalette(hue: hue).cardWash)
                        .frame(height: 54)
                        .overlay(alignment: .bottomLeading) {
                            Text("\(index)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.primary.opacity(0.92))
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
                    .font(.system(.headline, design: .serif))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let meta = seriesMeta {
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .subjectPanel(cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }

    private var seriesMeta: String? {
        var parts: [String] = []
        if let count = series.workCount {
            parts.append(count == 1 ? "1 part" : "\(count) parts")
        }
        if let words = series.words {
            parts.append("\(words.formatted()) words")
        }
        if series.isComplete == true {
            parts.append("complete")
        } else if !series.dateUpdated.isEmpty {
            parts.append(series.dateUpdated)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct AuthorProfileBookmarkNoteCard: View {
    let bookmark: AO3AuthorBookmark

    @Environment(ThemeManager.self) private var theme
    @Environment(\.accentFill) private var accentFill
    @ScaledMetric(relativeTo: .body) private var noteSize: CGFloat = 17
    @ScaledMetric(relativeTo: .body) private var cardWidth: CGFloat = 262

    private var palette: SubjectPalette {
        theme.appTheme.subjectPalette(
            hue: CoverArt.workHue(fandoms: bookmark.work.fandoms, title: bookmark.work.title)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !bookmark.notes.isEmpty {
                Text("“\(bookmark.notes.plainText)”")
                    .font(.system(size: noteSize, weight: .regular, design: .serif).italic())
                    .foregroundStyle(.primary)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .center, spacing: 10) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(palette.cardWash)
                    .frame(width: 28, height: 38)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(bookmark.work.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if bookmark.isRecommendation {
                            Text("Rec")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(accentFill)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 1)
                                .background(accentFill.opacity(0.1), in: Capsule())
                        }
                    }
                    if let meta = bookmarkMeta {
                        Text(meta)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
        .subjectPanel(cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }

    private var bookmarkMeta: String? {
        var parts: [String] = []
        if let author = bookmark.work.authors.first, !author.isEmpty {
            parts.append(author)
        }
        if let fandom = bookmark.work.fandoms.first {
            parts.append(FandomDisplayName.bareTitle(fandom))
        }
        if let words = bookmark.work.words {
            parts.append("\(words.formatted()) words")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
