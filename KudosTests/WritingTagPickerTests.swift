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
}
