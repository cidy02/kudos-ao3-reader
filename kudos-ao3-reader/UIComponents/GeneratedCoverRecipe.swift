import Foundation

/// The choices that identify a cover. No process-random hashing or UI state enters this value.
nonisolated struct GeneratedCoverRecipe: Codable, Equatable, Sendable {
    enum Ground: Int, Codable, Sendable { case gradient, split, band, solid, crossover }
    let rendererVersion: Int
    let salt: Int
    var pinnedAt: Double?
    private(set) var hues: [Int]
    private(set) var lightness: Double
    private(set) var ground: Ground
    let motif: String
    /// `private(set)` so a metadata refresh can move length tier without re-resolving the pin.
    private(set) var tier: Int
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

    var isDrawable: Bool {
        !hues.isEmpty && (0...3).contains(tier) && (0...2).contains(placement)
            && (0..<Int.max).contains(salt)
    }

    private struct PinTime: Decodable { let pinnedAt: Double? }

    static func pinnedAt(in json: String?, now: Date = Date()) -> Date? {
        guard let json, let time = try? JSONDecoder().decode(PinTime.self, from: Data(json.utf8)).pinnedAt,
              time.isFinite else { return nil }
        return KudosBackupContents.clampedArchiveDate(Date(timeIntervalSince1970: time), now: now)
    }

    /// The stored form of a pin. Sorted keys, so one recipe always encodes to the same string: `JSONEncoder`'s
    /// key order is not fixed, and restore breaks ties between pins by comparing these strings.
    static func encodedPin(_ recipe: GeneratedCoverRecipe) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(recipe) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Rewrites `pinnedAt` on a decodable renderer-1 recipe and leaves every other byte alone.
    /// Undecodable JSON and newer renderers pass through; those are not this build's to edit.
    static func clampingFuturePinIfSupported(_ json: String, now: Date = Date()) -> String {
        guard let recipe = supportedPin(in: json), let rawTime = recipe.pinnedAt, rawTime.isFinite else {
            return json
        }
        let ceiling = now.addingTimeInterval(KudosBackupContents.maxFutureTimestampSkew).timeIntervalSince1970
        guard rawTime > ceiling else { return json }
        if let replaced = replacingPinnedAt(in: json, with: ceiling) { return replaced }
        var clamped = recipe
        clamped.pinnedAt = ceiling
        return encodedPin(clamped) ?? json
    }

    static func isAutomaticPin(in json: String?) -> Bool {
        pinnedAt(in: json) == Date(timeIntervalSince1970: 0)
    }

    /// A recipe this build may draw and rewrite. Newer renderers and unknown keys are not supported,
    /// even when the decoder would ignore them. Float spelling is not a newer schema: JSONSerialization
    /// rewrites `0.085` so an `NSDictionary` round trip rejects a perfectly decodable renderer-1 pin.
    static func supportedPin(in json: String) -> GeneratedCoverRecipe? {
        let data = Data(json.utf8)
        guard let recipe = try? JSONDecoder().decode(Self.self, from: data),
              recipe.rendererVersion == 1, recipe.isDrawable,
              let original = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var keyed = recipe
        keyed.pinnedAt = 0
        guard let encoded = try? JSONEncoder().encode(keyed),
              let known = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any],
              Set(original.keys).subtracting(known.keys).isEmpty else { return nil }
        return recipe
    }

    /// Splices one JSON number over the `pinnedAt` value and leaves every other byte in place.
    private static func replacingPinnedAt(in json: String, with time: Double) -> String? {
        guard time.isFinite, let number = jsonNumber(time),
              let regex = try? NSRegularExpression(
                pattern: #""pinnedAt"\s*:\s*-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?"#
              ),
              let match = regex.firstMatch(in: json, range: NSRange(json.startIndex..., in: json)),
              let range = Range(match.range, in: json) else { return nil }
        return json.replacingCharacters(in: range, with: "\"pinnedAt\":\(number)")
    }

    private static func jsonNumber(_ value: Double) -> String? {
        guard value.isFinite,
              let data = try? JSONSerialization.data(withJSONObject: [value]),
              var text = String(data: data, encoding: .utf8) else { return nil }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2, text.first == "[", text.last == "]" else { return nil }
        return String(text.dropFirst().dropLast())
    }

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

    /// Cover-Spec §3: the fandom's bare name ("Doctor Who (2005)" → "Doctor Who", "Frozen (Disney
    /// Movies)" → "Frozen", "- All Media Types" dropped). The app's one rule for that, shared with the
    /// fandom lists, so a cover and a fandom card never name the same fandom differently.
    private static func clean(_ fandom: String) -> String {
        FandomDisplayName.bareTitle(fandom).trimmingCharacters(in: .whitespacesAndNewlines)
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
        rendererVersion = 1
        self.salt = salt
        pinnedAt = nil
        // Two tags that name one fandom ("Doctor Who (2005)" and "Doctor Who") are one fandom on
        // a cover: no repeated label, no crossover split between identical colours.
        var seen = Set<String>()
        let names = fandoms.map(Self.clean).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
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
        let key = (seriesKey ?? workKey) + (salt == 0 ? "" : ":" + String(salt))
        motif = if let seriesKey {
            Self.kinds[Int(Self.hash("series-kind:" + seriesKey) % UInt32(Self.kinds.count))]
        } else if selectedFamilies.count == 1, let family = selectedFamilies.first, let choices = Self.families[family] {
            choices[Int(authorHash % 4)]
        } else {
            Self.kinds[Int((authorHash &+ UInt32(max(0, salt))) % UInt32(Self.kinds.count))]
        }
        titleStyle = Int((authorHash >> 5) % 3)
        placement = !subtitle.isEmpty ? 2 : self.title.count <= 16 ? 1 : 0
        tier = Self.tier(for: words ?? 30_000)
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

    static func tier(for words: Int) -> Int {
        words < 10_000 ? 0 : words < 40_000 ? 1 : words < 100_000 ? 2 : 3
    }

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

extension GeneratedCoverRecipe {
    /// Length tier and the completion ring, without re-resolving hue, motif, or fandom.
    func updating(tier: Int, closedRing: Bool) -> GeneratedCoverRecipe {
        var copy = self
        copy.tier = tier
        copy.closedRing = closedRing
        return copy
    }
}

extension SavedWork {
    @MainActor
    var generatedCoverRecipe: GeneratedCoverRecipe {
        if let coverRecipeJSON, let pinned = GeneratedCoverRecipe.supportedPin(in: coverRecipeJSON) {
            return pinned
        }
        return resolvedCover(salt: 0)
    }

    @MainActor
    var coverTier: Int { GeneratedCoverRecipe.tier(for: wordCount) }

    @MainActor
    func pinCover(salt: Int? = nil, automatic: Bool = false) {
        let existing = coverRecipeJSON.flatMap(GeneratedCoverRecipe.supportedPin(in:))
        if coverRecipeJSON != nil, existing == nil { return }
        var recipe = resolvedCover(salt: salt ?? existing?.salt ?? 0)
        let previousTime = existing?.pinnedAt
        if var current = existing {
            current.pinnedAt = nil
            if current == recipe { return }
        }
        let now = Date()
        if automatic {
            let preserved = previousTime.flatMap { time -> Double? in
                guard time.isFinite, time > 0 else { return nil }
                return KudosBackupContents.clampedArchiveDate(
                    Date(timeIntervalSince1970: time), now: now
                ).timeIntervalSince1970
            }
            recipe.pinnedAt = preserved ?? 0
        } else {
            let ceiling = now.addingTimeInterval(KudosBackupContents.maxFutureTimestampSkew).timeIntervalSince1970
            let nextPrevious = previousTime.flatMap { time -> Double? in
                guard time.isFinite else { return nil }
                let clamped = KudosBackupContents.clampedArchiveDate(
                    Date(timeIntervalSince1970: time), now: now
                ).timeIntervalSince1970
                let stepped = clamped.nextUp
                return stepped.isFinite ? stepped : nil
            }
            let candidate = max(now.timeIntervalSince1970, nextPrevious ?? 0)
            // `ceiling.nextUp` is still above the skew limit. Never persist that.
            recipe.pinnedAt = min(candidate, ceiling)
        }
        guard let json = GeneratedCoverRecipe.encodedPin(recipe) else { return }
        coverRecipeJSON = json
        FolderSyncService.markDirty()
        NotificationCenter.default.post(name: .kudosSyncRelevantSettingChanged, object: nil)
    }

    @MainActor
    func refreshCoverIfNeeded() {
        guard let coverRecipeJSON, let pinned = GeneratedCoverRecipe.supportedPin(in: coverRecipeJSON),
              (!pinned.closedRing && isComplete) || pinned.tier != coverTier else { return }
        pinCover(salt: pinned.salt, automatic: (pinned.pinnedAt ?? 0) == 0)
    }

    @MainActor
    func ensureCoverPinnedOrRefreshed() {
        if coverRecipeJSON == nil {
            pinCover(salt: 0, automatic: true)
        } else {
            refreshCoverIfNeeded()
        }
    }

    @MainActor
    func refreshCoverAfterMetadataUpdate(hadEmptyFandoms: Bool, hadZeroWords: Bool) {
        guard let coverRecipeJSON,
              let pinned = GeneratedCoverRecipe.supportedPin(in: coverRecipeJSON) else { return }
        let automatic = (pinned.pinnedAt ?? 0) == 0
        if automatic && pinned.salt == 0 && (pinned.fandom.isEmpty || hadEmptyFandoms || hadZeroWords) {
            pinCover(salt: 0, automatic: true)
            return
        }
        // A reader's Shuffle or Reset is not refined from tags that just arrived.
        // Length tier and the completion ring are the only fields a refresh may move.
        if !automatic {
            reconcileCoverMetadata()
            return
        }
        refreshCoverIfNeeded()
    }

    /// Returns whether the pin changed. A restore passes `notifySync: false` and announces the change
    /// itself after its save, so a restore that rolls back never leaves Folder Sync dirty.
    @MainActor
    @discardableResult
    func reconcileCoverMetadata(notifySync: Bool = true) -> Bool {
        guard let coverRecipeJSON, let pinned = GeneratedCoverRecipe.supportedPin(in: coverRecipeJSON) else { return false }
        let nextTier = coverTier
        let nextRing = pinned.closedRing || isComplete
        guard pinned.tier != nextTier || pinned.closedRing != nextRing else { return false }
        let updated = pinned.updating(tier: nextTier, closedRing: nextRing)
        guard let json = GeneratedCoverRecipe.encodedPin(updated) else { return false }
        self.coverRecipeJSON = json
        if notifySync {
            FolderSyncService.markDirty()
            NotificationCenter.default.post(name: .kudosSyncRelevantSettingChanged, object: nil)
        }
        return true
    }

    @MainActor
    private func resolvedCover(salt: Int) -> GeneratedCoverRecipe {
        GeneratedCoverRecipe(id: ao3WorkID, title: title, author: author,
                             fandoms: workFandoms, tags: workTagsFetched ? workFreeforms : workTags,
                             words: wordCount,
                             complete: isComplete,
                             seriesID: ao3SeriesID ?? ReadingQueueService.ao3SeriesID(from: seriesURL),
                             part: seriesPosition,
                             salt: salt, firstAuthor: verifiedAuthorIdentities.first?.displayName)
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
