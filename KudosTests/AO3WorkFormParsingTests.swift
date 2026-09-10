import Foundation
import Testing
@testable import Kudos

private final class WorkFormBundleAnchor {}

struct AO3WorkFormParsingTests {
    private func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle(for: WorkFormBundleAnchor.self).url(forResource: name, withExtension: "html")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func parsesWorkEditFormGroups() throws {
        let form = try AO3Client.parseWorkForm(from: try fixture("ao3_work_edit"))

        #expect(form.kind == .edit)
        #expect(form.workID == 424242)
        #expect(form.actionURL.path == "/works/424242")
        #expect(form.httpMethodOverride == "patch")
        #expect(form.csrfToken == "work-csrf-token==")
        #expect(form.isPosted)
        #expect(!form.isDraft)

        // Required
        #expect(form.title == "The Weight of Water")
        #expect(form.rating == "Explicit")
        #expect(form.warnings == ["Choose Not To Use Archive Warnings"])
        #expect(form.warningOptions.first?.value == "Choose Not To Use Archive Warnings")
        #expect(form.fandoms == ["Jujutsu Kaisen", "Haikyuu!!"])
        #expect(form.languageID == "1")

        // Tags — order preserved
        #expect(form.categories == ["F/M", "M/M"])
        #expect(form.categoryOptions.count == 6)
        #expect(form.relationships == ["Geto/Gojo", "Hinata/Kageyama"])
        #expect(form.characters == ["Gojo Satoru", "Geto Suguru"])
        #expect(form.additionalTags == ["Hurt/Comfort", "Original Tag That Is New"])

        // Association
        #expect(form.collectionNames == ["nanami_week"])
        #expect(form.gifts.map(\.name) == ["giftee"])
        #expect(form.series.contains(where: { $0.seriesID == 77 && $0.isSelected }))
        #expect(form.parentWork.title == "First Rain")

        // Text
        #expect(form.summary.contains("long walk"))
        #expect(form.notes == "Thanks for reading.")
        #expect(form.endnotes == "More later.")

        // Publication
        #expect(form.chapterTotal == "20")
        #expect(form.isChaptered)
        #expect(!form.restricted)
        #expect(form.moderatedCommenting)
        #expect(form.commentPermissions == "disable_anon")
        #expect(form.missingRequiredFields().isEmpty)
    }

    @Test func missingRequiredFieldsNamesWhatPostNeeds() throws {
        let form = try AO3Client.parseWorkForm(from: try fixture("ao3_work_new_draft"))
        #expect(form.kind == .new)
        #expect(form.isDraft)
        #expect(!form.isPosted)
        let missing = form.missingRequiredFields()
        #expect(missing.contains("Title"))
        #expect(missing.contains("Rating"))
        #expect(missing.contains("Archive Warning"))
        #expect(missing.contains("Fandoms"))
        #expect(missing.contains("Language"))
        #expect(missing.contains("Work Text"))
    }

    @Test func tagRemovalIsADiffNotADeleteAPI() {
        let current = AO3WorkTagSet(
            rating: "Teen And Up Audiences",
            warnings: ["No Archive Warnings Apply"],
            fandoms: ["Haikyuu!!", "Jujutsu Kaisen"],
            additionalTags: ["Hurt/Comfort", "Fluff"]
        )
        let desired = AO3WorkTagSet(
            rating: "Teen And Up Audiences",
            warnings: ["No Archive Warnings Apply"],
            fandoms: ["Jujutsu Kaisen"],
            additionalTags: ["Hurt/Comfort", "Found Family"]
        )
        let diff = current.diff(toward: desired)
        #expect(diff.fandomsRemoved == ["Haikyuu!!"])
        #expect(diff.fandomsAdded.isEmpty)
        #expect(diff.additionalRemoved == ["Fluff"])
        #expect(diff.additionalAdded == ["Found Family"])
        #expect(diff.rating == nil)
        // POST is the full replacement set, not a per-tag delete.
        let params = Dictionary(uniqueKeysWithValues: desired.parameters())
        #expect(params[AO3WorkFormField.fandoms] == "Jujutsu Kaisen")
        #expect(params[AO3WorkFormField.additionalTags] == "Hurt/Comfort, Found Family")
        #expect(!params.keys.contains(where: { $0.contains("delete") }))
    }

    @Test func bulkAddRemoveLeavesBlankFieldsUntouchedAndMarksOverwrites() throws {
        let form = try AO3Client.parseBulkEditForm(from: try fixture("ao3_edit_multiple"))
        #expect(form.workIDs == [11, 22, 33])
        #expect(form.csrfToken == "bulk-csrf==")
        #expect(form.httpMethodOverride == "patch")
        #expect(form.actionURL.path.contains("update_multiple"))

        var changes = AO3BulkEditChanges(workIDs: form.workIDs)
        changes.tagsToAdd.fandoms = ["Doctor Who"]
        changes.tagsToRemove.fandoms = ["Haikyuu!!"]
        changes.rating = "Explicit"
        // language left nil — not an overwrite this save

        #expect(changes.isOverwriteField(AO3WorkFormField.rating))
        #expect(changes.isOverwriteField(AO3WorkFormField.languageID))
        #expect(!changes.isOverwriteField(AO3WorkFormField.fandoms))

        let params = changes.parameters(csrfToken: form.csrfToken)
        let dict = Dictionary(uniqueKeysWithValues: params.filter { $0.0 != AO3WorkFormField.workIDs })
        #expect(dict[AO3WorkFormField.fandoms] == "Doctor Who")
        #expect(dict[AO3WorkFormField.rating] == "Explicit")
        #expect(dict[AO3WorkFormField.languageID] == nil)
        #expect(params.filter { $0.0 == AO3WorkFormField.workIDs }.map(\.1) == ["11", "22", "33"])

        let applied = changes.applying(
            to: AO3WorkTagSet(fandoms: ["Haikyuu!!", "Jujutsu Kaisen"])
        )
        #expect(applied.fandoms == ["Jujutsu Kaisen", "Doctor Who"])
        #expect(applied.rating == "Explicit")
    }

    @Test func seriesReorderBuildsNWritesInOrder() {
        let writes = AO3SeriesReorderPlan.writes(
            seriesID: 77,
            orderedWorkIDs: [200, 100, 300],
            serialByWorkID: [100: 11, 200: 22, 300: 33]
        )
        #expect(writes.count == 3)
        #expect(writes.map(\.position) == [1, 2, 3])
        #expect(writes.map(\.serialWorkID) == [22, 11, 33])
        #expect(writes.compactMap(\.workID) == [200, 100, 300])
        #expect(writes.allSatisfy { $0.orderedSerialWorkIDs == [22, 11, 33] })
        #expect(writes[0].path == "/series/77/update_positions")
        let body = writes[1].parameters(csrfToken: "tok")
        #expect(body.filter { $0.0 == AO3WorkFormField.serialOrder }.map(\.1) == ["22", "11", "33"])
    }

    @Test func parsesChapterFormAndOmitsPositionWhenAbsent() {
        let html = """
        <html><head><meta name="csrf-token" content="ch=="></head>
        <body><div id="chapter-form" class="verbose post work chapter">
        <form action="/works/424242/chapters" method="post">
          <input type="hidden" name="authenticity_token" value="ch==">
          <input type="text" name="chapter[title]" value="Arrival">
          <textarea name="chapter[summary]">Later that night.</textarea>
          <textarea name="chapter[notes]">hi</textarea>
          <textarea name="chapter[endnotes]">bye</textarea>
          <textarea name="chapter[content]" id="content">It rained.</textarea>
          <input type="text" name="chapter[wip_length]" value="13">
          <input type="submit" name="save_button" value="Save As Draft">
          <input type="submit" name="post_without_preview_button" value="Post">
        </form></div></body></html>
        """
        let form = try #require(try? AO3Client.parseChapterForm(from: html))
        #expect(form.workID == 424242)
        #expect(form.chapterID == nil)
        #expect(form.title == "Arrival")
        #expect(form.content == "It rained.")
        #expect(form.wipLength == "13")
        #expect(!form.includePosition)
        let params = Dictionary(uniqueKeysWithValues: form.parameters(submit: .postWithoutPreview))
        #expect(params[AO3WorkFormField.chapterPosition] == nil)
        #expect(params[AO3WorkFormField.chapterWipLength] == "13")
    }

    @Test func parsesSeriesManageOrder() {
        let html = """
        <html><head><meta name="csrf-token" content="s=="></head>
        <body>
        <div id="manage-series">
          <form action="/series/77/update_positions" method="post">
            <ul id="sortable_series_list">
              <li id="serial_11" class="serial-position-list">
                <span id="position-for-11">1</span>.
                <h3 class="heading"><a href="/works/100">The Weight of Water</a></h3>
              </li>
              <li id="serial_22" class="serial-position-list">
                <span id="position-for-22">2</span>.
                <h3 class="heading"><a href="/works/200">Salt and Static</a></h3>
              </li>
              <li id="serial_33" class="serial-position-list">
                <span id="position-for-33">3</span>.
                <h3 class="heading"><a href="/works/300">Long Way from Home</a></h3>
              </li>
            </ul>
          </form>
        </div>
        </body></html>
        """
        let rows = try #require(try? AO3Client.parseSeriesManagePage(from: html))
        #expect(rows.map(\.serialWorkID) == [11, 22, 33])
        #expect(rows.map(\.workID) == [100, 200, 300])
        #expect(rows.map(\.position) == [1, 2, 3])
    }

    @Test func parsesCollectionRowStateOnTheBlurb() {
        let html = """
        <ul>
          <li class="collection picture blurb group">
            <h4 class="heading"><a href="/collections/slow_burn">Slow Burn Exchange 2026</a>
              <span class="name">(slow_burn)</span></h4>
            <p class="type">(Open, Moderated, Unrevealed)</p>
          </li>
          <li class="collection picture blurb group">
            <h4 class="heading"><a href="/collections/closed_bang">Jujutsu Kaisen Big Bang 2025</a></h4>
            <p class="type">(Closed, Unmoderated)</p>
          </li>
          <li class="collection picture blurb group">
            <h4 class="heading"><a href="/collections/nanami_week">Nanami Week</a></h4>
            <p class="type">(Open, Unmoderated)</p>
          </li>
        </ul>
        """
        let offers = try #require(try? AO3Client.parseCollectionOffers(from: html))
        #expect(offers.count == 3)
        #expect(offers[0].access.rowState == .moderated)
        #expect(offers[0].access.isUnrevealed)
        #expect(offers[1].access.rowState == .closed)
        #expect(offers[2].access.rowState == .open)
    }

    @Test func parsesDeleteConfirmCountsWhenPresent() {
        let html = """
        <html><head><meta name="csrf-token" content="del=="></head>
        <body>
          <h2 class="heading">Delete Work</h2>
          <form class="simple destroy" action="/works/424242" method="post">
            <input type="hidden" name="_method" value="delete">
            <input type="hidden" name="authenticity_token" value="del==">
            <p class="caution notice">Are you sure you want to delete "The Weight of Water" permanently?
              This cannot be undone. 12 chapters, 3812 kudos, 400 comments, and 90 bookmarks will be lost.
              84120 words.</p>
            <p class="actions"><input type="submit" value="Yes, Delete Work"></p>
          </form>
          <dl class="stats">
            <dd class="chapters">12/20</dd>
            <dd class="kudos">3,812</dd>
            <dd class="comments">400</dd>
            <dd class="bookmarks">90</dd>
            <dd class="words">84,120</dd>
          </dl>
        </body></html>
        """
        let implications = try #require(try? AO3Client.parseDeleteImplications(from: html))
        #expect(implications.title == "The Weight of Water")
        #expect(!implications.isDraft)
        #expect(implications.httpMethodOverride == "delete")
        #expect(implications.chapters == 12)
        #expect(implications.kudos == 3812)
        #expect(implications.comments == 400)
        #expect(implications.bookmarks == 90)
        #expect(implications.words == 84120)
    }

    @Test func draftsURLIsItsOwnIndexNotAWorksFilter() {
        #expect(
            AO3Client.myDraftsURL(username: "tester", page: 1)?.path
                == "/users/tester/works/drafts"
        )
        #expect(
            AO3Client.myDraftsURL(username: "tester", page: 2)?.query?
                .contains("page=2") == true
        )
        #expect(AO3Client.myDraftsURL(username: "  ", page: 1) == nil)
        #expect(
            AO3Client.myWorksURL(username: "tester", page: 1)?.path
                == "/users/tester/works"
        )
    }

    @Test func previewExtractsThePreviewPane() {
        let html = """
        <html><body>
          <div id="previewpane"><div class="draft work"><div id="workskin"><p>Hello.</p></div></div></div>
        </body></html>
        """
        let preview = try #require(try? AO3Client.parsePreviewHTML(from: html))
        #expect(preview.html.contains("Hello."))
    }

    @Test func missingFormThrowsParse() {
        #expect(throws: AO3Error.self) {
            try AO3Client.parseWorkForm(from: "<html><body>no form</body></html>")
        }
        #expect(throws: AO3Error.self) {
            try AO3Client.parseChapterForm(from: "<html><body>no form</body></html>")
        }
        #expect(throws: AO3Error.self) {
            try AO3Client.parseBulkEditForm(from: "<html><body>no form</body></html>")
        }
    }

    @Test func namedParamKeysMatchOtwarchive() {
        #expect(AO3WorkFormField.title == "work[title]")
        #expect(AO3WorkFormField.rating == "work[rating_string]")
        #expect(AO3WorkFormField.warnings == "work[archive_warning_strings][]")
        #expect(AO3WorkFormField.fandoms == "work[fandom_string]")
        #expect(AO3WorkFormField.additionalTags == "work[freeform_string]")
        #expect(AO3WorkFormField.wipLength == "work[wip_length]")
        #expect(AO3WorkFormField.chapterPosition == "chapter[position]")
        #expect(AO3WorkFormField.serialOrder == "serial[]")
    }
}
