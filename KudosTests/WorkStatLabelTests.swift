import Testing
@testable import Kudos

struct WorkStatLabelTests {
    @Test func ratingNameShortensKnownAO3Ratings() {
        #expect(WorkStat.ratingName("General Audiences") == "General")
        #expect(WorkStat.ratingName("Teen And Up Audiences") == "Teen")
        #expect(WorkStat.ratingName("Mature") == "Mature")
        #expect(WorkStat.ratingName("Explicit") == "Explicit")
        #expect(WorkStat.ratingName("Not Rated") == "Not Rated")
        #expect(WorkStat.ratingName("") == nil)
        #expect(WorkStat.ratingName("Some Custom Thing") == "Some Custom Thing")
    }

    @Test func displayDateParsesTheWorkDetailPageISOFormat() {
        #expect(WorkStat.displayDate("2025-11-01") == "11/01/2025")
    }

    @Test func displayDateParsesTheSearchBlurbFormat() {
        #expect(WorkStat.displayDate("01 Nov 2025") == "11/01/2025")
    }

    @Test func displayDateFallsBackToTheRawStringWhenUnrecognized() {
        #expect(WorkStat.displayDate("not a date") == "not a date")
    }
}
