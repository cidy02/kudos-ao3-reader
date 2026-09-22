import Foundation
import Testing
@testable import Kudos

/// 1q's pure piece: which pill a bookmark survives. Nothing here signs in
/// or posts. The note check goes through `AO3RichText`, not a Bool the test
/// invented, so an empty note cannot pass "With notes" by being mislabeled
/// on the way in.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct AO3BookmarksWorksBrowserTests {
    private func notes(_ text: String) -> AO3RichText {
        AO3RichText(blocks: [
            AO3RichText.Block(
                kind: .paragraph,
                runs: [AO3RichText.Run(text: text, isBold: false, isItalic: false, link: nil)],
                id: 0
            )
        ])
    }

    /// Each pill keeps the rows it names and drops the others. A bookmark
    /// that is a rec, private, and noted belongs to all three narrowed pills;
    /// the pills do not steal it from each other. A plain bookmark is All only.
    @Test func eachPillKeepsOnlyItsBookmarks() {
        let plain = (isRecommendation: false, isPrivate: false, notes: AO3RichText())
        let recOnly = (isRecommendation: true, isPrivate: false, notes: AO3RichText())
        let privateOnly = (isRecommendation: false, isPrivate: true, notes: AO3RichText())
        let notesOnly = (isRecommendation: false, isPrivate: false, notes: notes("a note"))
        let allThree = (isRecommendation: true, isPrivate: true, notes: notes("both"))

        for sample in [plain, recOnly, privateOnly, notesOnly, allThree] {
            #expect(kept(sample, by: .all))
        }

        #expect(kept(recOnly, by: .recs))
        #expect(kept(allThree, by: .recs))
        #expect(!kept(privateOnly, by: .recs))
        #expect(!kept(notesOnly, by: .recs))
        #expect(!kept(plain, by: .recs))

        #expect(kept(privateOnly, by: .`private`))
        #expect(kept(allThree, by: .`private`))
        #expect(!kept(recOnly, by: .`private`))
        #expect(!kept(notesOnly, by: .`private`))
        #expect(!kept(plain, by: .`private`))

        #expect(kept(notesOnly, by: .withNotes))
        #expect(kept(allThree, by: .withNotes))
        #expect(!kept(recOnly, by: .withNotes))
        #expect(!kept(privateOnly, by: .withNotes))
        #expect(!kept(plain, by: .withNotes))
    }

    /// The footnote uses the same predicate as `SensitiveWorkRow`'s blur.
    /// Revealed, not adult, privacy off, and Hide mode (the list drops the
    /// row before this screen) all leave the footnote up. Only an unrevealed
    /// adult work in Blur mode takes it down.
    @Test func footnoteFollowsTheRowBlur() {
        #expect(AO3BookmarksMatureBlur.isBlurred(
            isAdult: true, hideMature: true, mode: .obscure, isRevealed: false
        ))
        #expect(!AO3BookmarksMatureBlur.isBlurred(
            isAdult: true, hideMature: true, mode: .obscure, isRevealed: true
        ))
        #expect(!AO3BookmarksMatureBlur.isBlurred(
            isAdult: false, hideMature: true, mode: .obscure, isRevealed: false
        ))
        #expect(!AO3BookmarksMatureBlur.isBlurred(
            isAdult: true, hideMature: false, mode: .obscure, isRevealed: false
        ))
        #expect(!AO3BookmarksMatureBlur.isBlurred(
            isAdult: true, hideMature: true, mode: .hide, isRevealed: false
        ))
    }

    /// The case a Bool passed in from the view could not catch: the note is
    /// empty, including a note element whose only text is whitespace.
    /// `!notes.blocks.isEmpty` would keep the whitespace row.
    @Test func withNotesExcludesEmptyNotes() {
        #expect(!AO3BookmarksFilter.withNotes.includes(
            isRecommendation: true,
            isPrivate: true,
            notes: AO3RichText()
        ))
        #expect(!AO3BookmarksFilter.withNotes.includes(
            isRecommendation: false,
            isPrivate: false,
            notes: notes("  \n\t")
        ))
        #expect(AO3BookmarksFilter.withNotes.includes(
            isRecommendation: false,
            isPrivate: false,
            notes: notes("not empty")
        ))
    }

    private func kept(
        _ sample: (isRecommendation: Bool, isPrivate: Bool, notes: AO3RichText),
        by filter: AO3BookmarksFilter
    ) -> Bool {
        filter.includes(
            isRecommendation: sample.isRecommendation,
            isPrivate: sample.isPrivate,
            notes: sample.notes
        )
    }
}
}
