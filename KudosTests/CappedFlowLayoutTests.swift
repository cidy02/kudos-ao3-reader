import CoreGraphics
import Testing
@testable import Kudos

/// 1g's two-row chip cluster: chips wrap, stop at two rows, and the trailing
/// "+N more" chip always keeps a place after the ones that fit.
struct CappedFlowLayoutTests {
    private let layout = CappedFlowLayout(spacing: 10, rowSpacing: 5, maxRows: 2)
    private let chip = CGSize(width: 40, height: 20)

    @Test func stopsAtTwoRowsAndKeepsTheTrailingChip() {
        // Width 100 holds two 40s per row (40 + 10 + 40). Five chips + trailing
        // need three rows, so chips drop until the trailing one fits on row two.
        let result = layout.arrange(sizes: Array(repeating: chip, count: 5), trailing: chip, width: 100)
        #expect(result.fitCount == 3)
        #expect(result.trailing == CGPoint(x: 50, y: 25))
        #expect(result.origins.compactMap { $0 } == [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 0, y: 25)])
        #expect(result.origins.suffix(2).allSatisfy { $0 == nil })
        #expect(result.size == CGSize(width: 90, height: 45))
    }

    @Test func everythingFitsWhenThereIsRoom() {
        let result = layout.arrange(sizes: [chip, chip], trailing: .zero, width: 400)
        #expect(result.fitCount == 2)
        #expect(result.size.height == 20)
    }
}

/// Kickers print the fandom without its disambiguation (owner, 2026-09-28).
struct FandomBareTitleTests {
    @Test func dropsTheQualifierAndKeepsTheDisplaySegment() {
        #expect(FandomDisplayName.bareTitle("Doctor Who (2005)") == "Doctor Who")
        #expect(FandomDisplayName.bareTitle("NARUTO (Anime & Manga)") == "NARUTO")
        #expect(FandomDisplayName.bareTitle("Star Wars - All Media Types") == "Star Wars")
        #expect(FandomDisplayName.bareTitle("僕のヒーローアカデミア | Boku no Hero Academia | My Hero Academia")
            == "My Hero Academia")
        #expect(FandomDisplayName.bareTitle("Haikyuu!!") == "Haikyuu!!")
    }

    /// Two tags that shorten to one name keep their disambiguation side by side.
    @Test func keepsTheQualifierWhenTwoNamesWouldCollide() {
        let names = ["Doctor Who (2005)", "Doctor Who", "Haikyuu!!"]
        #expect(FandomDisplayName.bareTitle("Doctor Who (2005)", among: names) == "Doctor Who (2005)")
        #expect(FandomDisplayName.bareTitle("Doctor Who", among: names) == "Doctor Who")
        #expect(FandomDisplayName.bareTitle("Haikyuu!!", among: names) == "Haikyuu!!")
        #expect(FandomDisplayName.bareTitle("Doctor Who (2005)", among: ["Doctor Who (2005)"]) == "Doctor Who")
    }
}

struct LibraryChipLabelTests {
    @Test func aLowerWordBoundReadsAsACompactSize() {
        #expect(LibraryFilters.minimumWordsLabel("50000") == "50K+ words")
        #expect(LibraryFilters.minimumWordsLabel("abc") == "Words ≥ abc")
    }

    @Test func affinityTilesTakeTwoLetters() {
        #expect(FavoriteAffinityRow.initials("Good Omens") == "GO")
        #expect(FavoriteAffinityRow.initials("Haikyuu!!") == "HA")
    }
}

struct AO3CollectionDeleteConfirmationTests {
    @Test func deleteNeedsTheNameTypedExactly() {
        #expect(AO3CollectionFormView.confirmsDeletion(typed: "Slow Burn Exchange", name: "Slow Burn Exchange"))
        #expect(AO3CollectionFormView.confirmsDeletion(typed: " Slow Burn Exchange ", name: "Slow Burn Exchange"))
        #expect(!AO3CollectionFormView.confirmsDeletion(typed: "slow burn exchange", name: "Slow Burn Exchange"))
        #expect(!AO3CollectionFormView.confirmsDeletion(typed: "", name: ""))
        #expect(AO3CollectionFormView.deletionMessage.contains("anonymous show their creators"))
    }
}

@MainActor
struct LibraryFandomFamilyFilterTests {
    @Test func aFamilyChipMatchesEverySiblingTag() {
        let work = SavedWork(title: "W", author: "A")
        work.workFandoms = ["Doctor Who (2005)"]
        var filters = LibraryFilters()
        filters.fandoms = ["Doctor Who"]
        #expect(filters.matches(work))
        filters.fandoms = ["Frozen (Disney Movies)"]
        #expect(!filters.matches(work))
    }
}
