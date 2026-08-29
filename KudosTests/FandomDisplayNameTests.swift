import Testing
@testable import Kudos

/// Pins which part of an AO3 fandom tag reads as the title and which reads as the
/// disambiguation appended to keep the tag unique.
///
/// Every string here is a real tag taken from AO3's own media indexes, because the
/// interesting cases are the ones the conventions do not cover cleanly: a creator
/// where a medium would be expected, a hyphen inside the title itself, a tag that
/// is nothing but a parenthetical.
struct FandomDisplayNameTests {
    @Test func aTrailingParentheticalIsTheQualifier() {
        let split = FandomDisplayName.split("My Hero Academia (Anime & Manga)")
        #expect(split.title == "My Hero Academia")
        #expect(split.qualifier == "(Anime & Manga)")
    }

    @Test func aTrailingDashIsTheQualifier() {
        let split = FandomDisplayName.split("One Piece - All Media Types")
        #expect(split.title == "One Piece")
        #expect(split.qualifier == "- All Media Types")
    }

    @Test func aCreatorTailIsDisambiguationToo() {
        // "Miranda" is not a medium, but it is doing the same job: telling this
        // Hamilton apart from the other ones.
        let split = FandomDisplayName.split("Hamilton - Miranda")
        #expect(split.title == "Hamilton")
        #expect(split.qualifier == "- Miranda")
    }

    @Test func aHyphenInsideTheTitleIsNotASeparator() {
        // The regression this guards: " - " with spaces is the separator, so a
        // hyphenated name keeps its hyphen and only the tail is demoted.
        let split = FandomDisplayName.split("Spider-Man - All Media Types")
        #expect(split.title == "Spider-Man")
        #expect(split.qualifier == "- All Media Types")
    }

    @Test func onlyTheLastSeparatorSplits() {
        let split = FandomDisplayName.split("Newsies!: the Musical - Menken/Feldman/Fierstein")
        #expect(split.title == "Newsies!: the Musical")
        #expect(split.qualifier == "- Menken/Feldman/Fierstein")
    }

    @Test func aPlainNameHasNoQualifier() {
        for name in ["Marvel Cinematic Universe", "Sherlock Holmes & Related Fandoms", "Haikyuu!!"] {
            let split = FandomDisplayName.split(name)
            #expect(split.title == name, "\(name) should stay whole")
            #expect(split.qualifier.isEmpty)
        }
    }

    @Test func aNameThatIsOnlyAParentheticalStaysWhole() {
        // No title to lead with, so demoting the whole thing would render a row
        // with nothing in primary.
        let split = FandomDisplayName.split("(Anime)")
        #expect(split.title == "(Anime)")
        #expect(split.qualifier.isEmpty)
    }

    @Test func theTitleIsNeverEmptied() {
        // Whatever the shape, a row always has something to lead with.
        for name in ["Zone (Manga)", "- All Media Types", "()", "DCU (Comics)", "  Marvel  "] {
            #expect(!FandomDisplayName.split(name).title.isEmpty, "\(name) produced an empty title")
        }
    }
}
