import Foundation
import Testing
@testable import Kudos

/// 1bu: the posted tag field is the chip order, the recent list is local, and
/// "From your other works" reads only the works it is handed.
struct WritingTagPickerTests {
    @Test func postedFieldKeepsDisplayedChipOrder() throws {
        var names = ["Zutara", "Kataang", "Zukka"]
        WritingTagReorder.move(&names, name: "Zukka", before: "Zutara")
        #expect(names == ["Zukka", "Zutara", "Kataang"])

        var tags = AO3WorkTagSet()
        tags.relationships = names
        let form = AO3EditTagsForm(
            workID: 1,
            actionURL: try #require(URL(string: "https://archiveofourown.org/works/1")),
            httpMethodOverride: "put",
            csrfToken: "token",
            tags: tags
        )
        let posted = form.parameters(submit: .update)
            .first { $0.0 == AO3WorkFormField.relationships }?.1
        #expect(posted == "Zukka, Zutara, Kataang")
        #expect(posted == AO3TagListDiff.joined(names))
    }

    @Test func recentTagsCapAtTwentyAndDedupe() throws {
        let suite = "WritingTagPickerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        var store = RecentWritingTags.load(from: defaults)
        for index in 0..<21 {
            store.record("tag-\(index)", kind: .fandom)
        }
        store.record("Fluff", kind: .freeform)
        store.record("Angst", kind: .freeform)
        store.record("fluff", kind: .freeform)
        store.record("Angst", kind: .freeform)
        store.record("ignored", kind: .tag)
        store.save(to: defaults)

        let loaded = RecentWritingTags.load(from: defaults)
        let fandoms = loaded.names(kind: .fandom)
        #expect(fandoms.count == RecentWritingTags.cap)
        #expect(fandoms.count == 20)
        #expect(fandoms.first == "tag-20")
        #expect(fandoms.last == "tag-1")
        #expect(!fandoms.contains("tag-0"))
        #expect(loaded.names(kind: .freeform) == ["Angst", "fluff"])
        #expect(loaded.names(kind: .tag).isEmpty)
        #expect(loaded.names(kind: .character).isEmpty)
    }

    /// The only input is the works array. There is no client and no URL on
    /// this function, so the suggestions cannot be a request.
    @Test func fromYourOtherWorksMakesNoRequest() {
        let works = [
            WritingOtherWorkTags.Source(
                workID: 1,
                fandoms: ["Naruto", " ", "Naruto"],
                characters: ["Sakura"],
                relationships: ["A/B"],
                additionalTags: ["Fluff"]
            ),
            WritingOtherWorkTags.Source(
                workID: 2,
                fandoms: ["Bleach", "Naruto"],
                characters: ["Ichigo"],
                relationships: ["C/D"],
                additionalTags: ["fluff", "Angst"]
            )
        ]
        #expect(
            WritingOtherWorkTags.names(
                kind: .fandom, works: works, excluding: ["naruto"], excludingWorkID: nil
            ) == ["Bleach"]
        )
        #expect(
            WritingOtherWorkTags.names(
                kind: .fandom, works: works, excluding: [], excludingWorkID: 2
            ) == ["Naruto"]
        )
        #expect(
            WritingOtherWorkTags.names(
                kind: .freeform, works: works, excluding: [], excludingWorkID: nil
            ) == ["Fluff", "Angst"]
        )
        #expect(
            WritingOtherWorkTags.names(
                kind: .character, works: works, excluding: [], excludingWorkID: 1
            ) == ["Ichigo"]
        )
        #expect(
            WritingOtherWorkTags.names(
                kind: .relationship, works: [], excluding: [], excludingWorkID: nil
            ).isEmpty
        )
        #expect(
            WritingOtherWorkTags.names(
                kind: .tag, works: works, excluding: [], excludingWorkID: nil
            ).isEmpty
        )
    }

    /// "Fluff" and "fluff" are both posted. Repeating the exact chip leaves
    /// the field alone. Suggestions still hide a case-variant of a chosen tag.
    @Test func exactSpellingsBothStayAndARepeatLeavesTheField() {
        let variant = WritingTagAddition.apply(name: "fluff", values: ["Fluff"], term: "fluff")
        #expect(variant.values == ["Fluff", "fluff"])
        #expect(variant.term.isEmpty)
        #expect(variant.recordedName == "fluff")

        let same = WritingTagAddition.apply(name: "Fluff", values: ["Fluff"], term: "Fluff")
        #expect(same.values == ["Fluff"])
        #expect(same.term == "Fluff")
        #expect(same.recordedName == nil)

        let padded = WritingTagAddition.apply(name: "  Fluff  ", values: ["Fluff"], term: "  Fluff  ")
        #expect(padded.values == ["Fluff"])
        #expect(padded.term == "  Fluff  ")
        #expect(padded.recordedName == nil)

        let blank = WritingTagAddition.apply(name: "   ", values: ["Fluff"], term: "   ")
        #expect(blank.values == ["Fluff"])
        #expect(blank.term == "   ")

        #expect(WritingTagAddition.excludesSuggestion("fluff", chosen: ["Fluff"]))
        #expect(!WritingTagAddition.excludesSuggestion("Angst", chosen: ["Fluff"]))
        #expect(!WritingTagAddition.excludesSuggestion("  ", chosen: ["Fluff"]))
    }

    /// Dragging onto the last chip used to insert in front of it, so the
    /// dragged chip could not become last.
    @Test func droppingOnTheLastChipPlacesTheDraggedChipLast() {
        var names = ["Zukka", "Zutara", "Kataang"]
        WritingTagReorder.move(&names, name: "Zukka", before: "Kataang")
        #expect(names == ["Zutara", "Kataang", "Zukka"])

        names = ["Zukka", "Zutara", "Kataang"]
        WritingTagReorder.move(&names, name: "Zutara", before: "Kataang")
        #expect(names == ["Zukka", "Kataang", "Zutara"])

        names = ["Zukka", "Zutara", "Kataang"]
        WritingTagReorder.move(&names, name: "Kataang", before: "Zutara")
        #expect(names == ["Zukka", "Kataang", "Zutara"])
    }

    /// Add and remove stay at least 44pt, and the editor's remove mark is a
    /// button of its own rather than a tap on the dragged chip.
    @Test func addAndRemoveChipsKeepAMinimumHitTarget() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let form = try String(
            contentsOf: root.appending(path: "kudos-ao3-reader/Features/Writing/WritingFormFields.swift"),
            encoding: .utf8
        )
        let editor = try String(
            contentsOf: root.appending(path: "kudos-ao3-reader/Features/Writing/WritingTagsEditor.swift"),
            encoding: .utf8
        )
        #expect(form.contains(".minimumHitTarget()"))
        #expect(editor.contains(".minimumHitTarget()"))
        #expect(editor.contains("accessibilityLabel(\"Remove \\(value)\")"))
        #expect(!editor.contains(".onTapGesture"))
    }

    @Test func accessibilityMovesAChipEarlierOrLater() {
        var names = ["Zukka", "Zutara", "Kataang"]
        WritingTagReorder.moveLater(&names, name: "Zukka")
        #expect(names == ["Zutara", "Zukka", "Kataang"])
        WritingTagReorder.moveLater(&names, name: "Zukka")
        #expect(names == ["Zutara", "Kataang", "Zukka"])
        WritingTagReorder.moveEarlier(&names, name: "Zukka")
        #expect(names == ["Zutara", "Zukka", "Kataang"])

        WritingTagReorder.moveEarlier(&names, name: "Zutara")
        #expect(names == ["Zutara", "Zukka", "Kataang"])
        WritingTagReorder.moveLater(&names, name: "Kataang")
        #expect(names == ["Zutara", "Zukka", "Kataang"])
    }
}
