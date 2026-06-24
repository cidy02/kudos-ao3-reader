import Foundation

/// Local name of an XML element, ignoring any namespace prefix.
func localName(_ name: String) -> String {
    name.contains(":") ? String(name.split(separator: ":").last!) : name
}

extension String {
    /// Resolves HTML/XML character references (named and numeric) one level.
    /// Used to undo double-encoding left behind after XML parsing.
    func decodingHTMLEntities() -> String {
        guard contains("&") else { return self }
        let named: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&apos;": "'", "&#39;": "'", "&nbsp;": "\u{00a0}",
        ]
        var result = ""
        var rest = Substring(self)
        while let amp = rest.firstIndex(of: "&") {
            result += rest[rest.startIndex..<amp]
            let tail = rest[amp...]
            guard let semi = tail.firstIndex(of: ";"),
                  tail.distance(from: tail.startIndex, to: semi) <= 10 else {
                result.append("&")
                rest = rest[tail.index(after: tail.startIndex)...]
                continue
            }
            let entity = String(tail[tail.startIndex...semi])
            if let replacement = named[entity] {
                result += replacement
            } else if entity.hasPrefix("&#x") || entity.hasPrefix("&#X"),
                      let code = UInt32(entity.dropFirst(3).dropLast(), radix: 16),
                      let scalar = Unicode.Scalar(code) {
                result.unicodeScalars.append(scalar)
            } else if entity.hasPrefix("&#"),
                      let code = UInt32(entity.dropFirst(2).dropLast()),
                      let scalar = Unicode.Scalar(code) {
                result.unicodeScalars.append(scalar)
            } else {
                result += entity   // unknown entity: leave as-is
            }
            rest = rest[tail.index(after: semi)...]
        }
        result += rest
        return result
    }
}
