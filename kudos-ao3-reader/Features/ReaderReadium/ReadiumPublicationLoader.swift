#if os(iOS)
import Foundation
import ReadiumShared
import ReadiumStreamer

/// Opens a local EPUB file into a Readium `Publication`.
///
/// This is the Readium replacement for the custom parsing stack in
/// `EPUB.swift` (`MiniZip` + `OPFParser` + `NCXParser` + `NavTOCParser`). Where
/// the old code hand-rolled ZIP extraction and OPF/NCX/nav parsing, Readium's
/// `EPUBParser` produces a fully-formed `Publication` (metadata, reading order,
/// table of contents, resources) from the file.
///
/// Readium's navigator/shared modules link UIKit, so this loader is iOS-only;
/// the original `EPUB.swift` is kept untouched for macOS (and as a fallback)
/// until a later phase.
enum ReadiumPublicationLoader {
    enum LoadError: LocalizedError {
        case notAFileURL

        var errorDescription: String? {
            switch self {
            case .notAFileURL: "The selected item isn't a readable local file."
            }
        }
    }

    /// Opens the EPUB at `fileURL` and returns a parsed `Publication`.
    ///
    /// Pipeline (all Readium):
    /// - `AssetRetriever` reads the file's bytes and sniffs its format.
    /// - `PublicationOpener` runs the `EPUBParser` to build the `Publication`.
    ///
    /// `EPUBParser` is used directly (rather than `DefaultPublicationParser`) so
    /// the loader stays EPUB-only and pulls in no PDF/audio dependencies.
    ///
    /// When `chapterEnd` is provided (reader opens), wraps the container with a
    /// Readium `TransformingContainer` that appends the in-flow end-of-chapter
    /// card to every non-final story chapter while keeping the raw EPUB container
    /// for search, Read Aloud, and positions (`EPUBPositionsService` reads
    /// original archive lengths through `TransformingResource.properties()`).
    static func openEPUB(
        at fileURL: URL,
        chapterEnd: ReaderChapterEndWorkContext? = nil
    ) async throws -> Publication {
        // Readium uses its own strongly-typed URL family; bridge the Foundation URL.
        guard let absoluteURL = fileURL.fileURL else { throw LoadError.notAFileURL }

        // An HTTP client is required even for local files because some
        // publications reference remote resources.
        let httpClient = DefaultHTTPClient()
        let assetRetriever = AssetRetriever(httpClient: httpClient)
        let opener = PublicationOpener(parser: EPUBParser())

        let asset = try await assetRetriever.retrieve(url: absoluteURL).get()
        // allowUserInteraction:false — we only open unprotected AO3 EPUBs, so
        // there's never a credentials prompt to surface.
        guard let chapterEnd else {
            return try await opener.open(asset: asset, allowUserInteraction: false).get()
        }
        return try await opener.open(
            asset: asset,
            allowUserInteraction: false,
            onCreatePublication: { manifest, container, services in
                guard manifest.metadata.layout != .fixed else { return }
                let readingOrder = manifest.readingOrder
                let toc = manifest.tableOfContents.isEmpty ? readingOrder : manifest.tableOfContents
                let cardByHref = await MainActor.run {
                    Self.chapterEndCardsByHref(
                        toc: toc, readingOrder: readingOrder, work: chapterEnd
                    )
                }
                guard !cardByHref.isEmpty else { return }

                let rawContainer = container
                let kudosState = chapterEnd.kudosState
                let styleState = chapterEnd.styleState
                container = TransformingContainer(container: rawContainer) { href, resource in
                    guard let baseCard = Self.card(for: href, in: cardByHref) else {
                        return resource
                    }
                    return resource.mapAsString { html in
                        let card = ReaderChapterEndCardContext(
                            chapter: baseCard.chapter,
                            nextChapterTitle: baseCard.nextChapterTitle,
                            nextChapterHref: baseCard.nextChapterHref,
                            nextChapterTime: baseCard.nextChapterTime,
                            footer: baseCard.footer,
                            showsAO3Actions: baseCard.showsAO3Actions,
                            kudosGiven: kudosState.isGiven,
                            style: styleState.style
                        )
                        return ReaderChapterEndHTML.inject(into: html, card: card)
                    }
                }
                // Keep search and Read Aloud reading the original chapter XHTML so
                // the injected UI card is never searched or spoken aloud.
                services.set(RawEPUBContainerService.self) { _ in
                    RawEPUBContainerService(container: rawContainer)
                }
                services.setContentServiceFactory(
                    DefaultContentService.makeFactory(
                        resourceContentIteratorFactories: [
                            RawContainerHTMLContentIteratorFactory(container: rawContainer),
                        ]
                    )
                )
            }
        ).get()
    }

    private static func chapterEndCardsByHref(
        toc: [ReadiumShared.Link],
        readingOrder: [ReadiumShared.Link],
        work: ReaderChapterEndWorkContext
    ) -> [String: ReaderChapterEndCardContext] {
        let sections = ReadiumBook.buildSections(toc: toc, readingOrder: readingOrder)
        var cards: [String: ReaderChapterEndCardContext] = [:]
        for index in readingOrder.indices {
            if let mediaType = readingOrder[index].mediaType, !mediaType.isHTML {
                continue
            }
            guard let card = ReaderChapterEndHTML.cardContext(
                forSpineIndex: index, sections: sections, work: work
            ) else {
                continue
            }
            let key = normalizedResourceKey(readingOrder[index].url())
            cards[key] = card
        }
        return cards
    }

    nonisolated private static func card(
        for href: AnyURL,
        in cards: [String: ReaderChapterEndCardContext]
    ) -> ReaderChapterEndCardContext? {
        cards[normalizedResourceKey(href)]
    }

    nonisolated private static func normalizedResourceKey(_ url: AnyURL) -> String {
        var string = url.removingQuery().removingFragment().normalized.string
        while string.hasPrefix("/") { string.removeFirst() }
        return string
    }
}

/// Exposes the pre-transform EPUB container so Read Aloud reads original chapter
/// XHTML rather than the injected end-of-chapter UI card.
nonisolated final class RawEPUBContainerService: PublicationService {
    private let container: Container

    init(container: Container) {
        self.container = container
    }

    func resource(for link: ReadiumShared.Link) -> Resource? {
        let url = link.url()
        return container[url] ?? container[url.removingQuery().removingFragment()]
    }
}

/// Feeds `HTMLResourceContentIterator` from the pre-transform container so
/// `ContentSearchService` (Find in Work) searches only original chapter text.
nonisolated final class RawContainerHTMLContentIteratorFactory: ResourceContentIteratorFactory {
    private let container: Container
    private let htmlFactory = HTMLResourceContentIterator.Factory()

    init(container: Container) {
        self.container = container
    }

    func make(
        publication: Publication,
        readingOrderIndex: Int,
        resource: Resource,
        locator: Locator
    ) -> ContentIterator? {
        let rawResource = container[locator.href]
            ?? container[locator.href.removingQuery().removingFragment()]
            ?? resource
        return htmlFactory.make(
            publication: publication,
            readingOrderIndex: readingOrderIndex,
            resource: rawResource,
            locator: locator
        )
    }
}
#endif
