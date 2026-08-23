import CryptoKit
import Foundation

/// Weighted mixes of installed Kokoro voices, so the 28 shipped voices become
/// an unbounded set.
///
/// A voice pack is a flat `[510, 256]` little-endian fp32 blob (see
/// `KokoroAneVoicePack`), so a blend is just arithmetic on two of those blobs.
/// FluidAudio only ever loads a voice *by name* — `store.voicePack(name)` reads
/// `<name>.bin` out of the pack directory — so a blend has to be materialised
/// as a real `.bin` under a synthetic name before it can be spoken.
///
/// Kokoro-FastAPI (Apache-2.0) exposes the same feature as
/// `af_bella(2)+af_heart(1)`; this is that, normalised, content-addressed, and
/// spherically interpolated.
nonisolated enum KokoroVoiceBlend: Sendable {

    /// One voice and its raw (un-normalised) share of the mix.
    struct Component: Sendable, Equatable {
        var voice: String
        var weight: Double

        init(voice: String, weight: Double) {
            self.voice = voice
            self.weight = weight
        }
    }

    enum Failure: Error, Equatable {
        case emptyRecipe
        case invalidWeight(Double)
        case invalidVoiceName(String)
        case wrongElementCount(Int)
    }

    // MARK: - Layout

    /// Mirrors `KokoroAneConstants.voicePackRows` / `voicePackCols`. Duplicated
    /// rather than imported because those live behind `canImport(FluidAudio)`
    /// and this type has to stay loadable — and testable — without the 180 MB
    /// model pack. `KokoroVoiceBlendTests` pins the numbers.
    static let rows = 510
    static let columns = 256
    /// `[0..<128]` is `style_timbre`, `[128..<256]` is `style_s`.
    static let halfColumns = 128
    static let elementCount = rows * columns

    /// Synthetic-name prefix. Deliberately *not* a two-letter locale/gender
    /// pair, which is what `KokoroVoiceCatalog.voice(forIdentifier:)` requires:
    /// that keeps every blend out of the voice picker for free, with no change
    /// to the catalog. Blends are a derived cache addressed by an opaque
    /// digest — a picker should offer the shipped voice set and let a future
    /// blend UI present recipes, not hashes.
    static let namePrefix = "blend_"
    /// 64 bits of SHA-256. A collision would silently serve the wrong voice; at
    /// `cacheLimit` entries the odds are around 10^-17.
    static let digestLength = 16

    /// Blends are derived data at 510 * 256 * 4 = 510 KB each, and a slider can
    /// mint an unbounded number of them. Keep only the most recently used.
    static let cacheLimit = 8

    // MARK: - Recipes

    /// Canonical form of a recipe: duplicates merged, weights normalised to sum
    /// to 1, sorted by voice name, plus the deterministic synthetic voice name.
    ///
    /// Weights are quantised to parts-per-million before hashing *and* before
    /// blending, so the name is a true function of the bytes: two recipes that
    /// differ only by float noise resolve to the same cached `.bin`.
    ///
    /// A recipe that reduces to a single voice returns that voice's own name —
    /// there is nothing to blend, and no reason to write a 510 KB copy of a
    /// file that is already on disk.
    static func canonical(
        _ components: [Component]
    ) throws -> (recipe: [Component], identifier: String) {
        guard !components.isEmpty else { throw Failure.emptyRecipe }

        var merged: [String: Double] = [:]
        for component in components {
            guard isPlainVoiceName(component.voice) else {
                throw Failure.invalidVoiceName(component.voice)
            }
            guard component.weight.isFinite, component.weight >= 0 else {
                throw Failure.invalidWeight(component.weight)
            }
            merged[component.voice, default: 0] += component.weight
        }

        let names = merged.keys.sorted()
        // Guard the total before scaling: a weight near `.greatestFiniteMagnitude`
        // would overflow `Int` on the way to parts-per-million.
        let total = names.reduce(0.0) { $0 + merged[$1, default: 0] }
        guard total.isFinite, total > 0 else { throw Failure.invalidWeight(total) }

        var parts: [(voice: String, share: Int)] = []
        for name in names {
            let share = Int(((merged[name, default: 0] / total) * 1_000_000).rounded())
            if share > 0 { parts.append((name, share)) }
        }
        let totalShares = parts.reduce(0) { $0 + $1.share }
        guard totalShares > 0 else { throw Failure.invalidWeight(total) }

        let recipe = parts.map {
            Component(voice: $0.voice, weight: Double($0.share) / Double(totalShares))
        }
        if recipe.count == 1 { return (recipe, recipe[0].voice) }

        let canonicalText = parts.map { "\($0.voice):\($0.share)" }.joined(separator: "|")
        let digest = SHA256.hash(data: Data(canonicalText.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(digestLength)
        return (recipe, namePrefix + digest)
    }

    /// True for names this type minted. Also the delete-guard for `prune`.
    static func isBlend(_ identifier: String) -> Bool {
        identifier.hasPrefix(namePrefix) && identifier.count == namePrefix.count + digestLength
    }

    /// Letters, digits and `_` only, ASCII. Three reasons, all load-bearing:
    /// FluidAudio's `ensureVoicePack` strips every other character from the
    /// name before looking for `<name>.bin` (so a hyphen would make it miss the
    /// file and try to download it); the name becomes a path component here;
    /// and a blend of a blend would dangle once `prune` evicted its source.
    private static func isPlainVoiceName(_ voice: String) -> Bool {
        !voice.isEmpty
            && !isBlend(voice)
            && voice.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    // MARK: - Blending

    /// SLERP two `[510, 256]` blobs; `ratio` is the share taken from `rhs`.
    ///
    /// **Granularity: one interpolation per half-row** — 510 rows x 2 halves =
    /// 1020 independent slerps.
    ///
    /// The 130,560 floats are not one embedding, so a whole-tensor slerp is
    /// wrong: each row is the complete style vector for one phoneme-length
    /// bucket (`KokoroAneVoicePack.slice(for:)` picks exactly one row and
    /// ignores the other 509), and within a row the two halves are *different*
    /// embeddings consumed by different graph stages — `[0..<128]`
    /// `style_timbre` feeds Noise + Vocoder, `[128..<256]` `style_s` feeds
    /// PostAlbert + Prosody. A single global angle would be dominated by
    /// whichever sub-vector carries the largest norm and would drag all the
    /// others off their own great circles.
    ///
    /// Per-row is closer but still couples timbre to prosody: a 256-d rotation
    /// bends the timbre half to keep the concatenation on one sphere. Half-row
    /// is the exact granularity at which the model reads the data, so it is the
    /// granularity that has a direction worth preserving.
    static func slerp(_ lhs: [Float], _ rhs: [Float], ratio: Double) throws -> [Float] {
        guard lhs.count == elementCount else { throw Failure.wrongElementCount(lhs.count) }
        guard rhs.count == elementCount else { throw Failure.wrongElementCount(rhs.count) }

        var result = [Float](repeating: 0, count: elementCount)
        for base in stride(from: 0, to: elementCount, by: halfColumns) {
            slerpSegment(lhs, rhs, base: base, ratio: ratio, into: &result)
        }
        return result
    }

    /// Blend a whole recipe. Weights are normalised here too, so the pure maths
    /// stays testable without touching the filesystem.
    static func blendedStorage(_ storages: [[Float]], weights: [Double]) throws -> [Float] {
        guard !storages.isEmpty, storages.count == weights.count else { throw Failure.emptyRecipe }
        guard weights.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw Failure.invalidWeight(weights.first { !($0.isFinite && $0 >= 0) } ?? 0)
        }
        let total = weights.reduce(0, +)
        guard total.isFinite, total > 0 else { throw Failure.invalidWeight(total) }

        // ponytail: sequential fold, not a true spherical (Karcher) barycentre.
        // For n > 2 the result depends slightly on the fold order; `canonical`
        // sorts by voice name so it is at least deterministic. Swap in an
        // iterative Karcher mean if three-way blends ever sound off.
        var result = storages[0]
        guard result.count == elementCount else { throw Failure.wrongElementCount(result.count) }
        var accumulated = weights[0]
        for index in 1..<storages.count {
            let weight = weights[index]
            let running = accumulated + weight
            guard running > 0 else { continue }
            result = try slerp(result, storages[index], ratio: weight / running)
            accumulated = running
        }
        return result
    }

    /// One 128-d half-row.
    ///
    /// Direction is interpolated spherically and magnitude *linearly*, rather
    /// than running the textbook formula on the raw vectors: the textbook form
    /// only preserves magnitude when both inputs share a norm, and two voices
    /// generally do not. Splitting them makes the output norm exactly
    /// `(1-t)|lhs| + t|rhs|`, which is the whole reason for not using lerp — a
    /// weighted mean of two vectors pointing apart shrinks the resultant and
    /// audibly flattens the voice.
    private static func slerpSegment(
        _ lhs: [Float],
        _ rhs: [Float],
        base: Int,
        ratio: Double,
        into result: inout [Float]
    ) {
        let end = base + halfColumns
        // Double for the reductions: 128 fp32 accumulations, and `acos` loses
        // its footing fast near the poles.
        var lhsNorm = 0.0
        var rhsNorm = 0.0
        var dot = 0.0
        for index in base..<end {
            let left = Double(lhs[index])
            let right = Double(rhs[index])
            lhsNorm += left * left
            rhsNorm += right * right
            dot += left * right
        }
        lhsNorm = lhsNorm.squareRoot()
        rhsNorm = rhsNorm.squareRoot()

        // A zero vector has no direction to rotate towards, and dividing by its
        // norm is how NaN gets into a voice pack. Lerp instead.
        guard lhsNorm > 1e-12, rhsNorm > 1e-12 else {
            lerpSegment(lhs, rhs, base: base, ratio: ratio, into: &result)
            return
        }

        let cosine = min(max(dot / (lhsNorm * rhsNorm), -1), 1)
        // |cos| ~ 1 is the unstable band: sin(omega) -> 0 puts a near-zero in
        // the denominator. Near-parallel (cos ~ +1) slerp and lerp already
        // agree to fp32 noise, so nothing is lost. Near-antiparallel (cos ~ -1)
        // there is no unique great circle joining the two — every rotation
        // plane is equally valid, so no rotation is more defensible than an
        // arbitrary one. Both fall back to lerp, which stays finite either way.
        guard abs(cosine) < 0.9995 else {
            lerpSegment(lhs, rhs, base: base, ratio: ratio, into: &result)
            return
        }

        let omega = acos(cosine)
        let sinOmega = sin(omega)
        let targetNorm = (1 - ratio) * lhsNorm + ratio * rhsNorm
        let lhsCoefficient = Float(sin((1 - ratio) * omega) / sinOmega * targetNorm / lhsNorm)
        let rhsCoefficient = Float(sin(ratio * omega) / sinOmega * targetNorm / rhsNorm)
        for index in base..<end {
            result[index] = lhsCoefficient * lhs[index] + rhsCoefficient * rhs[index]
        }
    }

    private static func lerpSegment(
        _ lhs: [Float],
        _ rhs: [Float],
        base: Int,
        ratio: Double,
        into result: inout [Float]
    ) {
        let lhsCoefficient = Float(1 - ratio)
        let rhsCoefficient = Float(ratio)
        for index in base..<(base + halfColumns) {
            result[index] = lhsCoefficient * lhs[index] + rhsCoefficient * rhs[index]
        }
    }

    // MARK: - Materialising

    /// Blend `components` into a `.bin` in the pack directory and return the
    /// voice name to hand to FluidAudio (`store.voicePack(name)`).
    ///
    /// The name is content-addressed, so an existing file *is* the cache: this
    /// only reads and writes for a recipe it has not seen recently.
    @discardableResult
    static func ensure(
        _ components: [Component],
        in directory: URL = KokoroAneAvailability.packVoicesDirectory
    ) throws -> String {
        let (recipe, identifier) = try canonical(components)
        guard recipe.count > 1 else { return identifier }

        let fileManager = FileManager.default
        let url = directory.appendingPathComponent("\(identifier).bin")
        if fileManager.fileExists(atPath: url.path) {
            // Same name means same bytes. Touch it so `prune` keeps the blends
            // that are actually being listened to.
            try? fileManager.setAttributes(
                [.modificationDate: Date()], ofItemAtPath: url.path
            )
            return identifier
        }

        let storages = try recipe.map {
            try loadStorage(at: directory.appendingPathComponent("\($0.voice).bin"))
        }
        let blended = try blendedStorage(storages, weights: recipe.map(\.weight))

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try blended.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: url, options: .atomic)
        prune(in: directory, keeping: identifier)
        return identifier
    }

    /// Flat host-order fp32, byte-for-byte what `KokoroAneVoicePack.load` reads.
    /// Copied through a `[Float]` rather than rebound in place because `Data`'s
    /// backing store carries no alignment guarantee.
    static func loadStorage(at url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        let expected = elementCount * MemoryLayout<Float>.size
        guard data.count == expected else {
            throw Failure.wrongElementCount(data.count / MemoryLayout<Float>.size)
        }
        var storage = [Float](repeating: 0, count: elementCount)
        _ = storage.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return storage
    }

    /// Evict least-recently-used blends so the cache stays at `cacheLimit`.
    /// Best-effort: a blend that survives an eviction race is only wasted disk,
    /// and one that loses it is regenerated on next use.
    private static func prune(in directory: URL, keeping identifier: String) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let blends = entries.filter {
            let name = $0.deletingPathExtension().lastPathComponent
            return $0.pathExtension == "bin" && isBlend(name) && name != identifier
        }
        let excess = blends.count + 1 - cacheLimit
        guard excess > 0 else { return }

        let oldestFirst = blends.sorted { modifiedAt($0) < modifiedAt($1) }
        for url in oldestFirst.prefix(excess) {
            try? fileManager.removeItem(at: url)
        }
    }

    private static func modifiedAt(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
    }
}
