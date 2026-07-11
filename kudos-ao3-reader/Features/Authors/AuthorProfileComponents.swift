import SwiftUI

struct AO3AuthorHero: View {
    let header: AO3AuthorHeader
    let route: AO3AuthorRoute
    let profileTitle: String
    let isOwnProfile: Bool
    let isPerformingSubscription: Bool
    let onSubscription: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AO3AuthorAvatar(url: header.identity.avatarURL, name: route.displayName)

            VStack(alignment: .leading, spacing: 5) {
                Text(route.displayName)
                    .font(.title2.weight(.semibold))
                    .lineLimit(3)
                    .minimumScaleFactor(0.75)
                    .accessibilityAddTraits(.isHeader)

                if let pseud = route.pseud {
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

                if let form = header.subscriptionForm,
                   !isOwnProfile,
                   !route.isOrphanAccount {
                    Button(action: onSubscription) {
                        Label(
                            form.isSubscribed ? "Unsubscribe" : "Subscribe",
                            systemImage: form.isSubscribed ? "bell.slash" : "bell"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isPerformingSubscription)
                    .overlay {
                        if isPerformingSubscription {
                            ProgressView().controlSize(.small)
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
    let series: AO3SeriesSummary

    var body: some View {
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
                    WorkStatLabel(text: words.formatted(), symbol: "textformat.size")
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
                .cardRow()
            }
            Section {
                SkeletonBlock(height: 34, cornerRadius: 7)
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
