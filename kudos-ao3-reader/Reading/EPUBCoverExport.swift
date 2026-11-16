import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Changes only the exported copy. The original EPUB and its recorded digest never move.
enum EPUBCoverExport {
    static func copy(from source: URL, to destination: URL, includeCover: Bool,
                     coverJPEG: Data? = nil) throws {
        let original = try Data(contentsOf: source)
        guard includeCover else { try original.write(to: destination, options: .atomic); return }
        let zip = try MiniZip(data: original)
        guard let container = zip.data(named: "META-INF/container.xml"),
              let opfPath = EPUBDocument.rootfilePath(from: container),
              let opfData = zip.data(named: opfPath),
              let opf = String(data: opfData, encoding: .utf8) else { throw EPUBError.missingPackage }
        let parser = OPFParser()
        guard parser.parse(opfData) else { throw EPUBError.malformedPackage }
        // Existing declarations win, even when this app would choose different art.
        if parser.coverMetaID != nil || parser.manifestProps.values.contains(where: {
            $0.split(separator: " ").contains("cover-image")
        }) {
            try original.write(to: destination, options: .atomic)
            return
        }
        guard let coverJPEG else { throw EPUBError.missingPackage }
        let opfDir = (opfPath as NSString).deletingLastPathComponent
        func path(_ name: String) -> String { opfDir.isEmpty ? name : opfDir + "/" + name }
        var base = "kudos-export-cover"
        while zip.names.contains(path(base + ".jpg")) || zip.names.contains(path(base + ".xhtml")) {
            base += "-1"
        }
        let imageID = "kudos-export-cover-image"
        let pageID = "kudos-export-cover-page"
        guard !parser.manifest.keys.contains(imageID), !parser.manifest.keys.contains(pageID),
              let metadataEnd = opf.range(of: "</metadata>", options: .caseInsensitive),
              let manifestEnd = opf.range(of: "</manifest>", options: .caseInsensitive),
              let spineStart = opf.range(of: "<spine", options: .caseInsensitive),
              let spineOpenEnd = opf[spineStart.lowerBound...].firstIndex(of: ">") else {
            throw EPUBError.malformedPackage
        }
        var edited = opf
        // Insert backwards so ranges from the original text remain valid.
        let firstPage = parser.spine.first.flatMap { parser.manifest[$0] }
            .flatMap { zip.data(named: path($0.removingPercentEncoding ?? $0)) }
            .flatMap { String(data: $0, encoding: .utf8) }
        if firstPage?.range(of: "<img", options: .caseInsensitive) == nil {
            edited.insert(contentsOf: "<itemref idref=\"\(pageID)\"/>", at: edited.index(after: spineOpenEnd))
        }
        edited.insert(contentsOf: "<item id=\"\(imageID)\" href=\"\(base).jpg\" media-type=\"image/jpeg\" properties=\"cover-image\"/><item id=\"\(pageID)\" href=\"\(base).xhtml\" media-type=\"application/xhtml+xml\"/>", at: manifestEnd.lowerBound)
        edited.insert(contentsOf: "<meta name=\"cover\" content=\"\(imageID)\"/>", at: metadataEnd.lowerBound)
        let page = """
        <?xml version="1.0" encoding="utf-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>Cover</title></head><body style="margin:0"><img src="\(base).jpg" alt="Cover" style="width:100%;height:auto"/></body></html>
        """
        var entries: [(name: String, data: Data)] = []
        for name in zip.names {
            guard let data = zip.data(named: name) else { throw MiniZipError.truncatedRecord }
            entries.append((name, name == opfPath ? Data(edited.utf8) : data))
        }
        entries.append((path(base + ".jpg"), coverJPEG))
        entries.append((path(base + ".xhtml"), Data(page.utf8)))
        try MiniZip.archiveData(entries).write(to: destination, options: .atomic)
    }

    @MainActor
    static func jpeg(for work: SavedWork) -> Data? {
        if let embedded = EmbeddedWorkCoverImage.data(at: work.fileURL),
           let source = CGImageSourceCreateWithData(embedded as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            let width = 1600, height = 2400
            let scale = max(CGFloat(width) / CGFloat(image.width), CGFloat(height) / CGFloat(image.height))
            let drawnWidth = CGFloat(image.width) * scale
            let drawnHeight = CGFloat(image.height) * scale
            if let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                       bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                context.draw(image, in: CGRect(x: (CGFloat(width) - drawnWidth) / 2,
                                               y: (CGFloat(height) - drawnHeight) / 2,
                                               width: drawnWidth, height: drawnHeight))
                if let fitted = context.makeImage() { return encodeJPEG(fitted) }
            }
        }
        // The same recipe and drawing view used by the library cover.
        let renderer = ImageRenderer(content: GeneratedCoverView(
            recipe: work.generatedCoverRecipe, width: 1600, height: 2400, showsArt: true
        ).background(.white))
        renderer.scale = 1
        return renderer.cgImage.flatMap(encodeJPEG)
    }

    private static func encodeJPEG(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
