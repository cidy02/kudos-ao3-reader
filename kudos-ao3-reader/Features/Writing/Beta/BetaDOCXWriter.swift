import Foundation

// MARK: - OOXML (.docx) writer with Track Changes turned on

/// Builds a standards-compliant `.docx` package from AO3 chapter HTML using
/// `MiniZip.ArchiveWriter` and `SwiftSoup`, with `<w:trackRevisions/>` enabled so
/// Microsoft Word and Google Docs open it ready for beta suggestions and comments.
nonisolated enum BetaDOCXWriter {
    private static let xmlHeader = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"

    static func writeDOCX(
        html: String,
        title: String,
        author: String = "",
        date: Date = Date()
    ) throws -> Data {
        let blocks = BetaHTMLDocument.parse(html)
        let hasLists = blocks.contains { block in
            if case .listItem = block.kind { return true }
            return false
        }
        let orderedListIDs = collectOrderedListIDs(in: blocks)

        var hyperlinks: [(id: String, url: String)] = []
        var hyperlinkIDByURL: [String: String] = [:]
        // rId1 = styles.xml, rId2 = settings.xml, rId3 = numbering.xml (when present).
        var nextRelID = hasLists ? 4 : 3

        let documentXML = buildDocumentXML(
            blocks: blocks,
            hyperlinkIDFor: { url in
                if let existing = hyperlinkIDByURL[url] { return existing }
                let relID = "rId\(nextRelID)"
                nextRelID += 1
                hyperlinkIDByURL[url] = relID
                hyperlinks.append((id: relID, url: url))
                return relID
            }
        )

        var entries: [(name: String, data: Data)] = [
            ("[Content_Types].xml", Data(contentTypesXML(hasLists: hasLists).utf8)),
            ("_rels/.rels", Data(rootRelsXML().utf8)),
            ("word/document.xml", Data(documentXML.utf8)),
            ("word/styles.xml", Data(stylesXML().utf8)),
            ("word/settings.xml", Data(settingsXML().utf8)),
            (
                "word/_rels/document.xml.rels",
                Data(documentRelsXML(hasLists: hasLists, hyperlinks: hyperlinks).utf8)
            ),
            (
                "docProps/core.xml",
                Data(corePropertiesXML(title: title, author: author, date: date).utf8)
            ),
        ]
        if hasLists {
            entries.append((
                "word/numbering.xml",
                Data(numberingXML(orderedListIDs: orderedListIDs).utf8)
            ))
        }

        var archive = Data()
        let writer = MiniZip.ArchiveWriter { chunk in
            archive.append(chunk)
        }
        for entry in entries {
            try writer.append(name: entry.name, data: entry.data)
        }
        try writer.finish()
        return archive
    }

    static func escapeXML(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x26: result.append("&amp;")
            case 0x3C: result.append("&lt;")
            case 0x3E: result.append("&gt;")
            case 0x22: result.append("&quot;")
            case 0x27: result.append("&apos;")
            case 0x09, 0x0A, 0x0D, 0x20...:
                result.unicodeScalars.append(scalar)
            default:
                // Strip illegal XML 1.0 control characters so Word never rejects the file.
                continue
            }
        }
        return result
    }

    // MARK: - Document body XML

    private static func buildDocumentXML(
        blocks: [BetaHTMLBlock],
        hyperlinkIDFor: (String) -> String
    ) -> String {
        var xml = xmlHeader
        xml += "\n<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" "
            + "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
        xml += "<w:body>"
        if blocks.isEmpty {
            xml += "<w:p/>"
        } else {
            for block in blocks {
                xml += buildParagraphXML(block, hyperlinkIDFor: hyperlinkIDFor)
            }
        }
        xml += "<w:sectPr>"
            + "<w:pgSz w:w=\"12240\" w:h=\"15840\"/>"
            + "<w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" "
            + "w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/>"
            + "</w:sectPr>"
        xml += "</w:body></w:document>"
        return xml
    }

    private static func buildParagraphXML(
        _ block: BetaHTMLBlock,
        hyperlinkIDFor: (String) -> String
    ) -> String {
        var xml = "<w:p>"
        let pPr = buildParagraphProperties(block)
        if !pPr.isEmpty {
            xml += "<w:pPr>\(pPr)</w:pPr>"
        }
        xml += buildRunsXML(block.runs, hyperlinkIDFor: hyperlinkIDFor)
        xml += "</w:p>"
        return xml
    }

    private static func buildParagraphProperties(_ block: BetaHTMLBlock) -> String {
        var props = ""
        switch block.kind {
        case .paragraph:
            break
        case let .heading(level):
            let clamped = min(max(level, 1), 6)
            props += "<w:pStyle w:val=\"Heading\(clamped)\"/>"
        case .quote:
            props += "<w:pStyle w:val=\"Quote\"/>"
        case let .listItem(_, level, listID):
            props += "<w:pStyle w:val=\"ListParagraph\"/>"
            let ilvl = min(max(level, 0), 8)
            props += "<w:numPr><w:ilvl w:val=\"\(ilvl)\"/><w:numId w:val=\"\(listID)\"/></w:numPr>"
        case .sceneBreak:
            props += "<w:pStyle w:val=\"SceneBreak\"/>"
        case .preformatted:
            props += "<w:pStyle w:val=\"Normal\"/>"
        }
        if let alignment = block.alignment {
            props += "<w:jc w:val=\"\(alignment.ooxmlValue)\"/>"
        } else if case .sceneBreak = block.kind {
            props += "<w:jc w:val=\"center\"/>"
        }
        return props
    }

    private static func buildRunsXML(
        _ runs: [BetaInlineRun],
        hyperlinkIDFor: (String) -> String
    ) -> String {
        var xml = ""
        var index = 0
        while index < runs.count {
            if case let .text(_, style) = runs[index], let linkURL = style.linkURL {
                var group: [BetaInlineRun] = []
                while index < runs.count,
                      case let .text(_, runStyle) = runs[index],
                      runStyle.linkURL == linkURL {
                    group.append(runs[index])
                    index += 1
                }
                xml += buildHyperlinkXML(url: linkURL, runs: group, hyperlinkIDFor: hyperlinkIDFor)
                continue
            }
            xml += buildSingleRunXML(runs[index], isHyperlink: false)
            index += 1
        }
        return xml
    }

    private static func buildHyperlinkXML(
        url: String,
        runs: [BetaInlineRun],
        hyperlinkIDFor: (String) -> String
    ) -> String {
        let openTag: String
        if url.hasPrefix("#") {
            let anchor = escapeXML(String(url.dropFirst()))
            openTag = "<w:hyperlink w:anchor=\"\(anchor)\">"
        } else {
            let relID = hyperlinkIDFor(url)
            openTag = "<w:hyperlink r:id=\"\(relID)\">"
        }
        var xml = openTag
        for run in runs {
            xml += buildSingleRunXML(run, isHyperlink: true)
        }
        xml += "</w:hyperlink>"
        return xml
    }

    private static func buildSingleRunXML(_ run: BetaInlineRun, isHyperlink: Bool) -> String {
        switch run {
        case .lineBreak:
            return "<w:r><w:br/></w:r>"
        case let .text(text, style):
            let rPr = buildRunProperties(style, isHyperlink: isHyperlink)
            let escaped = escapeXML(text)
            if rPr.isEmpty {
                return "<w:r><w:t xml:space=\"preserve\">\(escaped)</w:t></w:r>"
            }
            return "<w:r><w:rPr>\(rPr)</w:rPr><w:t xml:space=\"preserve\">\(escaped)</w:t></w:r>"
        }
    }

    /// Emits `<w:rPr>` children in strict ECMA-376 `CT_RPr` schema order.
    private static func buildRunProperties(_ style: BetaRunStyle, isHyperlink: Bool) -> String {
        var props = ""
        if isHyperlink { props += "<w:rStyle w:val=\"Hyperlink\"/>" }
        if style.monospace {
            props += "<w:rFonts w:ascii=\"Courier New\" w:hAnsi=\"Courier New\" w:cs=\"Courier New\"/>"
        }
        if style.bold { props += "<w:b/>" }
        if style.italic { props += "<w:i/>" }
        if style.strikethrough { props += "<w:strike/>" }
        if style.smaller { props += "<w:sz w:val=\"18\"/><w:szCs w:val=\"18\"/>" }
        if style.underline { props += "<w:u w:val=\"single\"/>" }
        switch style.verticalAlign {
        case .baseline: break
        case .superscript: props += "<w:vertAlign w:val=\"superscript\"/>"
        case .`subscript`: props += "<w:vertAlign w:val=\"subscript\"/>"
        }
        return props
    }
}

// MARK: - Supporting OOXML parts

nonisolated extension BetaDOCXWriter {
    private static func contentTypesXML(hasLists: Bool) -> String {
        let wpPrefix = "application/vnd.openxmlformats-officedocument.wordprocessingml"
        let coreType = "application/vnd.openxmlformats-package.core-properties+xml"
        var overrides = [
            "  <Override PartName=\"/word/document.xml\" ContentType=\"\(wpPrefix).document.main+xml\"/>",
            "  <Override PartName=\"/word/styles.xml\" ContentType=\"\(wpPrefix).styles+xml\"/>",
            "  <Override PartName=\"/word/settings.xml\" ContentType=\"\(wpPrefix).settings+xml\"/>",
            "  <Override PartName=\"/docProps/core.xml\" ContentType=\"\(coreType)\"/>",
        ]
        if hasLists {
            overrides.append(
                "  <Override PartName=\"/word/numbering.xml\" ContentType=\"\(wpPrefix).numbering+xml\"/>"
            )
        }
        let relsType = "application/vnd.openxmlformats-package.relationships+xml"
        return """
        \(xmlHeader)
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="\(relsType)"/>
          <Default Extension="xml" ContentType="application/xml"/>
        \(overrides.joined(separator: "\n"))
        </Types>
        """
    }

    private static func rootRelsXML() -> String {
        let docType = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
        let coreType = "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties"
        return """
        \(xmlHeader)
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="\(docType)" Target="word/document.xml"/>
          <Relationship Id="rId2" Type="\(coreType)" Target="docProps/core.xml"/>
        </Relationships>
        """
    }

    private static func documentRelsXML(
        hasLists: Bool,
        hyperlinks: [(id: String, url: String)]
    ) -> String {
        let baseNS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        var lines = [
            "  <Relationship Id=\"rId1\" Type=\"\(baseNS)/styles\" Target=\"styles.xml\"/>",
            "  <Relationship Id=\"rId2\" Type=\"\(baseNS)/settings\" Target=\"settings.xml\"/>",
        ]
        if hasLists {
            lines.append("  <Relationship Id=\"rId3\" Type=\"\(baseNS)/numbering\" Target=\"numbering.xml\"/>")
        }
        for link in hyperlinks {
            let escapedURL = escapeXML(link.url)
            lines.append(
                "  <Relationship Id=\"\(link.id)\" Type=\"\(baseNS)/hyperlink\" "
                    + "Target=\"\(escapedURL)\" TargetMode=\"External\"/>"
            )
        }
        return """
        \(xmlHeader)
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        \(lines.joined(separator: "\n"))
        </Relationships>
        """
    }

    private static func settingsXML() -> String {
        """
        \(xmlHeader)
        <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:trackRevisions/>
          <w:defaultTabStop w:val="720"/>
        </w:settings>
        """
    }

    private static func stylesXML() -> String {
        let headingSizes: [(Int, Int)] = [(1, 36), (2, 30), (3, 26), (4, 24), (5, 22), (6, 22)]
        let headings = headingSizes.map { level, size in
            let pPr = "<w:keepNext/><w:spacing w:before=\"240\" w:after=\"120\"/>"
                + "<w:outlineLvl w:val=\"\(level - 1)\"/>"
            return """
              <w:style w:type="paragraph" w:styleId="Heading\(level)">
                <w:name w:val="heading \(level)"/>
                <w:basedOn w:val="Normal"/>
                <w:next w:val="Normal"/>
                <w:pPr>\(pPr)</w:pPr>
                <w:rPr><w:b/><w:sz w:val="\(size)"/><w:szCs w:val="\(size)"/></w:rPr>
              </w:style>
            """
        }.joined(separator: "\n")

        return """
        \(xmlHeader)
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:docDefaults>
            <w:rPrDefault>
              <w:rPr>
                <w:rFonts w:ascii="Georgia" w:hAnsi="Georgia" w:cs="Georgia"/>
                <w:sz w:val="22"/>
                <w:szCs w:val="22"/>
              </w:rPr>
            </w:rPrDefault>
            <w:pPrDefault>
              <w:pPr>
                <w:spacing w:after="160" w:line="276" w:lineRule="auto"/>
              </w:pPr>
            </w:pPrDefault>
          </w:docDefaults>
          <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
            <w:name w:val="Normal"/>
          </w:style>
        \(headings)
          <w:style w:type="paragraph" w:styleId="Quote">
            <w:name w:val="Quote"/>
            <w:basedOn w:val="Normal"/>
            <w:pPr>
              <w:pBdr><w:left w:val="single" w:sz="12" w:space="12" w:color="CCCCCC"/></w:pBdr>
              <w:ind w:left="720" w:right="720"/>
            </w:pPr>
          </w:style>
          <w:style w:type="paragraph" w:styleId="ListParagraph">
            <w:name w:val="List Paragraph"/>
            <w:basedOn w:val="Normal"/>
            <w:pPr><w:ind w:left="720"/></w:pPr>
          </w:style>
          <w:style w:type="paragraph" w:styleId="SceneBreak">
            <w:name w:val="Scene Break"/>
            <w:basedOn w:val="Normal"/>
            <w:pPr><w:spacing w:before="240" w:after="240"/><w:jc w:val="center"/></w:pPr>
          </w:style>
          <w:style w:type="character" w:styleId="Hyperlink">
            <w:name w:val="Hyperlink"/>
            <w:rPr><w:color w:val="0563C1"/><w:u w:val="single"/></w:rPr>
          </w:style>
        </w:styles>
        """
    }

    private static func numberingXML(orderedListIDs: [Int]) -> String {
        let bulletGlyphs = ["•", "◦", "▪"]
        let bulletLevels = (0 ..< 9).map { level in
            let glyph = bulletGlyphs[level % bulletGlyphs.count]
            let left = (level + 1) * 720
            return """
                <w:lvl w:ilvl="\(level)">
                  <w:start w:val="1"/>
                  <w:numFmt w:val="bullet"/>
                  <w:lvlText w:val="\(glyph)"/>
                  <w:lvlJc w:val="left"/>
                  <w:pPr><w:ind w:left="\(left)" w:hanging="360"/></w:pPr>
                </w:lvl>
            """
        }.joined(separator: "\n")

        let orderedFormats = ["decimal", "lowerLetter", "lowerRoman"]
        let orderedLevels = (0 ..< 9).map { level in
            let format = orderedFormats[level % orderedFormats.count]
            let left = (level + 1) * 720
            return """
                <w:lvl w:ilvl="\(level)">
                  <w:start w:val="1"/>
                  <w:numFmt w:val="\(format)"/>
                  <w:lvlText w:val="%\(level + 1)."/>
                  <w:lvlJc w:val="left"/>
                  <w:pPr><w:ind w:left="\(left)" w:hanging="360"/></w:pPr>
                </w:lvl>
            """
        }.joined(separator: "\n")

        var numEntries = [
            "  <w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num>",
        ]
        for listID in orderedListIDs {
            numEntries.append(
                "  <w:num w:numId=\"\(listID)\"><w:abstractNumId w:val=\"1\"/>"
                    + "<w:lvlOverride w:ilvl=\"0\"><w:startOverride w:val=\"1\"/></w:lvlOverride></w:num>"
            )
        }

        return """
        \(xmlHeader)
        <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:abstractNum w:abstractNumId="0">
        \(bulletLevels)
          </w:abstractNum>
          <w:abstractNum w:abstractNumId="1">
        \(orderedLevels)
          </w:abstractNum>
        \(numEntries.joined(separator: "\n"))
        </w:numbering>
        """
    }

    private static func corePropertiesXML(title: String, author: String, date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: date)
        let escapedTitle = escapeXML(title)
        let escapedAuthor = escapeXML(author)
        return """
        \(xmlHeader)
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" \
        xmlns:dc="http://purl.org/dc/elements/1.1/" \
        xmlns:dcterms="http://purl.org/dc/terms/" \
        xmlns:dcmitype="http://purl.org/dc/dcmitype/" \
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <dc:title>\(escapedTitle)</dc:title>
          <dc:creator>\(escapedAuthor)</dc:creator>
          <dcterms:created xsi:type="dcterms:W3CDTF">\(timestamp)</dcterms:created>
          <dcterms:modified xsi:type="dcterms:W3CDTF">\(timestamp)</dcterms:modified>
        </cp:coreProperties>
        """
    }

    private static func collectOrderedListIDs(in blocks: [BetaHTMLBlock]) -> [Int] {
        var seen: Set<Int> = []
        var ids: [Int] = []
        for block in blocks {
            if case let .listItem(ordered: true, level: _, listID: listID) = block.kind,
               seen.insert(listID).inserted {
                ids.append(listID)
            }
        }
        return ids
    }
}
