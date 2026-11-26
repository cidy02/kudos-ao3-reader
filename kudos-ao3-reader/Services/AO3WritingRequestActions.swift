import Foundation
import SwiftSoup

/// Native reads and single-shot writes for T-575 writing actions: co-creator
/// invitations, gifts to you, related works, orphaning, removing yourself as a
/// co-creator, and importing works from URLs.
///
/// Every read uses `AO3Client`'s paced authenticated GET pipeline; every write
/// goes through single-shot `submitWrite` / `submitWriteWithURL` (never retried,
/// never coalesced). Unexercised against a live AO3 session (release gate).
///
/// Ground truth: otwarchive master `452391b6` (2026-11-01).
extension AO3AuthService {

    // MARK: - 1. Co-creator invitations

    func loadCoCreatorRequests(
        page: Int = 1,
        using client: AO3Client = .shared
    ) async throws -> AO3CoCreatorRequestsPage {
        let username = try requireWritingRequestUser()
        guard let url = AO3Client.coCreatorRequestsURL(username: username, page: max(page, 1)) else {
            throw AO3WorkWriteError.notSignedIn
        }
        let html = try await writingRequestHTML(at: url, using: client)
        return try AO3Client.parseCoCreatorRequests(from: html, page: max(page, 1))
    }

    /// Accepts or declines (AO3 "Reject") selected co-creator requests via
    /// `POST /users/:login/creatorships` with `_method=put`, `selected[]`, and
    /// `accept=Accept` or `reject=Reject` (`CreatorshipsController#update`,
    /// otwarchive `452391b6`).
    @discardableResult
    func answerCoCreatorRequests(
        ids: [Int],
        accept: Bool,
        page: Int = 1,
        using client: AO3Client = .shared
    ) async throws -> String {
        let username = try requireWritingRequestUser()
        guard !ids.isEmpty else {
            throw AO3WorkWriteError.rejected("Please select at least one co-creator request first.")
        }
        let pageNumber = max(page, 1)
        guard let pageURL = AO3Client.coCreatorRequestsURL(username: username, page: pageNumber) else {
            throw AO3WorkWriteError.notSignedIn
        }
        let generation = sessionGeneration
        let html = try await writingRequestHTML(at: pageURL, using: client)
        try requireSessionGeneration(generation)
        let parsed = try AO3Client.parseCoCreatorRequests(from: html, page: pageNumber)
        let token = parsed.csrfToken
        guard !token.isEmpty else { throw AO3WorkWriteError.noCSRFToken }
        let actionURL = parsed.actionURL ?? pageURL

        var params: [(String, String)] = [
            (AO3WorkFormField.methodOverride, "put"),
            (AO3WorkFormField.authenticityToken, token)
        ]
        for id in ids {
            params.append(("selected[]", String(id)))
        }
        params.append(accept ? ("accept", "Accept") : ("reject", "Reject"))

        let request = try writeRequest(
            to: actionURL,
            body: Self.formEncoded(params),
            csrf: token,
            referer: pageURL,
            ajax: false
        )
        let (status, body) = try await submitWrite(request, using: client)
        await AO3AuthorPageCache.shared.removeAuthorPages(username: username)
        return try writingRequestVerdict(
            status: status,
            body: body,
            includeCaution: true,
            redirectFallback: accept ? "Co-creator request accepted." : "Requests rejected.",
            rejectedFallback: "AO3 couldn't update those co-creator requests."
        )
    }

    // MARK: - 2. Gifts to you

    func loadGifts(
        refused: Bool = false,
        page: Int = 1,
        using client: AO3Client = .shared
    ) async throws -> AO3GiftsPage {
        let username = try requireWritingRequestUser()
        let pageNumber = max(page, 1)
        guard let url = AO3Client.giftsURL(username: username, refused: refused, page: pageNumber) else {
            throw AO3WorkWriteError.notSignedIn
        }
        let html = try await writingRequestHTML(at: url, using: client)
        return try AO3Client.parseGiftsPage(from: html, refused: refused, page: pageNumber)
    }

    /// Refuses (`refused: true`) or accepts (`refused: false`) a gift via
    /// `POST /gifts/:gift_id/toggle_rejected`. Because AO3's endpoint is a
    /// toggle (`GiftsController#toggle_rejected`, otwarchive `452391b6`), this
    /// re-reads the list the row came from first and throws `.stateChanged`
    /// without posting if the row is absent or already in the desired state.
    @discardableResult
    func setGiftRefused(
        giftID: Int,
        workID: Int,
        refused: Bool,
        page: Int = 1,
        using client: AO3Client = .shared
    ) async throws -> String {
        let username = try requireWritingRequestUser()
        let pageNumber = max(page, 1)
        // To refuse, the row must currently live on Accepted (`refused: false`)
        // with a "Refuse Gift" link; to accept, on Refused (`refused: true`)
        // with an "Accept Gift" link.
        let sourceIsRefused = !refused
        guard let listURL = AO3Client.giftsURL(
            username: username, refused: sourceIsRefused, page: pageNumber
        ) else {
            throw AO3WorkWriteError.notSignedIn
        }
        let generation = sessionGeneration
        let html = try await writingRequestHTML(at: listURL, using: client)
        try requireSessionGeneration(generation)
        let currentPage = try AO3Client.parseGiftsPage(
            from: html, refused: sourceIsRefused, page: pageNumber
        )
        guard let row = currentPage.gifts.first(where: { $0.giftID == giftID && $0.workID == workID }),
              row.isRefused != refused
        else {
            throw AO3WorkWriteError.stateChanged
        }
        guard !currentPage.csrfToken.isEmpty else { throw AO3WorkWriteError.noCSRFToken }

        let request = try writeRequest(
            to: AO3Client.toggleGiftRejectedURL(giftID: giftID),
            body: Self.formEncoded([(AO3WorkFormField.authenticityToken, currentPage.csrfToken)]),
            csrf: currentPage.csrfToken,
            referer: listURL,
            ajax: false
        )
        let (status, body) = try await submitWrite(request, using: client)
        await AO3AuthorPageCache.shared.removeAuthorPages(username: username)
        return try writingRequestVerdict(
            status: status,
            body: body,
            includeCaution: true,
            redirectFallback: refused
                ? "This work will no longer be listed among your gifts."
                : "This work will now be listed among your gifts.",
            rejectedFallback: "AO3 couldn't update that gift."
        )
    }

    // MARK: - 3. Related works

    func loadRelatedWorks(
        using client: AO3Client = .shared
    ) async throws -> AO3RelatedWorksPage {
        let username = try requireWritingRequestUser()
        guard let url = AO3Client.relatedWorksURL(username: username) else {
            throw AO3WorkWriteError.notSignedIn
        }
        let html = try await writingRequestHTML(at: url, using: client)
        return try AO3Client.parseRelatedWorks(from: html)
    }

    /// Approves (`approved: true`) or removes (`approved: false`) a reciprocal
    /// link shown on your work via `PATCH /related_works/:id`. Because
    /// `RelatedWorksController#update` (otwarchive `452391b6`) flips
    /// `reciprocal`, this reads `GET /related_works/:id` first and throws
    /// `.stateChanged` without posting if the heading does not match `approved`.
    @discardableResult
    func setRelatedWorkLinkApproved(
        id: Int,
        approved: Bool,
        using client: AO3Client = .shared
    ) async throws -> String {
        let username = try requireWritingRequestUser()
        let showURL = AO3Client.relatedWorkURL(id: id)
        let generation = sessionGeneration
        let html = try await writingRequestHTML(at: showURL, using: client)
        try requireSessionGeneration(generation)
        let show = try AO3Client.parseRelatedWorkShow(from: html)
        let expectedMode: AO3RelatedWorkShowMode = approved ? .approve : .remove
        guard show.mode == expectedMode else {
            throw AO3WorkWriteError.stateChanged
        }

        let params: [(String, String)] = [
            (AO3WorkFormField.methodOverride, show.httpMethodOverride ?? "patch"),
            (AO3WorkFormField.authenticityToken, show.csrfToken),
            ("commit", show.commitValue)
        ]
        let request = try writeRequest(
            to: show.actionURL,
            body: Self.formEncoded(params),
            csrf: show.csrfToken,
            referer: showURL,
            ajax: false
        )
        let (status, body) = try await submitWrite(request, using: client)
        await AO3AuthorPageCache.shared.removeAuthorPages(username: username)
        return try writingRequestVerdict(
            status: status,
            body: body,
            includeCaution: true,
            redirectFallback: approved
                ? "Link was successfully approved"
                : "Link was successfully removed",
            rejectedFallback: "AO3 couldn't update that related-work link."
        )
    }

    /// Removes your own work's link to someone else's work via
    /// `DELETE /related_works/:id` (`RelatedWorksController#destroy`, otwarchive
    /// `452391b6`). Note: `destroy` redirects back without setting `flash[:notice]`,
    /// so a followed 200 confirms deletion by verifying the returned related-works
    /// page no longer lists `id`.
    func removeMyRelatedWorkLink(
        id: Int,
        using client: AO3Client = .shared
    ) async throws {
        let username = try requireWritingRequestUser()
        guard let indexURL = AO3Client.relatedWorksURL(username: username) else {
            throw AO3WorkWriteError.notSignedIn
        }
        let generation = sessionGeneration
        let html = try await writingRequestHTML(at: indexURL, using: client)
        try requireSessionGeneration(generation)
        guard let token = AO3Client.relatedWorkDeleteToken(from: html, id: id) else {
            throw AO3WorkWriteError.noCSRFToken
        }

        let request = try writeRequest(
            to: AO3Client.relatedWorkURL(id: id),
            body: Self.formEncoded([
                (AO3WorkFormField.methodOverride, "delete"),
                (AO3WorkFormField.authenticityToken, token)
            ]),
            csrf: token,
            referer: indexURL,
            ajax: false
        )
        let (status, body) = try await submitWrite(request, using: client)
        await AO3AuthorPageCache.shared.removeAuthorPages(username: username)
        if let error = AO3Client.writingRequestError(in: body, includeCaution: true) {
            throw AO3WorkWriteError.rejected(error)
        }
        if AO3Client.writingRequestNotice(in: body) != nil || (300 ... 399).contains(status) {
            return
        }
        if (200 ... 299).contains(status),
           let refreshed = try? AO3Client.parseRelatedWorks(from: body) {
            let stillPresent = refreshed.translationsByMe.contains { $0.id == id }
                || refreshed.thatInspiredMe.contains { $0.id == id }
            if !stillPresent { return }
        }
        if (200 ... 299).contains(status) {
            throw AO3WorkWriteError.unconfirmed
        }
        throw AO3WorkWriteError.rejected("AO3 couldn't remove that related-work link.")
    }

    // MARK: - 4. Orphan

    /// Loads `GET /orphans/new?…` for one work, several works, or a series.
    /// Throws `.notOwned` if AO3 redirects with `"You don't have permission to
    /// orphan that!"` (`OrphansController#new`, otwarchive `452391b6`).
    func loadOrphanForm(
        _ target: AO3OrphanTarget,
        using client: AO3Client = .shared
    ) async throws -> AO3OrphanForm {
        _ = try requireWritingRequestUser()
        guard let url = AO3Client.orphanNewURL(for: target) else {
            throw AO3WorkWriteError.rejected("Select at least one work.")
        }
        let html = try await writingRequestHTML(at: url, using: client)
        return try AO3Client.parseOrphanForm(from: html, target: target)
    }

    /// Enumerates every work in `seriesID` for Orphan's "Keep a copy" step.
    ///
    /// Ground truth (`otwarchive 452391b6`):
    /// - `GET /series/:id/manage` (`SeriesController#manage`, owner-only, unpaginated)
    ///   lists every work in the series (including restricted works and drafts), but
    ///   `series/_series_order.html.erb` renders only `li#serial_<id>` + bare title
    ///   with no `work_id`.
    /// - Signed-in `GET /series/:id` (`SeriesController#show`, paginated) lists every
    ///   posted work visible to the owner (including registered-users-only works that
    ///   anonymous `GET /series/:id` omits) with its `work_id`, but omits drafts
    ///   (`.posted`).
    ///
    /// Reads `/series/:id/manage` as the authoritative manifest and signed-in
    /// `/series/:id` for work IDs, then reconciles the two. Throws
    /// `AO3OrphanCopyError` if any work is a draft (AO3's `DownloadsController`
    /// refuses drafts) or cannot be resolved to a downloadable work ID.
    func loadSeriesWorksForOrphanCopy(
        seriesID: Int,
        using client: AO3Client = .shared
    ) async throws -> [AO3OrphanCopyWork] {
        _ = try requireWritingRequestUser()
        let generation = sessionGeneration
        try Task.checkCancellation()
        let manageHTML = try await writingRequestHTML(
            at: AO3Client.seriesManageURL(seriesID: seriesID),
            using: client
        )
        try requireSessionGeneration(generation)
        let manageRows = try AO3Client.parseSeriesManagePage(from: manageHTML)
            .sorted { $0.position < $1.position }
        if let draft = manageRows.first(where: \.isDraft) {
            throw AO3OrphanCopyError.draftWorkCannotBeDownloaded(title: draft.title)
        }
        let needsShowIDs = manageRows.contains { $0.workID == nil }
        var postedWorks: [AO3WorkSummary] = []
        if needsShowIDs {
            var page = 1
            let baseURL = AO3Client.seriesURL(seriesID: seriesID)
            while let pageURL = AO3Client.seriesPageURL(baseURL, page: page) {
                try Task.checkCancellation()
                let html = try await writingRequestHTML(at: pageURL, using: client)
                try requireSessionGeneration(generation)
                let parsed = try AO3Client.parseSearchPage(html, page: page)
                postedWorks.append(contentsOf: parsed.works)
                if parsed.works.isEmpty || page >= parsed.totalPages { break }
                page += 1
            }
        }
        return try Self.reconcileSeriesOrphanWorks(manageRows: manageRows, postedWorks: postedWorks)
    }

    static func reconcileSeriesOrphanWorks(
        manageRows: [AO3SeriesWorkRow],
        postedWorks: [AO3WorkSummary]
    ) throws -> [AO3OrphanCopyWork] {
        var remaining = postedWorks
        var items: [AO3OrphanCopyWork] = []
        var seenIDs = Set<Int>()
        for row in manageRows {
            if row.isDraft {
                throw AO3OrphanCopyError.draftWorkCannotBeDownloaded(title: row.title)
            }
            if let directID = row.workID {
                if let idx = remaining.firstIndex(where: { $0.id == directID }) {
                    remaining.remove(at: idx)
                }
                if seenIDs.insert(directID).inserted {
                    items.append(AO3OrphanCopyWork(workID: directID, title: row.title))
                }
                continue
            }
            let targetTitle = normalizedSeriesTitle(row.title)
            let matchIndex = remaining.firstIndex {
                $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    == row.title.trimmingCharacters(in: .whitespacesAndNewlines)
            } ?? remaining.firstIndex { normalizedSeriesTitle($0.title) == targetTitle }
            guard let matchIndex else {
                throw AO3OrphanCopyError.unenumerableWork(title: row.title)
            }
            let work = remaining.remove(at: matchIndex)
            if seenIDs.insert(work.id).inserted {
                items.append(AO3OrphanCopyWork(workID: work.id, title: work.title))
            }
        }
        for extra in remaining where seenIDs.insert(extra.id).inserted {
            items.append(AO3OrphanCopyWork(workID: extra.id, title: extra.title))
        }
        return items
    }

    private static func normalizedSeriesTitle(_ raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    /// Permanently orphans `target` via `POST /orphans` (`OrphansController#create`,
    /// otwarchive `452391b6`). `keepPseudCopy == false` sends `use_default=true`
    /// ("Take my pseud off as well"); `true` sends `use_default=false` ("Leave a
    /// copy of my pseud on"). Never sends `pseud_id`. Never retried.
    @discardableResult
    func orphan(
        _ target: AO3OrphanTarget,
        keepPseudCopy: Bool,
        form: AO3OrphanForm,
        using client: AO3Client = .shared
    ) async throws -> String {
        let username = try requireWritingRequestUser()
        guard form.target == target else {
            throw AO3WorkWriteError.stateChanged
        }
        guard let referer = AO3Client.orphanNewURL(for: target) else {
            throw AO3WorkWriteError.rejected("Select at least one work.")
        }
        guard !form.csrfToken.isEmpty else { throw AO3WorkWriteError.noCSRFToken }

        var params: [(String, String)] = [
            (AO3WorkFormField.authenticityToken, form.csrfToken),
            ("use_default", keepPseudCopy ? "false" : "true")
        ]
        switch target {
        case let .work(id):
            params.append((AO3WorkFormField.workIDs, String(id)))
        case let .works(ids):
            guard !ids.isEmpty else {
                throw AO3WorkWriteError.rejected("Select at least one work.")
            }
            for id in ids {
                params.append((AO3WorkFormField.workIDs, String(id)))
            }
        case let .series(id):
            params.append(("series_id", String(id)))
        }
        params.append(("commit", form.submitLabel))

        let request = try writeRequest(
            to: form.actionURL,
            body: Self.formEncoded(params),
            csrf: form.csrfToken,
            referer: referer,
            ajax: false
        )
        let (status, body) = try await submitWrite(request, using: client)
        await AO3AuthorPageCache.shared.removeAuthorPages(username: username)
        if let error = AO3Client.writingRequestError(in: body, includeCaution: true) {
            if AO3Client.isNotOwnedOrphanError(error) {
                throw AO3WorkWriteError.notOwned
            }
            throw AO3WorkWriteError.rejected(error)
        }
        if let notice = AO3Client.writingRequestNotice(in: body) {
            if case let .series(seriesID) = target { await seriesWasWritten(seriesID, title: nil) }
            return notice
        }
        if (300 ... 399).contains(status) {
            if case let .series(seriesID) = target { await seriesWasWritten(seriesID, title: nil) }
            return "Orphaning was successful."
        }
        if (200 ... 299).contains(status) || (500 ... 599).contains(status) {
            if case let .series(seriesID) = target { await seriesWasWritten(seriesID, title: nil) }
            throw AO3WorkWriteError.unconfirmed
        }
        throw AO3WorkWriteError.rejected("AO3 couldn't orphan that.")
    }

    // MARK: - 5. Remove me as a co-creator

    /// Removes the signed-in user as a co-creator of a work via
    /// `PATCH /works/:id/remove_user_creatorship` (`WorksController#remove_user_creatorship`,
    /// otwarchive `452391b6`). Throws `.onlyCreator` if the user is the sole
    /// creator (detected before posting when the edit page omits the button, or
    /// on AO3's redirect to `/orphans/new?work_id=…`).
    @discardableResult
    func removeMeAsCoCreator(
        workID: Int,
        using client: AO3Client = .shared
    ) async throws -> String {
        let username = try requireWritingRequestUser()
        let editURL = AO3Client.workEditURL(workID: workID)
        let actionURL = AO3Client.workRemoveUserCreatorshipURL(workID: workID)
        let generation = sessionGeneration
        let html = try await writingRequestHTML(at: editURL, using: client)
        try requireSessionGeneration(generation)
        let button = try AO3Client.removeMeButtonState(
            in: html,
            actionPath: actionURL.path,
            isRecognizedOwnerPage: { doc in
                (try? doc.select("form#work-form, form.work.post").first()) != nil
            }
        )
        guard button.present else { throw AO3WorkWriteError.onlyCreator }
        guard let token = button.token else { throw AO3WorkWriteError.noCSRFToken }

        let request = try writeRequest(
            to: actionURL,
            body: Self.formEncoded([
                (AO3WorkFormField.methodOverride, "patch"),
                (AO3WorkFormField.authenticityToken, token)
            ]),
            csrf: token,
            referer: editURL,
            ajax: false
        )
        let (status, body, finalURL) = try await submitWriteWithURL(request, using: client)
        if AO3Client.isOrphanRedirect(finalURL: finalURL, body: body) {
            throw AO3WorkWriteError.onlyCreator
        }
        await AO3AuthorPageCache.shared.removeAuthorPages(username: username)
        return try writingRequestVerdict(
            status: status,
            body: body,
            includeCaution: true,
            redirectFallback: "You have been removed as a creator from the work.",
            rejectedFallback: "AO3 couldn't remove you as a co-creator."
        )
    }

    /// Removes the signed-in user as a co-creator of a series via
    /// `PATCH /series/:id/remove_user_creatorship` (`SeriesController#remove_user_creatorship`,
    /// otwarchive `452391b6`). Throws `.onlyCreator` if the user is the sole
    /// creator (when series navigation omits the button or AO3 redirects to
    /// `/orphans/new?series_id=…`).
    @discardableResult
    func removeMeAsCoCreator(
        seriesID: Int,
        using client: AO3Client = .shared
    ) async throws -> String {
        let username = try requireWritingRequestUser()
        let seriesURL = AO3Client.seriesURL(seriesID: seriesID)
        let actionURL = AO3Client.seriesRemoveUserCreatorshipURL(seriesID: seriesID)
        let generation = sessionGeneration
        let html = try await writingRequestHTML(at: seriesURL, using: client)
        try requireSessionGeneration(generation)
        let button = try AO3Client.removeMeButtonState(
            in: html,
            actionPath: actionURL.path,
            isRecognizedOwnerPage: { doc in
                (try? doc.select("ul.navigation.actions a[href*=/series/\(seriesID)/edit]").first()) != nil
                    || (try? doc.select("ul.navigation.actions a[href*=/orphans/new]").first()) != nil
            }
        )
        guard button.present else { throw AO3WorkWriteError.onlyCreator }
        guard let token = button.token else { throw AO3WorkWriteError.noCSRFToken }

        let request = try writeRequest(
            to: actionURL,
            body: Self.formEncoded([
                (AO3WorkFormField.methodOverride, "patch"),
                (AO3WorkFormField.authenticityToken, token)
            ]),
            csrf: token,
            referer: seriesURL,
            ajax: false
        )
        let (status, body, finalURL) = try await submitWriteWithURL(request, using: client)
        if AO3Client.isOrphanRedirect(finalURL: finalURL, body: body) {
            throw AO3WorkWriteError.onlyCreator
        }
        await AO3AuthorPageCache.shared.removeAuthorPages(username: username)
        do {
            let notice = try writingRequestVerdict(
                status: status,
                body: body,
                includeCaution: true,
                redirectFallback: "You have been removed as a creator from the series and its works.",
                rejectedFallback: "AO3 couldn't remove you as a co-creator."
            )
            await seriesWasWritten(seriesID, title: nil)
            return notice
        } catch AO3WorkWriteError.unconfirmed {
            await seriesWasWritten(seriesID, title: nil)
            throw AO3WorkWriteError.unconfirmed
        }
    }

    // MARK: - 6. Import from a URL

    func loadImportForm(
        using client: AO3Client = .shared
    ) async throws -> AO3ImportForm {
        _ = try requireWritingRequestUser()
        let html = try await writingRequestHTML(at: AO3Client.importWorkFormURL(), using: client)
        return try AO3Client.parseImportForm(from: html)
    }

    /// Submits `POST /works/import` (`WorksController#import`, otwarchive
    /// `452391b6`). Single-shot, never retried.
    func importWorks(
        _ importRequest: AO3ImportRequest,
        form: AO3ImportForm,
        using client: AO3Client = .shared
    ) async throws -> AO3ImportResult {
        let username = try requireWritingRequestUser()
        guard !form.csrfToken.isEmpty else { throw AO3WorkWriteError.noCSRFToken }
        let params = importRequest.parameters(csrfToken: form.csrfToken)
        let request = try writeRequest(
            to: form.actionURL,
            body: Self.formEncoded(params),
            csrf: form.csrfToken,
            referer: AO3Client.importWorkFormURL(),
            ajax: false
        )
        let (status, body, finalURL) = try await submitWriteWithURL(request, using: client)
        await AO3AuthorPageCache.shared.removeAuthorPages(username: username)
        return try AO3Client.parseImportResult(status: status, body: body, finalURL: finalURL)
    }

    // MARK: - Internals

    private func requireWritingRequestUser() throws -> String {
        guard isLoggedIn, let username, !username.isEmpty else {
            throw AO3WorkWriteError.notSignedIn
        }
        return username
    }

    private func writingRequestHTML(at url: URL, using client: AO3Client) async throws -> String {
        let request = try authenticatedRequest(for: url)
        let html = try await client.authenticatedPageHTML(for: request)
        // Public pages (`/users/:login/gifts`, `/users/:login/related_works`,
        // `/series/:id`) answer 200 logged-out HTML instead of redirecting to
        // `/users/login` when a session expires.
        if LiveAO3SessionValidator.looksLikeAO3Page(html: html),
           !LiveAO3SessionValidator.isLoggedIn(html: html) {
            throw AO3Error.authenticationRequired
        }
        return html
    }

    private func submitWriteWithURL(
        _ request: URLRequest,
        using client: AO3Client = .shared
    ) async throws -> (status: Int, body: String, finalURL: URL?) {
        try await client.submitWriteWithURL(
            request,
            isCurrentWriteSession: { [weak self] prepared in
                self?.writeSessionStamp == prepared
            }
        )
    }

    private func writingRequestVerdict(
        status: Int,
        body: String,
        includeCaution: Bool,
        redirectFallback: String,
        rejectedFallback: String
    ) throws -> String {
        if let error = AO3Client.writingRequestError(in: body, includeCaution: includeCaution) {
            throw AO3WorkWriteError.rejected(error)
        }
        if let notice = AO3Client.writingRequestNotice(in: body) {
            return notice
        }
        if (300 ... 399).contains(status) {
            return redirectFallback
        }
        if (200 ... 299).contains(status) {
            throw AO3WorkWriteError.unconfirmed
        }
        throw AO3WorkWriteError.rejected(rejectedFallback)
    }
}
