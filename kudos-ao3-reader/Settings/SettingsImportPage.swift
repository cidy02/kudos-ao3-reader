import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Library & Sync › Import: EPUB and document import into the local
/// Library, moved as-is from the old single Settings page.
struct SettingsImportPage: View {
    @Environment(\.modelContext) private var context

    @State private var isChoosingFiles = false
    @State private var isImportingEPUB = false
    @State private var epubImportProgress: String?
    @State private var epubNotice: SettingsNotice?

    var body: some View {
        SettingsPageForm(route: .importFiles) {
            EPUBImportSettingsSection(
                isImporting: isImportingEPUB,
                progressText: epubImportProgress,
                onImport: { isChoosingFiles = true }
            )
        }
        .fileImporter(
            isPresented: $isChoosingFiles,
            allowedContentTypes: Self.workImportContentTypes,
            allowsMultipleSelection: true
        ) { result in
            importEPUBSelection(result)
        }
        .settingsNoticeAlert($epubNotice)
    }

    private func importEPUBSelection(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }
            Task { await importEPUBs(urls) }
        } catch {
            guard !error.isUserCancellation else {
                return
            }
            epubNotice = SettingsNotice(
                title: "Couldn't Import EPUB",
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    private func importEPUBs(_ urls: [URL]) async {
        isImportingEPUB = true
        epubImportProgress = nil
        defer {
            isImportingEPUB = false
            epubImportProgress = nil
        }

        // Security scope is held for the whole pass (download wait + import), not
        // just the read — a not-yet-downloaded iCloud Drive file needs access while
        // it materializes, not only once it's finally readable.
        let accessedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }

        // Kick off iCloud materialization for every file up front, so files later
        // in the list are already downloading by the time their turn comes instead
        // of each one only starting once the previous file's full import finishes.
        for url in urls {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }

        var summary = EPUBImportNoticeSummary()
        for (index, url) in urls.enumerated() {
            do {
                epubImportProgress = "Waiting for iCloud Drive… (\(index + 1) of \(urls.count))"
                try await waitForUbiquitousDownload(of: url)
                epubImportProgress = "Importing \(index + 1) of \(urls.count)…"
                // Accepts any supported format, converting non-EPUBs on the way in.
                let result = try await UserDocumentImport.perform(url, into: context)
                summary.record(result.outcome, convertedFrom: result.convertedFrom)
            } catch {
                summary.recordFailure(fileName: url.lastPathComponent, message: error.localizedDescription)
            }
        }

        epubNotice = SettingsNotice(title: summary.title, message: summary.message)
    }

    private static let epubContentType: UTType = {
        UTType(filenameExtension: "epub")
            ?? UTType(importedAs: "org.idpf.epub-container", conformingTo: .data)
    }()

    /// Everything the work importer can read. Wider than the formats T-152
    /// converts on purpose: a community copy arrives as whatever someone had, and
    /// a picker that greys the file out is a dead end, whereas letting it through
    /// produces a message naming the format and what to do about it.
    ///
    /// `.zip` matters more than it looks — forums and chat apps reject `.epub`
    /// attachments, so zipping the file is the normal way fanfic gets passed
    /// around, and `.data` catches the extensionless files Discord leaves behind.
    private static let workImportContentTypes: [UTType] = [
        epubContentType,
        .html,
        .plainText,
        .text,
        .zip,
        .pdf,
        .rtf,
        UTType(filenameExtension: "xhtml") ?? .html,
        UTType(filenameExtension: "md") ?? .plainText,
        UTType(filenameExtension: "docx") ?? .data,
        UTType(filenameExtension: "mobi") ?? .data,
        UTType(filenameExtension: "azw3") ?? .data,
        .data
    ]
}

struct EPUBImportSettingsSection: View {
    let isImporting: Bool
    let progressText: String?
    let onImport: () -> Void

    var body: some View {
        Section {
            Button(action: onImport) {
                Label("Import Files", systemImage: "doc.badge.plus")
            }
            .disabled(isImporting)
            .accessibilityLabel("Import files")

            if isImporting {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(progressText ?? "Importing…")
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("Import downloaded works, web pages, text files, or zipped chapters into your "
                + "Library. Kudos prepares supported files for reading, keeps the original, "
                + "and stores both so you can read offline.")
        }
    }
}

private struct EPUBImportNoticeSummary {
    var imported = 0
    var restored = 0
    var duplicates = 0
    /// How many files were converted to EPUB on the way in, by source format, so
    /// the notice can say what happened rather than silently changing the file.
    var converted: [ImportedFileFormat: Int] = [:]
    var failures: [(fileName: String, message: String)] = []

    var title: String {
        failures.isEmpty ? "Import Complete" : "Import Finished"
    }

    var message: String {
        var parts: [String] = []
        if imported > 0 { parts.append("Imported \(imported.formatted()).") }
        if !converted.isEmpty { parts.append(conversionSentence) }
        if restored > 0 {
            parts.append("Restored \(restored.formatted()) existing Library file\(restored == 1 ? "" : "s").")
        }
        if duplicates > 0 {
            parts.append("Skipped \(duplicates.formatted()) duplicate\(duplicates == 1 ? "" : "s").")
        }
        if failures.isEmpty {
            return parts.isEmpty ? "No files were selected." : parts.joined(separator: " ")
        }
        let failureText = failures.prefix(3)
            .map { "\($0.fileName): \($0.message)" }
            .joined(separator: "\n")
        let extra = failures.count > 3 ? "\n…and \(failures.count - 3) more." : ""
        return (parts.isEmpty ? "Nothing was imported." : parts.joined(separator: " "))
            + "\n\n" + failureText + extra
    }

    /// "Converted 2 from HTML, 1 from plain text." Formats are sorted by name so
    /// the sentence is stable rather than dictionary-ordered.
    private var conversionSentence: String {
        let clauses = converted
            .sorted { $0.key.displayName < $1.key.displayName }
            .map { "\($0.value.formatted()) from \($0.key.displayName)" }
        return "Converted \(clauses.joined(separator: ", ")) into readable downloads. The original file"
            + "\(converted.values.reduce(0, +) == 1 ? "" : "s") "
            + "\(converted.values.reduce(0, +) == 1 ? "was" : "were") kept."
    }

    mutating func record(_ outcome: UserEPUBImportOutcome, convertedFrom format: ImportedFileFormat? = nil) {
        switch outcome {
        case .imported:
            imported += 1
        case .restored:
            restored += 1
        case .duplicate:
            duplicates += 1
        }
        // A duplicate is not counted as a conversion: nothing new was stored, so
        // claiming "the original was kept" would be a lie.
        if let format, case .imported = outcome {
            converted[format, default: 0] += 1
        }
    }

    mutating func recordFailure(fileName: String, message: String) {
        failures.append((fileName, message))
    }
}

private extension Error {
    var isUserCancellation: Bool {
        let error = self as NSError
        return error.domain == NSCocoaErrorDomain
            && error.code == CocoaError.Code.userCancelled.rawValue
    }
}
