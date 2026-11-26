import Foundation
import SwiftSoup

/// URL builders and SwiftSoup parsers for T-575 writing actions: co-creator
/// invitations, gifts to you, related works, orphaning, co-creator removal,
/// and work import from URL.
///
/// Ground truth: otwarchive master `452391b6` (2026-11-01) — controllers,
/// views, and `config/routes.rb`.
extension AO3Client {

    // MARK: - URLs

    /// `GET`/`PUT` `/users/:login/creatorships` (`?page=N` when `page > 1`).
    static func coCreatorRequestsURL(username: String, page: Int = 1) -> URL? {
        let items = page > 1 ? [URLQueryItem(name: "page", value: String(page))] : []
        return userScopedURL(username: username, pathSuffix: "creatorships", queryItems: items)
    }

    /// `GET /users/:login/gifts` (`?refused=true` for refused gifts; `?page=N` when `page > 1`).
    static func giftsURL(username: String, refused: Bool = false, page: Int = 1) -> URL? {
        var items: [URLQueryItem] = []
        if refused { items.append(URLQueryItem(name: "refused", value: "true")) }
        if page > 1 { items.append(URLQueryItem(name: "page", value: String(page))) }
        return userScopedURL(username: username, pathSuffix: "gifts", queryItems: items)
    }

    /// `POST /gifts/:id/toggle_rejected` (`config/routes.rb:463-467`).
    static func toggleGiftRejectedURL(giftID: Int) -> URL {
        URL(string: "https://archiveofourown.org/gifts/\(giftID)/toggle_rejected")!
    }

    /// `GET /users/:login/related_works`.
    static func relatedWorksURL(username: String) -> URL? {
        userScopedURL(username: username, pathSuffix: "related_works")
    }

    /// `GET`/`PATCH`/`DELETE` `/related_works/:id` (`config/routes.rb:449`).
    static func relatedWorkURL(id: Int) -> URL {
        URL(string: "https://archiveofourown.org/related_works/\(id)")!
    }

    /// `GET /orphans/new?work_id=…` | `?work_ids[]=…` | `?series_id=…`
    /// (`app/controllers/orphans_controller.rb:14-35`).
    static func orphanNewURL(for target: AO3OrphanTarget) -> URL? {
        var components = URLComponents(string: "https://archiveofourown.org/orphans/new")
        switch target {
        case let .work(id):
            components?.queryItems = [URLQueryItem(name: "work_id", value: String(id))]
        case let .works(ids):
            guard !ids.isEmpty else { return nil }
            components?.queryItems = ids.map { URLQueryItem(name: "work_ids[]", value: String($0)) }
        case let .series(id):
            components?.queryItems = [URLQueryItem(name: "series_id", value: String(id))]
        }
        return components?.url
    }

    /// `POST /orphans` (`config/routes.rb:651`).
    static func orphansCreateURL() -> URL {
        URL(string: "https://archiveofourown.org/orphans")!
    }

    /// `PATCH /works/:id/remove_user_creatorship` (`config/routes.rb:394`).
    static func workRemoveUserCreatorshipURL(workID: Int) -> URL {
        URL(string: "https://archiveofourown.org/works/\(workID)/remove_user_creatorship")!
    }

    /// `PATCH /series/:id/remove_user_creatorship` (`config/routes.rb:456`).
    static func seriesRemoveUserCreatorshipURL(seriesID: Int) -> URL {
        URL(string: "https://archiveofourown.org/series/\(seriesID)/remove_user_creatorship")!
    }

    /// `GET /works/new?import=true` (`WorksController#new`, lines 278-280).
    static func importWorkFormURL() -> URL {
        URL(string: "https://archiveofourown.org/works/new?import=true")!
    }

    /// `POST /works/import` (`config/routes.rb:386`).
    static func importWorkURL() -> URL {
        URL(string: "https://archiveofourown.org/works/import")!
    }

    // MARK: - 1. Co-creator requests (`creatorships/show.html.erb`)

    /// Parses `GET /users/:login/creatorships` (otwarchive `452391b6`
    /// `app/views/creatorships/show.html.erb`).
    static func parseCoCreatorRequests(
        from html: String,
        page: Int = 1
    ) throws -> AO3CoCreatorRequestsPage {
        let doc = try SwiftSoup.parse(html)
        let form = try doc.select("form[action*=/creatorships]").first()
        let tableRows = try doc.select("fieldset.creatorships table tr").array().filter {
            ((try? $0.select("td").array())?.isEmpty) == false
        }
        var requests: [AO3CoCreatorRequest] = []
        for row in tableRows {
            if let parsed = try parseCoCreatorRow(row) { requests.append(parsed) }
        }
        if tableRows.isEmpty {
            let heading = ((try? doc.select("h2.heading").first()?.text()) ?? "").lowercased()
            let hasEmptyCopy = ((try? doc.select("#main p, p").array()) ?? []).contains {
                ((try? $0.text()) ?? "").localizedCaseInsensitiveContains("no co-creator requests found")
            }
            guard heading.contains("co-creator requests") || hasEmptyCopy || form != nil else {
                throw AO3Error.parse
            }
        } else if requests.isEmpty {
            throw AO3Error.parse
        }

        let csrf = form.flatMap { formToken(in: $0, fallbackHTML: html) } ?? parseCSRFToken(from: html) ?? ""
        let actionURL = form.flatMap { try? $0.attr("action") }.flatMap { AO3URLResolver.resolve($0) }
        return AO3CoCreatorRequestsPage(
            requests: requests,
            csrfToken: csrf,
            actionURL: actionURL,
            currentPage: page,
            totalPages: try paginationTotal(in: doc, currentPage: page)
        )
    }

    private static func parseCoCreatorRow(_ row: Element) throws -> AO3CoCreatorRequest? {
        let cells = try row.select("td").array()
        guard cells.count >= 5 else { return nil }
        // `collection_check_boxes "", :selected` emits `name="selected[]"` on
        // current Rails and `name="[selected][]"` (or `<prefix>[selected][]`)
        // on older Rails, plus a hidden input with empty value; match checkboxes only.
        let selector = "input[type=checkbox][name='selected[]'], input[type=checkbox][name$='[selected][]']"
        guard let box = try cells[4].select(selector).first(),
              let id = Int((try box.attr("value")).trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        let link = try cells[0].select("a[href]").first()
        let title = try (link?.text() ?? cells[0].text())
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let href = (try link?.attr("href")) ?? ""
        return AO3CoCreatorRequest(
            id: id,
            title: title,
            creationURL: AO3URLResolver.resolve(href),
            creationType: (try cells[1].text()).trimmingCharacters(in: .whitespacesAndNewlines),
            workID: workIDFromPath(href),
            seriesID: seriesID(inPath: href),
            chapterID: chapterID(inPath: href),
            invitedPseud: (try cells[2].text()).trimmingCharacters(in: .whitespacesAndNewlines),
            dateText: (try cells[3].text()).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    // MARK: - 2. Gifts (`gifts/index.html.erb`, `gifts/_gift_blurb.html.erb`)

    /// Parses `GET /users/:login/gifts` (or `?refused=true`), reusing
    /// `AO3Client.parseBlurb` for each work blurb (otwarchive `452391b6`
    /// `app/views/gifts/index.html.erb` & `_gift_blurb.html.erb`).
    static func parseGiftsPage(
        from html: String,
        refused: Bool = false,
        page: Int = 1
    ) throws -> AO3GiftsPage {
        let doc = try SwiftSoup.parse(html)
        let items = try doc.select("ul.gift.work.index > li[id^=work_], li.gift.work.blurb").array()
        var rows: [AO3GiftRow] = []
        for item in items {
            if let row = try parseGiftRow(item) { rows.append(row) }
        }
        if items.isEmpty {
            let hasList = (try? doc.select("ul.gift.work.index").first()) != nil
            let heading = ((try? doc.select("h2.heading").first()?.text()) ?? "").lowercased()
            guard hasList || heading.contains("gifts") else { throw AO3Error.parse }
        } else if rows.isEmpty {
            throw AO3Error.parse
        }

        return AO3GiftsPage(
            gifts: rows,
            isRefusedList: refused,
            csrfToken: parseCSRFToken(from: html) ?? "",
            currentPage: page,
            totalPages: try paginationTotal(in: doc, currentPage: page)
        )
    }

    private static func parseGiftRow(_ li: Element) throws -> AO3GiftRow? {
        guard let work = try? parseBlurb(li),
              let actionLink = try li.select("a[href*=/toggle_rejected]").first(),
              let giftID = pathID(in: try actionLink.attr("href"), after: "gifts")
        else { return nil }
        let label = (try actionLink.text()).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isRefused: Bool
        if label == "accept gift" {
            isRefused = true
        } else if label == "refuse gift" {
            isRefused = false
        } else {
            return nil
        }
        let isAnonymous = work.authorIdentities.contains { $0.kind == .anonymous }
            || ((try? isAnonymousBlurb(li)) == true)
        let creators: [String] = if !work.authors.isEmpty {
            work.authors
        } else if isAnonymous {
            ["Anonymous"]
        } else {
            work.authorIdentities.map(\.displayName)
        }
        return AO3GiftRow(
            giftID: giftID, workID: work.id, title: work.title,
            creators: creators, isAnonymous: isAnonymous, isRefused: isRefused, work: work
        )
    }

    // MARK: - 3. Related works (`related_works/index`, `show`, `_approve`, `_remove`)

    /// Parses `GET /users/:login/related_works` (otwarchive `452391b6`
    /// `app/views/related_works/index.html.erb`).
    ///
    /// Note: otwarchive renders `#translationsofme` and `#translationsbyme` as
    /// `<table>`s and the two inspired/remix sections as `<dl class="inspired index group">`.
    static func parseRelatedWorks(from html: String) throws -> AO3RelatedWorksPage {
        let doc = try SwiftSoup.parse(html)
        let translationsOfMe = try parseTranslationTable(
            in: doc, selector: "table#translationsofme", isParentOwned: true
        )
        let translationsByMe = try parseTranslationTable(
            in: doc, selector: "table#translationsbyme", isParentOwned: false
        )
        let (inspiredByMe, thatInspiredMe) = try parseInspiredLists(in: doc)

        let hasAnySection = (try? doc.select(
            "table#translationsofme, table#translationsbyme, dl.inspired.index"
        ).first()) != nil
        if !hasAnySection {
            let heading = ((try? doc.select("h2.heading").first()?.text()) ?? "").lowercased()
            guard heading.contains("related works") else { throw AO3Error.parse }
        }
        return AO3RelatedWorksPage(
            translationsOfMe: translationsOfMe,
            translationsByMe: translationsByMe,
            inspiredByMe: inspiredByMe,
            thatInspiredMe: thatInspiredMe,
            csrfToken: parseCSRFToken(from: html)
        )
    }

    /// Parses `GET /related_works/:id` (`related_works/show.html.erb` rendering
    /// `_approve.html.erb` or `_remove.html.erb`, otwarchive `452391b6`).
    static func parseRelatedWorkShow(from html: String) throws -> AO3RelatedWorkShow {
        let doc = try SwiftSoup.parse(html)
        let heading = ((try? doc.select("#main h3.heading, h3.heading").first()?.text()) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let mode: AO3RelatedWorkShowMode
        let defaultCommit: String
        if heading == "approve link" {
            mode = .approve
            defaultCommit = "Yes, link me!"
        } else if heading == "remove link" {
            mode = .remove
            defaultCommit = "Remove link"
        } else {
            throw AO3Error.parse
        }
        guard let form = try doc.select("form.edit_related_work, form[action*=/related_works/]").first(),
              let actionURL = AO3URLResolver.resolve(try form.attr("action"))
        else { throw AO3Error.parse }
        guard let csrf = formToken(in: form, fallbackHTML: html) else {
            throw AO3WorkWriteError.noCSRFToken
        }
        let method = (try? form.select("input[name=_method]").first()?.attr("value"))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let submitValue = ((try? form.select("input[type=submit][name=commit], input[type=submit]")
            .first()?.attr("value")) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return AO3RelatedWorkShow(
            id: pathID(in: actionURL.path, after: "related_works"),
            mode: mode,
            actionURL: actionURL,
            httpMethodOverride: method?.isEmpty == false ? method : nil,
            csrfToken: csrf,
            commitValue: submitValue.isEmpty ? defaultCommit : submitValue
        )
    }

    /// Reads the `authenticity_token` of the index page's `button_to "Remove"`
    /// form for `/related_works/:id`, falling back to `<meta name="csrf-token">`.
    static func relatedWorkDeleteToken(from html: String, id: Int) -> String? {
        if let doc = try? SwiftSoup.parse(html),
           let form = ((try? doc.select("form[action*=/related_works/\(id)]").array()) ?? [])
            .first(where: { pathID(in: (try? $0.attr("action")) ?? "", after: "related_works") == id }),
           let token = formToken(in: form, fallbackHTML: html) {
            return token
        }
        return parseCSRFToken(from: html)
    }

    // MARK: - Shared flash & token helpers

    /// Reads AO3's refusal flash or validation list outside writer-authored
    /// content (`#workskin`, `#previewpane`, `.userstuff`).
    static func writingRequestError(in html: String, includeCaution: Bool = true) -> String? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        let selector = includeCaution
            ? ".flash.error, .flash.caution, #error li, .errorlist li"
            : ".flash.error, #error li, .errorlist li"
        return firstNonUserText(in: doc, selector: selector)
    }

    /// Reads AO3's `.flash.notice` outside writer-authored content.
    static func writingRequestNotice(in html: String) -> String? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        return firstNonUserText(in: doc, selector: ".flash.notice")
    }

    /// Prefers a form's own hidden `authenticity_token` (Rails per-form CSRF),
    /// falling back to the page's `<meta name="csrf-token">`.
    static func formToken(in form: Element, fallbackHTML: String) -> String? {
        if let value = try? form.select("input[name=authenticity_token]").first()?.attr("value") {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return parseCSRFToken(from: fallbackHTML)
    }

    // MARK: - Private helpers

    private static func firstNonUserText(in doc: Document, selector: String) -> String? {
        let nodes = (try? doc.select(selector).array()) ?? []
        return nodes.lazy
            .filter { !isInsideUserContent($0) }
            .compactMap { (try? $0.text())?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func userScopedURL(
        username: String,
        pathSuffix: String,
        queryItems: [URLQueryItem] = []
    ) -> URL? {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/") else { return nil }
        var components = URLComponents(string: "https://archiveofourown.org")
        components?.path = "/users/\(name)/\(pathSuffix)"
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        return components?.url
    }

    private static func parseTranslationTable(
        in doc: Document,
        selector: String,
        isParentOwned: Bool
    ) throws -> [AO3RelatedWorkRow] {
        guard let table = try doc.select(selector).first() else { return [] }
        var rows: [AO3RelatedWorkRow] = []
        var actionable = 0
        for tr in try table.select("tbody tr").array() {
            let tds = try tr.select("td").array()
            guard tds.count >= 4 else { continue }
            actionable += 1
            let langs = parseLanguagePair(from: tds[2])
            if isParentOwned {
                guard let link = try tds[3].select("a[href*=/related_works/]").first(),
                      let id = pathID(in: try link.attr("href"), after: "related_works"),
                      let isApproved = reciprocalState(fromActionText: try link.text())
                else { continue }
                rows.append(AO3RelatedWorkRow(
                    id: id,
                    parentWork: parseTitleOnlyWorkRef(from: tds[1]),
                    childWork: parseWorkRefWithByline(from: tds[0]),
                    fromLanguage: langs.from, toLanguage: langs.to,
                    isApproved: isApproved, action: .toggleReciprocal(isApproved: isApproved)
                ))
            } else {
                guard let form = try tds[3].select("form[action*=/related_works/]").first(),
                      let id = pathID(in: try form.attr("action"), after: "related_works")
                else { continue }
                rows.append(AO3RelatedWorkRow(
                    id: id,
                    parentWork: parseWorkRefWithByline(from: tds[0]),
                    childWork: parseTitleOnlyWorkRef(from: tds[1]),
                    fromLanguage: langs.from, toLanguage: langs.to,
                    isApproved: nil, action: .removeLink
                ))
            }
        }
        if actionable > 0, rows.isEmpty { throw AO3Error.parse }
        return rows
    }

    private static func parseInspiredLists(
        in doc: Document
    ) throws -> (inspiredByMe: [AO3RelatedWorkRow], thatInspiredMe: [AO3RelatedWorkRow]) {
        var inspiredByMe: [AO3RelatedWorkRow] = []
        var thatInspiredMe: [AO3RelatedWorkRow] = []
        for dl in try doc.select("dl.inspired.index").array() {
            let children = dl.children().array()
            var index = 0
            while index + 1 < children.count {
                let dt = children[index]
                let dd = children[index + 1]
                index += 1
                guard dt.tagName().lowercased() == "dt", dd.tagName().lowercased() == "dd" else { continue }
                if dt.hasClass("child"), dd.hasClass("parent") {
                    guard let link = try dd.select("a[href*=/related_works/]").first(),
                          let id = pathID(in: try link.attr("href"), after: "related_works"),
                          let isApproved = reciprocalState(fromActionText: try link.text())
                    else { continue }
                    inspiredByMe.append(AO3RelatedWorkRow(
                        id: id,
                        parentWork: parseTitleOnlyWorkRef(from: dd),
                        childWork: parseWorkRefWithByline(from: dt),
                        fromLanguage: nil, toLanguage: nil,
                        isApproved: isApproved, action: .toggleReciprocal(isApproved: isApproved)
                    ))
                } else if dt.hasClass("parent"), dd.hasClass("child") {
                    guard let form = try dd.select("form[action*=/related_works/]").first(),
                          let id = pathID(in: try form.attr("action"), after: "related_works")
                    else { continue }
                    thatInspiredMe.append(AO3RelatedWorkRow(
                        id: id,
                        parentWork: parseWorkRefWithByline(from: dt),
                        childWork: parseTitleOnlyWorkRef(from: dd),
                        fromLanguage: nil, toLanguage: nil,
                        isApproved: nil, action: .removeLink
                    ))
                }
            }
        }
        return (inspiredByMe, thatInspiredMe)
    }

    private static func reciprocalState(fromActionText raw: String) -> Bool? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "remove": true
        case "approve": false
        default: nil
        }
    }

    private static func parseWorkRefWithByline(from container: Element) -> AO3RelatedWorkRef {
        let fullText = ((try? container.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let workLink = ((try? container.select("a[href]").array()) ?? []).first { link in
            let href = (try? link.attr("href")) ?? ""
            return !href.contains("/users/") && !href.contains("/related_works/")
        }
        if workLink == nil, fullText.localizedCaseInsensitiveContains("unrevealed collection") {
            return AO3RelatedWorkRef(workID: nil, title: fullText, url: nil, creators: [], isUnrevealed: true)
        }
        let href = (try? workLink?.attr("href")) ?? ""
        let title = ((try? workLink?.text()) ?? fullText).trimmingCharacters(in: .whitespacesAndNewlines)
        var creators = ((try? container.select("a[rel=author], a[href*=/users/]").array()) ?? [])
            .compactMap { try? $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if creators.isEmpty, let range = fullText.range(of: " by ", options: .backwards) {
            let tail = String(fullText[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty {
                creators = tail.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        }
        return AO3RelatedWorkRef(
            workID: workIDFromPath(href),
            title: title,
            url: AO3URLResolver.resolve(href, allowExternalHost: true),
            creators: creators
        )
    }

    private static func parseTitleOnlyWorkRef(from container: Element) -> AO3RelatedWorkRef {
        let workLink = ((try? container.select("a[href]").array()) ?? []).first { link in
            let href = (try? link.attr("href")) ?? ""
            return !href.contains("/related_works/") && !href.contains("/users/")
        }
        let href = (try? workLink?.attr("href")) ?? ""
        return AO3RelatedWorkRef(
            workID: workIDFromPath(href),
            title: ((try? workLink?.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            url: AO3URLResolver.resolve(href, allowExternalHost: true),
            creators: []
        )
    }

    private static func parseLanguagePair(from cell: Element) -> (from: String?, to: String?) {
        let links = ((try? cell.select("a").array()) ?? [])
            .compactMap { try? $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if links.count >= 2 { return (links[0], links[1]) }
        let text = ((try? cell.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let fromRange = text.range(of: "From ", options: .caseInsensitive),
              let toRange = text.range(
                  of: " to ",
                  options: .caseInsensitive,
                  range: fromRange.upperBound ..< text.endIndex
              )
        else { return (nil, nil) }
        let source = String(text[fromRange.upperBound ..< toRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let dest = String(text[toRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (source.isEmpty ? nil : source, dest.isEmpty ? nil : dest)
    }

    private static func pathID(in href: String, after segment: String) -> Int? {
        let parts = href.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(of: segment), index + 1 < parts.count else { return nil }
        let raw = parts[index + 1].split(separator: "?").first.map(String.init) ?? ""
        return Int(raw)
    }

    static func isInsideUserContent(_ element: Element) -> Bool {
        element.parents().array().contains {
            $0.id() == "workskin" || $0.id() == "previewpane" || $0.hasClass("userstuff")
        }
    }
}
