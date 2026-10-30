import SwiftUI

struct AO3AuthorHero: View {
    let header: AO3AuthorHeader
    let route: AO3AuthorRoute
    let profileTitle: String
    let isOwnProfile: Bool
    let isPerformingSubscription: Bool
    var isPerformingModeration: Bool = false
    /// Icon-only Mute / Block (or Unmute / Unblock) from AO3's profile actions.
    var muteAction: AO3AuthorWebAction?
    var blockAction: AO3AuthorWebAction?
    let onSubscription: () -> Void
    var onModerationAction: (AO3AuthorWebAction) -> Void = { _ in }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var showsAccountActions: Bool {
        !isOwnProfile && !route.isOrphanAccount
    }

    private var showsActionRow: Bool {
        guard showsAccountActions else { return false }
        return header.subscriptionForm != nil || muteAction != nil || blockAction != nil
    }

    private var actionsBusy: Bool {
        isPerformingSubscription || isPerformingModeration
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                AO3AuthorAvatar(url: header.identity.avatarURL, name: route.displayName)

                VStack(alignment: .leading, spacing: 5) {
                    Text(route.displayName)
                        .font(.title2.weight(.semibold))
                        .lineLimit(3)
                        .minimumScaleFactor(0.75)
                        .accessibilityAddTraits(.isHeader)

                    if route.pseud != nil {
                        Text("Pseud of \(route.username)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("AO3 user")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if !profileTitle.isEmpty {
                        Text(profileTitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if showsActionRow && !dynamicTypeSize.isAccessibilitySize {
                        // Subscribe keeps a text label; Mute/Block are icon-only beside it
                        // (AO3's full label is the accessibility string).
                        actionRow
                            .padding(.top, 3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Beside the avatar at AX5 the column broke "Sub-scribe": the row takes the card's width.
            if showsActionRow && dynamicTypeSize.isAccessibilitySize {
                actionRow
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    /// Beside the avatar at AX5, Subscribe was squeezed into a tall empty pillar
    /// with no label. There the row goes under the avatar row: Subscribe across the card,
    /// Mute and Block beside each other under it.
    @ViewBuilder
    private var actionRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                if let form = header.subscriptionForm {
                    subscribeButton(form)
                }
                HStack(spacing: 8) {
                    if let muteAction {
                        moderationIconButton(muteAction, webKind: .mute)
                    }
                    if let blockAction {
                        moderationIconButton(blockAction, webKind: .block)
                    }
                    if isPerformingModeration {
                        ProgressView()
                            .controlSize(.small)
                            .accentFill()
                    }
                }
            }
        } else {
            HStack(spacing: 8) {
                if let form = header.subscriptionForm {
                    subscribeButton(form)
                }
                if let muteAction {
                    moderationIconButton(muteAction, webKind: .mute)
                }
                if let blockAction {
                    moderationIconButton(blockAction, webKind: .block)
                }
                if isPerformingModeration {
                    ProgressView()
                        .controlSize(.small)
                        .accentFill()
                }
            }
        }
    }

    @ViewBuilder
    private func subscribeButton(_ form: AO3AuthorSubscriptionForm) -> some View {
        // Explicit HStack (not Label): Label + .borderedProminent +
        // .small often misaligns the glyph vs title.
        let button = Button(action: onSubscription) {
            HStack(spacing: 5) {
                if isPerformingSubscription {
                    ProgressView()
                        .controlSize(.small)
                        .accentFill()
                } else {
                    Image(systemName: form.isSubscribed ? "bell.slash" : "bell")
                }
                subscribeTitle(form)
            }
        }
        .buttonStyle(.borderedProminent)
        .accentFill()
        .prominentLabel()
        if dynamicTypeSize.isAccessibilitySize {
            // A small capsule clipped the label and left the chrome. A rounded
            // rect has room for the wrapped words, across the column.
            button
                .buttonBorderShape(.roundedRectangle(radius: SubjectMetrics.cornerRadius))
                .disabled(actionsBusy)
                .accessibilityHint(subscriptionHint)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            button
                .controlSize(.small)
                .disabled(actionsBusy)
                .accessibilityHint(subscriptionHint)
        }
    }

    private var subscriptionHint: String {
        route.pseud != nil
            ? "Applies to \(route.username)'s whole account, not only this pseud."
            : ""
    }

    @ViewBuilder
    private func subscribeTitle(_ form: AO3AuthorSubscriptionForm) -> some View {
        let title = Text(form.isSubscribed ? "Unsubscribe" : "Subscribe")
        if dynamicTypeSize.isAccessibilitySize {
            title
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            title
        }
    }

    private func moderationIconButton(
        _ action: AO3AuthorWebAction,
        webKind: AO3AuthorWebAction.Kind
    ) -> some View {
        let isUndo = action.label.localizedCaseInsensitiveContains("un")
        let kind = AO3AuthorModerationKind(webAction: webKind, isUndo: isUndo)
        return Button {
            onModerationAction(action)
        } label: {
            Image(systemName: kind?.systemImage
                ?? (webKind == .mute ? "speaker.slash" : "hand.raised"))
        }
        .buttonStyle(.bordered)
        .foregroundStyle(.accentInk)
        .accentFill()
        .moderationControlSize(accessibilitySize: dynamicTypeSize.isAccessibilitySize)
        .disabled(actionsBusy)
        .accessibilityLabel(action.label)
    }
}

extension View {
    /// `.controlSize(.small)` at AX5 turned Subscribe's neighbour into the same
    /// empty pillar. Ordinary sizes keep the small control.
    @ViewBuilder
    fileprivate func moderationControlSize(accessibilitySize: Bool) -> some View {
        if accessibilitySize {
            self
        } else {
            controlSize(.small)
        }
    }
}

struct AO3AuthorAvatar: View {
    let url: URL?
    let name: String
    /// 72pt square on an author page; 1m's account header draws a 56pt circle.
    var size: CGFloat = 72
    var isCircular = false

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .background(.quaternary)
        .clipShape(isCircular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous)))
        .accessibilityLabel("\(name) profile image")
    }

    private var placeholder: some View {
        Image(systemName: isCircular ? "person.crop.circle" : "person.crop.square")
            .font(.system(size: size * 0.42, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AO3SeriesRow: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let series: AO3SeriesSummary
    var presentation: WorkRow.Presentation = .standard

    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 19
    @ScaledMetric(relativeTo: .footnote) private var summarySize: CGFloat = 13.5
    @ScaledMetric(relativeTo: .caption) private var metaSize: CGFloat = 11.5

    var body: some View {
        Group {
            if presentation == .ledger {
                ledgerBody
            } else {
                standardBody
            }
        }
    }

    private var ledgerBody: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 12) {
                // The square Series icon (38x38)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    // The series' own hue through the palette, not a fixed dark
                    // gradient: Light and Sepia ship too, and a hard-coded
                    // white-0.15 tile reads as a black square in both.
                    .fill(seriesPalette.cardWash)
                    .frame(width: 38, height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(seriesPalette.chipStroke, lineWidth: 0.5)
                    )
                    .overlay(SeriesSpineStackMark(color: fandomColor))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(primaryFandom.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .lineSpacing(1.2)
                            .tracking(1.1)
                            .foregroundStyle(fandomColor)
                            .lineLimit(1)
                        if series.isComplete == true {
                            SubjectStateBadge(title: "Complete", color: .green)
                        }
                        if series.isRestricted {
                            SubjectStateBadge(title: "Restricted", color: restrictedColor)
                        }
                    }

                    Capsule()
                        .fill(fandomColor)
                        .frame(width: 22, height: 2.5)

                    Text(series.title)
                        .font(.system(size: titleSize, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.top, 1)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                }
            }

            if !series.summary.isEmpty {
                Text(series.summary)
                    .font(.system(size: summarySize))
                    .lineSpacing(1.5)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    // Side by side, each figure had a column a few letters wide at the
                    // accessibility sizes ("9,00 / 1 / word / s"): one line that wraps
                    // between figures, and the date under it.
                    VStack(alignment: .leading, spacing: 2) {
                        Text(figures.joined(separator: "  ·  "))
                        if !series.dateUpdated.isEmpty {
                            Text(series.dateUpdated)
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        ForEach(Array(figures.enumerated()), id: \.offset) { index, figure in
                            if index > 0 {
                                Text("·").foregroundStyle(.tertiary)
                            }
                            Text(figure)
                        }
                        Spacer(minLength: 8)
                        if !series.dateUpdated.isEmpty {
                            Text(series.dateUpdated)
                        }
                    }
                }
            }
            .font(.system(size: metaSize))
            .foregroundStyle(.secondary)

            AO3AuthorBylineView(
                names: series.creatorNames, identities: series.creatorIdentities,
                compact: !dynamicTypeSize.isAccessibilitySize
            )
        }
        // Its own height at the accessibility sizes: the list gave the taller card less than
        // it needed, and the title and the figures were cut to fit ("The Daw…").
        .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
    }

    /// The counts AO3 printed for the series, in its order, each with its noun.
    private var figures: [String] {
        [
            series.workCount.map { $0 == 1 ? "1 work" : "\($0) works" },
            series.words.map { "\($0.formatted()) words" },
            series.bookmarkCount.map { $0 == 1 ? "1 bookmark" : "\($0.formatted()) bookmarks" }
        ].compactMap { $0 }
    }

    private var primaryFandom: String {
        series.fandoms.first.map(FandomDisplayName.bareTitle) ?? "Series"
    }

    private var seriesPalette: SubjectPalette {
        themeManager.appTheme.subjectPalette(
            hue: CoverArt.workHue(fandoms: series.fandoms, title: series.title)
        )
    }

    private var fandomColor: Color {
        seriesPalette.accent
    }

    /// 1w's restricted chip. Orange is the board's own, the way Complete is green.
    private var restrictedColor: Color {
        Color(red: 1, green: 159.0 / 255, blue: 10.0 / 255)
    }

    private var standardBody: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(series.title)
                .font(.headline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            AO3AuthorBylineView(
                names: series.creatorNames,
                identities: series.creatorIdentities,
                compact: true
            )

            if !series.fandoms.isEmpty {
                Label(series.fandoms.joined(separator: ", "), systemImage: "books.vertical")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !series.summary.isEmpty {
                Text(series.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Divider()
            FlowLayout(spacing: 18, rowSpacing: 5) {
                if let workCount = series.workCount {
                    WorkStatLabel(text: "\(workCount) works", symbol: "square.stack")
                }
                if let words = series.words {
                    WorkStatLabel(
                        text: words.formatted(),
                        symbol: "textformat.size",
                        accessibilityLabel: "\(words.formatted()) words"
                    )
                }
                if let bookmarks = series.bookmarkCount {
                    WorkStatLabel(
                        text: bookmarks.formatted(),
                        symbol: "bookmark",
                        accessibilityLabel: bookmarks == 1
                            ? "1 bookmark"
                            : "\(bookmarks.formatted()) bookmarks"
                    )
                }
                if series.isRestricted {
                    WorkStatLabel(text: "Restricted", symbol: "lock.fill")
                }
                if let complete = series.isComplete {
                    WorkStatLabel(
                        text: complete ? "Complete" : "In progress",
                        symbol: complete ? "checkmark.seal" : "circle.dashed"
                    )
                }
                if !series.dateUpdated.isEmpty {
                    WorkStatLabel(text: series.dateUpdated, symbol: "calendar")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 1w's series mark: three offset book spines. The rear one is lighter.
/// The artboard draws this instead of a list glyph, at every work count —
/// the stack is the series, and the posted-work count stays in the stats line.
private struct SeriesSpineStackMark: View {
    var color: Color

    var body: some View {
        ZStack {
            spine(opacity: 0.55).offset(x: 4.2, y: -4.6)
            spine(opacity: 1).offset(x: 2.1, y: -2.3)
            spine(opacity: 1)
        }
        .frame(width: 17, height: 17)
        .accessibilityHidden(true)
    }

    private func spine(opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 1.6, style: .continuous)
            .stroke(color.opacity(opacity), lineWidth: 1.25)
            .frame(width: 9, height: 10)
    }
}

struct AO3AuthorBookmarkRow: View {
    let bookmark: AO3AuthorBookmark
    var expandAll = false
    var presentation: AO3WorkRow.Presentation = .standard

    var body: some View {
        AO3WorkRow(
            work: bookmark.work,
            expandAll: expandAll,
            presentation: presentation,
            bookmark: bookmark
        )
    }
}

/// The bookmark-only content shared by Account Bookmarks and author profiles.
/// 1q gives notes a rail and bookmark tags their own rounded-rectangle grammar;
/// neither carries a caption or repeats the status/date below the card.
struct AO3BookmarkFootnote: View {
    let bookmark: AO3AuthorBookmark
    /// Private / Rec / date, for rows whose card cannot carry them (a saved
    /// work's row). The 1q card puts them on its kicker and stats row instead.
    var showsStatus = false

    @Environment(ThemeManager.self) private var theme
    @ScaledMetric(relativeTo: .caption) private var dateSize: CGFloat = 11.5
    /// The note grows with the text, as the tags under it do: at a fixed 14pt it was the one
    /// line on the card that stayed small at the accessibility sizes.
    @ScaledMetric(relativeTo: .footnote) private var noteSize: CGFloat = 14

    private var palette: SubjectPalette {
        theme.appTheme.subjectPalette(
            hue: CoverArt.workHue(fandoms: bookmark.work.fandoms, title: bookmark.work.title)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsStatus, bookmark.isPrivate || bookmark.isRecommendation || !bookmark.date.isEmpty {
                HStack(spacing: 6) {
                    if bookmark.isPrivate { SubjectStateBadge(title: "Private", color: .secondary) }
                    if bookmark.isRecommendation { SubjectStateBadge(title: "Rec", color: .secondary) }
                    Spacer(minLength: 0)
                    if !bookmark.date.isEmpty {
                        Text(bookmark.date)
                            .font(.system(size: dateSize))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Bookmarked \(bookmark.date)")
                    }
                }
            }
            if !bookmark.notes.isEmpty {
                HStack(alignment: .top, spacing: 11) {
                    Capsule()
                        .fill(palette.accent)
                        .frame(width: 2)
                    AO3RichTextView(
                        document: bookmark.notes,
                        font: .system(size: noteSize),
                        lineSpacing: 7
                    )
                    .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if !bookmark.tags.isEmpty {
                FlowLayout(spacing: 7, rowSpacing: 7) {
                    ForEach(bookmark.tags, id: \.self) { BookmarkTagPill(text: $0) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BookmarkTagPill: View {
    let text: String
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .footnote) private var tagTextSize: CGFloat = 13

    var body: some View {
        Text(text)
            .font(.system(size: tagTextSize))
            .foregroundStyle(.primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                SubjectMetrics.controlShape(dynamicTypeSize)
                    .fill(theme.appTheme.glassFill(0.09))
                    .overlay(
                        SubjectMetrics.controlShape(dynamicTypeSize)
                            .strokeBorder(theme.appTheme.glassStroke(0.14), lineWidth: 0.5)
                    )
            )
    }
}

struct AO3RichTextView: View {
    let document: AO3RichText
    var font: Font = .body
    var lineSpacing: CGFloat = 0
    /// Lays out only the blocks on screen: a whole chapter is over a thousand (T-358).
    var isLazy = false
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            if isLazy {
                LazyVStack(alignment: .leading, spacing: 9) { blocks }
            } else {
                VStack(alignment: .leading, spacing: 9) { blocks }
            }
        }
        .font(font)
        .lineSpacing(lineSpacing)
        .environment(\.openURL, OpenURLAction { url in
            if AO3AuthorRoute.isAO3URL(url) {
                router.openAO3Link(url)
                return .handled
            }
            guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                return .discarded
            }
            return .systemAction
        })
    }

    private var blocks: some View {
        ForEach(document.blocks) { block in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if block.kind == .listItem {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 4))
                        .accessibilityHidden(true)
                }
                Text(attributedString(for: block))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func attributedString(for block: AO3RichText.Block) -> AttributedString {
        var result = AttributedString()
        for run in block.runs {
            var piece = AttributedString(run.text)
            var intent: InlinePresentationIntent = []
            if run.isBold { intent.insert(.stronglyEmphasized) }
            if run.isItalic { intent.insert(.emphasized) }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            piece.link = run.link
            result.append(piece)
        }
        return result
    }
}

struct AO3AuthorProfileSkeleton: View {
    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    SkeletonBlock(height: 72, width: 72, cornerRadius: 8)
                    VStack(alignment: .leading, spacing: 9) {
                        SkeletonTextLine(height: 20, width: 150)
                        SkeletonTextLine(width: 110)
                        SkeletonTextLine(width: 180)
                    }
                }
                .padding(.vertical, 4)
                .skeletonShimmer()
                .cardRow()
            }
            Section {
                SkeletonBlock(height: 34, cornerRadius: 7)
                    .skeletonShimmer()
                    .cardRow()
            }
            Section {
                ForEach(0..<4, id: \.self) { _ in
                    AO3WorkRowSkeleton().cardRow()
                }
            }
        }
        .cardList()
        .accessibilityLabel("Loading author profile")
    }
}

struct AO3ProfileMessageRow: View {
    let title: String
    let systemImage: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    /// The system empty state every other list uses (pass2-23).
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
    }
}

/// The hero's arithmetic, kept beside the rows it sums: `AuthorProfileView`
/// sits at the file-length limit.
extension AuthorProfileView {
    /// 1w's "3 series · 9 works · 219,300 words", after the series count. Summed
    /// from the loaded blurbs, so while more pages exist than are loaded both
    /// sums sit in one clause scoped to them — "45 series · 60 works, 1,200,000
    /// words in the 20 loaded series" — rather than passing a partial sum off as
    /// the account's total. A figure AO3 printed for no series is dropped, not
    /// shown as zero.
    static func seriesTallyParts(_ series: [AO3SeriesSummary], isPartial: Bool) -> [String] {
        var parts: [String] = []
        let works = series.compactMap(\.workCount)
        if !works.isEmpty {
            let total = works.reduce(0, +)
            parts.append("\(total.formatted()) \(total == 1 ? "work" : "works")")
        }
        let words = series.compactMap(\.words)
        if !words.isEmpty {
            parts.append("\(words.reduce(0, +).formatted()) words")
        }
        guard isPartial, !parts.isEmpty else { return parts }
        return ["\(parts.joined(separator: ", ")) in the \(series.count.formatted()) loaded series"]
    }
}
