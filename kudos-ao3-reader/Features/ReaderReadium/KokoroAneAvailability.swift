import Foundation

/// On-disk Neural Engine Kokoro pack. Playback is allowed whenever the pack
/// is installed; this does not second-guess the OS.
nonisolated enum KokoroAneAvailability: Sendable {
    static let readyMarkerFileName = ".kudos-kokoro-ane-ready"

    static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("TTS_Models/kokoro-ane", isDirectory: true)
    }

    static var readyMarkerURL: URL {
        modelsDirectory.appendingPathComponent(readyMarkerFileName)
    }

    /// Where the unpacked pack's `<voice>.bin` style vectors live.
    ///
    /// Mirrors `FluidAudio.TtsCacheDirectory.ensure()` — Application Support
    /// (deliberately *not* Caches, which the system can reclaim under disk
    /// pressure) plus the `Models/kokoro-82m-coreml/ANE` layout that
    /// `CoreMLKokoroPackInstaller` writes. Duplicated rather than called
    /// because that type lives behind `canImport(FluidAudio)`;
    /// `KokoroVoiceCatalogTests` pins the two together.
    static var packVoicesDirectory: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return support
            .appendingPathComponent("fluidaudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("kokoro-82m-coreml", isDirectory: true)
            .appendingPathComponent("ANE", isDirectory: true)
    }

    static var isPackInstalled: Bool {
        guard let marker = try? String(contentsOf: readyMarkerURL, encoding: .utf8) else {
            return false
        }
        return marker.contains(KokoroGitHubPack.tag)
    }

    /// Installed and eligible for the Core ML synthesizer.
    static var isUsableForPlayback: Bool {
        isPackInstalled
    }

    static func markInstalled() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = modelsDirectory
        try directory.setResourceValues(values)
        try Data("\(KokoroGitHubPack.tag)\n".utf8).write(to: readyMarkerURL, options: .atomic)
    }
}
