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
        //
        // Nearly all of those 62 were the "Political RPF - <region>" family, and
        // they now keep their RPF on purpose — it is part of the fandom's own name
        // (see FandomRPFUmbrellas). Across the whole 142,933-tag index this is the
        // only tag left where a later pass still has to expose an RPF that should
        // come off: "- Fandom" peels first, uncovering an RPF on a real fandom.
        #expect(FandomDisplayName.split("Roblox RPF - Fandom").title == "Roblox")
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
        // 49 names glue it on with no separating space.
        //
        // This used to assert hetamyuRPF, 英国演员RPF and 真人rpf. Those keep their
        // RPF now: "英国演员" is "British actor" and "真人" is "real person" —
        // categories, not works, so the RPF is the name (see FandomRPFUmbrellas).
        // These still strip, because a head carrying a bracket is a real work.
        #expect(FandomDisplayName.split("The Notebook(2004)RPF").title == "The Notebook")
        #expect(FandomDisplayName.split("超级小品秀（电视）RPF").title == "超级小品秀")
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

    // MARK: - The curated exceptions

    @Test func aNameOnTheKeepWholeListKeepsItsDashTail() {
        // The whole point of the list: these read as "Title - Suffix" and are not.
        for name in ["InuYasha - A Feudal Fairy Tale", "Dragon Age: Origins - Awakening"] {
            let split = FandomDisplayName.split(name)
            #expect(split.title == name, "\(name) should stay whole")
            #expect(split.qualifier.isEmpty)
        }
    }

    @Test func anExceptionStillLosesASuffixOfAnotherKind() {
        // Grok's counterexample in review. The dash tail belongs to the title,
        // but "(Germany TV)" is an ordinary qualifier — an early return out of
        // `split`, which is what the first version did, left both bold.
        for (name, title, qualifier) in [
            ("Ich bin ein Star - Holt mich hier raus! (Germany TV)",
             "Ich bin ein Star - Holt mich hier raus!", "(Germany TV)"),
            ("Cat Game - The Cat Collector! (Mino Games Video Game)",
             "Cat Game - The Cat Collector!", "(Mino Games Video Game)"),
            ("Daniel - The Wizard (Movie 2004)", "Daniel - The Wizard", "(Movie 2004)"),
        ] {
            let split = FandomDisplayName.split(name)
            #expect(split.title == title, "\(name)")
            #expect(split.qualifier == qualifier, "\(name)")
        }
    }

    @Test func theExceptionListIsKeyedOnWhatSplitActuallyReceives() {
        // `split` is handed the last "|" segment, not the raw multilingual tag.
        // 11 of the first 28 exceptions differ between the two, so a list keyed
        // on raw tags would silently no-op for those while looking correct.
        #expect(FandomDisplayExceptions.keepWhole.contains("Coil - A Circle of Children"))
        #expect(!FandomDisplayExceptions.keepWhole.contains("Dennou Coil | Coil - A Circle of Children"))
    }

    @Test func anUnlistedNameStillGetsTheOrdinaryRules() {
        // Fail-open: an incomplete list degrades to today's behaviour, never worse.
        let split = FandomDisplayName.split("Harry Potter - J. K. Rowling")
        #expect(split.title == "Harry Potter")
        #expect(split.qualifier == "- J. K. Rowling")
    }

    // MARK: - RPF umbrellas

    @Test func anRPFUmbrellaKeepsItsRPF() {
        // "Sports RPF" is the fandom's own name. Stripping the RPF left a bold
        // "Sports", which names nothing anyone writes for. 1,477 tags, 1.46M works.
        for name in ["Sports RPF", "Video Blogging RPF", "Actor RPF", "Music RPF",
                     "Political RPF", "Historical RPF", "Formula 1 RPF", "Motorsport RPF",
                     // Were asserted the other way before the umbrella set existed.
                     "Canadian Musician RPF", "英国演员RPF", "真人rpf"] {
            let split = FandomDisplayName.split(name)
            #expect(split.title == name, "\(name) is an umbrella; its RPF is part of the name")
            #expect(split.qualifier.isEmpty)
        }
    }

    @Test func anRPFSuffixOnARealFandomStillDemotes() {
        // The other half: these heads are fandoms in their own right, so the RPF
        // really is a qualifier and must keep behaving as one.
        let potter = FandomDisplayName.split("Harry Potter RPF")
        #expect(potter.title == "Harry Potter")
        #expect(potter.qualifier == "RPF")

        let supernatural = FandomDisplayName.split("Supernatural (TV 2005) RPF")
        #expect(supernatural.title == "Supernatural")
        #expect(supernatural.qualifier == "(TV 2005) RPF")
    }

    @Test func aRealWorkStripsItsRPFEvenWithNoNonRPFWorks() {
        // The work-count proxy asks "does this head have works of its own", which
        // is not "is this head a real title". Drag queens are real people, so every
        // RuPaul's Drag Race work is RPF and the head scores zero — but it is
        // plainly a show, and bolding the whole tag would be wrong. A head still
        // carrying its bracket is a work, never a category, so it strips.
        for (name, title, qualifier) in [
            ("RuPaul's Drag Race (US) RPF", "RuPaul's Drag Race", "(US) RPF"),
            ("Super Sketch Show (TV) RPF", "Super Sketch Show", "(TV) RPF"),
            ("8 Mile (2002) RPF", "8 Mile", "(2002) RPF"),
        ] {
            let split = FandomDisplayName.split(name)
            #expect(split.title == title, "\(name) should lead with \(title)")
            #expect(split.qualifier == qualifier)
        }
    }

    @Test func aRegionalPoliticalTagKeepsItsRPF() {
        // The dash tail comes off first and exposes "Political RPF", which must
        // then survive the RPF rule rather than decaying to a bare "Political".
        let split = FandomDisplayName.split("Political RPF - US 21st c.")
        #expect(split.title == "Political RPF")
        #expect(split.qualifier == "- US 21st c.")
    }

    // MARK: - Structured qualifiers

    @Test func qualifiersAreKeptSeparateAndKinded() {
        // 7,222 tags carry two or more. They stay a list so a layout can place the
        // medium and the creator in different parts of a card.
        let split = FandomDisplayName.split("IT (Movies - Muschietti)")
        #expect(split.title == "IT")
        #expect(split.parts.count == 1)
        #expect(split.parts.first?.kind == .parenthetical)
        #expect(split.parts.first?.text == "(Movies - Muschietti)")

        let potter = FandomDisplayName.split("Harry Potter - J. K. Rowling")
        #expect(potter.parts.map(\.kind) == [.creator])
        #expect(potter.parts.first?.text == "- J. K. Rowling")
    }

    @Test func joinedQualifierMatchesTheParts() {
        // The rendered string is derived from the parts, in original order.
        let split = FandomDisplayName.split("Supernatural (TV 2005) RPF")
        #expect(split.parts.map(\.kind) == [.parenthetical, .rpf])
        #expect(split.qualifier == split.parts.map(\.text).joined(separator: " "))
    }

    @Test func partsKeepTheOrderTheyHadInTheName() {
        // The rules peel from the end, so without the insert-at-front the list
        // would come out reversed and a layout reading parts left-to-right would
        // render the name inside out.
        for name in ["Supernatural (TV 2005) RPF",
                     "Political RPF - US 21st c.",
                     "Good Omens (TV) RPF",
                     "Bridgerton (TV) & Related Fandoms"] {
            let split = FandomDisplayName.split(name)
            var cursor = name.startIndex
            for part in split.parts {
                let needle = part.text.hasPrefix("- ") ? String(part.text.dropFirst(2)) : part.text
                guard let found = name.range(of: needle, range: cursor ..< name.endIndex) else {
                    Issue.record("\(needle) missing from \(name) after \(cursor)")
                    continue
                }
                cursor = found.upperBound
            }
        }
    }

    @Test func theOriginalNameIsKeptBecauseSplittingIsLossy() {
        // 1,519 tags (1.6%) do not survive title + qualifier: tidied() eats the
        // delimiter it cut against. Anything needing the real tag reads `original`.
        for name in ["Digimon Adventure: (Anime 2020)",
                     "The Hundred Line -Last Defense Academy- (Video Game)",
                     "Vampire: The Masquerade – Bloodlines (Video Game)"] {
            let split = FandomDisplayName.split(name)
            #expect(split.original == name)
            let rebuilt = split.qualifier.isEmpty ? split.title : split.title + " " + split.qualifier
            #expect(rebuilt != name, "\(name) is a known lossy case; if it now round-trips, tighten this test")
        }
    }

    @Test func protectingAnRPFDoesNotProtectTheWholeName() {
        // Codex flagged that the protection is not terminal: takeRPF declines for a
        // protected head, but a later rule can still peel past it. That is real —
        // 18 tags, 170 works — and it is what should happen. "Stage Play Touken
        // Ranbu" is a work and "Suemitsu Actor RPF" is telling you which staging.
        // Making protection terminal would send both of these bold in full, and the
        // second already has a test above pinning the current result.
        let staged = FandomDisplayName.split("Stage Play Touken Ranbu - Suemitsu Actor RPF")
        #expect(staged.title == "Stage Play Touken Ranbu")
        #expect(staged.qualifier == "- Suemitsu Actor RPF")

        #expect(FandomDisplayName.split("classmates - RPF").title == "classmates")
    }
}
