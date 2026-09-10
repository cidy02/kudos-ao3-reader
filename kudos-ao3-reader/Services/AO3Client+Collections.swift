import Foundation
import SwiftSoup

/// Collection reads: show, independent works/bookmarks/people segments, manage
/// items, edit/new form, URL-name availability, moderation extras. Fetch through
/// `getHTML` / `authenticatedPageHTML`. Collection **works** reuse `worksPage` /
/// `parseSearchPage`; bookmarks reuse `parseBookmarksPage`. People and items do not.
extension AO3Client {

    // MARK: - Fetchers

    func collectionShow(slug: String, request: URLRequest? = nil) async throws -> AO3CollectionShow {
        guard let url = AO3CollectionURL.show(slug: slug) else { throw AO3Error.parse }
        return try Self.parseCollectionShow(await html(url, request: request), slug: slug)
    }

    /// Paged works in a collection. Reuses the standard work-blurb parse.
    func collectionWorks(
        slug: String, page: Int = 1, request: URLRequest? = nil
    ) async throws -> AO3SearchPage {
        guard let url = Self.collectionWorksURL(name: slug, page: page) else { throw AO3Error.parse }
        if var request {
            request.url = url
            return try await worksPage(for: request, page: page)
        }
        return try await worksPage(at: url, page: page)
    }

    func collectionBookmarks(
        slug: String, page: Int = 1, request: URLRequest? = nil
    ) async throws -> AO3SearchPage {
        guard let url = AO3CollectionURL.bookmarks(slug: slug, page: page) else { throw AO3Error.parse }
        let body = try await html(url, request: request)
        return try Self.parseBookmarksPage(body, page: page)
    }

    func collectionPeople(
        slug: String, page: Int = 1, request: URLRequest? = nil
    ) async throws -> AO3CollectionPeoplePage {
        guard let url = AO3CollectionURL.people(slug: slug, page: page) else { throw AO3Error.parse }
        return try Self.parseCollectionPeoplePage(await html(url, request: request), page: page)
    }

    func collectionItems(
        slug: String,
        tab: AO3CollectionItemTab = .unreviewed,
        page: Int = 1,
        request: URLRequest
    ) async throws -> AO3CollectionItemsPage {
        var request = request
        request.url = AO3CollectionURL.items(slug: slug, tab: tab, page: page)
        let body = try await authenticatedPageHTML(for: request)
        return try Self.parseCollectionItemsPage(body, slug: slug, tab: tab, page: page)
    }

    func collectionEditForm(slug: String, request: URLRequest) async throws -> AO3CollectionForm {
        var request = request
        request.url = AO3CollectionURL.edit(slug: slug)
        return try Self.parseCollectionForm(await authenticatedPageHTML(for: request), slug: slug)
    }

    func collectionNewForm(request: URLRequest) async throws -> AO3CollectionForm {
        var request = request
        request.url = AO3CollectionURL.new()
        return try Self.parseCollectionForm(await authenticatedPageHTML(for: request), slug: "")
    }

    func collectionParticipants(
        slug: String, request: URLRequest
    ) async throws -> [AO3CollectionParticipant] {
        var request = request
        request.url = AO3CollectionURL.participants(slug: slug)
        return try Self.parseCollectionParticipants(
            await authenticatedPageHTML(for: request), slug: slug
        )
    }

    func collectionModeration(
        slug: String, request: URLRequest
    ) async throws -> AO3CollectionModeration {
        let items = try await AO3RequestCoordinator.shared.withSlot {
            try await collectionItems(slug: slug, tab: .unreviewed, page: 1, request: request)
        }
        let people = try await AO3RequestCoordinator.shared.withSlot {
            try await collectionParticipants(slug: slug, request: request)
        }
        let show = try await AO3RequestCoordinator.shared.withSlot {
            try await collectionShow(slug: slug, request: request)
        }
        return AO3CollectionModeration(
            slug: slug,
            awaitingReview: items.items,
            membershipRequests: people.filter(\.role.isMembershipRequest),
            maintainers: people.filter(\.role.isMaintainer),
            invitations: people.filter(\.role.isInvitation),
            revealScheduleText: revealScheduleText(from: show),
            itemsForm: items
        )
    }

    /// URL-name uniqueness. AO3 does not expose a cheap HEAD or availability
    /// endpoint — `Collection` only validates uniqueness on save
    /// (`validates :name, uniqueness:`). Heuristic: GET `/collections/<name>`
    /// through this client (host allow-list, pacing, retries) inside a
    /// coordinator slot. **404 → available**, **200 → taken**, anything else
    /// → **unknown**. Reserved slugs (`new`, challenge-list routes) are taken.
    /// Names that fail AO3's format (`[A-Za-z0-9]\w*[A-Za-z0-9]`) are invalid
    /// and never hit the network.
    func collectionNameAvailable(_ name: String) async throws -> AO3CollectionNameAvailability {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.collectionNameFormatIsValid(trimmed) else { return .invalid }
        if AO3CollectionURL.reservedSlugs.contains(trimmed.lowercased()) { return .taken }
        guard let url = AO3CollectionURL.show(slug: trimmed) else { return .invalid }
        return try await AO3RequestCoordinator.shared.withSlot {
            do {
                _ = try await getHTML(url)
                return Self.interpretCollectionNameAvailability(httpStatus: 200)
            } catch let error as AO3Error {
                return Self.interpretCollectionNameAvailability(error: error)
            }
        }
    }

    static func collectionNameFormatIsValid(_ name: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"^[A-Za-z0-9]\w*[A-Za-z0-9]$"#) else {
            return false
        }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return regex.firstMatch(in: name, range: range) != nil
    }

    /// Pure mapping used by `collectionNameAvailable` and its unit test.
    static func interpretCollectionNameAvailability(
        httpStatus: Int? = nil,
        error: AO3Error? = nil
    ) -> AO3CollectionNameAvailability {
        if let error {
            switch error {
            case .notFound: return .available
            default: return .unknown
            }
        }
        if let httpStatus {
            if (200...299).contains(httpStatus) { return .taken }
            if httpStatus == 404 { return .available }
            return .unknown
        }
        return .unknown
    }

    // MARK: - Show / blurb

    static func parseCollectionShow(_ html: String, slug: String) throws -> AO3CollectionShow {
        let doc = try SwiftSoup.parse(html)
        let title = ((try? doc.select("div.primary.header.module h2.heading").first()?.text()) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let typeText = ((try? doc.select("p.type").first()?.text()) ?? "")
        let flags = parseCollectionFlags(fromTypeText: typeText)
        let iconURL = try? doc.select("div.primary.header.module .icon img, .collection .icon img")
            .first()
            .flatMap { AO3URLResolver.resolve(try $0.attr("src")) }
        let headerImage = try? doc.select("img.collection-header, .header img[src*='header']")
            .first()
            .flatMap { AO3URLResolver.resolve(try $0.attr("src")) }
        let description = ((try? doc.select("div.primary.header.module > blockquote.userstuff").first()?.text()) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let intro = profileSection("intro", in: doc)
        let faq = profileSection("faq", in: doc)
        let rules = profileSection("rules", in: doc)
        let maintainers = parseMaintainerIdentities(in: doc)
        let dashboard = parseDashboard(in: doc, slug: slug)
        let nav = ((try? doc.select("ul.navigation.actions").first()?.text()) ?? "")
        let hasJoin = (try? doc.select("form[action*='/participants/join']").first()) != nil
            || nav.localizedCaseInsensitiveContains("Join")
        let leaveLink = try? doc.select("a[href*='/participants/'][data-method=delete], a[href*='/participants/']").first()
        let leaveID = leaveLink.flatMap { link -> Int? in
            guard let href = try? link.attr("href") else { return nil }
            return participantID(from: href)
        }
        let canLeave = leaveID != nil && (try? leaveLink?.text())?.localizedCaseInsensitiveContains("Leave") == true
        let isMaintainer = nav.localizedCaseInsensitiveContains("Manage Items")
            || nav.localizedCaseInsensitiveContains("Membership")
        var collection = AO3Collection(
            name: slug,
            title: title.isEmpty ? slug : title,
            byline: maintainers.map(\.displayName).joined(separator: ", "),
            maintainerNames: maintainers.map(\.displayName),
            maintainerIdentities: maintainers,
            isClosed: flags.closed,
            isModerated: flags.moderated,
            isUnrevealed: flags.unrevealed,
            isAnonymous: flags.anonymous,
            iconURL: iconURL,
            summary: description,
            challengeKind: flags.kind
        )
        if collection.title.isEmpty { collection.title = slug }
        return AO3CollectionShow(
            collection: collection,
            headerImageURL: headerImage,
            introduction: intro,
            faq: faq,
            rules: rules,
            canJoin: hasJoin,
            canLeave: canLeave,
            leaveParticipantID: leaveID,
            canPostWork: dashboard.postToCollectionURL != nil,
            isMaintainer: isMaintainer,
            dashboard: dashboard
        )
    }

    /// Richer blurb parse than `parseCollections` (flags, counts, icon). The
    /// original `parseCollections` is left unchanged for existing call sites.
    static func parseCollectionBlurbs(from html: String) throws -> [AO3Collection] {
        let doc = try SwiftSoup.parse(html)
        var result: [AO3Collection] = []
        for li in try doc.select("li.collection.blurb").array() {
            guard let parsed = try? parseCollectionBlurb(li) else { continue }
            result.append(parsed)
        }
        return result
    }

    static func parseCollectionBlurb(_ li: Element) throws -> AO3Collection {
        guard let link = try li.select("h4.heading a[href*=/collections/]").first() else {
            throw AO3Error.parse
        }
        let href = (try? link.attr("href")) ?? ""
        guard let range = href.range(of: "/collections/") else { throw AO3Error.parse }
        let slug = String(href[range.upperBound...]).split(separator: "/").first.map(String.init) ?? ""
        guard !slug.isEmpty else { throw AO3Error.parse }
        let title = (try? link.text()) ?? slug
        let maintainerLinks = try li.select("h4.heading a[href*='/users/']").array()
        let maintainerNames = try maintainerLinks.map { try $0.text() }
        let maintainerIdentities = try maintainerLinks.compactMap { link in
            try AO3AuthorIdentity(displayName: link.text(), href: link.attr("href"))
        }
        let fallbackByline = (try? li.select(".byline, .heading .byline").first()?.text()) ?? ""
        let flags = parseCollectionFlags(fromTypeText: (try? li.select("p.type").first()?.text()) ?? "")
        let works = intStat("works", in: li)
        let bookmarks = intStat("bookmarks", in: li)
        let icon = try? li.select(".icon img").first().flatMap { AO3URLResolver.resolve(try $0.attr("src")) }
        let summary = ((try? li.select("blockquote.userstuff.summary").first()?.text()) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = ((try? li.select("p.datetime").first()?.text()) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return AO3Collection(
            name: slug,
            title: title,
            byline: maintainerNames.isEmpty ? fallbackByline : maintainerNames.joined(separator: ", "),
            maintainerNames: maintainerNames,
            maintainerIdentities: maintainerIdentities,
            isClosed: flags.closed,
            isModerated: flags.moderated,
            isUnrevealed: flags.unrevealed,
            isAnonymous: flags.anonymous,
            worksCount: works,
            bookmarksCount: bookmarks,
            iconURL: icon,
            summary: summary,
            updatedAtText: updated,
            challengeKind: flags.kind
        )
    }

    /// Parses AO3's `(Open, Moderated, Unrevealed, Anonymous, Gift Exchange Challenge)`
    /// type line into four independent flags plus optional challenge kind.
    static func parseCollectionFlags(fromTypeText text: String) -> (
        closed: Bool, moderated: Bool, unrevealed: Bool, anonymous: Bool, kind: AO3ChallengeKind?
    ) {
        let lower = text.lowercased()
        let closed = lower.contains("closed")
        let moderated = lower.contains("moderated") && !lower.contains("unmoderated")
        let unrevealed = lower.contains("unrevealed")
        let anonymous = lower.contains("anonymous")
        let kind: AO3ChallengeKind?
        if lower.contains("gift exchange") {
            kind = .giftExchange
        } else if lower.contains("prompt meme") {
            kind = .promptMeme
        } else {
            kind = nil
        }
        return (
            closed: closed,
            moderated: moderated,
            unrevealed: unrevealed,
            anonymous: anonymous,
            kind: kind
        )
    }

    // MARK: - People

    static func parseCollectionPeoplePage(_ html: String, page: Int) throws -> AO3CollectionPeoplePage {
        let doc = try SwiftSoup.parse(html)
        let blurbs = try doc.select(
            "ul.participant.pseud.index li, li.user.pseud.blurb, li.pseud.blurb"
        ).array()
        if blurbs.isEmpty {
            let heading = ((try? doc.select("h2.heading").first()?.text()) ?? "").lowercased()
            let recognized = heading.contains("participant") || heading.contains("people")
                || (try? doc.select("p").first()?.text())?.localizedCaseInsensitiveContains("no matching") == true
            guard recognized else { throw AO3Error.parse }
        }
        let people = blurbs.compactMap { try? parseCollectionPerson($0) }
        if !blurbs.isEmpty, people.isEmpty { throw AO3Error.parse }
        return AO3CollectionPeoplePage(
            people: people,
            currentPage: page,
            totalPages: try paginationTotal(in: doc, currentPage: page)
        )
    }

    private static func parseCollectionPerson(_ li: Element) throws -> AO3CollectionPerson {
        guard let link = try li.select("h4.heading a[href*='/users/'], h5.heading a[href*='/users/'], a[href*='/users/']").first() else {
            throw AO3Error.parse
        }
        let name = try link.text()
        guard let identity = try AO3AuthorIdentity(displayName: name, href: link.attr("href")) else {
            throw AO3Error.parse
        }
        var copy = identity
        copy.avatarURL = try? li.select(".icon img").first().flatMap { AO3URLResolver.resolve(try $0.attr("src")) }
        let works = intStat("works", in: li)
        return AO3CollectionPerson(identity: copy, workCount: works)
    }

    // MARK: - Items

    static func parseCollectionItemsPage(
        _ html: String,
        slug: String,
        tab: AO3CollectionItemTab,
        page: Int
    ) throws -> AO3CollectionItemsPage {
        let doc = try SwiftSoup.parse(html)
        let form = try doc.select("form[action*='/items']").first()
            ?? doc.select("#main form").first()
        let items = try doc.select("li.collection.item, li.item.blurb").array()
            .compactMap { try? parseCollectionItem($0, slug: slug) }
        if items.isEmpty {
            let heading = ((try? doc.select("h2.heading").first()?.text()) ?? "").lowercased()
            let recognized = heading.contains("item") || heading.contains("collection")
                || (try? doc.select("ul.navigation.actions").first()) != nil
                || (try? doc.select("p.note").first()) != nil
            guard recognized else { throw AO3Error.parse }
        }
        let action: URL
        if let raw = try? form?.attr("action"), let url = AO3URLResolver.resolve(raw) {
            action = url
        } else {
            action = AO3CollectionURL.itemsUpdateMultiple(slug: slug)
        }
        let csrf = parseCSRFToken(from: html)
            ?? ((try? form?.select("input[name=authenticity_token]").first()?.attr("value")) ?? "")
        let method = try? form?.select("input[name=_method]").first()?.attr("value")
        return AO3CollectionItemsPage(
            items: items,
            tab: tab,
            currentPage: page,
            totalPages: try paginationTotal(in: doc, currentPage: page),
            actionURL: action,
            csrfToken: csrf,
            httpMethodOverride: method?.nilIfBlank
        )
    }

    static func parseCollectionItem(_ li: Element, slug: String) throws -> AO3CollectionItem {
        let heading = try li.select("h4.heading").first()
        let headingID = heading?.id() ?? ""
        var itemID = 0
        if headingID.hasPrefix("collection_item_"),
           let parsed = Int(headingID.replacingOccurrences(of: "collection_item_", with: "")) {
            itemID = parsed
        }
        if itemID == 0 {
            let named = (try? li.select("select, input").array()) ?? []
            let name = named.compactMap { try? $0.attr("name") }
                .first(where: { $0.hasPrefix("collection_items") }) ?? ""
            itemID = collectionItemID(fromFieldName: name) ?? 0
        }
        guard itemID != 0 else { throw AO3Error.parse }

        let titleLink = try li.select("h4.heading a").first()
        let workTitle = ((try? titleLink?.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let workURL = try titleLink.flatMap { AO3URLResolver.resolve(try $0.attr("href")) }
        let workID = workURL.flatMap { url -> Int? in
            let parts = url.pathComponents.filter { $0 != "/" }
            guard let index = parts.firstIndex(of: "works"), index + 1 < parts.count else { return nil }
            return Int(parts[index + 1])
        }
        let collectionLink = try li.select("span.collection a, h5.heading a[href*='/collections/']").first()
        let collectionTitle = ((try? collectionLink?.text()) ?? slug)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let h5 = ((try? li.select("h5.heading").first()?.text()) ?? "")
        var role = ""
        if h5.localizedCaseInsensitiveContains("(Member)") { role = "Member" }
        if h5.localizedCaseInsensitiveContains("(Owner)") { role = "Owner" }
        if h5.localizedCaseInsensitiveContains("(Moderator)") { role = "Moderator" }
        let creatorByline = h5
        let recipient = ((try? li.select("span.recipients .user, span.recipients").first()?.text()) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let selects = (try? li.select("select").array()) ?? []
        let userSelect = selects.first(where: {
            ((try? $0.attr("name")) ?? "").hasSuffix("[user_approval_status]")
        })
        let collectionSelect = selects.first(where: {
            ((try? $0.attr("name")) ?? "").hasSuffix("[collection_approval_status]")
        })
        let userApproval = selectedApproval(userSelect) ?? .unreviewed
        let collectionApproval = selectedApproval(collectionSelect) ?? .unreviewed
        let unrevealed = isChecked(li, nameSuffix: "[unrevealed]")
        let anonymous = isChecked(li, nameSuffix: "[anonymous]")
        let posted = (try? li.select("p.message").first()?.text())?
            .localizedCaseInsensitiveContains("deleted") != true

        return AO3CollectionItem(
            id: itemID,
            collectionSlug: slug,
            collectionTitle: collectionTitle.isEmpty ? slug : collectionTitle,
            workTitle: workTitle,
            workURL: workURL,
            workID: workID,
            itemType: (try? li.select("blockquote.bookmark").first()) != nil ? "Bookmark" : "Work",
            role: role,
            creatorApproval: userApproval,
            moderatorApproval: collectionApproval,
            isUnrevealed: unrevealed,
            isAnonymous: anonymous,
            isPosted: posted,
            recipient: recipient,
            creatorByline: creatorByline,
            userApprovalField: AO3CollectionParam.itemUserApproval(itemID),
            collectionApprovalField: AO3CollectionParam.itemCollectionApproval(itemID),
            unrevealedField: AO3CollectionParam.itemUnrevealed(itemID),
            anonymousField: AO3CollectionParam.itemAnonymous(itemID),
            removeField: AO3CollectionParam.itemRemove(itemID)
        )
    }

    static func parseCollectionItemTabs(from html: String) throws -> [AO3CollectionItemTab] {
        let doc = try SwiftSoup.parse(html)
        var tabs: [AO3CollectionItemTab] = []
        for link in try doc.select("ul.navigation.actions a, ul.navigation.actions span.current").array() {
            let href = ((try? link.attr("href")) ?? "")
            let text = ((try? link.text()) ?? "")
            let combined = href + " " + text
            if combined.contains("unreviewed_by_user")
                || text.localizedCaseInsensitiveContains("Unreviewed by User") {
                tabs.append(.invited)
            } else if combined.contains("rejected_by_user")
                || text.localizedCaseInsensitiveContains("Rejected by User") {
                tabs.append(.rejectedByUser)
            } else if combined.contains("rejected_by_collection")
                || text.localizedCaseInsensitiveContains("Rejected by Collection") {
                tabs.append(.rejected)
            } else if combined.contains("status=approved")
                || text.localizedCaseInsensitiveCompare("Approved") == .orderedSame {
                tabs.append(.approved)
            } else if combined.contains("unreviewed_by_collection")
                || text.localizedCaseInsensitiveContains("Unreviewed by Collection")
                || href.hasSuffix("/items") {
                tabs.append(.unreviewed)
            }
        }
        return tabs.isEmpty ? AO3CollectionItemTab.allCases : tabs
    }

    // MARK: - Form

    static func parseCollectionForm(_ html: String, slug: String) throws -> AO3CollectionForm {
        let doc = try SwiftSoup.parse(html)
        guard let form = try doc.select("form.collection, form[class*='collection'], form[action*='/collections']").first()
                ?? doc.select("#main form").first()
        else { throw AO3Error.parse }

        let actionRaw = (try? form.attr("action"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let actionURL = AO3URLResolver.resolve(actionRaw.isEmpty ? "/collections" : actionRaw) else {
            throw AO3Error.parse
        }
        let csrf = parseCSRFToken(from: html)
            ?? ((try? form.select("input[name=authenticity_token]").first()?.attr("value")) ?? "")
        guard !csrf.isEmpty else { throw AO3Error.parse }
        let method = try? form.select("input[name=_method]").first()?.attr("value")
        let isNew = slug.isEmpty

        let name = inputValue(form, "collection[name]")
        let resolvedSlug = name.isEmpty ? slug : name
        let flags = (
            closed: isChecked(form, name: AO3CollectionParam.closed),
            moderated: isChecked(form, name: AO3CollectionParam.moderated),
            unrevealed: isChecked(form, name: AO3CollectionParam.unrevealed),
            anonymous: isChecked(form, name: AO3CollectionParam.anonymous)
        )
        var ownerIDs: [String] = []
        for select in (try? form.select("select").array()) ?? [] {
            guard (try? select.attr("name")) == AO3CollectionParam.ownerPseuds else { continue }
            for option in (try? select.select("option[selected]").array()) ?? [] {
                let value = ((try? option.attr("value")) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { ownerIDs.append(value) }
            }
        }
        for input in (try? form.select("input").array()) ?? [] {
            guard (try? input.attr("name")) == AO3CollectionParam.ownerPseuds else { continue }
            let value = ((try? input.attr("value")) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { ownerIDs.append(value) }
        }

        var hidden: [(String, String)] = []
        for input in try form.select("input[type=hidden]").array() {
            let n = (try? input.attr("name")) ?? ""
            let v = (try? input.attr("value")) ?? ""
            guard !n.isEmpty, n != "authenticity_token" else { continue }
            hidden.append((n, v))
        }

        let (fieldErrors, general) = parseFormErrors(in: doc)

        return AO3CollectionForm(
            actionURL: actionURL,
            httpMethodOverride: method?.nilIfBlank,
            csrfToken: csrf,
            isNew: isNew,
            collectionSlug: resolvedSlug,
            name: name,
            nameIsLocked: !slug.isEmpty,
            title: inputValue(form, AO3CollectionParam.title),
            parentName: inputValue(form, AO3CollectionParam.parentName),
            email: inputValue(form, AO3CollectionParam.email),
            headerImageURL: inputValue(form, AO3CollectionParam.headerImageURL),
            headerImageAlt: inputValue(form, "collection[header_image_alt]")
                .nilIfBlank ?? "",
            iconURL: try? form.select("img").first().flatMap { AO3URLResolver.resolve(try $0.attr("src")) },
            iconAlt: inputValue(form, AO3CollectionParam.iconAlt),
            iconComment: inputValue(form, AO3CollectionParam.iconComment),
            deleteIcon: isChecked(form, name: AO3CollectionParam.deleteIcon),
            description: textAreaValue(form, AO3CollectionParam.description),
            tagString: inputValue(form, AO3CollectionParam.tagString),
            isMultifandom: isChecked(form, name: AO3CollectionParam.multifandom),
            ownerPseudIDs: ownerIDs,
            isClosed: flags.closed,
            isModerated: flags.moderated,
            isUnrevealed: flags.unrevealed,
            isAnonymous: flags.anonymous,
            showRandom: isChecked(form, name: AO3CollectionParam.showRandom),
            emailNotify: isChecked(form, name: AO3CollectionParam.emailNotify),
            challengeType: selectedValue(form, name: AO3CollectionParam.challengeType),
            preferenceID: inputValue(form, AO3CollectionParam.preferenceID),
            introduction: textAreaValue(form, AO3CollectionParam.intro),
            faq: textAreaValue(form, AO3CollectionParam.faq),
            rules: textAreaValue(form, AO3CollectionParam.rules),
            giftNotification: textAreaValue(form, AO3CollectionParam.giftNotification),
            assignmentNotification: textAreaValue(form, AO3CollectionParam.assignmentNotification),
            profileID: inputValue(form, AO3CollectionParam.profileID),
            maintainers: (try? parseCollectionParticipants(html, slug: resolvedSlug)) ?? [],
            invitationField: (try? form.select("input[name=participants_to_invite]").first()?.attr("name")) ?? "",
            revealScheduleText: revealScheduleText(in: doc),
            fieldErrors: fieldErrors,
            generalErrors: general,
            hiddenFields: hidden
        )
    }

    static func parseCollectionParticipants(
        _ html: String, slug: String
    ) throws -> [AO3CollectionParticipant] {
        let doc = try SwiftSoup.parse(html)
        var result: [AO3CollectionParticipant] = []
        for li in try doc.select("ul.participant.index li, li[id^=participant_]").array() {
            guard let parsed = try? parseParticipant(li, slug: slug) else { continue }
            result.append(parsed)
        }
        return result
    }

    // MARK: - Form encoding helpers

    static func collectionFormParameters(_ form: AO3CollectionForm) -> [(String, String)] {
        var params: [(String, String)] = [
            ("authenticity_token", form.csrfToken),
            (AO3CollectionParam.name, form.name),
            (AO3CollectionParam.title, form.title),
            (AO3CollectionParam.email, form.email),
            (AO3CollectionParam.headerImageURL, form.headerImageURL),
            (AO3CollectionParam.description, form.description),
            (AO3CollectionParam.parentName, form.parentName),
            (AO3CollectionParam.iconAlt, form.iconAlt),
            (AO3CollectionParam.iconComment, form.iconComment),
            (AO3CollectionParam.tagString, form.tagString),
            (AO3CollectionParam.multifandom, form.isMultifandom ? "1" : "0"),
            (AO3CollectionParam.deleteIcon, form.deleteIcon ? "1" : "0"),
            (AO3CollectionParam.challengeType, form.challengeType),
            (AO3CollectionParam.moderated, form.isModerated ? "1" : "0"),
            (AO3CollectionParam.closed, form.isClosed ? "1" : "0"),
            (AO3CollectionParam.unrevealed, form.isUnrevealed ? "1" : "0"),
            (AO3CollectionParam.anonymous, form.isAnonymous ? "1" : "0"),
            (AO3CollectionParam.showRandom, form.showRandom ? "1" : "0"),
            (AO3CollectionParam.emailNotify, form.emailNotify ? "1" : "0"),
            (AO3CollectionParam.intro, form.introduction),
            (AO3CollectionParam.faq, form.faq),
            (AO3CollectionParam.rules, form.rules),
            (AO3CollectionParam.giftNotification, form.giftNotification),
            (AO3CollectionParam.assignmentNotification, form.assignmentNotification)
        ]
        if let method = form.httpMethodOverride, !method.isEmpty {
            params.insert(("_method", method), at: 0)
        }
        if !form.preferenceID.isEmpty {
            params.append((AO3CollectionParam.preferenceID, form.preferenceID))
        }
        if !form.profileID.isEmpty {
            params.append((AO3CollectionParam.profileID, form.profileID))
        }
        if form.ownerPseudIDs.isEmpty == false {
            for id in form.ownerPseudIDs {
                params.append((AO3CollectionParam.ownerPseuds, id))
            }
        }
        return params
    }

    static func collectionItemParameters(
        _ draft: AO3CollectionItemDraft, csrf: String, methodOverride: String?
    ) -> [(String, String)] {
        var params: [(String, String)] = [("authenticity_token", csrf)]
        if let method = methodOverride, !method.isEmpty {
            params.append(("_method", method))
        }
        let id = draft.itemID
        if let approval = draft.creatorApproval {
            params.append((AO3CollectionParam.itemUserApproval(id), approval.rawValue))
        }
        if let approval = draft.moderatorApproval {
            params.append((AO3CollectionParam.itemCollectionApproval(id), approval.rawValue))
        }
        if let unrevealed = draft.isUnrevealed {
            params.append((AO3CollectionParam.itemUnrevealed(id), unrevealed ? "1" : "0"))
        }
        if let anonymous = draft.isAnonymous {
            params.append((AO3CollectionParam.itemAnonymous(id), anonymous ? "1" : "0"))
        }
        if draft.remove {
            params.append((AO3CollectionParam.itemRemove(id), "1"))
        }
        return params
    }

    // MARK: - Internals

    private func html(_ url: URL, request: URLRequest?) async throws -> String {
        if var request {
            request.url = url
            return try await authenticatedPageHTML(for: request)
        }
        return try await getHTML(url)
    }

    private static func parseDashboard(in doc: Document, slug: String) -> AO3CollectionDashboard {
        func link(containing: String) -> URL? {
            let nodes = (try? doc.select("#dashboard a, ul.navigation.actions a").array()) ?? []
            for node in nodes {
                let href = (try? node.attr("href")) ?? ""
                if href.contains(containing) { return AO3URLResolver.resolve(href) }
            }
            return nil
        }
        return AO3CollectionDashboard(
            profileURL: link(containing: "/profile") ?? AO3CollectionURL.profile(slug: slug),
            worksURL: link(containing: "/works") ?? Self.collectionWorksURL(name: slug, page: 1),
            bookmarksURL: link(containing: "/bookmarks") ?? AO3CollectionURL.bookmarks(slug: slug),
            peopleURL: link(containing: "/people") ?? AO3CollectionURL.people(slug: slug),
            itemsURL: link(containing: "/items"),
            participantsURL: link(containing: "/participants"),
            signUpsURL: link(containing: "/signups"),
            assignmentsURL: link(containing: "/assignments"),
            promptsURL: link(containing: "/requests"),
            challengeSettingsURL: link(containing: "/gift_exchange") ?? link(containing: "/prompt_meme"),
            postToCollectionURL: link(containing: "/works/new")
        )
    }

    private static func parseMaintainerIdentities(in doc: Document) -> [AO3AuthorIdentity] {
        let links = (try? doc.select("a.owner, a.mod, h4.heading a[href*='/users/']").array()) ?? []
        return links.compactMap { link in
            let name = (try? link.text()) ?? ""
            let href = (try? link.attr("href")) ?? ""
            return AO3AuthorIdentity(displayName: name, href: href)
        }
    }

    private static func profileSection(_ id: String, in doc: Document) -> String {
        let text = (try? doc.select("#\(id), div#\(id)").first()?.text()) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func revealScheduleText(from show: AO3CollectionShow) -> String {
        show.collection.isUnrevealed || show.collection.isAnonymous
            ? [
                show.collection.isUnrevealed ? "Unrevealed" : nil,
                show.collection.isAnonymous ? "Anonymous" : nil
            ].compactMap { $0 }.joined(separator: ", ")
            : ""
    }

    private static func revealScheduleText(in doc: Document) -> String {
        let meta = ((try? doc.select("dl.meta, .collection .meta").first()?.text()) ?? "")
        if meta.localizedCaseInsensitiveContains("reveal") { return meta }
        return ""
    }

    private static func parseParticipant(
        _ li: Element, slug: String
    ) throws -> AO3CollectionParticipant {
        let idAttr = li.id()
        var id = 0
        if idAttr.hasPrefix("participant_") {
            id = Int(idAttr.replacingOccurrences(of: "participant_", with: "")) ?? 0
        }
        if id == 0 {
            let action = (try? li.select("form").first()?.attr("action")) ?? ""
            id = participantID(from: action) ?? 0
        }
        guard id != 0 else { throw AO3Error.parse }
        let link = try li.select("span.byline a, a[href*='/users/']").first()
        let pseud = ((try? link?.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = try link.flatMap { try AO3AuthorIdentity(displayName: $0.text(), href: $0.attr("href")) }
        let selected = selectedValue(li, name: AO3CollectionParam.participantRole)
            .nilIfBlank
            ?? selectedValue(li, nameSuffix: "[participant_role]")
        let role = AO3CollectionParticipantRole(ao3: selected) ?? .member
        let action = (try? li.select("form").first()?.attr("action")) ?? ""
        return AO3CollectionParticipant(
            id: id,
            collectionSlug: slug,
            pseud: pseud,
            role: role,
            identity: identity,
            updateURL: AO3URLResolver.resolve(action)
        )
    }

    private static func parseFormErrors(in doc: Document) -> ([String: String], [String]) {
        var field: [String: String] = [:]
        var general: [String] = []
        let items = (try? doc.select("#error ul li, .error ul li, #errorExplanation li, div.error ul li").array()) ?? []
        for item in items {
            let text = ((try? item.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            general.append(text)
        }
        for node in (try? doc.select(".field_with_errors input, .field_with_errors textarea, .fieldWithErrors input").array()) ?? [] {
            let name = (try? node.attr("name")) ?? ""
            if !name.isEmpty { field[name] = general.first ?? "Invalid" }
        }
        return (field, general)
    }

    static func inputValue(_ root: Element, _ name: String) -> String {
        let nodes = (try? root.select("input").array()) ?? []
        for node in nodes where (try? node.attr("name")) == name {
            return ((try? node.attr("value")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    static func textAreaValue(_ root: Element, _ name: String) -> String {
        let nodes = (try? root.select("textarea").array()) ?? []
        for node in nodes where (try? node.attr("name")) == name {
            return ((try? node.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    static func selectedValue(_ root: Element, name: String) -> String {
        let nodes = (try? root.select("select").array()) ?? []
        guard let select = nodes.first(where: { (try? $0.attr("name")) == name }) else { return "" }
        return selectedOptionValue(select)
    }

    static func selectedValue(_ root: Element, nameSuffix: String) -> String {
        let nodes = (try? root.select("select").array()) ?? []
        guard let select = nodes.first(where: { ((try? $0.attr("name")) ?? "").hasSuffix(nameSuffix) }) else {
            return ""
        }
        return selectedOptionValue(select)
    }

    static func isChecked(_ root: Element, name: String) -> Bool {
        let nodes = (try? root.select("input[type=checkbox]").array()) ?? []
        guard let input = nodes.first(where: { (try? $0.attr("name")) == name }) else { return false }
        return (try? input.hasAttr("checked")) ?? false
    }

    static func isChecked(_ root: Element, nameSuffix: String) -> Bool {
        let nodes = (try? root.select("input[type=checkbox]").array()) ?? []
        guard let input = nodes.first(where: { ((try? $0.attr("name")) ?? "").hasSuffix(nameSuffix) }) else {
            return false
        }
        return (try? input.hasAttr("checked")) ?? false
    }

    private static func selectedOptionValue(_ select: Element) -> String {
        if let selected = try? select.select("option[selected]").first()?.attr("value"), !selected.isEmpty {
            return selected
        }
        return (try? select.select("option").first()?.attr("value")) ?? ""
    }

    private static func selectedApproval(_ select: Element?) -> AO3CollectionItemApproval? {
        guard let select else { return nil }
        let value: String
        if let selected = try? select.select("option[selected]").first()?.attr("value"), !selected.isEmpty {
            value = selected
        } else {
            value = (try? select.select("option").first()?.attr("value")) ?? ""
        }
        return AO3CollectionItemApproval(ao3: value)
    }

    private static func intStat(_ kind: String, in element: Element) -> Int? {
        let text = (try? element.select("dl.stats dd.\(kind)").first()?.text()) ?? ""
        let digits = text.filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }

    private static func collectionItemID(fromFieldName name: String) -> Int? {
        guard let open = name.firstIndex(of: "["), let close = name[open...].firstIndex(of: "]") else {
            return nil
        }
        let inner = name[name.index(after: open)..<close]
        return Int(inner)
    }

    private static func participantID(from href: String) -> Int? {
        let parts = href.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(of: "participants"), index + 1 < parts.count else {
            return nil
        }
        let raw = parts[index + 1].split(separator: "?").first.map(String.init) ?? ""
        return Int(raw)
    }

}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
