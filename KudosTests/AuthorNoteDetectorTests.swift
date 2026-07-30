import Foundation
import Testing
@testable import Kudos

/// Tests author's-note detection.
///
/// Fixtures quote **real** note text wherever possible and say where it came from,
/// because that is what makes the table extensible: when a future document needs a
/// new indicator, the test added alongside it should be evidence, not invention.
///
/// The asymmetry that guides every case here: a missed note is cosmetic, while a
/// false positive demotes real prose to apparatus. So the prose cases matter more
/// than the note cases.
struct AuthorNoteDetectorTests {
    private func names(_ blocks: [String]) -> [String] {
        AuthorNoteDetector.diagnostics(for: blocks)
            .sorted { $0.key < $1.key }
            .map(\.value)
    }

    // MARK: - Real-world notes

    @Test func detectsTheNoteFromTheTravelingSwordPDF() throws {
        // Verbatim from the PDF the owner imported (a fanfiction.net-era fic), which
        // is what prompted this feature. Notice it carries no "A/N:" marker at all —
        // only meta-talk about the author's other story and their obsession.
        let blocks = [
            "Yes I should be working on \"you're in the army now.\" I will finish it. I swear. "
                + "I'm just not feeling it right now. Im in the middle of a \"Frozen\" obsession.. "
                + "so enjoy this.",
            "Cold.",
            "That was all she was really aware of. The deep biting cold that had crawled its way "
                + "into her bones as she trudged thru the deep snow of the forest."
        ]
        let notes = AuthorNoteDetector.noteIndices(in: blocks)
        #expect(notes.contains(0))
        // The story itself must not be caught.
        #expect(!notes.contains(1))
        #expect(!notes.contains(2))
    }

    @Test func detectsExplicitMarkersAnywhereInTheWork() {
        let blocks = [
            "She walked into the room and the door closed behind her with a soft click.",
            "A/N: sorry this took so long, my laptop died.",
            "The story resumed where it had left off, as though nothing had happened at all.",
            "Disclaimer: I don't own these characters.",
            "Another paragraph of perfectly ordinary narration to fill the middle out."
        ]
        let notes = AuthorNoteDetector.noteIndices(in: blocks)
        // Both markers sit in the middle of the work, where meta-talk is not trusted —
        // these are caught because the marker itself is unambiguous.
        #expect(notes.contains(1))
        #expect(notes.contains(3))
        #expect(!notes.contains(0))
        #expect(!notes.contains(2))
        #expect(!notes.contains(4))
    }

    @Test func detectsBetaCreditsAndReviewAsks() {
        let blocks = [
            "Beta'd by the wonderful someone-or-other, all remaining errors are mine.",
            "The prose of the story goes here and continues for a good long while yet.",
            "Thanks for reading! Please review, it makes my day."
        ]
        let notes = AuthorNoteDetector.noteIndices(in: blocks)
        #expect(notes.contains(0))
        #expect(notes.contains(2))
        #expect(!notes.contains(1))
    }

    // MARK: - Prose that must survive

    @Test func narrationIsNotDemotedEvenWhenItSoundsChatty() {
        // Every one of these contains a phrase from the table, in the *middle* of the
        // work where meta-talk is not trusted. This is the test that protects prose.
        let blocks = Array(repeating: "Filler paragraph of narration.", count: 3) + [
            "She thought about the next chapter of her life and what it might hold for her.",
            "\"I will finish it,\" he said, \"whatever it costs me in the end.\"",
            "His obsession with the sword had cost him everything he had ever loved.",
            "Sorry for the delay, she wrote in the letter, and sealed it with wax."
        ] + Array(repeating: "More narration to keep these away from the edges.", count: 3)

        let notes = AuthorNoteDetector.noteIndices(in: blocks)
        for index in 3...6 {
            #expect(!notes.contains(index), "block \(index) was wrongly treated as a note")
        }
    }

    @Test func firstPersonProseIsNotANote() {
        let blocks = [
            "I don't own anything worth stealing, which is why the theft confused me.",
            "The rest of the story continues from there without further interruption."
        ]
        // This one *is* caught, by `ownership-disclaimer`, and the test records that
        // honestly rather than pretending otherwise: "I don't own" is a strong enough
        // fanfic marker to be worth the rare first-person false positive, and the
        // user-facing override (see TASKS.md) is the escape hatch. If this ever needs
        // to change, narrow the indicator's scope to `.edges` rather than deleting it.
        #expect(AuthorNoteDetector.diagnostics(for: blocks)[0] == "ownership-disclaimer")
    }

    // MARK: - Scope mechanics

    @Test func edgeScopedIndicatorsOnlyFireNearTheEnds() {
        let chatty = "Sorry for the wait, here is the new chapter at last."
        let filler = "Ordinary narration."
        // At the front: caught.
        #expect(AuthorNoteDetector.noteIndices(in: [chatty, filler, filler, filler]).contains(0))
        // Buried in the middle of a longer work: not caught.
        let long = [filler, filler, filler, chatty, filler, filler, filler]
        #expect(!AuthorNoteDetector.noteIndices(in: long).contains(3))
        // At the very end: caught again.
        let tail = [filler, filler, filler, filler, chatty]
        #expect(AuthorNoteDetector.noteIndices(in: tail).contains(4))
    }

    @Test func diagnosticsNameTheRuleThatMatched() {
        // The extension workflow depends on this: point it at a new document and see
        // which rule claimed which block.
        #expect(names(["A/N: hello"]) == ["an-abbreviation"])
        #expect(names(["Disclaimer: not mine"]) == ["disclaimer"])
        #expect(names(["Beta: someone"]) == ["beta-credit"])
    }

    @Test func emptyAndWhitespaceBlocksAreIgnored() {
        #expect(AuthorNoteDetector.noteIndices(in: ["", "   ", "\n"]).isEmpty)
    }

    // MARK: - Output shape

    @Test func notesBecomeAsidesAndProseStaysParagraphs() throws {
        let body = HTMLWorkSanitizer.paragraphs(from: [
            "A/N: quick note before we start.",
            "The story begins on a cold morning in the middle of nowhere at all."
        ])
        #expect(body.contains("<aside epub:type=\"note\" class=\"author-note\">"))
        #expect(body.contains("<p>A/N: quick note before we start.</p>"))
        #expect(body.contains("<p>The story begins on a cold morning"))
        // Prose must not end up inside the aside.
        let asideEnd = try #require(body.range(of: "</aside>"))
        #expect(body.range(of: "The story begins")!.lowerBound > asideEnd.upperBound)
    }

    @Test func consecutiveNotesShareOneAside() {
        // A three-paragraph preamble is one note, not three.
        let body = HTMLWorkSanitizer.paragraphs(from: [
            "A/N: first line of the note.",
            "Beta'd by someone lovely.",
            "Thanks for reading, please review!",
            "The actual story starts here and runs on for a while."
        ])
        #expect(body.components(separatedBy: "<aside").count - 1 == 1)
        #expect(body.components(separatedBy: "</aside>").count - 1 == 1)
    }
}
