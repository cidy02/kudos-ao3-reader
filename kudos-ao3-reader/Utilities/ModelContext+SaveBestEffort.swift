import Foundation
import OSLog
import SwiftData

extension ModelContext {
    /// Saves, logging (not throwing) on failure — the app's convention for
    /// derived/background state changes where a save failure shouldn't block
    /// the user's action or crash the flow that triggered it.
    @MainActor
    func saveBestEffort(reason: StaticString) {
        do {
            try save()
        } catch {
            Log.library.error(
                "\(String(describing: reason), privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
