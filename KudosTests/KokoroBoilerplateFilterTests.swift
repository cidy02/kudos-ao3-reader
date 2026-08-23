#if os(iOS)
import Foundation
import ReadiumShared
import XCTest
@testable import Kudos

/// Covers `KokoroBoilerplateFilter` directly (label matching, URL rewriting)
/// and through `KokoroSemanticDocument.blocks(from:)` / the packer, so both
/// the predicate itself and its wiring into the reader pipeline are checked.
/// Every true-positive string here is copied verbatim from real AO3 export
/// boilerplate found in the corpus at
/// `scratchpad/corpus3` and `scratchpad/corpus-multi` -- not paraphrased --
/// since AO3 generates these labels byte-for-byte identically on every
/// work. Fictional prose used to build false-positive traps is original,
/// written for this test.
@MainActor
final class KokoroBoilerplateFilterTests: XCTestCase {
    // MARK: - True positives: standalone AO3 labels (isBoilerplate)

    func testDropsWorkLevelSummaryLabel() {
        XCTAssertTrue(KokoroBoilerplateFilter.isBoilerplate("Summary"))
    }

    func testDropsWorkLevelNotesLabel() {
        XCTAssertTrue(KokoroBoilerplateFilter.isBoilerplate("Notes"))
    }

    func testDropsEndNotesLabel() {
        XCTAssertTrue(KokoroBoilerplateFilter.isBoilerplate("End Notes"))
    }

    func testDropsChapterSummaryLabel() {
        XCTAssertTrue(KokoroBoilerplateFilter.isBoilerplate("Chapter Summary"))
    }

    func testDropsChapterNotesLabel() {
        XCTAssertTrue(KokoroBoilerplateFilter.isBoilerplate("Chapter Notes"))
    }

    func testDropsKudosPlugFooter() {
        XCTAssertTrue(KokoroBoilerplateFilter.isBoilerplate(
            "Please drop by the Archive and comment to let the creator know if you enjoyed their work!"
        ))
    }

    func testLabelMatchIgnoresCurlyQuoteNormalization() {
        // Raw block text hasn't been through KokoroSpeechNormalizer yet when
        // this runs; the filter must normalize itself rather than assume
        // straight quotes.
        XCTAssertTrue(KokoroBoilerplateFilter.isBoilerplate("Author\u{2019}s Note"))
    }

    // MARK: - False-positive traps: prose that merely resembles a label

    func testKeepsProseThatMerelyBeginsWithNotes() {
        XCTAssertFalse(KokoroBoilerplateFilter.isBoilerplate(
            "Notes on my process for this fic were extensive, honestly."
        ))
    }

    func testKeepsDialogueContainingTheWordSummary() {
        XCTAssertFalse(KokoroBoilerplateFilter.isBoilerplate(
            "\"Give me a summary,\" she said, already reaching for her coat."
        ))
    }

    func testKeepsRealNoteGluedToTheLabelWithNoSpace() {
        // Real corpus example (nightvale-broadcast): the source HTML glued
        // the label directly onto the following sentence with no space.
        XCTAssertFalse(KokoroBoilerplateFilter.isBoilerplate(
            "Author\u{2019}s End NoteThank you to everyone who\u{2019}s been with me since I first started posting this story."
        ))
    }

    func testKeepsCasualLowercaseChatMessageSayingNotes() {
        // Epistolary/chat-fic guard: lowercase, casual usage is real content,
        // not the site's own capitalized section label.
        XCTAssertFalse(KokoroBoilerplateFilter.isBoilerplate("notes"))
    }

    func testKeepsLabelLikeTextWithTrailingContent() {
        XCTAssertFalse(KokoroBoilerplateFilter.isBoilerplate("Notes: bring pizza tomorrow"))
    }

    // MARK: - URLs: rewritten to a bare host, never silently deleted

    func testMidSentenceURLBecomesBareHost() {
        let result = KokoroBoilerplateFilter.sanitizingURLs(
            in: "Silence is Golden Posted originally on the Archive of Our Own at https://archiveofourown.org/works/407062."
        )
        XCTAssertTrue(result.contains("archiveofourown.org"))
        XCTAssertFalse(result.contains("https://"))
        XCTAssertFalse(result.contains("/works/407062"))
        // Surrounding sentence must survive untouched.
        XCTAssertTrue(result.hasPrefix("Silence is Golden Posted originally on the Archive of Our Own at"))
    }

    func testURLFollowedByMoreProseKeepsTheProse() {
        let result = KokoroBoilerplateFilter.sanitizingURLs(
            in: "follow me for news and updates: http://wittyy-name.tumblr.com/ and I post there weekly."
        )
        XCTAssertTrue(result.contains("tumblr.com"))
        XCTAssertTrue(result.contains("and I post there weekly."))
        XCTAssertFalse(result.contains("http://"))
    }

    func testStandaloneURLBlockIsShortenedNotEmptied() {
        let result = KokoroBoilerplateFilter.sanitizingURLs(in: "http://www.youtube.com/watch?v=gpSEOj-dp9A")
        XCTAssertFalse(result.isEmpty)
        XCTAssertFalse(result.contains("gpSEOj-dp9A"))
        XCTAssertTrue(result.contains("youtube.com"))
    }

    func testChainedURLsWithNoSeparatorCollapseToOneHost() {
        // Real corpus example (nightvale-broadcast): four tumblr links glued
        // back-to-back with zero whitespace between them.
        let result = KokoroBoilerplateFilter.sanitizingURLs(
            in: "http://nikipaprika.tumblr.com/post/78916116313http://queenofthecute.tumblr.com/post/76087921384/hello"
        )
        XCTAssertLessThan(result.count, 40)
        XCTAssertFalse(result.contains("http"))
    }

    func testTextWithoutAURLIsUntouched() {
        let text = "She walked to the door and knocked twice before anyone answered."
        XCTAssertEqual(KokoroBoilerplateFilter.sanitizingURLs(in: text), text)
    }

    // MARK: - Wired into blocks(from:): the packer never speaks the label

    func testChapterNotesLabelNeverReachesSpokenOutput() {
        let units = [
            unit("Chapter 2", selector: "html > body > h2:nth-child(1)"),
            unit("Chapter Summary", selector: "html > body > p:nth-child(2)"),
            unit("Carlos and Charles argue about the puppy again.", selector: "html > body > blockquote:nth-child(3)"),
            unit("The real chapter begins here, with rain on the window.", selector: "html > body > p:nth-child(4)")
        ]
        let utterances = KokoroUtterancePacker.pack(units: units)
        let spoken = KokoroUtterancePacker.reconstructedText(from: utterances)
        XCTAssertFalse(spoken.contains("Chapter Summary"))
        XCTAssertTrue(spoken.contains("Carlos and Charles argue about the puppy again."))
        XCTAssertTrue(spoken.contains("The real chapter begins here"))
    }

    func testKudosPlugFooterNeverReachesSpokenOutput() {
        let units = [
            unit("The story's last line, quiet at last.", selector: "html > body > p:nth-child(1)"),
            unit("Please drop by the Archive and comment to let the creator know if you enjoyed their work!",
                 selector: "html > body > p:nth-child(2)")
        ]
        let utterances = KokoroUtterancePacker.pack(units: units)
        let spoken = KokoroUtterancePacker.reconstructedText(from: utterances)
        XCTAssertFalse(spoken.contains("drop by the Archive"))
        XCTAssertTrue(spoken.contains("The story's last line"))
    }

    private func unit(_ text: String, selector: String? = nil) -> TTSSpeechUnit {
        var locations = Locator.Locations()
        if let selector {
            locations.cssSelector = selector
        }
        return TTSSpeechUnit(
            text: text,
            locator: Locator(
                href: URL(string: "https://example.invalid/chapter.xhtml")!,
                mediaType: .xhtml,
                locations: locations,
                text: .init(highlight: text)
            )
        )
    }
}
#endif
