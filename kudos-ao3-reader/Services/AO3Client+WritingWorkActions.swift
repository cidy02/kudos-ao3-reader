import Foundation
import SwiftSoup

/// SwiftSoup parsers for T-575 Actions 4–6: orphaning, removing yourself as a
/// co-creator, and importing works from URLs.
///
/// Ground truth: otwarchive master `452391b6` (2026-11-01) — controllers,
/// views, and `config/routes.rb`.
extension AO3Client {

    // MARK: - 4. Orphan (`orphans/new`, `_orphan_work`, `_orphan_series`, `_choose_pseud`)

    /// Parses `GET /orphans/new?…` (otwarchive `452391b6` `orphans_controller.rb`
    /// and `app/views/orphans/`). Throws `.notOwned` when AO3 redirects with its
    /// permission error flash.
    static func parseOrphanForm(
        from html: String,
        target: AO3OrphanTarget
    ) throws -> AO3OrphanForm {
        if let error = writingRequestError(in: html, includeCaution: false) {
            throw isNotOwnedOrphanError(error) ? AO3WorkWriteError.notOwned : AO3WorkWriteError.rejected(error)
        }
        let doc = try SwiftSoup.parse(html)
        guard let form = try doc.select("form[action=/orphans], form[action$=/orphans]").first(),
              let actionURL = AO3URLResolver.resolve(try form.attr("action"))
        else { throw AO3Error.parse }
        guard let csrf = formToken(in: form, fallbackHTML: html) else {
            throw AO3WorkWriteError.noCSRFToken
        }

        let radios = parseRadios(form, name: "use_default")
        let values = Set(radios.options.map(\.value))
        guard values.contains("true"), values.contains("false") else { throw AO3Error.parse }

        let cautions = ((try? doc.select("p.caution.notice, p.caution").array()) ?? [])
            .compactMap { try? $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let parsed = try verifyAndExtractOrphanTargets(in: doc, form: form, target: target, cautions: cautions)
        let submit = ((try? form.select("input[type=submit]").first()?.attr("value")) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return AO3OrphanForm(
            target: target,
            actionURL: actionURL,
            csrfToken: csrf,
            titles: parsed.titles,
            workItems: parsed.workItems,
            pseudOptions: radios.options,
            cautionTexts: cautions,
            submitLabel: submit.isEmpty ? "Yes, I'm sure" : submit
        )
    }

    static func isNotOwnedOrphanError(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains("don't have permission to orphan")
            || text.localizedCaseInsensitiveContains("do not have permission to orphan")
    }

    // MARK: - 5. Remove me as co-creator

    /// Detects AO3's redirect to `/orphans/new?work_id=…` or `?series_id=…`
    /// when `remove_user_creatorship` is invoked by the sole listed creator
    /// (`works_controller.rb:339-340`, `series_controller.rb:74-75`).
    static func isOrphanRedirect(finalURL: URL?, body: String) -> Bool {
        if let path = finalURL?.path.lowercased(), path == "/orphans/new" || path.hasSuffix("/orphans/new") {
            return true
        }
        guard let doc = try? SwiftSoup.parse(body),
              let form = try? doc.select("form[action=/orphans], form[action$=/orphans]").first()
        else { return false }
        return (try? form.select("input[name=use_default]").first()) != nil
    }

    /// Reads the `Remove Me As Co-Creator` `button_to` form token on a work edit
    /// or series page. Fails closed (`AO3Error.parse`) when the button is absent
    /// and the page is not recognised as the expected owner page.
    static func removeMeButtonState(
        in html: String,
        actionPath: String,
        isRecognizedOwnerPage: (Document) -> Bool
    ) throws -> (present: Bool, token: String?) {
        let doc = try SwiftSoup.parse(html)
        let forms = try doc.select("form[action*=/remove_user_creatorship]").array()
        if let match = forms.first(where: {
            AO3URLResolver.resolve((try? $0.attr("action")) ?? "")?.path == actionPath
        }) {
            return (true, formToken(in: match, fallbackHTML: html))
        }
        if isRecognizedOwnerPage(doc) { return (false, nil) }
        throw AO3Error.parse
    }

    // MARK: - 6. Import from URL (`works/new_import.html.erb`, `works#import`)

    /// Parses `GET /works/new?import=true` (otwarchive `452391b6`
    /// `app/views/works/new_import.html.erb`), reusing `parseSelect`,
    /// `parseCheckboxes`, and `parseRadios` from `AO3Client+Works`.
    static func parseImportForm(from html: String) throws -> AO3ImportForm {
        let doc = try SwiftSoup.parse(html)
        guard let form = try doc.select("form.import.work, form[action*=/works/import]").first(),
              let actionURL = AO3URLResolver.resolve(try form.attr("action"))
        else { throw AO3Error.parse }
        guard let csrf = formToken(in: form, fallbackHTML: html) else {
            throw AO3WorkWriteError.noCSRFToken
        }

        let language = parseSelect(form, name: "language_id")
        let encoding = parseSelect(form, name: "encoding")
        let rating = parseSelect(form, name: AO3WorkFormField.rating)
        let warnings = parseCheckboxes(form, name: AO3WorkFormField.warnings)
        let categories = parseCheckboxes(form, name: AO3WorkFormField.categories)
        let comments = parseRadios(form, name: "comment_permissions")
        return AO3ImportForm(
            actionURL: actionURL,
            csrfToken: csrf,
            languageOptions: language.options,
            selectedLanguageID: language.selected,
            encodingOptions: encoding.options,
            ratingOptions: rating.options,
            warningOptions: warnings.options,
            categoryOptions: categories.options,
            commentPermissionOptions: comments.options,
            defaultCommentPermissions: comments.selected.isEmpty ? "disable_anon" : comments.selected
        )
    }

    /// Classifies the response to `POST /works/import` (otwarchive `452391b6`
    /// `app/controllers/works_controller.rb:452-558`).
    static func parseImportResult(
        status: Int,
        body: String,
        finalURL: URL?
    ) throws -> AO3ImportResult {
        if let path = finalURL?.path, let workID = workIDFromPath(path) {
            return path.hasSuffix("/preview") ? .draft(workID) : .posted(workID)
        }
        // Fallback when a stub returns preview markup without updating finalURL.
        if let preview = try? parsePreviewHTML(from: body), let workID = preview.workID {
            return .draft(workID)
        }
        let failures = importFailuresSummary(in: body)
        if writingRequestNotice(in: body) != nil {
            let ids = importedWorkIDs(in: body)
            if !ids.isEmpty { return .several(ids, failures: failures) }
        }
        if let error = failures ?? writingRequestError(in: body, includeCaution: true) {
            return .failed(error)
        }
        if (200 ... 299).contains(status) || (500 ... 599).contains(status) {
            throw AO3WorkWriteError.unconfirmed
        }
        throw AO3WorkWriteError.rejected("AO3 couldn't import from those URLs.")
    }

    // MARK: - Private helpers

    private static func verifyAndExtractOrphanTargets(
        in doc: Document,
        form: Element,
        target: AO3OrphanTarget,
        cautions: [String]
    ) throws -> (titles: [String], workItems: [AO3OrphanCopyWork]) {
        switch target {
        case let .work(id):
            let hiddenIDs = try form.select("input[type=hidden][name='work_ids[]']").array()
                .compactMap { Int((try? $0.attr("value")) ?? "") }
            let items = abbreviatedWorkItems(in: doc)
            guard hiddenIDs == [id], items.count == 1, items[0].workID == id else {
                throw AO3Error.parse
            }
            return (items.map(\.title), items)
        case let .works(ids):
            guard !ids.isEmpty else { throw AO3Error.parse }
            let hiddenIDs = try form.select("input[type=hidden][name='work_ids[]']").array()
                .compactMap { Int((try? $0.attr("value")) ?? "") }
            let items = abbreviatedWorkItems(in: doc)
            let expected = Set(ids)
            guard Set(hiddenIDs) == expected, Set(items.map(\.workID)) == expected else {
                throw AO3Error.parse
            }
            return (items.map(\.title), items)
        case let .series(id):
            let hidden = (try? form.select("input[type=hidden][name=series_id]").first()?.attr("value")) ?? ""
            guard Int(hidden) == id, let title = cautions.compactMap(quotedOrphanTitle).first else {
                throw AO3Error.parse
            }
            return ([title], [])
        }
    }

    private static func abbreviatedWorkItems(in doc: Document) -> [AO3OrphanCopyWork] {
        var items: [AO3OrphanCopyWork] = []
        var seen = Set<Int>()
        for link in (try? doc.select("dl.work.index > dt > a:first-of-type").array()) ?? [] {
            guard let href = try? link.attr("href"),
                  let id = workIDFromPath(href),
                  seen.insert(id).inserted
            else { continue }
            let title = ((try? link.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            items.append(AO3OrphanCopyWork(workID: id, title: title))
        }
        return items
    }

    /// Reads AO3's `flash.now[:error]` on `works/import` (`works_controller.rb:546-550`),
    /// formatting `<dl><dt>url</dt><dd>err</dd></dl>` lines when present.
    private static func importFailuresSummary(in html: String) -> String? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        let flashes = ((try? doc.select(".flash.error, .flash.caution").array()) ?? [])
            .filter { !isInsideUserContent($0) }
        for flash in flashes {
            if let dl = try? flash.select("dl").first(),
               let formatted = formattedImportFailureList(in: dl) {
                return formatted
            }
            let text = ((try? flash.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return nil
    }

    private static func formattedImportFailureList(in list: Element) -> String? {
        let children = list.children().array()
        var lines: [String] = []
        var idx = 0
        while idx < children.count {
            let node = children[idx]
            idx += 1
            guard node.tagName().lowercased() == "dt" else { continue }
            let urlText = trimmedElementText(node)
            var reason = ""
            if idx < children.count, children[idx].tagName().lowercased() == "dd" {
                reason = trimmedElementText(children[idx])
                idx += 1
            }
            let parts = [urlText, reason].filter { !$0.isEmpty }
            if !parts.isEmpty { lines.append(parts.joined(separator: ": ")) }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func trimmedElementText(_ element: Element) -> String {
        ((try? element.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func quotedOrphanTitle(in text: String) -> String? {
        guard let first = text.firstIndex(of: "\""),
              let last = text.lastIndex(of: "\""),
              first < last
        else { return nil }
        let inner = text[text.index(after: first) ..< last].trimmingCharacters(in: .whitespacesAndNewlines)
        return inner.isEmpty ? nil : String(inner)
    }

    private static func importedWorkIDs(in html: String) -> [Int] {
        guard let doc = try? SwiftSoup.parse(html),
              let root = (try? doc.select("#main").first()) ?? doc.body()
        else { return [] }
        var seen = Set<Int>()
        var ids: [Int] = []
        for link in (try? root.select("a[href*=/works/]").array()) ?? [] {
            let skip = link.parents().array().contains {
                $0.hasClass("flash") || $0.hasClass("navigation") || $0.tagName() == "form"
            }
            guard !skip,
                  let href = try? link.attr("href"),
                  let id = workIDFromPath(href),
                  seen.insert(id).inserted
            else { continue }
            ids.append(id)
        }
        return ids
    }
}
