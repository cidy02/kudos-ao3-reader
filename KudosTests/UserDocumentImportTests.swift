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
            SavedSearch.self, SyncTombstone.self, ReadingAnnotation.self
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

    /// Removes everything an import leaves in the app's permanent storage.
    private func cleanUp(_ work: SavedWork) {
        try? FileManager.default.removeItem(at: work.fileURL)
        if let original = Storage.existingOriginalDocumentURL(for: work.id) {
            try? FileManager.default.removeItem(at: original)
        }
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

        let result = try await UserDocumentImport.perform(source, into: context)
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
}
