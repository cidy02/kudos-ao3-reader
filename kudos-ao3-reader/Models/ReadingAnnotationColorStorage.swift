import Foundation

/// How a highlight's colour is stored in `ReadingAnnotation.colorRaw` once the
/// reader can pick any colour (T-471): a preset is its `ReadingAnnotationColor`
/// raw value as ever ("yellow"), and a colour from the well is its `#RRGGBB`
/// hex — the same string the queue and collection colour wells store
/// (`Color.hexString`). One column, so the backup format, the sync merge and the
/// schema are untouched; a build that predates this reads an unknown value as the
/// default yellow, exactly as it already does for any unrecognised raw value.
nonisolated enum ReadingAnnotationColorStorage {
    /// The uppercase `#RRGGBB` for a custom colour, or `nil` if `raw` is a
    /// preset's name or anything else that is not a six-digit hex colour.
    static func customHex(fromRaw raw: String) -> String? {
        var digits = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard digits.hasPrefix("#") else { return nil }
        digits.removeFirst()
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + digits.uppercased()
    }

    /// What to store for `raw`: a preset's name, or a custom colour normalised
    /// to uppercase `#RRGGBB`; anything unrecognised falls back to yellow.
    static func normalizedRaw(_ raw: String) -> String {
        if ReadingAnnotationColor(rawValue: raw) != nil { return raw }
        return customHex(fromRaw: raw) ?? ReadingAnnotationColor.yellow.rawValue
    }
}

extension ReadingAnnotation {
    /// The `#RRGGBB` of a colour picked in the well, `nil` for a preset.
    var customColorHex: String? {
        ReadingAnnotationColorStorage.customHex(fromRaw: colorRaw)
    }
}
