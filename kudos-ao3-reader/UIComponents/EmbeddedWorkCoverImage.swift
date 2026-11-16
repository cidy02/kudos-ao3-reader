import Foundation
import ImageIO
import SwiftSoup
import UniformTypeIdentifiers

/// Finds author-supplied art already inside a downloaded EPUB. Never requests remote images.
nonisolated enum EmbeddedWorkCoverImage {
    struct Candidate {
        let data: Data
        let frontMatter: Bool
        let pixelArea: Int
    }

    static func preferred(_ current: Candidate?, _ candidate: Candidate) -> Candidate {
        guard let current else { return candidate }
        if candidate.frontMatter != current.frontMatter {
            return candidate.frontMatter ? candidate : current
        }
        return candidate.pixelArea > current.pixelArea ? candidate : current
    }

    static func accepts(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0, width <= 20_000, height <= 20_000 else { return false }
        return min(width, height) >= 320 && (0.40...1.85).contains(Double(width) / Double(height))
    }

    static func data(at epubURL: URL) -> Data? {
        guard let archive = try? Data(contentsOf: epubURL),
              let zip = try? MiniZip(data: archive),
              let container = zip.data(named: "META-INF/container.xml"),
              let opfPath = EPUBDocument.rootfilePath(from: container) else { return nil }
        let root = URL(fileURLWithPath: "/KudosGeneratedCoverArt", isDirectory: true)
        let rootPath = root.path + "/"
        func entryName(_ url: URL) -> String? {
            let path = url.standardizedFileURL.path
            guard url.isFileURL, path.hasPrefix(rootPath) else { return nil }
            return String(path.dropFirst(rootPath.count))
        }
        let opfURL = root.appendingPathComponent(opfPath).standardizedFileURL
        guard let opfName = entryName(opfURL),
              let opfData = zip.data(named: opfName) else { return nil }
        let parser = OPFParser()
        guard parser.parse(opfData) else { return nil }
        let opfDir = opfURL.deletingLastPathComponent()
        let pages: [URL] = parser.spine.compactMap { id in
            guard let href = parser.manifest[id],
                  let url = URL(string: href, relativeTo: opfDir)?.absoluteURL,
                  entryName(url) != nil else { return nil }
            return url
        }
        guard !pages.isEmpty else { return nil }
        let chapters = EPUBDocument.tableOfContents(
            parser: parser, opfDir: opfDir, spineCount: pages.count,
            readData: { url in entryName(url).flatMap(zip.data(named:)) }
        )
        let sections = ReaderSectionBuilder.build(
            tocEntries: chapters.map {
                ReaderSectionBuilder.RawTOCEntry(title: $0.title, spineIndex: $0.spineIndex)
            },
            spineHrefs: pages.map(\.lastPathComponent)
        )
        let firstChapter = sections.first(where: { $0.kind == .chapter })?.spineIndex ?? 0
        var best: Candidate?
        for index in 0...firstChapter where pages.indices.contains(index) {
            let pageURL = pages[index]
            guard let pageName = entryName(pageURL),
                  let pageData = zip.data(named: pageName),
                  let xhtml = String(data: pageData, encoding: .utf8),
                  let page = try? SwiftSoup.parse(xhtml),
                  let images = try? page.select("img[src]").array() else { continue }
            for image in images {
                guard let src = try? image.attr("src"),
                      !src.isEmpty, !src.hasPrefix("//"),
                      let url = URL(string: src, relativeTo: pageURL)?.absoluteURL,
                      url.isFileURL else { continue }
                guard let name = entryName(url),
                      let bytes = zip.uncompressedSize(named: name),
                      bytes <= 20_000_000,
                      let data = zip.data(named: name),
                      let imageSource = CGImageSourceCreateWithData(data as CFData,
                          [kCGImageSourceShouldCache: false] as CFDictionary),
                      let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? NSDictionary,
                      let width = properties[kCGImagePropertyPixelWidth] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight] as? Int,
                      accepts(width: width, height: height) else { continue }
                let candidate = Candidate(data: data, frontMatter: index < firstChapter,
                                          pixelArea: width * height)
                best = preferred(best, candidate)
            }
        }
        return best?.data
    }

    static func downsampledJPEG(_ data: Data?) -> Data? {
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 600
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
