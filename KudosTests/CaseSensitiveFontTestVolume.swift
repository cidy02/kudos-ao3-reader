import Foundation
@testable import Kudos

/// A mounted APFS test volume supplied by Scripts/test-casefold-fonts.sh.
///
/// The iOS Simulator test bundle cannot run hdiutil, and a host /tmp mount is
/// outside its sandbox. The host-side harness mounts the image inside the
/// installed simulator app's container, then this helper proves the volume really preserves
/// case variants before routing production restore code through it.
@MainActor
enum CaseSensitiveFontTestVolume {
    private static let sentinelName = ".kudos-case-sensitive-fonts"

    static func withFontsDirectory<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        let mountedDirectory = try requiredMountedDirectory()
        let testDirectory = mountedDirectory.appendingPathComponent(
            "KudosFontRestoreTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDirectory) }

        try verifyCaseSensitivity(in: testDirectory)
        let previousOverride = Storage.fontsDirectoryOverride
        Storage.fontsDirectoryOverride = testDirectory
        defer { Storage.fontsDirectoryOverride = previousOverride }
        return try await operation()
    }

    private static func requiredMountedDirectory() throws -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let directory = applicationSupport.appendingPathComponent(
            "KudosCaseSensitiveFonts",
            isDirectory: true
        )
        guard FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(sentinelName).path
        ) else {
            throw CaseSensitiveFontTestVolumeError.missingSentinel(directory.path)
        }
        return directory
    }

    private static func verifyCaseSensitivity(in directory: URL) throws {
        let baseName = "CaseProbe-\(UUID().uuidString)"
        let upperURL = directory.appendingPathComponent("\(baseName.uppercased()).ttf")
        let lowerURL = directory.appendingPathComponent("\(baseName.lowercased()).ttf")
        defer {
            try? FileManager.default.removeItem(at: upperURL)
            try? FileManager.default.removeItem(at: lowerURL)
        }

        try Data("upper".utf8).write(to: upperURL, options: .withoutOverwriting)
        try Data("lower".utf8).write(to: lowerURL, options: .withoutOverwriting)
        let names = try Set(FileManager.default.contentsOfDirectory(atPath: directory.path))
        guard names.contains(upperURL.lastPathComponent),
              names.contains(lowerURL.lastPathComponent),
              try Data(contentsOf: upperURL) == Data("upper".utf8),
              try Data(contentsOf: lowerURL) == Data("lower".utf8)
        else {
            throw CaseSensitiveFontTestVolumeError.notCaseSensitive(directory.path)
        }
    }
}

private enum CaseSensitiveFontTestVolumeError: LocalizedError {
    case missingSentinel(String)
    case notCaseSensitive(String)

    var errorDescription: String? {
        switch self {
        case let .missingSentinel(path):
            "Case-fold test volume is unavailable at \(path); run Scripts/test-casefold-fonts.sh."
        case let .notCaseSensitive(path):
            "Case-fold test volume at \(path) cannot preserve Case.ttf and case.ttf separately."
        }
    }
}
