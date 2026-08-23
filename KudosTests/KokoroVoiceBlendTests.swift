#if os(iOS)
import Foundation
import Testing
@testable import Kudos

@Suite("Kokoro voice blending")
struct KokoroVoiceBlendTests {

    // MARK: - Fixtures

    /// Deterministic pseudo-random voice pack. A real `.bin` is 180 MB of
    /// download away, and none of this maths cares where the floats came from.
    static func fakePack(seed: UInt64, scale: Float = 1) -> [Float] {
        var state = seed &* 6_364_136_223_846_793_005 &+ 1
        var storage = [Float](repeating: 0, count: KokoroVoiceBlend.elementCount)
        for index in storage.indices {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let unit = Float(Double(state >> 11) / Double(1 << 53))
            storage[index] = (unit * 2 - 1) * scale
        }
        return storage
    }

    /// Norms of every 128-float half-row — the granularity the blend works at.
    static func halfRowNorms(_ storage: [Float]) -> [Double] {
        stride(from: 0, to: storage.count, by: KokoroVoiceBlend.halfColumns).map { base in
            var sum = 0.0
            for index in base..<(base + KokoroVoiceBlend.halfColumns) {
                sum += Double(storage[index]) * Double(storage[index])
            }
            return sum.squareRoot()
        }
    }

    static func lerp(_ lhs: [Float], _ rhs: [Float], ratio: Double) -> [Float] {
        let rhsCoefficient = Float(ratio)
        let lhsCoefficient = Float(1 - ratio)
        return zip(lhs, rhs).map { lhsCoefficient * $0 + rhsCoefficient * $1 }
    }

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kokoro-blend-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func write(_ storage: [Float], named name: String, in directory: URL) throws {
        let data = storage.withUnsafeBufferPointer { Data(buffer: $0) }
        try data.write(to: directory.appendingPathComponent("\(name).bin"))
    }

    // MARK: - Layout

    /// Pins the duplicated constants to `KokoroAneVoicePack`'s contract: a flat
    /// `[510, 256]` fp32 blob, exactly 522,240 bytes, split 128/128 per row.
    @Test func layoutMatchesTheVoicePackContract() {
        #expect(KokoroVoiceBlend.rows == 510)
        #expect(KokoroVoiceBlend.columns == 256)
        #expect(KokoroVoiceBlend.halfColumns == 128)
        #expect(KokoroVoiceBlend.elementCount == 510 * 256)
        #expect(KokoroVoiceBlend.elementCount * MemoryLayout<Float>.size == 522_240)
    }

    @Test func blendOutputIsExactlyOneVoicePack() throws {
        let blended = try KokoroVoiceBlend.blendedStorage(
            [Self.fakePack(seed: 1), Self.fakePack(seed: 2)],
            weights: [2, 1]
        )
        #expect(blended.count == 510 * 256)
    }

    @Test func mismatchedInputSizesAreRejected() {
        #expect(throws: KokoroVoiceBlend.Failure.wrongElementCount(3)) {
            try KokoroVoiceBlend.blendedStorage(
                [[1, 2, 3], Self.fakePack(seed: 1)],
                weights: [1, 1]
            )
        }
    }

    // MARK: - Identity

    @Test func blendingAVoiceWithItselfReproducesIt() throws {
        let pack = Self.fakePack(seed: 7)
        for weights in [[1.0, 1.0], [2.0, 1.0], [1.0, 9.0]] {
            let blended = try KokoroVoiceBlend.blendedStorage([pack, pack], weights: weights)
            let worst = zip(pack, blended).map { abs($0 - $1) }.max() ?? 0
            #expect(worst < 1e-5, "weights \(weights) drifted by \(worst)")
        }
    }

    /// A recipe naming one voice twice *is* that voice: `canonical` merges it
    /// down to a single component and hands back the shipped name, so nothing
    /// is blended and no 510 KB copy is written.
    @Test func aRecipeThatReducesToOneVoiceIsThatVoice() throws {
        let single = try KokoroVoiceBlend.canonical([
            .init(voice: "af_heart", weight: 2),
            .init(voice: "af_heart", weight: 1)
        ])
        #expect(single.identifier == "af_heart")
        #expect(single.recipe.count == 1)
        #expect(!KokoroVoiceBlend.isBlend(single.identifier))

        // A weight small enough to quantise to zero parts-per-million drops out
        // rather than forking the cache with an inaudible variant.
        let dusted = try KokoroVoiceBlend.canonical([
            .init(voice: "af_heart", weight: 1),
            .init(voice: "am_puck", weight: 1e-9)
        ])
        #expect(dusted.identifier == "af_heart")
    }

    // MARK: - Weights

    @Test func weightsNormaliseRegardlessOfScaleOrOrder() throws {
        let expected = [
            KokoroVoiceBlend.Component(voice: "af_bella", weight: 2.0 / 3.0),
            KokoroVoiceBlend.Component(voice: "af_heart", weight: 1.0 / 3.0)
        ]
        let recipes: [[KokoroVoiceBlend.Component]] = [
            [.init(voice: "af_bella", weight: 2), .init(voice: "af_heart", weight: 1)],
            [.init(voice: "af_heart", weight: 1), .init(voice: "af_bella", weight: 2)],
            [.init(voice: "af_bella", weight: 200), .init(voice: "af_heart", weight: 100)],
            [.init(voice: "af_bella", weight: 0.666_666_6), .init(voice: "af_heart", weight: 0.333_333_3)]
        ]
        var identifiers: Set<String> = []
        for recipe in recipes {
            let canonical = try KokoroVoiceBlend.canonical(recipe)
            identifiers.insert(canonical.identifier)
            #expect(canonical.recipe.map(\.voice) == expected.map(\.voice))
            #expect(abs(canonical.recipe.reduce(0) { $0 + $1.weight } - 1) < 1e-9)
            for (actual, want) in zip(canonical.recipe, expected) {
                #expect(abs(actual.weight - want.weight) < 1e-6)
            }
        }
        // Same mix, one cached `.bin`: order, scale and float noise all collapse
        // onto a single content-addressed name.
        #expect(identifiers.count == 1)
    }

    @Test func differentMixesGetDifferentNames() throws {
        let first = try KokoroVoiceBlend.canonical([
            .init(voice: "af_bella", weight: 2), .init(voice: "af_heart", weight: 1)
        ]).identifier
        let second = try KokoroVoiceBlend.canonical([
            .init(voice: "af_bella", weight: 1), .init(voice: "af_heart", weight: 2)
        ]).identifier
        let third = try KokoroVoiceBlend.canonical([
            .init(voice: "af_bella", weight: 1), .init(voice: "bm_george", weight: 2)
        ]).identifier
        #expect(Set([first, second, third]).count == 3)
    }

    @Test func invalidRecipesAreRejected() {
        #expect(throws: KokoroVoiceBlend.Failure.emptyRecipe) {
            try KokoroVoiceBlend.canonical([])
        }
        #expect(throws: KokoroVoiceBlend.Failure.invalidWeight(-1)) {
            try KokoroVoiceBlend.canonical([
                .init(voice: "af_heart", weight: -1), .init(voice: "af_bella", weight: 2)
            ])
        }
        // NaN is not equal to itself, so match on the case rather than the payload.
        #expect(throws: KokoroVoiceBlend.Failure.self) {
            try KokoroVoiceBlend.canonical([.init(voice: "af_heart", weight: .nan)])
        }
        #expect(throws: KokoroVoiceBlend.Failure.self) {
            try KokoroVoiceBlend.canonical([.init(voice: "af_heart", weight: .infinity)])
        }
        #expect(throws: KokoroVoiceBlend.Failure.invalidWeight(0)) {
            try KokoroVoiceBlend.canonical([
                .init(voice: "af_heart", weight: 0), .init(voice: "af_bella", weight: 0)
            ])
        }
    }

    /// The voice name becomes a path component and a FluidAudio lookup key, so
    /// anything outside `[A-Za-z0-9_]` has to bounce here rather than escape
    /// the pack directory or get silently rewritten by `ensureVoicePack`.
    @Test func voiceNamesThatWouldEscapeOrBeRewrittenAreRejected() {
        for bad in ["../../../etc/passwd", "af-bella", "af heart", "af.heart", "", "af/heart"] {
            #expect(throws: KokoroVoiceBlend.Failure.invalidVoiceName(bad)) {
                try KokoroVoiceBlend.canonical([
                    .init(voice: bad, weight: 1), .init(voice: "af_heart", weight: 1)
                ])
            }
        }
        // Blending a blend would dangle the moment the cache evicted its source.
        let nested = KokoroVoiceBlend.namePrefix + String(repeating: "a", count: 16)
        #expect(throws: KokoroVoiceBlend.Failure.invalidVoiceName(nested)) {
            try KokoroVoiceBlend.canonical([
                .init(voice: nested, weight: 1), .init(voice: "af_heart", weight: 1)
            ])
        }
    }

    // MARK: - SLERP vs LERP

    /// The reason for all of this. Two independent 128-d vectors are close to
    /// orthogonal, so a weighted mean of them lands *inside* the sphere and the
    /// voice audibly flattens. SLERP stays on it.
    @Test func slerpHoldsMagnitudeWhereLerpCollapsesIt() throws {
        let lhs = Self.fakePack(seed: 11)
        let rhs = Self.fakePack(seed: 29)
        let ratio = 0.5

        let slerped = try KokoroVoiceBlend.slerp(lhs, rhs, ratio: ratio)
        let lerped = Self.lerp(lhs, rhs, ratio: ratio)

        let lhsNorms = Self.halfRowNorms(lhs)
        let rhsNorms = Self.halfRowNorms(rhs)
        let target = zip(lhsNorms, rhsNorms).map { (1 - ratio) * $0 + ratio * $1 }

        func meanRelativeError(_ storage: [Float]) -> Double {
            let norms = Self.halfRowNorms(storage)
            let errors = zip(norms, target).map { abs($0 - $1) / $1 }
            return errors.reduce(0, +) / Double(errors.count)
        }

        let slerpError = meanRelativeError(slerped)
        let lerpError = meanRelativeError(lerped)

        // SLERP reconstructs the intended magnitude to fp32 noise...
        #expect(slerpError < 0.001, "slerp lost \(slerpError * 100)% of the magnitude")
        // ...while LERP throws away ~29% of it (1 - 1/sqrt(2) at 90 degrees).
        #expect(lerpError > 0.2, "lerp only lost \(lerpError * 100)%; fixture is not divergent")
        #expect(lerpError > slerpError * 50)
    }

    /// Whatever the mix, the output has to stay on the sphere the two inputs
    /// define — not just at the midpoint.
    @Test func magnitudeIsHeldAcrossTheWholeWeightRange() throws {
        let lhs = Self.fakePack(seed: 3)
        let rhs = Self.fakePack(seed: 5, scale: 3)
        let lhsNorms = Self.halfRowNorms(lhs)
        let rhsNorms = Self.halfRowNorms(rhs)

        for ratio in [0.0, 0.1, 0.25, 0.75, 0.9, 1.0] {
            let blended = try KokoroVoiceBlend.slerp(lhs, rhs, ratio: ratio)
            let norms = Self.halfRowNorms(blended)
            for index in norms.indices {
                let want = (1 - ratio) * lhsNorms[index] + ratio * rhsNorms[index]
                #expect(abs(norms[index] - want) / want < 0.001, "ratio \(ratio), row \(index)")
            }
        }
    }

    // MARK: - Degenerate inputs

    @Test func degenerateVectorsNeverProduceNaNOrInf() throws {
        let base = Self.fakePack(seed: 13)
        let zeros = [Float](repeating: 0, count: KokoroVoiceBlend.elementCount)
        let antiparallel = base.map { -$0 }
        let nearlyParallel = base.map { $0 * 1.000_001 }
        // One dead half-row inside an otherwise healthy pack: the degenerate
        // case has to be handled per segment, not per file.
        var punctured = base
        for index in 0..<KokoroVoiceBlend.halfColumns { punctured[index] = 0 }

        let cases: [(String, [Float], [Float])] = [
            ("zero + normal", zeros, base),
            ("normal + zero", base, zeros),
            ("zero + zero", zeros, zeros),
            ("antiparallel", base, antiparallel),
            ("near parallel", base, nearlyParallel),
            ("identical", base, base),
            ("punctured half-row", punctured, base)
        ]
        for (label, lhs, rhs) in cases {
            for ratio in [0.0, 0.5, 1.0, 1.0 / 3.0] {
                let blended = try KokoroVoiceBlend.slerp(lhs, rhs, ratio: ratio)
                #expect(blended.count == KokoroVoiceBlend.elementCount)
                // `allSatisfy` is `rethrows`; the key-path form reads as
                // throwing inside the macro expansion, so hoist it out.
                let allFinite = blended.allSatisfy { $0.isFinite }
                #expect(allFinite, "\(label) at ratio \(ratio) went non-finite")
            }
        }
    }

    @Test func nearParallelFallsBackToLerpRatherThanDividingByZero() throws {
        let base = Self.fakePack(seed: 17)
        let nudged = base.map { $0 * 1.000_001 }
        let blended = try KokoroVoiceBlend.slerp(base, nudged, ratio: 0.5)
        let worst = zip(base, blended).map { abs($0 - $1) }.max() ?? 0
        let peak = base.map(abs).max() ?? 1
        #expect(worst / peak < 1e-4)
    }

    // MARK: - Materialising

    @Test func blendRoundTripsThroughTheBinFormatByteForByte() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let bella = Self.fakePack(seed: 101)
        let heart = Self.fakePack(seed: 202)
        try Self.write(bella, named: "af_bella", in: directory)
        try Self.write(heart, named: "af_heart", in: directory)

        let recipe: [KokoroVoiceBlend.Component] = [
            .init(voice: "af_bella", weight: 2), .init(voice: "af_heart", weight: 1)
        ]
        let identifier = try KokoroVoiceBlend.ensure(recipe, in: directory)
        #expect(KokoroVoiceBlend.isBlend(identifier))

        let url = directory.appendingPathComponent("\(identifier).bin")
        let size = try #require(
            try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
        )
        #expect(size == 522_240)

        let reloaded = try KokoroVoiceBlend.loadStorage(at: url)
        let canonical = try KokoroVoiceBlend.canonical(recipe)
        let expected = try KokoroVoiceBlend.blendedStorage(
            [bella, heart], weights: canonical.recipe.map(\.weight)
        )
        #expect(reloaded == expected)
        #expect(reloaded != bella)
        #expect(reloaded != heart)

        // Re-running is a cache hit: same name, same bytes, no rewrite needed.
        // `try` is hoisted out of `#expect` — inside a comparison the macro
        // expansion drops it and the call reads as non-throwing.
        let cachedIdentifier = try KokoroVoiceBlend.ensure(recipe, in: directory)
        #expect(cachedIdentifier == identifier)
        let cachedStorage = try KokoroVoiceBlend.loadStorage(at: url)
        #expect(cachedStorage == expected)
    }

    @Test func aSingleVoiceRecipeWritesNothing() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.write(Self.fakePack(seed: 1), named: "af_heart", in: directory)

        let identifier = try KokoroVoiceBlend.ensure(
            [.init(voice: "af_heart", weight: 3)], in: directory
        )
        #expect(identifier == "af_heart")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files == ["af_heart.bin"])
    }

    @Test func aMissingSourceVoiceFailsInsteadOfWritingHalfABlend() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.write(Self.fakePack(seed: 1), named: "af_heart", in: directory)

        #expect(throws: (any Error).self) {
            try KokoroVoiceBlend.ensure([
                .init(voice: "af_heart", weight: 1), .init(voice: "af_nope", weight: 1)
            ], in: directory)
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files == ["af_heart.bin"])
    }

    /// Blends are a cache, not an archive: at 510 KB each an unbounded slider
    /// would fill the device. Oldest-used goes first, and only blends go.
    @Test func theBlendCacheEvictsLeastRecentlyUsedAndTouchesNothingElse() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try Self.write(Self.fakePack(seed: 1), named: "af_bella", in: directory)
        try Self.write(Self.fakePack(seed: 2), named: "af_heart", in: directory)

        // Stale blends, oldest first.
        var stale: [String] = []
        for index in 0..<(KokoroVoiceBlend.cacheLimit + 2) {
            let name = KokoroVoiceBlend.namePrefix + String(format: "%016x", index)
            stale.append(name)
            let url = directory.appendingPathComponent("\(name).bin")
            try Data("stale".utf8).write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: Double(1_000 + index))],
                ofItemAtPath: url.path
            )
        }

        let identifier = try KokoroVoiceBlend.ensure([
            .init(voice: "af_bella", weight: 2), .init(voice: "af_heart", weight: 1)
        ], in: directory)

        let names = Set(
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .map { $0.replacingOccurrences(of: ".bin", with: "") }
        )
        let survivingBlends = names.filter(KokoroVoiceBlend.isBlend)
        #expect(survivingBlends.count == KokoroVoiceBlend.cacheLimit)
        #expect(survivingBlends.contains(identifier))
        // The three oldest went; the shipped voices never do.
        #expect(!survivingBlends.contains(stale[0]))
        #expect(!survivingBlends.contains(stale[1]))
        #expect(!survivingBlends.contains(stale[2]))
        #expect(survivingBlends.contains(stale[3]))
        #expect(names.contains("af_bella"))
        #expect(names.contains("af_heart"))
    }

    // MARK: - Integration shape

    /// Two contracts a blend name has to satisfy at once.
    ///
    /// `KokoroAneResourceDownloader.ensureVoicePack` strips everything that is
    /// not a letter, digit or `_` before looking for `<name>.bin` — a name with
    /// a hyphen in it would miss the file we just wrote and try to fetch it
    /// from HuggingFace. And `KokoroVoiceCatalog` builds the picker from the
    /// same directory, so the name must *not* parse as a locale/gender pair.
    @Test func blendNamesSurviveFluidAudioAndStayOutOfThePicker() throws {
        let identifier = try KokoroVoiceBlend.canonical([
            .init(voice: "af_bella", weight: 2), .init(voice: "bm_george", weight: 1)
        ]).identifier

        let sanitized = identifier.filter { $0.isLetter || $0.isNumber || $0 == "_" }
        #expect(sanitized == identifier)
        #expect(KokoroVoiceCatalog.voice(forIdentifier: identifier) == nil)
    }

    @Test func thePickerListsShippedVoicesOnlyEvenWithBlendsOnDisk() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try Self.write(Self.fakePack(seed: 1), named: "af_bella", in: directory)
        try Self.write(Self.fakePack(seed: 2), named: "af_heart", in: directory)
        try KokoroVoiceBlend.ensure([
            .init(voice: "af_bella", weight: 1), .init(voice: "af_heart", weight: 1)
        ], in: directory)

        let listed = KokoroVoiceCatalog.installedVoices(in: directory).map(\.identifier)
        #expect(listed == ["af_bella", "af_heart"])
    }
}
#endif
