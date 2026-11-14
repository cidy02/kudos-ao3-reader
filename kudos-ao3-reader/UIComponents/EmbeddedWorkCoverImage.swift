import Foundation
import ImageIO
import SwiftSoup

/// Finds author-supplied art already inside a downloaded EPUB. Never requests remote images.
nonisolated enum EmbeddedWorkCoverImage {
    struct Candidate {
        let data: Data
        let frontMatter: Bool
        let pixelArea: Int
    }

    static func preferred(_ candidates: [Candidate]) -> Data? {
        candidates.reduce(nil as Candidate?) { current, candidate in
            guard let current else { return candidate }
            return better(candidate, than: current) ? candidate : current
        }?.data
    }

    private static func better(_ candidate: Candidate, than current: Candidate) -> Bool {
        if candidate.frontMatter != current.frontMatter { return candidate.frontMatter }
        return candidate.pixelArea > current.pixelArea
    }

    static func accepts(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0, width <= 20_000, height <= 20_000 else { return false }
        return min(width, height) >= 320 && (0.40...1.85).contains(Double(width) / Double(height))
    }

    static func data(at epubURL: URL) -> Data? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cover-image-\(UUID().uuidString)", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: directory) }
        guard let document = try? EPUBDocument.open(epubURL: epubURL, into: directory) else { return nil }
        let sections = ReaderSectionBuilder.build(
            tocEntries: document.chapters.map {
                ReaderSectionBuilder.RawTOCEntry(title: $0.title, spineIndex: $0.spineIndex)
            },
            spineHrefs: document.spineURLs.map(\.lastPathComponent)
        )
        let firstChapter = sections.first(where: { $0.kind == .chapter })?.spineIndex ?? 0
        let root = directory.standardizedFileURL.path + "/"
        var best: Candidate?
        for index in 0...firstChapter where document.spineURLs.indices.contains(index) {
            let pageURL = document.spineURLs[index]
            guard let xhtml = try? String(contentsOf: pageURL, encoding: .utf8),
                  let page = try? SwiftSoup.parse(xhtml),
                  let images = try? page.select("img[src]").array() else { continue }
            for image in images {
                guard let src = try? image.attr("src"),
                      !src.isEmpty, !src.hasPrefix("//"),
                      let url = URL(string: src, relativeTo: pageURL)?.absoluteURL,
                      url.isFileURL else { continue }
                let file = url.standardizedFileURL
                guard file.path.hasPrefix(root),
                      let bytes = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      bytes <= 20_000_000,
                      let data = try? Data(contentsOf: file),
                      let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? NSDictionary,
                      let width = properties[kCGImagePropertyPixelWidth] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight] as? Int,
                      accepts(width: width, height: height) else { continue }
                let candidate = Candidate(data: data, frontMatter: index < firstChapter,
                                          pixelArea: width * height)
                if let best, !better(candidate, than: best) { continue }
                best = candidate
            }
        }
        return best?.data
    }
}
