import Foundation

/// The choices that identify a cover. No process-random hashing or UI state enters this value.
nonisolated struct GeneratedCoverRecipe: Equatable, Sendable {
    enum Ground: Int, Sendable { case gradient, split, band, solid, crossover }
    private(set) var hues: [Int]
    private(set) var lightness: Double
    private(set) var ground: Ground
    let motif: String
    let tier: Int
    private(set) var closedRing: Bool
    private(set) var hasRing: Bool
    private(set) var placement: Int
    let titleStyle: Int
    let rotation: Double
    let scale: Double
    let lineWidth: Double
    let opacity: Double
    let shapeSeed: UInt32
    let title: String
    let subtitle: String
    let author: String
    let fandom: String
    let part: Int
    private(set) var groundChroma: Double = 0.085

    private static let palette = [20, 55, 85, 125, 150, 180, 205, 230, 260, 290, 320, 350]
    private static let parents = ["Persuasion": "Jane Austen", "Pride and Prejudice": "Jane Austen",
                                  "Northanger Abbey": "Jane Austen", "Jane Eyre": "The Brontës"]
    private static let sourceHues = ["Jane Austen": 150, "The Brontës": 300,
                                     "Sherlock Holmes": 55, "Original Work": 220]
    private static let kinds = ["rings", "orbit", "contours", "sigil", "guilloche", "sprig",
                                "waves", "halftone", "truchet", "rosette", "sunburst",
                                "constellation", "chevrons", "moire", "squares", "petals"]
    private static let families = [
        "soft": ["petals", "sprig", "waves", "rosette"],
        "angular": ["chevrons", "squares", "sunburst", "sigil"],
        "orderly": ["truchet", "contours", "halftone", "moire"],
        "celestial": ["constellation", "orbit", "rings", "guilloche"]
    ]
    private static let tones = [
        "Fluff": "soft", "Domestic Fluff": "soft", "Romance": "soft", "Humor": "soft", "Slice of Life": "soft",
        "Angst": "angular", "Drama": "angular", "Horror": "angular", "Thriller": "angular",
        "Case Fic": "orderly", "Mystery": "orderly", "Politics": "orderly", "Character Study": "orderly",
        "Fantasy": "celestial", "Magic": "celestial", "Science Fiction": "celestial"
    ]
    private static let subtitlePattern = try! NSRegularExpression(pattern: #"^(.*\S)\s+(\(.*\)|\[.*\])$"#)
    // Approximate posting dates of well-known works and round-number IDs, supplied
    // by the orchestrator from memory on 2026-11-14 while AO3 was down; not verified
    // against AO3. A year of error shifts the 16-year, 0.14-lightness ramp by <0.01.
    // Fixed and monotone matters; changing these anchors changes the renderer version.
    private static let idYears: [(id: Int, year: Double)] = [
        (0, 2010.0), (540_000, 2012.8), (1_000_000, 2013.8), (5_000_000, 2015.8),
        (8_340_000, 2016.8), (10_060_000, 2017.2), (14_450_000, 2018.3),
        (20_000_000, 2019.6), (26_600_000, 2020.7), (34_500_000, 2021.8),
        (40_000_000, 2022.5), (50_000_000, 2023.7), (60_000_000, 2024.8),
        (72_000_000, 2026.0)
    ]

    static func hash(_ text: String) -> UInt32 {
        text.utf8.reduce(2_166_136_261) { ($0 ^ UInt32($1)) &* 16_777_619 }
    }

    private static func clean(_ fandom: String) -> String {
        var name = fandom.components(separatedBy: " - ").first ?? fandom
        for suffix in [" (TV)", " (Movies)", " (Comics)", " (Anime)", " & Related Fandoms"] {
            if name.hasSuffix(suffix) { name.removeLast(suffix.count) }
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func hue(_ fandom: String) -> Int {
        let source = parents[fandom] ?? fandom
        let base = sourceHues[source] ?? palette[Int(hash("source:" + source) % UInt32(palette.count))]
        return source == fandom ? base : base + (Int(hash("fandom:" + fandom) % 5) - 2) * 9
    }

    static func year(for id: Int?) -> Double {
        guard let id else { return 2018 }
        if id <= idYears[0].id { return idYears[0].year }
        for index in 1..<idYears.count where id < idYears[index].id {
            let lower = idYears[index - 1], upper = idYears[index]
            return lower.year + Double(id - lower.id) / Double(upper.id - lower.id) * (upper.year - lower.year)
        }
        return 2026
    }

    init(id: Int?, title: String, author: String, fandoms: [String], tags: [String] = [],
         words: Int? = nil, complete: Bool = true, seriesID: Int? = nil, part: Int = 0,
         salt: Int = 0, postedYear: Int? = nil, firstAuthor: String? = nil) {
        let names = fandoms.map(Self.clean).filter { !$0.isEmpty }
        let mainTitle = title.replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression)
        let titleParts = Self.splitTitle(mainTitle)
        self.title = titleParts.0
        subtitle = titleParts.1
        self.author = author
        fandom = names.joined(separator: " × ")
        self.part = part
        let fallback = Self.palette[Int(Self.hash("title:" + mainTitle) % UInt32(Self.palette.count))]
        hues = names.isEmpty ? [fallback] : names.enumerated().map { index, name in
            Self.hue(name) + (index == 0 && part > 0 ? (part - 1) * 18 : 0)
        }
        let year = postedYear.map(Double.init) ?? Self.year(for: id)
        lightness = Self.round2(0.32 + min(max((year - 2010) / 16, 0), 1) * 0.14)
        let authorHash = Self.hash("author:" + (firstAuthor ?? author.components(separatedBy: ", ").first ?? author))
        let selectedFamilies = Set(tags.compactMap { Self.tones[$0] })
        let workKey = String(id ?? Int(Self.hash("work:" + mainTitle + "|" + author)))
        let seriesKey = seriesID.map(String.init)
        let key = seriesKey ?? workKey + (salt == 0 ? "" : ":" + String(salt))
        motif = if let seriesKey {
            Self.kinds[Int(Self.hash("series-kind:" + seriesKey) % UInt32(Self.kinds.count))]
        } else if selectedFamilies.count == 1, let family = selectedFamilies.first, let choices = Self.families[family] {
            choices[Int(authorHash % 4)]
        } else {
            Self.kinds[Int((authorHash &+ UInt32(max(0, salt))) % UInt32(Self.kinds.count))]
        }
        titleStyle = Int((authorHash >> 5) % 3)
        placement = !subtitle.isEmpty ? 2 : self.title.count <= 16 ? 1 : 0
        tier = (words ?? 30_000) < 10_000 ? 0 : (words ?? 30_000) < 40_000 ? 1 : (words ?? 30_000) < 100_000 ? 2 : 3
        closedRing = complete
        hasRing = true
        shapeSeed = Self.hash((seriesKey == nil ? "shape:" : "series-shape:") + key)
        var random = Random(seed: Self.hash((seriesKey == nil ? "fine:" : "series-fine:") + key))
        let treatment = Ground(rawValue: random.integer(0, 3)) ?? .solid
        ground = names.count > 1 ? .crossover : treatment
        rotation = Self.round2((["sprig", "waves", "chevrons", "truchet", "halftone"].contains(motif)
                                ? random.between(-12, 12) : random.between(0, 360)))
        scale = Self.round2(random.between(0.85, 1.2))
        lineWidth = Self.round2(random.between(1, 1.5))
        opacity = Self.round2(random.between(0.4, 0.55))
    }

    init(collection name: String, identity: String? = nil, hue: Int, graphite: Bool = false) {
        let key = identity ?? name
        self.init(id: Int(Self.hash("collection:" + key)), title: name,
                  author: "collection:" + key, fandoms: [], complete: true)
        hues = [hue]
        lightness = 0.4
        ground = .gradient
        closedRing = false
        hasRing = false
        groundChroma = graphite ? 0.012 : 0.085
        placement = 0
    }

    static func collectionHue(_ hex: String?, fallback: Int) -> Int {
        collectionSwatch(hex, fallback: fallback).hue
    }

    static func collectionHue(for identity: UUID) -> Int {
        palette[Int(hash("collection:" + identity.uuidString) % UInt32(palette.count))]
    }

    static func collectionSwatch(_ hex: String?, fallback: Int) -> (hue: Int, chroma: Double) {
        guard let hex, hex.count == 7, hex.first == "#",
              let value = UInt32(hex.dropFirst(), radix: 16) else {
            let normalized = (fallback % 360 + 360) % 360
            let hue = palette.min { min(abs($0 - normalized), 360 - abs($0 - normalized))
                                  < min(abs($1 - normalized), 360 - abs($1 - normalized)) } ?? palette[0]
            return (hue, 0.085)
        }
        let channels = [16, 8, 0].map { shift -> Double in
            let v = Double((value >> shift) & 255) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let l = cbrt(0.4122214708 * channels[0] + 0.5363325363 * channels[1] + 0.0514459929 * channels[2])
        let m = cbrt(0.2119034982 * channels[0] + 0.6806995451 * channels[1] + 0.1073969566 * channels[2])
        let s = cbrt(0.0883024619 * channels[0] + 0.2817188376 * channels[1] + 0.6299787005 * channels[2])
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        if hypot(a, b) < 0.03 { return (260, 0.012) }
        let hue = (atan2(b, a) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        let snapped = palette.min { min(abs(Double($0) - hue), 360 - abs(Double($0) - hue))
                                  < min(abs(Double($1) - hue), 360 - abs(Double($1) - hue)) } ?? palette[0]
        return (snapped, 0.085)
    }

    private static func splitTitle(_ text: String) -> (String, String) {
        if let range = text.range(of: "; or, ") { return (String(text[..<range.lowerBound]), String(text[range.upperBound...])) }
        if let match = subtitlePattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let main = Range(match.range(at: 1), in: text),
           let subtitle = Range(match.range(at: 2), in: text) {
            return (String(text[main]), String(text[subtitle]))
        }
        return (text, "")
    }

    private static func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }

    struct Random {
        private var state: UInt32
        init(seed: UInt32) { state = seed }
        mutating func next() -> Double {
            state &+= 0x6D2B79F5
            var value = state
            value = (value ^ (value >> 15)) &* (value | 1)
            value ^= value &+ ((value ^ (value >> 7)) &* (value | 61))
            return Double(value ^ (value >> 14)) / 4_294_967_296
        }
        mutating func between(_ low: Double, _ high: Double) -> Double { low + next() * (high - low) }
        mutating func integer(_ low: Int, _ high: Int) -> Int { low + Int(next() * Double(high - low + 1)) }
    }
}

extension SavedWork {
    @MainActor
    var generatedCoverRecipe: GeneratedCoverRecipe {
        GeneratedCoverRecipe(id: ao3WorkID, title: title, author: author,
                             fandoms: workFandoms, tags: workTagsFetched ? workFreeforms : workTags,
                             words: wordCount,
                             complete: isComplete,
                             seriesID: ao3SeriesID ?? ReadingQueueService.ao3SeriesID(from: seriesURL),
                             part: seriesPosition,
                             firstAuthor: verifiedAuthorIdentities.first?.displayName)
    }
}

extension AO3WorkSummary {
    @MainActor
    var generatedCoverRecipe: GeneratedCoverRecipe {
        GeneratedCoverRecipe(id: id, title: title, author: authorText,
                             fandoms: fandoms, tags: tags, words: words,
                             complete: isComplete ?? true,
                             seriesID: seriesURL.flatMap { ReadingQueueService.ao3SeriesID(from: $0) },
                             part: seriesPosition ?? 0, firstAuthor: authors.first)
    }
}
