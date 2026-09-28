import Foundation
import Testing
@testable import Kudos

private final class SeriesCollectionsBundleAnchor {}

/// T-270: the work form's Current Series, the collections it posts and
/// searches, and 1br's reorder-row metadata. Markup follows otwarchive's
/// `works/_standard_form.html.erb` and `series/_series_order.html.erb`.
@MainActor
struct WritingSeriesCollectionsTests {
    private func editForm(currentSeries: String = "") throws -> AO3WorkForm {
        let url = try #require(
            Bundle(for: SeriesCollectionsBundleAnchor.self).url(forResource: "ao3_work_edit", withExtension: "html")
        )
        var html = try String(contentsOf: url, encoding: .utf8)
        html = html.replacingOccurrences(
            of: "<option selected=\"selected\" value=\"77\">", with: "<option value=\"77\">"
        )
        if !currentSeries.isEmpty {
            let anchor = "<dd><input type=\"text\" name=\"work[series_attributes][title]\""
            let range = try #require(html.range(of: anchor))
            let end = try #require(html.range(of: "</dd>", range: range.upperBound..<html.endIndex))
            html.insert(contentsOf: currentSeries, at: end.upperBound)
        }
        return try AO3Client.parseWorkForm(from: html)
    }

    /// `_standard_form`: `<dt>Current Series</dt>`, then per membership a
    /// series link and `link_to "Remove Work From Series", serial_work_path(serial), method: :delete`.
    static let currentSeriesMarkup = """
    <dt>Current Series</dt>
    <dd><ul class="actions" role="navigation">
      <li><a href="/series/77">Water</a></li>
      <li><a rel="nofollow" data-method="delete" href="/serial_works/4401">Remove Work From Series</a></li>
    </ul></dd>
    <dd><ul class="actions" role="navigation">
      <li><a href="/series/91">Salt</a></li>
      <li><a rel="nofollow" data-method="delete" href="/serial_works/4402">Remove Work From Series</a></li>
    </ul></dd>
    """

    @Test func theWorkFormReadsItsCurrentSeriesAndPostsNoneOfIt() throws {
        let form = try editForm(currentSeries: Self.currentSeriesMarkup)
        #expect(form.currentSeries == [
            AO3CurrentSeries(seriesID: 77, title: "Water", serialWorkID: 4401),
            AO3CurrentSeries(seriesID: 91, title: "Salt", serialWorkID: 4402)
        ])
        // Nothing picked: the select and title go blank, which
        // `Work#series_attributes=` reads as "add nothing".
        let params = Dictionary(form.parameters(submit: .update), uniquingKeysWith: { $1 })
        #expect(params[AO3WorkFormField.seriesID] == "")
        #expect(params[AO3WorkFormField.seriesTitle] == "")
        #expect(!form.parameters(submit: .update).contains { $0.0.contains("serial") })
        #expect(WorkEditView.seriesValue(current: form.currentSeries.map(\.title), adding: nil) == "Water, Salt")
        #expect(try editForm().currentSeries.isEmpty)
    }

    @Test func theSeriesRowNamesWhatIsAndWhatSavingAdds() {
        #expect(WorkEditView.seriesValue(current: [], adding: nil) == "None")
        #expect(WorkEditView.seriesValue(current: [], adding: "Salt") == "Adding Salt")
        #expect(WorkEditView.seriesValue(current: ["Water"], adding: "Salt") == "Water + Salt")
        #expect(WorkSeriesPickerView.membershipText(workTitle: "Tide", count: 1) == "Tide is part of one series")
        #expect(WorkSeriesPickerView.membershipText(workTitle: "Tide", count: 2) == "Tide is part of 2 series")
    }

    // MARK: Collections

    /// The picker edits `collections`; the payload used to post
    /// `collectionNames` as parsed, so a tick or untick never reached AO3.
    @Test func theCollectionsPickerDecidesWhatIsPosted() throws {
        var form = try editForm()
        func posted() -> String? {
            Dictionary(form.parameters(submit: .update), uniquingKeysWith: { $1 })[AO3WorkFormField.collectionNames]
        }
        #expect(posted() == "nanami_week")
        form.collections[0].isSelected = false
        #expect(posted() == "")
        form.collections.append(AO3CollectionOffer(
            name: "slowburn_2026", title: "Slow Burn Exchange 2026", access: AO3CollectionAccess(), isSelected: true
        ))
        #expect(posted() == "slowburn_2026")
    }

    @Test func searchingAllCollectionsUsesTheWorkFormsOwnAutocomplete() throws {
        let url = try #require(AO3Client.openCollectionNamesURL(term: " slow burn "))
        #expect(url.absoluteString == "https://archiveofourown.org/autocomplete/open_collection_names?term=slow%20burn")
        #expect(AO3Client.openCollectionNamesURL(term: "  ") == nil)
        // `AutocompleteController#open_collection_names`: id is the name,
        // name is "Title (name)".
        let json = Data(#"""
        [{"id":"slowburn_2026","name":"Slow Burn Exchange 2026 (slowburn_2026)"},
         {"id":"nanami_week","name":"Nanami Week (nanami_week)"}]
        """#.utf8)
        let found = try AO3Client.parseOpenCollectionNames(json)
        #expect(found.map(\.name) == ["slowburn_2026", "nanami_week"])
        #expect(found.map(\.title) == ["Slow Burn Exchange 2026", "Nanami Week"])
        #expect(found.allSatisfy { !$0.isSelected && $0.access.rowState == .unknown })
        let held = [AO3CollectionOffer(name: "Nanami_Week", title: "", access: AO3CollectionAccess())]
        #expect(WorkCollectionsGiftsView.newOffers(found, excluding: held).map(\.name) == ["slowburn_2026"])
    }

    /// A collection is one name. The work is in `salt`; the writer also runs a
    /// collection titled "Salt" named `salt_exchange`. Matching titles ticked
    /// that one too, and Save posted the work into it. What posts is the names
    /// the form loaded, a closed one missing from the writer's page included.
    @Test func onlyTheNamesTheFormLoadedAreTicked() throws {
        var form = try editForm()
        form.collectionNames = ["salt", "gift_swap_2025"]
        form = form.applyingCollectionStates([
            AO3CollectionOffer(name: "salt_exchange", title: "Salt", access: AO3CollectionAccess(isUnrevealed: true)),
            AO3CollectionOffer(name: "Salt", title: "Salt Flats", access: AO3CollectionAccess())
        ])
        #expect(form.collections.map(\.name) == ["salt_exchange", "Salt", "gift_swap_2025"])
        #expect(form.collections.map(\.isSelected) == [false, true, true])
        #expect(form.postedCollectionNames == ["Salt", "gift_swap_2025"])
    }

    /// AO3's open-collection autocomplete is every collection that is not
    /// closed — moderated, unrevealed and anonymous ones too — so a hit says
    /// so, and is added unticked: the writer ticks it or it is not posted.
    @Test func aSearchHitIsAddedUntickedAndSaysWhatAO3DidNotTell() throws {
        let found = try AO3Client.parseOpenCollectionNames(Data(#"[{"id":"salt_exchange","name":"Salt (salt_exchange)"}]"#.utf8))
        let hit = try #require(found.first)
        let text = WorkCollectionsGiftsView.stateText(hit.access)
        #expect(text.contains("moderated") && text.contains("unrevealed"))
        var form = try editForm()
        form.collections = WorkCollectionsGiftsView.adding(hit, to: form.collections)
        #expect(form.collections.map(\.name) == ["nanami_week", "salt_exchange"])
        #expect(form.collections.last?.isSelected == false)
        #expect(form.postedCollectionNames == ["nanami_week"])
    }

    // MARK: 1br reorder metadata

    private func row(_ serial: Int, _ title: String, position: Int, draft: Bool = false) -> AO3SeriesWorkRow {
        AO3SeriesWorkRow(workID: nil, serialWorkID: serial, title: title, position: position, isDraft: draft)
    }

    private func blurb(_ id: Int, _ title: String, words: Int?, date: String) -> AO3WorkSummary {
        AO3WorkSummary(
            id: id, title: title, authors: [], fandoms: [], rating: "", warnings: [], categories: [],
            isComplete: nil, dateUpdated: date, tags: [], summary: "", language: "", words: words, chapters: ""
        )
    }

    @Test func reorderRowsTakeWordsAndDatesFromTheSeriesPage() {
        let rows = [
            row(33, "Long Way", position: 3),
            row(11, "Salt and Static", position: 1),
            row(22, "Untitled (DRAFT)", position: 2, draft: true)
        ]
        let works = [
            blurb(300, "Long Way", words: 30_280, date: "12 Aug 2024"),
            blurb(100, "Salt and Static", words: 4200, date: "09 Jan 2023")
        ]
        let joined = AO3SeriesWorkRow.attachingBlurbs(works, to: rows)
        #expect(joined.map(\.serialWorkID) == [11, 22, 33])
        #expect(joined.map(\.metadataText) == ["4,200 words · 09 Jan 2023", nil, "30,280 words · 12 Aug 2024"])
        // Display only: the reorder write still has no work id to trust.
        #expect(joined.allSatisfy { $0.workID == nil })
        #expect(AO3SeriesWorkRow.attachingBlurbs([], to: rows).allSatisfy { $0.metadataText == nil })

        let fresh = [row(33, "Long Way", position: 2), row(11, "Salt and Static", position: 1)]
        let kept = SeriesRemoveWorksView.keepingMetadata(of: joined, on: fresh)
        #expect(kept.map(\.serialWorkID) == [11, 33])
        #expect(kept.map(\.metadataText) == ["4,200 words · 09 Jan 2023", "30,280 words · 12 Aug 2024"])
    }

    /// `series/_series_order` as AO3 renders it: the row is `li#serial_<id>`,
    /// its title the `h3.heading` text, and only a draft gets
    /// `draft_work_title` ("%{title} (DRAFT)"). A posted work named "Draft
    /// Notes" is not a draft, so it still takes its words and date.
    @Test func manageRowsAreAO3sOwnAndOnlyTheDraftSuffixMarksADraft() throws {
        let html = """
        <html><body><div id="main"><h2 class="heading">Manage Series: Water</h2>
        <div id="manage-series"><form action="/series/77/update_positions" method="post">
        <ul id="sortable_series_list">
          <li id="serial_11" class="serial-position-list">
            <input type="text" name="serial_works[]" size="3" maxlength="3" class="number serial-position-field" id="serial_0">
            <span id='position-for-11'>1</span>.
            <h3 class="heading">
              Draft Notes
            </h3>
          </li>
          <li id="serial_22" class="serial-position-list">
            <input type="text" name="serial_works[]" size="3" maxlength="3" class="number serial-position-field" id="serial_1">
            <span id='position-for-22'>2</span>.
            <h3 class="heading">
              Tide (DRAFT)
            </h3>
          </li>
        </ul>
        <p class="submit actions"><input type="submit" name="commit" value="Update Positions"></p>
        </form></div></div></body></html>
        """
        let rows = try AO3Client.parseSeriesManagePage(from: html)
        #expect(rows.map(\.serialWorkID) == [11, 22])
        #expect(rows.map(\.title) == ["Draft Notes", "Tide (DRAFT)"])
        #expect(rows.map(\.isDraft) == [false, true])
        let joined = AO3SeriesWorkRow.attachingBlurbs([blurb(100, "Draft Notes", words: 900, date: "01 Feb 2024")], to: rows)
        #expect(joined.map(\.metadataText) == ["900 words · 01 Feb 2024", nil])
    }
}
