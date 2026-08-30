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
        // "Sherlock Holmes & Related Fandoms" used to sit in this list. It was
        // never a plain name — it is an umbrella-grouped tag, and asserting it
        // had no qualifier was asserting the bug.
        for name in ["Marvel Cinematic Universe", "Doctor Who", "Haikyuu!!"] {
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

    // MARK: - Defects Codex found reviewing this against the full index

    @Test func peelingASuffixLeavesNoDashBehind() {
        // 15 rows rendered a title ending in " -": the outer suffix came off but
        // the separator that had joined it did not.
        #expect(FandomDisplayName.split("classmates - RPF").title == "classmates")
        #expect(FandomDisplayName.split("Deadpool & Wolverine - (Movie 2024)").title == "Deadpool & Wolverine")
    }

    @Test func aSuffixExposedByAnotherIsAlsoPeeled() {
        // The single-pass version was not a fixed point: stripping the dash tail
        // uncovered an RPF that was never looked at again, leaving 62 titles
        // still ending in "RPF".
        #expect(FandomDisplayName.split("Political RPF - US 21st c.").title == "Political")
        #expect(FandomDisplayName.split("Canadian Musician RPF (C6D)").title == "Canadian Musician")
    }

    @Test func rpfIsMatchedWhateverItsCase() {
        #expect(FandomDisplayName.split("Kamen Rider Blade Rpf").title == "Kamen Rider Blade")
    }

    @Test func allMediaTypesIsFoundWithoutADashToo() {
        // "Digimon: All Media Types" used to keep the whole thing bold, then
        // once fixed left a trailing colon.
        #expect(FandomDisplayName.split("Digimon: All Media Types").title == "Digimon")
        #expect(FandomDisplayName.split("Hulk-All Media Types").title == "Hulk")
    }

    @Test func theUnicodeHyphenSeparatesToo() {
        // U+2010, visually identical to a hyphen-minus.
        let split = FandomDisplayName.split("Dreaming of Sunshine \u{2010} Silver Queen")
        #expect(split.title == "Dreaming of Sunshine")
        #expect(split.qualifier == "- Silver Queen")
    }

    @Test func aJapaneseSubtitleKeepsItsClosingDash() {
        // 42 names use the "-Subtitle-" convention. Nothing is peeled off them,
        // so the debris trim must never see them.
        for name in ["Lamento -BEYOND THE VOID-", "Bad Wife -Mizuho-", "CAGE-CLOSE-"] {
            #expect(FandomDisplayName.split(name).title == name)
        }
    }

    @Test func blankInputSurvives() {
        #expect(!FandomDisplayName.split("   ").title.isEmpty)
    }

    // MARK: - Umbrella grouping (A)

    @Test func relatedFandomsIsASuffix() {
        let split = FandomDisplayName.split("Sherlock Holmes & Related Fandoms")
        #expect(split.title == "Sherlock Holmes")
        #expect(split.qualifier == "& Related Fandoms")
    }

    @Test func onlyTheLastRelatedFandomsSplits() {
        // The series ampersand belongs to the title.
        #expect(FandomDisplayName.split("Spirou & Fantasio & Related Fandoms").title == "Spirou & Fantasio")
    }

    @Test func relatedFandomsNeedsItsSeparator() {
        // Both are titles, not grouped tags: no " & " or " and " before the phrase.
        for name in ["Eason-Related Fandoms", "Chinese Related Fandoms"] {
            let split = FandomDisplayName.split(name)
            #expect(split.title == name, "\(name) should stay whole")
            #expect(split.qualifier.isEmpty)
        }
    }

    @Test func relatedFandomsUncoversWhatItWraps() {
        // It sits outside the parenthetical, so peeling it must expose the (TV).
        let split = FandomDisplayName.split("Bridgerton (TV) & Related Fandoms")
        #expect(split.title == "Bridgerton")
        #expect(split.qualifier == "(TV) & Related Fandoms")
    }

    @Test func theLowercaseSpellingCountsToo() {
        #expect(FandomDisplayName.split("Arsène Lupin & related fandoms").title == "Arsène Lupin")
        #expect(FandomDisplayName.split("Red Hood and Related Fandoms").title == "Red Hood")
    }

    // MARK: - Glued RPF (C)

    @Test func rpfNeedsNoSpaceAtAll() {
        // 47 names glue it on. Across all 144,866 the only Latin-letter-preceded
        // match is hetamyuRPF, which genuinely is RPF.
        #expect(FandomDisplayName.split("hetamyuRPF").title == "hetamyu")
        #expect(FandomDisplayName.split("英国演员RPF").title == "英国演员")
        #expect(FandomDisplayName.split("真人rpf").title == "真人")
    }

    @Test func aBareRPFIsItsOwnTitle() {
        // Nothing to lead with otherwise.
        #expect(FandomDisplayName.split("RPF").title == "RPF")
    }

    @Test func gluedRPFStacksWithABracket() {
        let split = FandomDisplayName.split("The Notebook(2004)RPF")
        #expect(split.title == "The Notebook")
        #expect(split.qualifier == "(2004) RPF")
    }

    // MARK: - Localized media umbrella (D)

    @Test func theMediaUmbrellaIsMatchedInEverySpellingWeHaveSeen() {
        for (name, title) in [
            ("刺客信条-所有媒体类型", "刺客信条"),
            ("蝙蝠俠-所有媒體型別", "蝙蝠俠"),
            ("蝙蝠俠 - 所有媒體類型", "蝙蝠俠"),
            ("Capitão América - Todos os Tipos de Mídia", "Capitão América"),
            ("Capitán América - Todos los tipos de medios", "Capitán América"),
        ] {
            #expect(FandomDisplayName.split(name).title == title, "\(name)")
        }
    }

    // MARK: - Mixed-width brackets (E)

    @Test func aBracketPairMayMixWidths() {
        // 16 names open one width and close the other.
        #expect(FandomDisplayName.split("BLEACH(Anime&Manga）").title == "BLEACH")
        #expect(FandomDisplayName.split("南风知我意(TV）").title == "南风知我意")
        #expect(FandomDisplayName.split("第三日（原创作品)").title == "第三日")
    }

    @Test func aCloserWithNoOpenerIsTitle() {
        // The band's name really is three closing parens.
        #expect(FandomDisplayName.split("Sunn O)))").title == "Sunn O)))")
        #expect(FandomDisplayName.split("1967)").title == "1967)")
    }

    @Test func aSmileyIsNotAParenthetical() {
        #expect(FandomDisplayName.split("MYSTERIOUS MURDER DIY :)").title == "MYSTERIOUS MURDER DIY :)")
    }

    // MARK: - Glued Fandom (B)

    @Test func fandomGluedByADashIsASuffix() {
        for (name, title) in [
            ("The Expanse-Fandom", "The Expanse"),
            ("Creepypasta-fandom", "Creepypasta"),
            ("杀死你的旅程—Fandom", "杀死你的旅程"),
            ("Jinkx Monsoon- Fandom", "Jinkx Monsoon"),
            ("Fanfic -Fandom", "Fanfic"),
        ] {
            #expect(FandomDisplayName.split(name).title == title, "\(name)")
        }
    }

    @Test func fandomWithoutADashIsPartOfTheTitle() {
        // The narrowness is the point: no dash, no split.
        for name in ["Pizza Fandom", "Celebrity Fiction"] {
            #expect(FandomDisplayName.split(name).title == name, "\(name) should stay whole")
        }
    }

    // MARK: - Identity

    @Test func siblingsShareADisplayTitleButNotAnIdentity() {
        // 534 stems exist both bare and parenthesized. The parsed title is a
        // display string and must never be treated as the fandom's identity —
        // these two are different fandoms that render the same title.
        let older = FandomDisplayName.split("Doctor Who (1963)")
        let newer = FandomDisplayName.split("Doctor Who (2005)")
        #expect(older.title == newer.title)
        #expect(older.qualifier != newer.qualifier)
    }

    // MARK: - Adversarial cases contributed by Gemini's review

    @Test func aTitleWithItsOwnParentheticalKeepsItThroughADashTail() {
        let split = FandomDisplayName.split("The (Unfinished) Story - Author (Novel)")
        #expect(split.title == "The (Unfinished) Story")
        #expect(split.qualifier == "- Author (Novel)")
    }

    @Test func stackedMixedWidthBracketsPeelOnlyTheOuter() {
        let split = FandomDisplayName.split("My Show (Season 1)（2024)")
        #expect(split.title == "My Show (Season 1)")
        #expect(split.qualifier == "（2024)")
    }

    @Test func aBookBracketTitleKeepsItsWrapperButLosesTheQualifier() {
        let split = FandomDisplayName.split("《病案本》 (Novel)")
        #expect(split.title == "《病案本》")
        #expect(split.qualifier == "(Novel)")
    }

    @Test func anUnopenedCloserSurvivesAlongsideARealQualifier() {
        let split = FandomDisplayName.split("Sunn O))) (Band)")
        #expect(split.title == "Sunn O)))")
        #expect(split.qualifier == "(Band)")
    }

    @Test func relatedFandomsWithoutItsConjunctionStaysWhole() {
        let split = FandomDisplayName.split("Sherlock Holmes Related Fandoms")
        #expect(split.title == "Sherlock Holmes Related Fandoms")
        #expect(split.qualifier.isEmpty)
    }

    @Test func aNameThatIsNothingButASuffixKeepsItself() {
        // No stem to lead with, so every rule must decline.
        for bare in ["  RPF  ", "  - Fandom  ", "  - All Media Types  ", "  & Related Fandoms  "] {
            let split = FandomDisplayName.split(bare)
            #expect(split.title == bare.trimmingCharacters(in: .whitespaces), "\(bare)")
            #expect(split.qualifier.isEmpty, "\(bare)")
        }
    }

    @Test func aTitleEndingInItsOwnParentheticalKeepsIt() {
        // Required by the plan's definition of done and missing until Codex's
        // review caught it: the band is "f(x)", so the one-shot bracket rule has
        // to be spent on "(Band)" and leave "(x)" alone.
        let split = FandomDisplayName.split("f(x) (Band)")
        #expect(split.title == "f(x)")
        #expect(split.qualifier == "(Band)")
    }
}
