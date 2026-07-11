import Foundation

/// One pseud AO3 rendered as an authorized choice in a write form. The numeric
/// id is deliberately scraped from that exact form instead of inferred from a
/// profile URL or pseud name.
nonisolated struct AO3PostingPseudOption: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let isDefault: Bool
}
