import Foundation

/// Parses an EPUB2 NCX document into (title, src) pairs in document order.
final nonisolated class NCXParser: NSObject, XMLParserDelegate {
    var entries: [(title: String, src: String)] = []

    private var inText = false
    private var buffer = ""
    private var pendingTitle = ""

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
        case "text":
            inText = true
            buffer = ""
        case "content":
            if let src = attributes["src"] {
                entries.append((pendingTitle.trimmingCharacters(in: .whitespacesAndNewlines), src))
            }
        default:
            break
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        if inText { buffer += string }
    }

    func parser(
        _: XMLParser,
        didEndElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?
    ) {
        if localName(elementName) == "text" {
            inText = false
            pendingTitle = buffer
        }
    }
}
