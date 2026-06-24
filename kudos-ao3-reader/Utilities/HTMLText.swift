import Foundation

extension String {
    /// Converts a fragment of HTML (as found in EPUB `<dc:description>` summaries)
    /// to readable plain text: `<br>` and block-closing tags become line breaks,
    /// all other tags are removed, and character entities are decoded. Used so
    /// work summaries don't show raw "<p>…</p>" markup.
    func strippingHTML() -> String {
        guard contains("<") || contains("&") else { return self }
        var text = self

        // Turn line breaks and block boundaries into newlines.
        for tag in ["<br>", "<br/>", "<br />", "</p>", "</div>", "</li>", "</h1>",
                    "</h2>", "</h3>", "</h4>", "</h5>", "</h6>"] {
            text = text.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }
        // Drop every remaining tag, then decode entities like &amp; / &#39;.
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.decodingHTMLEntities()
        // Collapse runs of blank lines and trim surrounding whitespace.
        text = text.replacingOccurrences(of: "[ \\t]+\n", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
