import OSLog
import SwiftUI

/// A dedicated page listing every fandom in a media category (loaded from AO3's
/// `/media/<name>/fandoms` index), sorted most-popular first with work counts and a
/// live filter. Tapping a fandom hands its name back to run a works search.
struct FandomListView: View {
    let category: AO3MediaCategory
    /// Called with the chosen fandom name; the host runs the search and pops back.
    let onSelect: (String) -> Void

    /// The other half of the Browse zoom pair — set by BrowseView on the stack.
    @Environment(\.workCardTransitionNamespace) private var zoomNamespace

    @State private var fandoms: [AO3Fandom] = []
    /// Names normalized once per load (`WorkSearchIndex.normalize`) so the live
    /// filter is a plain substring pass — a category holds up to tens of
    /// thousands of fandoms, and locale-collating every name on every keystroke
    /// (the old `localizedCaseInsensitiveContains` filter) froze typing.
    @State private var searchEntries: [FandomCatalog.SearchEntry] = []
    /// The rows the List renders. Refreshed by the debounced filter task instead
    /// of recomputed per keystroke render — re-diffing a many-thousand-row list
    /// on every letter was the other half of the freeze.
    @State private var filtered: [AO3Fandom] = []
    @State private var phase: Phase = .loading
    @State private var query = ""

    private enum Phase: Equatable { case loading, loaded, failed(String) }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                FandomRowSkeletonList()
            case let .failed(message):
                ContentUnavailableView {
                    Label("Couldn't load fandoms", systemImage: "wifi.slash")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            case .loaded:
                List(filtered) { fandom in
                    Button {
                        onSelect(fandom.name)
                    } label: {
                        FandomListRow(fandom: fandom)
                    }
                    .buttonStyle(.plain)
                    // This row is the source for the next hop: the works list it pushes
                    // zooms out of it. On the Button — the control that performs the
                    // navigation — for the same reason the category card marks its
                    // NavigationLink rather than the card nested inside it.
                    .workCardZoomSource(BrowseZoomKey.fandom(fandom.name), in: zoomNamespace)
                    .cardRow()
                }
                // Card-based list, matching the Media Browser it's pushed from.
                .cardList()
                // Here rather than inside `refresh()`, which `load()` also calls:
                // the initial load has nothing to invalidate and would only evict
                // other screens' entries. `/media/<x>/fandoms` is
                // `max-age=600, public`; it escapes the cache today only because
                // the index is megabytes and overflows `URLCache`'s per-entry
                // ceiling, which is a fact about AO3's page size, not about us.
                .refreshable {
                    await AO3Client.shared.invalidateCachedResponses()
                    await refresh()
                }
                .searchable(text: $query, prompt: "Search \(category.name)")
                // Floats the filter field in the bottom bar instead of the navigation
                // bar, matching Settings and the rest of iOS 26: on a long list your
                // thumb is already down there, and the field stops eating the top of
                // the content. `.searchable` still owns the field and its behaviour —
                // this only says where the system should put it.
                .toolbar { DefaultToolbarItem(kind: .search, placement: .bottomBar) }
                .task(id: query) { await applyFilter() }
            }
        }
        .navigationTitle(category.name)
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .hidesFloatingTabBar()
            // Zooms out of the category card that pushed it. Keyed on the same
            // `category.id` that card advertises — one String on both ends, so
            // there is no cross-type mismatch to get wrong here (see WorkZoomKey
            // for the one that bit the work cards).
            .workCardZoomDestination(BrowseZoomKey.category(category.id), in: zoomNamespace)
            .task { if fandoms.isEmpty { await load() } }
    }

    /// One pass over the precomputed normalized names — case- and
    /// diacritic-insensitive (matching Global Search's folding, so "pokemon"
    /// finds "Pokémon"), preserving the list's most-popular-first order.
    private func matchedFandoms(for trimmedQuery: String) -> [AO3Fandom] {
        guard !trimmedQuery.isEmpty else { return fandoms }
        let normalizedQuery = WorkSearchIndex.normalize(trimmedQuery)
        return searchEntries.filter { $0.normalizedName.contains(normalizedQuery) }.map(\.fandom)
    }

    /// Debounced filter: coalesces a keystroke burst into one scan + one List
    /// diff. An emptied query restores the full list instantly.
    private func applyFilter() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            filtered = fandoms
            return
        }
        // Sleep throws when a newer keystroke restarts the task — just stop.
        guard (try? await Task.sleep(for: .milliseconds(120))) != nil else { return }
        filtered = matchedFandoms(for: trimmed)
    }

    private func load() async {
        phase = .loading
        await refresh()
    }

    private func refresh() async {
        do {
            var list = try await AO3Client.shared.fandoms(atPath: category.fandomsURL)
            // Surface the biggest fandoms first; the index arrives alphabetically.
            list.sort { ($0.workCount ?? 0) > ($1.workCount ?? 0) }
            fandoms = list
            searchEntries = list.map {
                FandomCatalog.SearchEntry(normalizedName: WorkSearchIndex.normalize($0.name), fandom: $0)
            }
            // Re-apply any active filter against the fresh list right away — the
            // debounced task only reruns on query changes, not data changes.
            filtered = matchedFandoms(for: query.trimmingCharacters(in: .whitespaces))
            phase = .loaded
        } catch let error as AO3Error {
            if fandoms.isEmpty {
                phase = .failed(error.errorDescription ?? "Something went wrong.")
            } else {
                Log.network.notice("Fandom list refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        } catch {
            if fandoms.isEmpty {
                phase = .failed(error.localizedDescription)
            } else {
                Log.network.notice("Fandom list refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// Whether a name can be set in italic, or would only get a synthesized slant.
///
/// Italic is a Latin idea. CJK, Hangul, Thai, Hebrew and Arabic have no italic
/// form, so asking for one skews the upright glyphs mechanically — and on dense
/// CJK at caption size that blurs the strokes that distinguish characters. It is
/// also the majority case in AO3's index: 14,250 of the ~23,300 alias segments
/// are CJK against 6,143 Latin, so slanting everything would make most rows
/// harder to read in order to style a minority correctly.
///
/// Cyrillic and Greek are deliberately absent from the upright list: both have
/// real italics, and Cyrillic's is a different letterform rather than a slant.
enum FandomScript {
    private static let noItalicForm: [ClosedRange<Unicode.Scalar>] = [
        "\u{3000}" ... "\u{303F}", // CJK punctuation
        "\u{3040}" ... "\u{30FF}", // hiragana, katakana
        "\u{3400}" ... "\u{4DBF}", // CJK extension A
        "\u{4E00}" ... "\u{9FFF}", // CJK unified ideographs
        "\u{AC00}" ... "\u{D7AF}", // hangul syllables
        "\u{F900}" ... "\u{FAFF}", // CJK compatibility ideographs
        "\u{0E00}" ... "\u{0E7F}", // Thai
        "\u{0590}" ... "\u{05FF}", // Hebrew
        "\u{0600}" ... "\u{06FF}", // Arabic
    ]

    /// A name mixing scripts stays upright: half a slanted string reads as a
    /// rendering fault, and mixed names are common — "文豪ストレイドッグス" sits
    /// beside "Bungou Stray Dogs" in the same tag.
    static func hasItalicForm(_ text: String) -> Bool {
        !text.unicodeScalars.contains { scalar in
            noItalicForm.contains { $0.contains(scalar) }
        }
    }
}

/// Splits an AO3 fandom name into the part you scan for and the disambiguation
/// AO3 appends to keep tags unique.
///
/// Derived from AO3's own indexes rather than guessed: 144,866 fandoms across all
/// 11 media categories, from the app's own catalog cache. Two suffix conventions
/// cover them, and a name may carry both at once.
///
///   * A trailing parenthetical — "Naruto (Anime & Manga)", "DCU (Comics)",
///     "Se7en (1995)". 40.8% of names. Near-unambiguous.
///   * A trailing " - " — "One Piece - All Media Types", "Hamilton - Miranda",
///     "Stars of Chaos: Sha Po Lang - priest". 28.9% of names. The tail is a
///     medium, a creator, an author handle, or the literal word "Fandom"
///     (17,424 of them) — all the same job, so all demoted.
///   * A trailing " RPF". 2,394 names, and the only one with no separator.
///
/// Both are stripped, parenthetical first, because 5,560 names are the compound
/// "Title - Creator (Medium)" and peeling only one leaves half the suffix reading
/// as the title.
///
/// Two deliberate limits, both measured:
///
///   * A title that genuinely contains " - " has its tail greyed — "ef - a fairy
///     tale of the two." is one real title, not a title and a qualifier. Roughly
///     0.05% of names. A lowercase-tail guard was tried against the real index
///     and rejected: the 550 lowercase tails are overwhelmingly author handles
///     ("priest", "refrainbow", "heyitsJaki") that *should* be demoted, so the
///     guard cost far more than it fixed.
///   * The failure is cosmetic either way. The full name is still displayed,
///     still searched, and still what the works query receives.
/// One disambiguator peeled off a fandom tag, and which form it took.
///
/// Kinds name the *shape* the parser recognised, not a guaranteed meaning: a
/// `.parenthetical` is usually the medium ("(TV 2005)", "(Anime & Manga)") and a
/// `.creator` is usually an author or studio ("- J. K. Rowling"), but AO3 is a
/// folksonomy and neither is a promise.
nonisolated struct FandomQualifier: Hashable, Sendable {
    enum Kind: String, Hashable, Sendable, CaseIterable {
        case parenthetical
        case creator
        case rpf
        case allMediaTypes
        case relatedFandoms
        case fandomSuffix
    }

    let kind: Kind
    let text: String
}

/// A fandom tag split into the part worth reading big and the parts that only
/// disambiguate it.
///
/// The qualifiers stay a list rather than one joined string so a layout can put
/// the medium, the creator and the RPF marker in different places on a card.
/// 7,222 tags carry two or more, and `qualifier` renders them the way the list
/// row does today: in the order they appeared in the original name.
nonisolated struct FandomName: Hashable, Sendable {
    /// The tag exactly as AO3 spells it. Splitting is deliberately not reversible:
    /// `tidied` eats the delimiter it cut against, so "Digimon Adventure: (Anime
    /// 2020)" loses its colon and the Japanese subtitle convention in "The Hundred
    /// Line -Last Defense Academy- (Video Game)" loses its closing dash. 1,519 tags
    /// (1.6%) do not survive a title + qualifier round trip, so anything that needs
    /// the real name — a search query, a cache key — reads this rather than
    /// rebuilding one. `parts` is for laying the name out, not for reassembling it.
    let original: String
    let title: String
    /// In the order they appear in `original`, left to right: the rules peel from
    /// the end, and each peel is inserted at the front to undo that.
    let parts: [FandomQualifier]
    /// Stored, not computed: the list row reads this on every row it draws, and a
    /// category holds tens of thousands of fandoms.
    let qualifier: String

    init(original: String, title: String, parts: [FandomQualifier]) {
        self.original = original
        self.title = title
        self.parts = parts
        qualifier = parts.map(\.text).joined(separator: " ")
    }
}

enum FandomDisplayName {
    /// Closing brackets that can end a qualifier, either width. The fullwidth
    /// pair is the same convention on CJK names — （电子游戏）, （电视）, （漫画）.
    ///
    /// Openers are searched independently of the closer rather than as fixed
    /// pairs: 16 names in the index mix the widths ("BLEACH(Anime&Manga）",
    /// "第三日（原创作品)"), and a pair list would either miss those or bind an
    /// opener of the wrong width that happens to sit earlier in the name.
    ///
    /// `《》`, `【】`, `「」`, `[]` are deliberately absent. Their use in the index
    /// mixes whole-title wrappers (《病案本》), furigana (`炎の蜃気楼[ミラージュ]`)
    /// and ad-hoc metadata, so no one reading of them is safe.
    private static let closingBrackets: Set<Character> = [")", "）"]

    /// Every spaced dash that appears as a separator in the index, including
    /// U+2010 HYPHEN, which is visually identical to a hyphen-minus and shows up
    /// in three names ("Dreaming of Sunshine ‐ Silver Queen").
    private static let separators = [" - ", " – ", " — ", " ‐ "]

    /// The dash characters that can glue a suffix on with no space around it.
    private static let dashes: Set<Character> = ["-", "–", "—", "‐"]

    /// The media-umbrella phrase, in the five spellings the index actually uses.
    /// Named outright rather than left to the dash rule because it is the single
    /// most common tail (18k names) and appears attached by delimiters the dash
    /// rule does not recognise — "Digimon: All Media Types", "Hulk-All Media
    /// Types", "刺客信条-所有媒体类型".
    ///
    /// Measured, not guessed: Simplified 8, Traditional 1 + 1 (two variants),
    /// Portuguese 5, Spanish 5. No speculative translations — an unused spelling
    /// is a rule nobody can test.
    private static let mediaUmbrellas = [
        "All Media Types",
        "所有媒体类型",
        "所有媒體類型",
        "所有媒體型別",
        "Todos os Tipos de Mídia",
        "Todos los tipos de medios",
    ]

    /// The umbrella-grouping tail, with its leading separator included in the
    /// needle. That leading space is load-bearing: it keeps `Eason-Related
    /// Fandoms` and `Chinese Related Fandoms` — which are titles, not grouped
    /// tags — out of the rule.
    private static let relatedFandoms = [" & Related Fandoms", " and Related Fandoms"]

    /// Debris a peeled suffix leaves on the end of the title: "classmates - RPF"
    /// would otherwise render as "classmates -", and "Digimon: All Media Types"
    /// as "Digimon:".
    private static let debris = CharacterSet(charactersIn: " -–—‐:")

    /// A suffix a rule was able to cut off: what is left of the title, and the
    /// piece that came away.
    private typealias Peel = (head: String, qualifier: String)

    /// One suffix convention: what to call it when it fires, which kind of
    /// qualifier it produces, and how to cut it off.
    private struct Rule {
        let name: String
        let kind: FandomQualifier.Kind
        let cut: (String) -> Peel?
    }

    static func split(_ name: String) -> FandomName {
        var title = name.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return FandomName(original: name, title: name, parts: []) }

        // Names whose dash tail is really part of the title — "InuYasha - A
        // Feudal Fairy Tale", "Dragon Age: Origins - Awakening". Nothing in the
        // string says so; it takes knowing the work, which is why this is a list
        // rather than a rule (three general rules were measured and rejected —
        // see discussions/fandom-name-disambiguation.md).
        //
        // It disables ONLY the dash rule, not the whole function. A listed name
        // can still carry a perfectly ordinary suffix of another kind:
        // "Ich bin ein Star - Holt mich hier raus! (Germany TV)" keeps its dash
        // tail and should still lose "(Germany TV)". Returning early here — the
        // first version of this — left both bold.
        //
        // Matched on the trimmed primary, which is the string the agents judged,
        // rather than on whatever a bracket rule leaves behind. Fail-open: an
        // unlisted name gets every rule, so the worst an incomplete list can do
        // is today's behaviour.
        let keepsDashTail = FandomDisplayExceptions.keepWhole.contains(title)

        var qualifiers: [FandomQualifier] = []

        // Each form appears at most once, but they stack in any order, so the
        // rules run in a loop with a fired-flag each rather than a single pass.
        //
        // The loop is what catches "Political RPF - US 21st c.", where the RPF
        // is only exposed once the dash tail comes off — a single pass left 62
        // titles still ending in "RPF". The flags are what stop it running away:
        // an unguarded loop also peeled a title's *own* parenthetical on the
        // second turn, turning "Ellie and Abbie (and Ellie's Dead Aunt) (2020)"
        // into "Ellie and Abbie". A second bracket or dash belongs to the title.
        //
        // Order is load-bearing in one place: the parenthetical must be tried
        // before the dash tail, or "À Tout le Monde (Set Me Free) - Megadeth
        // (Music Video)" loses the parenthetical belonging to its title on the
        // next turn.
        var taken = Set<String>()
        var rules: [Rule] = [
            Rule(name: "relatedFandoms", kind: .relatedFandoms, cut: takeRelatedFandoms),
            Rule(name: "rpf", kind: .rpf, cut: takeRPF),
            Rule(name: "mediaUmbrella", kind: .allMediaTypes, cut: takeMediaUmbrella),
            Rule(name: "bracket", kind: .parenthetical, cut: takeBracket),
            Rule(name: "separator", kind: .creator, cut: takeSeparator),
            Rule(name: "gluedFandom", kind: .fandomSuffix, cut: takeGluedFandom),
        ]
        if keepsDashTail {
            rules.removeAll { $0.name == "separator" }
        }

        for _ in 0 ..< rules.count {
            let before = title
            for rule in rules where !taken.contains(rule.name) {
                guard let peel = rule.cut(title), !peel.head.isEmpty else { continue }
                qualifiers.insert(FandomQualifier(kind: rule.kind, text: peel.qualifier), at: 0)
                title = peel.head
                taken.insert(rule.name)
            }
            if title == before { break }
        }

        return FandomName(original: name, title: title, parts: qualifiers)
    }

    /// Umbrella grouping. Tried first because it sits outside everything else —
    /// "Bridgerton (TV) & Related Fandoms" only exposes its "(TV)" once this is
    /// gone. Backwards, so "Spirou & Fantasio & Related Fandoms" keeps the
    /// ampersand belonging to the series.
    private static func takeRelatedFandoms(_ title: String) -> Peel? {
        for needle in relatedFandoms {
            guard let range = title.range(of: needle, options: [.caseInsensitive, .backwards]),
                  range.upperBound == title.endIndex else { continue }
            return (
                tidied(String(title[title.startIndex ..< range.lowerBound])),
                String(title[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
            )
        }
        return nil
    }

    /// Real Person Fiction. No leading space required: 47 names glue it on
    /// ("hetamyuRPF", "中国音乐剧演员RPF", "真人rpf"), and across all 144,866 the
    /// only Latin-letter-preceded match is hetamyuRPF, which genuinely is RPF.
    /// A bare "RPF" survives on the empty-head guard in `split`.
    private static func takeRPF(_ title: String) -> Peel? {
        guard let range = title.range(of: "RPF", options: [.caseInsensitive, .backwards]),
              range.upperBound == title.endIndex else { return nil }
        let head = tidied(String(title[title.startIndex ..< range.lowerBound]))
        // For most tags the RPF is a suffix on a fandom that exists without it —
        // "Harry Potter RPF" leaves "Harry Potter", which is a fandom. For the
        // umbrella tags it is the name itself: stripping "Sports RPF" left a bold
        // "Sports", which names nothing anyone writes for. 1,477 tags, 1.46M works.
        //
        // Membership is corpus-derived, not hand-listed — a head counts as a real
        // fandom only if non-RPF tags sharing it hold works of their own. See
        // Scripts/fandom-audit/gen-umbrellas.py. Keyed on the head as this rule
        // sees it, which is not always the final title: RPF is peeled before the
        // bracket, so "Super Sketch Show (TV) RPF" arrives here still carrying its
        // "(TV)". Fail-open — an unlisted head strips exactly as it always did.
        guard !FandomUmbrellas.rpfKeepAttached.contains(head) else { return nil }
        return (head, String(title[range.lowerBound...]).trimmingCharacters(in: .whitespaces))
    }

    private static func takeMediaUmbrella(_ title: String) -> Peel? {
        for umbrella in mediaUmbrellas {
            guard let range = title.range(of: umbrella, options: [.caseInsensitive, .backwards]),
                  range.upperBound == title.endIndex else { continue }
            return (
                tidied(String(title[title.startIndex ..< range.lowerBound])),
                "- " + String(title[range.lowerBound...])
            )
        }
        return nil
    }

    /// Trailing parenthetical. The opener is the later of the two widths, so a
    /// mixed pair binds correctly; `lastIndex` also means a title carrying its
    /// own parenthetical keeps it. A closer with no opener at all is title —
    /// the band "Sunn O)))".
    private static func takeBracket(_ title: String) -> Peel? {
        guard let last = title.last, closingBrackets.contains(last),
              let open = [title.lastIndex(of: "("), title.lastIndex(of: "（")].compactMap({ $0 }).max()
        else { return nil }
        return (tidied(String(title[title.startIndex ..< open])), String(title[open...]))
    }

    /// Dash tail, last separator wins so "Spider-Man - All Media Types" keeps
    /// its hyphenated title.
    private static func takeSeparator(_ title: String) -> Peel? {
        guard let separator = separators
            .compactMap({ title.range(of: $0, options: .backwards) })
            .max(by: { $0.lowerBound < $1.lowerBound })
        else { return nil }
        let tail = String(title[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !tail.isEmpty else { return nil }
        return (tidied(String(title[title.startIndex ..< separator.lowerBound])), "- " + tail)
    }

    /// "Fandom" glued on with a dash and no spacing the separator rule
    /// recognises — "The Expanse-Fandom", "杀死你的旅程—Fandom", "Jinkx Monsoon-
    /// Fandom". Deliberately last, so a properly spaced " - " still wins, and
    /// deliberately narrow: an unspaced dash followed by anything at all would
    /// eat real subtitles like "「云熠」对家总裁有点怪-办公室篇". Requiring the dash
    /// also leaves "Pizza Fandom" alone.
    private static func takeGluedFandom(_ title: String) -> Peel? {
        guard let range = title.range(of: "Fandom", options: [.caseInsensitive, .backwards]),
              range.upperBound == title.endIndex else { return nil }
        let beforeWord = String(title[title.startIndex ..< range.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        guard let joiner = beforeWord.last, dashes.contains(joiner) else { return nil }
        let head = tidied(beforeWord)
        // Same shape as the RPF umbrellas: "Multi-Fandom" marks a crossover, and
        // there is no fandom called "Multi", so peeling left a bold stub naming
        // nothing across 6,659 works. Corpus-derived, same rule and threshold.
        guard !FandomUmbrellas.fandomKeepAttached.contains(head) else { return nil }
        return (head, "- " + String(title[range.lowerBound...]))
    }

    /// Trims separator debris off a freshly-peeled title. Only ever applied to a
    /// head the parser just cut, never to a whole name — so the Japanese
    /// "-Subtitle-" convention ("Lamento -BEYOND THE VOID-", 42 names) keeps its
    /// closing dash, because nothing was peeled off it in the first place.
    private static func tidied(_ text: String) -> String {
        var out = text.trimmingCharacters(in: .whitespaces)
        while let last = out.unicodeScalars.last, debris.contains(last) {
            out.unicodeScalars.removeLast()
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}

private struct FandomListRow: View {
    let fandom: AO3Fandom

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                // Three tiers, each on its own line and each a step quieter than
                // the one above. The title used to carry its qualifier inline to
                // save a line, but that let a long name wrap mid-qualifier —
                // "My Hero Academia (Anime" / "& Manga)" — which is the worst
                // thing a row can do to a name you are trying to read.
                Text(splitName.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                // The disambiguation. Below rather than beside, so the title
                // owns its line; also lines the qualifiers up in a column, which
                // is how you tell 23 versions of Les Misérables apart.
                if !splitName.qualifier.isEmpty {
                    Text(splitName.qualifier)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // The other names this fandom is tagged under. A tier below the
                // qualifier rather than level with it: 13% of rows show both, and
                // in matching styles they read as one blurred block instead of
                // "what this is" followed by "what else it is called". Joined
                // rather than stacked so a three-name tag costs one line, not two.
                if !aliases.isEmpty {
                    aliasText
                        .font(.caption)
                        // Size carries the tier, not colour. `.tertiary` here was
                        // ~3:1 against every card surface — under WCAG AA, and
                        // worst on dense CJK, where 12pt kanji strokes blur
                        // together at that contrast.
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let count = fandom.workCount {
                HStack(spacing: 4) {
                    // Secondary, not tinted: the glyph is the same on every row,
                    // so in accent red it competed with the name for attention
                    // while carrying no per-row information.
                    Image(systemName: "doc.text")
                        .font(.caption.weight(.semibold))
                    Text(count.formatted())
                        .monospacedDigit()
                        // Fixed column, trailing-aligned: without it the glyph
                        // slides left or right with the digit count and no two
                        // rows line up. Wide enough for AO3's largest fandoms
                        // (~700k) at this size.
                        .frame(minWidth: 58, alignment: .trailing)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel("\(count.formatted()) works")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// AO3 writes a multilingual fandom tag as `original | romanization |
    /// localized` — "僕のヒーローアカデミア | Boku no Hero Academia | My Hero
    /// Academia (Anime & Manga)" — so the last segment is the one an
    /// English-locale reader is scanning for. Single-segment tags ("Marvel")
    /// are their own primary and have no aliases.
    private var nameParts: [String] {
        let parts = fandom.name
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? [fandom.name] : parts
    }

    private var primaryName: String { nameParts[nameParts.count - 1] }

    private var splitName: FandomName { FandomDisplayName.split(primaryName) }

    private var aliases: [String] { Array(nameParts.dropLast()) }

    /// The other names, set in italic — the convention for a foreign name in an
    /// English-language list — but only where the script actually has one.
    ///
    /// Italic is a Latin idea. CJK, Hangul, Thai, Hebrew and Arabic have no
    /// italic form, so asking for one gets a synthesized oblique: the upright
    /// glyphs mechanically skewed. On dense CJK at caption size that blurs the
    /// strokes you need to tell characters apart, which is the same legibility
    /// budget the colour choice above is already spending carefully. It is also
    /// the majority case — 14,250 of the ~23,300 alias segments in the index are
    /// CJK, against 6,143 Latin — so slanting everything would make most of these
    /// rows harder to read in order to style a minority correctly.
    ///
    /// Cyrillic keeps the italic: it has a real one, and a genuinely different
    /// letterform rather than a slant.
    private var aliasText: Text {
        aliases.enumerated().reduce(Text(verbatim: "")) { running, entry in
            let (index, alias) = entry
            let separator = index == 0 ? Text(verbatim: "") : Text(verbatim: " · ")
            let name = Text(alias)
            return running + separator + (FandomScript.hasItalicForm(alias) ? name.italic() : name)
        }
    }

}
