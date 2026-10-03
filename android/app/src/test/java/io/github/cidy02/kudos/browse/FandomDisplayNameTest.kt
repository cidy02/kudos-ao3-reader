package io.github.cidy02.kudos.browse

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Port of iOS `FandomDisplayNameTests.swift` and `CappedFlowLayoutTests.swift`.
 * Pins which part of an AO3 fandom tag reads as the title and which reads as disambiguation.
 */
class FandomDisplayNameTest {

    @Test
    fun aTrailingParentheticalIsTheQualifier() {
        val split = FandomDisplayName.split("My Hero Academia (Anime & Manga)")
        assertEquals("My Hero Academia", split.title)
        assertEquals("(Anime & Manga)", split.qualifier)
    }

    @Test
    fun aTrailingDashIsTheQualifier() {
        val split = FandomDisplayName.split("One Piece - All Media Types")
        assertEquals("One Piece", split.title)
        assertEquals("- All Media Types", split.qualifier)
    }

    @Test
    fun aCreatorTailIsDisambiguationToo() {
        val split = FandomDisplayName.split("Hamilton - Miranda")
        assertEquals("Hamilton", split.title)
        assertEquals("- Miranda", split.qualifier)
    }

    @Test
    fun aHyphenInsideTheTitleIsNotASeparator() {
        val split = FandomDisplayName.split("Spider-Man - All Media Types")
        assertEquals("Spider-Man", split.title)
        assertEquals("- All Media Types", split.qualifier)
    }

    @Test
    fun onlyTheLastSeparatorSplits() {
        val split = FandomDisplayName.split("Newsies!: the Musical - Menken/Feldman/Fierstein")
        assertEquals("Newsies!: the Musical", split.title)
        assertEquals("- Menken/Feldman/Fierstein", split.qualifier)
    }

    @Test
    fun aPlainNameHasNoQualifier() {
        for (name in listOf("Marvel Cinematic Universe", "Doctor Who", "Haikyuu!!")) {
            val split = FandomDisplayName.split(name)
            assertEquals("$name should stay whole", name, split.title)
            assertTrue(split.qualifier.isEmpty())
        }
    }

    @Test
    fun aNameThatIsOnlyAParentheticalStaysWhole() {
        val split = FandomDisplayName.split("(Anime)")
        assertEquals("(Anime)", split.title)
        assertTrue(split.qualifier.isEmpty())
    }

    @Test
    fun theTitleIsNeverEmptied() {
        for (name in listOf("Zone (Manga)", "- All Media Types", "()", "DCU (Comics)", "  Marvel  ")) {
            assertTrue("$name produced an empty title", FandomDisplayName.split(name).title.isNotEmpty())
        }
    }

    @Test
    fun aCreatorAndAMediumAreBothDemoted() {
        val split = FandomDisplayName.split("Astronomy - Conan Gray (Song)")
        assertEquals("Astronomy", split.title)
        assertEquals("- Conan Gray (Song)", split.qualifier)
    }

    @Test
    fun aTitleKeepsItsOwnParentheticalWhileTheSuffixGoes() {
        val split = FandomDisplayName.split("À Tout le Monde (Set Me Free) - Megadeth (Music Video)")
        assertEquals("À Tout le Monde (Set Me Free)", split.title)
        assertEquals("- Megadeth (Music Video)", split.qualifier)
    }

    @Test
    fun onlyTheTrailingParentheticalIsTheQualifier() {
        val split = FandomDisplayName.split("Ellie and Abbie (and Ellie's Dead Aunt) (2020)")
        assertEquals("Ellie and Abbie (and Ellie's Dead Aunt)", split.title)
        assertEquals("(2020)", split.qualifier)
    }

    @Test
    fun anAuthorHandleIsDemotedLikeAnyOtherCreator() {
        val split = FandomDisplayName.split("Stars of Chaos: Sha Po Lang - priest")
        assertEquals("Stars of Chaos: Sha Po Lang", split.title)
        assertEquals("- priest", split.qualifier)
    }

    @Test
    fun theLiteralWordFandomIsASuffixToo() {
        val split = FandomDisplayName.split("Taylor Swift - Fandom")
        assertEquals("Taylor Swift", split.title)
        assertEquals("- Fandom", split.qualifier)
    }

    @Test
    fun aShortTitleIsStillATitle() {
        val cases = listOf(
            "O - Cirque du Soleil" to "O",
            "13 - Brown/Elish/Horn" to "13"
        )
        for ((name, title) in cases) {
            assertEquals(title, FandomDisplayName.split(name).title)
        }
    }

    @Test
    fun rpfIsASuffixEvenWithNoSeparator() {
        val split = FandomDisplayName.split("One Direction RPF")
        assertEquals("One Direction", split.title)
        assertEquals("RPF", split.qualifier)
    }

    @Test
    fun rpfSitsOutsideTheParenthetical() {
        val cases = listOf(
            Triple("Yanni (Musician) RPF", "Yanni", "(Musician) RPF"),
            Triple("Only Lovers Left Alive (2013) RPF", "Only Lovers Left Alive", "(2013) RPF")
        )
        for ((name, title, qualifier) in cases) {
            val split = FandomDisplayName.split(name)
            assertEquals(title, split.title)
            assertEquals(qualifier, split.qualifier)
        }
    }

    @Test
    fun fullwidthParenthesesAreTheSameConvention() {
        val split = FandomDisplayName.split("博士斯通（漫画）")
        assertEquals("博士斯通", split.title)
        assertEquals("（漫画）", split.qualifier)
    }

    @Test
    fun cjkBookBracketsWrapTheTitleAndAreLeftAlone() {
        for (name in listOf("《病案本》", "《将进酒》", "《可怜的社畜》")) {
            val split = FandomDisplayName.split(name)
            assertEquals(name, split.title)
            assertTrue(split.qualifier.isEmpty())
        }
    }

    @Test
    fun enAndEmDashesSeparateToo() {
        assertEquals("- All Media Types", FandomDisplayName.split("Some Show – All Media Types").qualifier)
        assertEquals("- All Media Types", FandomDisplayName.split("Some Show — All Media Types").qualifier)
    }

    @Test
    fun peelingASuffixLeavesNoDashBehind() {
        assertEquals("classmates", FandomDisplayName.split("classmates - RPF").title)
        assertEquals("Deadpool & Wolverine", FandomDisplayName.split("Deadpool & Wolverine - (Movie 2024)").title)
    }

    @Test
    fun aSuffixExposedByAnotherIsAlsoPeeled() {
        assertEquals("Roblox", FandomDisplayName.split("Roblox RPF - Fandom").title)
    }

    @Test
    fun rpfIsMatchedWhateverItsCase() {
        assertEquals("Kamen Rider Blade", FandomDisplayName.split("Kamen Rider Blade Rpf").title)
    }

    @Test
    fun allMediaTypesIsFoundWithoutADashToo() {
        assertEquals("Digimon", FandomDisplayName.split("Digimon: All Media Types").title)
        assertEquals("Hulk", FandomDisplayName.split("Hulk-All Media Types").title)
    }

    @Test
    fun theUnicodeHyphenSeparatesToo() {
        val split = FandomDisplayName.split("Dreaming of Sunshine \u2010 Silver Queen")
        assertEquals("Dreaming of Sunshine", split.title)
        assertEquals("- Silver Queen", split.qualifier)
    }

    @Test
    fun aJapaneseSubtitleKeepsItsClosingDash() {
        for (name in listOf("Lamento -BEYOND THE VOID-", "Bad Wife -Mizuho-", "CAGE-CLOSE-")) {
            assertEquals(name, FandomDisplayName.split(name).title)
        }
    }

    @Test
    fun blankInputSurvives() {
        assertTrue(FandomDisplayName.split("   ").title.isNotEmpty())
    }

    @Test
    fun relatedFandomsIsASuffix() {
        val split = FandomDisplayName.split("Sherlock Holmes & Related Fandoms")
        assertEquals("Sherlock Holmes", split.title)
        assertEquals("& Related Fandoms", split.qualifier)
    }

    @Test
    fun onlyTheLastRelatedFandomsSplits() {
        assertEquals("Spirou & Fantasio", FandomDisplayName.split("Spirou & Fantasio & Related Fandoms").title)
    }

    @Test
    fun relatedFandomsNeedsItsSeparator() {
        for (name in listOf("Eason-Related Fandoms", "Chinese Related Fandoms")) {
            val split = FandomDisplayName.split(name)
            assertEquals("$name should stay whole", name, split.title)
            assertTrue(split.qualifier.isEmpty())
        }
    }

    @Test
    fun relatedFandomsUncoversWhatItWraps() {
        val split = FandomDisplayName.split("Bridgerton (TV) & Related Fandoms")
        assertEquals("Bridgerton", split.title)
        assertEquals("(TV) & Related Fandoms", split.qualifier)
    }

    @Test
    fun theLowercaseSpellingCountsToo() {
        assertEquals("Arsène Lupin", FandomDisplayName.split("Arsène Lupin & related fandoms").title)
        assertEquals("Red Hood", FandomDisplayName.split("Red Hood and Related Fandoms").title)
    }

    @Test
    fun rpfNeedsNoSpaceAtAll() {
        assertEquals("hetamyu", FandomDisplayName.split("hetamyuRPF").title)
        assertEquals("英国演员", FandomDisplayName.split("英国演员RPF").title)
        assertEquals("真人", FandomDisplayName.split("真人rpf").title)
        assertEquals("The Notebook", FandomDisplayName.split("The Notebook(2004)RPF").title)
    }

    @Test
    fun aBareRPFIsItsOwnTitle() {
        assertEquals("RPF", FandomDisplayName.split("RPF").title)
    }

    @Test
    fun gluedRPFStacksWithABracket() {
        val split = FandomDisplayName.split("The Notebook(2004)RPF")
        assertEquals("The Notebook", split.title)
        assertEquals("(2004) RPF", split.qualifier)
    }

    @Test
    fun theMediaUmbrellaIsMatchedInEverySpellingWeHaveSeen() {
        val cases = listOf(
            "刺客信条-所有媒体类型" to "刺客信条",
            "蝙蝠俠-所有媒體型別" to "蝙蝠俠",
            "蝙蝠俠 - 所有媒體類型" to "蝙蝠俠",
            "Capitão América - Todos os Tipos de Mídia" to "Capitão América",
            "Capitán América - Todos los tipos de medios" to "Capitán América"
        )
        for ((name, title) in cases) {
            assertEquals(name, title, FandomDisplayName.split(name).title)
        }
    }

    @Test
    fun aBracketPairMayMixWidths() {
        assertEquals("BLEACH", FandomDisplayName.split("BLEACH(Anime&Manga）").title)
        assertEquals("南风知我意", FandomDisplayName.split("南风知我意(TV）").title)
        assertEquals("第三日", FandomDisplayName.split("第三日（原创作品)").title)
    }

    @Test
    fun aCloserWithNoOpenerIsTitle() {
        assertEquals("Sunn O)))", FandomDisplayName.split("Sunn O)))").title)
        assertEquals("1967)", FandomDisplayName.split("1967)").title)
    }

    @Test
    fun aSmileyIsNotAParenthetical() {
        assertEquals("MYSTERIOUS MURDER DIY :)", FandomDisplayName.split("MYSTERIOUS MURDER DIY :)").title)
    }

    @Test
    fun fandomGluedByADashIsASuffix() {
        val cases = listOf(
            "The Expanse-Fandom" to "The Expanse",
            "Creepypasta-fandom" to "Creepypasta",
            "杀死你的旅程—Fandom" to "杀死你的旅程",
            "Jinkx Monsoon- Fandom" to "Jinkx Monsoon",
            "Fanfic -Fandom" to "Fanfic"
        )
        for ((name, title) in cases) {
            assertEquals(name, title, FandomDisplayName.split(name).title)
        }
    }

    @Test
    fun fandomWithoutADashIsPartOfTheTitle() {
        for (name in listOf("Pizza Fandom", "Celebrity Fiction")) {
            assertEquals("$name should stay whole", name, FandomDisplayName.split(name).title)
        }
    }

    @Test
    fun thePrimarySegmentIsTheLastPipePiece() {
        val name = "僕のヒーローアカデミア | Boku no Hero Academia | My Hero Academia (Anime & Manga)"
        assertEquals("My Hero Academia (Anime & Manga)", FandomDisplayName.primarySegment(name))
        assertEquals(listOf("僕のヒーローアカデミア", "Boku no Hero Academia"), FandomDisplayName.aliasSegments(name))
        assertEquals("Marvel", FandomDisplayName.primarySegment("Marvel"))
    }

    @Test
    fun siblingsShareADisplayTitleButNotAnIdentity() {
        val older = FandomDisplayName.split("Doctor Who (1963)")
        val newer = FandomDisplayName.split("Doctor Who (2005)")
        assertEquals(older.title, newer.title)
        assertNotEquals(older.qualifier, newer.qualifier)
    }

    @Test
    fun aTitleWithItsOwnParentheticalKeepsItThroughADashTail() {
        val split = FandomDisplayName.split("The (Unfinished) Story - Author (Novel)")
        assertEquals("The (Unfinished) Story", split.title)
        assertEquals("- Author (Novel)", split.qualifier)
    }

    @Test
    fun stackedMixedWidthBracketsPeelOnlyTheOuter() {
        val split = FandomDisplayName.split("My Show (Season 1)（2024)")
        assertEquals("My Show (Season 1)", split.title)
        assertEquals("（2024)", split.qualifier)
    }

    @Test
    fun aBookBracketTitleKeepsItsWrapperButLosesTheQualifier() {
        val split = FandomDisplayName.split("《病案本》 (Novel)")
        assertEquals("《病案本》", split.title)
        assertEquals("(Novel)", split.qualifier)
    }

    @Test
    fun anUnopenedCloserSurvivesAlongsideARealQualifier() {
        val split = FandomDisplayName.split("Sunn O))) (Band)")
        assertEquals("Sunn O)))", split.title)
        assertEquals("(Band)", split.qualifier)
    }

    @Test
    fun relatedFandomsWithoutItsConjunctionStaysWhole() {
        val split = FandomDisplayName.split("Sherlock Holmes Related Fandoms")
        assertEquals("Sherlock Holmes Related Fandoms", split.title)
        assertTrue(split.qualifier.isEmpty())
    }

    @Test
    fun aNameThatIsNothingButASuffixKeepsItself() {
        for (bare in listOf("  RPF  ", "  - Fandom  ", "  - All Media Types  ", "  & Related Fandoms  ")) {
            val split = FandomDisplayName.split(bare)
            assertEquals(bare.trim(), split.title)
            assertTrue(split.qualifier.isEmpty())
        }
    }

    @Test
    fun aTitleEndingInItsOwnParentheticalKeepsIt() {
        val split = FandomDisplayName.split("f(x) (Band)")
        assertEquals("f(x)", split.title)
        assertEquals("(Band)", split.qualifier)
    }

    @Test
    fun aNameOnTheKeepWholeListKeepsItsDashTail() {
        for (name in listOf("InuYasha - A Feudal Fairy Tale", "Dragon Age: Origins - Awakening")) {
            val split = FandomDisplayName.split(name)
            assertEquals("$name should stay whole", name, split.title)
            assertTrue(split.qualifier.isEmpty())
        }
    }

    @Test
    fun anExceptionStillLosesASuffixOfAnotherKind() {
        val cases = listOf(
            Triple("Ich bin ein Star - Holt mich hier raus! (Germany TV)", "Ich bin ein Star - Holt mich hier raus!", "(Germany TV)"),
            Triple("Cat Game - The Cat Collector! (Mino Games Video Game)", "Cat Game - The Cat Collector!", "(Mino Games Video Game)"),
            Triple("Daniel - The Wizard (Movie 2004)", "Daniel - The Wizard", "(Movie 2004)")
        )
        for ((name, title, qualifier) in cases) {
            val split = FandomDisplayName.split(name)
            assertEquals(name, title, split.title)
            assertEquals(name, qualifier, split.qualifier)
        }
    }

    @Test
    fun theExceptionListIsKeyedOnWhatSplitActuallyReceives() {
        assertTrue(FandomDisplayExceptions.keepWhole.contains("Coil - A Circle of Children"))
        assertTrue(!FandomDisplayExceptions.keepWhole.contains("Dennou Coil | Coil - A Circle of Children"))
    }

    @Test
    fun anUnlistedNameStillGetsTheOrdinaryRules() {
        val split = FandomDisplayName.split("Harry Potter - J. K. Rowling")
        assertEquals("Harry Potter", split.title)
        assertEquals("- J. K. Rowling", split.qualifier)
    }

    @Test
    fun anRPFUmbrellaKeepsItsRPF() {
        val cases = listOf(
            "Sports RPF", "Video Blogging RPF", "Actor RPF", "Music RPF",
            "Political RPF", "Historical RPF", "Formula 1 RPF", "Motorsport RPF",
            "Rock Music RPF", "Men's Football RPF", "Chinese Actor RPF"
        )
        for (name in cases) {
            val split = FandomDisplayName.split(name)
            assertEquals("$name is an umbrella; its RPF is part of the name", name, split.title)
            assertTrue(split.qualifier.isEmpty())
        }
    }

    @Test
    fun anRPFSuffixOnARealFandomStillDemotes() {
        val potter = FandomDisplayName.split("Harry Potter RPF")
        assertEquals("Harry Potter", potter.title)
        assertEquals("RPF", potter.qualifier)

        val supernatural = FandomDisplayName.split("Supernatural (TV 2005) RPF")
        assertEquals("Supernatural", supernatural.title)
        assertEquals("(TV 2005) RPF", supernatural.qualifier)
    }

    @Test
    fun aRealWorkStripsItsRPFEvenWithNoNonRPFWorks() {
        val cases = listOf(
            Triple("RuPaul's Drag Race (US) RPF", "RuPaul's Drag Race", "(US) RPF"),
            Triple("Super Sketch Show (TV) RPF", "Super Sketch Show", "(TV) RPF"),
            Triple("8 Mile (2002) RPF", "8 Mile", "(2002) RPF")
        )
        for ((name, title, qualifier) in cases) {
            val split = FandomDisplayName.split(name)
            assertEquals(name, title, split.title)
            assertEquals(qualifier, split.qualifier)
        }
    }

    @Test
    fun aRegionalPoliticalTagKeepsItsRPF() {
        val split = FandomDisplayName.split("Political RPF - US 21st c.")
        assertEquals("Political RPF", split.title)
        assertEquals("- US 21st c.", split.qualifier)
    }

    @Test
    fun qualifiersAreKeptSeparateAndKinded() {
        val split = FandomDisplayName.split("IT (Movies - Muschietti)")
        assertEquals("IT", split.title)
        assertEquals(1, split.parts.size)
        assertEquals(FandomQualifierKind.Parenthetical, split.parts.first().kind)
        assertEquals("(Movies - Muschietti)", split.parts.first().text)

        val potter = FandomDisplayName.split("Harry Potter - J. K. Rowling")
        assertEquals(listOf(FandomQualifierKind.Creator), potter.parts.map { it.kind })
        assertEquals("- J. K. Rowling", potter.parts.first().text)
    }

    @Test
    fun joinedQualifierMatchesTheParts() {
        val split = FandomDisplayName.split("Supernatural (TV 2005) RPF")
        assertEquals(listOf(FandomQualifierKind.Parenthetical, FandomQualifierKind.Rpf), split.parts.map { it.kind })
        assertEquals(split.parts.joinToString(" ") { it.text }, split.qualifier)
    }

    @Test
    fun partsKeepTheOrderTheyHadInTheName() {
        val names = listOf(
            "Supernatural (TV 2005) RPF",
            "Political RPF - US 21st c.",
            "Good Omens (TV) RPF",
            "Bridgerton (TV) & Related Fandoms"
        )
        for (name in names) {
            val split = FandomDisplayName.split(name)
            var cursor = 0
            for (part in split.parts) {
                val needle = if (part.text.startsWith("- ")) part.text.drop(2) else part.text
                val found = name.indexOf(needle, startIndex = cursor)
                assertTrue("$needle missing from $name after $cursor", found >= 0)
                cursor = found + needle.length
            }
        }
    }

    @Test
    fun protectingAnRPFDoesNotProtectTheWholeName() {
        val staged = FandomDisplayName.split("Stage Play Touken Ranbu - Suemitsu Actor RPF")
        assertEquals("Stage Play Touken Ranbu", staged.title)
        assertEquals("- Suemitsu Actor RPF", staged.qualifier)

        assertEquals("classmates", FandomDisplayName.split("classmates - RPF").title)
    }

    @Test
    fun multiFandomKeepsItsFandomSuffix() {
        val split = FandomDisplayName.split("Multi-Fandom")
        assertEquals("Multi-Fandom", split.title)
        assertTrue(split.qualifier.isEmpty())
    }

    @Test
    fun aRealFandomStillLosesAGluedFandomSuffix() {
        val split = FandomDisplayName.split("The Expanse-Fandom")
        assertEquals("The Expanse", split.title)
        assertEquals("- Fandom", split.qualifier)
    }

    @Test
    fun aLowVolumeRealFandomStillLosesItsRPF() {
        val ming = FandomDisplayName.split("Ming Dynasty RPF")
        assertEquals("Ming Dynasty", ming.title)
        assertEquals("RPF", ming.qualifier)

        assertEquals("Tang Dynasty", FandomDisplayName.split("Tang Dynasty RPF").title)
    }

    @Test
    fun bareTitleCases() {
        assertEquals("Doctor Who", FandomDisplayName.bareTitle("Doctor Who (2005)"))
        assertEquals("NARUTO", FandomDisplayName.bareTitle("NARUTO (Anime & Manga)"))
        assertEquals("Star Wars", FandomDisplayName.bareTitle("Star Wars - All Media Types"))
        assertEquals(
            "My Hero Academia",
            FandomDisplayName.bareTitle("僕のヒーローアカデミア | Boku no Hero Academia | My Hero Academia")
        )
        assertEquals("Haikyuu!!", FandomDisplayName.bareTitle("Haikyuu!!"))
    }

    @Test
    fun bareTitleAmongCases() {
        val names = listOf("Doctor Who (2005)", "Doctor Who")
        assertEquals("Doctor Who (2005)", FandomDisplayName.bareTitle("Doctor Who (2005)", names))
        assertEquals("Doctor Who", FandomDisplayName.bareTitle("Doctor Who", names))
        assertEquals("Haikyuu!!", FandomDisplayName.bareTitle("Haikyuu!!", names))
        assertEquals("Doctor Who", FandomDisplayName.bareTitle("Doctor Who (2005)", listOf("Doctor Who (2005)")))
    }
}
