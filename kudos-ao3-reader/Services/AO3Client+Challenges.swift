import Foundation
import SwiftSoup

/// Challenge reads: settings, paged sign-ups (join assignments client-side),
/// own sign-up, assignments/defaults/pinch hits, prompt-meme prompts, tag sets.
/// Matching and tag-set association are Open-on-AO3 URLs, not writes.
extension AO3Client {

    func challengeSettings(slug: String, request: URLRequest) async throws -> AO3ChallengeSettingsForm {
        let giftURL = AO3ChallengeURL.giftExchangeEdit(slug: slug)
        var giftRequest = request
        giftRequest.url = giftURL
        do {
            let html = try await authenticatedPageHTML(for: giftRequest)
            if let form = try? Self.parseChallengeSettingsForm(html, slug: slug, kind: .giftExchange) {
                return form
            }
        } catch AO3Error.notFound {
            // Fall through to prompt meme.
        }
        var memeRequest = request
        memeRequest.url = AO3ChallengeURL.promptMemeEdit(slug: slug)
        let html = try await authenticatedPageHTML(for: memeRequest)
        return try Self.parseChallengeSettingsForm(html, slug: slug, kind: .promptMeme)
    }

    func challengeSignUps(
        slug: String, page: Int = 1, request: URLRequest
    ) async throws -> AO3ChallengeSignUpPage {
        var request = request
        request.url = AO3ChallengeURL.signUps(slug: slug, page: page)
        return try Self.parseChallengeSignUpsPage(
            await authenticatedPageHTML(for: request), slug: slug, page: page
        )
    }

    /// Maintainer-only join: complete, open, and defaulted assignments each
    /// paginate independently. Fetch sequentially and stop on cancellation.
    func challengeSignUpsJoinedToAssignments(
        slug: String, page: Int = 1, request: URLRequest
    ) async throws -> AO3ChallengeSignUpPage {
        let signUps = try await AO3RequestCoordinator.shared.withSlot {
            try await challengeSignUps(slug: slug, page: page, request: request)
        }
        let assignments = try await Self.allChallengeAssignments { list, assignmentPage in
            try await AO3RequestCoordinator.shared.withSlot {
                try await self.challengeAssignments(
                    slug: slug, list: list, page: assignmentPage, request: request
                )
            }
        }
        return AO3ChallengeSignUpPage(
            signUps: AO3ChallengeSignUpMatching.joining(signUps.signUps, assignments: assignments),
            currentPage: signUps.currentPage, totalPages: signUps.totalPages
        )
    }

    static func allChallengeAssignments(
        fetchPage: (AO3ChallengeAssignmentList, Int) async throws -> AO3ChallengeAssignmentPage
    ) async throws -> [AO3ChallengeAssignment] {
        var assignments: [AO3ChallengeAssignment] = []
        // Open includes covered pinch hits; no fourth crawl is needed.
        for list in [AO3ChallengeAssignmentList.assignments, .unfulfilled, .defaults] {
            var page = 1
            while true {
                try Task.checkCancellation()
                let result = try await fetchPage(list, page)
                assignments.append(contentsOf: result.assignments)
                guard page < result.totalPages else { break }
                page += 1
            }
        }
        return assignments
    }

    func ownChallengeSignUp(slug: String, request: URLRequest) async throws -> AO3ChallengeSignUpForm {
        var request = request
        request.url = AO3ChallengeURL.newSignUp(slug: slug)
        let html = try await authenticatedPageHTML(for: request)
        return try Self.parseChallengeSignUpForm(html, slug: slug)
    }

    func challengeSignUpForm(
        slug: String, id: Int, request: URLRequest
    ) async throws -> AO3ChallengeSignUpForm {
        var request = request
        request.url = AO3ChallengeURL.editSignUp(slug: slug, id: id)
        return try Self.parseChallengeSignUpForm(await authenticatedPageHTML(for: request), slug: slug)
    }

    func challengeAssignments(
        slug: String,
        list: AO3ChallengeAssignmentList,
        page: Int = 1,
        request: URLRequest
    ) async throws -> AO3ChallengeAssignmentPage {
        var request = request
        request.url = AO3ChallengeURL.assignments(slug: slug, list: list, page: page)
        return try Self.parseChallengeAssignmentsPage(
            await authenticatedPageHTML(for: request), slug: slug, page: page, list: list
        )
    }

    func promptMemePrompts(
        slug: String, page: Int = 1, request: URLRequest? = nil
    ) async throws -> AO3PromptMemePage {
        let url = AO3ChallengeURL.requests(slug: slug, page: page)
        let html: String
        if var request {
            request.url = url
            html = try await authenticatedPageHTML(for: request)
        } else {
            html = try await getHTML(url)
        }
        return try Self.parsePromptMemePage(html, slug: slug, page: page)
    }

    func tagSet(id: Int, request: URLRequest? = nil) async throws -> AO3TagSet {
        let url = AO3ChallengeURL.tagSet(id)
        let html: String
        if var request {
            request.url = url
            html = try await authenticatedPageHTML(for: request)
        } else {
            html = try await getHTML(url)
        }
        return try Self.parseTagSet(html, id: id)
    }

    func tagSetEditForm(id: Int, request: URLRequest) async throws -> AO3TagSet {
        var request = request
        request.url = AO3ChallengeURL.tagSetEdit(id)
        return try Self.parseTagSet(await authenticatedPageHTML(for: request), id: id)
    }

    func tagSetNominations(id: Int, request: URLRequest) async throws -> [AO3TagNomination] {
        var request = request
        request.url = AO3ChallengeURL.tagSetNominations(id)
        return try Self.parseTagSetNominations(await authenticatedPageHTML(for: request))
    }

    // MARK: - Settings parser

    static func parseChallengeSettingsForm(
        _ html: String, slug: String, kind: AO3ChallengeKind
    ) throws -> AO3ChallengeSettingsForm {
        let doc = try SwiftSoup.parse(html)
        let prefix = kind == .giftExchange ? "gift_exchange" : "prompt_meme"
        guard let form = try doc.select("form[action*='\(kind == .giftExchange ? "gift_exchange" : "prompt_meme")']").first()
                ?? doc.select("#main form").first()
        else { throw AO3Error.parse }

        let actionRaw = (try? form.attr("action")) ?? ""
        guard let actionURL = AO3URLResolver.resolve(actionRaw.isEmpty
            ? (kind == .giftExchange
                ? AO3ChallengeURL.giftExchange(slug: slug).path
                : AO3ChallengeURL.promptMeme(slug: slug).path)
            : actionRaw)
        else { throw AO3Error.parse }

        let csrf = parseCSRFToken(from: html)
            ?? ((try? form.select("input[name=authenticity_token]").first()?.attr("value")) ?? "")
        guard !csrf.isEmpty else { throw AO3Error.parse }
        let method = try? form.select("input[name=_method]").first()?.attr("value")
        let zone = selectedValue(form, name: "\(prefix)[time_zone]").nilIfBlank ?? "UTC"

        func instant(_ key: String) -> AO3ChallengeInstant {
            AO3ChallengeInstant.parse(
                inputValue(form, "\(prefix)[\(key)_string]").nilIfBlank
                    ?? inputValue(form, "\(prefix)[\(key)]"),
                timeZoneName: zone
            )
        }

        var settings = AO3ChallengeSettings(
            collectionSlug: slug,
            kind: kind,
            signupOpen: isChecked(form, name: "\(prefix)[signup_open]"),
            timeZoneName: zone,
            signupsOpenAt: instant("signups_open_at"),
            signupsCloseAt: instant("signups_close_at"),
            assignmentsDueAt: instant("assignments_due_at"),
            worksRevealAt: instant("works_reveal_at"),
            authorsRevealAt: instant("authors_reveal_at"),
            limits: AO3ChallengeSignUpLimits(
                requestsRequired: intValue(form, "\(prefix)[requests_num_required]") ?? 1,
                requestsAllowed: intValue(form, "\(prefix)[requests_num_allowed]") ?? 1,
                offersRequired: intValue(form, "\(prefix)[offers_num_required]") ?? 1,
                offersAllowed: intValue(form, "\(prefix)[offers_num_allowed]") ?? 1
            ),
            requestsSummaryVisible: isChecked(form, name: "\(prefix)[requests_summary_visible]"),
            isAnonymous: isChecked(form, name: "\(prefix)[anonymous]"),
            signupInstructionsGeneral: textAreaValue(form, "\(prefix)[signup_instructions_general]"),
            signupInstructionsRequests: textAreaValue(form, "\(prefix)[signup_instructions_requests]"),
            signupInstructionsOffers: textAreaValue(form, "\(prefix)[signup_instructions_offers]"),
            requestURLLabel: inputValue(form, "\(prefix)[request_url_label]"),
            offerURLLabel: inputValue(form, "\(prefix)[offer_url_label]"),
            requestDescriptionLabel: inputValue(form, "\(prefix)[request_description_label]"),
            offerDescriptionLabel: inputValue(form, "\(prefix)[offer_description_label]"),
            requestRestriction: parsePromptRestriction(form, prefix: "\(prefix)[request_restriction_attributes]"),
            offerRestriction: parsePromptRestriction(form, prefix: "\(prefix)[offer_restriction_attributes]")
        )
        if let sent = AO3ChallengeUTCDate.parse(inputValue(form, "\(prefix)[assignments_sent_at]")) {
            settings.assignmentsSentAt = sent
        }
        let (fieldErrors, general) = parseChallengeFormErrors(in: doc)
        var hidden: [(String, String)] = []
        for input in try form.select("input[type=hidden]").array() {
            let name = (try? input.attr("name")) ?? ""
            let value = (try? input.attr("value")) ?? ""
            guard !name.isEmpty, name != "authenticity_token" else { continue }
            hidden.append((name, value))
        }
        return AO3ChallengeSettingsForm(
            actionURL: actionURL,
            httpMethodOverride: method?.nilIfBlank,
            csrfToken: csrf,
            kind: kind,
            collectionSlug: slug,
            settings: settings,
            fieldErrors: fieldErrors,
            generalErrors: general,
            hiddenFields: hidden
        )
    }

    static func challengeSettingsParameters(_ form: AO3ChallengeSettingsForm) -> [(String, String)] {
        let prefix = form.kind == .giftExchange ? "gift_exchange" : "prompt_meme"
        let settings = form.settings
        var params: [(String, String)] = [("authenticity_token", form.csrfToken)]
        if let method = form.httpMethodOverride, !method.isEmpty {
            params.append(("_method", method))
        }
        params.append(contentsOf: [
            ("\(prefix)[signup_open]", settings.signupOpen ? "1" : "0"),
            ("\(prefix)[time_zone]", "UTC"),
            ("\(prefix)[signups_open_at_string]", settings.signupsOpenAt.postedString),
            ("\(prefix)[signups_close_at_string]", settings.signupsCloseAt.postedString),
            ("\(prefix)[assignments_due_at_string]", settings.assignmentsDueAt.postedString),
            ("\(prefix)[works_reveal_at_string]", settings.worksRevealAt.postedString),
            ("\(prefix)[authors_reveal_at_string]", settings.authorsRevealAt.postedString),
            ("\(prefix)[requests_num_required]", String(settings.limits.requestsRequired)),
            ("\(prefix)[requests_num_allowed]", String(settings.limits.requestsAllowed)),
            ("\(prefix)[signup_instructions_general]", settings.signupInstructionsGeneral),
            ("\(prefix)[signup_instructions_requests]", settings.signupInstructionsRequests),
            ("\(prefix)[request_url_label]", settings.requestURLLabel),
            ("\(prefix)[request_description_label]", settings.requestDescriptionLabel)
        ])
        if form.kind == .giftExchange {
            params.append(contentsOf: [
                ("\(prefix)[offers_num_required]", String(settings.limits.offersRequired)),
                ("\(prefix)[offers_num_allowed]", String(settings.limits.offersAllowed)),
                ("\(prefix)[signup_instructions_offers]", settings.signupInstructionsOffers),
                ("\(prefix)[offer_url_label]", settings.offerURLLabel),
                ("\(prefix)[offer_description_label]", settings.offerDescriptionLabel),
                ("\(prefix)[requests_summary_visible]", settings.requestsSummaryVisible ? "1" : "0")
            ])
        } else {
            params.append(("\(prefix)[anonymous]", settings.isAnonymous ? "1" : "0"))
        }
        params.append(contentsOf: promptRestrictionParameters(
            settings.requestRestriction, prefix: "\(prefix)[request_restriction_attributes]"
        ))
        if form.kind == .giftExchange {
            params.append(contentsOf: promptRestrictionParameters(
                settings.offerRestriction, prefix: "\(prefix)[offer_restriction_attributes]"
            ))
        }
        for hidden in form.hiddenFields where !params.contains(where: { $0.0 == hidden.name }) {
            params.append(hidden)
        }
        return params
    }

    // MARK: - Sign-ups

    static func parseChallengeSignUpsPage(
        _ html: String, slug: String, page: Int
    ) throws -> AO3ChallengeSignUpPage {
        let doc = try SwiftSoup.parse(html)
        var signUps: [AO3ChallengeSignUp] = []
        let links = try doc.select("a[href*='/signups/']").array()
        var seen = Set<Int>()
        for link in links {
            let href = (try? link.attr("href")) ?? ""
            guard let id = resourceID(href, after: "signups"), !seen.contains(id) else { continue }
            seen.insert(id)
            let pseud = ((try? link.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let identity = try? AO3AuthorIdentity(displayName: pseud, href: href)
            let parent = link.parent()
            let summary = ((try? parent?.text()) ?? "")
            signUps.append(AO3ChallengeSignUp(
                id: id,
                collectionSlug: slug,
                pseud: pseud,
                userURL: identity?.userURL,
                requests: summary.isEmpty ? [] : [
                    AO3ChallengePrompt(id: 0, kind: .request, promptText: summary, fandoms: [])
                ]
            ))
        }
        for li in try doc.select("li.challenge.signup, li.signup.blurb, dd.signup").array() {
            guard let parsed = try? parseSignUpBlurb(li, slug: slug) else { continue }
            if let index = signUps.firstIndex(where: { $0.id == parsed.id }) {
                signUps[index] = parsed
            } else {
                signUps.append(parsed)
            }
        }
        if signUps.isEmpty {
            let heading = ((try? doc.select("h2.heading").first()?.text()) ?? "").lowercased()
            let recognized = heading.contains("sign") || heading.contains("challenge")
                || (try? doc.select("p.note, p.message").first()) != nil
            guard recognized else { throw AO3Error.parse }
        }
        return AO3ChallengeSignUpPage(
            signUps: signUps,
            currentPage: page,
            totalPages: try paginationTotal(in: doc, currentPage: page)
        )
    }

    static func parseChallengeSignUpForm(_ html: String, slug: String) throws -> AO3ChallengeSignUpForm {
        let doc = try SwiftSoup.parse(html)
        guard let form = try doc.select("form[action*='/signups']").first()
                ?? doc.select("#main form").first()
        else { throw AO3Error.parse }
        let actionRaw = (try? form.attr("action")) ?? ""
        guard let actionURL = AO3URLResolver.resolve(actionRaw.isEmpty ? "/collections/\(slug)/signups" : actionRaw)
        else { throw AO3Error.parse }
        let csrf = parseCSRFToken(from: html)
            ?? ((try? form.select("input[name=authenticity_token]").first()?.attr("value")) ?? "")
        guard !csrf.isEmpty else { throw AO3Error.parse }
        let method = try? form.select("input[name=_method]").first()?.attr("value")
        let signUpID = resourceID(actionRaw, after: "signups")
        let pseudID = inputValue(form, "challenge_signup[pseud_id]").nilIfBlank
            ?? selectedValue(form, name: "challenge_signup[pseud_id]")
        let requests = parseNestedPrompts(form, kind: .request)
        let offers = parseNestedPrompts(form, kind: .offer)
        let (fieldErrors, general) = parseChallengeFormErrors(in: doc)
        var hidden: [(String, String)] = []
        for input in try form.select("input[type=hidden]").array() {
            let name = (try? input.attr("name")) ?? ""
            let value = (try? input.attr("value")) ?? ""
            guard !name.isEmpty, name != "authenticity_token" else { continue }
            hidden.append((name, value))
        }
        return AO3ChallengeSignUpForm(
            actionURL: actionURL,
            httpMethodOverride: method?.nilIfBlank,
            csrfToken: csrf,
            collectionSlug: slug,
            signUpID: signUpID,
            pseudID: pseudID,
            requests: requests,
            offers: offers,
            fieldErrors: fieldErrors,
            generalErrors: general,
            hiddenFields: hidden
        )
    }

    static func challengeSignUpParameters(_ form: AO3ChallengeSignUpForm) -> [(String, String)] {
        var params: [(String, String)] = [("authenticity_token", form.csrfToken)]
        if let method = form.httpMethodOverride, !method.isEmpty {
            params.append(("_method", method))
        }
        if !form.pseudID.isEmpty {
            params.append(("challenge_signup[pseud_id]", form.pseudID))
        }
        params.append(contentsOf: nestedPromptParameters(form.requests, key: "requests"))
        params.append(contentsOf: nestedPromptParameters(form.offers, key: "offers"))
        return params
    }

    // MARK: - Assignments

    static func parseChallengeAssignmentsPage(
        _ html: String, slug: String, page: Int, list: AO3ChallengeAssignmentList? = nil
    ) throws -> AO3ChallengeAssignmentPage {
        let document = try SwiftSoup.parse(html)
        var assignments: [AO3ChallengeAssignment] = []
        for heading in try document.select("dl.index > dt").array() {
            guard let details = try heading.nextElementSibling(), details.tagName() == "dd" else {
                throw AO3Error.parse
            }
            assignments.append(try parseAssignmentRow(heading, details: details, slug: slug, list: list))
        }
        if assignments.isEmpty {
            let heading = try document.select("h2.heading").text()
            let emptyMessage = try document.select("p.note").text()
            guard heading.localizedCaseInsensitiveContains("assignments"),
                  emptyMessage.localizedCaseInsensitiveContains("No assignments") else { throw AO3Error.parse }
        }
        return AO3ChallengeAssignmentPage(
            assignments: assignments, currentPage: page,
            totalPages: try paginationTotal(in: document, currentPage: page)
        )
    }

    // MARK: - Prompt meme

    static func parsePromptMemePage(
        _ html: String, slug: String, page: Int
    ) throws -> AO3PromptMemePage {
        let doc = try SwiftSoup.parse(html)
        var prompts: [AO3PromptMemePrompt] = []
        for li in try doc.select("li.prompt.blurb, li.request.blurb, li.prompt").array() {
            guard let parsed = try? parsePromptMemeCard(li, slug: slug) else { continue }
            prompts.append(parsed)
        }
        if prompts.isEmpty {
            for link in try doc.select("a[href*='/prompts/']").array() {
                let href = (try? link.attr("href")) ?? ""
                guard let id = resourceID(href, after: "prompts") else { continue }
                let text = ((try? link.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                prompts.append(AO3PromptMemePrompt(
                    id: id, collectionSlug: slug, promptText: text
                ))
            }
        }
        if prompts.isEmpty {
            let heading = ((try? doc.select("h2.heading").first()?.text()) ?? "").lowercased()
            let recognized = heading.contains("prompt") || heading.contains("request")
                || heading.contains("meme") || (try? doc.select("p.note, p.message").first()) != nil
            guard recognized else { throw AO3Error.parse }
        }
        return AO3PromptMemePage(
            prompts: prompts,
            currentPage: page,
            totalPages: try paginationTotal(in: doc, currentPage: page)
        )
    }

    // MARK: - Tag sets

    static func parseTagSet(_ html: String, id: Int) throws -> AO3TagSet {
        let doc = try SwiftSoup.parse(html)
        let title = ((try? doc.select("h2.heading, h2").first()?.text()) ?? "")
            .replacingOccurrences(of: " | Archive of Our Own", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty || (try? doc.select("form[action*='/tag_sets']").first()) != nil else {
            throw AO3Error.parse
        }
        let form = try doc.select("form[action*='/tag_sets']").first()
        let description = ((try? doc.select("blockquote.userstuff, .tagset .userstuff").first()?.text()) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        func count(_ type: String) -> Int {
            let heading = (try? doc.select("h3.heading, h4.heading").array().first(where: {
                ((try? $0.text()) ?? "").localizedCaseInsensitiveContains(type)
            })?.text()) ?? ""
            return Int(heading.filter(\.isNumber)) ?? (try? doc.select("ul.\(type) li, div.\(type) li").array().count) ?? 0
        }
        let csrf = parseCSRFToken(from: html)
            ?? ((try? form?.select("input[name=authenticity_token]").first()?.attr("value")) ?? "")
        let action = (try? form?.attr("action")).flatMap { AO3URLResolver.resolve($0) }
        let method = try? form?.select("input[name=_method]").first()?.attr("value")
        let nominations = (try? parseTagSetNominations(html)) ?? []
        return AO3TagSet(
            id: id,
            title: title.isEmpty ? "Tag Set \(id)" : title,
            description: description,
            isVisible: form.map { isChecked($0, name: "owned_tag_set[visible]") } ?? true,
            isNominated: form.map { isChecked($0, name: "owned_tag_set[nominated]") } ?? false,
            fandomCount: count("fandom"),
            characterCount: count("character"),
            relationshipCount: count("relationship"),
            freeformCount: count("freeform") + count("additional"),
            fandomNominationLimit: intValue(form, "owned_tag_set[fandom_nomination_limit]") ?? 0,
            characterNominationLimit: intValue(form, "owned_tag_set[character_nomination_limit]") ?? 0,
            relationshipNominationLimit: intValue(form, "owned_tag_set[relationship_nomination_limit]") ?? 0,
            freeformNominationLimit: intValue(form, "owned_tag_set[freeform_nomination_limit]") ?? 0,
            fandomTagnames: textOrInput(form, "owned_tag_set[tag_set_attributes][fandom_tagnames_to_add]"),
            characterTagnames: textOrInput(form, "owned_tag_set[tag_set_attributes][character_tagnames_to_add]"),
            relationshipTagnames: textOrInput(form, "owned_tag_set[tag_set_attributes][relationship_tagnames_to_add]"),
            freeformTagnames: textOrInput(form, "owned_tag_set[tag_set_attributes][freeform_tagnames_to_add]"),
            reviewQueue: nominations,
            csrfToken: csrf,
            actionURL: action,
            httpMethodOverride: method?.nilIfBlank
        )
    }

    static func parseTagSetNominations(_ html: String) throws -> [AO3TagNomination] {
        let doc = try SwiftSoup.parse(html)
        var result: [AO3TagNomination] = []
        var index = 0
        for row in try doc.select("li.nomination, tr.nomination, div.nomination").array() {
            let name = ((try? row.select(".tag, td.tag, a.tag").first()?.text())
                ?? (try? row.text()))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { continue }
            let text = ((try? row.text()) ?? "").lowercased()
            let field: AO3TagSetField
            if text.contains("character") { field = .character }
            else if text.contains("relationship") { field = .relationship }
            else if text.contains("freeform") || text.contains("additional") { field = .freeform }
            else { field = .fandom }
            let state: AO3TagNominationState
            if text.contains("reject") { state = .rejected }
            else if text.contains("approv") { state = .approved }
            else { state = .unreviewed }
            index += 1
            result.append(AO3TagNomination(id: index, tagName: name, field: field, state: state))
        }
        for key in (try? doc.select("input[type=checkbox], input[type=radio]").array().compactMap { try? $0.attr("name") }) ?? [] {
            guard let parsed = nominationFromParam(key) else { continue }
            if !result.contains(where: { $0.tagName == parsed.tagName && $0.field == parsed.field }) {
                result.append(parsed)
            }
        }
        return result
    }

    static func tagSetSaveParameters(_ tagSet: AO3TagSet, save: AO3TagSetSave, csrf: String) -> [(String, String)] {
        var params: [(String, String)] = [("authenticity_token", csrf)]
        if let method = tagSet.httpMethodOverride, !method.isEmpty {
            params.append(("_method", method))
        }
        params.append(contentsOf: [
            (AO3TagSetField.fandom.tagnamesToAddParam, save.fandomTagnames),
            (AO3TagSetField.character.tagnamesToAddParam, save.characterTagnames),
            (AO3TagSetField.relationship.tagnamesToAddParam, save.relationshipTagnames),
            (AO3TagSetField.freeform.tagnamesToAddParam, save.freeformTagnames)
        ])
        return params
    }

    static func rejectedTagParam(field: AO3TagSetField, tagName: String) -> (String, String) {
        let encoded = tagName.replacingOccurrences(of: "[", with: "#LBRACKET")
            .replacingOccurrences(of: "]", with: "#RBRACKET")
        return ("\(field.rawValue)_reject_\(encoded)", "1")
    }

    // MARK: - Internals

    private static func parsePromptRestriction(
        _ form: Element, prefix: String
    ) -> AO3PromptRestrictionSnapshot {
        AO3PromptRestrictionSnapshot(
            id: inputValue(form, "\(prefix)[id]"),
            optionalTagsAllowed: isChecked(form, name: "\(prefix)[optional_tags_allowed]"),
            titleRequired: isChecked(form, name: "\(prefix)[title_required]"),
            titleAllowed: isChecked(form, name: "\(prefix)[title_allowed]"),
            descriptionRequired: isChecked(form, name: "\(prefix)[description_required]"),
            descriptionAllowed: isChecked(form, name: "\(prefix)[description_allowed]"),
            urlRequired: isChecked(form, name: "\(prefix)[url_required]"),
            urlAllowed: isChecked(form, name: "\(prefix)[url_allowed]"),
            fandomRequired: intValue(form, "\(prefix)[fandom_num_required]") ?? 0,
            fandomAllowed: intValue(form, "\(prefix)[fandom_num_allowed]") ?? 0,
            allowAnyFandom: isChecked(form, name: "\(prefix)[allow_any_fandom]"),
            requireUniqueFandom: isChecked(form, name: "\(prefix)[require_unique_fandom]"),
            characterRequired: intValue(form, "\(prefix)[character_num_required]") ?? 0,
            characterAllowed: intValue(form, "\(prefix)[character_num_allowed]") ?? 0,
            allowAnyCharacter: isChecked(form, name: "\(prefix)[allow_any_character]"),
            requireUniqueCharacter: isChecked(form, name: "\(prefix)[require_unique_character]"),
            relationshipRequired: intValue(form, "\(prefix)[relationship_num_required]") ?? 0,
            relationshipAllowed: intValue(form, "\(prefix)[relationship_num_allowed]") ?? 0,
            allowAnyRelationship: isChecked(form, name: "\(prefix)[allow_any_relationship]"),
            requireUniqueRelationship: isChecked(form, name: "\(prefix)[require_unique_relationship]"),
            freeformRequired: intValue(form, "\(prefix)[freeform_num_required]") ?? 0,
            freeformAllowed: intValue(form, "\(prefix)[freeform_num_allowed]") ?? 0,
            allowAnyFreeform: isChecked(form, name: "\(prefix)[allow_any_freeform]"),
            requireUniqueFreeform: isChecked(form, name: "\(prefix)[require_unique_freeform]"),
            tagSetsToAdd: inputValue(form, "\(prefix)[tag_sets_to_add]")
        )
    }

    private static func promptRestrictionParameters(
        _ snapshot: AO3PromptRestrictionSnapshot, prefix: String
    ) -> [(String, String)] {
        var params: [(String, String)] = [
            ("\(prefix)[optional_tags_allowed]", snapshot.optionalTagsAllowed ? "1" : "0"),
            ("\(prefix)[title_required]", snapshot.titleRequired ? "1" : "0"),
            ("\(prefix)[title_allowed]", snapshot.titleAllowed ? "1" : "0"),
            ("\(prefix)[description_required]", snapshot.descriptionRequired ? "1" : "0"),
            ("\(prefix)[description_allowed]", snapshot.descriptionAllowed ? "1" : "0"),
            ("\(prefix)[url_required]", snapshot.urlRequired ? "1" : "0"),
            ("\(prefix)[url_allowed]", snapshot.urlAllowed ? "1" : "0"),
            ("\(prefix)[fandom_num_required]", String(snapshot.fandomRequired)),
            ("\(prefix)[fandom_num_allowed]", String(snapshot.fandomAllowed)),
            ("\(prefix)[allow_any_fandom]", snapshot.allowAnyFandom ? "1" : "0"),
            ("\(prefix)[require_unique_fandom]", snapshot.requireUniqueFandom ? "1" : "0"),
            ("\(prefix)[character_num_required]", String(snapshot.characterRequired)),
            ("\(prefix)[character_num_allowed]", String(snapshot.characterAllowed)),
            ("\(prefix)[allow_any_character]", snapshot.allowAnyCharacter ? "1" : "0"),
            ("\(prefix)[require_unique_character]", snapshot.requireUniqueCharacter ? "1" : "0"),
            ("\(prefix)[relationship_num_required]", String(snapshot.relationshipRequired)),
            ("\(prefix)[relationship_num_allowed]", String(snapshot.relationshipAllowed)),
            ("\(prefix)[allow_any_relationship]", snapshot.allowAnyRelationship ? "1" : "0"),
            ("\(prefix)[require_unique_relationship]", snapshot.requireUniqueRelationship ? "1" : "0"),
            ("\(prefix)[freeform_num_required]", String(snapshot.freeformRequired)),
            ("\(prefix)[freeform_num_allowed]", String(snapshot.freeformAllowed)),
            ("\(prefix)[allow_any_freeform]", snapshot.allowAnyFreeform ? "1" : "0"),
            ("\(prefix)[require_unique_freeform]", snapshot.requireUniqueFreeform ? "1" : "0"),
            ("\(prefix)[tag_sets_to_add]", snapshot.tagSetsToAdd)
        ]
        if !snapshot.id.isEmpty {
            params.insert(("\(prefix)[id]", snapshot.id), at: 0)
        }
        return params
    }

    private static func parseNestedPrompts(
        _ form: Element, kind: AO3ChallengePromptKind
    ) -> [AO3ChallengePrompt] {
        let key = kind == .request ? "requests" : "offers"
        let prefix = "challenge_signup[\(key)_attributes]"
        var indices = Set<Int>()
        let named = (try? form.select("input, textarea, select").array()) ?? []
        let names = named.compactMap { try? $0.attr("name") }
        for name in names where name.hasPrefix(prefix) {
            if let index = nestedIndex(name, after: prefix) { indices.insert(index) }
        }
        return indices.sorted().map { index in
            let p = "\(prefix)[\(index)]"
            let id = Int(inputValue(form, "\(p)[id]")) ?? index
            let fandoms = commaTags(inputValue(form, "\(p)[tag_set_attributes][fandom_tagnames]"))
            let characters = commaTags(inputValue(form, "\(p)[tag_set_attributes][character_tagnames]"))
            let relationships = commaTags(inputValue(form, "\(p)[tag_set_attributes][relationship_tagnames]"))
            let freeforms = commaTags(inputValue(form, "\(p)[tag_set_attributes][freeform_tagnames]"))
            return AO3ChallengePrompt(
                id: id,
                kind: kind,
                title: inputValue(form, "\(p)[title]"),
                promptText: textAreaValue(form, "\(p)[description]"),
                url: inputValue(form, "\(p)[url]"),
                isAnonymous: isChecked(form, name: "\(p)[anonymous]"),
                fandoms: fandoms,
                characters: characters,
                relationships: relationships,
                freeforms: freeforms,
                anyFandom: isChecked(form, name: "\(p)[any_fandom]"),
                anyCharacter: isChecked(form, name: "\(p)[any_character]"),
                anyRelationship: isChecked(form, name: "\(p)[any_relationship]"),
                anyFreeform: isChecked(form, name: "\(p)[any_freeform]"),
                destroy: isChecked(form, name: "\(p)[_destroy]")
            )
        }
    }

    private static func nestedPromptParameters(
        _ prompts: [AO3ChallengePrompt], key: String
    ) -> [(String, String)] {
        var params: [(String, String)] = []
        for (index, prompt) in prompts.enumerated() {
            let p = "challenge_signup[\(key)_attributes][\(index)]"
            if prompt.id != 0 { params.append(("\(p)[id]", String(prompt.id))) }
            params.append(contentsOf: [
                ("\(p)[title]", prompt.title),
                ("\(p)[description]", prompt.promptText),
                ("\(p)[url]", prompt.url),
                ("\(p)[anonymous]", prompt.isAnonymous ? "1" : "0"),
                ("\(p)[any_fandom]", prompt.anyFandom ? "1" : "0"),
                ("\(p)[any_character]", prompt.anyCharacter ? "1" : "0"),
                ("\(p)[any_relationship]", prompt.anyRelationship ? "1" : "0"),
                ("\(p)[any_freeform]", prompt.anyFreeform ? "1" : "0"),
                ("\(p)[_destroy]", prompt.destroy ? "1" : "0"),
                ("\(p)[tag_set_attributes][fandom_tagnames]", prompt.fandoms.joined(separator: ",")),
                ("\(p)[tag_set_attributes][character_tagnames]", prompt.characters.joined(separator: ",")),
                ("\(p)[tag_set_attributes][relationship_tagnames]", prompt.relationships.joined(separator: ",")),
                ("\(p)[tag_set_attributes][freeform_tagnames]", prompt.freeforms.joined(separator: ","))
            ])
        }
        return params
    }

    private static func parseSignUpBlurb(_ li: Element, slug: String) throws -> AO3ChallengeSignUp {
        let link = try li.select("a[href*='/signups/']").first()
        let href = (try? link?.attr("href")) ?? ""
        guard let id = resourceID(href, after: "signups") else { throw AO3Error.parse }
        let pseud = ((try? link?.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = (try? li.select("a.tag, .tags a").array().map { try $0.text() }) ?? []
        let anonymous = ((try? li.className()) ?? "").contains("anonymous")
            || ((try? li.text()) ?? "").localizedCaseInsensitiveContains("anonymous")
        let prompt = AO3ChallengePrompt(
            id: 0,
            kind: .request,
            promptText: ((try? li.select("blockquote, .userstuff").first()?.text()) ?? ""),
            isAnonymous: anonymous,
            fandoms: tags
        )
        return AO3ChallengeSignUp(
            id: id,
            collectionSlug: slug,
            pseud: anonymous ? "" : pseud,
            requests: [prompt]
        )
    }

    /// Mirrors otwarchive's assignment_blurb and maintainer_index_* dt/dd pairs.
    /// Giver bylines are plain dt text; mailto links and the recipient are children.
    private static func parseAssignmentRow(
        _ heading: Element, details: Element, slug: String, list: AO3ChallengeAssignmentList?
    ) throws -> AO3ChallengeAssignment {
        let assignmentLink = try details.select("a[href*='/assignments/']").first()
        let assignmentID = try assignmentLink.flatMap { resourceID(try $0.attr("href"), after: "assignments") }
        let controls = try details.select("input[name]").array()
        let controlID = try controls.compactMap { input -> Int? in
            let name = try input.attr("name")
            for prefix in ["default_", "undefault_", "approve_", "cover_"] where name.hasPrefix(prefix) {
                return Int(name.dropFirst(prefix.count))
            }
            return nil
        }.first
        guard let identifier = assignmentID ?? controlID else { throw AO3Error.parse }
        let signupLink = try heading.select("a[href*='/signups/']").first()
            ?? details.select("a[href*='/signups/']").first()
        let requestID = try signupLink.flatMap { resourceID(try $0.attr("href"), after: "signups") }
        let isDefaulted = try details.select("input[name^=undefault_]").first() != nil
        let recipient = try (signupLink ?? assignmentLink)?.text() ?? ""
        var giver = try heading.ownText().trimmingCharacters(in: .whitespacesAndNewlines)
        if isDefaulted {
            giver = try details.select("label[for^=undefault_]").first()?.ownText() ?? ""
            if giver.hasPrefix("Undefault ") { giver.removeFirst("Undefault ".count) }
        }
        let isPinchHitter = giver.hasSuffix("* (pinch hitter)")
        if isPinchHitter { giver.removeLast("* (pinch hitter)".count) }
        giver = giver.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = try details.select("dl.stats > dd").first()?.text().lowercased() ?? ""
        return AO3ChallengeAssignment(
            id: identifier, collectionSlug: slug, requestSignupID: requestID,
            requestPseud: recipient, offerPseud: giver,
            pinchHitterPseud: isPinchHitter ? giver : "",
            isDefaulted: isDefaulted,
            isFulfilled: list == .assignments || status == "complete" || status == "fulfilled",
            isCovered: isPinchHitter
        )
    }

    private static func parsePromptMemeCard(_ li: Element, slug: String) throws -> AO3PromptMemePrompt {
        let idAttr = li.id()
        var id = 0
        if idAttr.hasPrefix("prompt_") {
            id = Int(idAttr.replacingOccurrences(of: "prompt_", with: "")) ?? 0
        }
        if id == 0 {
            let href = (try? li.select("a[href*='/prompts/']").first()?.attr("href")) ?? ""
            id = resourceID(href, after: "prompts") ?? 0
        }
        guard id != 0 else { throw AO3Error.parse }
        let classes = ((try? li.className()) ?? "").lowercased()
        let body = ((try? li.select("blockquote.userstuff, .userstuff, p").first()?.text()) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = ((try? li.select("h4.heading, h5.heading").first()?.text()) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = (try? li.select("a.tag").array().map { try $0.text() }) ?? []
        let isAnonymous = classes.contains("anonymous")
            || title.localizedCaseInsensitiveContains("anonymous")
            || body.localizedCaseInsensitiveContains("(anonymous)")
        let ownerLink = try li.select("h4.heading a[href*='/users/'], .byline a[href*='/users/']").first()
        let owner = isAnonymous ? nil : (try? ownerLink?.text())
        let claimHref = (try? li.select("a[href*='/claims/'], form[action*='/claims']").first()?.attr("href"))
            ?? (try? li.select("form[action*='/claims']").first()?.attr("action"))
            ?? ""
        let claimID = resourceID(claimHref, after: "claims")
        let claimedByMe = ((try? li.text()) ?? "").localizedCaseInsensitiveContains("your claim")
            || ((try? li.select(".actions").first()?.text()) ?? "").localizedCaseInsensitiveContains("drop")
        return AO3PromptMemePrompt(
            id: id,
            collectionSlug: slug,
            promptText: body,
            title: title,
            tagSummary: tags.joined(separator: ", "),
            isAnonymous: isAnonymous,
            ownerPseud: owner,
            claimID: claimID,
            claimedByCurrentUser: claimedByMe
        )
    }

    private static func parseChallengeFormErrors(in doc: Document) -> ([String: String], [String]) {
        var field: [String: String] = [:]
        var general: [String] = []
        for item in (try? doc.select("#error ul li, .error ul li, #errorExplanation li").array()) ?? [] {
            let text = ((try? item.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { general.append(text) }
        }
        return (field, general)
    }

    private static func intValue(_ root: Element?, _ name: String) -> Int? {
        guard let root else { return nil }
        let raw = inputValue(root, name)
        return Int(raw.filter(\.isNumber))
    }

    private static func textOrInput(_ root: Element?, _ name: String) -> String {
        guard let root else { return "" }
        let area = textAreaValue(root, name)
        return area.isEmpty ? inputValue(root, name) : area
    }

    private static func commaTags(_ raw: String) -> [String] {
        raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func nestedIndex(_ name: String, after prefix: String) -> Int? {
        guard name.hasPrefix(prefix + "[") else { return nil }
        let rest = name.dropFirst(prefix.count + 1)
        guard let close = rest.firstIndex(of: "]") else { return nil }
        return Int(rest[rest.startIndex..<close])
    }

    private static func resourceID(_ href: String, after key: String) -> Int? {
        let parts = href.split(whereSeparator: { $0 == "/" || $0 == "?" }).map(String.init)
        guard let index = parts.firstIndex(of: key), index + 1 < parts.count else { return nil }
        return Int(parts[index + 1])
    }

    private static func nominationFromParam(_ name: String) -> AO3TagNomination? {
        // fandom_reject_Tag Name / character_approve_X / relationship_synonym_Y
        let parts = name.split(separator: "_", maxSplits: 2).map(String.init)
        guard parts.count >= 3,
              let field = AO3TagSetField(rawValue: parts[0]),
              ["approve", "reject", "synonym", "change"].contains(parts[1])
        else { return nil }
        let tag = parts[2].replacingOccurrences(of: "#LBRACKET", with: "[")
            .replacingOccurrences(of: "#RBRACKET", with: "]")
        let state: AO3TagNominationState = parts[1] == "reject" ? .rejected
            : parts[1] == "approve" ? .approved : .unreviewed
        return AO3TagNomination(id: tag.hashValue, tagName: tag, field: field, state: state)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
