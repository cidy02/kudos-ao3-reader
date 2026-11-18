import Foundation
import CoreGraphics
import ImageIO
import os
import Testing
import UniformTypeIdentifiers
@testable import Kudos

@Suite("Generated cover recipe")
struct GeneratedCoverRecipeTests {
    @Test @MainActor func pinnedCoverChangesOnlyForItsTriggers() {
        let work = SavedWork(title: "Original", author: "First")
        work.workFandoms = ["Original Work"]
        work.workTags = ["Angst"]
        work.wordCount = 9_999
        work.pinCover(salt: 0)
        let original = work.generatedCoverRecipe
        #expect(original.rendererVersion == 1)
        #expect(original.salt == 0)

        work.author = "Renamed"
        work.workTags = ["Fluff"]
        work.workFandoms = ["Other"]
        work.wordCount = 9_998
        #expect(work.generatedCoverRecipe == original)
        work.wordCount = 10_000
        #expect(work.generatedCoverRecipe == original)
        work.refreshCoverIfNeeded()
        let longer = work.generatedCoverRecipe
        #expect(longer.tier == 1)
        #expect(longer.author == "Renamed")
        work.isComplete = true
        #expect(!work.generatedCoverRecipe.closedRing)
        work.refreshCoverIfNeeded()
        #expect(work.generatedCoverRecipe.closedRing)

        work.pinCover(salt: work.generatedCoverRecipe.salt + 1)
        #expect(work.generatedCoverRecipe.salt == 1)
        #expect(work.generatedCoverRecipe.shapeSeed != longer.shapeSeed)
        work.pinCover(salt: 0)
        #expect(work.generatedCoverRecipe.salt == 0)
        work.author = "Updated again"
        #expect(work.generatedCoverRecipe.author == "Renamed")
        work.pinCover(salt: work.generatedCoverRecipe.salt)
        #expect(work.generatedCoverRecipe.author == "Updated again")
    }

    @Test @MainActor func readingCoverNeverWritesThePinOrWorkClock() {
        let work = SavedWork(title: "Read only cover", author: "Writer")
        work.wordCount = 9_999
        work.pinCover(salt: 0)
        let pin = work.coverRecipeJSON
        let workClock = work.lastModifiedAt
        work.pinCover(salt: 0) // Update Covers leaves an unchanged pin alone.
        #expect(work.coverRecipeJSON == pin)
        work.wordCount = 10_000
        work.isComplete = true

        #expect(work.generatedCoverRecipe.tier == 0)
        #expect(!work.generatedCoverRecipe.closedRing)
        #expect(work.coverRecipeJSON == pin)
        #expect(work.lastModifiedAt == workClock)

        work.refreshCoverIfNeeded()
        #expect(work.generatedCoverRecipe.tier == 1)
        #expect(work.generatedCoverRecipe.closedRing)
        #expect(work.lastModifiedAt == workClock)
    }

    @Test @MainActor func automaticPinCarriesEpochZeroWhileReaderActionsStampNow() {
        let auto = SavedWork(title: "Auto", author: "Writer")
        auto.pinCover(salt: 0, automatic: true)
        #expect(GeneratedCoverRecipe.pinnedAt(in: auto.coverRecipeJSON) == Date(timeIntervalSince1970: 0))
        #expect(GeneratedCoverRecipe.isAutomaticPin(in: auto.coverRecipeJSON))

        auto.pinCover(salt: 1)
        #expect((GeneratedCoverRecipe.pinnedAt(in: auto.coverRecipeJSON)?.timeIntervalSince1970 ?? 0) > 0)
        #expect(!GeneratedCoverRecipe.isAutomaticPin(in: auto.coverRecipeJSON))

        auto.pinCover(salt: 0) // Reader Reset Cover must not drop back to epoch 0.
        #expect((GeneratedCoverRecipe.pinnedAt(in: auto.coverRecipeJSON)?.timeIntervalSince1970 ?? 0) > 0)
        #expect(!GeneratedCoverRecipe.isAutomaticPin(in: auto.coverRecipeJSON))
    }

    @Test @MainActor func onePinAlwaysEncodesToTheSameString() throws {
        let work = SavedWork(title: "Stable", author: "Writer")
        work.pinCover(salt: 3)
        let json = try #require(work.coverRecipeJSON)
        let recipe = try #require(GeneratedCoverRecipe.supportedPin(in: json))
        let encodings = Set((0..<20).compactMap { _ in GeneratedCoverRecipe.encodedPin(recipe) })
        #expect(encodings.count == 1)
        #expect(encodings.first == work.coverRecipeJSON)
    }

    @Test @MainActor func pinCoverNotifiesFolderSyncObserverOnlyWhenRecipeChanges() {
        let notifications = OSAllocatedUnfairLock(initialState: 0)
        let token = NotificationCenter.default.addObserver(
            forName: .kudosSyncRelevantSettingChanged,
            object: nil,
            queue: nil
        ) { _ in notifications.withLock { $0 += 1 } }
        defer { NotificationCenter.default.removeObserver(token) }

        let work = SavedWork(title: "Sync Signal", author: "Writer")
        work.pinCover(salt: 0)
        #expect(notifications.withLock { $0 } == 1)

        work.pinCover(salt: 0) // Unchanged — must not re-notify FolderSyncObserver.
        #expect(notifications.withLock { $0 } == 1)

        work.pinCover(salt: 1)
        #expect(notifications.withLock { $0 } == 2)
    }

    @Test @MainActor func futureSkewedAndMaxFinitePinnedAtAreClampedWithoutBreakingPinCover() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let ceiling = now.addingTimeInterval(KudosBackupContents.maxFutureTimestampSkew)
        let year3000 = #"{"pinnedAt":32503680000}"#
        #expect(GeneratedCoverRecipe.pinnedAt(in: year3000, now: now) == ceiling)

        let work = SavedWork(title: "Skewed", author: "Writer")
        work.pinCover(salt: 0)
        let pinJSON = try #require(work.coverRecipeJSON)
        var obj = try #require(
            JSONSerialization.jsonObject(with: Data(pinJSON.utf8)) as? [String: Any]
        )
        obj["pinnedAt"] = Double.greatestFiniteMagnitude
        let rawMax = try #require(String(data: JSONSerialization.data(withJSONObject: obj), encoding: .utf8))
        work.coverRecipeJSON = rawMax

        #expect(GeneratedCoverRecipe.pinnedAt(in: work.coverRecipeJSON, now: now) == ceiling)

        // Previously `Double.greatestFiniteMagnitude.nextUp == .infinity` broke JSONEncoder on Shuffle/Reset.
        work.pinCover(salt: 1)
        let shuffledCeiling = Date().addingTimeInterval(KudosBackupContents.maxFutureTimestampSkew)
        #expect(work.generatedCoverRecipe.salt == 1)
        let repinnedAt = try #require(GeneratedCoverRecipe.pinnedAt(in: work.coverRecipeJSON))
        #expect(repinnedAt <= shuffledCeiling)
    }

    @Test @MainActor func unknownRecipeFieldsAreNeverReencodedByCoverActions() throws {
        let work = SavedWork(title: "Future fields", author: "Writer")
        work.pinCover(salt: 0)
        let json = try #require(work.coverRecipeJSON)
        var object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        object["futureField"] = ["value": 42]
        let raw = try #require(String(data: JSONSerialization.data(withJSONObject: object), encoding: .utf8))
        work.coverRecipeJSON = raw

        work.pinCover(salt: 1)
        work.pinCover(salt: 0)
        work.refreshCoverIfNeeded()
        #expect(work.coverRecipeJSON == raw)
        #expect(work.generatedCoverRecipe.rendererVersion == 1)
    }

    @Test func fandomLabelUsesTheBareFandomName() {
        let doctor = GeneratedCoverRecipe(id: 1, title: "Sodium Lights", author: "a", fandoms: ["Doctor Who (2005)"])
        let frozen = GeneratedCoverRecipe(id: 2, title: "Winter Garden", author: "b", fandoms: ["Frozen (Disney Movies)"])
        let media = GeneratedCoverRecipe(id: 3, title: "T", author: "c", fandoms: ["Avatar: The Last Airbender - All Media Types"])
        #expect(doctor.fandom == "Doctor Who")
        #expect(frozen.fandom == "Frozen")
        #expect(media.fandom == "Avatar: The Last Airbender")
    }

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

    @Test func subtitlesAndFirstAuthor() {
        for title in ["The Work (A Subtitle)", "The Work [A Subtitle]"] {
            let recipe = GeneratedCoverRecipe(id: 42, title: title, author: "First, Second", fandoms: ["Original Work"])
            #expect(recipe.title == "The Work")
            #expect(!recipe.subtitle.isEmpty)
            #expect(recipe.placement == 2)
        }
        let orTitle = GeneratedCoverRecipe(id: 42, title: "The Work; or, A Subtitle",
                                           author: "First", fandoms: ["Original Work"])
        #expect(orTitle.title == "The Work")
        #expect(orTitle.subtitle == "A Subtitle")
        let onlyParentheses = GeneratedCoverRecipe(id: 42, title: "(Only)",
                                                    author: "First", fandoms: ["Original Work"])
        #expect(onlyParentheses.title == "(Only)")
        #expect(onlyParentheses.subtitle.isEmpty)
        let first = GeneratedCoverRecipe(id: 42, title: "The Work", author: "First", fandoms: ["Original Work"])
        let joined = GeneratedCoverRecipe(id: 42, title: "The Work", author: "First, Second", fandoms: ["Original Work"])
        #expect(first.motif == joined.motif)
        #expect(first.titleStyle == joined.titleStyle)
    }

    @Test func unrelatedTagsDoNotChangeRecipe() {
        let base = GeneratedCoverRecipe(id: 42, title: "The Work", author: "First",
                                        fandoms: ["Original Work"], tags: ["Fantasy"])
        let extra = GeneratedCoverRecipe(id: 42, title: "The Work", author: "First",
                                         fandoms: ["Original Work"], tags: ["Fantasy", "Coffee Shops & Cafés"])
        #expect(base == extra)
    }

    @Test @MainActor func threePartsShareSeriesArtAndBuildersAgree() {
        let recipes = (1...3).map { part in
            GeneratedCoverRecipe(id: 42 + part, title: "Part \(part)", author: "Different \(part)",
                                 fandoms: ["Original Work"], tags: part == 2 ? ["Angst"] : ["Fluff"],
                                 seriesID: 77, part: part)
        }
        #expect(recipes.allSatisfy { $0.motif == recipes[0].motif })
        #expect(recipes.allSatisfy { $0.ground == recipes[0].ground })
        #expect(recipes.allSatisfy { $0.rotation == recipes[0].rotation })

        let saved = SavedWork(title: "Part 2", author: "First, Second")
        saved.ao3WorkID = 44
        saved.workFandoms = ["Original Work"]
        saved.workTags = ["Angst"]
        saved.ao3SeriesID = 77
        saved.seriesPosition = 2
        let remote = AO3WorkSummary.subscription(id: 44, title: "Part 2", authors: ["First", "Second"])
        var listed = remote
        listed.fandoms = ["Original Work"]
        listed.tags = ["Angst"]
        listed.seriesURL = "https://archiveofourown.org/series/77"
        listed.seriesPosition = 2
        listed.isComplete = saved.isComplete
        listed.words = saved.wordCount
        #expect(saved.generatedCoverRecipe == listed.generatedCoverRecipe)
    }

    @Test @MainActor func crossoverBandsHaveTheRequestedArea() {
        let height: CGFloat = 112 * 1.42
        func squared(_ value: CGFloat) -> CGFloat { max(value, 0) * max(value, 0) }
        let fractions: [CGFloat] = [0.6, 1.0 / 3, 2.0 / 3]
        for fraction in fractions {
            let cut = GeneratedCoverView.crossoverCut(fraction, height: height)
            let area = (squared(cut) - squared(cut - 112) - squared(cut - height)
                        + squared(cut - 112 - height)) / 2
            #expect(abs(area / (112 * height) - fraction) < 0.0001)
        }
    }

    @Test @MainActor func whiteContrastAcrossGroundRange() {
        #expect(GeneratedCoverView.bylineOpacity == 0.86)
        #expect(GeneratedCoverView.fandomOpacity == 0.88)
        #expect(GeneratedCoverView.lighterGroundLightness(0.46) == 0.50)
        for hue in 0..<360 {
            for (lightness, chroma) in [(0.32, 0.085), (0.46, 0.085), (0.50, 0.09),
                                        (0.27, 0.08), (0.47, 0.017)] {
                let (red, green, blue) = GeneratedCoverView.rgb(lightness, chroma, Double(hue))
                func linear(_ value: Double) -> Double {
                    value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
                }
                let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
                for opacity in [GeneratedCoverView.bylineOpacity, GeneratedCoverView.fandomOpacity, 1.0] {
                    let foreground = [red, green, blue].map { opacity + (1 - opacity) * $0 }
                    let textLuminance = 0.2126 * linear(foreground[0])
                        + 0.7152 * linear(foreground[1]) + 0.0722 * linear(foreground[2])
                    #expect((textLuminance + 0.05) / (luminance + 0.05) >= 4.5)
                }
            }
        }
    }

    @Test @MainActor func vectorCacheKeyIsStableAndZeroWidthHasFiniteStroke() {
        let recipe = GeneratedCoverRecipe(id: 42, title: "Title", author: "Author", fandoms: ["Original Work"])
        let first = GeneratedCoverView(recipe: recipe, width: 112)
        let second = GeneratedCoverView(recipe: recipe, width: 112)
        let small = GeneratedCoverView(recipe: recipe, width: 40)
        #expect(first.artCacheKey == second.artCacheKey)
        #expect(first.artCacheKey != small.artCacheKey)
        #expect(GeneratedCoverView.strokeFloor(for: 0).isFinite)
        #expect(GeneratedCoverView.strokeFloor(for: 0) == GeneratedCoverView.strokeFloor(for: 1))
        #expect(GeneratedCoverView.crossoverCut(0.6, height: 0).isFinite)
    }

    @Test func collectionColourSnapsToPalette() {
        #expect(GeneratedCoverRecipe.collectionHue("#808080", fallback: 20) == 260)
        #expect(GeneratedCoverRecipe.collectionSwatch("#808080", fallback: 20).chroma == 0.012)
        #expect([20, 55, 85, 125, 150, 180, 205, 230, 260, 290, 320, 350]
            .contains(GeneratedCoverRecipe.collectionHue(nil, fallback: 137)))
        let identity = UUID(uuidString: "00000000-0000-0000-0000-000000000077")!
        #expect([20, 55, 85, 125, 150, 180, 205, 230, 260, 290, 320, 350]
            .contains(GeneratedCoverRecipe.collectionHue(for: identity)))
        #expect(GeneratedCoverRecipe(collection: "Next", hue: 150).hasRing == false)
        let renamed = GeneratedCoverRecipe(collection: "Renamed", identity: "same-id", hue: 150)
        let original = GeneratedCoverRecipe(collection: "Original", identity: "same-id", hue: 150)
        #expect(renamed.motif == original.motif)
        #expect(renamed.shapeSeed == original.shapeSeed)
        #expect(renamed.placement == original.placement)
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
        let chosen = images.reduce(nil as EmbeddedWorkCoverImage.Candidate?) {
            EmbeddedWorkCoverImage.preferred($0, $1)
        }
        #expect(chosen?.data == Data([3]))
    }

    @Test func embeddedArtScansFrontMatterInARealEPUB() throws {
        func png(width: Int, red: CGFloat) throws -> Data {
            let context = try #require(CGContext(
                data: nil, width: width, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.setFillColor(red: red, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: 800))
            let image = try #require(context.makeImage())
            let output = NSMutableData()
            let destination = try #require(CGImageDestinationCreateWithData(
                output, UTType.png.identifier as CFString, 1, nil
            ))
            CGImageDestinationAddImage(destination, image, nil)
            #expect(CGImageDestinationFinalize(destination))
            return output as Data
        }
        let front = try png(width: 320, red: 1)
        let chapter = try png(width: 400, red: 0.5)
        let container = """
            <?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
            <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
            </container>
            """
        let opf = """
            <?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0">
            <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Art Test</dc:title>
            <dc:creator>Author</dc:creator><dc:language>en</dc:language></metadata>
            <manifest><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
            <item id="front" href="front.xhtml" media-type="application/xhtml+xml"/>
            <item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest>
            <spine toc="ncx"><itemref idref="front"/><itemref idref="chapter"/></spine>
            </package>
            """
        let toc = """
            <?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
            <navMap><navPoint id="front" playOrder="1"><navLabel><text>Preface</text></navLabel>
            <content src="front.xhtml"/></navPoint><navPoint id="chapter" playOrder="2">
            <navLabel><text>Chapter 1</text></navLabel><content src="chapter.xhtml"/></navPoint></navMap>
            </ncx>
            """
        func entry(_ name: String, _ data: Data) -> HostileZipFixture.Entry {
            HostileZipFixture.Entry(name: name, payload: data)
        }
        let archive = HostileZipFixture.build([
            entry("mimetype", Data("application/epub+zip".utf8)),
            entry("META-INF/container.xml", Data(container.utf8)),
            entry("OEBPS/content.opf", Data(opf.utf8)),
            entry("OEBPS/toc.ncx", Data(toc.utf8)),
            entry("OEBPS/front.xhtml", Data("<html><body><img src='front%2520.png'/></body></html>".utf8)),
            entry("OEBPS/chapter.xhtml", Data("<html><body><img src='chapter.png'/></body></html>".utf8)),
            entry("OEBPS/front%20.png", front), entry("OEBPS/chapter.png", chapter),
            // Selective entry reads succeed; extracting this unrelated, malformed entry cannot.
            HostileZipFixture.Entry(name: "unrelated.bin", payload: Data([0]),
                                    declaredCompressedSize: 1_000_000,
                                    declaredUncompressedSize: 1_000_000)
        ])
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
        defer { try? FileManager.default.removeItem(at: file) }
        try archive.write(to: file)
        #expect(EmbeddedWorkCoverImage.data(at: file) == front)
        let thumb = try #require(EmbeddedWorkCoverImage.downsampledJPEG(front))
        let source = try #require(CGImageSourceCreateWithData(thumb as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(max(image.width, image.height) <= 600)
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

    @Test func cancelledQueuedCoverDoesNotScan() async throws {
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var count = 0
            func hit() { lock.lock(); count += 1; lock.unlock() }
            var value: Int { lock.lock(); defer { lock.unlock() }; return count }
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let firstFile = folder.appendingPathComponent("first.epub")
        let secondFile = folder.appendingPathComponent("second.epub")
        try Data([1]).write(to: firstFile)
        try Data([2]).write(to: secondFile)
        let counter = Counter()
        let gate = DispatchSemaphore(value: 0)
        let loader = GeneratedCoverArtLoader(directory: folder.appendingPathComponent("cache"), scan: { file in
            counter.hit()
            if file == firstFile { gate.wait() }
            return nil
        })
        let first = Task { await loader.image(workID: UUID(), fileURL: firstFile) }
        for _ in 0..<100 where counter.value == 0 { try await Task.sleep(for: .milliseconds(5)) }
        guard counter.value == 1 else {
            gate.signal()
            Issue.record("The first scan never started")
            return
        }
        let second = Task { await loader.image(workID: UUID(), fileURL: secondFile) }
        second.cancel()
        _ = await second.value
        gate.signal()
        _ = await first.value
        #expect(counter.value == 1)
    }
}
