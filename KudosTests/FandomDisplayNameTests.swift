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

    // MARK: - Compound suffixes, the shape that needed the second pass

    @Test func aCreatorAndAMediumAreBothDemoted() {
        // 5,560 fandoms in AO3's index carry both at once. Peeling only the
        // parenthetical used to leave "Astronomy - Conan Gray" as the title.
        let split = FandomDisplayName.split("Astronomy - Conan Gray (Song)")
        #expect(split.title == "Astronomy")
        #expect(split.qualifier == "- Conan Gray (Song)")
    }

    @Test func aTitleKeepsItsOwnParentheticalWhileTheSuffixGoes() {
        let split = FandomDisplayName.split("À Tout le Monde (Set Me Free) - Megadeth (Music Video)")
        #expect(split.title == "À Tout le Monde (Set Me Free)")
        #expect(split.qualifier == "- Megadeth (Music Video)")
    }

    @Test func onlyTheTrailingParentheticalIsTheQualifier() {
        // Two parentheticals, no dash: the first belongs to the title.
        let split = FandomDisplayName.split("Ellie and Abbie (and Ellie's Dead Aunt) (2020)")
        #expect(split.title == "Ellie and Abbie (and Ellie's Dead Aunt)")
        #expect(split.qualifier == "(2020)")
    }

    @Test func anAuthorHandleIsDemotedLikeAnyOtherCreator() {
        // Lowercase tails are author handles, not title continuations — the
        // reason the lowercase-tail guard was measured and rejected.
        let split = FandomDisplayName.split("Stars of Chaos: Sha Po Lang - priest")
        #expect(split.title == "Stars of Chaos: Sha Po Lang")
        #expect(split.qualifier == "- priest")
    }

    @Test func theLiteralWordFandomIsASuffixToo() {
        // 17,424 names end this way — the single most common dash tail.
        let split = FandomDisplayName.split("Taylor Swift - Fandom")
        #expect(split.title == "Taylor Swift")
        #expect(split.qualifier == "- Fandom")
    }

    @Test func aShortTitleIsStillATitle() {
        // "O" and "13" really are the whole names; the tail is the company or
        // the writing team. A minimum-length guard would have broken these.
        for (name, title) in [("O - Cirque du Soleil", "O"), ("13 - Brown/Elish/Horn", "13")] {
            #expect(FandomDisplayName.split(name).title == title)
        }
    }

    // MARK: - Conventions found by scanning AO3's full index

    @Test func rpfIsASuffixEvenWithNoSeparator() {
        let split = FandomDisplayName.split("One Direction RPF")
        #expect(split.title == "One Direction")
        #expect(split.qualifier == "RPF")
    }

    @Test func rpfSitsOutsideTheParenthetical() {
        // The ordering trap: RPF has to come off before the bracket is looked
        // for, or the name no longer ends in ")" and the medium stays bold.
        for (name, title, qualifier) in [
            ("Yanni (Musician) RPF", "Yanni", "(Musician) RPF"),
            ("Only Lovers Left Alive (2013) RPF", "Only Lovers Left Alive", "(2013) RPF"),
        ] {
            let split = FandomDisplayName.split(name)
            #expect(split.title == title)
            #expect(split.qualifier == qualifier)
        }
    }

    @Test func fullwidthParenthesesAreTheSameConvention() {
        // 699 names, mostly CJK media words and years.
        let split = FandomDisplayName.split("博士斯通（漫画）")
        #expect(split.title == "博士斯通")
        #expect(split.qualifier == "（漫画）")
    }

    @Test func cjkBookBracketsWrapTheTitleAndAreLeftAlone() {
        // The trap this guards: 《》 looks like a bracket suffix but wraps the
        // whole name. Stripping it would leave the row with nothing to lead with.
        for name in ["《病案本》", "《将进酒》", "《可怜的社畜》"] {
            let split = FandomDisplayName.split(name)
            #expect(split.title == name)
            #expect(split.qualifier.isEmpty)
        }
    }

    @Test func enAndEmDashesSeparateToo() {
        #expect(FandomDisplayName.split("Some Show – All Media Types").qualifier == "- All Media Types")
        #expect(FandomDisplayName.split("Some Show — All Media Types").qualifier == "- All Media Types")
    }
}
