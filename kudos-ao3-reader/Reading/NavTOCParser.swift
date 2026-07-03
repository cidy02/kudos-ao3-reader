import Foundation

/// Parses an EPUB3 navigation document's `toc` nav into (title, src) pairs.
final nonisolated class NavTOCParser: NSObject, XMLParserDelegate {
    var entries: [(title: String, src: String)] = []

    private var inToc = false
    private var inAnchor = false
    private var href = ""
    private var buffer = ""

    func parse(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes: [String: String]
    ) {
        switch localName(elementName) {
        case "nav":
            let type = attributes["epub:type"] ?? attributes["type"] ?? ""
            let navID = attributes["id"] ?? ""
            if type.contains("toc") || navID == "toc" { inToc = true }
        case "a" where inToc:
            inAnchor = true
            href = attributes["href"] ?? ""
            buffer = ""
        default:
            break
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        if inAnchor { buffer += string }
    }

    func parser(
        _: XMLParser,
        didEndElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?
    ) {
        switch localName(elementName) {
        case "a" where inAnchor:
            if !href.isEmpty {
                entries.append((buffer.trimmingCharacters(in: .whitespacesAndNewlines), href))
            }
            inAnchor = false
        case "nav" where inToc:
            inToc = false
        default:
            break
        }
    }
}
