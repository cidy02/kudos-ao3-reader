import Foundation
import Testing
@testable import Kudos

struct PDFParagraphRepairTests {
    // MARK: - Paragraph joining

    @Test func paragraphSplitAcrossAPageBreakJoinsWithOneSpace() {
        let pages = [
            ["She felt the strap keeping"],
            ["her sword to her waist went loose.", "A fresh paragraph began below."]
        ]

        let repaired = PDFParagraphRepair.repair(pages)
        #expect(repaired.count == 2)
        #expect(repaired[0] == ["She felt the strap keeping her sword to her waist went loose."])
        #expect(repaired[1] == ["A fresh paragraph began below."])
    }

    /// Within a page, MuPDF's separate blocks are real paragraph gaps: in the owner's 171-page PDF, joining them merged
    /// 8 of the author's own unpunctuated paragraphs and repaired 1 split, so only page breaks join (T-579b).
    @Test func twoBlocksOnTheSamePageStayApartEvenWithoutPunctuation() {
        let pages = [[
            "She nuzzled her face against Elsa's",
            "She smiled even as her blush deepened."
        ]]

        let repaired = PDFParagraphRepair.joinBrokenParagraphs(pages)
        #expect(repaired == pages)
    }

    @Test func paragraphSpanningThreePagesJoinsAndPreservesPageCount() {
        let pages = [
            ["The road wound along the ridge"],
            ["through the fog and the pines"],
            ["until the lanterns came into view.", "Then they stopped."]
        ]

        let repaired = PDFParagraphRepair.joinBrokenParagraphs(pages)
        #expect(repaired.count == 3)
        #expect(repaired[0] == [
            "The road wound along the ridge through the fog and the pines until the lanterns came into view."
        ])
        #expect(repaired[1].isEmpty)
        #expect(repaired[2] == ["Then they stopped."])
    }

    @Test func dialogueEndingWithPeriodInsideQuotesDoesNotJoinNextPage() {
        let pages = [
            ["\"I am not going back there.\""],
            ["\"You do not have a choice.\""]
        ]

        let repaired = PDFParagraphRepair.repair(pages)
        #expect(repaired == [
            ["\"I am not going back there.\""],
            ["\"You do not have a choice.\""]
        ])
    }

    @Test func terminalPunctuationVariantsAndQuotedEmDashStayApart() {
        #expect(!PDFParagraphRepair.shouldJoin("She stopped.", with: "then looked back."))
        #expect(!PDFParagraphRepair.shouldJoin("“Enough!”", with: "he shouted."))
        #expect(!PDFParagraphRepair.shouldJoin("“Really?”", with: "she asked."))
        #expect(!PDFParagraphRepair.shouldJoin("“Wait…”", with: "she murmured."))
        #expect(!PDFParagraphRepair.shouldJoin("(She knew better.)", with: "still she went."))
        #expect(!PDFParagraphRepair.shouldJoin("“I never meant—”", with: "she started."))
        #expect(!PDFParagraphRepair.shouldJoin("\"I never meant—\"", with: "He cut her off."))
    }

    @Test func chapterHeadingAtPageEndStaysSeparate() {
        let pages = [
            ["The previous scene ended quietly.", "Chapter 3"],
            ["The morning arrived cold and grey."]
        ]

        let repaired = PDFParagraphRepair.repair(pages)
        #expect(repaired == [
            ["The previous scene ended quietly.", "Chapter 3"],
            ["The morning arrived cold and grey."]
        ])
    }

    @Test func authorSignOffBeforeChapterHeadingStaysSeparate() {
        let pages = [
            ["~Malthazar LOS"],
            ["*Chapter 2*: A Queens Gratitude", "Dawn broke over the fjord."]
        ]

        let repaired = PDFParagraphRepair.repair(pages)
        #expect(repaired == [
            ["~Malthazar LOS"],
            ["*Chapter 2*: A Queens Gratitude", "Dawn broke over the fjord."]
        ])
    }

    @Test func shortLineBeforeCapitalisedParagraphStaysSeparate() {
        let pages = [
            ["Winter breaths"],
            ["They were her favourite flower."]
        ]

        let repaired = PDFParagraphRepair.repair(pages)
        #expect(repaired == [
            ["Winter breaths"],
            ["They were her favourite flower."]
        ])
    }

    @Test func commaAndSemicolonJoinBeforeCapitalisedNameOrDialogue() {
        let commaPages = [
            ["Before she could answer,"],
            ["Harry stepped into the doorway."]
        ]
        #expect(PDFParagraphRepair.repair(commaPages) == [
            ["Before she could answer, Harry stepped into the doorway."],
            []
        ])

        let semicolonPages = [
            ["The fire had gone out;"],
            ["Harry struck another match."]
        ]
        #expect(PDFParagraphRepair.repair(semicolonPages) == [
            ["The fire had gone out; Harry struck another match."],
            []
        ])

        let quotedCommaPages = [
            ["“Wait for me,”"],
            ["Harry called down the stairs."]
        ]
        #expect(PDFParagraphRepair.repair(quotedCommaPages) == [
            ["“Wait for me,” Harry called down the stairs."],
            []
        ])
    }

    @Test func longBlockEndingInLowercaseLetterJoinsBeforeCapitalisedName() {
        let longLead = "She crossed the courtyard in the rain, lowered her hood, and quietly said to"
        #expect(longLead.count >= 60)

        let pages = [
            [longLead],
            ["Harry that nobody else knew where the key was hidden."]
        ]
        #expect(PDFParagraphRepair.repair(pages) == [
            [longLead + " Harry that nobody else knew where the key was hidden."],
            []
        ])
    }

    @Test func colonAndOpeningQuoteJoinBeforeLowercaseOnly() {
        #expect(PDFParagraphRepair.shouldJoin("She only had one rule:", with: "never look back."))
        #expect(!PDFParagraphRepair.shouldJoin("Chapter 1:", with: "The Return"))
        #expect(!PDFParagraphRepair.shouldJoin("Part Two", with: "They left at sunrise."))
        #expect(PDFParagraphRepair.shouldJoin("He murmured, “", with: "stay quiet.”"))
    }

    // MARK: - Scene-break separators & headers/footers

    @Test func sceneBreakAtPageEdgeOnHalfThePagesSurvivesEverywhere() {
        let pages = [
            ["Page one opening.", "* * *"],
            ["Page two opening.", "* * *", "Page two closing."],
            ["Page three opening.", "* * *"],
            ["* * *", "Page four opening."],
            ["Page five opening.", "Page five closing."],
            ["Page six opening.", "* * *"]
        ]

        let repaired = PDFParagraphRepair.repair(pages)
        #expect(repaired[0] == ["Page one opening.", "* * *"])
        #expect(repaired[1] == ["Page two opening.", "* * *", "Page two closing."])
        #expect(repaired[2] == ["Page three opening.", "* * *"])
        #expect(repaired[3] == ["* * *", "Page four opening."])
        #expect(repaired[4] == ["Page five opening.", "Page five closing."])
        #expect(repaired[5] == ["Page six opening.", "* * *"])
    }

    @Test func separatorVariantsSurviveHeaderFilterAndNormaliseToAsterisks() {
        let variants = ["* * *", "~~~", "***", "o0o", "oOo", "xXx", "❦", "-x-x-x-", "✦ ✦ ✦", "⁂", "—", "---"]
        for variant in variants {
            #expect(PDFParagraphRepair.isSeparator(variant), "expected separator: \(variant)")
        }

        // Non-separators: bare numbers, Roman numerals, short words, stutters, quoted dash,
        // signatures, names the ornament rule must not eat, a lone hyphen, and faces.
        let nonSeparators = [
            "000", "- 0 -", "- 12 -", "XX", "Ox", "ox", "O", "O-", "x- x",
            "Xox", "xox", "oxo", "XoX",
            "-", ":-)", "^_^", "o_o", ">_<",
            "“—”", "...", "~Malthazar LOS", "*Chapter 2*: A Queens Gratitude"
        ]
        for text in nonSeparators {
            #expect(!PDFParagraphRepair.isSeparator(text), "unexpected separator: \(text)")
        }

        let pages = [
            ["Scene one.", "~~~"],
            ["Scene two.", "o0o"],
            ["Scene three.", "❦"],
            ["Scene four.", "-x-x-x-"]
        ]
        let repaired = PDFParagraphRepair.repair(pages)
        #expect(repaired == [
            ["Scene one.", "* * *"],
            ["Scene two.", "* * *"],
            ["Scene three.", "* * *"],
            ["Scene four.", "* * *"]
        ])
    }

    @Test func runningHeaderAtTopOfMostPagesIsRemovedButMidPageOccurrenceSurvives() {
        let pages = [
            ["The Weight of Water", "First page prose.", "1"],
            ["The Weight of Water", "Second page prose.", "2"],
            ["The Weight of Water", "Intro on page three.", "The Weight of Water", "Still page three.", "3"],
            ["The Weight of Water", "Fourth page prose.", "- 4 -"],
            ["The Weight of Water", "Fifth page prose.", "5."]
        ]

        let repaired = PDFParagraphRepair.repair(pages)
        #expect(repaired[0] == ["First page prose."])
        #expect(repaired[1] == ["Second page prose."])
        #expect(repaired[2] == ["Intro on page three.", "The Weight of Water", "Still page three."])
        #expect(repaired[3] == ["Fourth page prose."])
        #expect(repaired[4] == ["Fifth page prose."])
    }

    @Test func runningFooterAbovePageNumberIsRemovedAndSeparatorNeverJoinsProse() {
        let pages = [
            ["She paused", "~~~", "and waited.", "Author Footer", "1"],
            ["Second page prose.", "Author Footer", "2"],
            ["Third page prose.", "Author Footer", "3"],
            ["Fourth page prose.", "Author Footer", "4"]
        ]

        let repaired = PDFParagraphRepair.repair(pages)
        #expect(repaired[0] == ["She paused", "* * *", "and waited."])
        #expect(repaired[1] == ["Second page prose."])
        #expect(repaired[2] == ["Third page prose."])
        #expect(repaired[3] == ["Fourth page prose."])
    }

    // MARK: - Hyphens

    @Test func stuttersAndCutOffHyphensStayUnchanged() {
        let singleBlockPages = [[
            "\"I didn't mean y- your majesty.\"",
            "\"Wha- really?\" he asked.",
            "There were five- hundred soldiers outside."
        ]]
        #expect(PDFParagraphRepair.repair(singleBlockPages) == singleBlockPages)

        // Even when a block ends on a stutter hyphen before a lowercase continuation,
        // it joins with one space and keeps the hyphen rather than merging the words.
        let splitPages = [
            ["\"I didn't mean y-"],
            ["your majesty.\""],
            ["\"Wha-"],
            ["really?\""]
        ]
        let repaired = PDFParagraphRepair.repair(splitPages)
        #expect(repaired == [
            ["\"I didn't mean y- your majesty.\""],
            [],
            ["\"Wha- really?\""],
            []
        ])
    }

    // MARK: - Names, faces, lowercase headings, scripts

    @Test func namesFacesAndALoneHyphenStayProse() {
        #expect(PDFParagraphRepair.repair([["Xox"], ["waited in the doorway."]]) == [
            ["Xox waited in the doorway."],
            []
        ])
        #expect(PDFParagraphRepair.repair([["-"], ["then she left."]]) == [
            ["- then she left."],
            []
        ])

        let pages = [
            ["She waved.", ":-)", "Xox stood still.", "^_^"],
            ["o_o", "oxo left.", "—"]
        ]
        #expect(PDFParagraphRepair.repair(pages) == [
            ["She waved.", ":-)", "Xox stood still.", "^_^"],
            ["o_o", "oxo left.", "* * *"]
        ])
    }

    @Test func lowercaseChapterHeadingDoesNotJoin() {
        let spilled = [
            ["she never finished the"],
            ["chapter three", "they left before dawn."]
        ]
        #expect(PDFParagraphRepair.repair(spilled) == [
            ["she never finished the"],
            ["chapter three", "they left before dawn."]
        ])

        let followedByLowercase = [
            ["chapter three"],
            ["they left before dawn."]
        ]
        #expect(PDFParagraphRepair.repair(followedByLowercase) == followedByLowercase)

        #expect(!PDFParagraphRepair.shouldJoin("she said,", with: "chapter three"))
        #expect(!PDFParagraphRepair.shouldJoin("she stopped", with: "part two"))
        #expect(!PDFParagraphRepair.shouldJoin("part two", with: "they left before dawn."))
        #expect(!PDFParagraphRepair.shouldJoin("she never finished the", with: "epilogue"))
        #expect(!PDFParagraphRepair.shouldJoin("epilogue", with: "they left before dawn."))
        #expect(PDFParagraphRepair.shouldJoin("she skipped the", with: "epilogue and went to bed."))
        // A heading cut after its colon is still one heading.
        #expect(PDFParagraphRepair.shouldJoin("Chapter 1:", with: "the return"))
    }

    @Test func repeatedChapterHeadingKeepsTheFirstCopy() {
        let pages = [
            ["Chapter 1", "Once upon a time there was a sword."],
            ["Chapter 1", "The road continued past the ridge."],
            ["Chapter 1", "Fog sat in the valley below."],
            ["Chapter 1", "They did not turn back."]
        ]
        #expect(PDFParagraphRepair.repair(pages) == [
            ["Chapter 1", "Once upon a time there was a sword."],
            ["The road continued past the ridge."],
            ["Fog sat in the valley below."],
            ["They did not turn back."]
        ])
    }

    @Test func repeatedSentenceAtThePageEdgeIsKept() {
        let refrain = "And the light remains."
        let pages = [
            ["The first stanza ended.", refrain],
            ["The second stanza ended.", refrain],
            ["The third stanza ended.", refrain],
            ["The fourth stanza ended.", refrain]
        ]
        #expect(PDFParagraphRepair.repair(pages) == pages)
    }

    @Test func midPageYearSurvivesWhileEdgePageNumbersGo() {
        let pages = [
            ["The Weight of Water", "1984", "First page prose.", "1"],
            ["The Weight of Water", "Second page prose.", "2"],
            ["The Weight of Water", "Third page prose.", "3"],
            ["The Weight of Water", "Fourth page prose.", "4"]
        ]
        let repaired = PDFParagraphRepair.repair(pages)
        #expect(repaired[0] == ["1984", "First page prose."])
        #expect(repaired[1] == ["Second page prose."])
        #expect(repaired[2] == ["Third page prose."])
        #expect(repaired[3] == ["Fourth page prose."])
    }

    @Test func uncasedAndRightToLeftPagesDoNotMerge() {
        let chinese = String(repeating: "她握住剑带，风从山上吹下来。", count: 5)
        let japanese = String(repeating: "彼女は紐を握ったまま丘を越えた。", count: 4)
        let arabic = String(repeating: "أمسكت بالحزام ", count: 6)
            .trimmingCharacters(in: .whitespaces)
        let hebrew = String(repeating: "היא אחזה ברצועה ", count: 6)
            .trimmingCharacters(in: .whitespaces)
        #expect(chinese.count >= 60)
        #expect(japanese.count >= 60)
        #expect(arabic.count >= 60)
        #expect(hebrew.count >= 60)

        let pairs = [
            [chinese, "剑仍在腰间，她没有松手。"],
            [japanese, "剣は腰に残った。"],
            [arabic, "وبقي السيف قريباً منها."],
            [hebrew, "החרב נשארה קרוב אליה."]
        ]
        for pair in pairs {
            let pages = [[pair[0]], [pair[1]]]
            #expect(PDFParagraphRepair.repair(pages) == pages)
        }

        // Cyrillic has case: a finished sentence stays apart, a short line before a
        // capital stays apart, and a lowercase continuation still joins.
        #expect(PDFParagraphRepair.repair([
            ["Она остановилась."],
            ["Потом она пошла домой."]
        ]) == [
            ["Она остановилась."],
            ["Потом она пошла домой."]
        ])
        #expect(PDFParagraphRepair.repair([
            ["Зимний вздох"],
            ["Они были её цветами."]
        ]) == [
            ["Зимний вздох"],
            ["Они были её цветами."]
        ])
        #expect(PDFParagraphRepair.repair([
            ["Она почувствовала, как ремень"],
            ["удерживавший меч ослаб."]
        ]) == [
            ["Она почувствовала, как ремень удерживавший меч ослаб."],
            []
        ])
    }

    /// `outlineChapters` slices `pageLines[start..<end]` by PDF page index. A continuation
    /// belongs on the earlier page; the next page's own paragraphs stay put.
    @Test func outlineSliceKeepsTheContinuationOnTheEarlierPage() {
        let pages = [
            ["The previous chapter ended with", "She felt the strap keeping"],
            ["her sword to her waist went loose.", "Chapter 2", "Dawn broke."]
        ]
        let repaired = PDFParagraphRepair.repair(pages)
        #expect(repaired.count == pages.count)
        #expect(Array(repaired[0..<1].flatMap(\.self)) == [
            "The previous chapter ended with",
            "She felt the strap keeping her sword to her waist went loose."
        ])
        #expect(Array(repaired[1..<2].flatMap(\.self)) == [
            "Chapter 2",
            "Dawn broke."
        ])
    }

    @Test func thousandPagesKeepTheirTextAndTheirPageCount() {
        let pages = (0..<1_000).map { index in
            ["The sentence on page \(index) keeps going", "until it finishes."]
        }
        let repaired = PDFParagraphRepair.repair(pages)
        #expect(repaired.count == 1_000)
        #expect(repaired == pages)
    }

    // MARK: - Short-document chrome, Line Break separator, verse line breaks

    @Test func singlePageDropsBareEdgePageNumberAndKeepsMidPageNumber() {
        let single = [["The harbor was quiet before dawn.", "1"]]
        #expect(PDFParagraphRepair.repair(single) == [["The harbor was quiet before dawn."]])

        let dashed = [["- 1 -", "The harbor was quiet before dawn."]]
        #expect(PDFParagraphRepair.repair(dashed) == [["The harbor was quiet before dawn."]])

        let midPage = [["Opening line of the story.", "1984", "Closing line of the story.", "Page 1 of 1"]]
        #expect(PDFParagraphRepair.repair(midPage) == [
            ["Opening line of the story.", "1984", "Closing line of the story."]
        ])
    }

    @Test func twoAndThreePageDocumentsDropRepeatedEdgeChromeAndPageNumbers() {
        let threePages = [
            ["The Night Notebook", "Chapter 1: Salt", "Page one prose.", "1"],
            ["The Night Notebook", "Page two prose.", "2 / 3"],
            ["The Night Notebook", "Page three prose.", "Page 3 of 3"]
        ]
        #expect(PDFParagraphRepair.repair(threePages) == [
            ["Chapter 1: Salt", "Page one prose."],
            ["Page two prose."],
            ["Page three prose."]
        ])

        // An edge line appearing on only 2 of 3 pages is NOT dropped on a 3-page PDF.
        let twoOfThree = [
            ["Dear Maren,", "First page prose.", "1"],
            ["Dear Maren,", "Second page prose.", "2"],
            ["Yours, Lina", "Third page prose.", "3"]
        ]
        #expect(PDFParagraphRepair.repair(twoOfThree) == [
            ["Dear Maren,", "First page prose."],
            ["Dear Maren,", "Second page prose."],
            ["Yours, Lina", "Third page prose."]
        ])

        // On a 2-page PDF, an edge line on both pages goes, while a repeated chapter heading keeps page 1's copy.
        let twoPages = [
            ["The Night Notebook", "Chapter 1", "First page prose.", "1"],
            ["The Night Notebook", "Second page prose.", "2"]
        ]
        #expect(PDFParagraphRepair.repair(twoPages) == [
            ["Chapter 1", "First page prose."],
            ["Second page prose."]
        ])

        let twoPageHeadingHeader = [
            ["Chapter 1", "First page prose."],
            ["Chapter 1", "Second page prose."]
        ]
        #expect(PDFParagraphRepair.repair(twoPageHeadingHeader) == [
            ["Chapter 1", "First page prose."],
            ["Second page prose."]
        ])
    }

    @Test func lineBreakSeparatorNormalizesAndVerseNeverJoinsAcrossPages() {
        #expect(PDFParagraphRepair.isSeparator("Line Break"))
        #expect(PDFParagraphRepair.isSeparator("  line   break  "))
        #expect(!PDFParagraphRepair.isSeparator("She added a line break."))
        #expect(!PDFParagraphRepair.isSeparator("Line Break\nSecond line"))

        let pages = [
            ["Scene one ended quietly.", "Line Break"],
            ["Scene two began at dusk.", "Line Break"],
            ["Scene three ended.", "Line Break"],
            ["Scene four.", "Line Break"]
        ]
        #expect(PDFParagraphRepair.repair(pages) == [
            ["Scene one ended quietly.", "* * *"],
            ["Scene two began at dusk.", "* * *"],
            ["Scene three ended.", "* * *"],
            ["Scene four.", "* * *"]
        ])

        #expect(!PDFParagraphRepair.shouldJoin(
            "The harbor keeps its own books\nin salt and in nails",
            with: "and in the names of boats"
        ))
        #expect(!PDFParagraphRepair.shouldJoin(
            "She read aloud",
            with: "Salt on the lintel\nsalt on the tongue"
        ))
    }
}
