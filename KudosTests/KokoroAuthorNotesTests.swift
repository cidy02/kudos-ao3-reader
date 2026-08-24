#if os(iOS)
import Foundation
import ReadiumShared
import Testing
@testable import Kudos

/// Author's notes are opt-out, and the opt-out has to be *precise* — reading a
/// note that was meant to be skipped is a much better failure than skipping a
/// chapter that was meant to be read.
@Suite("Author's note suppression", .serialized)
struct KokoroAuthorNotesTests {
    private func withReadNotes(_ value: Bool, _ body: () -> Void) {
        let previous = ReaderSpeechPreferences.readAuthorNotes
        ReaderSpeechPreferences.readAuthorNotes = value
        defer { ReaderSpeechPreferences.readAuthorNotes = previous }
        body()
    }

    /// A unit carrying a real CSS selector, because `classify` reads the
    /// selector off the locator — a `nil` locator can never produce
    /// `.blockquote`, and a fixture without one would leave the suppression
    /// branch completely unexercised while still passing.
    private func unit(_ text: String, selector: String? = nil) -> TTSSpeechUnit {
        guard let selector else { return TTSSpeechUnit(text: text, locator: nil) }
        return TTSSpeechUnit(
            text: text,
            locator: Locator(
                href: AnyURL(string: "chapter.xhtml")!,
                mediaType: .xhtml,
                locations: .init(otherLocations: ["cssSelector": .string(selector)])
            )
        )
    }

    /// AO3's export shape: a bare `Notes` heading, the note inside a
    /// blockquote, then the story.
    private func notedWork() -> [TTSSpeechUnit] {
        [
            unit("Notes"),
            unit("Content warning: this chapter is rough.", selector: "blockquote"),
            unit("The corridor was empty when she reached it.", selector: "p"),
        ]
    }

    @Test func defaultReadsNotes() {
        #expect(ReaderSpeechPreferences.readAuthorNotes == true)
    }

    /// The bare heading was always dropped, in both modes — it is furniture,
    /// not content.
    @Test func headingIsNeverSpoken() {
        for reads in [true, false] {
            withReadNotes(reads) {
                let blocks = KokoroSemanticDocument.blocks(from: notedWork())
                #expect(!blocks.contains { $0.text == "Notes" })
            }
        }
    }

    /// The note *body* is spoken by default. This is the behaviour that
    /// existed before the setting, and content warnings depend on it.
    @Test func noteBodyIsSpokenByDefault() {
        withReadNotes(true) {
            let blocks = KokoroSemanticDocument.blocks(from: notedWork())
            #expect(blocks.contains { $0.text.contains("Content warning") })
        }
    }

    /// Story text after a note must survive suppression — the failure mode
    /// that matters.
    @Test func storyAfterANoteIsNeverSuppressed() {
        for reads in [true, false] {
            withReadNotes(reads) {
                let blocks = KokoroSemanticDocument.blocks(from: notedWork())
                #expect(
                    blocks.contains { $0.text.contains("corridor") },
                    "story content lost with readAuthorNotes=\(reads)"
                )
            }
        }
    }

    /// A long work with no heading after the note must not lose its narrative.
    /// Suppressing "until the next heading" would have: measured, the gap has
    /// a median of 38 blocks and over half of notes never reach one.
    @Test func aNoteFollowedByManyParagraphsLosesNone() {
        withReadNotes(false) {
            var units = [TTSSpeechUnit(text: "Chapter Notes", locator: nil)]
            units += (0 ..< 40).map {
                TTSSpeechUnit(text: "Narrative paragraph number \($0) continues.", locator: nil)
            }
            let blocks = KokoroSemanticDocument.blocks(from: units)
            let spoken = blocks.map(\.text).joined(separator: " ")
            for index in 0 ..< 40 {
                #expect(spoken.contains("number \(index) "), "lost paragraph \(index)")
            }
        }
    }

    /// The actual opt-out. Without a real blockquote selector this branch
    /// never runs, so this is the test the feature lives or dies by.
    @Test func noteBodyIsSuppressedWhenOptedOut() {
        withReadNotes(false) {
            let blocks = KokoroSemanticDocument.blocks(from: notedWork())
            #expect(!blocks.contains { $0.text.contains("Content warning") })
            #expect(blocks.contains { $0.text.contains("corridor") })
        }
    }

    /// A blockquote that is *not* preceded by a note heading is ordinary
    /// content — a pull quote, an in-story letter — and must still be read.
    @Test func anUnrelatedBlockquoteIsNeverSuppressed() {
        withReadNotes(false) {
            let blocks = KokoroSemanticDocument.blocks(from: [
                unit("She unfolded the letter.", selector: "p"),
                unit("My dearest, the war is over.", selector: "blockquote"),
            ])
            #expect(blocks.contains { $0.text.contains("dearest") })
        }
    }

    @Test func theArchiveClosingPlugIsAlwaysDropped() {
        let plug = "Please drop by the Archive and comment to let the creator know if you enjoyed their work!"
        #expect(KokoroBoilerplateFilter.isBoilerplate(plug))
        // ...but it is not a note heading, so it must not open a suppression span.
        #expect(!KokoroBoilerplateFilter.isNoteLabel(plug))
    }

    @Test func noteHeadingsAreRecognised() {
        for label in ["Notes", "Summary", "End Notes", "Chapter Notes", "Chapter Summary"] {
            #expect(KokoroBoilerplateFilter.isNoteLabel(label), "\(label) not recognised")
        }
        #expect(!KokoroBoilerplateFilter.isNoteLabel("Notes on the war were scarce."))
    }
}
#endif
