import Foundation

/// Parses an OPF package document: Dublin Core metadata + manifest + spine.
nonisolated final class OPFParser: NSObject, XMLParserDelegate {
    var title = ""
    var author = ""
    var summary = ""
    var subjects: [String] = []
    var identifiers: [String] = []
    var sources: [String] = []
    var dates: [String] = []
    var language = ""
    var publishedDate = ""
    var updatedDate = ""
    var seriesTitle = ""
    var seriesIndex: Int?
    var metaContents: [String] = []
    var manifest: [String: String] = [:]        // item id -> href
    var manifestMedia: [String: String] = [:]   // item id -> media-type
    var manifestProps: [String: String] = [:]   // item id -> properties
    var spine: [String] = []                     // itemref idref order
    var tocID: String?                           // <spine toc="..."> (NCX id)

    private var currentElement = ""
    private var buffer = ""
    private var currentMetaName = ""

    func parse(_ data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser.parse()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String]
    ) {
        let name = elementName.contains(":")
            ? String(elementName.split(separator: ":").last!)
            : elementName
        currentElement = name
        buffer = ""

        switch name {
        case "item":
            if let id = attributes["id"], let href = attributes["href"] {
                manifest[id] = href
                manifestMedia[id] = attributes["media-type"]
                manifestProps[id] = attributes["properties"]
            }
        case "itemref":
            if let idref = attributes["idref"] { spine.append(idref) }
        case "spine":
            if let toc = attributes["toc"] { tocID = toc }
        case "meta":
            // calibre encodes series via <meta name="calibre:series" content="…">.
            currentMetaName = attributes["name"] ?? attributes["property"] ?? ""
            if let content = attributes["content"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !content.isEmpty {
                metaContents.append(content)
            }
            switch attributes["name"] {
            case "calibre:series": seriesTitle = attributes["content"] ?? ""
            case "calibre:series_index":
                if let content = attributes["content"], let value = Double(content) {
                    seriesIndex = Int(value)   // calibre writes "1" or "1.0"
                }
            default: break
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.contains(":")
            ? String(elementName.split(separator: ":").last!)
            : elementName
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch name {
        case "title" where title.isEmpty:
            title = value
        case "creator" where author.isEmpty:
            author = value
        case "description" where summary.isEmpty:
            summary = value
        case "identifier":
            Self.append(value, to: &identifiers)
        case "source":
            Self.append(value, to: &sources)
        case "date":
            recordDate(value)
        case "subject":
            Self.append(value, to: &subjects)
        case "language" where language.isEmpty:
            language = value
        case "meta":
            recordMeta(value)
            currentMetaName = ""
        default:
            break
        }
        buffer = ""
    }

    /// Text corpus used for best-effort source URL detection without caring which
    /// OPF metadata bucket an exporter chose.
    var metadataSearchText: String {
        ([title, author, summary, language, publishedDate, updatedDate]
            + identifiers + sources + dates + subjects + metaContents)
            .joined(separator: "\n")
    }

    private static func append(_ value: String, to values: inout [String]) {
        if !value.isEmpty { values.append(value) }
    }

    private func recordDate(_ value: String) {
        guard !value.isEmpty else { return }
        dates.append(value)
        if publishedDate.isEmpty { publishedDate = value }
    }

    private func recordMeta(_ value: String) {
        guard !value.isEmpty else { return }
        metaContents.append(value)
        let name = currentMetaName.lowercased()
        if updatedDate.isEmpty, name.contains("modified") {
            updatedDate = value
        } else if publishedDate.isEmpty,
                  name.contains("published") || name.contains("issued") {
            publishedDate = value
        }
    }
}
