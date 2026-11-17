import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Changes only the exported copy. The original EPUB and its recorded digest never move.
nonisolated enum EPUBCoverExport {
    enum ExportError: LocalizedError {
        case coverUnavailable
        var errorDescription: String? { "A cover could not be created for this work." }
    }

    static func copy(from source: URL, to destination: URL, includeCover: Bool,
                     coverJPEG: Data? = nil) throws {
        try Task.checkCancellation()
        guard includeCover else { try FileManager.default.copyItem(at: source, to: destination); return }
        let zip = try MiniZip(data: Data(contentsOf: source, options: .mappedIfSafe))
        guard let container = zip.data(named: "META-INF/container.xml"),
              let opfPath = EPUBDocument.rootfilePath(from: container),
              let opfData = zip.data(named: opfPath) else { throw EPUBError.missingPackage }
        let parser = OPFParser()
        guard parser.parse(opfData) else { throw EPUBError.malformedPackage }
        // Existing declarations win, even when this app would choose different art.
        if parser.coverMetaID != nil || parser.hasGuideCover || parser.manifestProps.values.contains(where: {
            $0.split(whereSeparator: \.isWhitespace).contains("cover-image")
        }) {
            try FileManager.default.copyItem(at: source, to: destination)
            return
        }
        guard let coverJPEG else { throw ExportError.coverUnavailable }
        guard var opf = decodeOPF(opfData) else {
            throw EPUBError.malformedPackage
        }
        // A UTF-16 source is written as UTF-8 along with its new archive entry.
        opf = opf.replacingOccurrences(of: #"encoding\s*=\s*(['"])utf-16(?:le|be)?\1"#,
                                       with: "encoding=\"utf-8\"",
                                       options: [.regularExpression, .caseInsensitive])
        let opfDir = (opfPath as NSString).deletingLastPathComponent
        func path(_ name: String) -> String { opfDir.isEmpty ? name : opfDir + "/" + name }
        let existingNames = Set(zip.names.map { $0.lowercased() })
        var base = "kudos-export-cover"
        while existingNames.contains(path(base + ".jpg").lowercased())
                || existingNames.contains(path(base + ".xhtml").lowercased()) {
            base += "-1"
        }
        var imageID = "kudos-export-cover-image"
        while parser.manifest[imageID] != nil { imageID += "-1" }
        var pageID = "kudos-export-cover-page"
        while parser.manifest[pageID] != nil || pageID == imageID { pageID += "-1" }
        let edited = try addingCoverDeclarations(to: opf, imageID: imageID,
                                                 pageID: pageID, base: base)
        let page = """
        <?xml version="1.0" encoding="utf-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>Cover</title>
        <style type="text/css">
        html,body{height:100%;margin:0}
        img{display:block;max-width:100%;max-height:100%;width:auto;height:auto;margin:auto}
        </style>
        </head><body><img src="\(base).jpg" alt="Cover"/></body></html>
        """
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let handle = try FileHandle(forWritingTo: destination)
        do {
            let writer = MiniZip.ArchiveWriter { try handle.write(contentsOf: $0) }
            try writer.append(name: "mimetype", data: Data("application/epub+zip".utf8))
            for name in zip.names where name != "mimetype" {
                try Task.checkCancellation()
                guard let data = zip.data(named: name) else { throw MiniZipError.truncatedRecord }
                try writer.append(name: name, data: name == opfPath ? Data(edited.utf8) : data)
            }
            try writer.append(name: path(base + ".jpg"), data: coverJPEG)
            try writer.append(name: path(base + ".xhtml"), data: Data(page.utf8))
            try writer.finish()
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// Match XML tag positions after masking comments; edits use UTF-16 offsets in the original.
    private static func addingCoverDeclarations(
        to opf: String, imageID: String, pageID: String, base: String
    ) throws -> String {
        let masked = NSMutableString(string: opf)
        let fullRange = NSRange(location: 0, length: masked.length)
        let comments = try NSRegularExpression(pattern: #"<!--[\s\S]*?-->"#)
        for match in comments.matches(in: opf, range: fullRange).reversed() {
            masked.replaceCharacters(in: match.range,
                                     with: String(repeating: " ", count: match.range.length))
        }
        let source = masked as String
        func tag(_ pattern: String) throws -> (NSRange, String) {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            guard let match = regex.firstMatch(in: source,
                                               range: NSRange(location: 0, length: masked.length)) else {
                throw EPUBError.malformedPackage
            }
            return (match.range, (opf as NSString).substring(with: match.range))
        }
        let metadata = try tag(#"</\s*(?:[A-Za-z_][\w.-]*:)?metadata\s*>"#)
        let manifest = try tag(#"</\s*(?:[A-Za-z_][\w.-]*:)?manifest\s*>"#)
        let spine = try tag(#"<\s*(?:[A-Za-z_][\w.-]*:)?spine\b(?:[^>"']|"[^"]*"|'[^']*')*>"#)
        func prefix(_ tag: String, name: String) -> String {
            let pattern = #"(?:[A-Za-z_][\w.-]*:)?"# + name
            let match = tag.range(of: pattern, options: [.regularExpression, .caseInsensitive])
            guard let match else { return "" }
            let qualified = String(tag[match])
            return qualified.contains(":") ? String(qualified.prefix(while: { $0 != ":" })) + ":" : ""
        }
        let metaPrefix = prefix(metadata.1, name: "metadata")
        let itemPrefix = prefix(manifest.1, name: "manifest")
        let spinePrefix = prefix(spine.1, name: "spine")
        let package = try tag(#"<\s*(?:[A-Za-z_][\w.-]*:)?package\b(?:[^>"']|"[^"]*"|'[^']*')*>"#)
        let epub2 = package.1.range(of: #"\bversion\s*=\s*['"]2\."#,
                                    options: .regularExpression) != nil
        let imageProperties = epub2 ? "" : " properties=\"cover-image\""
        let meta = "<\(metaPrefix)meta name=\"cover\" content=\"\(imageID)\"/>"
        let items = "<\(itemPrefix)item id=\"\(imageID)\" href=\"\(base).jpg\""
            + " media-type=\"image/jpeg\"\(imageProperties)/>"
            + "<\(itemPrefix)item id=\"\(pageID)\" href=\"\(base).xhtml\" media-type=\"application/xhtml+xml\"/>"
        let itemref = "<\(spinePrefix)itemref idref=\"\(pageID)\"/>"
        let selfClosing = spine.1.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("/>")
        let spineEdit = selfClosing
            ? (spine.0, String(spine.1.dropLast(2)) + ">" + itemref + "</\(spinePrefix)spine>")
            : (NSRange(location: NSMaxRange(spine.0), length: 0), itemref)
        let edits: [(NSRange, String)] = [
            (NSRange(location: metadata.0.location, length: 0), meta),
            (NSRange(location: manifest.0.location, length: 0), items),
            spineEdit
        ]
        let result = NSMutableString(string: opf)
        for (range, replacement) in edits.sorted(by: { $0.0.location > $1.0.location }) {
            result.replaceCharacters(in: range, with: replacement)
        }
        return result as String
    }

    private static func decodeOPF(_ data: Data) -> String? {
        if !data.contains(0), let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        let hasBOM = data.starts(with: [0xFE, 0xFF]) || data.starts(with: [0xFF, 0xFE])
        let candidate: String?
        if hasBOM {
            candidate = String(data: data, encoding: .utf16)
        } else if data.starts(with: [0x00, 0x3C]) {
            candidate = String(data: data, encoding: .utf16BigEndian)
        } else if data.starts(with: [0x3C, 0x00]) {
            candidate = String(data: data, encoding: .utf16LittleEndian)
        } else {
            return nil
        }
        guard let candidate else { return nil }
        let hasDeclaration = candidate.range(
            of: #"<\?xml\b[^>]*\bencoding\s*=\s*['"]utf-16(?:le|be)?['"]"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        return (hasBOM || hasDeclaration) ? candidate : nil
    }

    static func embeddedJPEG(at url: URL) -> Data? {
        encodedEmbeddedJPEG(EmbeddedWorkCoverImage.data(at: url))
    }

    static func encodedEmbeddedJPEG(_ embedded: Data?) -> Data? {
        guard let embedded,
              let source = CGImageSourceCreateWithData(embedded as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2400
              ] as CFDictionary) else { return nil }
        return encodeJPEG(flattenedOntoWhiteIfNeeded(image))
    }

    private static func flattenedOntoWhiteIfNeeded(_ image: CGImage) -> CGImage {
        switch image.alphaInfo {
        case .none, .noneSkipLast, .noneSkipFirst:
            return image
        default:
            break
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return image
        }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(bounds)
        context.draw(image, in: bounds)
        return context.makeImage() ?? image
    }

    @MainActor
    static func jpeg(for work: SavedWork) -> Data? {
        embeddedJPEG(at: work.fileURL) ?? generatedJPEG(for: work)
    }

    @MainActor
    static func generatedJPEG(for work: SavedWork) -> Data? {
        generatedJPEG(recipe: work.generatedCoverRecipe)
    }

    @MainActor
    static func generatedJPEG(recipe: GeneratedCoverRecipe) -> Data? {
        let renderer = ImageRenderer(content: GeneratedCoverView(
            recipe: recipe, width: 1600, height: 2400,
            showsArt: true, cornerRadius: 0
        ))
        renderer.scale = 1
        return renderer.cgImage.flatMap(encodeJPEG)
    }

    private static func encodeJPEG(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
