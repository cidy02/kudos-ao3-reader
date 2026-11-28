import Foundation
import SwiftData
import Testing
@testable import Kudos

/// End-to-end tests for importing a non-EPUB file: conversion, the `SavedWork`
/// that results, and the preserved original beside it.
///
/// These write into the app's real `Storage` directories (as `EPUBTests` already
/// does, since `SavedWork.fileURL` is derived from `Storage`) and clean up after
/// themselves.
@MainActor
struct UserDocumentImportTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, QueueSavedSearchLink.self, SyncTombstone.self, ReadingAnnotation.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }

    private func write(_ contents: String, _ ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func makeOriginalsDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-originals-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Removes everything an import leaves in the app's permanent storage.
    private func cleanUp(_ work: SavedWork) {
        try? FileManager.default.removeItem(at: work.fileURL)
        if let original = Storage.existingOriginalDocumentURL(for: work.id) {
            try? FileManager.default.removeItem(at: original)
        }
        WorkConversionRecord.delete(for: work.id)
    }

    private static let ao3HTML = """
    <!DOCTYPE html><html lang="en"><head><title>Rescued Fic [Archive of Our Own]</title></head><body>
      <h1 class="title">Rescued Fic</h1>
      <h3 class="byline"><a rel="author">LostAuthor</a></h3>
      <div class="summary"><blockquote>The only copy left.</blockquote></div>
      <div id="chapters">
        <div class="chapter"><h2 class="heading">Chapter 1</h2><p>Body one.</p></div>
        <div class="chapter"><h2 class="heading">Chapter 2</h2><p>Body two.</p></div>
      </div>
    </body></html>
    """

    @Test func htmlImportCreatesAReadableWorkAndReportsItsFormat() async throws {
        let context = try makeContext()
        let source = try write(Self.ao3HTML, "html")
        defer { try? FileManager.default.removeItem(at: source) }

        let result = try await UserDocumentImport.perform(source, into: context)
        let work = result.outcome.work
        defer { cleanUp(work) }

        #expect(result.convertedFrom == .html)
        #expect(work.title == "Rescued Fic")
        #expect(work.author == "LostAuthor")
        #expect(work.summary == "The only copy left.")
        #expect(work.hasEPUB)
        // The stored file is a real EPUB the reader can open, not the source HTML.
        #expect(FileManager.default.fileExists(atPath: work.fileURL.path))
        #expect(work.fileURL.pathExtension == "epub")
        let package = try EPUBDocument.inspectPackage(ofEPUBAt: work.fileURL)
        #expect(package.readableItemCount == 2)
    }

    @Test func anImportedWorkGetsAWordCount() async throws {
        // The owner's report: converted works showed no length on the card.
        let context = try makeContext()
        let source = try write("Chapter 1: Start\n\nOne two three four five six seven.", "txt")
        defer { try? FileManager.default.removeItem(at: source) }

        let work = try await UserDocumentImport.perform(source, into: context).outcome.work
        defer { cleanUp(work) }

        // Counts the prose, not the chapter heading, which becomes an <h1> rather than
        // body text.
        #expect(work.wordCount == 7, "expected the converted text's word count, got \(work.wordCount)")
    }

    @Test func theOriginalFileIsKeptBesideTheConvertedEPUB() async throws {
        // A community copy is often the last copy in existence and conversion is
        // lossy, so the exact bytes handed to us are archived.
        let context = try makeContext()
        let source = try write(Self.ao3HTML, "html")
        defer { try? FileManager.default.removeItem(at: source) }

        let result = try await UserDocumentImport.perform(source, into: context)
        let work = result.outcome.work
        defer { cleanUp(work) }

        let original = try #require(Storage.existingOriginalDocumentURL(for: work.id))
        #expect(original.pathExtension == "html")
        let archived = try Data(contentsOf: original)
        #expect(archived == Data(Self.ao3HTML.utf8))
    }

    @Test func failureToStageTheOriginalLeavesNoWorkOrStaging() async throws {
        let context = try makeContext()
        let source = try write(Self.ao3HTML, "html")
        let directory = try makeOriginalsDirectory()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: directory)
        }
        let blockedDirectory = directory.appendingPathComponent("Originals")
        try Data("blocking file".utf8).write(to: blockedDirectory)

        await #expect(throws: UserEPUBImportError.couldNotKeepOriginal) {
            _ = try await UserDocumentImport.perform(source, originalsDirectory: blockedDirectory, into: context)
        }
        #expect(try context.fetch(FetchDescriptor<SavedWork>()).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["Originals"])
        #expect(try Data(contentsOf: source) == Data(Self.ao3HTML.utf8))
    }

    @Test func theFinalOriginalAndRecordAreOnDiskBeforeTheWorkIsSaved() async throws {
        let context = try makeContext()
        let source = try write(Self.ao3HTML, "html")
        let directory = try makeOriginalsDirectory()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: directory)
        }
        let probe = OriginalFilesAtFirstSave()
        let observer = NotificationCenter.default.addObserver(
            forName: ModelContext.willSave, object: context, queue: nil
        ) { _ in
            MainActor.assumeIsolated { probe.capture(in: directory) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let work = try await UserDocumentImport.perform(source, originalsDirectory: directory, into: context)
            .outcome.work
        defer { cleanUp(work) }
        let original = Storage.originalDocumentURL(for: work.id, fileExtension: "html", in: directory)
        let sidecar = WorkConversionRecord.url(for: work.id, in: directory)
        let files = try #require(probe.files)
        #expect(files[original.lastPathComponent] == Data(Self.ao3HTML.utf8))
        let recordBytes = try #require(files[sidecar.lastPathComponent])
        let record = try JSONDecoder().decode(WorkConversionRecord.self, from: recordBytes)
        #expect(record.converterVersion == ImportedDocumentConverter.converterVersion)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
            == Set([original.lastPathComponent, sidecar.lastPathComponent]))
    }

    @MainActor
    private final class OriginalFilesAtFirstSave {
        private(set) var files: [String: Data]?

        func capture(in directory: URL) {
            guard files == nil else { return }
            files = [:]
            for url in (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            )) ?? [] {
                files?[url.lastPathComponent] = try? Data(contentsOf: url)
            }
        }
    }

    @Test func plainTextImportSplitsChaptersAndKeepsItsOriginal() async throws {
        let context = try makeContext()
        let text = """
        Chapter 1: Start

        Opening lines.

        Chapter 2: Finish

        Closing lines.
        """
        let source = try write(text, "txt")
        defer { try? FileManager.default.removeItem(at: source) }

        let result = try await UserDocumentImport.perform(source, into: context)
        let work = result.outcome.work
        defer { cleanUp(work) }

        #expect(result.convertedFrom == .plainText)
        #expect(try EPUBDocument.inspectPackage(ofEPUBAt: work.fileURL).readableItemCount == 2)
        #expect(Storage.existingOriginalDocumentURL(for: work.id)?.pathExtension == "txt")
    }

    @Test func aRealEPUBImportsUnconvertedAndKeepsNoSeparateOriginal() async throws {
        // Nothing was converted, so there is nothing to preserve — the stored EPUB
        // *is* the original, and a second copy would just waste disk.
        let context = try makeContext()
        let epub = try EPUBBuilder.archive(
            metadata: .init(title: "Already An EPUB"),
            chapters: [.init(title: "One", bodyXHTML: "<p>Text.</p>")]
        )
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("plain-\(UUID().uuidString).epub")
        try epub.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let result = try await UserDocumentImport.perform(source, into: context)
        let work = result.outcome.work
        defer { cleanUp(work) }

        #expect(result.convertedFrom == nil)
        #expect(work.title == "Already An EPUB")
        #expect(Storage.existingOriginalDocumentURL(for: work.id) == nil)
    }

    @Test func aConvertedAO3DownloadKeepsItsAO3Identity() async throws {
        // The point of recovering dc:source: the work can still be matched to AO3
        // and have its tags refreshed, even though it arrived as a loose HTML file.
        let context = try makeContext()
        let html = Self.ao3HTML.replacingOccurrences(
            of: "<div id=\"chapters\">",
            with: "<p>Source: https://archiveofourown.org/works/999111</p><div id=\"chapters\">"
        )
        let source = try write(html, "html")
        defer { try? FileManager.default.removeItem(at: source) }

        let result = try await UserDocumentImport.perform(source, verifyAvailability: false, into: context)
        let work = result.outcome.work
        defer { cleanUp(work) }

        #expect(work.sourceURL == "https://archiveofourown.org/works/999111")
        #expect(work.ao3WorkID == 999_111)
    }

    @Test func aConvertedWorkWithNoAO3IdentityStaysProtected() async throws {
        // `isProtected` is true when ao3WorkID == nil, which is what stops the
        // history sweep from freeing a file that can never be re-downloaded.
        let context = try makeContext()
        let source = try write("Just a rescued story with no archive link.", "txt")
        defer { try? FileManager.default.removeItem(at: source) }

        let result = try await UserDocumentImport.perform(source, into: context)
        let work = result.outcome.work
        defer { cleanUp(work) }

        #expect(work.ao3WorkID == nil)
        #expect(work.isProtected)
    }

    @Test func permanentDeletionRemovesThePreservedOriginal() async throws {
        // Otherwise the archived copy outlives the work as an orphan that nothing
        // in the app can reach or clean up.
        let context = try makeContext()
        let source = try write(Self.ao3HTML, "html")
        defer { try? FileManager.default.removeItem(at: source) }

        let result = try await UserDocumentImport.perform(source, into: context)
        let work = result.outcome.work
        let workID = work.id
        #expect(Storage.existingOriginalDocumentURL(for: workID) != nil)

        WorkLifecycle.hardDelete(work, in: context)
        #expect(Storage.existingOriginalDocumentURL(for: workID) == nil)
    }

    @Test func anUnsupportedFormatFailsWithoutCreatingAWork() async throws {
        let context = try makeContext()
        // RTF rather than PDF: PDF converts since T-157, so it no longer exercises
        // the "format we cannot read yet" path.
        let source = try write("{\\rtf1\\ansi Not handled yet}", "rtf")
        defer { try? FileManager.default.removeItem(at: source) }

        await #expect(throws: ImportedDocumentConverter.ConversionError.notYetSupported(.rtf)) {
            _ = try await UserDocumentImport.perform(source, into: context)
        }
        let works = try context.fetch(FetchDescriptor<SavedWork>())
        #expect(works.isEmpty)
    }

    @Test func reimportingTheSameConvertedFileIsTreatedAsADuplicate() async throws {
        let context = try makeContext()
        let source = try write(Self.ao3HTML, "html")
        defer { try? FileManager.default.removeItem(at: source) }

        let first = try await UserDocumentImport.perform(source, into: context)
        defer { cleanUp(first.outcome.work) }
        let second = try await UserDocumentImport.perform(source, into: context)

        // Conversion is byte-reproducible, so the second pass matches the first on
        // the title/author/size heuristic rather than creating a second copy.
        guard case let .duplicate(duplicate) = second.outcome else {
            Issue.record("expected a duplicate, got \(second.outcome)")
            return
        }
        #expect(duplicate.id == first.outcome.work.id)
        #expect(try context.fetch(FetchDescriptor<SavedWork>()).count == 1)
    }

    @Test func aDuplicateReplacesTheOriginalEvenWhenItsExtensionChanges() async throws {
        let context = try makeContext()
        let revised = Self.ao3HTML.replacingOccurrences(of: "Body one.", with: "Body new.")
        let originalSource = try write(Self.ao3HTML, "html")
        let revisedSource = try write(revised, "htm")
        let directory = try makeOriginalsDirectory()
        defer {
            try? FileManager.default.removeItem(at: originalSource)
            try? FileManager.default.removeItem(at: revisedSource)
            try? FileManager.default.removeItem(at: directory)
        }

        let first = try await UserDocumentImport.perform(originalSource, originalsDirectory: directory, into: context)
        let work = first.outcome.work
        defer { cleanUp(work) }
        let readingCopy = try Data(contentsOf: work.fileURL)
        let second = try await UserDocumentImport.perform(revisedSource, originalsDirectory: directory, into: context)
        guard case let .duplicate(duplicate) = second.outcome else {
            Issue.record("Expected a duplicate, got \(second.outcome)")
            cleanUp(second.outcome.work)
            return
        }

        #expect(duplicate.id == work.id)
        let original = try #require(Storage.existingOriginalDocumentURL(for: work.id, in: directory))
        #expect(original.pathExtension == "htm")
        #expect(try Data(contentsOf: original) == Data(revised.utf8))
        let previous = Storage.originalDocumentURL(for: work.id, fileExtension: "html", in: directory)
        #expect(!FileManager.default.fileExists(atPath: previous.path))
        #expect(try Data(contentsOf: work.fileURL) == readingCopy)
        let sidecar = WorkConversionRecord.url(for: work.id, in: directory)
        let record = try JSONDecoder().decode(WorkConversionRecord.self, from: Data(contentsOf: sidecar))
        #expect(record.originalFileName == revisedSource.lastPathComponent)
        #expect(record.converterVersion == 0)
    }

    @Test func failureToInstallTheRecordRestoresThePreviousOriginal() async throws {
        let context = try makeContext()
        let source = try write(Self.ao3HTML, "html")
        let directory = try makeOriginalsDirectory()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: directory)
        }
        let work = try await UserDocumentImport.perform(source, originalsDirectory: directory, into: context)
            .outcome.work
        defer { cleanUp(work) }
        let original = try #require(Storage.existingOriginalDocumentURL(for: work.id, in: directory))
        let sidecar = WorkConversionRecord.url(for: work.id, in: directory)
        try FileManager.default.removeItem(at: sidecar)
        try FileManager.default.createDirectory(at: sidecar, withIntermediateDirectories: false)
        let revised = Self.ao3HTML.replacingOccurrences(of: "Body one.", with: "Body new.")
        try Data(revised.utf8).write(to: source)

        await #expect(throws: UserEPUBImportError.couldNotKeepOriginal) {
            _ = try await UserDocumentImport.perform(source, originalsDirectory: directory, into: context)
        }
        #expect(try Data(contentsOf: original) == Data(Self.ao3HTML.utf8))
        #expect(try context.fetch(FetchDescriptor<SavedWork>()).count == 1)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
            == Set([original.lastPathComponent, sidecar.lastPathComponent]))
    }

    @Test func missingOriginalStatusUsesTheRecordOrLegacyConvertedEPUB() async throws {
        let context = try makeContext()
        let source = try write(Self.ao3HTML, "html")
        defer { try? FileManager.default.removeItem(at: source) }
        let work = try await UserDocumentImport.perform(source, into: context).outcome.work
        defer { cleanUp(work) }
        let original = try #require(Storage.existingOriginalDocumentURL(for: work.id))
        let whenPresent = await WorkProvenanceSections.shouldShowMissingOriginal(for: work)
        #expect(!whenPresent)

        try FileManager.default.removeItem(at: original)
        let whenOnlyTheRecordRemains = await WorkProvenanceSections.shouldShowMissingOriginal(for: work)
        #expect(whenOnlyTheRecordRemains)

        WorkConversionRecord.delete(for: work.id)
        let whenOnlyTheConvertedEPUBRemains = await WorkProvenanceSections.shouldShowMissingOriginal(for: work)
        #expect(whenOnlyTheConvertedEPUBRemains)
    }

    @Test func missingOriginalStatusSkipsPlainEPUBImportsAndAO3Downloads() async throws {
        let sample = try EPUBTests.sampleEPUB
        let context = try makeContext()
        let imported = try await UserDocumentImport.perform(sample, verifyAvailability: false, into: context)
            .outcome.work
        defer { cleanUp(imported) }
        #expect(imported.importSource == .fileImport)
        let forPlainEPUB = await WorkProvenanceSections.shouldShowMissingOriginal(for: imported)
        #expect(!forPlainEPUB)

        let download = SavedWork(title: "Downloaded from AO3", author: "Writer")
        download.ao3WorkID = 42
        download.recordImportSource(.browse)
        defer { cleanUp(download) }
        try FileManager.default.copyItem(at: sample, to: download.fileURL)
        let forDownload = await WorkProvenanceSections.shouldShowMissingOriginal(for: download)
        #expect(!forDownload)
    }
}
