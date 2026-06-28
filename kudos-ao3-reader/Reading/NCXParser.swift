import Foundation

/// Parses an EPUB2 NCX document into (title, src) pairs in document order.
nonisolated final class NCXParser: NSObject, XMLParserDelegate {
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
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
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

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { buffer += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if localName(elementName) == "text" {
            inText = false
            pendingTitle = buffer
        }
    }
}
