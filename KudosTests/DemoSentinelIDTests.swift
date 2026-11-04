import SwiftData
import Testing
@testable import Kudos

/// The demo seed writes into the same store a normal debug launch opens, and two
/// of its works carry a fabricated AO3 id. Left behind, Library's metadata
/// backfill refreshes them against AO3 and a 404 marks them unavailable.
@MainActor
struct DemoSentinelIDTests {
    private func store() throws -> ModelContext {
        let container = try ModelContainer(
            for: SavedWork.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func clearsFabricatedIDsWhenDemoIsOff() throws {
        UserDefaults.standard.set(false, forKey: "KudosDemoLibrary")
        let context = try store()
        let seeded = SavedWork(title: "Tea in the Jasmine Dragon", author: "uncle_iroh_fan", summary: "")
        seeded.ao3WorkID = 999_000_001
        let real = SavedWork(title: "A real saved work", author: "someone", summary: "")
        real.ao3WorkID = 61_234_567
        context.insert(seeded)
        context.insert(real)

        DemoLibrary.clearSentinelIDs(in: context)

        #expect(seeded.ao3WorkID == nil)
        #expect(real.ao3WorkID == 61_234_567, "a genuine AO3 id must survive the scrub")
    }

    @Test func keepsFabricatedIDsWhileDemoIsOn() throws {
        UserDefaults.standard.set(true, forKey: "KudosDemoLibrary")
        defer { UserDefaults.standard.set(false, forKey: "KudosDemoLibrary") }
        let context = try store()
        let seeded = SavedWork(title: "What the River Keeps", author: "undertow", summary: "")
        seeded.ao3WorkID = 999_000_002
        context.insert(seeded)

        DemoLibrary.clearSentinelIDs(in: context)

        // The end-of-work card needs the id to draw Give Kudos for the board-34 shot.
        #expect(seeded.ao3WorkID == 999_000_002)
    }
}
