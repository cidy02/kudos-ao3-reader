import Foundation

extension Int {
    /// A count on a chip, card or stat strip: 999, 1K, 1.5K, 1.2M. Exact
    /// figures stay in prose, pagination and accessibility values.
    var compactCount: String {
        formatted(.number.notation(.compactName))
    }
}
