import Foundation
import SwiftSoup

/// Authenticated GETs and SwiftSoup parsers for AO3 writing surfaces
/// (work / chapter / series / draft / bulk / tags). Markup ground truth is
/// otwarchive's work, chapter, and series form partials. Fetches ride
/// `authenticatedPageHTML` (paced, coalesced, retried); never a raw
/// `URLSession` to AO3.
extension AO3Client {

    // MARK: URLs

    static func newWorkURL() -> URL {
        URL(string: "https://archiveofourown.org/works/new")!
    }

    static func workEditURL(workID: Int) -> URL {
        URL(string: "https://archiveofourown.org/works/\(workID)/edit")!
    }

    static func workEditTagsURL(workID: Int) -> URL {
        URL(string: "https://archiveofourown.org/works/\(workID)/edit_tags")!
    }

    static func workPreviewURL(workID: Int) -> URL {
        URL(string: "https://archiveofourown.org/works/\(workID)/preview")!
    }

    static func workConfirmDeleteURL(workID: Int) -> URL {
        URL(string: "https://archiveofourown.org/works/\(workID)/confirm_delete")!
    }

    static func workURL(workID: Int) -> URL {
        URL(string: "https://archiveofourown.org/works/\(workID)")!
    }

    static func newChapterURL(workID: Int) -> URL {
        URL(string: "https://archiveofourown.org/works/\(workID)/chapters/new")!
    }

    static func chapterEditURL(workID: Int, chapterID: Int) -> URL {
        URL(string: "https://archiveofourown.org/works/\(workID)/chapters/\(chapterID)/edit")!
    }

    static func chapterPreviewURL(workID: Int, chapterID: Int) -> URL {
        URL(string: "https://archiveofourown.org/works/\(workID)/chapters/\(chapterID)/preview")!
    }

    static func chapterConfirmDeleteURL(workID: Int, chapterID: Int) -> URL {
        URL(string: "https://archiveofourown.org/works/\(workID)/chapters/\(chapterID)/confirm_delete")!
    }

    static func chaptersURL(workID: Int) -> URL {
        URL(string: "https://archiveofourown.org/works/\(workID)/chapters")!
    }

    static func chapterURL(workID: Int, chapterID: Int) -> URL {
        URL(string: "https://archiveofourown.org/works/\(workID)/chapters/\(chapterID)")!
    }

    static func seriesEditURL(seriesID: Int) -> URL {
        URL(string: "https://archiveofourown.org/series/\(seriesID)/edit")!
    }

    static func seriesManageURL(seriesID: Int) -> URL {
        URL(string: "https://archiveofourown.org/series/\(seriesID)/manage")!
    }

    static func seriesURL(seriesID: Int) -> URL {
        URL(string: "https://archiveofourown.org/series/\(seriesID)")!
    }

    /// `serial_work_path` — what "Remove Work From Series" deletes.
    static func serialWorkURL(serialWorkID: Int) -> URL {
        URL(string: "https://archiveofourown.org/serial_works/\(serialWorkID)")!
    }

    /// The work form's own collection field autocomplete —
    /// `autocomplete_options("open_collection_names")` in `works/_standard_form`
    /// — built like `autocompleteURL(kind:term:)`. nil for a blank term.
    static func openCollectionNamesURL(term: String) -> URL? {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents(string: "https://archiveofourown.org/autocomplete/open_collection_names")
        components?.queryItems = [URLQueryItem(name: "term", value: trimmed)]
        return components?.url
    }

    static func newSeriesURL() -> URL {
        URL(string: "https://archiveofourown.org/series/new")!
    }

    static func seriesCreateURL() -> URL {
        URL(string: "https://archiveofourown.org/series")!
    }

    static func seriesUpdatePositionsURL(seriesID: Int) -> URL {
        URL(string: "https://archiveofourown.org/series/\(seriesID)/update_positions")!
    }

    /// Drafts are their own index (`WorksController#drafts`), not a filter on
    /// `myWorksURL`. Path matches Account › Writing › Drafts (`works/drafts`).
    static func myDraftsURL(username: String, page: Int) -> URL? {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        var components = URLComponents(string: "https://archiveofourown.org")
        components?.path = "/users/\(name)/works/drafts"
        if page > 1 {
            components?.queryItems = [URLQueryItem(name: "page", value: String(page))]
        }
        return components?.url
    }

    static func showMultipleWorksURL(username: String) -> URL? {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return URL(string: "https://archiveofourown.org/users/\(name)/works/show_multiple")
    }

    static func editMultipleWorksURL(username: String) -> URL? {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return URL(string: "https://archiveofourown.org/users/\(name)/works/edit_multiple")
    }

    static func updateMultipleWorksURL(username: String) -> URL? {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return URL(string: "https://archiveofourown.org/users/\(name)/works/update_multiple")
    }

    /// `delete_multiple_user_works_path` — where `works/confirm_delete_multiple`
    /// posts "Yes, Delete Works".
    static func deleteMultipleWorksURL(username: String) -> URL? {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return URL(string: "https://archiveofourown.org/users/\(name)/works/delete_multiple")
    }

    // MARK: Fetchers

    func workFormHTML(for request: URLRequest) async throws -> String {
        try await authenticatedPageHTML(for: request)
    }

    /// The drafts page, parsed twice from the one response: as works, and for
    /// the deletion date each draft's blurb prints.
    func draftsPage(for request: URLRequest, page: Int) async throws -> AO3DraftsPage {
        let html = try await authenticatedPageHTML(for: request)
        return try AO3DraftsPage(
            page: Self.parseSearchPage(html, page: page),
            deletionDates: Self.parseDraftDeletionDates(html)
        )
    }

    /// Each draft's deletion date, keyed by work id. otwarchive renders every
    /// unposted work's blurb (`li#work_<id>`) with
    /// `<p class="caution notice">This draft will be <strong>scheduled for
    /// deletion</strong> on …</p>`, the date in `date_short_html`: `span.date`
    /// (day of month), `abbr.month[title]` (the English month name) and
    /// `span.year` (`works/_work_module.html.erb`; `en.yml` `date_short_html`).
    /// Read from the notice only — the blurb's `p.datetime` is the revised date.
    /// A blurb whose notice is missing or unreadable is left out, not guessed.
    static func parseDraftDeletionDates(_ html: String) -> [Int: DateComponents] {
        guard let doc = try? SwiftSoup.parse(html),
              let blurbs = try? doc.select("li.work.blurb").array()
        else { return [:] }
        var dates: [Int: DateComponents] = [:]
        for blurb in blurbs {
            let id = blurb.id()
            guard id.hasPrefix("work_"), let workID = Int(id.dropFirst("work_".count)),
                  let notice = try? blurb.select("p.caution.notice").first(),
                  let dayText = try? notice.select("span.date").first()?.text(),
                  let monthName = try? notice.select("abbr.month").first()?.attr("title"),
                  let yearText = try? notice.select("span.year").first()?.text(),
                  let day = Int(dayText.trimmingCharacters(in: .whitespaces)),
                  let year = Int(yearText.trimmingCharacters(in: .whitespaces)),
                  let month = draftNoticeMonths.firstIndex(of: monthName.trimmingCharacters(in: .whitespaces))
            else { continue }
            dates[workID] = DateComponents(year: year, month: month + 1, day: day)
        }
        return dates
    }

    /// `%B` in AO3's English locale, which is the only one its pages render in.
    private static let draftNoticeMonths = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    // MARK: Work form

    static func parseWorkForm(from html: String) throws -> AO3WorkForm {
        let doc = try SwiftSoup.parse(html)
        guard let form = try workFormElement(in: doc) else { throw AO3Error.parse }
        let action = (try? form.attr("action")) ?? ""
        guard let actionURL = writingAbsoluteURL(action) else { throw AO3Error.parse }
        guard let csrf = parseCSRFToken(from: html)
            ?? inputValue(form, name: AO3WorkFormField.authenticityToken)
        else { throw AO3Error.parse }

        let methodOverride = inputValue(form, name: "_method")
        let workID = workIDFromPath(actionURL.path)
        let heading = ((try? doc.select("h2.heading, h2").first()?.text()) ?? "")
            .lowercased()
        let hasSaveDraft = submitNamed(form, AO3WorkFormField.saveButton)
        let hasUpdate = submitNamed(form, AO3WorkFormField.updateButton)
        let isPosted = hasUpdate && !hasSaveDraft
        let kind: AO3WorkFormKind
        if actionURL.path.contains("edit_tags") || actionURL.path.contains("update_tags") {
            kind = .editTags
        } else if heading.contains("post new") || workID == nil {
            kind = .new
        } else if !isPosted {
            kind = .draft
        } else {
            kind = .edit
        }

        let rating = parseSelect(form, name: AO3WorkFormField.rating)
        let warnings = parseCheckboxes(form, name: AO3WorkFormField.warnings)
        let categories = parseCheckboxes(form, name: AO3WorkFormField.categories)
        let language = parseSelect(form, name: AO3WorkFormField.languageID)
        let commentPerms = parseRadios(form, name: AO3WorkFormField.commentPermissions)
        let skins = parseSelect(form, name: AO3WorkFormField.workSkinID)

        var formDTO = AO3WorkForm(
            kind: kind,
            workID: workID,
            actionURL: actionURL,
            httpMethodOverride: methodOverride.flatMap { $0.isEmpty ? nil : $0 },
            csrfToken: csrf,
            isDraft: !isPosted,
            isPosted: isPosted,
            title: inputValue(form, name: AO3WorkFormField.title) ?? "",
            rating: rating.selected,
            ratingOptions: rating.options,
            warnings: warnings.selected,
            warningOptions: warnings.options,
            fandoms: AO3TagListDiff.split(
                inputValue(form, name: AO3WorkFormField.fandoms) ?? ""
            ),
            languageID: language.selected,
            languageOptions: language.options,
            categories: categories.selected,
            categoryOptions: categories.options,
            relationships: AO3TagListDiff.split(
                inputValue(form, name: AO3WorkFormField.relationships) ?? ""
            ),
            characters: AO3TagListDiff.split(
                inputValue(form, name: AO3WorkFormField.characters) ?? ""
            ),
            additionalTags: AO3TagListDiff.split(
                inputValue(form, name: AO3WorkFormField.additionalTags) ?? ""
            ),
            collectionNames: AO3TagListDiff.split(
                inputValue(form, name: AO3WorkFormField.collectionNames) ?? ""
            ),
            gifts: AO3TagListDiff.split(
                inputValue(form, name: AO3WorkFormField.recipients) ?? ""
            ).map { AO3GiftRecipient(name: $0) },
            series: parseSeriesMemberships(in: form),
            newSeriesTitle: inputValue(form, name: AO3WorkFormField.seriesTitle) ?? "",
            parentWork: parseParentWork(in: form),
            existingParentTitles: parseExistingParentTitles(in: form),
            summary: textareaValue(form, name: AO3WorkFormField.summary),
            notes: textareaValue(form, name: AO3WorkFormField.notes),
            endnotes: textareaValue(form, name: AO3WorkFormField.endnotes),
            chapter: parseNestedChapter(in: form),
            creators: parseCreators(in: form, prefix: "work"),
            chapterTotal: inputValue(form, name: AO3WorkFormField.wipLength) ?? "",
            isChaptered: checkboxOn(form, id: "chapters-options-show")
                || checkboxOn(form, name: "chapters-options-show"),
            backdate: checkboxOn(form, name: AO3WorkFormField.backdate),
            restricted: checkboxOn(form, name: AO3WorkFormField.restricted),
            moderatedCommenting: checkboxOn(
                form, name: AO3WorkFormField.moderatedCommenting
            ),
            commentPermissions: commentPerms.selected,
            commentPermissionOptions: commentPerms.options,
            anonymous: optionalCheckbox(form, name: AO3WorkFormField.anonymous),
            collectionInbox: optionalCheckbox(
                form, name: AO3WorkFormField.collectionInbox
            ),
            workSkinID: skins.selected,
            workSkinOptions: skins.options,
            hiddenFields: parseCarryHiddenFields(in: form)
        )
        formDTO.chaptersPosted = parsePostedChapterCount(in: doc, form: form)
        formDTO.currentSeries = parseCurrentSeries(in: form)
        formDTO.collections = formDTO.collectionNames.map {
            AO3CollectionOffer(
                name: $0,
                title: $0,
                access: AO3CollectionAccess(),
                isSelected: true
            )
        }
        return formDTO
    }

    static func parseEditTagsForm(from html: String) throws -> AO3EditTagsForm {
        let work = try parseWorkForm(from: html)
        guard let workID = work.workID else { throw AO3Error.parse }
        return AO3EditTagsForm(
            workID: workID,
            actionURL: work.actionURL,
            httpMethodOverride: work.httpMethodOverride,
            csrfToken: work.csrfToken,
            tags: work.tagSet,
            warningOptions: work.warningOptions,
            categoryOptions: work.categoryOptions,
            ratingOptions: work.ratingOptions,
            languageID: work.languageID,
            languageOptions: work.languageOptions
        )
    }

    // MARK: Chapter

    static func parseChapterForm(from html: String) throws -> AO3ChapterForm {
        let doc = try SwiftSoup.parse(html)
        guard let form = try doc.select("#chapter-form form, form.chapter, form[action*=/chapters]")
            .first()
        else { throw AO3Error.parse }
        let action = (try? form.attr("action")) ?? ""
        guard let actionURL = writingAbsoluteURL(action) else { throw AO3Error.parse }
        guard let csrf = parseCSRFToken(from: html)
            ?? inputValue(form, name: AO3WorkFormField.authenticityToken)
        else { throw AO3Error.parse }

        let workID = workIDFromPath(actionURL.path) ?? 0
        let chapterID = chapterID(inPath: actionURL.path)
        let positionField = firstInput(form, name: AO3WorkFormField.chapterPosition)
        let includePosition = positionField != nil
        return AO3ChapterForm(
            workID: workID,
            chapterID: chapterID,
            actionURL: actionURL,
            httpMethodOverride: inputValue(form, name: "_method").flatMap {
                $0.isEmpty ? nil : $0
            },
            csrfToken: csrf,
            title: inputValue(form, name: AO3WorkFormField.chapterOnlyTitle) ?? "",
            position: inputValue(form, name: AO3WorkFormField.chapterPosition) ?? "",
            includePosition: includePosition,
            wipLength: inputValue(form, name: AO3WorkFormField.chapterWipLength) ?? "",
            summary: textareaValue(form, name: AO3WorkFormField.chapterOnlySummary),
            notes: textareaValue(form, name: AO3WorkFormField.chapterNotes),
            endnotes: textareaValue(form, name: AO3WorkFormField.chapterEndnotes),
            content: textareaValue(form, name: AO3WorkFormField.chapterOnlyContent)
                .ifEmpty(textareaValue(form, id: "content")),
            publishedYear: controlValue(
                form, name: AO3WorkFormField.chapterOnlyPublishedYear
            ) ?? "",
            publishedMonth: controlValue(
                form, name: AO3WorkFormField.chapterOnlyPublishedMonth
            ) ?? "",
            publishedDay: controlValue(
                form, name: AO3WorkFormField.chapterOnlyPublishedDay
            ) ?? "",
            isDraft: submitNamed(form, AO3WorkFormField.saveButton),
            creators: parseCreators(in: form, prefix: "chapter")
        )
    }

    // MARK: Series

    static func parseSeriesForm(from html: String) throws -> AO3SeriesForm {
        let doc = try SwiftSoup.parse(html)
        let heading = ((try? doc.select("h2.heading, h2").first()?.text()) ?? "")
            .lowercased()
        guard let form = try doc.select("form.series, #work-form form, form[action*=/series]")
            .first()
        else { throw AO3Error.parse }
        let action = (try? form.attr("action")) ?? ""
        guard let actionURL = writingAbsoluteURL(action) else { throw AO3Error.parse }
        guard let csrf = parseCSRFToken(from: html)
            ?? inputValue(form, name: AO3WorkFormField.authenticityToken)
        else { throw AO3Error.parse }

        let titleField = firstInput(form, name: AO3WorkFormField.seriesFormTitle)
        let isCreate = actionURL.path == "/series" || heading.contains("new series")
        return AO3SeriesForm(
            seriesID: seriesID(inPath: actionURL.path),
            actionURL: actionURL,
            httpMethodOverride: inputValue(form, name: "_method").flatMap {
                $0.isEmpty ? nil : $0
            },
            csrfToken: csrf,
            title: inputValue(form, name: AO3WorkFormField.seriesFormTitle) ?? "",
            summary: textareaValue(form, name: AO3WorkFormField.seriesSummary),
            notes: textareaValue(form, name: AO3WorkFormField.seriesNotes),
            isComplete: checkboxOn(form, name: AO3WorkFormField.seriesComplete),
            creators: parseCreators(in: form, prefix: "series"),
            works: [],
            openOnAO3ForCreate: isCreate && titleField == nil
        )
    }

    /// `series/_series_order`: `ul#sortable_series_list` (AO3 draws no other
    /// list of serial works), each row `li#serial_<id>` with its title in
    /// `h3.heading` and `draft_work_title` ("%{title} (DRAFT)") for a draft.
    static func parseSeriesManagePage(from html: String) throws -> [AO3SeriesWorkRow] {
        let doc = try SwiftSoup.parse(html)
        guard let list = try doc.select("#sortable_series_list").first()
        else { throw AO3Error.parse }
        var rows: [AO3SeriesWorkRow] = []
        for (index, li) in try list.select("li").array().enumerated() {
            let idAttr = (try? li.attr("id")) ?? ""
            let serialID = Int(idAttr.replacingOccurrences(of: "serial_", with: ""))
                ?? Int(
                    ((try? li.select("[id^=position-for-]").first()?.id()) ?? "")
                        .replacingOccurrences(of: "position-for-", with: "")
                )
            guard let serialID else { continue }
            let positionText = (try? li.select("[id^=position-for-]").first()?.text()) ?? ""
            let position = Int(positionText.trimmingCharacters(in: .whitespaces))
                ?? (index + 1)
            let title = ((try? li.select("h3.heading, h4.heading, a").first()?.text()) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let isDraft = title.hasSuffix(" (DRAFT)")
            rows.append(
                AO3SeriesWorkRow(
                    workID: workID(in: li),
                    serialWorkID: serialID,
                    title: title,
                    position: position,
                    isDraft: isDraft
                )
            )
        }
        if rows.isEmpty { throw AO3Error.parse }
        return rows
    }

    /// 1bw's "Search all collections by name": collections open to new works
    /// (otwarchive's `autocomplete_collection_open` set — not closed; whether
    /// one is moderated is not in the answer). Anonymous, paced like any GET.
    func openCollections(matching term: String) async throws -> [AO3CollectionOffer] {
        guard let url = Self.openCollectionNamesURL(term: term) else { return [] }
        return try Self.parseOpenCollectionNames(Data(try await getHTML(url).utf8))
    }

    /// `AutocompleteController#open_collection_names` answers
    /// `[{id: name, name: "Title (name)"}]`: `id` is what the form posts.
    static func parseOpenCollectionNames(_ data: Data) throws -> [AO3CollectionOffer] {
        struct Row: Decodable { let id: String; let name: String }
        return try JSONDecoder().decode([Row].self, from: data).compactMap { row in
            let name = row.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let suffix = " (\(name))"
            let title = row.name.hasSuffix(suffix) ? String(row.name.dropLast(suffix.count)) : row.name
            return AO3CollectionOffer(name: name, title: title, access: AO3CollectionAccess(isDescribed: false))
        }
    }

    // MARK: Bulk edit

    static func parseBulkEditForm(from html: String) throws -> AO3BulkEditForm {
        let doc = try SwiftSoup.parse(html)
        guard let form = try doc.select("form.verbose.post, form[action*=update_multiple], form[action*=edit_multiple]")
            .first()
        else { throw AO3Error.parse }
        let action = (try? form.attr("action")) ?? ""
        guard let actionURL = writingAbsoluteURL(action) else { throw AO3Error.parse }
        guard let csrf = parseCSRFToken(from: html)
            ?? inputValue(form, name: AO3WorkFormField.authenticityToken)
        else { throw AO3Error.parse }

        let ids = inputs(form, name: AO3WorkFormField.workIDs).compactMap {
            Int((try? $0.attr("value")) ?? "")
        }
        // otwarchive's `works/_work_abbreviated_list`: each `dt` holds the
        // title link and then the fandom links, so only the first is the title.
        let titles = try doc.select("dl.work.index > dt > a:first-of-type")
            .array()
            .compactMap { try? $0.text() }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let rating = parseSelect(form, name: AO3WorkFormField.rating)
        let warnings = parseCheckboxes(form, name: AO3WorkFormField.warnings)
        let categories = parseCheckboxes(form, name: AO3WorkFormField.categories)
        let language = parseSelect(form, name: AO3WorkFormField.languageID)
        let collections = parseCheckboxes(form, name: AO3WorkFormField.collectionsToRemove)
        let commentPerms = parseRadios(form, name: AO3WorkFormField.commentPermissions)
        return AO3BulkEditForm(
            actionURL: actionURL,
            httpMethodOverride: inputValue(form, name: "_method").flatMap {
                $0.isEmpty ? nil : $0
            },
            csrfToken: csrf,
            workIDs: ids,
            workTitles: titles,
            ratingOptions: rating.options,
            warningOptions: warnings.options,
            categoryOptions: categories.options,
            languageOptions: language.options,
            currentCollections: collections.options,
            commentPermissionOptions: commentPerms.options
        )
    }

    // MARK: Collections picker (1bw)

    /// Collection blurbs (`p.type`: Open/Closed, Moderated/Unmoderated).
    static func parseCollectionOffers(from html: String) throws -> [AO3CollectionOffer] {
        let doc = try SwiftSoup.parse(html)
        var offers: [AO3CollectionOffer] = []
        for li in try doc.select("li.collection.blurb").array() {
            guard let link = try li.select("h4.heading a[href*=/collections/]").first()
            else { continue }
            let href = (try? link.attr("href")) ?? ""
            guard let range = href.range(of: "/collections/") else { continue }
            let slug = String(href[range.upperBound...])
                .split(separator: "/").first.map(String.init) ?? ""
            guard !slug.isEmpty else { continue }
            let title = ((try? link.text()) ?? slug)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let typeText = ((try? li.select("p.type").first()?.text()) ?? "")
                .lowercased()
            var access = AO3CollectionAccess()
            if typeText.contains("closed") { access.isOpen = false }
            if typeText.contains("open") { access.isOpen = true }
            if typeText.contains("unmoderated") {
                access.isModerated = false
            } else if typeText.contains("moderated") {
                access.isModerated = true
            }
            access.isUnrevealed = typeText.contains("unrevealed")
            access.isAnonymous = typeText.contains("anonymous")
            offers.append(
                AO3CollectionOffer(name: slug, title: title, access: access)
            )
        }
        return offers
    }

    // MARK: Delete confirm

    static func parseDeleteImplications(from html: String) throws -> AO3DeleteImplications {
        let doc = try SwiftSoup.parse(html)
        guard let form = try doc.select("form.destroy, form[method=post]").first()
            ?? doc.select("form").first()
        else { throw AO3Error.parse }
        let action = (try? form.attr("action")) ?? ""
        guard let actionURL = writingAbsoluteURL(action) else { throw AO3Error.parse }
        guard let csrf = parseCSRFToken(from: html)
            ?? inputValue(form, name: AO3WorkFormField.authenticityToken)
        else { throw AO3Error.parse }
        let heading = ((try? doc.select("h2.heading, h2").first()?.text()) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let caution = ((try? doc.select("p.caution, p.notice, .caution.notice").first()?.text())
            ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let isDraft = heading.lowercased().contains("draft")
            || caution.lowercased().contains("draft")
        let stats = parseImplicationCounts(in: doc, caution: caution)
        let title = quotedTitle(in: caution) ?? heading
        return AO3DeleteImplications(
            title: title,
            isDraft: isDraft,
            actionURL: actionURL,
            csrfToken: csrf,
            httpMethodOverride: inputValue(form, name: "_method") ?? "delete",
            chapters: stats.chapters,
            kudos: stats.kudos,
            comments: stats.comments,
            bookmarks: stats.bookmarks,
            words: stats.words,
            cautionText: caution
        )
    }

    nonisolated struct WorkStatCounts: Sendable {
        let chapters: Int?
        let kudos: Int?
        let comments: Int?
        let bookmarks: Int?
        let words: Int?
    }

    static func parseWorkStatCounts(from html: String) -> WorkStatCounts {
        guard let doc = try? SwiftSoup.parse(html) else {
            return WorkStatCounts(chapters: nil, kudos: nil, comments: nil, bookmarks: nil, words: nil)
        }
        func stat(_ name: String) -> Int? {
            let text = (try? doc.select("dl.stats dd.\(name), dd.\(name)").first()?.text()) ?? ""
            let digits = text.filter(\.isNumber)
            return digits.isEmpty ? nil : Int(digits)
        }
        let chaptersText = (try? doc.select("dl.stats dd.chapters, dd.chapters").first()?.text())
            ?? ""
        let posted = chaptersText.split(separator: "/").first
            .flatMap { Int($0.filter(\.isNumber)) }
        return WorkStatCounts(
            chapters: posted ?? stat("chapters"),
            kudos: stat("kudos"),
            comments: stat("comments"),
            bookmarks: stat("bookmarks"),
            words: stat("words")
        )
    }

    /// Both of otwarchive's preview templates wrap the page in `#previewpane`.
    /// Anything else is AO3 re-rendering the form instead (`render :new` /
    /// `:edit` on a validation failure), so it is refused rather than shown as
    /// a preview — with AO3's own reason when `error_messages_for` gave one.
    static func parsePreviewHTML(from html: String) throws -> AO3PreviewHTML {
        let doc = try SwiftSoup.parse(html)
        guard let pane = try doc.select("#previewpane").first() else {
            if let reason = workWriteError(in: html) { throw AO3WorkWriteError.rejected(reason) }
            throw AO3WorkWriteError.previewUnavailable
        }
        // The posting fieldset in preview mode swaps Preview for `edit_button`.
        // The form sits inside the pane for a work, after it for a chapter.
        let form = try doc.select("form").array().first {
            (try? $0.select("[name=\(AO3WorkFormField.editButton)]").first()) != nil
        }
        let action = form.flatMap { try? $0.attr("action") }.flatMap(writingAbsoluteURL)?.path ?? ""
        try pane.select("form, .landmark, img").remove()

        var blocks: [AO3PreviewHTML.Block] = []
        for element in try pane.select("h2.title, h3.title, .module > h3.heading, .userstuff") {
            if element.hasClass("userstuff") {
                blocks += try parseRichText(element).blocks.map { .text(AO3RichText(blocks: [$0])) }
            } else if let text = try? element.text().trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty {
                blocks.append(element.hasClass("title") ? .heading(text) : .label(text))
            }
        }
        return AO3PreviewHTML(
            html: try pane.html(),
            workID: workIDFromPath(action),
            chapterID: chapterID(inPath: action),
            csrfToken: parseCSRFToken(from: html),
            notice: workWriteNotice(in: html),
            blocks: blocks
        )
    }

    // MARK: - Write verdicts

    /// AO3's refusal of a work, chapter or series write: the layout's error
    /// flash (`flash_div :error, :caution, :notice, :alert`, the first thing
    /// in `#main`) or `error_messages_for`'s `#error` list, which the form
    /// templates put at their top level. Only `#main`'s own children count:
    /// AO3 keeps a writer's `class` attributes (`OtwSanitize::UserClassSanitizer`),
    /// so a chapter's own `<div class="error"><p>` in a preview or on the
    /// work page is not AO3 refusing it — the shared `writeErrorMessage`
    /// matches `.error p` anywhere, and `.flash.caution`, which otwarchive's
    /// work and chapter controllers never set. A page that shows the saved
    /// thing (`#previewpane`) is never a refusal: AO3 has the draft, and
    /// reading it as a failure skipped `adopting`, so the next Preview or Post
    /// made a second one. A notice is no such proof: `chapters#update` previews
    /// a draft chapter with `flash[:notice]`, not `flash.now`, so its banner
    /// also rides on the next page — a Post's `render :edit` refusal included.
    static func workWriteError(in html: String) -> String? {
        guard let doc = try? SwiftSoup.parse(html),
              (try? doc.select("#main > #previewpane").first()) == nil
        else { return nil }
        // Anywhere under `#main` (a refused form nests its `#error` in the
        // form), but never inside the writer's own content: AO3 keeps writer
        // classes, so a chapter may carry `class="flash error"` itself.
        let refusals = (try? doc.select("#main .flash.error, #main #error li").array()) ?? []
        return refusals.lazy
            .filter { !isInsideWriterContent($0) }
            .compactMap { (try? $0.text())?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    /// `#workskin`, `.userstuff` or `#previewpane`: text the writer wrote.
    private static func isInsideWriterContent(_ element: Element) -> Bool {
        element.parents().array().contains { parent in
            parent.id() == "workskin" || parent.id() == "previewpane" || parent.hasClass("userstuff")
        }
    }

    /// The layout's notice flash — same scoping as `workWriteError`.
    static func workWriteNotice(in html: String) -> String? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        return mainText(doc, "#main > .flash.notice")
    }

    private static func mainText(_ doc: Document, _ selector: String) -> String? {
        let text = (try? doc.select(selector).first()?.text())?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    // MARK: - Field helpers

    private static func workFormElement(in doc: Document) throws -> Element? {
        try doc.select("form#work-form, form.work.post, form[id=work-form]").first()
            ?? doc.select("form[action*=/works]").first()
    }

    private static func parseSelect(
        _ root: Element, name: String
    ) -> (selected: String, options: [AO3FormOption]) {
        guard let select = firstElement(root, tag: "select", name: name) else {
            return ("", [])
        }
        var options: [AO3FormOption] = []
        var selected = ""
        for option in (try? select.select("option").array()) ?? [] {
            let value = (try? option.attr("value")) ?? ""
            let title = ((try? option.text()) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let isSelected = option.hasAttr("selected")
            options.append(AO3FormOption(value: value, title: title, isSelected: isSelected))
            if isSelected { selected = value }
        }
        return (selected, options)
    }

    private static func parseCheckboxes(
        _ root: Element, name: String
    ) -> (selected: [String], options: [AO3FormOption]) {
        var options: [AO3FormOption] = []
        var selected: [String] = []
        let boxes = inputs(root, name: name).filter { (try? $0.attr("type")) == "checkbox" }
        for input in boxes {
            let value = (try? input.attr("value")) ?? ""
            guard !value.isEmpty else { continue }
            let isOn = input.hasAttr("checked")
            let id = (try? input.attr("id")) ?? ""
            var title = value
            if !id.isEmpty,
               let label = try? root.select("label[for=\"\(id)\"]").first()?.text() {
                let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { title = trimmed }
            }
            options.append(AO3FormOption(value: value, title: title, isSelected: isOn))
            if isOn { selected.append(value) }
        }
        return (selected, options)
    }

    private static func parseRadios(
        _ root: Element, name: String
    ) -> (selected: String, options: [AO3FormOption]) {
        var options: [AO3FormOption] = []
        var selected = ""
        let radios = inputs(root, name: name).filter { (try? $0.attr("type")) == "radio" }
        for input in radios {
            let value = (try? input.attr("value")) ?? ""
            let id = (try? input.attr("id")) ?? ""
            var title = value
            if !id.isEmpty,
               let label = try? root.select("label[for=\"\(id)\"]").first()?.text() {
                let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { title = trimmed }
            }
            let isOn = input.hasAttr("checked")
            options.append(AO3FormOption(value: value, title: title, isSelected: isOn))
            if isOn { selected = value }
        }
        return (selected, options)
    }

    private static func parseSeriesMemberships(in form: Element) -> [AO3SeriesMembership] {
        let parsed = parseSelect(form, name: AO3WorkFormField.seriesID)
        return parsed.options.compactMap { option in
            guard let id = Int(option.value), id > 0 else { return nil }
            return AO3SeriesMembership(
                seriesID: id,
                title: option.title,
                isSelected: option.isSelected
            )
        }
    }

    /// "Current Series": each `<dd>` holds the series link and "Remove Work
    /// From Series" (`link_to …, serial_work_path(serial), method: :delete`).
    private static func parseCurrentSeries(in form: Element) -> [AO3CurrentSeries] {
        let removals = (try? form.select("a[href*=/serial_works/]").array()) ?? []
        return removals.compactMap { remove in
            guard let entry = remove.parent()?.parent(),
                  let link = try? entry.select("a[href*=/series/]").first(),
                  let seriesID = seriesID(inPath: (try? link.attr("href")) ?? "")
            else { return nil }
            let href = (try? remove.attr("href")) ?? ""
            return AO3CurrentSeries(
                seriesID: seriesID,
                title: ((try? link.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                serialWorkID: href.split(separator: "/").last.flatMap { Int($0) }
            )
        }
    }

    private static func parseParentWork(in form: Element) -> AO3ParentWorkDraft {
        AO3ParentWorkDraft(
            url: inputValue(form, name: AO3WorkFormField.parentURL)
                ?? inputValue(form, nameContains: "[url]") ?? "",
            title: inputValue(form, name: AO3WorkFormField.parentTitle)
                ?? inputValue(form, nameContains: "parent_work") ?? "",
            author: inputValue(form, name: AO3WorkFormField.parentAuthor) ?? "",
            languageID: inputValue(form, name: AO3WorkFormField.parentLanguageID) ?? "",
            isTranslation: checkboxOn(form, name: AO3WorkFormField.parentTranslation)
        )
    }

    private static func parseExistingParentTitles(in form: Element) -> [String] {
        let links = (try? form.select("#parent-options a[href]").array()) ?? []
        return links.compactMap { try? $0.text() }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.lowercased() != "remove" }
    }

    private static func parseNestedChapter(in form: Element) -> AO3WorkChapterDraft? {
        let content = textareaValue(form, name: AO3WorkFormField.chapterContent)
            .ifEmpty(textareaValue(form, id: "content"))
        let title = inputValue(form, name: AO3WorkFormField.chapterTitle) ?? ""
        let summary = textareaValue(form, name: AO3WorkFormField.chapterSummary)
        // Presence, not content. A New Work form has a chapter field that is
        // *empty* — that is the whole point of it — and returning nil for that made
        // `missingRequiredFields` skip Work Text entirely, so the one field AO3
        // certainly requires was never reported as missing.
        let hasChapterField =
            firstElement(form, tag: "textarea", name: AO3WorkFormField.chapterContent) != nil
                || ((try? form.select("textarea#content").first()) ?? nil) != nil
        if !hasChapterField, content.isEmpty, title.isEmpty, summary.isEmpty { return nil }
        return AO3WorkChapterDraft(
            title: title,
            summary: summary,
            content: content,
            publishedYear: controlValue(form, name: AO3WorkFormField.chapterPublishedYear) ?? "",
            publishedMonth: controlValue(form, name: AO3WorkFormField.chapterPublishedMonth) ?? "",
            publishedDay: controlValue(form, name: AO3WorkFormField.chapterPublishedDay) ?? "",
            contentServed: hasChapterField
        )
    }

    private static func parseCreators(in form: Element, prefix: String) -> AO3CreatorDraft {
        let selectName = "\(prefix)[author_attributes][ids][]"
        let hiddenName = "\(prefix)[author_attributes][ids][]"
        let parsed = parseSelect(form, name: selectName)
        var ids = parsed.options.filter(\.isSelected).map(\.value)
        if ids.isEmpty {
            ids = inputs(form, name: hiddenName)
                .filter { (try? $0.attr("type")) == "hidden" }
                .compactMap { try? $0.attr("value") }
                .filter { !$0.isEmpty }
        }
        let byline = inputValue(form, name: "\(prefix)[author_attributes][byline]") ?? ""
        return AO3CreatorDraft(
            selectedPseudIDs: ids,
            availablePseuds: parsed.options,
            coauthorByline: byline
        )
    }

    private static func parseCarryHiddenFields(in form: Element) -> [AO3WorkHiddenField] {
        let skip: Set<String> = [
            AO3WorkFormField.authenticityToken, "_method", "utf8"
        ]
        var fields: [AO3WorkHiddenField] = []
        var seen = Set<String>()
        for input in (try? form.select("input[type=hidden][name]").array()) ?? [] {
            let name = (try? input.attr("name")) ?? ""
            guard !name.isEmpty, !skip.contains(name), !name.hasSuffix("[]") else { continue }
            guard seen.insert(name).inserted else { continue }
            fields.append(
                AO3WorkHiddenField(name: name, value: (try? input.attr("value")) ?? "")
            )
        }
        return fields
    }

    private static func parsePostedChapterCount(in doc: Document, form: Element) -> Int? {
        if let links = try? doc.select("a[href*=/chapters/][href*=/edit]").array(),
           !links.isEmpty {
            return links.count
        }
        let wip = inputValue(form, name: AO3WorkFormField.wipLength) ?? ""
        if let total = Int(wip), total == 1 { return 1 }
        return nil
    }

    private static func parseImplicationCounts(
        in doc: Document, caution: String
    ) -> WorkStatCounts {
        let fromStats = parseWorkStatCounts(from: (try? doc.html()) ?? "")
        func named(_ label: String) -> Int? {
            let pattern = "(\\d[\\d,]*)\\s+\(label)"
            guard let range = caution.range(of: pattern, options: [.regularExpression, .caseInsensitive])
            else { return nil }
            let digits = caution[range].filter(\.isNumber)
            return digits.isEmpty ? nil : Int(digits)
        }
        return WorkStatCounts(
            chapters: fromStats.chapters ?? named("chapter"),
            kudos: fromStats.kudos ?? named("kudo"),
            comments: fromStats.comments ?? named("comment"),
            bookmarks: fromStats.bookmarks ?? named("bookmark"),
            words: fromStats.words ?? named("word")
        )
    }

    private static func quotedTitle(in text: String) -> String? {
        guard let first = text.firstIndex(of: "\""),
              let last = text.lastIndex(of: "\""),
              first < last
        else { return nil }
        let inner = text[text.index(after: first)..<last]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return inner.isEmpty ? nil : String(inner)
    }

    private static func inputs(_ root: Element, name: String) -> [Element] {
        ((try? root.select("input[name]").array()) ?? []).filter {
            (try? $0.attr("name")) == name
        }
    }

    private static func firstInput(_ root: Element, name: String) -> Element? {
        inputs(root, name: name).first
    }

    private static func firstElement(_ root: Element, tag: String, name: String) -> Element? {
        ((try? root.select("\(tag)[name]").array()) ?? []).first {
            (try? $0.attr("name")) == name
        }
    }

    private static func inputValue(_ root: Element, name: String) -> String? {
        let matches = inputs(root, name: name)
        let visible = matches.first { element in
            let type = (try? element.attr("type")) ?? "text"
            return type != "hidden" && type != "submit"
        }
        return try? (visible ?? matches.first)?.attr("value")
    }

    /// A form control's current value whether AO3 rendered it as an `input` or a
    /// `select`.
    ///
    /// Publication dates are three `select`s with a `selected` option, and reading
    /// them with `inputValue` returned three empty strings — an existing date of
    /// 2020-05-04 arrived in the editor blank, and saving would have republished
    /// the work at today's date.
    private static func controlValue(_ root: Element, name: String) -> String? {
        if let value = inputValue(root, name: name), !value.isEmpty { return value }
        return selectedOptionValue(root, name: name)
    }

    /// The `selected` option's value, falling back to the first option — which is
    /// what a browser submits for a `select` with nothing explicitly selected.
    private static func selectedOptionValue(_ root: Element, name: String) -> String? {
        guard let select = firstElement(root, tag: "select", name: name) else { return nil }
        let options = (try? select.select("option").array()) ?? []
        let chosen = options.first { $0.hasAttr("selected") } ?? options.first
        guard let chosen else { return nil }
        let value = (try? chosen.attr("value")) ?? ""
        return value.isEmpty ? (try? chosen.text()) : value
    }

    private static func inputValue(_ root: Element, nameContains: String) -> String? {
        let match = ((try? root.select("input[name]").array()) ?? []).first {
            ((try? $0.attr("name")) ?? "").contains(nameContains)
        }
        return try? match?.attr("value")
    }

    private static func textareaValue(_ root: Element, name: String) -> String {
        (try? firstElement(root, tag: "textarea", name: name)?.text()) ?? ""
    }

    private static func textareaValue(_ root: Element, id: String) -> String {
        (try? root.select("textarea#\(id)").first()?.text()) ?? ""
    }

    private static func checkboxOn(_ root: Element, name: String) -> Bool {
        inputs(root, name: name).contains { input in
            (try? input.attr("type")) == "checkbox" && input.hasAttr("checked")
        }
    }

    private static func checkboxOn(_ root: Element, id: String) -> Bool {
        (try? root.select("#\(id)").first()?.hasAttr("checked")) ?? false
    }

    private static func optionalCheckbox(_ root: Element, name: String) -> Bool? {
        guard firstInput(root, name: name) != nil else { return nil }
        return checkboxOn(root, name: name)
    }

    private static func submitNamed(_ root: Element, _ name: String) -> Bool {
        inputs(root, name: name).contains { (try? $0.attr("type")) == "submit" }
            || ((try? root.select("button[name]").array()) ?? []).contains {
                (try? $0.attr("name")) == name
            }
    }

    private static func writingAbsoluteURL(_ path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        let withSlash = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
        return URL(string: "https://archiveofourown.org\(withSlash)")
    }

    static func workIDFromPath(_ path: String) -> Int? {
        let parts = path.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(of: "works"), index + 1 < parts.count else {
            return nil
        }
        return Int(parts[index + 1].split(separator: "?").first.map(String.init) ?? "")
    }

    private static func chapterID(inPath path: String) -> Int? {
        let parts = path.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(of: "chapters"), index + 1 < parts.count else {
            return nil
        }
        let raw = parts[index + 1]
        if raw == "new" { return nil }
        return Int(raw.split(separator: "?").first.map(String.init) ?? "")
    }

    private static func seriesID(inPath path: String) -> Int? {
        let parts = path.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(of: "series"), index + 1 < parts.count else {
            return nil
        }
        return Int(parts[index + 1].split(separator: "?").first.map(String.init) ?? "")
    }

    private static func workID(in element: Element) -> Int? {
        if let href = try? element.select("a[href*=/works/]").first()?.attr("href") {
            return workIDFromPath(href)
        }
        return nil
    }
}

private extension String {
    func ifEmpty(_ other: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? other : self
    }
}
