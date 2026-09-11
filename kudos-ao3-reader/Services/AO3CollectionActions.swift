import Foundation

/// Native collection writes. Each action fetches one CSRF page, then a **single**
/// `submitWrite` POST — never retried, never coalesced. Batch item updates still
/// POST one item at a time, sequentially, each `submitWrite` inside a coordinator
/// slot.
///
/// Unexercised against a live AO3 session — a release gate, not a reason these
/// endpoints are unbuilt.
///
/// Close and delete stay on AO3 (irreversible: unrevealed works become revealed
/// and anonymous creators are shown). Use `AO3CollectionForm.deleteOpenOnAO3` /
/// `closeOpenOnAO3` rather than a native write.
enum AO3CollectionWriteError: LocalizedError, Equatable {
    case notSignedIn
    case noCSRFToken
    case rejected(String)
    case unconfirmed
    case emptyRejectReason
    case invalidName

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Log in to AO3 first."
        case .noCSRFToken: "Couldn't prepare the request. Try again, or open the collection on AO3."
        case let .rejected(reason): reason
        case .unconfirmed:
            "AO3 replied but didn't confirm the change went through. Check on AO3 before trying again."
        case .emptyRejectReason:
            "A reject reason is required. The item stays in the queue until AO3 accepts the rejection."
        case .invalidName:
            "That URL name isn't valid on AO3. Use letters, numbers, and underscores, and don't start or end with an underscore."
        }
    }
}

extension AO3AuthService {

    /// Unexercised against a live AO3 session — a release gate, not a reason this
    /// endpoint is unbuilt. Single-shot `submitWrite`; never retried or coalesced.
    /// AO3's New Collection form — the hidden fields, the CSRF token and whatever
    /// defaults the account carries. Fetched rather than assumed, so a form the app
    /// posts is the form AO3 served.
    func collectionNewForm() async throws -> AO3CollectionForm {
        guard isLoggedIn else { throw AO3CollectionWriteError.notSignedIn }
        let request = try authenticatedRequest(for: AO3CollectionURL.new())
        return try await AO3Client.shared.collectionNewForm(request: request)
    }

    func createCollection(_ form: AO3CollectionForm) async throws -> AO3CollectionSaveOutcome {
        guard isLoggedIn else { throw AO3CollectionWriteError.notSignedIn }
        guard AO3Client.collectionNameFormatIsValid(form.name) else {
            var invalid = form
            invalid.fieldErrors[AO3CollectionParam.name] = AO3CollectionWriteError.invalidName.errorDescription ?? ""
            return .invalid(invalid)
        }
        let (html, token) = try await fetchCSRFPage(at: AO3CollectionURL.new())
        var posted = form
        posted.csrfToken = token
        if posted.actionURL.absoluteString.isEmpty {
            posted.actionURL = AO3CollectionURL.create()
        }
        return try await submitCollectionForm(posted, referer: AO3CollectionURL.new(), fallbackHTML: html)
    }

    /// Unexercised against a live AO3 session — a release gate, not a reason this
    /// endpoint is unbuilt. Single-shot `submitWrite`; never retried or coalesced.
    func updateCollection(slug: String, form: AO3CollectionForm) async throws -> AO3CollectionSaveOutcome {
        guard isLoggedIn else { throw AO3CollectionWriteError.notSignedIn }
        let referer = AO3CollectionURL.edit(slug: slug)
        let (html, token) = try await fetchCSRFPage(at: referer)
        var posted = form
        posted.csrfToken = token
        posted.collectionSlug = slug
        if posted.nameIsLocked { posted.name = slug }
        return try await submitCollectionForm(posted, referer: referer, fallbackHTML: html)
    }

    /// Confirmed one-way reveal. Unchecks `unrevealed` on the live edit form and
    /// POSTs the whole form so other fields are not wiped. Unexercised against a
    /// live AO3 session — a release gate, not a reason this endpoint is unbuilt.
    func revealCollection(slug: String) async throws -> String {
        guard isLoggedIn else { throw AO3CollectionWriteError.notSignedIn }
        var form = try await collectionEditForm(slug: slug)
        form.isUnrevealed = false
        switch try await updateCollection(slug: slug, form: form) {
        case let .saved(message, _): return message
        case let .invalid(invalid):
            throw AO3CollectionWriteError.rejected(invalid.generalErrors.first ?? "Couldn't reveal the collection.")
        }
    }

    /// Confirmed one-way un-anon. Unchecks `anonymous` on the live edit form and
    /// POSTs the whole form. Unexercised against a live AO3 session — a release
    /// gate, not a reason this endpoint is unbuilt.
    func unanonCollection(slug: String) async throws -> String {
        guard isLoggedIn else { throw AO3CollectionWriteError.notSignedIn }
        var form = try await collectionEditForm(slug: slug)
        form.isAnonymous = false
        switch try await updateCollection(slug: slug, form: form) {
        case let .saved(message, _): return message
        case let .invalid(invalid):
            throw AO3CollectionWriteError.rejected(invalid.generalErrors.first ?? "Couldn't un-anon the collection.")
        }
    }

    /// Unexercised against a live AO3 session — a release gate, not a reason this
    /// endpoint is unbuilt. Single-shot `submitWrite`; never retried or coalesced.
    /// On failure the item remains in the queue — this method only throws.
    func approveCollectionItem(slug: String, itemID: Int) async throws {
        try await updateCollectionItems(
            slug: slug,
            drafts: [
                AO3CollectionItemDraft(itemID: itemID, moderatorApproval: .approved)
            ]
        )
    }

    /// Reject reason is required by artboard 1ce. AO3's item form has no reason
    /// field (`collection_items_controller` permits only approval/unrevealed/
    /// anonymous/remove), so the reason is validated locally and never invented
    /// as a POST param. On failure the item remains in the queue.
    ///
    /// Unexercised against a live AO3 session — a release gate, not a reason this
    /// endpoint is unbuilt.
    func rejectCollectionItem(slug: String, itemID: Int, reason: String) async throws {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AO3CollectionWriteError.emptyRejectReason }
        try await updateCollectionItems(
            slug: slug,
            drafts: [
                AO3CollectionItemDraft(itemID: itemID, moderatorApproval: .rejected)
            ]
        )
    }

    /// 1s stages then submits. Each item is still one `submitWrite`, sequential,
    /// never coalesced, never parallel; each POST takes a coordinator slot.
    /// Unexercised against a live AO3 session — a release gate, not a reason this
    /// endpoint is unbuilt.
    func updateCollectionItems(slug: String, drafts: [AO3CollectionItemDraft]) async throws {
        guard isLoggedIn else { throw AO3CollectionWriteError.notSignedIn }
        guard !drafts.isEmpty else { return }
        let referer = AO3CollectionURL.items(slug: slug, tab: .unreviewed, page: 1)
        let (html, token) = try await fetchCSRFPage(at: referer)
        let page = try AO3Client.parseCollectionItemsPage(html, slug: slug, tab: .unreviewed, page: 1)
        for draft in drafts {
            try Task.checkCancellation()
            let params = AO3Client.collectionItemParameters(
                draft, csrf: token, methodOverride: page.httpMethodOverride ?? "patch"
            )
            let request = try writeRequest(
                to: page.actionURL,
                body: Self.formEncoded(params),
                csrf: token,
                referer: referer,
                ajax: false
            )
            let (status, body) = try await AO3RequestCoordinator.shared.withSlot {
                try await AO3Client.shared.submitWrite(request)
            }
            try throwIfCollectionWriteFailed(
                status: status, body: body, fallback: "AO3 couldn't update that collection item."
            )
        }
    }

    /// Unexercised against a live AO3 session — a release gate, not a reason this
    /// endpoint is unbuilt. Single-shot `submitWrite`; never retried or coalesced.
    func acceptMember(slug: String, participantID: Int) async throws {
        try await updateParticipantRole(slug: slug, participantID: participantID, role: .member)
    }

    /// Unexercised against a live AO3 session — a release gate, not a reason this
    /// endpoint is unbuilt. Single-shot `submitWrite`; never retried or coalesced.
    func declineMember(slug: String, participantID: Int) async throws {
        guard isLoggedIn else { throw AO3CollectionWriteError.notSignedIn }
        let referer = AO3CollectionURL.participants(slug: slug)
        let (_, token) = try await fetchCSRFPage(at: referer)
        let body = Self.formEncoded([("_method", "delete"), ("authenticity_token", token)])
        let request = try writeRequest(
            to: AO3CollectionURL.participant(slug: slug, id: participantID),
            body: body, csrf: token, referer: referer, ajax: false
        )
        let (status, response) = try await AO3Client.shared.submitWrite(request)
        try throwIfCollectionWriteFailed(
            status: status, body: response, fallback: "AO3 couldn't decline that member."
        )
    }

    /// Unexercised against a live AO3 session — a release gate, not a reason this
    /// endpoint is unbuilt. Single-shot `submitWrite`; never retried or coalesced.
    func inviteMaintainer(slug: String, byline: String) async throws {
        guard isLoggedIn else { throw AO3CollectionWriteError.notSignedIn }
        let invite = byline.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !invite.isEmpty else {
            throw AO3CollectionWriteError.rejected("Name someone to invite.")
        }
        let referer = AO3CollectionURL.participants(slug: slug)
        let (_, token) = try await fetchCSRFPage(at: referer)
        let params: [(String, String)] = [
            ("authenticity_token", token),
            (AO3CollectionParam.participantsToInvite, invite)
        ]
        let request = try writeRequest(
            to: AO3CollectionURL.participantsAdd(slug: slug),
            body: Self.formEncoded(params), csrf: token, referer: referer, ajax: false
        )
        let (status, response) = try await AO3Client.shared.submitWrite(request)
        try throwIfCollectionWriteFailed(
            status: status, body: response, fallback: "AO3 couldn't invite that maintainer."
        )
    }

    /// Unexercised against a live AO3 session — a release gate, not a reason this
    /// endpoint is unbuilt. Single-shot `submitWrite`; never retried or coalesced.
    func joinCollection(slug: String) async throws {
        guard isLoggedIn else { throw AO3CollectionWriteError.notSignedIn }
        guard let showURL = AO3CollectionURL.show(slug: slug) else {
            throw AO3CollectionWriteError.rejected("Couldn't build that collection URL.")
        }
        let (_, token) = try await fetchCSRFPage(at: showURL)
        let request = try writeRequest(
            to: AO3CollectionURL.participantsJoin(slug: slug),
            body: Self.formEncoded([("authenticity_token", token)]),
            csrf: token, referer: showURL, ajax: false
        )
        let (status, response) = try await AO3Client.shared.submitWrite(request)
        try throwIfCollectionWriteFailed(
            status: status, body: response, fallback: "AO3 couldn't join that collection."
        )
    }

    /// Unexercised against a live AO3 session — a release gate, not a reason this
    /// endpoint is unbuilt. Single-shot `submitWrite`; never retried or coalesced.
    func leaveCollection(slug: String, participantID: Int) async throws {
        guard isLoggedIn else { throw AO3CollectionWriteError.notSignedIn }
        guard let showURL = AO3CollectionURL.show(slug: slug) else {
            throw AO3CollectionWriteError.rejected("Couldn't build that collection URL.")
        }
        let (_, token) = try await fetchCSRFPage(at: showURL)
        let request = try writeRequest(
            to: AO3CollectionURL.participant(slug: slug, id: participantID),
            body: Self.formEncoded([("_method", "delete"), ("authenticity_token", token)]),
            csrf: token, referer: showURL, ajax: false
        )
        let (status, response) = try await AO3Client.shared.submitWrite(request)
        try throwIfCollectionWriteFailed(
            status: status, body: response, fallback: "AO3 couldn't leave that collection."
        )
    }

    /// Unexercised against a live AO3 session — a release gate, not a reason this
    /// endpoint is unbuilt. Single-shot `submitWrite`; never retried or coalesced.
    func submitWorkToCollection(workID: Int, collectionSlug: String) async throws {
        guard isLoggedIn else { throw AO3CollectionWriteError.notSignedIn }
        let workURL = Self.workURL(workID)
        let (_, token) = try await fetchCSRFPage(at: workURL)
        let params: [(String, String)] = [
            ("authenticity_token", token),
            (AO3CollectionParam.collectionNames, collectionSlug)
        ]
        let request = try writeRequest(
            to: AO3CollectionURL.workCollectionItems(workID: workID),
            body: Self.formEncoded(params), csrf: token, referer: workURL, ajax: false
        )
        let (status, response) = try await AO3Client.shared.submitWrite(request)
        try throwIfCollectionWriteFailed(
            status: status, body: response, fallback: "AO3 couldn't submit the work to that collection."
        )
    }

    // MARK: - Internals

    /// AO3's Edit Collection form, prefilled. Internal rather than private since
    /// `AO3CollectionFormView` binds to it — and it stays here, in the collections
    /// networking file, rather than the view building its own request:
    /// `AO3_NETWORKING_POLICY` puts every AO3 request through this layer.
    func collectionEditForm(slug: String) async throws -> AO3CollectionForm {
        let request = try authenticatedRequest(for: AO3CollectionURL.edit(slug: slug))
        return try await AO3Client.shared.collectionEditForm(slug: slug, request: request)
    }

    private func updateParticipantRole(
        slug: String, participantID: Int, role: AO3CollectionParticipantRole
    ) async throws {
        guard isLoggedIn else { throw AO3CollectionWriteError.notSignedIn }
        let referer = AO3CollectionURL.participants(slug: slug)
        let (_, token) = try await fetchCSRFPage(at: referer)
        let params: [(String, String)] = [
            ("_method", "patch"),
            ("authenticity_token", token),
            (AO3CollectionParam.participantRole, role.rawValue)
        ]
        let request = try writeRequest(
            to: AO3CollectionURL.participant(slug: slug, id: participantID),
            body: Self.formEncoded(params), csrf: token, referer: referer, ajax: false
        )
        let (status, response) = try await AO3Client.shared.submitWrite(request)
        try throwIfCollectionWriteFailed(
            status: status, body: response, fallback: "AO3 couldn't update that member."
        )
    }

    private func submitCollectionForm(
        _ form: AO3CollectionForm, referer: URL, fallbackHTML: String
    ) async throws -> AO3CollectionSaveOutcome {
        let params = AO3Client.collectionFormParameters(form)
        let request = try writeRequest(
            to: form.actionURL,
            body: Self.formEncoded(params),
            csrf: form.csrfToken,
            referer: referer,
            ajax: false
        )
        let (status, body) = try await AO3Client.shared.submitWrite(request)
        if let error = AO3Client.writeErrorMessage(in: body) {
            var invalid = (try? AO3Client.parseCollectionForm(body, slug: form.collectionSlug)) ?? form
            invalid.generalErrors = [error] + invalid.generalErrors
            return .invalid(invalid)
        }
        if let notice = AO3Client.writeSuccessMessage(in: body)
            ?? (body.localizedCaseInsensitiveContains("successfully created")
                ? "Collection was successfully created."
                : nil)
            ?? (body.localizedCaseInsensitiveContains("successfully updated")
                ? "Collection was successfully updated."
                : nil)
        {
            let parsed = (try? AO3Client.parseCollectionForm(body, slug: form.collectionSlug)) ?? form
            return .saved(message: notice, form: parsed)
        }
        if (300...399).contains(status) {
            return .saved(message: form.isNew ? "Collection created." : "Collection updated.", form: form)
        }
        if (200...299).contains(status),
           let parsed = try? AO3Client.parseCollectionForm(body, slug: form.collectionSlug),
           !parsed.generalErrors.isEmpty || !parsed.fieldErrors.isEmpty {
            return .invalid(parsed)
        }
        throw AO3CollectionWriteError.unconfirmed
    }

    private func throwIfCollectionWriteFailed(status: Int, body: String, fallback: String) throws {
        if let error = AO3Client.writeErrorMessage(in: body) {
            throw AO3CollectionWriteError.rejected(error)
        }
        guard (200...399).contains(status) else {
            throw AO3CollectionWriteError.rejected(fallback)
        }
    }
}
