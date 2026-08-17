import SwiftUI

// Building blocks for the redesigned Work Details hub: the work identity hero
// card, the Overview quick-action grid tile, and the pure label/state helpers
// behind them. Visual language matches the Account tab where the two hubs are
// playing the same role — the segmented section Picker uses Account's own
// `accountControlCardRow()` chrome, and `WorkQuickActionTile` shares
// `AccountShortcutGridTile`'s `CardRadius.tile` — but work-content cards
// (the hero, tag/status/stats sections) deliberately keep the Library's
// standard `.cardRow()` geometry instead, exactly as `AccountControlStyle.swift`
// documents ("Work cards deliberately retain the library's standard geometry").
// The two hubs are siblings in navigation-chrome, not in every card radius.

/// The four top-level Work Details sections, mirroring Account's
/// Overview / Reading / Writing / Activity segmented control.
enum WorkDetailTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case tags = "Tags"
    case discussion = "Discussion"
    case library = "Library"

    var id: String { rawValue }
}

/// The work identity hero card shown above the section control: title, tappable
/// author byline, fandoms, and the at-a-glance stat row. The full summary, tag
/// chips, and personal library state live in their sections, not here.
struct WorkDetailHeroCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var themeManager
    let title: String
    let authors: [String]
    let identities: [AO3AuthorIdentity]
    let fandoms: [String]
    let rating: String
    let categories: [String]
    let warnings: [String]
    let completion: WorkCompletionStatus
    let language: String
    let chapters: String
    let words: Int?
    /// Progress bar shown only when set — a work with no local reading state
    /// (remote-only, never opened) has nothing to show here, exactly like
    /// HomeResumeHero's own clamping only ever runs for a real `SavedWork`.
    var readingProgress: Double?
    var lastSpineIndex: Int = 0

    var body: some View {
        // Byte-for-byte the same card as HomeResumeHero.swift's
        // UnblurredHomeResumeHero — same background/border/shadow, same
        // VStack spacing and padding, same title/stat-row treatment — per
        // the owner's explicit "copy it exactly" request. This supersedes
        // the file header comment above (work-content cards keeping the
        // Library's `.cardRow()` geometry): that was a *prior* design
        // decision, not a hard constraint, and the owner asked for this one
        // specifically. `.cardRow()` was removed from this card's call site
        // in WorkDetailView.swift for the same reason — a self-contained
        // card inside another card's chrome would double up the background.
        let hue = CoverArt.hue(for: title)
        return VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.bold))
                .lineLimit(2)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            // `.caption`-sized, matching the "Continue Reading" hero's
            // author/fandom (WorkStatLabel) so the metadata reads as one
            // family instead of running a size larger here — see
            // HomeResumeHero.swift. Still a real Label (not WorkStatLabel):
            // author needs AO3AuthorBylineView's per-co-author tap
            // navigation, and fandoms need multi-line wrap (WorkStatLabel
            // forces a single fixed line).
            if !authors.isEmpty {
                // A real Label (not a hand-rolled HStack) so the icon lines up
                // with the Fandoms Label right below it — a raw HStack can't
                // reproduce Label's exact icon size/gap/baseline alignment.
                //
                // The `.font` has to be on the Label, not just inside the
                // byline: a Label sizes its icon from the *ambient* font, so
                // passing the font only to `AO3AuthorBylineView` left this
                // icon rendering at `.body` while the Fandoms icon below used
                // the Label's own font — two different glyph sizes on two
                // different baselines, which is exactly the column alignment
                // the comment above was trying to guarantee.
                Label {
                    AO3AuthorBylineView(
                        names: authors,
                        identities: identities,
                        includesBy: false,
                        font: .caption
                    )
                } icon: {
                    Image(systemName: "person")
                        .foregroundStyle(themeManager.effectiveTint)
                }
                .font(.caption)
            }

            if !fandoms.isEmpty {
                // Capped at 3 lines for density normally, but let the fandoms wrap
                // in full at accessibility Dynamic Type sizes — the title above
                // already wraps unlimited, and a 3-line clamp on scaled-up text
                // truncates fandom names to uselessness (HIG review UI-4, §5).
                Label(fandoms.joined(separator: ", "), systemImage: "books.vertical")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
            }

            // Same four-chip Rating/Pairings/Warnings/Completion row the
            // search-result cards show (WorkListStatsRow's top row) — see
            // HomeResumeHero.swift for the matching Home hero treatment.
            WorkTopStatsRow(
                rating: rating.isEmpty ? nil : rating,
                categories: categories,
                warnings: warnings,
                completion: completion
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            FlowLayout(spacing: 10, rowSpacing: 6) {
                if !language.isEmpty {
                    WorkStatLabel(text: language, symbol: "globe", accessibilityLabel: "Language: \(language)")
                }
                if let words {
                    WorkStatLabel(
                        text: words.formatted(),
                        symbol: "textformat.size",
                        accessibilityLabel: "\(words.formatted()) words"
                    )
                }
                if !chapters.isEmpty {
                    WorkStatLabel(text: chapters, symbol: "book", accessibilityLabel: "Chapters \(chapters)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            // Only the stat pills merge into one VoiceOver element. The card
            // itself must stay `.contain` so the byline's individually routed
            // co-author buttons remain separately focusable/activatable.
            .accessibilityElement(children: .combine)

            if let readingProgress {
                let progressValue = min(1, max(0, readingProgress))
                let percent = Int((progressValue * 100).rounded())
                let chapterLabel: String? = lastSpineIndex > 0 ? "Ch \(lastSpineIndex + 1)" : nil
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(chapterLabel ?? "Reading")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(percent)%")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule().fill(.tint)
                                .frame(width: geo.size.width * max(0.03, progressValue))
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
                .fill(themeManager.appTheme.carouselCardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
                        .fill(themeManager.appTheme.carouselCardTint(hue: hue))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CarouselCardMetrics.cornerRadius, style: .continuous)
                        .strokeBorder(themeManager.appTheme.carouselCardBorder(hue: hue), lineWidth: 0.5)
                )
                .shadow(color: themeManager.appTheme.carouselCardShadow.color,
                        radius: themeManager.appTheme.carouselCardShadow.radius,
                        x: 0,
                        y: themeManager.appTheme.carouselCardShadow.y)
        )
    }
}

/// One state-aware shortcut tile for the Overview quick-action grid. Same card
/// chrome as `AccountShortcutGridTile`; `detail` carries the current state
/// ("In 2 Queues"), and `isBusy` swaps the glyph for a spinner while a
/// download/import is in flight.
struct WorkQuickActionTile: View {
    @Environment(ThemeManager.self) private var theme

    let title: String
    let systemImage: String
    var detail: String?
    var isBusy = false

    private let cornerRadius: CGFloat = CardRadius.tile

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.tint)
                }
            }
            .frame(width: 36, height: 36)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 88)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(theme.appTheme.cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
                )
                .shadow(
                    color: theme.appTheme.cardShadow.color,
                    radius: theme.appTheme.cardShadow.radius,
                    x: 0,
                    y: theme.appTheme.cardShadow.y
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        // .combine (not .isButton) — this tile's only call site (quickAction(_:)
        // in WorkDetailOverviewSections.swift) already wraps it in a real Button,
        // which supplies the trait on its own; adding it again here doubled the
        // "Button" announcement (HIG audit UI-2).
        .accessibilityElement(children: .combine)
    }
}

/// Pure label/state derivations for the Work Details quick actions and Library
/// rows, extracted from the old single-list view so the moved logic stays
/// unit-testable.
enum WorkDetailPresentation {
    static func readAction(
        hasEPUB: Bool, working: Bool, continueReading: Bool = false
    ) -> (title: String, systemImage: String) {
        if working { return ("Downloading…", "arrow.down.circle") }
        guard hasEPUB else { return ("Download & Read", "arrow.down.circle") }
        return continueReading ? ("Continue Reading", "book") : ("Read", "book")
    }

    /// Compact tile labels for the keep-offline toggle. Menus use
    /// `WorkActionLabels.saved`'s full wording ("Download" / "Remove Download").
    static func savedAction(isSaved: Bool) -> (title: String, systemImage: String) {
        isSaved
            ? ("Downloaded", WorkActionLabels.downloadedSymbol)
            : ("Download", WorkActionLabels.downloadEmptySymbol)
    }

    /// Compact tile labels; the Library row uses `WorkActionLabels.savedForLater`'s
    /// full wording for the same toggle. Icons match that pair (clock, not bookmark).
    static func laterAction(isQueued: Bool) -> (title: String, systemImage: String) {
        let icons = WorkActionLabels.savedForLater(isQueued: isQueued)
        return (
            isQueued ? "Remove from Later" : "Save for Later",
            icons.systemImage
        )
    }

    static func queueLabel(count: Int) -> String {
        count == 0 ? "Add to Queue" : "In \(count) Queue\(count == 1 ? "" : "s")"
    }

    static func collectionLabel(count: Int) -> String {
        count == 0 ? "Add to Collection" : "In \(count) Collection\(count == 1 ? "" : "s")"
    }

    /// What the detail should do after "Remove from Later" possibly soft-deleted
    /// a queue-only record: keep showing the (still-live) local work, fall back
    /// to remote/AO3 state, or — only when there is nothing left to show — dismiss
    /// so the screen can't keep mutating a Recently Deleted record.
    enum PostRemovalAction: Equatable {
        case keepLocal
        case showRemote
        case dismiss
    }

    static func postRemovalAction(
        isPendingDeletion: Bool, hasRemoteSource: Bool
    ) -> PostRemovalAction {
        guard isPendingDeletion else { return .keepLocal }
        return hasRemoteSource ? .showRemote : .dismiss
    }

    /// Sparse AO3 blurb built from a local record so Work Details can stay open
    /// after a queue-only remove soft-deletes the local copy (opened from Library
    /// with no separate `remote` payload).
    static func summaryFromLocal(_ work: SavedWork) -> AO3WorkSummary? {
        guard let id = work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL) else {
            return nil
        }
        let authors = work.author
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return AO3WorkSummary(
            id: id,
            title: work.title,
            authors: authors,
            authorIdentities: work.verifiedAuthorIdentities,
            fandoms: work.workFandoms,
            rating: work.rating,
            warnings: work.workWarnings,
            categories: work.workCategories,
            relationships: work.workRelationships,
            characters: work.workCharacters,
            isComplete: work.isComplete,
            dateUpdated: work.dateUpdated,
            tags: work.workFreeforms,
            summary: work.summary,
            language: work.language,
            words: work.wordCount > 0 ? work.wordCount : nil,
            chapters: work.chapters,
            comments: work.comments > 0 ? work.comments : nil,
            kudos: work.kudos > 0 ? work.kudos : nil,
            bookmarks: work.bookmarks > 0 ? work.bookmarks : nil,
            hits: work.hits > 0 ? work.hits : nil,
            seriesTitle: work.seriesTitle.isEmpty ? nil : work.seriesTitle,
            seriesURL: work.seriesURL.isEmpty ? nil : work.seriesURL,
            seriesPosition: work.seriesPosition > 0 ? work.seriesPosition : nil
        )
    }

    /// Long summaries start collapsed behind a Show More affordance; short ones
    /// render in full with no extra control.
    static func summaryCollapses(_ summary: String) -> Bool {
        summary.count > 600
    }

    static func preservationStatusLabel(_ status: EPUBPreservationStatus) -> String {
        switch status {
        case .preserved: "Preserved offline"
        case .preserving: "Preserving…"
        case .queued: "Preservation queued"
        case .failed, .missingFile: "Needs restore"
        case .notPreserved: "Not preserved"
        }
    }

    /// On-disk EPUB size, formatted, or nil when the file doesn't exist.
    static func fileSizeLabel(forFileAt url: URL) -> String? {
        guard let value = try? FileManager.default.attributesOfItem(atPath: url.path)[.size],
              let bytes = (value as? NSNumber)?.int64Value
        else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
