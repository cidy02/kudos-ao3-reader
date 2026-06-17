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
    static func openEPUB(at fileURL: URL) async throws -> Publication {
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
        return try await opener.open(asset: asset, allowUserInteraction: false).get()
    }
}
#endif
