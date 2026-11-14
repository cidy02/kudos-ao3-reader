import Foundation
import Testing
@testable import Kudos

@Suite("Generated cover recipe")
struct GeneratedCoverRecipeTests {
    @Test func referenceShelf() {
        // Values came from executing CoverArt.dc.html's renderVals with row C's work inputs and years.
        let cases: [(Int, String, String, String, Int, Bool, Int, [String], Int?, Int,
                     String, Int, Double, GeneratedCoverRecipe.Ground, Int, Double, Double, Double, Double)] = [
            (1001, "The Long Frost", "fogandlamplight", "Sherlock Holmes", 92_000, true, 2019, ["Slow Burn", "Angst"], 77, 1,
             "sigil", 55, 0.40, .gradient, 1, 284.36, 1.03, 1.01, 0.47),
            (1002, "Thaw", "fogandlamplight", "Sherlock Holmes", 41_000, true, 2020, ["Fluff"], 77, 2,
             "sigil", 73, 0.41, .gradient, 1, 284.36, 1.03, 1.01, 0.47),
            (1004, "The Lamplight Cases", "gaslitgrey", "Sherlock Holmes", 30_000, true, 2016, ["Case Fic"], 91, 1,
             "petals", 55, 0.37, .split, 0, 310.17, 0.96, 1.36, 0.45),
            (1007, "A Study in Small Hours", "baskervilled", "Sherlock Holmes", 3_100, true, 2023, ["Fluff", "Domestic Fluff"], nil, 0,
             "petals", 55, 0.43, .solid, 0, 64.92, 1.15, 1.29, 0.4),
            (1008, "Salt & Starlight", "wrenfield", "Original Work", 118_000, false, 2024, ["Fantasy", "Magic"], nil, 0,
             "rings", 220, 0.44, .band, 1, 57.36, 1.11, 1.1, 0.48),
            (1009, "Letters Never Sent", "marginalia", "Persuasion", 18_000, true, 2018, ["Romance", "Angst"], nil, 0,
             "orbit", 141, 0.39, .band, 0, 143.39, 1.02, 1.28, 0.5)
        ]
        for (id, title, author, fandom, words, done, year, tags, series, part,
             motif, hue, lightness, ground, spot, rotation, scale, lineWidth, opacity) in cases {
            let recipe = GeneratedCoverRecipe(id: id, title: title, author: author, fandoms: [fandom],
                                              tags: tags, words: words, complete: done,
                                              seriesID: series, part: part, postedYear: year)
            #expect(recipe.motif == motif)
            #expect(recipe.hues[0] == hue)
            #expect(recipe.lightness == lightness)
            #expect(recipe.ground == ground)
            #expect(recipe.placement == spot)
            #expect(recipe.rotation == rotation)
            #expect(recipe.scale == scale)
            #expect(recipe.lineWidth == lineWidth)
            #expect(recipe.opacity == opacity)
            #expect(recipe.closedRing == done)
        }
    }

    @Test func inputsChooseOnlyTheirAssignedParts() {
        let base = GeneratedCoverRecipe(id: 1008, title: "Salt & Starlight", author: "wrenfield",
                                        fandoms: ["Original Work"], words: 8_000, complete: false)
        #expect(base == GeneratedCoverRecipe(id: 1008, title: "Salt & Starlight", author: "wrenfield",
                                             fandoms: ["Original Work"], words: 8_000, complete: false))
        let otherID = GeneratedCoverRecipe(id: 1009, title: "Salt & Starlight", author: "wrenfield",
                                           fandoms: ["Original Work"], words: 8_000, complete: false)
        #expect(base.shapeSeed != otherID.shapeSeed)
        #expect(base.hues == otherID.hues)
        #expect(base.tier == 0)
        #expect(GeneratedCoverRecipe(id: 1008, title: "Salt & Starlight", author: "wrenfield",
                                     fandoms: ["Original Work"], words: 150_000).tier == 3)
        #expect(GeneratedCoverRecipe(id: 1008, title: "Salt & Starlight", author: "wrenfield",
                                     fandoms: ["Original Work"], complete: true).closedRing)
        #expect(GeneratedCoverRecipe(id: 1008, title: "Salt & Starlight", author: "wrenfield",
                                     fandoms: ["Sherlock Holmes", "Jane Eyre"]).ground == .crossover)
        #expect(GeneratedCoverRecipe(id: 1008, title: "Salt & Starlight", author: "wrenfield",
                                     fandoms: ["Original Work"], tags: ["Fantasy"]).motif == "rings")
        #expect(GeneratedCoverRecipe(id: 1008, title: "Salt & Starlight", author: "wrenfield",
                                     fandoms: ["Original Work"], tags: ["Angst"]).motif != "rings")
        #expect(GeneratedCoverRecipe(id: 1008, title: "Salt & Starlight", author: "wrenfield",
                                     fandoms: ["Persuasion"]).hues != base.hues)
        let shuffled = GeneratedCoverRecipe(id: 1008, title: "Salt & Starlight", author: "wrenfield",
                                            fandoms: ["Original Work"], salt: 1)
        #expect(shuffled.shapeSeed != base.shapeSeed)
        #expect(shuffled.motif != base.motif)
    }

    @Test func seriesKeepsItsLook() {
        let first = GeneratedCoverRecipe(id: 1001, title: "The Long Frost", author: "fogandlamplight",
                                         fandoms: ["Sherlock Holmes"], seriesID: 77, part: 1)
        let second = GeneratedCoverRecipe(id: 1002, title: "Thaw", author: "another author",
                                          fandoms: ["Sherlock Holmes"], seriesID: 77, part: 2)
        #expect(first.motif == second.motif)
        #expect(first.ground == second.ground)
        #expect(first.rotation == second.rotation)
        #expect(first.scale == second.scale)
        #expect(second.hues[0] == first.hues[0] + 18)
    }

    @Test func whiteContrastAcrossGroundRange() {
        for hue in 0..<360 {
            for (lightness, chroma) in [(0.32, 0.085), (0.46, 0.085), (0.53, 0.09), (0.27, 0.08)] {
                let (red, green, blue) = GeneratedCoverView.rgb(lightness, chroma, Double(hue))
                func linear(_ value: Double) -> Double {
                    value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
                }
                let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
                #expect(1.05 / (luminance + 0.05) >= 4.5)
            }
        }
    }

    @Test func collectionColourSnapsToPalette() {
        #expect(GeneratedCoverRecipe.collectionHue("#808080", fallback: 20) == 260)
        #expect(GeneratedCoverRecipe(collection: "Next", hue: 150).hasRing == false)
    }

    @Test func embeddedArtPrefersFrontMatterThenLargest() {
        #expect(EmbeddedWorkCoverImage.accepts(width: 320, height: 800))
        #expect(EmbeddedWorkCoverImage.accepts(width: 740, height: 400))
        #expect(!EmbeddedWorkCoverImage.accepts(width: 320, height: 801))
        #expect(!EmbeddedWorkCoverImage.accepts(width: 741, height: 400))
        #expect(!EmbeddedWorkCoverImage.accepts(width: 319, height: 800))
        #expect(!EmbeddedWorkCoverImage.accepts(width: 800, height: 320))
        #expect(!EmbeddedWorkCoverImage.accepts(width: 0, height: 500))
        let images = [
            EmbeddedWorkCoverImage.Candidate(data: Data([1]), frontMatter: false, pixelArea: 3_000_000),
            EmbeddedWorkCoverImage.Candidate(data: Data([2]), frontMatter: true, pixelArea: 500_000),
            EmbeddedWorkCoverImage.Candidate(data: Data([3]), frontMatter: true, pixelArea: 1_000_000)
        ]
        #expect(EmbeddedWorkCoverImage.preferred(images) == Data([3]))
    }

    @Test func postingYearIsMonotoneAndClamped() {
        #expect(GeneratedCoverRecipe.year(for: -1) == 2010)
        #expect(GeneratedCoverRecipe.year(for: 0) == 2010)
        #expect(GeneratedCoverRecipe.year(for: 72_000_000) == 2026)
        #expect(GeneratedCoverRecipe.year(for: 90_000_000) == 2026)
        var previous = 2010.0
        for id in stride(from: 0, through: 72_000_000, by: 100_000) {
            let year = GeneratedCoverRecipe.year(for: id)
            #expect(year >= previous)
            previous = year
        }
    }

    @Test func coverArtLoaderScansOneFileOnce() async throws {
        final class Count: @unchecked Sendable {
            private let lock = NSLock()
            private var scans = 0
            func hit() {
                lock.lock(); scans += 1; lock.unlock()
                Thread.sleep(forTimeInterval: 0.03)
            }
            var value: Int {
                lock.lock(); defer { lock.unlock() }
                return scans
            }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("work.epub")
        try Data([1]).write(to: file)
        let workID = UUID()
        let count = Count()
        let cache = directory.appendingPathComponent("GeneratedCoverArt")
        let loader = GeneratedCoverArtLoader(directory: cache, scan: { _ in count.hit(); return nil })
        async let first = loader.image(workID: workID, fileURL: file)
        async let second = loader.image(workID: workID, fileURL: file)
        let results = await (first, second)
        #expect(results.0 == nil && results.1 == nil)
        #expect(count.value == 1)
        let cached = await loader.image(workID: workID, fileURL: file)
        #expect(cached == nil)
        let restarted = GeneratedCoverArtLoader(directory: cache, scan: { _ in count.hit(); return nil })
        let fromDisk = await restarted.image(workID: workID, fileURL: file)
        #expect(fromDisk == nil)
        #expect(count.value == 1)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)],
                                              ofItemAtPath: file.path)
        let refreshed = await restarted.image(workID: workID, fileURL: file)
        #expect(refreshed == nil)
        #expect(count.value == 2)
        let cacheFiles = try FileManager.default.contentsOfDirectory(atPath: cache.path)
        #expect(cacheFiles.count == 1)
    }
}
