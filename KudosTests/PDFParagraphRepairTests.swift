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
        let variants = ["* * *", "~~~", "***", "o0o", "oOo", "xXx", "❦", "-x-x-x-", "✦ ✦ ✦", "⁂", "—"]
        for variant in variants {
            #expect(PDFParagraphRepair.isSeparator(variant), "expected separator: \(variant)")
        }

        // Non-separators: bare numbers, Roman numerals, short words, stutters, quoted dash, signatures.
        let nonSeparators = [
            "000", "- 0 -", "- 12 -", "XX", "Ox", "O", "O-", "x- x",
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
}
