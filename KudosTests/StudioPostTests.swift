import Foundation
import Testing
@testable import Kudos

// MARK: - Shared pure fixture builders (no network, no AO3 contact)

nonisolated enum StudioPostTestFixtures {
    static func makePostedWorkForm(
        workID: Int = 424242,
        canRemoveMe: Bool = false,
        canOrphan: Bool = true
    ) -> AO3WorkForm {
        var form = AO3WorkForm(
            kind: .edit,
            workID: workID,
            actionURL: AO3Client.workURL(workID: workID),
            httpMethodOverride: "patch",
            csrfToken: "tok==",
            isDraft: false,
            isPosted: true
        )
        form.title = "What the Tide Keeps"
        form.rating = "Teen And Up Audiences"
        form.ratingOptions = [
            AO3FormOption(value: "Not Rated", title: "Not Rated"),
            AO3FormOption(value: "General Audiences", title: "General Audiences"),
            AO3FormOption(value: "Teen And Up Audiences", title: "Teen And Up Audiences")
        ]
        form.warnings = ["No Archive Warnings Apply"]
        form.warningOptions = [
            AO3FormOption(
                value: "Creator Chose Not To Use Archive Warnings",
                title: "Creator Chose Not To Use Archive Warnings"
            ),
            AO3FormOption(value: "No Archive Warnings Apply", title: "No Archive Warnings Apply")
        ]
        form.categories = ["Gen"]
        form.fandoms = ["Original Work"]
        form.relationships = ["Ines & Her Father"]
        form.characters = ["Ines", "Tomas"]
        form.additionalTags = ["Coastal Town", "Tides"]
        form.languageID = "1"
        form.languageOptions = [
            AO3FormOption(value: "1", title: "English"),
            AO3FormOption(value: "2", title: "Español")
        ]
        form.summary = "<p>Ines counts the ribs of a stranded boat.</p>"
        form.notes = "<p>Written for winter.</p>"
        form.endnotes = "<p>Thanks for reading.</p>"
        form.chaptersPosted = 3
        form.chapterTotal = "8"
        form.isChaptered = true
        form.restricted = false
        form.moderatedCommenting = false
        form.commentPermissions = "disable_anon"
        form.commentPermissionOptions = [
            AO3FormOption(value: "enable_all", title: "Registered users and guests can comment"),
            AO3FormOption(value: "disable_anon", title: "Only registered users can comment"),
            AO3FormOption(value: "disable_all", title: "No one can comment")
        ]
        form.creators = AO3CreatorDraft(
            selectedPseudIDs: ["101"],
            availablePseuds: [AO3FormOption(value: "101", title: "quietharbor", isSelected: true)],
            coauthorByline: ""
        )
        form.currentSeries = [AO3CurrentSeries(seriesID: 55, title: "Harbour Lights", serialWorkID: 700)]
        form.collections = [
            AO3CollectionOffer(
                name: "lighthouses_week",
                title: "Lighthouses Week",
                access: AO3CollectionAccess(),
                isSelected: true
            )
        ]
        form.gifts = [AO3GiftRecipient(name: "anne_at_lyme")]
        form.canRemoveMe = canRemoveMe
        form.canOrphan = canOrphan
        return form
    }

    static func makeNewWorkForm() -> AO3WorkForm {
        var form = AO3WorkForm(
            kind: .new,
            workID: nil,
            actionURL: URL(string: "https://archiveofourown.org/works")!,
            httpMethodOverride: nil,
            csrfToken: "tok==",
            isDraft: true,
            isPosted: false
        )
        form.ratingOptions = [
            AO3FormOption(value: "General Audiences", title: "General Audiences"),
            AO3FormOption(value: "Teen And Up Audiences", title: "Teen And Up Audiences")
        ]
        form.warningOptions = [
            AO3FormOption(value: "No Archive Warnings Apply", title: "No Archive Warnings Apply"),
            AO3FormOption(value: "Major Character Death", title: "Major Character Death")
        ]
        form.languageOptions = [
            AO3FormOption(value: "1", title: "English"),
            AO3FormOption(value: "2", title: "Français")
        ]
        form.chapter = AO3WorkChapterDraft(title: "", summary: "", content: "", contentServed: true)
        return form
    }

    static func makeChapterForm(
        workID: Int = 424242,
        chapterID: Int? = nil,
        position: String = "4",
        wipLength: String = "8",
        content: String = "<p>The tide came in <em>quietly</em>.</p><hr>"
            + "<p>Read <a href=\"https://example.com\">more</a>.</p><hr>"
    ) -> AO3ChapterForm {
        let actionURL = chapterID.map { AO3Client.chapterURL(workID: workID, chapterID: $0) }
            ?? AO3Client.chaptersURL(workID: workID)
        return AO3ChapterForm(
            workID: workID,
            chapterID: chapterID,
            actionURL: actionURL,
            httpMethodOverride: chapterID == nil ? nil : "patch",
            csrfToken: "tok==",
            title: "The Boatyard",
            position: position,
            includePosition: true,
            wipLength: wipLength,
            summary: "",
            notes: "",
            endnotes: "",
            content: content,
            isDraft: true
        )
    }
}

// MARK: - 1. Post Chapter on-device checks (`Studio-Post-Chapter`)

@MainActor
struct StudioPostChapterChecksTests {
    @Test func allFourChecksPassOrWarnCleanlyOnHealthyChapter() {
        let work = StudioPostTestFixtures.makePostedWorkForm()
        let chapter = StudioPostTestFixtures.makeChapterForm()
        let checks = StudioPostChapterChecker.checks(
            chapterForm: chapter,
            workForm: work,
            openTKCount: 0,
            openNoteCount: 2
        )

        #expect(checks.map(\.id) == [.workDetails, .textReady, .chapterCount, .comments])
        #expect(StudioPostChapterChecker.canPost(checks: checks))

        let details = checks[0]
        #expect(details.status == .pass)
        #expect(details.title == "Work details carry over")
        #expect(details.detail.contains("Teen And Up Audiences"))
        #expect(details.detail.contains("Original Work"))
        #expect(details.detail.contains("everyone can see it"))
        #expect(details.actionTitle == "Edit")

        let text = checks[1]
        #expect(text.status == .pass)
        #expect(text.title == "Text is ready for AO3")
        #expect(text.detail.contains("Italics, 2 scene breaks and 1 link convert cleanly to AO3's HTML"))
        #expect(text.detail.contains("2 private notes stay on this device"))

        let count = checks[2]
        #expect(count.status == .warning)
        #expect(count.detail == "Still 8 planned? Change it here if the story grew")
        #expect(count.actionTitle == "Change")

        let comments = checks[3]
        #expect(comments.status == .pass)
        #expect(comments.detail == "Registered users can comment · moderation off")
    }

    @Test func workDetailsCheckWarnsWhenWorkFormMissingAndFailsWhenRequiredMetadataMissing() {
        let chapter = StudioPostTestFixtures.makeChapterForm()

        let noWorkChecks = StudioPostChapterChecker.checks(chapterForm: chapter, workForm: nil)
        #expect(noWorkChecks[0].id == .workDetails)
        #expect(noWorkChecks[0].status == .warning)
        #expect(noWorkChecks[3].id == .comments)
        #expect(noWorkChecks[3].status == .warning)
        #expect(StudioPostChapterChecker.canPost(checks: noWorkChecks))

        var brokenWork = StudioPostTestFixtures.makePostedWorkForm()
        brokenWork.rating = ""
        brokenWork.warnings = []
        brokenWork.fandoms = []
        let brokenChecks = StudioPostChapterChecker.checks(chapterForm: chapter, workForm: brokenWork)
        #expect(brokenChecks[0].status == .fail)
        #expect(brokenChecks[0].detail.contains("rating"))
        #expect(brokenChecks[0].detail.contains("archive warnings"))
        #expect(brokenChecks[0].detail.contains("fandom"))
        #expect(!StudioPostChapterChecker.canPost(checks: brokenChecks))
    }

    @Test func textReadyCheckCoversEmptyOverLimitStrippedHTMLAndOpenTKs() {
        let work = StudioPostTestFixtures.makePostedWorkForm()

        let plain = StudioPostTestFixtures.makeChapterForm(content: "<p>Just plain prose.</p>")
        let plainChecks = StudioPostChapterChecker.checks(chapterForm: plain, workForm: work)
        #expect(plainChecks[1].status == .pass)
        #expect(plainChecks[1].detail == "Plain paragraphs convert cleanly to AO3's HTML")

        let empty = StudioPostTestFixtures.makeChapterForm(content: "   <p></p>  ")
        let emptyChecks = StudioPostChapterChecker.checks(chapterForm: empty, workForm: work)
        #expect(emptyChecks[1].status == .fail)
        #expect(!StudioPostChapterChecker.canPost(checks: emptyChecks))

        let giant = StudioPostTestFixtures.makeChapterForm(content: String(repeating: "a", count: 510_001))
        let giantChecks = StudioPostChapterChecker.checks(chapterForm: giant, workForm: work)
        #expect(giantChecks[1].status == .fail)
        #expect(giantChecks[1].title == "Chapter text is too long for AO3")
        #expect(!StudioPostChapterChecker.canPost(checks: giantChecks))

        var longSummary = StudioPostTestFixtures.makeChapterForm(content: "<p>Body text.</p>")
        longSummary.summary = String(repeating: "s", count: 1_251)
        #expect(StudioPostChapterChecker.checks(chapterForm: longSummary, workForm: work)[1].status == .fail)

        var longBegin = StudioPostTestFixtures.makeChapterForm(content: "<p>Body text.</p>")
        longBegin.notes = String(repeating: "n", count: 5_001)
        #expect(StudioPostChapterChecker.checks(chapterForm: longBegin, workForm: work)[1].status == .fail)

        var longEnd = StudioPostTestFixtures.makeChapterForm(content: "<p>Body text.</p>")
        longEnd.endnotes = String(repeating: "e", count: 5_001)
        #expect(StudioPostChapterChecker.checks(chapterForm: longEnd, workForm: work)[1].status == .fail)

        let tkChecks = StudioPostChapterChecker.checks(chapterForm: plain, workForm: work, openTKCount: 2)
        #expect(tkChecks[1].status == .warning)
        #expect(tkChecks[1].detail.contains("2 TK markers still open"))
        #expect(StudioPostChapterChecker.canPost(checks: tkChecks))

        let messy = StudioPostTestFixtures.makeChapterForm(
            content: "<p style=\"color:red\">Hi</p><script>alert(1)</script><a href=\"javascript:void(0)\">bad</a>"
        )
        let messyChecks = StudioPostChapterChecker.checks(chapterForm: messy, workForm: work)
        #expect(messyChecks[1].status == .warning)
        #expect(messyChecks[1].detail.contains("<script>"))
        #expect(messyChecks[1].detail.contains("inline styles"))
        #expect(messyChecks[1].detail.contains("http/https/mailto"))
    }

    @Test func chapterCountCheckCoversOpenEndedCompletePastTotalAndInvalidInput() {
        var work = StudioPostTestFixtures.makePostedWorkForm()
        work.chapterTotal = ""

        let openEnded = StudioPostTestFixtures.makeChapterForm(position: "4", wipLength: "")
        let openChecks = StudioPostChapterChecker.checks(chapterForm: openEnded, workForm: work)
        #expect(openChecks[2].status == .pass)
        #expect(openChecks[2].detail == "Becomes 4 of ? on AO3 · work stays in progress")

        let completing = StudioPostTestFixtures.makeChapterForm(position: "4", wipLength: "4")
        let completeChecks = StudioPostChapterChecker.checks(chapterForm: completing, workForm: work)
        #expect(completeChecks[2].status == .warning)
        #expect(completeChecks[2].detail.contains("Marks the work complete at 4 of 4"))

        let pastTotal = StudioPostTestFixtures.makeChapterForm(position: "4", wipLength: "3")
        let pastChecks = StudioPostChapterChecker.checks(chapterForm: pastTotal, workForm: work)
        #expect(pastChecks[2].status == .fail)
        #expect(!StudioPostChapterChecker.canPost(checks: pastChecks))

        let invalidTotal = StudioPostTestFixtures.makeChapterForm(position: "4", wipLength: "abc")
        let invalidChecks = StudioPostChapterChecker.checks(chapterForm: invalidTotal, workForm: work)
        #expect(invalidChecks[2].status == .fail)
        #expect(!StudioPostChapterChecker.canPost(checks: invalidChecks))
    }

    @Test func commentsCheckReflectsAllThreePermissionsAndModeration() {
        let chapter = StudioPostTestFixtures.makeChapterForm()
        var work = StudioPostTestFixtures.makePostedWorkForm()

        work.commentPermissions = "enable_all"
        work.moderatedCommenting = true
        let allMod = StudioPostChapterChecker.checks(chapterForm: chapter, workForm: work)[3]
        #expect(allMod.status == .pass)
        #expect(allMod.detail == "Everyone can comment · moderation on")

        work.commentPermissions = "disable_all"
        work.moderatedCommenting = false
        let none = StudioPostChapterChecker.checks(chapterForm: chapter, workForm: work)[3]
        #expect(none.status == .pass)
        #expect(none.detail == "Comments are turned off · moderation off")
    }

    @Test func chapterMetaLineFormatsCountsAndUnknownTotal() {
        let known = StudioPostChapterChecker.chapterMetaLine(wordCount: 2410, position: 4, plannedTotal: 8)
        #expect(known == "2,410 words · becomes 4 of 8 on AO3")

        let open = StudioPostChapterChecker.chapterMetaLine(wordCount: 1, position: 1, plannedTotal: nil)
        #expect(open == "1 word · becomes 1 of ? on AO3")
    }
}

// MARK: - 2. Post New Work required fields & Post button state (`Studio-Post-New-Work`)

@MainActor
struct StudioPostNewWorkRequirementsTests {
    @Test func emptyWorkReportsSixLeftAndDisabledPostButton() {
        let form = StudioPostTestFixtures.makeNewWorkForm()
        let req = StudioNewWorkRequirements.evaluate(form)

        #expect(req.items.map(\.kind) == [.title, .rating, .warnings, .fandom, .language, .text])
        #expect(req.remainingCount == 6)
        #expect(req.remainingBadgeText == "6 left")
        #expect(!req.canPost)
        #expect(req.postButtonTitle == "Post — 6 required fields left")
    }

    @Test func singleMissingArchiveWarningsMatchesBoardPhrase() {
        var form = StudioPostTestFixtures.makeNewWorkForm()
        form.title = "The Harbour Pilot's Daughter"
        form.rating = "Teen And Up Audiences"
        form.fandoms = ["Original Work"]
        form.languageID = "1"
        form.chapter = AO3WorkChapterDraft(content: "<p>The harbour bell rang twice.</p>")

        let req = StudioNewWorkRequirements.evaluate(form)
        #expect(req.remainingCount == 1)
        #expect(req.remainingBadgeText == "1 left")
        #expect(!req.canPost)
        #expect(req.postButtonTitle == "Post — choose Archive Warnings first")
    }

    @Test func eachSingleMissingFieldProducesSpecificPostButtonTitle() {
        func completeForm() -> AO3WorkForm {
            var form = StudioPostTestFixtures.makeNewWorkForm()
            form.title = "Title"
            form.rating = "General Audiences"
            form.warnings = ["No Archive Warnings Apply"]
            form.fandoms = ["Original Work"]
            form.languageID = "1"
            form.chapter = AO3WorkChapterDraft(content: "<p>Some text.</p>")
            return form
        }

        var missingTitle = completeForm()
        missingTitle.title = "   "
        #expect(StudioNewWorkRequirements.evaluate(missingTitle).postButtonTitle == "Post — add a Title first")

        var missingRating = completeForm()
        missingRating.rating = ""
        #expect(StudioNewWorkRequirements.evaluate(missingRating).postButtonTitle == "Post — choose a Rating first")

        var missingFandom = completeForm()
        missingFandom.fandoms = []
        #expect(StudioNewWorkRequirements.evaluate(missingFandom).postButtonTitle == "Post — add a Fandom first")

        var missingLanguage = completeForm()
        missingLanguage.languageID = ""
        let langTitle = StudioNewWorkRequirements.evaluate(missingLanguage).postButtonTitle
        #expect(langTitle == "Post — choose a Language first")

        var missingText = completeForm()
        missingText.chapter?.content = ""
        #expect(StudioNewWorkRequirements.evaluate(missingText).postButtonTitle == "Post — add the Text first")

        let ready = StudioNewWorkRequirements.evaluate(completeForm())
        #expect(ready.remainingCount == 0)
        #expect(ready.remainingBadgeText == nil)
        #expect(ready.canPost)
        #expect(ready.postButtonTitle == "Post")
    }

    @Test func multiChapterDraftWithoutServedTextDoesNotBlockOnText() {
        var form = StudioPostTestFixtures.makeNewWorkForm()
        form.kind = .draft
        form.title = "Multi-chapter Draft"
        form.rating = "General Audiences"
        form.warnings = ["No Archive Warnings Apply"]
        form.fandoms = ["Original Work"]
        form.languageID = "1"
        form.chapter = AO3WorkChapterDraft(content: "", contentServed: false)

        let req = StudioNewWorkRequirements.evaluate(form)
        #expect(req.canPost)
        #expect(req.remainingCount == 0)
    }

    @Test func workTemplateAppliesOnlyBlankFieldsAndFormatsBanner() {
        let base = StudioPostTestFixtures.makeNewWorkForm()
        let template = StudioPostWorkTemplate(
            sourceTitle: "What the Tide Keeps",
            rating: "Teen And Up Audiences",
            warnings: [],
            fandoms: ["Original Work"],
            languageID: "1",
            restricted: false
        )
        let applied = template.applying(to: base)
        #expect(applied.form.rating == "Teen And Up Audiences")
        #expect(applied.form.fandoms == ["Original Work"])
        #expect(applied.form.languageID == "1")
        #expect(applied.copiedLabels == ["rating", "fandom", "language"])

        let banner = StudioPostWorkTemplate.bannerText(
            sourceTitle: template.sourceTitle,
            copiedLabels: applied.copiedLabels
        )
        #expect(banner == "Started from What the Tide Keeps — rating, fandom and language copied. Change anything.")

        let overlaid = StudioPostWorkTemplate.overlayChapterDraft(
            workTitle: "The Harbour Pilot's Daughter",
            chapterTitle: "Opening",
            summary: "<p>A short summary.</p>",
            notesBefore: "<p>Begin.</p>",
            notesAfter: "<p>End.</p>",
            content: "<p>First line.</p>",
            onto: applied.form
        )
        #expect(overlaid.title == "The Harbour Pilot's Daughter")
        #expect(overlaid.summary == "<p>A short summary.</p>")
        #expect(overlaid.notes == "<p>Begin.</p>")
        #expect(overlaid.endnotes == "<p>End.</p>")
        #expect(overlaid.chapter?.title == "Opening")
        #expect(overlaid.chapter?.content == "<p>First line.</p>")
    }
}
