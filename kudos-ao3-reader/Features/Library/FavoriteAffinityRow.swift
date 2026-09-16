import SwiftUI

/// One aggregate row in Favorites' Authors / Fandoms / Tags scopes — artboards
/// **1ak**, **1bc** and **1bd**.
///
/// The spec draws the three scopes with the same row: an initial tile, the name,
/// one line of log facts, and a library line underneath saying what is still
/// unread. Keeping them one type rather than three means the initial, the spacing
/// and the "no unread works" wording cannot drift between scopes that sit one tap
/// apart.
struct FavoriteAffinityRow: View {
    let row: ReadingAffinities.Row
    let palette: SubjectPalette
    /// `#` for tags, the name's first letter for authors and fandoms — the spec's
    /// own distinction, and it is doing work: a tag's first letter is not a thing
    /// anyone sorts or scans by.
    var usesHashTile = false
    /// Authors (1ak) and tags (1bd) draw a circular tile; fandoms (1bc) draw a
    /// rounded square. Not derivable from `usesHashTile` — tags are circles *and*
    /// hashed, authors are circles and lettered, fandoms are squares and lettered.
    var usesCircularTile = true
    /// 1ak's "Newest work" block. Only the Authors scope has one: 1bc and 1bd draw
    /// no such block, and there is no per-fandom or per-tag equivalent to fetch.
    var newestWork: AO3WorkSummary?
    /// Whether `newestWork` is absent from what you have opened — 1ak's UNREAD tag.
    var isNewestWorkUnread = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            identityLine
            if let newestWork {
                SubjectRowSeparator(inset: 0)
                newestWorkBlock(newestWork)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .subjectCard(palette: palette)
        .combinedAccessibilityRow(accessibilityText)
    }

    private var identityLine: some View {
        HStack(alignment: .top, spacing: 11) {
            tile
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                    // Filled on every row of all three scopes, as the spec draws it:
                    // being on this page *is* the favourite. The explicit
                    // `ReadingFavorite` star is a separate axis nothing writes yet
                    // (`ReadingLogService.setFavorite` still has no callers), so this
                    // is not a toggle and does not pretend to be one.
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.subjectFavoriteGold)
                        .accessibilityHidden(true)
                }
                Text(logLine)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // 1ak's own label says these counts belong on the author's page
                // "rather than crowding the row", so this used to be hidden
                // whenever the newest-work block appeared. The owner overrode
                // that on 2026-09-15: Fandoms and Tags both keep the line, and
                // an Authors row that silently drops it reads as a different
                // kind of row rather than the same row with more on it.
                libraryLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 1ak's second half: what this author posted most recently, and whether you
    /// have opened it.
    private func newestWorkBlock(_ work: AO3WorkSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            // A dimmed uppercase label, not a `SubjectKicker`: the kicker is the
            // accent-coloured subject line with a rule under it, and this is a
            // section label inside a card the kicker's own rule would fight.
            Text("Newest work")
                .font(.system(size: 8.5, weight: .bold))
                .kerning(0.85)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 9) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(work.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                    Text(newestWorkMetadata(work))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isNewestWorkUnread {
                    Text("UNREAD")
                        .font(.system(size: 8.5, weight: .bold))
                        .kerning(0.6)
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(palette.chipFill)
                        )
                }
            }
            .contentShape(Rectangle())
            // A background link rather than a NavigationLink wrapping the content:
            // as a label it would restyle the block and draw a second chevron.
            // `LibraryView` already registers the `AO3WorkSummary` destination.
            .subjectRowNavigation(
                to: work,
                accessibilityLabel: "Open \(work.title)"
            )
        }
    }

    /// "Good Omens (TV) · updated 2 Sep 2026 · 12k words".
    ///
    /// The artboard reads **posted**. A works-page blurb carries one date and the
    /// parser stores it as `dateUpdated`, because that is the date AO3 prints
    /// there — so this says "updated". Naming it "posted" would be a label the app
    /// cannot stand behind, and the request is already pinned to the Date Posted
    /// *ordering* (see `AuthorNewestWorkStore`), which is the part that decides
    /// which work this is.
    private func newestWorkMetadata(_ work: AO3WorkSummary) -> String {
        var parts: [String] = []
        if let fandom = work.fandoms.first(where: { !$0.isEmpty }) {
            parts.append(fandom)
        }
        if !work.dateUpdated.isEmpty {
            parts.append("updated \(work.dateUpdated)")
        }
        if let words = work.words, words > 0 {
            parts.append("\(words.formatted(.number.notation(.compactName))) words")
        }
        return parts.joined(separator: " · ")
    }

    private var accessibilityText: String {
        var text = "\(row.name). \(logLine)."
        if let newestWork {
            text += " Newest work: \(newestWork.title), \(newestWorkMetadata(newestWork))."
            if isNewestWorkUnread { text += " Unread." }
        } else {
            text += " \(libraryText)"
        }
        return text
    }

    private var tile: some View {
        Text(usesHashTile ? "#" : String(row.name.prefix(1)).uppercased())
            .font(.system(size: 15, weight: .bold, design: usesHashTile ? .monospaced : .default))
            .foregroundStyle(palette.accent)
            .frame(width: 38, height: 38)
            .background(
                RoundedRectangle(
                    cornerRadius: usesCircularTile ? 19 : 11,
                    style: .continuous
                )
                .fill(palette.chipFill)
            )
            .accessibilityHidden(true)
    }

    /// Spec 1ak: "6 works read · 31h 12m · last read 4 Sep 2026". Each fact is
    /// dropped rather than zeroed when it has nothing to say — "0h 00m" on a row
    /// whose sessions predate the log is a wrong number, not a small one.
    private var logLine: String {
        var parts = ["\(row.worksRead) work\(row.worksRead == 1 ? "" : "s") read"]
        if row.totalSeconds > 0 {
            parts.append(ReadingInsights.durationLabel(row.totalSeconds))
        }
        if let lastRead = row.lastRead {
            parts.append("last read \(lastRead.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var libraryLine: some View {
        Text(libraryText)
            .font(.system(size: 11))
            .foregroundStyle(row.unreadInLibrary > 0 ? palette.accent : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Spec 1bd's second line, including its wording for the empty case: "No unread
    /// works · Everything tagged this way is finished". That sentence is the reason
    /// the line exists — it is the one that tells you there is nothing left here.
    private var libraryText: String {
        guard row.unreadInLibrary > 0 else {
            return "No unread works in your library"
        }
        var text = "\(row.unreadInLibrary) unread work\(row.unreadInLibrary == 1 ? "" : "s")"
        var extras: [String] = []
        if row.downloadedInLibrary > 0 { extras.append("\(row.downloadedInLibrary) downloaded") }
        if row.savedForLater > 0 { extras.append("\(row.savedForLater) in Saved for Later") }
        if !extras.isEmpty { text += " · " + extras.joined(separator: " · ") }
        return text
    }
}

/// 1ak's Authors row: `FavoriteAffinityRow` plus the newest-work line.
///
/// A wrapper rather than state on the row itself, because the newest work is a
/// network fact and only this scope has one — and because the list this sits in
/// is already at the Swift type checker's limit, so the `@State` and the `.task`
/// belong anywhere but there.
///
/// The parent list prefetches every registered author before it enables 1ak's
/// "With new work" filter. This wrapper reads that cache rather than issuing a
/// second, per-row request.
struct FavoriteAuthorRow: View {
    let row: ReadingAffinities.Row
    let palette: SubjectPalette
    /// AO3 work ids the reader has opened, for the UNREAD tag.
    let readWorkIDs: Set<Int>

    @Environment(AO3AuthService.self) private var auth

    var body: some View {
        let newestWork = cachedNewestWork
        FavoriteAffinityRow(
            row: row,
            palette: palette,
            newestWork: newestWork,
            isNewestWorkUnread: newestWork.map { !readWorkIDs.contains($0.id) } ?? false
        )
    }

    private var cachedNewestWork: AO3WorkSummary? {
        guard let username = row.username else { return nil }
        let scope = AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)
        guard let cached = AuthorNewestWorkStore.cached(username: username, scope: scope) else {
            return nil
        }
        return cached
    }
}
