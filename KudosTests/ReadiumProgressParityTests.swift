import Foundation
import Testing

#if os(iOS)
import ReadiumShared
@testable import Kudos
#endif

#if os(iOS)
/// The macOS reader cannot run Readium, so it rebuilds Readium's
/// `totalProgression` from the EPUB's ZIP entry lengths
/// (`WorkReadingPosition.publicationProgress`). This opens the same files with
/// both stacks and checks every resource starts at the same fraction, so the two
/// platforms print the same card percent — and a Readium change to its position
/// formula fails here rather than silently skewing Mac labels.
struct ReadiumProgressParityTests {
    private func paragraphs(bytes: Int) -> String {
        String(repeating: "<p>Lorem ipsum dolor sit amet, consectetur.</p>", count: max(1, bytes / 48))
    }

    private func builtEPUB() throws -> URL {
        let data = try EPUBBuilder.archive(
            metadata: .init(title: "Parity", identifier: "parity"),
            chapters: [
                .init(title: "Short", bodyXHTML: paragraphs(bytes: 300)),
                .init(title: "Medium", bodyXHTML: paragraphs(bytes: 5_000)),
                .init(title: "Long", bodyXHTML: paragraphs(bytes: 20_000))
            ],
            modified: Date(timeIntervalSince1970: 0)
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("epub")
        try data.write(to: url)
        return url
    }

    private func expectParity(_ epub: URL) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lengths = try EPUBDocument.open(epubURL: epub, into: directory).spineEntryLengths
        let publication = try await ReadiumPublicationLoader.openEPUB(at: epub)
        let positions = try await publication.positionsByReadingOrder().get()

        // Readium's reading order is the spine minus the items it leaves out.
        let spines = lengths.indices.filter { lengths[$0] != nil }
        #expect(positions.count == spines.count)
        func mac(_ spine: Int, _ fraction: Double) throws -> Double {
            try #require(WorkReadingPosition.publicationProgress(
                spineIndex: spine, chapterFraction: fraction, resourceLengths: lengths))
        }
        for (index, spine) in zip(positions.indices, spines) {
            // ViewportProgressionCalculator: linear from this resource's first
            // position to the next resource's (1 after the last).
            let start = try #require(positions[index].first?.locations.totalProgression)
            let end = index + 1 < positions.count
                ? (positions[index + 1].first?.locations.totalProgression ?? 1) : 1
            for fraction in [0, 0.5, 1] {
                let readium = start + fraction * (end - start)
                let ours = try mac(spine, fraction)
                #expect(abs(readium - ours) < 1e-9, "resource \(index) at \(fraction): Readium \(readium), Mac \(ours)")
            }
            // And every position Readium lists inside the resource.
            for locator in positions[index] {
                let readium = try #require(locator.locations.totalProgression)
                let ours = try mac(spine, try #require(locator.locations.progression))
                #expect(abs(readium - ours) < 1e-9, "\(locator.locations.position ?? 0): \(readium) vs \(ours)")
            }
        }
    }

    /// Calibre-style: a heavy `linear="no"` cover that Readium leaves out of its
    /// reading order, and a chapter whose file name the OPF must percent-encode.
    private func nonLinearEPUB() throws -> URL {
        func page(_ bytes: Int) -> Data {
            Data(("<?xml version=\"1.0\" encoding=\"utf-8\"?><html xmlns=\"http://www.w3.org/1999/xhtml\">"
                + "<head><title>T</title></head><body>\(paragraphs(bytes: bytes))</body></html>").utf8)
        }
        let container = """
        <?xml version="1.0"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """
        let opf = """
        <?xml version="1.0" encoding="utf-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="id">nonlinear</dc:identifier><dc:title>Nonlinear</dc:title><dc:language>en</dc:language>
          </metadata>
          <manifest>
            <item id="cover" href="cover.xhtml" media-type="application/xhtml+xml"/>
            <item id="c1" href="ch%201.xhtml" media-type="application/xhtml+xml"/>
            <item id="c2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine><itemref idref="cover" linear="no"/><itemref idref="c1"/><itemref idref="c2"/></spine>
        </package>
        """
        let data = try MiniZip.archiveData([
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", Data(container.utf8)),
            ("OEBPS/content.opf", Data(opf.utf8)),
            ("OEBPS/cover.xhtml", page(40_000)),
            ("OEBPS/ch 1.xhtml", page(3_000)),
            ("OEBPS/ch2.xhtml", page(9_000))
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("epub")
        try data.write(to: url)
        return url
    }

    @Test func nonLinearItemsAndEncodedNamesWeighLikeReadium() async throws {
        let epub = try nonLinearEPUB()
        defer { try? FileManager.default.removeItem(at: epub) }
        try await expectParity(epub)
    }

    @Test func storedEntriesStartWhereReadiumSays() async throws {
        let epub = try builtEPUB()
        defer { try? FileManager.default.removeItem(at: epub) }
        try await expectParity(epub)
    }

    @Test func deflatedEntriesStartWhereReadiumSays() async throws {
        try await expectParity(try EPUBTests.sampleEPUB)
    }

    /// Pins the length basis: ch1 is 6,347 bytes raw (7 positions) but 130
    /// deflated (1), so ch2 starts at 0.5 on archived lengths and 0.875 on raw ones.
    @Test func deflatedLengthsNotRawOnesSizePositions() async throws {
        let epub = try #require(
            Bundle(for: EPUBTests.BundleAnchor.self).url(forResource: "deflated-parity", withExtension: "epub"))
        let zip = try MiniZip(data: try Data(contentsOf: epub))
        #expect(zip.entryLength(named: "OEBPS/ch1.xhtml") == 130)
        #expect(zip.uncompressedSize(named: "OEBPS/ch1.xhtml") == 6_347)
        try await expectParity(epub)
    }
}
#endif
