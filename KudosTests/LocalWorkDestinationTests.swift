import Testing
@testable import Kudos

struct LocalWorkDestinationTests {
    @Test func readAloudDestinationIsDistinctFromPlainReader() {
        let work = SavedWork(title: "T", author: "A")
        #expect(LocalWorkDestination.readerReadAloud(work) != .reader(work))
        #expect(LocalWorkDestination.readerReadAloud(work) == .readerReadAloud(work))
    }
}
