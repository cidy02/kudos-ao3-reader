import OSLog
import SwiftData
import SwiftUI

/// A dedicated page listing every fandom in a media category (loaded from AO3's
/// `/media/<name>/fandoms` index). Sibling tags that share a parsed title are
/// grouped into families; tapping a family sends every raw original name as an
/// included fandom filter, never the parsed title.
struct FandomListView: View { // swiftlint:disable:this type_body_length
    let category: AO3MediaCategory
    /// `originalNames` are the raw AO3 tags to include. `title` is the works
    /// screen's navigation title (the original tag for a single fandom, the
    /// parsed title for a family) and is never sent as a filter.
    let onSelect: (_ originalNames: [String], _ title: String) -> Void

    /// The other half of the Browse zoom pair — set by BrowseView on the stack.
    @Environment(\.workCardTransitionNamespace) private var zoomNamespace
    @Environment(ThemeManager.self) private var themeManager
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }) private var library: [SavedWork]

    @State private var fandoms: [AO3Fandom] = []
    @State private var families: [FandomFamily] = []
    /// Pre-normalized haystacks so the live filter is a substring pass.
    @State private var searchEntries: [FamilySearchEntry] = []
    /// The rows the List renders. Refreshed by the debounced filter task instead
    /// of recomputed per keystroke render — re-diffing a many-thousand-row list
    /// on every letter was the other half of the freeze.
    @State private var filtered: [FandomFamily] = []
    @State private var phase: Phase = .loading
    @State private var query = ""
    @State private var sort: FandomFamilySort = .familyTotal
    @State private var filterOptions = FandomListFilterOptions()
    @State private var draftFilterOptions = FandomListFilterOptions()
    @State private var showingFilters = false
    @State private var exactCounts = FandomFamilyExactCountCache.shared

    private enum Phase: Equatable { case loading, loaded, failed(String) }

    private struct FamilySearchEntry: Sendable {
        let family: FandomFamily
        let haystack: String
    }

    private var palette: SubjectPalette {
        themeManager.appTheme.subjectPalette(hue: CoverArt.hue(for: category.name))
    }

    private var libraryIndex: FandomLibraryIndex {
        var favourites = Set<String>()
        var downloads = Set<String>()
        for work in library {
            let names = work.workFandoms.map { $0.lowercased() }
            if work.isFavorite { favourites.formUnion(names) }
            if work.isSaved { downloads.formUnion(names) }
        }
        return FandomLibraryIndex(
            favouriteNamesLowercased: favourites,
            downloadNamesLowercased: downloads
        )
    }

    /// Signature of everything `applyFilter` depends on besides the query debounce.
    private var listingToken: String {
        let favs = library.reduce(0) { $0 + ($1.isFavorite ? 1 : 0) }
        let saved = library.reduce(0) { $0 + ($1.isSaved ? 1 : 0) }
        return [
            query,
            sort.rawValue,
            "\(filterOptions.minimumWorks.rawValue)",
            "\(filterOptions.hideRPF)",
            "\(filterOptions.hideAllMediaTypes)",
            "\(filterOptions.hideRelatedFandoms)",
            "\(filterOptions.favouritedOnly)",
            "\(filterOptions.downloadsOnly)",
            "\(filterOptions.multiTagOnly)",
            "\(families.count)",
            "\(library.count):\(favs):\(saved)",
        ].joined(separator: "|")
    }

    /// Families the list draws, with cached exact unions applied so a family
    /// that has been opened drops its tilde.
    private var displayedFamilies: [FandomFamily] {
        filtered.map { $0.applyingExactCount(exactCounts.exactCount(for: $0.id)) }
    }

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
                loadedList
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
            .filterPanelPresentation(isPresented: $showingFilters) {
                FandomListFilterSheet(
                    options: $draftFilterOptions,
                    families: families,
                    library: libraryIndex,
                    palette: palette,
                    onApply: {
                        filterOptions = draftFilterOptions
                        showingFilters = false
                    },
                    onReset: { draftFilterOptions = FandomListFilterOptions() }
                )
                .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
            }
            .onChange(of: showingFilters) { _, isOpen in
                if isOpen { draftFilterOptions = filterOptions }
            }
            .task { if fandoms.isEmpty { await load() } }
    }

    private var loadedList: some View {
        List {
            Section {
                FandomListSortRail(
                    sort: $sort,
                    filterCount: filterOptions.activeFilterCount,
                    palette: palette,
                    onOpenFilters: { showingFilters = true }
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if sort == .alphabetical {
                ForEach(FandomFamily.letterSections(displayedFamilies)) { section in
                    Section {
                        ForEach(section.families) { family in
                            familyRow(family)
                        }
                    } header: {
                        FandomLetterHeader(
                            letter: section.letter,
                            count: section.families.count,
                            palette: palette
                        )
                    }
                }
            } else {
                ForEach(displayedFamilies) { family in
                    familyRow(family)
                }
            }
        }
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
        .toolbar { DefaultToolbarItem(kind: .search, placement: .bottomBar) }
        .task(id: listingToken) { await applyFilter() }
    }

    @ViewBuilder
    private func familyRow(_ family: FandomFamily) -> some View {
        if family.memberCount == 1, let member = family.members.first {
            Button {
                onSelect([member.originalName], member.originalName)
            } label: {
                FandomListRow(fandom: member.fandom)
            }
            .buttonStyle(.plain)
            .workCardZoomSource(BrowseZoomKey.fandom(member.originalName), in: zoomNamespace)
            .cardRow()
        } else {
            FandomFamilyBlock(
                family: family,
                palette: palette,
                onSelectFamily: {
                    onSelect(family.includedFilterNames, family.parsedTitle)
                },
                onSelectMember: { member in
                    onSelect([member.originalName], member.originalName)
                }
            )
            .cardRow()
        }
    }

    /// Debounced filter: coalesces a keystroke burst into one scan + one List
    /// diff. An emptied query restores the grouped list instantly (then filters
    /// and sort still apply).
    private func applyFilter() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            guard (try? await Task.sleep(for: .milliseconds(120))) != nil else { return }
        }
        let index = libraryIndex
        let haystackQuery = WorkSearchIndex.normalize(trimmed)
        var result = families
        if !haystackQuery.isEmpty {
            result = searchEntries.filter { $0.haystack.contains(haystackQuery) }.map(\.family)
        }
        result = FandomFamilyFilters.apply(result, options: filterOptions, library: index)
        filtered = FandomFamily.sorted(result, by: sort)
    }

    private func load() async {
        phase = .loading
        await refresh()
    }

    private func refresh() async {
        do {
            let list = try await AO3Client.shared.fandoms(atPath: category.fandomsURL)
            fandoms = list
            // Full-category grouping is tens of thousands of splits on Uncategorized
            // — same reason MediaBrowserView.computeStats is off the main actor.
            let grouped = await Task.detached(priority: .userInitiated) {
                FandomFamily.grouped(fandoms: list)
            }.value
            families = grouped
            searchEntries = grouped.map {
                FamilySearchEntry(family: $0, haystack: $0.searchHaystack())
            }
            await applyFilter()
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
    /// AO3 writes a multilingual fandom tag as `original | romanization |
    /// localized`. The last segment is the one an English-locale reader scans
    /// for, and the one `split` should see. Empty segments are dropped; a name
    /// with no `|` is its own primary.
    static func segments(of name: String) -> [String] {
        let parts = name
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? [name] : parts
    }

    static func primarySegment(of name: String) -> String {
        segments(of: name).last ?? name
    }

    static func aliasSegments(of name: String) -> [String] {
        Array(segments(of: name).dropLast())
    }

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
                // "what this is" followed by "what else it is called".
                //
                // One per line. These were joined with a middot to keep a row
                // short, but a stack is what a list of names wants: each is a
                // whole name, and reading them off a column beats picking them
                // out of a run separated by a character that also appears inside
                // titles. It costs a line on the 2,371 tags carrying two aliases
                // and nothing on the 140,537 carrying one or none.
                ForEach(Array(aliases.enumerated()), id: \.offset) { _, alias in
                    aliasText(alias)
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
                    Text(count.formatted())
                        .monospacedDigit()
                        // Fixed column, trailing-aligned. The digits are what the
                        // eye compares down the list, so they need a straight
                        // right edge; the column also keeps the block one width,
                        // which is what stops the name beside it ending in a
                        // different place on every row. Wide enough for AO3's
                        // largest fandoms (~700k) at this size.
                        .frame(minWidth: 58, alignment: .trailing)
                    // Trailing the number, and secondary rather than tinted: the
                    // glyph is the same on every row, so in accent red it competed
                    // with the name for attention while carrying no per-row
                    // information.
                    Image(systemName: "doc.text")
                        .font(.caption.weight(.semibold))
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
    private var nameParts: [String] { FandomDisplayName.segments(of: fandom.name) }

    private var primaryName: String { FandomDisplayName.primarySegment(of: fandom.name) }

    private var splitName: FandomName { FandomDisplayName.split(primaryName) }

    private var aliases: [String] { FandomDisplayName.aliasSegments(of: fandom.name) }

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
    private func aliasText(_ alias: String) -> Text {
        let name = Text(alias)
        return FandomScript.hasItalicForm(alias) ? name.italic() : name
    }

}
