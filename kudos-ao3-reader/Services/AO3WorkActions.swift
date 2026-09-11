import Foundation

/// Native writes for AO3 work / chapter / series / draft / bulk / tag-edit
/// surfaces. Each method: require logged in, fetch CSRF once, one
/// `submitWrite`, never retried, never coalesced.
///
/// Unexercised against a live AO3 session (release gate).
extension AO3AuthService {

    // MARK: Loads (authenticated GET)

    func loadNewWorkForm() async throws -> AO3WorkForm {
        try requireWorkSession()
        return try await loadWorkForm(at: AO3Client.newWorkURL())
    }

    func loadWorkForm(workID: Int) async throws -> AO3WorkForm {
        try requireWorkSession()
        return try await loadWorkForm(at: AO3Client.workEditURL(workID: workID))
    }

    func loadEditTagsForm(workID: Int) async throws -> AO3EditTagsForm {
        try requireWorkSession()
        let html = try await workFormHTML(at: AO3Client.workEditTagsURL(workID: workID))
        return try AO3Client.parseEditTagsForm(from: html)
    }

    func loadChapterForm(workID: Int, chapterID: Int?) async throws -> AO3ChapterForm {
        try requireWorkSession()
        let url = chapterID.map { AO3Client.chapterEditURL(workID: workID, chapterID: $0) }
            ?? AO3Client.newChapterURL(workID: workID)
        let html = try await workFormHTML(at: url)
        return try AO3Client.parseChapterForm(from: html)
    }

    func loadSeriesForm(seriesID: Int) async throws -> AO3SeriesForm {
        try requireWorkSession()
        var form = try AO3Client.parseSeriesForm(
            from: try await workFormHTML(at: AO3Client.seriesEditURL(seriesID: seriesID))
        )
        if let rows = try? AO3Client.parseSeriesManagePage(
            from: try await workFormHTML(at: AO3Client.seriesManageURL(seriesID: seriesID))
        ) {
            form.works = rows
        }
        return form
    }

    func loadSeriesManagePage(seriesID: Int) async throws -> [AO3SeriesWorkRow] {
        try requireWorkSession()
        return try AO3Client.parseSeriesManagePage(
            from: try await workFormHTML(at: AO3Client.seriesManageURL(seriesID: seriesID))
        )
    }

    func loadBulkEditForm(workIDs: [Int]) async throws -> AO3BulkEditForm {
        try requireWorkSession()
        guard let first = workIDs.first else {
            throw AO3WorkWriteError.rejected("Select at least one work.")
        }
        guard let username,
              let url = AO3Client.editMultipleWorksURL(username: username)
        else { throw AO3WorkWriteError.notSignedIn }
        let tokenPage = try await csrfPage(at: AO3Client.workEditURL(workID: first))
        var pairs: [(String, String)] = [
            (AO3WorkFormField.authenticityToken, tokenPage.token)
        ]
        for id in workIDs {
            pairs.append((AO3WorkFormField.workIDs, String(id)))
        }
        // POST /edit_multiple only renders the form; it does not mutate works.
        // Still a POST, so it goes through submitWrite (never retried).
        let request = try writeRequest(
            to: url,
            body: Self.formEncoded(pairs),
            csrf: tokenPage.token,
            referer: url,
            ajax: false
        )
        let (_, body) = try await AO3Client.shared.submitWrite(request)
        return try AO3Client.parseBulkEditForm(from: body)
    }

    func loadDeleteImplications(workID: Int) async throws -> AO3DeleteImplications {
        try requireWorkSession()
        var implications = try AO3Client.parseDeleteImplications(
            from: try await workFormHTML(at: AO3Client.workConfirmDeleteURL(workID: workID))
        )
        let stats = AO3Client.parseWorkStatCounts(
            from: try await workFormHTML(at: AO3Client.workURL(workID: workID))
        )
        if implications.chapters == nil { implications.chapters = stats.chapters }
        if implications.kudos == nil { implications.kudos = stats.kudos }
        if implications.comments == nil { implications.comments = stats.comments }
        if implications.bookmarks == nil { implications.bookmarks = stats.bookmarks }
        if implications.words == nil { implications.words = stats.words }
        return implications
    }

    func loadChapterDeleteImplications(
        workID: Int, chapterID: Int
    ) async throws -> AO3DeleteImplications {
        try requireWorkSession()
        return try AO3Client.parseDeleteImplications(
            from: try await workFormHTML(
                at: AO3Client.chapterConfirmDeleteURL(workID: workID, chapterID: chapterID)
            )
        )
    }

    func loadDrafts(page: Int = 1) async throws -> AO3SearchPage {
        try requireWorkSession()
        guard let username, let url = AO3Client.myDraftsURL(username: username, page: page)
        else { throw AO3WorkWriteError.notSignedIn }
        let request = try authenticatedRequest(for: url)
        return try await AO3Client.shared.draftsPage(for: request, page: page)
    }

    // MARK: Work writes

    /// Create or update a work / draft. Posting notifies subscribers and cannot
    /// be reversed — that is copy, not an extra endpoint. Gifts
    /// (`work[recipients]`) notify by email on post and cannot be taken back.
    /// Locally blocked when `missingRequiredFields()` is non-empty for a post.
    /// Unexercised against a live AO3 session (release gate).
    @discardableResult
    func saveWork(
        _ form: AO3WorkForm, submit: AO3WorkSubmitAction
    ) async throws -> String {
        try requireWorkSession()
        if submit == .post || submit == .postWithoutPreview {
            let missing = form.missingRequiredFields()
            if !missing.isEmpty {
                throw AO3WorkWriteError.missingRequiredFields(missing)
            }
        }
        return try await submitWorkForm(form.actionURL, form.parameters(submit: submit), referer: form.actionURL)
    }

    /// GET `/works/:id/edit_tags` is its own page so a tag fix never opens the
    /// text. Removing a chip is a diff against `current`; the POST is the full
    /// replacement AO3 expects. Non-canonical tags still post.
    @discardableResult
    func editTags(
        workID: Int, current: AO3WorkTagSet, desired: AO3WorkTagSet
    ) async throws -> String {
        try requireWorkSession()
        _ = current.diff(toward: desired)
        let page = try await loadEditTagsForm(workID: workID)
        var form = page
        form.tags = desired
        return try await submitWorkForm(
            form.actionURL,
            form.parameters(submit: .update),
            referer: AO3Client.workEditTagsURL(workID: workID)
        )
    }

    // MARK: Chapter writes

    /// POST `/works/:id/chapters`. Position is omitted on one-shots
    /// (`includePosition == false`) rather than sending a dummy. Draft chapter
    /// posting notifies subscribers.
    @discardableResult
    func createChapter(
        _ form: AO3ChapterForm, submit: AO3WorkSubmitAction = .postWithoutPreview
    ) async throws -> String {
        try requireWorkSession()
        return try await submitWorkForm(
            form.actionURL,
            form.parameters(submit: submit),
            referer: form.actionURL
        )
    }

    @discardableResult
    func updateChapter(
        _ form: AO3ChapterForm, submit: AO3WorkSubmitAction = .update
    ) async throws -> String {
        try requireWorkSession()
        return try await submitWorkForm(
            form.actionURL,
            form.parameters(submit: submit),
            referer: form.actionURL
        )
    }

    /// Separate work write for the chapter total (`work[wip_length]`). Posting a
    /// chapter may also need this; sequential `submitWrite`, never parallel.
    @discardableResult
    func updateWorkTotals(workID: Int, posted: Int?, total: Int) async throws -> String {
        try requireWorkSession()
        var form = try await loadWorkForm(workID: workID)
        form.chapterTotal = String(total)
        if let posted { form.chaptersPosted = posted }
        return try await saveWork(form, submit: form.isPosted ? .update : .saveDraft)
    }

    /// Fan-out: create/update the chapter, then optionally write the work total.
    /// Sequential + coordinator slots. Never parallel.
    @discardableResult
    func saveChapterUpdatingTotal(
        _ form: AO3ChapterForm,
        submit: AO3WorkSubmitAction,
        newTotal: Int?
    ) async throws -> String {
        let created = try await AO3RequestCoordinator.shared.withSlot {
            if form.chapterID == nil {
                try await createChapter(form, submit: submit)
            } else {
                try await updateChapter(form, submit: submit)
            }
        }
        guard let newTotal else { return created }
        return try await AO3RequestCoordinator.shared.withSlot {
            try await updateWorkTotals(
                workID: form.workID, posted: nil, total: newTotal
            )
        }
    }

    // MARK: Series writes

    @discardableResult
    func saveSeries(_ form: AO3SeriesForm) async throws -> String {
        try requireWorkSession()
        if form.openOnAO3ForCreate && form.seriesID == nil {
            throw AO3WorkWriteError.seriesCreateUnavailable
        }
        return try await submitWorkForm(
            form.actionURL, form.parameters(), referer: form.actionURL
        )
    }

    /// Create a series if the new-series form is a simple POST (`series[title]`
    /// etc.). The stock `/series/new` template has no title field — callers
    /// should Open-on-AO3 when `openOnAO3ForCreate` is set. Creating from a
    /// work uses `work[series_attributes][title]` on the work form instead.
    @discardableResult
    func createSeries(title: String, summary: String = "", notes: String = "") async throws -> String {
        try requireWorkSession()
        let html = try await workFormHTML(at: AO3Client.newSeriesURL())
        let parsed = try AO3Client.parseSeriesForm(from: html)
        if parsed.openOnAO3ForCreate {
            throw AO3WorkWriteError.seriesCreateUnavailable
        }
        var form = parsed
        form.title = title
        form.summary = summary
        form.notes = notes
        return try await saveSeries(form)
    }

    /// Reorder is drag-only from the caller's POV: one save, N sequential
    /// POSTs via coordinator slots. Position lives on the work's `SerialWork`.
    @discardableResult
    func reorderSeries(seriesID: Int, orderedWorkIDs: [Int]) async throws -> String {
        try requireWorkSession()
        let manageHTML = try await workFormHTML(at: AO3Client.seriesManageURL(seriesID: seriesID))
        let csrf = try csrfToken(from: manageHTML)
        let rows = try AO3Client.parseSeriesManagePage(from: manageHTML)
        let seriesHTML = try await workFormHTML(at: AO3Client.seriesURL(seriesID: seriesID))
        let serialByWork = try serialWorkMap(
            rows: rows, seriesHTML: seriesHTML, orderedWorkIDs: orderedWorkIDs
        )
        let plan = AO3SeriesReorderPlan.writes(
            seriesID: seriesID,
            orderedWorkIDs: orderedWorkIDs,
            serialByWorkID: serialByWork
        )
        guard plan.count == orderedWorkIDs.count else {
            throw AO3WorkWriteError.rejected("Couldn't match those works to the series.")
        }
        var last = "Series order updated."
        for write in plan {
            last = try await AO3RequestCoordinator.shared.withSlot {
                try await submitWorkForm(
                    AO3Client.seriesUpdatePositionsURL(seriesID: seriesID),
                    write.parameters(csrfToken: csrf),
                    referer: AO3Client.seriesManageURL(seriesID: seriesID)
                )
            }
        }
        return last
    }

    // MARK: Bulk edit

    /// POST selected work ids + add/remove changes. Fields left blank stay
    /// untouched. Rating and language overwrite when set.
    @discardableResult
    /// Bulk edit, in two halves — because AO3's bulk form cannot express one of them.
    ///
    /// **Tags are merged per work and sent per work.** Every tag field on
    /// `update_multiple` replaces rather than appends (the `*_string` setters in
    /// `taggable.rb` assign the whole list), so "add Fluff to these twelve works"
    /// has twelve different correct results and one POST cannot carry them. Sending
    /// the additions raw — which is what this used to do — replaced each work's
    /// tags with just the additions, destroying tags on somebody's published works
    /// with no undo. `applying(to:)` existed for this and was never called.
    ///
    /// The uniform scalars — rating, language, collections, the permission fields —
    /// still go in one POST, because setting those to a single value across a
    /// selection is exactly what they mean and none is a list.
    ///
    /// Fan-out is paced through `AO3RequestCoordinator.withSlot`, and a work whose
    /// tag write fails stops the run rather than leaving half a selection edited
    /// with no report of which half.
    @discardableResult
    func bulkEditWorks(_ changes: AO3BulkEditChanges) async throws -> String {
        try requireWorkSession()
        guard let username,
              let url = AO3Client.updateMultipleWorksURL(username: username)
        else { throw AO3WorkWriteError.notSignedIn }
        guard let first = changes.workIDs.first else {
            throw AO3WorkWriteError.rejected("Select at least one work.")
        }

        var lastResponse = ""
        if changes.hasTagChanges {
            for workID in changes.workIDs {
                lastResponse = try await AO3RequestCoordinator.shared.withSlot {
                    let form = try await loadEditTagsForm(workID: workID)
                    let merged = changes.applying(to: form.tags)
                    return try await editTags(
                        workID: workID, current: form.tags, desired: merged
                    )
                }
            }
        }

        guard changes.hasUniformChanges else { return lastResponse }
        let csrf = try await csrfPage(at: AO3Client.workEditURL(workID: first)).token
        return try await submitWorkForm(
            url,
            changes.parameters(csrfToken: csrf),
            referer: url
        )
    }

    // MARK: Delete

    @discardableResult
    func deleteWork(workID: Int) async throws -> String {
        try requireWorkSession()
        let implications = try await loadDeleteImplications(workID: workID)
        return try await submitDelete(implications)
    }

    @discardableResult
    func deleteDraft(workID: Int) async throws -> String {
        try await deleteWork(workID: workID)
    }

    @discardableResult
    func deleteChapter(workID: Int, chapterID: Int) async throws -> String {
        try requireWorkSession()
        let implications = try await loadChapterDeleteImplications(
            workID: workID, chapterID: chapterID
        )
        return try await submitDelete(implications)
    }

    // MARK: Preview

    /// POSTs AO3's preview action and returns the rendered HTML. Unexercised
    /// against a live session. Does not build a text editor.
    func previewWork(_ form: AO3WorkForm) async throws -> AO3PreviewHTML {
        try requireWorkSession()
        let body = try await postPreview(
            url: form.actionURL,
            parameters: form.parameters(submit: .preview),
            referer: form.actionURL
        )
        return try AO3Client.parsePreviewHTML(from: body)
    }

    func previewChapter(_ form: AO3ChapterForm) async throws -> AO3PreviewHTML {
        try requireWorkSession()
        let body = try await postPreview(
            url: form.actionURL,
            parameters: form.parameters(submit: .preview),
            referer: form.actionURL
        )
        return try AO3Client.parsePreviewHTML(from: body)
    }

    // MARK: - Internals

    private func loadWorkForm(at url: URL) async throws -> AO3WorkForm {
        let html = try await workFormHTML(at: url)
        var form = try AO3Client.parseWorkForm(from: html)
        if let username, let collectionsURL = AO3Client.collectionsURL(username: username, page: 1) {
            let request = try authenticatedRequest(for: collectionsURL)
            if let offers = try? AO3Client.parseCollectionOffers(
                from: try await AO3Client.shared.authenticatedPageHTML(for: request)
            ), !offers.isEmpty {
                form = form.applyingCollectionStates(offers)
            }
        }
        return form
    }

    private func workFormHTML(at url: URL) async throws -> String {
        let request = try authenticatedRequest(for: url)
        return try await AO3Client.shared.authenticatedPageHTML(for: request)
    }

    private func csrfPage(at url: URL) async throws -> (html: String, token: String) {
        do {
            return try await fetchCSRFPage(at: url)
        } catch AO3WriteError.notSignedIn {
            throw AO3WorkWriteError.notSignedIn
        } catch AO3WriteError.noCSRFToken {
            throw AO3WorkWriteError.noCSRFToken
        }
    }

    private func csrfToken(from html: String) throws -> String {
        guard let token = AO3Client.parseCSRFToken(from: html) else {
            throw AO3WorkWriteError.noCSRFToken
        }
        return token
    }

    private func requireWorkSession() throws {
        guard isLoggedIn else { throw AO3WorkWriteError.notSignedIn }
    }

    /// One `submitWrite`. Never retried. Never coalesced.
    /// Unexercised against a live AO3 session (release gate).
    @discardableResult
    private func submitWorkForm(
        _ url: URL, _ params: [(String, String)], referer: URL
    ) async throws -> String {
        let csrf = params.first { $0.0 == AO3WorkFormField.authenticityToken }?.1 ?? ""
        let request = try writeRequest(
            to: url,
            body: Self.formEncoded(params),
            csrf: csrf,
            referer: referer,
            ajax: false
        )
        let (status, body) = try await AO3Client.shared.submitWrite(request)
        if let error = AO3Client.writeErrorMessage(in: body) {
            throw AO3WorkWriteError.rejected(error)
        }
        if let notice = AO3Client.writeSuccessMessage(in: body) {
            return notice
        }
        if (300 ... 399).contains(status) {
            return "Saved."
        }
        if (200 ... 299).contains(status) {
            // Redirect-followed 200 with no flash is common; do not claim a
            // specific success string without evidence.
            if body.localizedCaseInsensitiveContains("successfully") {
                return "Saved."
            }
            throw AO3WorkWriteError.unconfirmed
        }
        throw AO3WorkWriteError.rejected("AO3 didn't accept the change.")
    }

    private func submitDelete(_ implications: AO3DeleteImplications) async throws -> String {
        var params: [(String, String)] = [
            (AO3WorkFormField.authenticityToken, implications.csrfToken)
        ]
        if let method = implications.httpMethodOverride, !method.isEmpty {
            params.append((AO3WorkFormField.methodOverride, method))
        } else {
            params.append((AO3WorkFormField.methodOverride, "delete"))
        }
        return try await submitWorkForm(
            implications.actionURL, params, referer: implications.actionURL
        )
    }

    private func postPreview(
        url: URL, parameters: [(String, String)], referer: URL
    ) async throws -> String {
        let csrf = parameters.first { $0.0 == AO3WorkFormField.authenticityToken }?.1 ?? ""
        let request = try writeRequest(
            to: url,
            body: Self.formEncoded(parameters),
            csrf: csrf,
            referer: referer,
            ajax: false
        )
        let (status, body) = try await AO3Client.shared.submitWrite(request)
        if let error = AO3Client.writeErrorMessage(in: body) {
            throw AO3WorkWriteError.rejected(error)
        }
        guard (200 ... 399).contains(status) else {
            throw AO3WorkWriteError.previewUnavailable
        }
        return body
    }

    private func serialWorkMap(
        rows: [AO3SeriesWorkRow],
        seriesHTML: String,
        orderedWorkIDs: [Int]
    ) throws -> [Int: Int] {
        var map: [Int: Int] = [:]
        for row in rows {
            if let workID = row.workID {
                map[workID] = row.serialWorkID
            }
        }
        if map.count == orderedWorkIDs.count { return map }
        // Series show lists works in position order as `li.work.blurb`; match
        // that order to the manage-page serial rows.
        if let page = try? AO3Client.parseSearchPage(seriesHTML, page: 1) {
            let works = page.works
            for (index, row) in rows.enumerated() where index < works.count {
                map[works[index].id] = row.serialWorkID
            }
        }
        return map
    }
}
