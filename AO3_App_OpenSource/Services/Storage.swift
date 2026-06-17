import Foundation

/// Filesystem locations used by the app. `nonisolated` so the off-main
/// `AO3Client` actor can build download paths without crossing actors.
nonisolated enum Storage {
    /// Permanent home for user-imported fonts.
    static var fontsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Fonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Permanent home for downloaded EPUBs.
    static var worksDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Works", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Scratch space where EPUBs are unzipped for reading.
    static func readerDirectory(for id: UUID) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Reader/\(id.uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Temporary destination for an in-flight download.
    static func tempDownloadURL(suggestedName: String) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = suggestedName.isEmpty ? "\(UUID().uuidString).epub" : suggestedName
        return dir.appendingPathComponent(name)
    }
}
