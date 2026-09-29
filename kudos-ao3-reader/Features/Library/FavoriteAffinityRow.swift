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
    /// Which of 1ak / 1bc / 1bd this row is drawn for. The three share the row
    /// but not every line on it — the tile shape, the log line's wording, and
    /// where the library facts sit all follow the scope's own artboard.
    let scope: LibrarySectionListView.FavoriteScope
    /// 1ak's "Newest work" block. Only the Authors scope has one: 1bc and 1bd draw
    /// no such block, and there is no per-fandom or per-tag equivalent to fetch.
    var newestWork: AO3WorkSummary?
    /// Whether `newestWork` is absent from what you have opened — 1ak's UNREAD tag.
    var isNewestWorkUnread = false

    @Environment(AppRouter.self) private var router

    /// `#` for tags, the name's first letter for authors and fandoms — the spec's
    /// own distinction, and it is doing work: a tag's first letter is not a thing
    /// anyone sorts or scans by.
    private var usesHashTile: Bool { scope == .tags }
    /// Authors (1ak) and tags (1bd) draw a circular tile; fandoms (1bc) draw a
    /// rounded square.
    private var usesCircularTile: Bool { scope != .fandoms }

    /// 1ak's trailing chevron: "Counts, signal mix and the rest live in the
    /// author's own page". Nil for a byline with no registered account — an
    /// orphaned or anonymous work has no page to open, and a guessed URL is not one.
    private var authorRoute: AO3AuthorRoute? {
        guard scope == .authors, let username = row.username else { return nil }
        return AO3AuthorRoute(username: username)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            identityLine
            // 1bd puts the library facts in their own labelled block under a
            // hairline, the slot 1ak gives the newest work.
            if scope == .tags {
                SubjectRowSeparator(inset: 0)
                libraryBlock
            }
            if let newestWork {
                SubjectRowSeparator(inset: 0)
                newestWorkBlock(newestWork)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .subjectCard(palette: palette)
        .combinedAccessibilityRow(accessibilityText)
        // The row is one VoiceOver element, which hides the chevron's button;
        // this puts the same destination in the rotor.
        .accessibilityActions {
            if let authorRoute {
                Button("Open author page") { router.openAuthorProfile(authorRoute) }
            }
        }
    }

    private var identityLine: some View {
        HStack(alignment: .top, spacing: 11) {
            tile
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(.system(size: 16, weight: .semibold))
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
                // kind of row rather than the same row with more on it. Tags now
                // carry it as 1bd's labelled block below instead.
                if scope != .tags {
                    libraryLine
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let authorRoute {
                // A borderless button, not a link: the newest-work block below
                // already owns this row's background link, and a List row with
                // two would open whichever SwiftUI picked.
                Button {
                    router.openAuthorProfile(authorRoute)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .minimumHitTarget()
                .accessibilityLabel("Open author page")
            }
        }
    }

    /// 1bd: "In your library", then the unread count, then what of it is
    /// downloaded or waiting in Saved for Later.
    private var libraryBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("In your library")
                .font(.system(size: 8.5, weight: .bold))
                .kerning(0.85)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            let unread = row.unreadInLibrary
            Text(unread > 0 ? "\(unread) unread work\(unread == 1 ? "" : "s")" : "No unread works")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(unread > 0 ? palette.accent : Color.primary)
            if let libraryDetail {
                Text(libraryDetail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The spec's empty line reads "Everything tagged this way is finished", but
    /// no unread works only means every one has been *opened* — some may be
    /// mid-way — so this says the part the count can stand behind.
    private var libraryDetail: String? {
        row.unreadInLibrary > 0 ? libraryExtras : "Everything tagged this way has been opened"
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
            parts.append(FandomDisplayName.bareTitle(fandom))
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
        Text(usesHashTile ? "#" : Self.initials(row.name))
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

    /// Spec 1ak: "6 works read · 31h 12m · last read 4 Sep 2026"; 1bc adds
    /// "6 favorited" after the count, and 1bd reads "41 works read carry this
    /// tag". Each fact is dropped rather than zeroed when it has nothing to say —
    /// "0h 00m" on a row whose sessions predate the log is a wrong number, not a
    /// small one.
    private var logLine: String {
        var worksRead = "\(row.worksRead) work\(row.worksRead == 1 ? "" : "s") read"
        if scope == .tags {
            worksRead += row.worksRead == 1 ? " carries this tag" : " carry this tag"
        }
        var parts = [worksRead]
        if scope == .fandoms, row.favorited > 0 {
            parts.append("\(row.favorited) favorited")
        }
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

    /// The Authors and Fandoms rows' one-line form of 1bd's library facts, and
    /// every row's VoiceOver text. It says "no unread works" outright because that
    /// is the line that tells you there is nothing left here.
    private var libraryText: String {
        guard row.unreadInLibrary > 0 else {
            return "No unread works in your library"
        }
        let text = "\(row.unreadInLibrary) unread work\(row.unreadInLibrary == 1 ? "" : "s")"
        return libraryExtras.map { text + " · " + $0 } ?? text
    }

    /// "8 downloaded · 3 in Saved for Later", or nil when neither applies.
    private var libraryExtras: String? {
        var extras: [String] = []
        if row.downloadedInLibrary > 0 { extras.append("\(row.downloadedInLibrary) downloaded") }
        if row.savedForLater > 0 { extras.append("\(row.savedForLater) in Saved for Later") }
        return extras.isEmpty ? nil : extras.joined(separator: " · ")
    }
}

/// The Authors / Fandoms / Tags scopes' empty state.
///
/// `hiddenByFilter` distinguishes "you have read nothing" from "the active chip
/// matched none of the rows you do have". Without it an active "With new work"
/// told a reader with a full history that nothing had been read yet — the empty
/// state described a different list than the one that produced it.
struct FavoriteAffinityEmptyCard: View {
    let scope: LibrarySectionListView.FavoriteScope
    let hiddenByFilter: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(detail)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .subjectPanel()
    }

    /// Two chips can hide rows — Authors' "With new work" and Tags' "Unread
    /// works" — and each needs its own sentence about what it hid.
    private var hiddenByUnread: Bool { hiddenByFilter && scope == .tags }

    private var title: String {
        hiddenByUnread ? "No unread works" : hiddenByFilter ? "No new work" : "Nothing read yet"
    }

    private var detail: String {
        let noun = scope.title.lowercased()
        if hiddenByUnread {
            return "Every work in your library under these tags has been opened. Tap All to see them again."
        }
        if hiddenByFilter {
            return "None of these \(noun) has posted something you have not already read. "
                + "Tap All to see them again."
        }
        return "These are the \(noun) behind the works you have "
            + "actually read, ranked. They fill in as you read — there is nothing to star."
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
            scope: .authors,
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

extension FavoriteAffinityRow {
    /// 1bc's two-letter tiles: "GO" for Good Omens, "HA" for Haikyuu!!.
    static func initials(_ name: String) -> String {
        let words = name.split { !$0.isLetter && !$0.isNumber }
        let letters = words.count >= 2
            ? String(words[0].prefix(1)) + String(words[1].prefix(1))
            : String((words.first ?? Substring(name)).prefix(2))
        return letters.uppercased()
    }
}
