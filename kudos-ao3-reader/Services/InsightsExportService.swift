import Foundation
import SwiftData
import UniformTypeIdentifiers

enum InsightsExportFormat: String, CaseIterable, Identifiable, Sendable {
    case csv
    case json

    var id: String { rawValue }

    var title: String {
        switch self {
        case .csv: return "CSV"
        case .json: return "JSON"
        }
    }

    var fileExtension: String { rawValue }

    var contentType: UTType {
        switch self {
        case .csv: return .commaSeparatedText
        case .json: return .json
        }
    }
}

/// Top-level JSON export payload matching D6 (`sittings`, `statuses`, `reasons`, `notes`).
nonisolated struct InsightsExportDocument: Codable, Equatable, Sendable {
    var schemaVersion: Int = 1
    var exportedAt: Date
    var discreetMode: Bool
    var sittings: [Sitting]
    var statuses: [WorkStatus]
    var reasons: [StopReasonRecord]
    var notes: [NoteRecord]

    nonisolated struct Sitting: Codable, Equatable, Sendable {
        var sessionID: UUID
        var workID: UUID
        var workTitle: String
        var authors: [String]
        var fandoms: [String]
        var relationships: [String]
        var characters: [String]
        var tags: [String]
        var mode: String
        var playbackRate: Double?
        var startedAt: Date
        var endedAt: Date
        var durationSeconds: Double
        var activeSeconds: Double?
        var wordsRead: Int
        var wordCount: Int
        var wordUnit: String
        var startProgress: Double?
        var endingProgress: Double
        var chapterCountAtVisit: Int
        var didFinish: Bool
        var rating: String
        var warnings: [String]
        var categories: [String]
        var language: String
        var isCompleteAtVisit: Bool
    }

    nonisolated struct WorkStatus: Codable, Equatable, Sendable {
        var workID: UUID
        var workTitle: String
        var authors: [String]
        var fandoms: [String]
        var relationships: [String]
        var characters: [String]
        var tags: [String]
        var status: String
        var explicitStatus: String
        var progress: Double?
        var wordCount: Int
        var wordUnit: String
        var statusChangedAt: Date?
        var stoppedAt: Date?
        var stopReason: String
        var stopTag: String
        var stopNote: String
        var stackThreshold: Int
        var isFinished: Bool
    }

    nonisolated struct StopReasonRecord: Codable, Equatable, Sendable {
        var workID: UUID
        var workTitle: String
        var reason: String
        var stopTag: String
        var stoppedAt: Date?
    }

    nonisolated struct NoteRecord: Codable, Equatable, Sendable {
        var workID: UUID
        var workTitle: String
        var status: String
        var reason: String
        var note: String
        var updatedAt: Date?
    }
}

nonisolated struct InsightsResetCounts: Equatable, Sendable {
    var sessionCount: Int
    var workCount: Int
}

@MainActor
enum InsightsExportService {
    static let csvHeaderColumns: [String] = [
        "record_type",
        "session_id",
        "work_id",
        "work_title",
        "author",
        "fandoms",
        "mode",
        "started_at",
        "ended_at",
        "duration_seconds",
        "active_seconds",
        "words_read",
        "word_count",
        "word_unit",
        "start_progress",
        "ending_progress",
        "did_finish",
        "reading_status",
        "status_changed_at",
        "stopped_at",
        "stop_reason",
        "stop_tag",
        "stop_note"
    ]

    /// Builds the structured JSON document through `options.filter(...)` and applies
    /// Discreet Mode when enabled.
    static func makeDocument(
        works: [SavedWork],
        sessions: [ReadingSession],
        options: InsightsOptions = InsightsOptions(),
        aliases: TagAliasResolver = .empty,
        exportedAt: Date = Date()
    ) -> InsightsExportDocument {
        let filtered = options.filter(sessions: sessions, works: works, aliases: aliases)
        let sortedWorks = filtered.works.sorted {
            ($0.title, $0.id.uuidString) < ($1.title, $1.id.uuidString)
        }
        let sortedSessions = filtered.sessions.sorted {
            ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString)
        }
        let worksByID = Dictionary(
            sortedWorks.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let readBySession = ReadingLogService.wordsRead(sessions: sortedSessions, works: sortedWorks)
        let masker = options.discreetMode
            ? makeExportMasker(works: sortedWorks, sessions: sortedSessions, aliases: aliases)
            : .empty

        let context = ExportBuildContext(
            options: options,
            aliases: aliases,
            masker: masker
        )
        let exportedSittings = sortedSessions.map { session in
            makeSitting(
                session: session,
                work: worksByID[session.workID],
                wordsRead: readBySession[session.id] ?? 0,
                context: context
            )
        }
        let exportedStatuses = sortedWorks.map { work in
            makeWorkStatus(work: work, context: context)
        }

        let exportedReasons: [InsightsExportDocument.StopReasonRecord] = exportedStatuses.compactMap { status in
            guard status.status == SavedWork.InsightsReadingStatus.stopped.rawValue
                || !status.stopReason.isEmpty
                || !status.stopTag.isEmpty
            else { return nil }
            return InsightsExportDocument.StopReasonRecord(
                workID: status.workID,
                workTitle: status.workTitle,
                reason: status.stopReason,
                stopTag: status.stopTag,
                stoppedAt: status.stoppedAt
            )
        }

        let exportedNotes: [InsightsExportDocument.NoteRecord] = exportedStatuses.compactMap { status in
            guard !status.stopNote.isEmpty else { return nil }
            return InsightsExportDocument.NoteRecord(
                workID: status.workID,
                workTitle: status.workTitle,
                status: status.status,
                reason: status.stopReason,
                note: status.stopNote,
                updatedAt: status.stoppedAt ?? status.statusChangedAt
            )
        }

        return InsightsExportDocument(
            schemaVersion: 1,
            exportedAt: exportedAt,
            discreetMode: options.discreetMode,
            sittings: exportedSittings,
            statuses: exportedStatuses,
            reasons: exportedReasons,
            notes: exportedNotes
        )
    }

    private struct ExportBuildContext {
        var options: InsightsOptions
        var aliases: TagAliasResolver
        var masker: InsightsDiscreetMasker
    }

    private static func makeSitting(
        session: ReadingSession,
        work: SavedWork?,
        wordsRead: Int,
        context: ExportBuildContext
    ) -> InsightsExportDocument.Sitting {
        let rawTitle = session.workTitle.isEmpty ? (work?.title ?? "") : session.workTitle
        let workAuthor = work?.author.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawAuthors = !session.authorAccounts.isEmpty
            ? session.authorAccounts
            : (workAuthor.isEmpty ? [] : [workAuthor])
        let rawFandoms = !session.fandoms.isEmpty ? session.fandoms : (work?.workFandoms ?? [])
        let rawRelationships = !session.relationships.isEmpty
            ? session.relationships : (work?.workRelationships ?? [])
        let rawCharacters = !session.characters.isEmpty
            ? session.characters : (work?.workCharacters ?? [])
        let workFallbackTags = work?.workFreeforms.isEmpty == false
            ? (work?.workFreeforms ?? [])
            : (work?.workTags ?? [])
        let rawTags = !session.freeformTags.isEmpty ? session.freeformTags : workFallbackTags
        let rawWarnings = !session.warnings.isEmpty ? session.warnings : (work?.workWarnings ?? [])
        let rawCategories = !session.categories.isEmpty ? session.categories : (work?.workCategories ?? [])

        let resolvedFandoms = context.aliases.resolvedUnique(rawFandoms, kind: .fandom)
        let resolvedShips = context.aliases.resolvedUnique(rawRelationships, kind: .relationship)
        let resolvedChars = context.aliases.resolvedUnique(rawCharacters, kind: .character)
        let resolvedTags = context.aliases.resolvedUnique(rawTags, kind: .freeform)
        let mask = context.options.discreetMode
        let masker = context.masker

        return InsightsExportDocument.Sitting(
            sessionID: session.id,
            workID: session.workID,
            workTitle: mask ? masker.work(id: session.workID, title: rawTitle) : rawTitle,
            authors: mask ? rawAuthors.map { masker.author($0) } : rawAuthors,
            fandoms: mask ? resolvedFandoms.map { masker.fandom($0) } : resolvedFandoms,
            relationships: mask ? resolvedShips.map { masker.ship($0) } : resolvedShips,
            characters: mask ? resolvedChars.map { masker.character($0) } : resolvedChars,
            tags: mask ? resolvedTags.map { masker.tag($0) } : resolvedTags,
            mode: session.mode.rawValue,
            playbackRate: session.playbackRate,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            durationSeconds: session.durationSeconds,
            activeSeconds: session.activeSeconds,
            wordsRead: wordsRead,
            wordCount: session.wordCount,
            wordUnit: (work?.wordUnit ?? .words).rawValue,
            startProgress: session.startProgress,
            endingProgress: session.endingProgress,
            chapterCountAtVisit: session.chapterCountAtVisit,
            didFinish: session.didFinish,
            rating: session.rating.isEmpty ? (work?.rating ?? "") : session.rating,
            warnings: rawWarnings,
            categories: rawCategories,
            language: session.language.isEmpty ? (work?.language ?? "") : session.language,
            isCompleteAtVisit: session.isCompleteAtVisit
        )
    }

    private static func makeWorkStatus(
        work: SavedWork,
        context: ExportBuildContext
    ) -> InsightsExportDocument.WorkStatus {
        let rawAuthor = work.author.trimmingCharacters(in: .whitespacesAndNewlines)
        let authors = rawAuthor.isEmpty ? [] : [rawAuthor]
        let resolvedFandoms = context.aliases.resolvedUnique(work.workFandoms, kind: .fandom)
        let resolvedShips = context.aliases.resolvedUnique(work.workRelationships, kind: .relationship)
        let resolvedChars = context.aliases.resolvedUnique(work.workCharacters, kind: .character)
        let tagSource = work.workFreeforms.isEmpty ? work.workTags : work.workFreeforms
        let resolvedTags = context.aliases.resolvedUnique(tagSource, kind: .freeform)
        let trimmedStopTag = work.stopTag.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedStopTag = trimmedStopTag.isEmpty ? "" : context.aliases.resolve(trimmedStopTag, kind: .freeform)
        let trimmedNote = work.stopNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let mask = context.options.discreetMode
        let masker = context.masker

        return InsightsExportDocument.WorkStatus(
            workID: work.id,
            workTitle: mask ? masker.work(id: work.id, title: work.title) : work.title,
            authors: mask ? authors.map { masker.author($0) } : authors,
            fandoms: mask ? resolvedFandoms.map { masker.fandom($0) } : resolvedFandoms,
            relationships: mask ? resolvedShips.map { masker.ship($0) } : resolvedShips,
            characters: mask ? resolvedChars.map { masker.character($0) } : resolvedChars,
            tags: mask ? resolvedTags.map { masker.tag($0) } : resolvedTags,
            status: work.insightsReadingStatus.rawValue,
            explicitStatus: work.readingStatusRaw,
            progress: work.readingProgress,
            wordCount: work.wordCount,
            wordUnit: work.wordUnit.rawValue,
            statusChangedAt: work.statusChangedAt,
            stoppedAt: work.stoppedAt,
            stopReason: work.stopReasonRaw,
            stopTag: mask && !resolvedStopTag.isEmpty
                ? masker.tag(resolvedStopTag) : resolvedStopTag,
            stopNote: mask && !trimmedNote.isEmpty
                ? "[Hidden in Discreet Mode]" : trimmedNote,
            stackThreshold: work.stackThreshold,
            isFinished: work.isFinished
        )
    }

    static func jsonData(
        works: [SavedWork],
        sessions: [ReadingSession],
        options: InsightsOptions = InsightsOptions(),
        aliases: TagAliasResolver = .empty,
        exportedAt: Date = Date()
    ) throws -> Data {
        let document = makeDocument(
            works: works,
            sessions: sessions,
            options: options,
            aliases: aliases,
            exportedAt: exportedAt
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    static func csvString(
        works: [SavedWork],
        sessions: [ReadingSession],
        options: InsightsOptions = InsightsOptions(),
        aliases: TagAliasResolver = .empty,
        exportedAt: Date = Date()
    ) -> String {
        let document = makeDocument(
            works: works,
            sessions: sessions,
            options: options,
            aliases: aliases,
            exportedAt: exportedAt
        )
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var lines: [String] = []
        lines.reserveCapacity(1 + document.sittings.count + document.statuses.count)
        lines.append(csvHeaderColumns.joined(separator: ","))

        for sitting in document.sittings {
            let row: [String] = [
                "sitting",
                sitting.sessionID.uuidString,
                sitting.workID.uuidString,
                sitting.workTitle,
                sitting.authors.joined(separator: "; "),
                sitting.fandoms.joined(separator: "; "),
                sitting.mode,
                iso.string(from: sitting.startedAt),
                iso.string(from: sitting.endedAt),
                formatDouble(sitting.durationSeconds),
                sitting.activeSeconds.map(formatDouble) ?? "",
                String(sitting.wordsRead),
                String(sitting.wordCount),
                sitting.wordUnit,
                sitting.startProgress.map(formatDouble) ?? "",
                formatDouble(sitting.endingProgress),
                sitting.didFinish ? "true" : "false",
                "",
                "",
                "",
                "",
                "",
                ""
            ]
            lines.append(row.map(csvEscape).joined(separator: ","))
        }

        for status in document.statuses {
            let row: [String] = [
                "status",
                "",
                status.workID.uuidString,
                status.workTitle,
                status.authors.joined(separator: "; "),
                status.fandoms.joined(separator: "; "),
                "",
                "",
                "",
                "",
                "",
                "",
                String(status.wordCount),
                status.wordUnit,
                "",
                status.progress.map(formatDouble) ?? "",
                status.isFinished ? "true" : "false",
                status.status,
                status.statusChangedAt.map { iso.string(from: $0) } ?? "",
                status.stoppedAt.map { iso.string(from: $0) } ?? "",
                status.stopReason,
                status.stopTag,
                status.stopNote
            ]
            lines.append(row.map(csvEscape).joined(separator: ","))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    static func writeTemporaryExportFile(
        format: InsightsExportFormat,
        works: [SavedWork],
        sessions: [ReadingSession],
        options: InsightsOptions = InsightsOptions(),
        aliases: TagAliasResolver = .empty,
        now: Date = Date()
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InsightsExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let stamp = dateFormatter.string(from: now)
        let fileURL = directory.appendingPathComponent(
            "Kudos-Reading-History-\(stamp).\(format.fileExtension)"
        )

        let data: Data
        switch format {
        case .csv:
            data = Data(csvString(
                works: works,
                sessions: sessions,
                options: options,
                aliases: aliases,
                exportedAt: now
            ).utf8)
        case .json:
            data = try jsonData(
                works: works,
                sessions: sessions,
                options: options,
                aliases: aliases,
                exportedAt: now
            )
        }
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    // MARK: - Reset Insights (D6)

    static func resetCounts(in context: ModelContext) -> InsightsResetCounts {
        let sessions = (try? context.fetch(FetchDescriptor<ReadingSession>())) ?? []
        let distinctWorks = Set(sessions.map(\.workID))
        return InsightsResetCounts(sessionCount: sessions.count, workCount: distinctWorks.count)
    }

    /// Deletes all local `ReadingSession` rows via `ReadingLogService.delete(_:in:)`,
    /// minting signed sync tombstones without modifying any `SavedWork`, progress, or status.
    @discardableResult
    static func resetReadingLog(in context: ModelContext) throws -> Int {
        let sessions = try context.fetch(FetchDescriptor<ReadingSession>())
        let deletedCount = sessions.count
        for session in sessions {
            ReadingLogService.delete(session, in: context)
        }
        let remaining = try context.fetchCount(FetchDescriptor<ReadingSession>())
        if remaining > 0 {
            throw NSError(
                domain: "InsightsReset",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not delete all reading log entries."]
            )
        }
        return deletedCount
    }

    // MARK: - Helpers

    private static func makeExportMasker(
        works: [SavedWork],
        sessions: [ReadingSession],
        aliases: TagAliasResolver
    ) -> InsightsDiscreetMasker {
        var builder = InsightsDiscreetMasker.Builder(aliases: aliases)
        for work in works {
            builder.registerWork(id: work.id, title: work.title)
            builder.registerAuthor(work.author)
            work.workFandoms.forEach { builder.registerFandom($0) }
            work.workRelationships.forEach { builder.registerShip($0) }
            work.workCharacters.forEach { builder.registerCharacter($0) }
            (work.workFreeforms + work.workTags).forEach { builder.registerTag($0) }
            if !work.stopTag.isEmpty { builder.registerTag(work.stopTag) }
        }
        for session in sessions {
            builder.registerWork(id: session.workID, title: session.workTitle)
            session.authorAccounts.forEach { builder.registerAuthor($0) }
            session.fandoms.forEach { builder.registerFandom($0) }
            session.relationships.forEach { builder.registerShip($0) }
            session.characters.forEach { builder.registerCharacter($0) }
            session.freeformTags.forEach { builder.registerTag($0) }
        }
        return builder.build()
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    private static func formatDouble(_ value: Double) -> String {
        if value.rounded() == value, value.isFinite, abs(value) < Double(Int.max) {
            return String(Int(value))
        }
        return String(format: "%.4f", value)
    }
}
