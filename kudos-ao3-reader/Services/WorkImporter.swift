import Foundation
import OSLog
import SwiftData
import SwiftSoup

// Import funnels (AO3 download + user-file) and their shared iCloud-materialization
// helper are cohesive; avoid a behavior-risking split for lint.
// swiftlint:disable file_length

/// Imports a downloaded EPUB into the library: reads its metadata, moves the
/// file into permanent storage, and inserts a `SavedWork`. Returns the inserted
/// work, or throws if the file couldn't be saved. Shared by the Browse tab's
/// download interception and the native AO3 search/download flow.
///
/// Metadata extraction is best-effort: a work still imports (with a filename
/// fallback title) if its metadata can't be read, since the file itself is valid.
@MainActor
@discardableResult
func importEPUB(
    _ tempURL: URL,
    source: URL?,
    isComplete: Bool = false,
    seriesURL: String = "",
    knownChapterCount: Int = 0,
    into context: ModelContext
) async throws -> SavedWork {
    // Reading the EPUB's metadata pulls the whole file into memory and unzips it, so
    // run that off the main actor; everything below (SwiftData + the file move) stays
    // on the main actor where it belongs.
    let meta = await Task.detached(priority: .userInitiated) {
        try? EPUBDocument.metadata(ofEPUBAt: tempURL)
    }.value
    if meta == nil { Log.library.notice("EPUB metadata unreadable; importing with the filename as title") }
    let fallbackTitle = tempURL.deletingPathExtension().lastPathComponent
    let title = (meta?.title).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle

    // Callers pre-check for an existing copy before the multi-second EPUB download,
    // so two concurrent acquisitions of the same work can both pass that check and
    // land here together. Re-check now and merge into any existing record instead of
    // inserting a duplicate; a match sitting in Recently Deleted is revived first
    // (with all its reading progress) rather than left scheduled for permanent deletion.
    if let source, let existing = existingWork(forSource: source, in: context) {
        let revived = existing.isPendingDeletion
        if revived {
            PreservedWorkService.restore(existing, in: context)
        }
        if let meta {
            applyEPUBMetadata(meta, extracted: .empty, localChapterCount: nil, to: existing, fillOnly: true)
        }
        existing.isComplete = isComplete || existing.isComplete
        if existing.seriesURL.isEmpty { existing.seriesURL = seriesURL }
        if existing.ao3WorkID == nil { existing.ao3WorkID = WorkTags.ao3WorkID(from: existing.sourceURL) }
        if existing.ao3SeriesID == nil { existing.ao3SeriesID = ReadingQueueService.ao3SeriesID(from: seriesURL) }
        if existing.knownChapterCount == 0 { existing.knownChapterCount = knownChapterCount }
        do {
            try ReadingQueueService.replaceEPUB(for: existing, with: tempURL)
            existing.hasEPUB = true
        } catch {
            Log.library.error("Couldn't save imported EPUB: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        existing.markModified()
        WorkSearchIndex.reindex(existing)
        try? context.save()
        if revived {
            Log.library.info("Import revived “\(existing.title)” from Recently Deleted")
        } else {
            Log.library.info("Import merged into existing “\(existing.title)”")
        }
        Task { await WorkTags.refreshFromAO3(for: existing, in: context) }
        return existing
    }

    let work = SavedWork(
        title: title,
        author: meta?.author ?? "",
        summary: meta?.summary ?? "",
        sourceURL: source?.absoluteString ?? ""
    )
    if let meta {
        applyEPUBMetadata(
            meta,
            extracted: .empty,
            localChapterCount: nil,
            to: work,
            fillOnly: false
        )
    }
    work.isComplete = isComplete || work.isComplete
    work.seriesURL = seriesURL
    work.ao3WorkID = WorkTags.ao3WorkID(from: work.sourceURL)
    work.ao3SeriesID = ReadingQueueService.ao3SeriesID(from: seriesURL)
    if work.hasEPUB {
        work.epubPreservationStatus = .notPreserved
    }
    // Baseline for update detection: the posted-chapter count at download time, so
    // chapters AO3 adds afterwards surface in Home → Recently Updated. Native imports
    // pass it from the AO3 work page; web imports baseline on the first update check.
    work.knownChapterCount = knownChapterCount

    do {
        try ReadingQueueService.replaceEPUB(for: work, with: tempURL)
        work.hasEPUB = true
    } catch {
        Log.library.error("Couldn't save imported EPUB: \(error.localizedDescription, privacy: .public)")
        throw error
    }

    context.insert(work)
    WorkSearchIndex.reindex(work)
    try? context.save()
    Log.library.info("Imported work “\(title)”")

    // Refresh the work's tags from AO3's live page in the background; the EPUB
    // tags set above stand in until (and if) that succeeds.
    Task { await WorkTags.refreshFromAO3(for: work, in: context) }

    return work
}

// MARK: - User-selected EPUB import

enum UserEPUBImportOutcome {
    case imported(SavedWork)
    case restored(SavedWork)
    case duplicate(SavedWork)

    var work: SavedWork {
        switch self {
        case let .imported(work), let .restored(work), let .duplicate(work):
            work
        }
    }
}

enum UserEPUBImportError: LocalizedError {
    case notLocalFile
    case invalidExtension
    /// A `.fileImporter`-selected file lives in iCloud Drive and wasn't fully
    /// downloaded within the wait window — see `waitForUbiquitousDownload(of:)`.
    case iCloudDownloadTimedOut

    var errorDescription: String? {
        switch self {
        case .notLocalFile:
            "Choose a local EPUB file."
        case .invalidExtension:
            "Choose a file ending in .epub."
        case .iCloudDownloadTimedOut:
            "This file is still downloading from iCloud Drive. Wait for it to finish "
                + "downloading in the Files app, then try importing again."
        }
    }
}

/// Waits for a `.fileImporter`-selected file to finish downloading from iCloud
/// Drive before it's read. The document picker can return a URL to a
/// not-yet-materialized placeholder — e.g. any file showing the cloud-download
/// icon in Files — and reading it immediately (`Data(contentsOf:)`) fails with an
/// opaque "unreadable file" error instead of actually waiting for the download.
/// A no-op for files that are already local (including the common case of
/// picking from "On My iPhone"/"On My Mac").
func waitForUbiquitousDownload(
    of url: URL,
    pollInterval: TimeInterval = 0.3,
    timeout: TimeInterval = 120
) async throws {
    guard let isUbiquitous = try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem,
          isUbiquitous
    else { return }

    // Idempotent: harmless (and necessary) to call even if a download is already
    // in progress or finished — it's how the placeholder actually starts
    // materializing rather than sitting inert until something else touches it.
    try? FileManager.default.startDownloadingUbiquitousItem(at: url)

    let deadline = Date().addingTimeInterval(timeout)
    while true {
        let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            .ubiquitousItemDownloadingStatus
        if status == .current { return }
        guard Date() < deadline else { throw UserEPUBImportError.iCloudDownloadTimedOut }
        try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
    }
}

private nonisolated struct UserEPUBInspection {
    let package: EPUBPackageInspection
    let extracted: ExtractedAO3EPUBMetadata

    var metadata: EPUBMetadata {
        package.metadata
    }

    var title: String {
        firstNonEmpty(metadata.title, extracted.title)
    }

    var author: String {
        firstNonEmpty(metadata.author, extracted.author)
    }

    var summary: String {
        firstNonEmpty(metadata.summary, extracted.summary)
    }

    var sourceURL: String {
        firstNonEmpty(extracted.sourceURL, metadata.sourceURL)
    }

    var rating: String {
        firstNonEmpty(extracted.rating, metadata.rating)
    }

    var publishedDate: String {
        firstNonEmpty(extracted.publishedDate, metadata.publishedDate)
    }

    var updatedDate: String {
        firstNonEmpty(extracted.updatedDate, metadata.updatedDate)
    }

    var localChapterCount: Int {
        package.readableItemCount
    }

    static func inspect(_ url: URL) throws -> Self {
        let package = try EPUBDocument.inspectPackage(ofEPUBAt: url)
        let extracted = AO3EPUBMetadataScanner.scan(url)
        return Self(package: package, extracted: extracted)
    }

    private func firstNonEmpty(_ first: String, _ second: String) -> String {
        first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? second : first
    }
}

@MainActor
func importUserEPUB(_ url: URL, into context: ModelContext) async throws -> UserEPUBImportOutcome {
    guard url.isFileURL else { throw UserEPUBImportError.notLocalFile }
    guard url.pathExtension.localizedCaseInsensitiveCompare("epub") == .orderedSame else {
        throw UserEPUBImportError.invalidExtension
    }

    let inspection = try await Task.detached(priority: .userInitiated) {
        try UserEPUBInspection.inspect(url)
    }.value

    if let duplicate = existingWork(matching: inspection, sourceFile: url, in: context) {
        // A duplicate sitting in Recently Deleted is revived, not reported as "already
        // in your library" — without this the import would silently land in a record
        // still scheduled for permanent deletion.
        let revivedFromRecentlyDeleted = duplicate.isPendingDeletion
        if revivedFromRecentlyDeleted {
            PreservedWorkService.restore(duplicate, in: context)
        }
        applyUserImportMetadata(inspection, to: duplicate, fillOnly: true)
        if !duplicate.hasEPUB {
            try copyImportedEPUB(from: url, to: duplicate.fileURL)
            duplicate.hasEPUB = true
            duplicate.markModified()
            WorkSearchIndex.reindex(duplicate)
            try? context.save()
            Task { await WorkTags.refreshFromAO3(for: duplicate, in: context) }
            return .restored(duplicate)
        }
        duplicate.markModified()
        WorkSearchIndex.reindex(duplicate)
        try? context.save()
        return revivedFromRecentlyDeleted ? .restored(duplicate) : .duplicate(duplicate)
    }

    let fallbackTitle = url.deletingPathExtension().lastPathComponent
    let work = SavedWork(
        title: inspection.title.isEmpty ? fallbackTitle : inspection.title,
        author: inspection.author,
        summary: inspection.summary,
        sourceURL: inspection.sourceURL
    )
    applyUserImportMetadata(inspection, to: work, fillOnly: false)
    work.ao3WorkID = WorkTags.ao3WorkID(from: work.sourceURL)
    work.ao3SeriesID = ReadingQueueService.ao3SeriesID(from: work.seriesURL)
    work.markModified()

    try copyImportedEPUB(from: url, to: work.fileURL)

    context.insert(work)
    WorkSearchIndex.reindex(work)
    try? context.save()
    Log.library.info("Imported user EPUB “\(work.title)”")

    Task { await WorkTags.refreshFromAO3(for: work, in: context) }
    return .imported(work)
}

/// Maps an EPUB `dc:language` code (e.g. "en") to a human-readable name, reusing
/// the search filter's language table. Falls back to the raw value so unusual
/// codes still display something; AO3's refresh later replaces it with the
/// canonical name from the work page.
private func displayLanguage(_ code: String?) -> String {
    guard let code, !code.isEmpty else { return "" }
    let normalized = code.replacingOccurrences(of: "-", with: "").lowercased()
    if let match = AO3SearchFilters.Language.allCases.first(where: {
        $0.rawValue.lowercased() == normalized
    }) {
        return match.title
    }
    return code
}

private func applyUserImportMetadata(
    _ inspection: UserEPUBInspection,
    to work: SavedWork,
    fillOnly: Bool
) {
    var meta = inspection.metadata
    meta.sourceURL = inspection.sourceURL
    meta.rating = inspection.rating
    meta.publishedDate = inspection.publishedDate
    meta.updatedDate = inspection.updatedDate
    applyEPUBMetadata(
        meta,
        extracted: inspection.extracted,
        localChapterCount: inspection.localChapterCount,
        to: work,
        fillOnly: fillOnly
    )
    if work.ao3WorkID == nil {
        work.ao3WorkID = WorkTags.ao3WorkID(from: work.sourceURL)
    }
    if work.ao3SeriesID == nil {
        work.ao3SeriesID = ReadingQueueService.ao3SeriesID(from: work.seriesURL)
    }
}

private func applyEPUBMetadata(
    _ meta: EPUBMetadata,
    extracted: ExtractedAO3EPUBMetadata,
    localChapterCount: Int?,
    to work: SavedWork,
    fillOnly: Bool
) {
    assign(meta.title, to: \.title, on: work, fillOnly: fillOnly)
    assign(meta.author, to: \.author, on: work, fillOnly: fillOnly)
    assign(firstNonEmpty(meta.summary, extracted.summary), to: \.summary, on: work, fillOnly: fillOnly)
    assign(firstNonEmpty(meta.sourceURL, extracted.sourceURL), to: \.sourceURL, on: work, fillOnly: fillOnly)
    assign(firstNonEmpty(meta.rating, extracted.rating), to: \.rating, on: work, fillOnly: fillOnly)
    assign(displayLanguage(meta.language), to: \.language, on: work, fillOnly: fillOnly)
    assign(extracted.groups.language, to: \.language, on: work, fillOnly: true)
    assign(
        firstNonEmpty(meta.publishedDate, extracted.publishedDate),
        to: \.datePublished,
        on: work,
        fillOnly: fillOnly
    )
    assign(firstNonEmpty(meta.updatedDate, extracted.updatedDate), to: \.dateUpdated, on: work, fillOnly: fillOnly)
    assign(meta.seriesTitle, to: \.seriesTitle, on: work, fillOnly: fillOnly)
    if let position = meta.seriesIndex, !fillOnly || work.seriesPosition == 0 {
        work.seriesPosition = position
    }
    if let complete = extracted.isComplete, !fillOnly || !work.isComplete {
        work.isComplete = complete
    }
    if let words = extracted.groups.words, words > 0, !fillOnly || work.wordCount == 0 {
        work.wordCount = words
    }
    if !extracted.groups.chapters.isEmpty {
        assign(extracted.groups.chapters, to: \.chapters, on: work, fillOnly: fillOnly)
    } else if let localChapterCount, localChapterCount > 0, work.chapters.isEmpty {
        work.chapters = "\(localChapterCount)/\(localChapterCount)"
    }
    if let kudos = extracted.groups.kudos, kudos > 0, !fillOnly || work.kudos == 0 {
        work.kudos = kudos
    }
    if let comments = extracted.groups.comments, comments > 0, !fillOnly || work.comments == 0 {
        work.comments = comments
    }
    if let hits = extracted.groups.hits, hits > 0, !fillOnly || work.hits == 0 {
        work.hits = hits
    }

    let flatSubjects = SavedWork.normalizedWorkTags(meta.subjects, excludingRating: work.rating)
    applyTagMetadata(
        groups: extracted.groups,
        flatSubjects: flatSubjects,
        to: work,
        fillOnly: fillOnly
    )
}

private func applyTagMetadata(
    groups: AO3WorkTagGroups,
    flatSubjects: [String],
    to work: SavedWork,
    fillOnly: Bool
) {
    let warningSubjects = flatSubjects.filter(isArchiveWarning)
    let categorySubjects = flatSubjects.filter(isCategory)

    if !groups.fandoms.isEmpty {
        work.workFandoms = merged(fillOnly ? work.workFandoms : [], groups.fandoms)
    }
    if !groups.relationships.isEmpty {
        work.workRelationships = merged(fillOnly ? work.workRelationships : [], groups.relationships)
    }
    if !groups.characters.isEmpty {
        work.workCharacters = merged(fillOnly ? work.workCharacters : [], groups.characters)
    }
    if !groups.freeforms.isEmpty {
        work.workFreeforms = merged(fillOnly ? work.workFreeforms : [], groups.freeforms)
    }
    if !groups.warnings.isEmpty || !warningSubjects.isEmpty {
        work.workWarnings = merged(fillOnly ? work.workWarnings : [], groups.warnings + warningSubjects)
    }
    if !groups.categories.isEmpty || !categorySubjects.isEmpty {
        work.workCategories = merged(fillOnly ? work.workCategories : [], groups.categories + categorySubjects)
    }

    let categorized = work.workFandoms + work.workRelationships + work.workCharacters + work.workFreeforms
    let known = Set((categorized + work.workWarnings + work.workCategories + [work.rating]).map(normalizedKey))
    let uncategorized = flatSubjects.filter { !known.contains(normalizedKey($0)) }
    if !groups.isEmpty {
        work.workFreeforms = merged(work.workFreeforms, uncategorized)
        work.workTagsFetched = true
    }

    let fallbackFlat = groups.isEmpty ? flatSubjects : categorized + uncategorized
    work.workTags = merged(fillOnly ? work.workTags : [], fallbackFlat)
}

private func assign(
    _ rawValue: String,
    to keyPath: ReferenceWritableKeyPath<SavedWork, String>,
    on work: SavedWork,
    fillOnly: Bool
) {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return }
    if !fillOnly || work[keyPath: keyPath].isEmpty {
        work[keyPath: keyPath] = value
    }
}

private nonisolated func firstNonEmpty(_ first: String, _ second: String) -> String {
    first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? second : first
}

private nonisolated func merged(_ existing: [String], _ incoming: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for value in existing + incoming {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, seen.insert(normalizedKey(trimmed)).inserted else { continue }
        result.append(trimmed)
    }
    return result
}

private nonisolated func normalizedKey(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private nonisolated func isArchiveWarning(_ tag: String) -> Bool {
    archiveWarningKeys.contains(normalizedKey(tag))
}

private nonisolated func isCategory(_ tag: String) -> Bool {
    categoryKeys.contains(normalizedKey(tag))
}

private nonisolated let archiveWarningKeys: Set<String> = [
    "creator chose not to use archive warnings",
    "graphic depictions of violence",
    "major character death",
    "no archive warnings apply",
    "rape/non-con",
    "underage"
]

private nonisolated let categoryKeys: Set<String> = [
    "f/f", "f/m", "gen", "m/m", "multi", "other"
]

@MainActor
private func existingWork(
    matching inspection: UserEPUBInspection,
    sourceFile: URL,
    in context: ModelContext
) -> SavedWork? {
    let works = (try? context.fetch(FetchDescriptor<SavedWork>())) ?? []
    if let importedID = WorkTags.ao3WorkID(from: inspection.sourceURL),
       let byID = works.first(where: {
           $0.ao3WorkID == importedID || WorkTags.ao3WorkID(from: $0.sourceURL) == importedID
       }) {
        return byID
    }

    let titleKey = normalizedKey(inspection.title)
    let authorKey = normalizedKey(inspection.author)
    guard !titleKey.isEmpty else { return nil }
    let sourceSize = fileSize(of: sourceFile)
    return works.first { work in
        normalizedKey(work.title) == titleKey
            && normalizedKey(work.author) == authorKey
            && sourceSize != nil
            && fileSize(of: work.fileURL) == sourceSize
    }
}

private func fileSize(of url: URL) -> UInt64? {
    guard let value = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] else {
        return nil
    }
    if let number = value as? NSNumber { return number.uint64Value }
    return value as? UInt64
}

private func copyImportedEPUB(from source: URL, to destination: URL) throws {
    _ = try EPUBDocument.inspectPackage(ofEPUBAt: source)
    try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    do {
        if FileManager.default.fileExists(atPath: destination.path) {
            let staged = destination.deletingLastPathComponent()
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("epub")
            try FileManager.default.copyItem(at: source, to: staged)
            do {
                _ = try FileManager.default.replaceItemAt(
                    destination,
                    withItemAt: staged,
                    backupItemName: nil,
                    options: .usingNewMetadataOnly
                )
            } catch {
                try? FileManager.default.removeItem(at: staged)
                throw error
            }
        } else {
            try FileManager.default.copyItem(at: source, to: destination)
        }
    } catch {
        Log.library.error("Couldn't copy imported EPUB: \(error.localizedDescription, privacy: .public)")
        throw error
    }
}

private nonisolated struct ExtractedAO3EPUBMetadata {
    var title = ""
    var author = ""
    var summary = ""
    var sourceURL = ""
    var rating = ""
    var publishedDate = ""
    var updatedDate = ""
    var isComplete: Bool?
    var groups = AO3WorkTagGroups()

    static let empty = Self()
}

private nonisolated enum AO3EPUBMetadataScanner {
    private enum LabelField {
        case fandoms
        case relationships
        case characters
        case freeforms
        case warnings
        case categories
        case rating
        case language
        case words
        case chapters
        case published
        case updated
        case status
    }

    private static let exactLabelFields: [String: LabelField] = [
        "warnings": .warnings,
        "category": .categories,
        "categories": .categories,
        "rating": .rating,
        "language": .language,
        "words": .words,
        "chapters": .chapters,
        "status": .status
    ]

    private static let containingLabelFields: [(String, LabelField)] = [
        ("fandom", .fandoms),
        ("relationship", .relationships),
        ("character", .characters),
        ("additional", .freeforms),
        ("freeform", .freeforms),
        ("archive warning", .warnings),
        ("published", .published),
        ("updated", .updated)
    ]

    static func scan(_ url: URL) -> ExtractedAO3EPUBMetadata {
        guard let data = try? Data(contentsOf: url),
              let zip = try? MiniZip(data: data)
        else { return .empty }

        var result = ExtractedAO3EPUBMetadata()
        for name in zip.names where isMetadataCandidate(name) {
            guard let entry = zip.data(named: name),
                  let text = String(data: entry, encoding: .utf8)
                  ?? String(data: entry, encoding: .isoLatin1)
            else { continue }
            merge(scanText(text), into: &result)
        }
        return result.deduplicated()
    }

    private static func isMetadataCandidate(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["opf", "xhtml", "html", "htm", "xml"].contains(ext)
    }

    private static func scanText(_ text: String) -> ExtractedAO3EPUBMetadata {
        var result = ExtractedAO3EPUBMetadata()
        result.sourceURL = EPUBMetadata.canonicalAO3WorkURL(in: text) ?? ""

        guard let doc = try? SwiftSoup.parse(text) else { return result }
        result.title = firstText(doc, selectors: [
            "h2.title", "h1.title", "h1", "h2"
        ])
        result.author = firstText(doc, selectors: [
            "h3.byline a[rel=author]", "h3.byline a", ".byline a[rel=author]", ".byline"
        ])
        result.summary = firstText(doc, selectors: [
            ".summary blockquote", "blockquote.userstuff", "div.summary", "section.summary"
        ])

        if let pageGroups = try? AO3Client.parseWorkTags(from: text) {
            result.groups = pageGroups
        }
        applyLabelledMetadata(from: doc, to: &result)
        return result
    }

    private static func applyLabelledMetadata(
        from doc: Document,
        to result: inout ExtractedAO3EPUBMetadata
    ) {
        guard let labels = try? doc.select("dt").array() else { return }
        for label in labels {
            let labelText = ((try? label.text()) ?? "")
                .trimmingCharacters(in: CharacterSet(charactersIn: " :\n\t"))
                .lowercased()
            guard let valueElement = try? label.nextElementSibling() else { continue }
            let values = tagValues(in: valueElement)
            let plain = ((try? valueElement.text()) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let field = field(for: labelText) else { continue }
            apply(field, values: values, plain: plain, to: &result)
        }
    }

    private static func field(for label: String) -> LabelField? {
        exactLabelFields[label]
            ?? containingLabelFields.first { label.contains($0.0) }?.1
    }

    private static func apply(
        _ field: LabelField,
        values: [String],
        plain: String,
        to result: inout ExtractedAO3EPUBMetadata
    ) {
        guard !applyTagField(field, values: values, to: &result) else { return }
        applyScalarField(field, values: values, plain: plain, to: &result)
    }

    private static func applyTagField(
        _ field: LabelField,
        values: [String],
        to result: inout ExtractedAO3EPUBMetadata
    ) -> Bool {
        switch field {
        case .fandoms:
            result.groups.fandoms = merged(result.groups.fandoms, values)
        case .relationships:
            result.groups.relationships = merged(result.groups.relationships, values)
        case .characters:
            result.groups.characters = merged(result.groups.characters, values)
        case .freeforms:
            result.groups.freeforms = merged(result.groups.freeforms, values)
        case .warnings:
            result.groups.warnings = merged(result.groups.warnings, values)
        case .categories:
            result.groups.categories = merged(result.groups.categories, values)
        default:
            return false
        }
        return true
    }

    private static func applyScalarField(
        _ field: LabelField,
        values: [String],
        plain: String,
        to result: inout ExtractedAO3EPUBMetadata
    ) {
        switch field {
        case .rating:
            if result.rating.isEmpty { result.rating = values.first ?? plain }
        case .language:
            if result.groups.language.isEmpty { result.groups.language = plain }
        case .words:
            if result.groups.words == nil { result.groups.words = Int(plain.filter(\.isNumber)) }
        case .chapters:
            if result.groups.chapters.isEmpty { result.groups.chapters = plain }
        case .published:
            if result.publishedDate.isEmpty { result.publishedDate = plain }
        case .updated:
            if result.updatedDate.isEmpty { result.updatedDate = plain }
        case .status:
            if result.isComplete == nil {
                result.isComplete = plain.localizedCaseInsensitiveContains("complete")
                    && !plain.localizedCaseInsensitiveContains("incomplete")
            }
        default:
            break
        }
    }

    private static func tagValues(in element: Element) -> [String] {
        if let links = try? element.select("a.tag, a").array(), !links.isEmpty {
            return links.compactMap { link in
                let text = ((try? link.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            }
        }
        let text = ((try? element.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func firstText(_ doc: Document, selectors: [String]) -> String {
        for selector in selectors {
            if let value = try? doc.select(selector).first()?.text()
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty {
                return value
            }
        }
        return ""
    }

    private static func merge(
        _ incoming: ExtractedAO3EPUBMetadata,
        into result: inout ExtractedAO3EPUBMetadata
    ) {
        if result.title.isEmpty { result.title = incoming.title }
        if result.author.isEmpty { result.author = incoming.author }
        if result.summary.isEmpty { result.summary = incoming.summary }
        if result.sourceURL.isEmpty { result.sourceURL = incoming.sourceURL }
        if result.rating.isEmpty { result.rating = incoming.rating }
        if result.publishedDate.isEmpty { result.publishedDate = incoming.publishedDate }
        if result.updatedDate.isEmpty { result.updatedDate = incoming.updatedDate }
        if result.isComplete == nil { result.isComplete = incoming.isComplete }
        result.groups = merge(result.groups, incoming.groups)
    }

    private static func merge(_ existing: AO3WorkTagGroups, _ incoming: AO3WorkTagGroups) -> AO3WorkTagGroups {
        var groups = existing
        groups.fandoms = merged(groups.fandoms, incoming.fandoms)
        groups.relationships = merged(groups.relationships, incoming.relationships)
        groups.characters = merged(groups.characters, incoming.characters)
        groups.freeforms = merged(groups.freeforms, incoming.freeforms)
        groups.warnings = merged(groups.warnings, incoming.warnings)
        groups.categories = merged(groups.categories, incoming.categories)
        if groups.language.isEmpty { groups.language = incoming.language }
        if groups.words == nil { groups.words = incoming.words }
        if groups.chapters.isEmpty { groups.chapters = incoming.chapters }
        if groups.kudos == nil { groups.kudos = incoming.kudos }
        if groups.comments == nil { groups.comments = incoming.comments }
        if groups.hits == nil { groups.hits = incoming.hits }
        return groups
    }
}

private extension ExtractedAO3EPUBMetadata {
    nonisolated func deduplicated() -> Self {
        var copy = self
        let categorized = groups.fandoms + groups.relationships + groups.characters
            + groups.warnings + groups.categories + [rating]
        let categorizedKeys = Set(categorized.map(normalizedKey))
        copy.groups.freeforms = merged([], groups.freeforms.filter {
            !categorizedKeys.contains(normalizedKey($0))
        })
        copy.groups.fandoms = merged([], groups.fandoms)
        copy.groups.relationships = merged([], groups.relationships)
        copy.groups.characters = merged([], groups.characters)
        copy.groups.warnings = merged([], groups.warnings)
        copy.groups.categories = merged([], groups.categories)
        return copy
    }
}

/// Returns an already-saved work that came from the given AO3 source URL, if one
/// exists — so we can open it instead of downloading a duplicate.
@MainActor
func existingWork(forSource source: URL, in context: ModelContext) -> SavedWork? {
    let target = source.absoluteString
    let sourceID = WorkTags.ao3WorkID(from: target)
    let canonicalTarget = WorkTags.canonicalAO3WorkURL(from: target)
    let works = (try? context.fetch(FetchDescriptor<SavedWork>())) ?? []
    return works.first {
        $0.sourceURL == target
            || (canonicalTarget != nil
                && WorkTags.canonicalAO3WorkURL(from: $0.sourceURL) == canonicalTarget)
            || (sourceID != nil && ($0.ao3WorkID == sourceID
                    || WorkTags.ao3WorkID(from: $0.sourceURL) == sourceID))
    }
}
