import Foundation
import OSLog
import SwiftData

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

    let work = SavedWork(
        title: title,
        author: meta?.author ?? "",
        summary: meta?.summary ?? "",
        sourceURL: source?.absoluteString ?? ""
    )
    work.isComplete = isComplete
    // Series + rating come from the EPUB metadata, so both native and web
    // imports get them; the AO3 series URL is only known for native imports.
    work.rating = meta?.rating ?? ""
    work.language = displayLanguage(meta?.language)
    work.workTags = SavedWork.normalizedWorkTags(meta?.subjects ?? [], excludingRating: work.rating)
    work.seriesTitle = meta?.seriesTitle ?? ""
    work.seriesPosition = meta?.seriesIndex ?? 0
    work.seriesURL = seriesURL
    // Baseline for update detection: the posted-chapter count at download time, so
    // chapters AO3 adds afterwards surface in Home → Recently Updated. Native imports
    // pass it from the AO3 work page; web imports baseline on the first update check.
    work.knownChapterCount = knownChapterCount

    let destination = work.fileURL
    try? FileManager.default.removeItem(at: destination)
    do {
        try FileManager.default.moveItem(at: tempURL, to: destination)
    } catch {
        Log.library.error("Couldn't save imported EPUB: \(error.localizedDescription, privacy: .public)")
        throw error
    }

    context.insert(work)
    try? context.save()
    Log.library.info("Imported work “\(title)”")

    // Refresh the work's tags from AO3's live page in the background; the EPUB
    // tags set above stand in until (and if) that succeeds.
    Task { await WorkTags.refreshFromAO3(for: work, in: context) }

    return work
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

/// Returns an already-saved work that came from the given AO3 source URL, if one
/// exists — so we can open it instead of downloading a duplicate.
@MainActor
func existingWork(forSource source: URL, in context: ModelContext) -> SavedWork? {
    let target = source.absoluteString
    let descriptor = FetchDescriptor<SavedWork>(
        predicate: #Predicate { $0.sourceURL == target }
    )
    return try? context.fetch(descriptor).first
}
