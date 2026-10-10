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
        let (_, body) = try await submitWrite(request)
        return try AO3Client.parseBulkEditForm(from: body)
    }

    func loadDeleteImplications(
        workID: Int, using client: AO3Client = .shared
    ) async throws -> AO3DeleteImplications {
        try requireWorkSession()
        // T-372. This used to go on to read the work's own page for the counts AO3's
        // confirmation page lacks, here and again on the confirmed delete. Nothing shows
        // those counts (the alert is AO3's caution, verbatim), so it was two requests for
        // every delete, and a delete that failed whenever that page could not be read,
        // which is the usual case for an unposted draft. Android never made the read.
        return try AO3Client.parseDeleteImplications(
            from: try await workFormHTML(at: AO3Client.workConfirmDeleteURL(workID: workID), using: client)
        )
    }

    func loadChapterDeleteImplications(
        workID: Int, chapterID: Int, using client: AO3Client = .shared
    ) async throws -> AO3DeleteImplications {
        try requireWorkSession()
        return try AO3Client.parseDeleteImplications(
            from: try await workFormHTML(
                at: AO3Client.chapterConfirmDeleteURL(workID: workID, chapterID: chapterID), using: client
            )
        )
    }

    func loadDrafts(page: Int = 1) async throws -> AO3DraftsPage {
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
    /// Unexercised against a live AO3 session (release gate). `client` is for
    /// the local-stub tests.
    @discardableResult
    func saveWork(
        _ form: AO3WorkForm, submit: AO3WorkSubmitAction, using client: AO3Client = .shared
    ) async throws -> String {
        try requireWorkSession()
        if submit == .post || submit == .postWithoutPreview {
            let missing = form.missingRequiredFields()
            if !missing.isEmpty {
                throw AO3WorkWriteError.missingRequiredFields(missing)
            }
        }
        return try await submitWorkForm(
            form.actionURL, form.parameters(submit: submit), referer: form.actionURL, using: client
        )
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
        _ form: AO3ChapterForm, submit: AO3WorkSubmitAction = .postWithoutPreview,
        using client: AO3Client = .shared
    ) async throws -> String {
        try requireWorkSession()
        return try await submitWorkForm(
            form.actionURL,
            form.parameters(submit: submit),
            referer: form.actionURL,
            using: client
        )
    }

    @discardableResult
    func updateChapter(
        _ form: AO3ChapterForm, submit: AO3WorkSubmitAction = .update, using client: AO3Client = .shared
    ) async throws -> String {
        try requireWorkSession()
        return try await submitWorkForm(
            form.actionURL,
            form.parameters(submit: submit),
            referer: form.actionURL,
            using: client
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
        do {
            let message = try await submitWorkForm(
                form.actionURL, form.parameters(), referer: form.actionURL
            )
            await seriesWasWritten(form.seriesID, title: form.title)
            return message
        } catch AO3WorkWriteError.unconfirmed {
            // AO3 may have saved it: what is kept of the series is in doubt too.
            await seriesWasWritten(form.seriesID, title: nil)
            throw AO3WorkWriteError.unconfirmed
        }
    }

    /// Once AO3 has been sent a series write, the pages kept of that series from before it are not
    /// what AO3 has, whatever it answered, and the screens showing the series read it again. The
    /// series page went on showing the old title, order and works after a save, and the cache
    /// answered with them for five minutes (T-378; Android `WritingSeriesState.seriesChanged`).
    private func seriesWasWritten(_ seriesID: Int?, title: String?) async {
        guard let seriesID else { return }
        await AO3AuthorPageCache.shared.removeSeries(id: seriesID, creator: username)
        lastSeriesWrite = AO3SeriesWrite(
            seriesID: seriesID, count: (lastSeriesWrite?.count ?? 0) + 1, title: title
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

    /// 1br's reorder Save: one POST of AO3's own sortable payload. The manage
    /// page (`series/_series_order`) draws each work as `li#serial_<id>` with a
    /// bare title — no work link — and its jQuery `sortable("serialize")` posts
    /// those ids as `serial[]` in the dragged order, which
    /// `series#update_positions` numbers 1…N (`SerialWork.update(id,
    /// position:)`). The ids are the manage page's own, drafts included; the
    /// public series page (posted works only, paginated) is never used to
    /// match them. The whole list must be the one AO3 lists now, or a partial
    /// renumbering would leave two works at one position. The HTML reply is
    /// a bare redirect, so the manage page is read back and must show the
    /// order, else `.unconfirmed`. `expectedGeneration`: as `deleteChapter`.
    /// Unexercised against a live AO3 session (release gate).
    func reorderSeries(
        seriesID: Int, orderedSerialWorkIDs: [Int], expectedGeneration: Int, using client: AO3Client = .shared
    ) async throws -> [AO3SeriesWorkRow] {
        try requireSessionGeneration(expectedGeneration)
        try requireWorkSession()
        let manageURL = AO3Client.seriesManageURL(seriesID: seriesID)
        let manageHTML = try await workFormHTML(at: manageURL, using: client)
        try requireSessionGeneration(expectedGeneration)
        let csrf = try csrfToken(from: manageHTML)
        let listed = try AO3Client.parseSeriesManagePage(from: manageHTML).map(\.serialWorkID)
        guard listed.count == orderedSerialWorkIDs.count, Set(listed) == Set(orderedSerialWorkIDs) else {
            throw AO3WorkWriteError.rejected(
                "The series changed on AO3 since this screen opened. Reopen it and try again."
            )
        }
        let params = [(AO3WorkFormField.authenticityToken, csrf)]
            + orderedSerialWorkIDs.map { (AO3WorkFormField.serialOrder, String($0)) }
        let request = try writeRequest(
            to: AO3Client.seriesUpdatePositionsURL(seriesID: seriesID),
            body: Self.formEncoded(params),
            csrf: csrf,
            referer: manageURL,
            ajax: false
        )
        let (_, body) = try await submitWrite(request, using: client)
        await seriesWasWritten(seriesID, title: nil)
        if let error = AO3Client.workWriteError(in: body) {
            throw AO3WorkWriteError.rejected(error)
        }
        guard let rows = await readBackManagePage(manageURL, expectedGeneration: expectedGeneration, using: client),
              rows.sorted(by: { $0.position < $1.position }).map(\.serialWorkID) == orderedSerialWorkIDs
        else { throw AO3WorkWriteError.unconfirmed }
        return rows
    }

    /// 1br's Remove works: AO3's "Remove Work From Series" link, which Rails
    /// UJS sends as a POST with `_method=delete` to `/serial_works/:id`. The
    /// work stays posted. `serial_works#destroy` redirects with no flash, so
    /// the manage page is read back as the evidence: the row must be gone, and
    /// the fresh rows are returned. AO3 deletes the series with its last work
    /// (`SerialWork#delete_empty_series`), and the screen's list can be stale,
    /// so the live manage page (the token GET) must list this work and another.
    /// `expectedGeneration`: as `deleteChapter`. Unexercised against a live
    /// AO3 session (release gate).
    func removeWorkFromSeries(
        seriesID: Int, serialWorkID: Int, expectedGeneration: Int, using client: AO3Client = .shared
    ) async throws -> [AO3SeriesWorkRow] {
        try requireSessionGeneration(expectedGeneration)
        try requireWorkSession()
        let manageURL = AO3Client.seriesManageURL(seriesID: seriesID)
        let manageHTML = try await workFormHTML(at: manageURL, using: client)
        try requireSessionGeneration(expectedGeneration)
        let csrf = try csrfToken(from: manageHTML)
        let listed = ((try? AO3Client.parseSeriesManagePage(from: manageHTML)) ?? []).map(\.serialWorkID)
        guard listed.contains(serialWorkID) else {
            throw AO3WorkWriteError.rejected(
                "The series changed on AO3 since this screen opened. Reopen it and try again."
            )
        }
        guard listed.count > 1 else {
            throw AO3WorkWriteError.rejected(
                "It is the series' last work on AO3, and AO3 deletes a series with its last work."
            )
        }
        let request = try writeRequest(
            to: AO3Client.serialWorkURL(serialWorkID: serialWorkID),
            body: Self.formEncoded([
                (AO3WorkFormField.authenticityToken, csrf), (AO3WorkFormField.methodOverride, "delete")
            ]),
            csrf: csrf,
            referer: manageURL,
            ajax: false
        )
        let (_, body) = try await submitWrite(request, using: client)
        await seriesWasWritten(seriesID, title: nil)
        if let error = AO3Client.workWriteError(in: body) {
            throw AO3WorkWriteError.rejected(error)
        }
        guard let rows = await readBackManagePage(manageURL, expectedGeneration: expectedGeneration, using: client),
              !rows.contains(where: { $0.serialWorkID == serialWorkID })
        else { throw AO3WorkWriteError.unconfirmed }
        return rows
    }

    /// The manage page read back after a series write, or nil. Read under
    /// the session that wrote: another account's page proves nothing.
    private func readBackManagePage(
        _ url: URL, expectedGeneration: Int, using client: AO3Client
    ) async -> [AO3SeriesWorkRow]? {
        guard let html = try? await workFormHTML(at: url, using: client),
              sessionGeneration == expectedGeneration
        else { return nil }
        return try? AO3Client.parseSeriesManagePage(from: html)
    }

    // MARK: Bulk edit

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
    func deleteWork(workID: Int, using client: AO3Client = .shared) async throws -> String {
        try requireWorkSession()
        let implications = try await loadDeleteImplications(workID: workID, using: client)
        return try await submitDelete(implications, using: client)
    }

    /// 1bn's bulk Delete: AO3's own last step. Edit Multiple Works' Delete
    /// renders `works/confirm_delete_multiple`, whose form posts `work_ids[]`
    /// and "Yes, Delete Works" to `/users/:login/works/delete_multiple`;
    /// `works#delete_multiple` destroys the signed-in user's works among those
    /// ids and flashes "Your works … were deleted." The app's own alert, naming
    /// the count and the titles, stands in for AO3's confirm page. The CSRF
    /// token comes from Edit Multiple Works' GET page. `expectedGeneration`:
    /// as `deleteChapter`. Unexercised against a live AO3 session (release gate).
    @discardableResult
    func deleteWorks(
        workIDs: [Int], expectedGeneration: Int, using client: AO3Client = .shared
    ) async throws -> String {
        try requireSessionGeneration(expectedGeneration)
        try requireWorkSession()
        guard !workIDs.isEmpty else { throw AO3WorkWriteError.rejected("Select at least one work.") }
        guard let username,
              let url = AO3Client.deleteMultipleWorksURL(username: username),
              let referer = AO3Client.showMultipleWorksURL(username: username)
        else { throw AO3WorkWriteError.notSignedIn }
        let csrf = try csrfToken(from: try await workFormHTML(at: referer, using: client))
        try requireSessionGeneration(expectedGeneration)
        let params = [(AO3WorkFormField.authenticityToken, csrf)]
            + workIDs.map { (AO3WorkFormField.workIDs, String($0)) }
            + [("commit", "Yes, Delete Works")]
        return try await submitWorkForm(url, params, referer: referer, using: client)
    }

    @discardableResult
    func deleteDraft(workID: Int) async throws -> String {
        try await deleteWork(workID: workID)
    }

    /// AO3's own two steps: GET `confirm_delete` for its form, then the
    /// `_method=delete` POST. AO3 refuses the only chapter, or the only posted
    /// one (`chapters#destroy`); that refusal comes back as its error flash.
    /// `expectedGeneration` is the session the editor was opened under, checked
    /// before the GET and again after it, so a sign-in during the GET cannot
    /// send the new account's cookie with the old account's delete (T-240).
    /// Unexercised against a live AO3 session (release gate).
    @discardableResult
    func deleteChapter(
        workID: Int, chapterID: Int, expectedGeneration: Int, using client: AO3Client = .shared
    ) async throws -> String {
        try requireSessionGeneration(expectedGeneration)
        try requireWorkSession()
        let implications = try await loadChapterDeleteImplications(
            workID: workID, chapterID: chapterID, using: client
        )
        try requireSessionGeneration(expectedGeneration)
        return try await submitDelete(implications, using: client)
    }

    // MARK: Preview

    /// POSTs AO3's `preview_button` and returns the rendered page. For
    /// something already on AO3 this only renders (`#update`); for something
    /// new AO3 saves it as a draft first (`#create`) — apply the result with
    /// `adopting(_:)`. Unexercised against a live session.
    func previewWork(_ form: AO3WorkForm, using client: AO3Client = .shared) async throws -> AO3PreviewHTML {
        try requireWorkSession()
        let body = try await postPreview(
            url: form.actionURL,
            parameters: form.parameters(submit: .preview),
            referer: form.actionURL,
            using: client
        )
        return try AO3Client.parsePreviewHTML(from: body)
    }

    func previewChapter(_ form: AO3ChapterForm, using client: AO3Client = .shared) async throws -> AO3PreviewHTML {
        try requireWorkSession()
        let body = try await postPreview(
            url: form.actionURL,
            parameters: form.parameters(submit: .preview),
            referer: form.actionURL,
            using: client
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

    private func workFormHTML(at url: URL, using client: AO3Client = .shared) async throws -> String {
        let request = try authenticatedRequest(for: url)
        return try await client.authenticatedPageHTML(for: request)
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
        _ url: URL, _ params: [(String, String)], referer: URL, using client: AO3Client = .shared
    ) async throws -> String {
        let csrf = params.first { $0.0 == AO3WorkFormField.authenticityToken }?.1 ?? ""
        let request = try writeRequest(
            to: url,
            body: Self.formEncoded(params),
            csrf: csrf,
            referer: referer,
            ajax: false
        )
        let (status, body) = try await submitWrite(request, using: client)
        if let error = AO3Client.workWriteError(in: body) {
            throw AO3WorkWriteError.rejected(error)
        }
        if let notice = AO3Client.workWriteNotice(in: body) {
            return notice
        }
        if (300 ... 399).contains(status) {
            return "Saved."
        }
        if (200 ... 299).contains(status) {
            // Every AO3 work, chapter and series success flashes a notice. A
            // 200 without one proves nothing — and a re-rendered form carries
            // the writer's own text, "successfully" and all.
            throw AO3WorkWriteError.unconfirmed
        }
        throw AO3WorkWriteError.rejected("AO3 didn't accept the change.")
    }

    private func submitDelete(
        _ implications: AO3DeleteImplications, using client: AO3Client = .shared
    ) async throws -> String {
        var params: [(String, String)] = [
            (AO3WorkFormField.authenticityToken, implications.csrfToken)
        ]
        if let method = implications.httpMethodOverride, !method.isEmpty {
            params.append((AO3WorkFormField.methodOverride, method))
        } else {
            params.append((AO3WorkFormField.methodOverride, "delete"))
        }
        return try await submitWorkForm(
            implications.actionURL, params, referer: implications.actionURL, using: client
        )
    }

    private func postPreview(
        url: URL, parameters: [(String, String)], referer: URL, using client: AO3Client
    ) async throws -> String {
        let csrf = parameters.first { $0.0 == AO3WorkFormField.authenticityToken }?.1 ?? ""
        let request = try writeRequest(
            to: url,
            body: Self.formEncoded(parameters),
            csrf: csrf,
            referer: referer,
            ajax: false
        )
        let (status, body) = try await submitWrite(request, using: client)
        if let error = AO3Client.workWriteError(in: body) {
            throw AO3WorkWriteError.rejected(error)
        }
        guard (200 ... 399).contains(status) else {
            throw AO3WorkWriteError.previewUnavailable
        }
        return body
    }
}
