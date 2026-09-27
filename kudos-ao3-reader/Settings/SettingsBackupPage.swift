import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private final class SecurityScopedURL: Sendable {
    let url: URL
    let accessed: Bool

    init(_ url: URL) {
        self.url = url
        accessed = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if accessed {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

/// Confirm-time handle: scoped URL + manifest + identity. Full contents
/// are read only at execute so a hostile archive cannot sit decoded in
/// `@State` for the whole Merge/Replace extra step.
private struct PendingBackupImport: Identifiable {
    let id = UUID()
    let scopedURL: SecurityScopedURL
    let manifest: KudosBackupManifest
    let identity: KudosBackupContents.SourceIdentity
}

/// Settings › Library & Sync › Backup: export and import of `.kudosbackup`
/// archives, moved as-is from the old single Settings page.
struct SettingsBackupPage: View {
    @Environment(\.modelContext) private var context
    @Environment(ThemeManager.self) private var themeManager
    @Query(sort: \CustomFont.dateAdded) private var customFonts: [CustomFont]
    @Query(sort: \SavedWork.dateAdded) private var works: [SavedWork]
    @Query(sort: \Bookmark.dateAdded) private var bookmarks: [Bookmark]
    @Query(sort: \WorkCollection.dateAdded) private var collections: [WorkCollection]
    @Query(sort: \ReadingQueue.sortOrder) private var readingQueues: [ReadingQueue]
    @Query private var syncTombstones: [SyncTombstone]
    @Query(sort: \ReadingAnnotation.createdAt) private var readingAnnotations: [ReadingAnnotation]
    @Query(sort: \SavedSearch.dateAdded, order: .reverse) private var savedSearches: [SavedSearch]
    @Query(sort: \ReadingSession.startedAt) private var readingSessions: [ReadingSession]
    @Query(sort: \ReadingFavorite.createdAt) private var readingFavorites: [ReadingFavorite]
    @Query(sort: \FandomReadWatermark.lastVisitedAt)
    private var fandomReadWatermarks: [FandomReadWatermark]

    @State private var isChoosingBackup = false
    @State private var exportingBackup = false
    @State private var backupExportURL: URL?
    @State private var isPreparingBackupExport = false
    @State private var isImportingBackup = false
    /// Pre-confirm holds the scoped URL + manifest only. Full contents are
    /// read at execute inside `restorePendingBackup` (M4). The identity
    /// snapshot refuses a swapped file between confirm and restore (FIX-5).
    @State private var pendingImport: PendingBackupImport?
    @State private var backupNotice: SettingsNotice?
    /// Assets `writeArchive` had to skip, carried to the export confirmation.
    @State private var backupExportSkippedAssets = 0
    /// Read for the Replace sheet's "pause sync" offer.
    @State private var folderSyncStatus = FolderSyncService.snapshot()

    /// Whether Replace has anything to take away, which decides whether it is
    /// offered at all.
    ///
    /// Asking only "are there works?" was too narrow: saved links, saved
    /// searches, collections and the reader's own queues all outlive the last
    /// work and are all pruned by Replace. A library emptied of works but still
    /// holding those was shown Merge alone — and Merge cannot remove anything,
    /// so there was no way left to make the library match the file. The
    /// built-in Saved for Later queue is excluded: it always exists, so
    /// counting it would make this permanently true.
    private var hasAnythingReplaceWouldRemove: Bool {
        works.contains { !$0.isPendingDeletion }
            || !bookmarks.isEmpty
            || !savedSearches.isEmpty
            || !collections.isEmpty
            || readingQueues.contains { $0.kind != .savedForLater }
    }

    var body: some View {
        SettingsPageForm(route: .backup) {
            BackupSettingsSection(
                isPreparingExport: isPreparingBackupExport,
                isImporting: isImportingBackup,
                onExport: exportBackup,
                onImport: { isChoosingBackup = true }
            )
        }
        .onAppear { folderSyncStatus = FolderSyncService.snapshot() }
        // `.folder` keeps the pre-archive directory-form backups from older
        // versions selectable — `KudosBackupContents.read(from:)` handles both
        // formats, and a plain directory is exactly what such a backup resolves
        // to. It cannot be narrowed to a package type: nothing declares
        // `.kudosbackup` as a package, so the system types those directories as
        // `public.folder` (verified on a real legacy backup). The previous
        // `UTType(filenameExtension:conformingTo: .package)` matched neither
        // them nor anything else, so legacy import was silently broken too.
        .fileImporter(
            isPresented: $isChoosingBackup,
            allowedContentTypes: [.kudosBackup, .folder],
            allowsMultipleSelection: false
        ) { result in
            importBackup(result)
        }
        // Item-based exporter: the archive is already streamed to a temp file,
        // so saving is a file copy — the archive never lives in memory.
        .fileExporter(
            isPresented: $exportingBackup,
            item: backupExportURL.map(KudosBackupArchiveFile.init),
            contentTypes: [.kudosBackup],
            // Derived from the archive's own filename so the two can never
            // disagree — that URL is what this exporter actually presents.
            defaultFilename: backupExportURL?.deletingPathExtension().lastPathComponent
        ) { result in
            cleanUpBackupExportFile()
            switch result {
            case .success:
                backupNotice = SettingsNotice(
                    title: "Backup Exported",
                    message: Self.exportSuccessMessage(
                        recordCount: works.count,
                        missingAssets: backupExportSkippedAssets
                    )
                )
            case let .failure(error):
                backupNotice = SettingsNotice(
                    title: "Couldn't Export Backup",
                    message: error.localizedDescription
                )
            }
        } onCancellation: {
            cleanUpBackupExportFile()
        }
        // An `.alert`, not a `.confirmationDialog`, and only one: see
        // `settingsNoticeAlert`.
        .settingsNoticeAlert($backupNotice)
        // One sheet for the whole import decision. It replaces an alert on an
        // empty library, a confirmation dialog on a non-empty one, and the
        // separate sheet Replace used to open on top of that. Presenting is
        // simply `pendingImport` being non-nil, so nothing can get out of step
        // with it — which is what the old boolean-plus-optional pairing did.
        .sheet(item: $pendingImport) { pending in
            BackupImportSheet(
                manifest: pending.manifest,
                localWorks: works.filter { !$0.isPendingDeletion },
                hasReplaceableRecords: hasAnythingReplaceWouldRemove,
                syncIsConnected: folderSyncStatus.isConnected,
                onMerge: { restorePendingBackup(mode: .merge) },
                onReplace: { pauseSync in
                    if pauseSync {
                        FolderSyncService.setAutoSyncEnabled(false)
                        folderSyncStatus = FolderSyncService.snapshot()
                    }
                    restorePendingBackup(mode: .replaceLibrary)
                },
                onCancel: { pendingImport = nil },
                makePreReplaceBackup: makePreReplaceBackup
            )
        }
    }

    /// What the archive actually contains, including what it does not.
    ///
    /// A converted import keeps the exact file it came from
    /// (`UserDocumentImport.preserveOriginal`), described there as "insurance".
    /// Both exporters enumerate works and fonts only, so that insurance does
    /// not survive the one event it exists for: migrating to a new phone and
    /// erasing the old one. Saying so at export time is the difference between
    /// a reader who can copy the files off and one who finds out afterwards.
    private static func exportSuccessMessage(recordCount: Int, missingAssets: Int) -> String {
        var parts = ["\(recordCount.formatted()) Library records were included."]
        if missingAssets > 0 {
            let noun = missingAssets == 1 ? "file was" : "files were"
            parts.append("\(missingAssets.formatted()) \(noun) listed but could not be read, "
                + "so they are not in this backup. Those works restore without their EPUB.")
        }
        return parts.joined(separator: "\n\n")
    }

    // MARK: Backup export / import

    private func exportBackup() {
        guard !isPreparingBackupExport else { return }
        let plan: KudosBackupExportPlan
        do {
            plan = try KudosBackupService.makeExportPlan(
                works: works,
                bookmarks: bookmarks,
                fonts: customFonts,
                collections: collections,
                readingQueues: readingQueues,
                annotations: readingAnnotations,
                savedSearches: savedSearches,
                readingSessions: readingSessions,
                readingFavorites: readingFavorites,
                fandomReadWatermarks: fandomReadWatermarks,
                tombstones: syncTombstones
            )
        } catch {
            backupNotice = SettingsNotice(
                title: "Couldn't Create Backup",
                message: error.localizedDescription
            )
            return
        }

        // The archive streams to a temp file off the main actor — constant
        // memory and no UI stall, however large the library is. The exporter
        // sheet is presented only once the file is complete.
        //
        // The temp file is given the name the user should see in the save
        // sheet, because the item-based `fileExporter` takes the presented
        // filename from the exported file's URL — `defaultFilename:` below is
        // not consulted for it. The UUID therefore lives in a wrapping
        // *directory* rather than in the filename, so concurrent or same-day
        // exports still can't collide while the file itself stays readable.
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KudosBackupExport-\(UUID().uuidString)", isDirectory: true)
        let destination = exportDirectory
            .appendingPathComponent("Kudos Backup \(Self.backupDateFormatter.string(from: Date()))")
            .appendingPathExtension("kudosbackup")
        do {
            try FileManager.default.createDirectory(
                at: exportDirectory, withIntermediateDirectories: true
            )
        } catch {
            backupNotice = SettingsNotice(
                title: "Couldn't Create Backup",
                message: error.localizedDescription
            )
            return
        }
        isPreparingBackupExport = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try KudosBackupService.writeArchive(plan, to: destination) }
            }.value
            isPreparingBackupExport = false
            switch result {
            case let .success(skipped):
                backupExportSkippedAssets = skipped.count
                backupExportURL = destination
                exportingBackup = true
            case let .failure(error):
                backupNotice = SettingsNotice(
                    title: "Couldn't Create Backup",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func cleanUpBackupExportFile() {
        if let url = backupExportURL {
            // Removes the per-export wrapping directory, not just the archive
            // inside it (see `exportBackup()`), so nothing is left behind in tmp.
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        backupExportURL = nil
    }

    private func importBackup(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            // Keep the security scope alive across the confirm UI; the
            // execute Task captures the same helper so access is not dropped
            // when `@State` is niled at the start of restore.
            let scoped = SecurityScopedURL(url)
            let manifest = try KudosBackupContents.preConfirmManifest(from: scoped.url)
            let identity = try KudosBackupContents.sourceIdentity(
                of: scoped.url,
                manifest: manifest
            )
            pendingImport = PendingBackupImport(
                scopedURL: scoped,
                manifest: manifest,
                identity: identity
            )
            // Presenting is `pendingImport` being non-nil — one sheet, which
            // asks the question and owns Replace's gate as its second step.
        } catch {
            pendingImport = nil
            backupNotice = SettingsNotice(
                title: "Couldn't Read Backup",
                message: error.localizedDescription
            )
        }
    }

    /// Posts a backup alert from inside the confirmation alert's own button.
    ///
    /// Through a `Task` for exactly the reason the success path is — see below.
    /// A notice assigned synchronously from that button races the confirmation
    /// alert's dismissal, SwiftUI drops the second presentation, and the failure
    /// becomes as silent as the bug this whole path exists to report. Yielding
    /// once lets the confirmation finish dismissing first.
    private func postBackupNotice(_ title: String, _ message: String) {
        Task { @MainActor in
            backupNotice = SettingsNotice(title: title, message: message)
        }
    }

    /// Runs the merge and reports what changed.
    ///
    /// Deliberately hops through a `Task` before doing any work. The call site
    /// is the confirmation alert's own button, and setting `backupNotice`
    /// straight from there raced that alert's dismissal — SwiftUI dropped the
    /// second presentation, so the "Backup Imported" summary silently never
    /// appeared and an import looked like it had done nothing. Yielding once
    /// lets the confirmation finish dismissing, after which the result alert
    /// presents reliably. The hop also gives the progress indicator on the
    /// Import row a chance to render before the merge begins.
    private func restorePendingBackup(mode: BackupImportMode = .merge) {
        let pending = pendingImport
        pendingImport = nil
        guard let pending else {
            // Never silent. Returning empty-handed here is precisely how a
            // failed restore looked like a no-op: the reader tapped Restore,
            // nothing happened, and nothing said why.
            postBackupNotice(
                "Couldn't Import Backup",
                "Kudos lost track of the backup you chose before the restore "
                    + "began. Pick the file again."
            )
            return
        }
        guard PersistenceOperationGate.begin(.backupImport) else {
            postBackupNotice(
                "Import Already Busy",
                "Kudos is already running "
                    + "\(PersistenceOperationGate.active?.title ?? "another persistence operation")."
            )
            return
        }
        isImportingBackup = true
        Task { @MainActor in
            // Hold the security scope open for the duration of the read+restore.
            // Clearing `@State` above would otherwise drop the last reference
            // and stop access before `readForConfirmedImport` runs.
            let scopedURL = pending.scopedURL
            defer {
                _ = scopedURL
                PersistenceOperationGate.end(.backupImport)
                isImportingBackup = false
            }
            do {
                let backup = try KudosBackupContents.readForConfirmedImport(
                    from: scopedURL.url,
                    expectedIdentity: pending.identity,
                    manifest: pending.manifest
                )
                let summary = try KudosBackupService.restore(
                    backup, into: context, mode: mode
                )
                if mode != .replaceLibrary {
                    applyRestoredTheme(pending.manifest.settings)
                }
                let verb = mode == .replaceLibrary ? "Replaced" : "Merged"
                let title = mode == .replaceLibrary ? "Library Replaced" : "Backup Imported"
                let conflictMessage = summary.conflictMessage
                backupNotice = SettingsNotice(
                    title: title,
                    message: "\(verb) into your library:\n\(summary.changeMessage)"
                        + (conflictMessage.isEmpty ? "" : "\n\n\(conflictMessage)")
                )
            } catch {
                backupNotice = SettingsNotice(
                    title: "Couldn't Import Backup",
                    message: error.localizedDescription
                )
            }
        }
    }

    /// Writes a copy of the current library so Replace can be undone by importing
    /// that file. Returns a user-visible filename or the error to show.
    ///
    /// **This is the only undo a Replace has**, so it is written defensively:
    ///
    /// - The name carries a time, not just a date, and the write refuses to
    ///   overwrite. It used to be `yyyy-MM-dd` written with plain `.atomic`, so
    ///   *opening* the Replace sheet a second time on the same day — this runs
    ///   from `onAppear`, and cancelling still ran it — silently wrote the
    ///   ALREADY-REPLACED library over the original copy. The one file that
    ///   could undo the first replace was destroyed by considering a second.
    /// - It retries. A single failure is not proof that the disk cannot take a
    ///   copy, and the alternative to a copy is an unrecoverable replace.
    ///
    /// `PreReplaceBackupNaming` owns the naming so it can be tested without a
    /// SwiftUI view.
    private func makePreReplaceBackup() -> Result<String, Error> {
        var lastError: Error?
        for attempt in 0 ..< PreReplaceBackupNaming.attemptLimit {
            do {
                let contents = try KudosBackupService.makeContents(
                    works: works,
                    bookmarks: bookmarks,
                    fonts: customFonts,
                    collections: collections,
                    readingQueues: readingQueues,
                    annotations: readingAnnotations,
                    savedSearches: savedSearches,
                    readingSessions: readingSessions,
                    readingFavorites: readingFavorites,
                    fandomReadWatermarks: fandomReadWatermarks,
                    tombstones: syncTombstones
                )
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let url = PreReplaceBackupNaming.url(in: docs, at: Date(), attempt: attempt)
                // Staged, then moved into place.
                //
                // This used to be `write(options: [.atomic, .withoutOverwriting])`,
                // which looks like it gives both guarantees and in fact gives
                // neither: Foundation TRAPS on that combination — "withoutOverwriting
                // is not supported with atomic" — so the one path that exists to
                // protect the only undo a Replace has would have taken the app down
                // instead of writing a copy.
                //
                // An atomic write to a scratch name cannot leave a partial file, and
                // `moveItem` refuses an existing destination, so even two attempts
                // inside the same second cannot clobber each other.
                let staged = FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "\(UUID().uuidString).\(PreReplaceBackupNaming.fileExtension)"
                    )
                try contents.zipData().write(to: staged, options: .atomic)
                do {
                    try FileManager.default.moveItem(at: staged, to: url)
                } catch {
                    try? FileManager.default.removeItem(at: staged)
                    throw error
                }
                return .success(url.lastPathComponent)
            } catch {
                lastError = error
            }
        }
        return .failure(lastError ?? CocoaError(.fileWriteUnknown))
    }

    private func applyRestoredTheme(_ settings: KudosBackupSettings) {
        themeManager.matchAppAndReader = false
        themeManager.appTheme = ReaderTheme(rawValue: settings.appTheme) ?? .light
        themeManager.readerTheme = ReaderTheme(rawValue: settings.readerTheme) ?? .light
        themeManager.accentHex = settings.accentColorHex
        themeManager.matchAppAndReader = settings.matchAppReaderTheme
    }

    private static let backupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct BackupSettingsSection: View {
    var isPreparingExport = false
    var isImporting = false
    let onExport: () -> Void
    let onImport: () -> Void

    private var isBusy: Bool {
        isPreparingExport || isImporting
    }

    var body: some View {
        Section {
            Button(action: onExport) {
                HStack {
                    Label("Export Backup…", systemImage: "square.and.arrow.up")
                    if isPreparingExport {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isBusy)
            Button(action: onImport) {
                HStack {
                    Label("Import Backup…", systemImage: "square.and.arrow.down")
                    if isImporting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isBusy)
            // A full-width bar while either side is working. Indeterminate on
            // purpose: neither `writeArchive` nor `restore` reports per-record
            // progress today, and a bar that invented a percentage would be
            // lying about how far along the merge actually is.
            if isBusy {
                ProgressView()
                    .progressViewStyle(.linear)
                    .accessibilityLabel(isImporting ? "Importing backup" : "Preparing backup")
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("Backups include Library records, Reading Queues, preserved EPUBs, "
                + "User Tags, saved links, custom fonts, and app settings. Import "
                + "merges without deleting items already on this device. AO3 sessions "
                + "and passwords are never included.")
        }
    }
}
