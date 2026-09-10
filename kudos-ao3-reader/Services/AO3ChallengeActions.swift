import Foundation

/// Native challenge writes. Matching (`potential_matches#generate`) and tag-set
/// association are **not** implemented — AO3 does not expose them to clients.
/// Use `AO3ChallengeSettings.matchingOpenOnAO3` and `AO3TagSet.associationOpenOnAO3`.
///
/// Unexercised against a live AO3 session — a release gate, not a reason these
/// endpoints are unbuilt. Every mutating method is one CSRF GET then a single
/// `submitWrite` POST (never retried, never coalesced).
enum AO3ChallengeWriteError: LocalizedError, Equatable {
    case notSignedIn
    case noCSRFToken
    case rejected(String)
    case unconfirmed
    case invalidForm

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Log in to AO3 first."
        case .noCSRFToken: "Couldn't prepare the request. Try again, or open the challenge on AO3."
        case let .rejected(reason): reason
        case .unconfirmed:
            "AO3 replied but didn't confirm the change went through. Check on AO3 before trying again."
        case .invalidForm:
            "That sign-up doesn't meet this challenge's limits, so nothing was posted."
        }
    }
}

extension AO3AuthService {

    /// Unexercised against a live AO3 session — a release gate, not a reason this
    /// endpoint is unbuilt. Single-shot `submitWrite`; never retried or coalesced.
    func saveChallengeSignUp(_ form: AO3ChallengeSignUpForm) async throws -> AO3ChallengeSignUpForm {
        guard isLoggedIn else { throw AO3ChallengeWriteError.notSignedIn }
        let checked = form.validated()
        guard checked.isValid else { return checked }
        let referer = form.isNew
            ? AO3ChallengeURL.newSignUp(slug: form.collectionSlug)
            : AO3ChallengeURL.editSignUp(slug: form.collectionSlug, id: form.signUpID ?? 0)
        let (html, token) = try await fetchCSRFPage(at: referer)
        var posted = checked
        posted.csrfToken = token
        if posted.actionURL.absoluteString.isEmpty {
            posted.actionURL = form.isNew
                ? AO3ChallengeURL.signUps(slug: form.collectionSlug)
                : AO3ChallengeURL.signUp(slug: form.collectionSlug, id: form.signUpID ?? 0)
        }
        let request = try writeRequest(
            to: posted.actionURL,
            body: Self.formEncoded(AO3Client.challengeSignUpParameters(posted)),
            csrf: token, referer: referer, ajax: false
        )
        let (status, body) = try await AO3Client.shared.submitWrite(request)
        if let parsed = try? AO3Client.parseChallengeSignUpForm(body, slug: form.collectionSlug),
           !parsed.generalErrors.isEmpty || !parsed.fieldErrors.isEmpty {
            return parsed
        }
        if let error = AO3Client.writeErrorMessage(in: body) {
            var invalid = posted
            invalid.generalErrors = [error]
            return invalid
        }
        if AO3Client.writeSuccessMessage(in: body) != nil || (300...399).contains(status) {
            return (try? AO3Client.parseChallengeSignUpForm(body, slug: form.collectionSlug)) ?? posted
        }
        _ = html
        throw AO3ChallengeWriteError.unconfirmed
    }

    /// Withdraw while sign-ups are still open: `DELETE /collections/:slug/signups/:id`.
    /// Unexercised against a live AO3 session — a release gate, not a reason this
    /// endpoint is unbuilt.
    func withdrawSignUp(slug: String, signUpID: Int) async throws {
        guard isLoggedIn else { throw AO3ChallengeWriteError.notSignedIn }
        let referer = AO3ChallengeURL.confirmDeleteSignUp(slug: slug, id: signUpID)
        let (_, token) = try await fetchCSRFPage(at: referer)
        let request = try writeRequest(
            to: AO3ChallengeURL.signUp(slug: slug, id: signUpID),
            body: Self.formEncoded([("_method", "delete"), ("authenticity_token", token)]),
            csrf: token, referer: referer, ajax: false
        )
        let (status, body) = try await AO3Client.shared.submitWrite(request)
        try throwIfChallengeWriteFailed(
            status: status, body: body, fallback: "AO3 couldn't withdraw that sign-up."
        )
    }

    /// After sign-ups close AO3 will not destroy the sign-up (`check_signup_open`
    /// / `destroy` refuse it). Participants default on the assignment instead:
    /// `PATCH /collections/:slug/assignments/:id/default`.
    /// Unexercised against a live AO3 session — a release gate, not a reason this
    /// endpoint is unbuilt.
    func withdrawSignUpAfterClose(slug: String, assignmentID: Int) async throws {
        try await reportAssignmentDefault(slug: slug, assignmentID: assignmentID)
    }

    /// Unexercised against a live AO3 session — a release gate, not a reason this
    /// endpoint is unbuilt. Single-shot `submitWrite`; never retried or coalesced.
    func reportAssignmentDefault(slug: String, assignmentID: Int) async throws {
        guard isLoggedIn else { throw AO3ChallengeWriteError.notSignedIn }
        let referer = AO3ChallengeURL.assignments(slug: slug, list: .assignments, page: 1)
        let (_, token) = try await fetchCSRFPage(at: referer)
        let request = try writeRequest(
            to: AO3ChallengeURL.assignmentDefault(slug: slug, id: assignmentID),
            body: Self.formEncoded([("_method", "patch"), ("authenticity_token", token)]),
            csrf: token, referer: referer, ajax: false
        )
        let (status, body) = try await AO3Client.shared.submitWrite(request)
        try throwIfChallengeWriteFailed(
            status: status, body: body, fallback: "AO3 couldn't record the default."
        )
    }

    /// Unexercised against a live AO3 session — a release gate, not a reason this
    /// endpoint is unbuilt. Single-shot `submitWrite`; never retried or coalesced.
    func claimPinchHit(slug: String, assignmentID: Int, byline: String) async throws {
        guard isLoggedIn else { throw AO3ChallengeWriteError.notSignedIn }
        let pinch = byline.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pinch.isEmpty else {
            throw AO3ChallengeWriteError.rejected("Name a pinch hitter.")
        }
        let referer = AO3ChallengeURL.assignments(slug: slug, list: .pinchHits, page: 1)
        let (_, token) = try await fetchCSRFPage(at: referer)
        let params: [(String, String)] = [
            ("_method", "put"),
            ("authenticity_token", token),
            ("cover_\(assignmentID)", pinch)
        ]
        let request = try writeRequest(
            to: AO3ChallengeURL.assignmentUpdateMultiple(slug: slug),
            body: Self.formEncoded(params), csrf: token, referer: referer, ajax: false
        )
        let (status, body) = try await AO3Client.shared.submitWrite(request)
        try throwIfChallengeWriteFailed(
            status: status, body: body, fallback: "AO3 couldn't claim that pinch hit."
        )
    }

    /// Unexercised against a live AO3 session — a release gate, not a reason this
    /// endpoint is unbuilt. Single-shot `submitWrite`; never retried or coalesced.
    func claimPrompt(slug: String, promptID: Int) async throws {
        guard isLoggedIn else { throw AO3ChallengeWriteError.notSignedIn }
        let referer = AO3ChallengeURL.requests(slug: slug)
        let (_, token) = try await fetchCSRFPage(at: referer)
        let params: [(String, String)] = [
            ("authenticity_token", token),
            ("prompt_id", String(promptID))
        ]
        let request = try writeRequest(
            to: AO3ChallengeURL.claims(slug: slug),
            body: Self.formEncoded(params), csrf: token, referer: referer, ajax: false
        )
        let (status, body) = try await AO3Client.shared.submitWrite(request)
        try throwIfChallengeWriteFailed(
            status: status, body: body, fallback: "AO3 couldn't claim that prompt."
        )
    }

    /// Unexercised against a live AO3 session — a release gate, not a reason this
    /// endpoint is unbuilt. Single-shot `submitWrite`; never retried or coalesced.
    func releasePrompt(slug: String, claimID: Int) async throws {
        guard isLoggedIn else { throw AO3ChallengeWriteError.notSignedIn }
        let referer = AO3ChallengeURL.claims(slug: slug, forUser: true)
        let (_, token) = try await fetchCSRFPage(at: referer)
        let request = try writeRequest(
            to: AO3ChallengeURL.claim(slug: slug, id: claimID),
            body: Self.formEncoded([("_method", "delete"), ("authenticity_token", token)]),
            csrf: token, referer: referer, ajax: false
        )
        let (status, body) = try await AO3Client.shared.submitWrite(request)
        try throwIfChallengeWriteFailed(
            status: status, body: body, fallback: "AO3 couldn't release that prompt."
        )
    }

    /// Saves the four comma-separated tag-set fields together in one POST.
    /// Unexercised against a live AO3 session — a release gate, not a reason this
    /// endpoint is unbuilt.
    func saveTagSetFields(tagSet: AO3TagSet, fields: AO3TagSetSave) async throws {
        guard isLoggedIn else { throw AO3ChallengeWriteError.notSignedIn }
        let referer = AO3ChallengeURL.tagSetEdit(tagSet.id)
        let (_, token) = try await fetchCSRFPage(at: referer)
        guard let action = tagSet.actionURL else {
            throw AO3ChallengeWriteError.rejected("Couldn't find AO3's tag-set form.")
        }
        let request = try writeRequest(
            to: action,
            body: Self.formEncoded(AO3Client.tagSetSaveParameters(tagSet, save: fields, csrf: token)),
            csrf: token, referer: referer, ajax: false
        )
        let (status, body) = try await AO3Client.shared.submitWrite(request)
        try throwIfChallengeWriteFailed(
            status: status, body: body, fallback: "AO3 couldn't save that tag set."
        )
    }

    /// Reports a rejected nomination against the field it came from
    /// (`fandom_reject_TagName`, otwarchive `TagSetNominationsController#update_multiple`).
    /// Unexercised against a live AO3 session — a release gate, not a reason this
    /// endpoint is unbuilt.
    func reportRejectedTag(tagSetID: Int, field: AO3TagSetField, tagName: String) async throws {
        guard isLoggedIn else { throw AO3ChallengeWriteError.notSignedIn }
        let referer = AO3ChallengeURL.tagSetNominations(tagSetID)
        let (_, token) = try await fetchCSRFPage(at: referer)
        var params: [(String, String)] = [
            ("_method", "put"),
            ("authenticity_token", token)
        ]
        params.append(AO3Client.rejectedTagParam(field: field, tagName: tagName))
        let request = try writeRequest(
            to: referer,
            body: Self.formEncoded(params), csrf: token, referer: referer, ajax: false
        )
        let (status, body) = try await AO3Client.shared.submitWrite(request)
        try throwIfChallengeWriteFailed(
            status: status, body: body, fallback: "AO3 couldn't reject that tag."
        )
    }

    /// One challenge-update POST. Validates locally first so a failed AO3
    /// round-trip returns the submitted form with errors instead of discarding
    /// the caller's input. Matching is not a write — see `matchingOpenOnAO3`.
    /// Unexercised against a live AO3 session — a release gate, not a reason this
    /// endpoint is unbuilt.
    func updateChallengeSettings(
        _ form: AO3ChallengeSettingsForm
    ) async throws -> AO3ChallengeSettingsSaveOutcome {
        guard isLoggedIn else { throw AO3ChallengeWriteError.notSignedIn }
        let checked = form.validated()
        if !checked.isValid { return .invalid(checked) }
        let referer = form.kind == .giftExchange
            ? AO3ChallengeURL.giftExchangeEdit(slug: form.collectionSlug)
            : AO3ChallengeURL.promptMemeEdit(slug: form.collectionSlug)
        let (html, token) = try await fetchCSRFPage(at: referer)
        var posted = checked
        posted.csrfToken = token
        let request = try writeRequest(
            to: posted.actionURL,
            body: Self.formEncoded(AO3Client.challengeSettingsParameters(posted)),
            csrf: token, referer: referer, ajax: false
        )
        let (status, body) = try await AO3Client.shared.submitWrite(request)
        if let error = AO3Client.writeErrorMessage(in: body) {
            var invalid = (try? AO3Client.parseChallengeSettingsForm(
                body, slug: form.collectionSlug, kind: form.kind
            )) ?? posted
            invalid.generalErrors = [error] + invalid.generalErrors
            // Keep the caller's dates/limits if AO3 re-rendered blanks.
            invalid.settings.signupsOpenAt = posted.settings.signupsOpenAt
            invalid.settings.signupsCloseAt = posted.settings.signupsCloseAt
            invalid.settings.assignmentsDueAt = posted.settings.assignmentsDueAt
            invalid.settings.worksRevealAt = posted.settings.worksRevealAt
            invalid.settings.authorsRevealAt = posted.settings.authorsRevealAt
            invalid.settings.limits = posted.settings.limits
            return .invalid(invalid)
        }
        if let notice = AO3Client.writeSuccessMessage(in: body)
            ?? (body.localizedCaseInsensitiveContains("successfully")
                ? "Challenge was successfully updated." : nil)
        {
            let parsed = (try? AO3Client.parseChallengeSettingsForm(
                body, slug: form.collectionSlug, kind: form.kind
            )) ?? posted
            return .saved(message: notice, form: parsed)
        }
        if (300...399).contains(status) {
            return .saved(message: "Challenge updated.", form: posted)
        }
        if (200...299).contains(status),
           let parsed = try? AO3Client.parseChallengeSettingsForm(
            body, slug: form.collectionSlug, kind: form.kind
           ),
           !parsed.generalErrors.isEmpty || !parsed.fieldErrors.isEmpty {
            return .invalid(parsed)
        }
        _ = html
        throw AO3ChallengeWriteError.unconfirmed
    }

    private func throwIfChallengeWriteFailed(status: Int, body: String, fallback: String) throws {
        if let error = AO3Client.writeErrorMessage(in: body) {
            throw AO3ChallengeWriteError.rejected(error)
        }
        guard (200...399).contains(status) else {
            throw AO3ChallengeWriteError.rejected(fallback)
        }
    }
}
