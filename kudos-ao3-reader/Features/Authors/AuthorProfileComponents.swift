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

                if showsActionRow {
                    // Subscribe keeps a text label; Mute/Block are icon-only beside it
                    // (AO3's full label is the accessibility string).
                    HStack(spacing: 8) {
                        if let form = header.subscriptionForm {
                            // Explicit HStack (not Label): Label + .borderedProminent +
                            // .small often misaligns the glyph vs title.
                            Button(action: onSubscription) {
                                HStack(spacing: 5) {
                                    if isPerformingSubscription {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: form.isSubscribed ? "bell.slash" : "bell")
                                    }
                                    Text(form.isSubscribed ? "Unsubscribe" : "Subscribe")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(actionsBusy)
                            // The button reads as scoped to whatever route is on screen,
                            // but AO3 subscriptions are account-wide — the unsubscribe
                            // confirmation already says so explicitly; give Subscribe
                            // the same disclosure when viewing a specific pseud.
                            .accessibilityHint(
                                route.pseud != nil
                                    ? "Applies to \(route.username)'s whole account, not only this pseud."
                                    : ""
                            )
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
                        }
                    }
                    .padding(.top, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
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
        .controlSize(.small)
        .disabled(actionsBusy)
        .accessibilityLabel(action.label)
    }
}

struct AO3AuthorAvatar: View {
    let url: URL?
    let name: String

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
        .frame(width: 72, height: 72)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel("\(name) profile image")
    }

    private var placeholder: some View {
        Image(systemName: "person.crop.square")
            .font(.system(size: 30, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AO3SeriesRow: View {
    @Environment(ThemeManager.self) private var themeManager
    let series: AO3SeriesSummary
    var presentation: WorkRow.Presentation = .standard

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
                    .overlay(
                        Image(systemName: "books.vertical")
                            .foregroundStyle(fandomColor)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(primaryFandom.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .lineSpacing(1.2)
                            .tracking(1.1)
                            .foregroundStyle(fandomColor)
                            .lineLimit(1)
                        if series.isComplete == true {
                            Text("COMPLETE")
                                .font(.system(size: 9.5, weight: .semibold, design: .default))
                                .tracking(0.5)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.15))
                                .foregroundStyle(Color.green)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(Color.green.opacity(0.35), lineWidth: 0.5)
                                )
                        }
                    }

                    Capsule()
                        .fill(fandomColor)
                        .frame(width: 22, height: 2.5)

                    Text(series.title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.top, 1)
                        .lineLimit(2)
                }
            }

            if !series.summary.isEmpty {
                Text(series.summary)
                    .font(.system(size: 13.5))
                    .lineSpacing(1.5)
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(3)
            }

            HStack(spacing: 8) {
                if let workCount = series.workCount {
                    Text("\(workCount) works")
                }
                if series.words != nil {
                    Text("·")
                        .foregroundStyle(.white.opacity(0.3))
                }
                if let words = series.words {
                    Text("\(words.formatted()) words")
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.white.opacity(0.62))
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
    }

    private var primaryFandom: String {
        series.fandoms.first ?? "Series"
    }

    private var seriesPalette: SubjectPalette {
        themeManager.appTheme.subjectPalette(
            hue: CoverArt.workHue(fandoms: series.fandoms, title: series.title)
        )
    }

    private var fandomColor: Color {
        let hue = CoverArt.workHue(fandoms: series.fandoms, title: series.title)
        return Color(hue: hue, saturation: 0.4, brightness: 0.9)
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

struct AO3AuthorBookmarkRow: View {
    let bookmark: AO3AuthorBookmark
    var expandAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AO3WorkRow(work: bookmark.work, expandAll: expandAll)

            if bookmark.isRecommendation || bookmark.isPrivate || !bookmark.date.isEmpty {
                FlowLayout(spacing: 8, rowSpacing: 5) {
                    if bookmark.isRecommendation {
                        WorkStateBadge(text: "Recommended", symbol: "hand.thumbsup.fill")
                    }
                    if bookmark.isPrivate {
                        WorkStateBadge(text: "Private", symbol: "lock.fill")
                    }
                    if !bookmark.date.isEmpty {
                        WorkStateBadge(text: bookmark.date, symbol: "calendar")
                    }
                }
                .font(.caption2)
            }

            if !bookmark.tags.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bookmark Tags")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    FlowLayout(spacing: 6, rowSpacing: 6) {
                        ForEach(bookmark.tags, id: \.self) { TagChip(text: $0) }
                    }
                }
            }

            if !bookmark.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bookmark Notes")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    AO3RichTextView(document: bookmark.notes)
                }
            }

            if !bookmark.collections.isEmpty {
                Label(bookmark.collections.joined(separator: ", "), systemImage: "square.stack")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AO3RichTextView: View {
    let document: AO3RichText
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
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
        .font(.body)
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

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
