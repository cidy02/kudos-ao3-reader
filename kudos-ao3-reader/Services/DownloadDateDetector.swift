import Foundation

nonisolated enum DownloadDateSource: String, Equatable, Sendable {
    case file
    case ao3Generated
    case importTime
}

nonisolated struct DownloadDateDetection: Equatable, Sendable {
    let date: Date
    let source: DownloadDateSource
}

/// Chooses the best available download date without touching app or file state.
nonisolated enum DownloadDateDetector {
    static let freshCopyWindow: TimeInterval = 5 * 60

    static func detect(
        fileCreated: Date?,
        fileModified: Date?,
        epubGeneratedAt: Date?,
        now: Date
    ) -> DownloadDateDetection {
        let fileDate = [fileCreated, fileModified].compactMap { $0 }.min()
        if let fileDate,
           fileDate < now.addingTimeInterval(-freshCopyWindow),
           epubGeneratedAt.map({ fileDate >= $0 }) ?? true {
            return DownloadDateDetection(date: fileDate, source: .file)
        }
        if let epubGeneratedAt {
            return DownloadDateDetection(date: epubGeneratedAt, source: .ao3Generated)
        }
        return DownloadDateDetection(date: now, source: .importTime)
    }

    static func parseEPUBTimestamp(_ value: String) -> Date? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
