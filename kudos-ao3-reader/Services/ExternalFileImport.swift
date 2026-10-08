import Foundation
import OSLog
import SwiftData
import SwiftUI

/// Handles files handed to Kudos from *outside* the app — "Open in Kudos" from
/// Files, Safari's download menu, a Reddit or Discord attachment, AirDrop.
///
/// This is the path that actually matches how community copies travel. Before
/// this existed, the only way in was a picker buried in Settings, which means the
/// user had to know the feature was there and go looking for it; the natural
/// gesture is to tap the file where they found it.
///
/// Registered document types live in the Info.plist injection build phase (arrays
/// of dictionaries, which `INFOPLIST_KEY_*` cannot express).
@MainActor
@Observable
final class ExternalFileImport {
    /// The result of the last external import, for the root view to surface.
    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        /// Set when a work was actually added, so the notice can offer to open it.
        let workID: UUID?
    }

    private(set) var isImporting = false
    var notice: Notice?
    private(set) var pendingImport: PendingDocumentImport?

    /// Inspects a file opened from outside the app, then lets the root view ask
    /// the reader to confirm or change the detected download date.
    ///
    /// Files arriving this way are usually already local (iOS copies them into
    /// `Documents/Inbox` for a document type the app claims), but an iCloud Drive
    /// URL can still be a placeholder, which `UserDocumentImport` waits out.
    func handle(_ url: URL) async {
        guard url.isFileURL else { return }
        guard !isImporting, pendingImport == nil else {
            Log.library.notice("Ignoring an opened file while another import is in flight")
            return
        }
        isImporting = true
        defer { isImporting = false }

        // A URL delivered by the system may be security-scoped (a file the user
        // picked in another app) or may not (a copy already in our own Inbox).
        // Starting access is harmless in the second case; stopping it must be
        // paired only when it actually started.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let detection = try await UserDocumentImport.detectDownloadDate(of: url)
            pendingImport = PendingDocumentImport(url: url, detection: detection)
        } catch {
            let fileName = url.lastPathComponent
            let reason = error.localizedDescription
            // A file's name is the reader's business, and the system's reason usually repeats it.
            Log.library.error("Opening \(fileName, privacy: .private) failed: \(reason, privacy: .private)")
            notice = Notice(
                title: "Couldn't Import This File",
                message: error.localizedDescription,
                workID: nil
            )
            removeInboxCopy(at: url)
        }
    }

    func confirm(_ selection: SelectedDocumentImport, in context: ModelContext) async {
        guard pendingImport?.url == selection.url, !isImporting else { return }
        pendingImport = nil
        isImporting = true
        defer {
            isImporting = false
            // iOS copies an opened document into Documents/Inbox and leaves it
            // there forever otherwise; the importer now owns its durable copy.
            removeInboxCopy(at: selection.url)
        }

        let scoped = selection.url.startAccessingSecurityScopedResource()
        defer { if scoped { selection.url.stopAccessingSecurityScopedResource() } }
        do {
            let result = try await UserDocumentImport.perform(
                selection.url, downloadedAt: selection.downloadedAt, into: context
            )
            notice = successNotice(for: result, fileName: selection.url.lastPathComponent)
        } catch {
            let fileName = selection.url.lastPathComponent
            let reason = error.localizedDescription
            // A file's name is the reader's business, and the system's reason usually repeats it.
            Log.library.error("Opening \(fileName, privacy: .private) failed: \(reason, privacy: .private)")
            notice = Notice(
                title: "Couldn't Import This File",
                message: error.localizedDescription,
                workID: nil
            )
        }
    }

    func cancelPendingImport() {
        if let url = pendingImport?.url { removeInboxCopy(at: url) }
        pendingImport = nil
    }

    private func successNotice(
        for result: (outcome: UserEPUBImportOutcome, convertedFrom: ImportedFileFormat?),
        fileName: String
    ) -> Notice {
        let work = result.outcome.work
        let converted = result.convertedFrom.map {
            " Converted from \($0.displayName); the original file was kept."
        } ?? ""

        switch result.outcome {
        case .imported:
            return Notice(
                title: "Added to Your Library",
                message: "“\(work.title)” was imported.\(converted)",
                workID: work.id
            )
        case .restored:
            return Notice(
                title: "Restored to Your Library",
                message: "“\(work.title)” was already in your Library and its file has been "
                    + "restored.\(converted)",
                workID: work.id
            )
        case .duplicate:
            return Notice(
                title: "Already in Your Library",
                message: "“\(work.title)” is already saved, so nothing was added.",
                workID: work.id
            )
        }
    }

    /// Deletes the system's inbox copy, but only if the URL really is inside our
    /// own container — never a file the user still owns somewhere else.
    private func removeInboxCopy(at url: URL) {
        let path = url.standardizedFileURL.path
        guard path.contains("/Documents/Inbox/") else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
