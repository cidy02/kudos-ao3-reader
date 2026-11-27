import Foundation
import SwiftSoup

// MARK: - Chapter editor posting route (`Studio-Post-Chapter` vs `Studio-Post-New-Work`)

/// Active posting sheet presented from `ChapterEditorScreen`'s `•••` menu.
nonisolated enum StudioEditorPostSheet: Identifiable, Hashable, Sendable {
    case postChapter(workID: Int, chapterID: Int?)
    case postNewWork(existingDraftWorkID: Int?)

    var id: String {
        switch self {
        case let .postChapter(workID, chapterID):
            "post-chapter-\(workID)-\(chapterID ?? -1)"
        case let .postNewWork(draftID):
            "post-new-work-\(draftID ?? -1)"
        }
    }
}

/// Pure routing decision for `ChapterEditorScreen`'s `••• → Post` / `Update on AO3`.
nonisolated enum StudioEditorPostRoute: Equatable, Hashable, Sendable {
    /// Already posted chapter: runs the existing Update on AO3 callback.
    case updatePosted
    /// Unposted chapter belonging to a posted AO3 work (`Studio-Post-Chapter`).
    case postChapter(workID: Int, chapterID: Int?)
    /// Chapter of a work that isn't posted on AO3 yet (`Studio-Post-New-Work`).
    case postNewWork(existingDraftWorkID: Int?)
    /// Fallback to the host's callback when no signed-in Studio sheet applies.
    case fallbackCallback
    /// Signed out with no AO3 host actions.
    case unavailable
}

nonisolated enum StudioEditorPostRouting {
    static func route(
        isPosted: Bool,
        ao3WorkID: Int?,
        ao3ChapterID: Int?,
        isUnpostedWorkDraft: Bool,
        hasPostCallback: Bool,
        isSignedIn: Bool
    ) -> StudioEditorPostRoute {
        if isPosted {
            return hasPostCallback ? .updatePosted : .unavailable
        }
        guard isSignedIn else {
            return hasPostCallback ? .fallbackCallback : .unavailable
        }
        if isUnpostedWorkDraft {
            return .postNewWork(existingDraftWorkID: ao3WorkID)
        }
        if let ao3WorkID {
            return .postChapter(workID: ao3WorkID, chapterID: ao3ChapterID)
        }
        return .postNewWork(existingDraftWorkID: nil)
    }
}

// MARK: - On-device pre-post checks (`Studio-Post-Chapter`)

nonisolated enum StudioPostCheckID: String, CaseIterable, Identifiable, Hashable, Sendable {
    case workDetails
    case textReady
    case chapterCount
    case comments

    var id: String { rawValue }
}

nonisolated enum StudioPostCheckStatus: String, Equatable, Hashable, Sendable {
    case pass
    case warning
    case fail
}

nonisolated struct StudioPostCheckItem: Identifiable, Equatable, Hashable, Sendable {
    let id: StudioPostCheckID
    let status: StudioPostCheckStatus
    let title: String
    let detail: String
    let actionTitle: String?

    init(
        id: StudioPostCheckID,
        status: StudioPostCheckStatus,
        title: String,
        detail: String,
        actionTitle: String? = nil
    ) {
        self.id = id
        self.status = status
        self.title = title
        self.detail = detail
        self.actionTitle = actionTitle
    }
}

/// On-device inspection of chapter HTML before anything is sent to AO3.
nonisolated struct StudioPostHTMLInspection: Equatable, Sendable {
    var wordCount: Int
    var characterCount: Int
    var italicsCount: Int
    var boldCount: Int
    var sceneBreakCount: Int
    var linkCount: Int
    var quoteCount: Int
    var listCount: Int
    var headingCount: Int
    var foldOutCount: Int
    var imageCount: Int
    var strippedElements: [String]
    var hasInlineStyles: Bool
    var hasUnsafeLinks: Bool
    var isEffectivelyEmpty: Bool

    /// Elements AO3's `Sanitize::Config::ARCHIVE` strips outright.
    private static let disallowedElements: Set<String> = [
        "script", "style", "iframe", "object", "embed", "form", "input",
        "button", "textarea", "select", "font", "meta", "link"
    ]

    private struct Counters {
        var italics = 0
        var bold = 0
        var sceneBreaks = 0
        var links = 0
        var quotes = 0
        var lists = 0
        var headings = 0
        var foldOuts = 0
        var images = 0
        var stripped: Set<String> = []
        var hasInlineStyles = false
        var hasUnsafeLinks = false
    }

    static func inspect(_ html: String) -> StudioPostHTMLInspection {
        let characterCount = html.unicodeScalars.count
        let wordCount = AO3WordCounter.count(html)
        let trimmedRaw = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRaw.isEmpty else {
            return StudioPostHTMLInspection(
                wordCount: 0,
                characterCount: characterCount,
                italicsCount: 0,
                boldCount: 0,
                sceneBreakCount: 0,
                linkCount: 0,
                quoteCount: 0,
                listCount: 0,
                headingCount: 0,
                foldOutCount: 0,
                imageCount: 0,
                strippedElements: [],
                hasInlineStyles: false,
                hasUnsafeLinks: false,
                isEffectivelyEmpty: true
            )
        }

        var counters = Counters()
        var visibleText = ""

        if let doc = try? SwiftSoup.parseBodyFragment(html), let body = doc.body() {
            visibleText = ((try? body.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            for element in (try? body.getAllElements().array()) ?? [] {
                classifyElement(element, into: &counters)
            }
        } else {
            visibleText = trimmedRaw
        }

        let isEffectivelyEmpty = visibleText.isEmpty && counters.images == 0 && counters.sceneBreaks == 0
        return StudioPostHTMLInspection(
            wordCount: wordCount,
            characterCount: characterCount,
            italicsCount: counters.italics,
            boldCount: counters.bold,
            sceneBreakCount: counters.sceneBreaks,
            linkCount: counters.links,
            quoteCount: counters.quotes,
            listCount: counters.lists,
            headingCount: counters.headings,
            foldOutCount: counters.foldOuts,
            imageCount: counters.images,
            strippedElements: counters.stripped.sorted(),
            hasInlineStyles: counters.hasInlineStyles,
            hasUnsafeLinks: counters.hasUnsafeLinks,
            isEffectivelyEmpty: isEffectivelyEmpty
        )
    }

    private static func classifyElement(_ element: Element, into counters: inout Counters) {
        let tag = element.tagName().lowercased()
        guard tag != "body", tag != "#root" else { return }

        if disallowedElements.contains(tag) {
            counters.stripped.insert(tag)
        }
        if element.hasAttr("style") {
            let styleValue = ((try? element.attr("style")) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !styleValue.isEmpty {
                counters.hasInlineStyles = true
            }
        }

        switch tag {
        case "em", "i": counters.italics += 1
        case "strong", "b": counters.bold += 1
        case "hr": counters.sceneBreaks += 1
        case "a": classifyLink(element, into: &counters)
        case "blockquote": counters.quotes += 1
        case "ul", "ol": counters.lists += 1
        case "h1", "h2", "h3", "h4", "h5", "h6": counters.headings += 1
        case "details": counters.foldOuts += 1
        case "img": counters.images += 1
        default: break
        }
    }

    private static func classifyLink(_ element: Element, into counters: inout Counters) {
        let href = ((try? element.attr("href")) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !href.isEmpty else { return }
        if href.hasPrefix("#") || AO3Markup.safeLink(href) {
            counters.links += 1
        } else {
            counters.hasUnsafeLinks = true
        }
    }

    /// Plain-English summary of formatting that converts cleanly to AO3's HTML
    /// (e.g. `"Italics, 2 scene breaks and 1 link convert cleanly to AO3's HTML"`).
    var cleanConversionDetail: String {
        var parts: [String] = []
        if italicsCount > 0 { parts.append("italics") }
        if boldCount > 0 { parts.append("bold") }
        if sceneBreakCount > 0 {
            parts.append(sceneBreakCount == 1 ? "1 scene break" : "\(sceneBreakCount) scene breaks")
        }
        if linkCount > 0 {
            parts.append(linkCount == 1 ? "1 link" : "\(linkCount) links")
        }
        if quoteCount > 0 {
            parts.append(quoteCount == 1 ? "1 quote" : "\(quoteCount) quotes")
        }
        if listCount > 0 {
            parts.append(listCount == 1 ? "1 list" : "\(listCount) lists")
        }
        if headingCount > 0 {
            parts.append(headingCount == 1 ? "1 heading" : "\(headingCount) headings")
        }
        if foldOutCount > 0 {
            parts.append(foldOutCount == 1 ? "1 fold-out section" : "\(foldOutCount) fold-out sections")
        }
        if imageCount > 0 {
            parts.append(imageCount == 1 ? "1 image" : "\(imageCount) images")
        }
        guard !parts.isEmpty else {
            return "Plain paragraphs convert cleanly to AO3's HTML"
        }
        let joined = Self.joinNaturalList(parts)
        let capitalized = joined.prefix(1).uppercased() + joined.dropFirst()
        let verb = parts.count == 1 && Self.isSingularPhrase(parts[0]) ? "converts" : "convert"
        return "\(capitalized) \(verb) cleanly to AO3's HTML"
    }

    private static func isSingularPhrase(_ phrase: String) -> Bool {
        phrase == "bold" || phrase.hasPrefix("1 ")
    }

    static func joinNaturalList(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default:
            let head = items.dropLast().joined(separator: ", ")
            return "\(head) and \(items[items.count - 1])"
        }
    }
}

/// Pure, testable evaluator for the 4 on-device checks on `Studio-Post-Chapter`.
nonisolated enum StudioPostChapterChecker {
    /// AO3's chapter content limit (`otwarchive` `CONTENT_MAX = 510000`).
    static let maxChapterCharacters = 510_000

    static func positiveInt(_ raw: String) -> Int? {
        Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0 > 0 ? $0 : nil }
    }

    static func resolvedChapterPosition(
        chapterForm: AO3ChapterForm,
        workForm: AO3WorkForm?
    ) -> Int {
        if let explicit = positiveInt(chapterForm.position) {
            return explicit
        }
        if let posted = workForm?.chaptersPosted, posted >= 0 {
            return chapterForm.chapterID == nil ? posted + 1 : max(1, posted)
        }
        return 1
    }

    static func resolvedPlannedTotal(
        chapterForm: AO3ChapterForm,
        workForm: AO3WorkForm?
    ) -> Int? {
        let chapterTotalRaw = chapterForm.wipLength.trimmingCharacters(in: .whitespacesAndNewlines)
        if !chapterTotalRaw.isEmpty {
            return positiveInt(chapterTotalRaw)
        }
        guard let workTotalRaw = workForm?.chapterTotal.trimmingCharacters(in: .whitespacesAndNewlines),
              !workTotalRaw.isEmpty
        else { return nil }
        return positiveInt(workTotalRaw)
    }

    static func chapterMetaLine(
        wordCount: Int,
        position: Int,
        plannedTotal: Int?
    ) -> String {
        let wordsText = wordCount == 1 ? "1 word" : "\(wordCount.formatted()) words"
        let totalText = plannedTotal.map(String.init) ?? "?"
        return "\(wordsText) · becomes \(position) of \(totalText) on AO3"
    }

    static func checks(
        chapterForm: AO3ChapterForm,
        workForm: AO3WorkForm?,
        openTKCount: Int = 0,
        openNoteCount: Int = 0
    ) -> [StudioPostCheckItem] {
        [
            workDetailsCheck(workForm: workForm),
            textReadyCheck(
                chapterForm: chapterForm,
                openTKCount: openTKCount,
                openNoteCount: openNoteCount
            ),
            chapterCountCheck(chapterForm: chapterForm, workForm: workForm),
            commentsCheck(workForm: workForm)
        ]
    }

    static func canPost(checks: [StudioPostCheckItem]) -> Bool {
        !checks.contains { $0.status == .fail }
    }

    // MARK: Individual checks

    private static func workDetailsCheck(workForm: AO3WorkForm?) -> StudioPostCheckItem {
        guard let workForm else {
            return StudioPostCheckItem(
                id: .workDetails,
                status: .warning,
                title: "Work details carry over",
                detail: "Couldn't load the work's details from AO3. Existing details will carry over.",
                actionTitle: "Edit"
            )
        }
        var missing: [String] = []
        if workForm.rating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("rating")
        }
        if workForm.warnings.isEmpty {
            missing.append("archive warnings")
        }
        if workForm.fandoms.isEmpty {
            missing.append("fandom")
        }
        if !missing.isEmpty {
            let list = StudioPostHTMLInspection.joinNaturalList(missing)
            return StudioPostCheckItem(
                id: .workDetails,
                status: .fail,
                title: "Work details need attention",
                detail: "Missing \(list) on this work. Edit work details before posting.",
                actionTitle: "Edit"
            )
        }
        return StudioPostCheckItem(
            id: .workDetails,
            status: .pass,
            title: "Work details carry over",
            detail: workDetailsSummary(for: workForm),
            actionTitle: "Edit"
        )
    }

    static func workDetailsSummary(for workForm: AO3WorkForm) -> String {
        var parts: [String] = []
        let rating = workForm.rating.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rating.isEmpty {
            parts.append("Rating \(rating)")
        }
        if let firstWarning = workForm.warnings.first {
            if workForm.warnings.count == 1 {
                parts.append(firstWarning)
            } else {
                parts.append("\(firstWarning) +\(workForm.warnings.count - 1)")
            }
        }
        if let firstFandom = workForm.fandoms.first {
            if workForm.fandoms.count == 1 {
                parts.append(firstFandom)
            } else {
                parts.append("\(firstFandom) +\(workForm.fandoms.count - 1)")
            }
        }
        let extraTagCount = workForm.categories.count
            + workForm.relationships.count
            + workForm.characters.count
            + workForm.additionalTags.count
        if extraTagCount > 0 {
            parts.append(extraTagCount == 1 ? "1 tag" : "\(extraTagCount) tags")
        }
        parts.append(workForm.restricted ? "registered users only" : "everyone can see it")
        return parts.joined(separator: " · ")
    }

    private static func textReadyCheck(
        chapterForm: AO3ChapterForm,
        openTKCount: Int,
        openNoteCount: Int
    ) -> StudioPostCheckItem {
        let inspection = StudioPostHTMLInspection.inspect(chapterForm.content)

        if let failure = textLengthFailure(chapterForm: chapterForm, inspection: inspection) {
            return failure
        }

        var warnings: [String] = []
        if openTKCount > 0 {
            let label = openTKCount == 1 ? "1 TK marker" : "\(openTKCount) TK markers"
            warnings.append("\(label) still open")
        }
        if !inspection.strippedElements.isEmpty {
            let tags = inspection.strippedElements.map { "<\($0)>" }.joined(separator: ", ")
            warnings.append("AO3 removes \(tags)")
        }
        if inspection.hasInlineStyles {
            warnings.append("AO3 removes inline styles")
        }
        if inspection.hasUnsafeLinks {
            warnings.append("links without http/https/mailto will be stripped")
        }

        if !warnings.isEmpty {
            let title = openTKCount > 0 ? "Check before posting" : "Some formatting won't carry over"
            return StudioPostCheckItem(
                id: .textReady,
                status: .warning,
                title: title,
                detail: warnings.joined(separator: " · ")
            )
        }

        var detail = inspection.cleanConversionDetail
        if openNoteCount > 0 {
            let label = openNoteCount == 1 ? "1 private note stays" : "\(openNoteCount) private notes stay"
            detail += " · \(label) on this device"
        }
        return StudioPostCheckItem(
            id: .textReady,
            status: .pass,
            title: "Text is ready for AO3",
            detail: detail
        )
    }

    private static func textLengthFailure(
        chapterForm: AO3ChapterForm,
        inspection: StudioPostHTMLInspection
    ) -> StudioPostCheckItem? {
        if inspection.isEffectivelyEmpty {
            return StudioPostCheckItem(
                id: .textReady,
                status: .fail,
                title: "Chapter text is empty",
                detail: "Add chapter text before posting to AO3."
            )
        }
        if inspection.characterCount > maxChapterCharacters {
            return StudioPostCheckItem(
                id: .textReady,
                status: .fail,
                title: "Chapter text is too long for AO3",
                detail: "\(inspection.characterCount.formatted()) characters — AO3 accepts up to "
                    + "\(maxChapterCharacters.formatted())."
            )
        }
        let summaryStatus = CharacterLimitStatus.evaluate(text: chapterForm.summary, field: .summary)
        if summaryStatus.severity == .exceeded {
            return StudioPostCheckItem(
                id: .textReady,
                status: .fail,
                title: "Chapter summary is too long",
                detail: summaryStatus.overLimitMessage ?? "Chapter summary exceeds AO3's limit."
            )
        }
        let beginStatus = CharacterLimitStatus.evaluate(text: chapterForm.notes, field: .notes)
        if beginStatus.severity == .exceeded {
            return StudioPostCheckItem(
                id: .textReady,
                status: .fail,
                title: "Beginning notes are too long",
                detail: beginStatus.overLimitMessage ?? "Beginning notes exceed AO3's limit."
            )
        }
        let endStatus = CharacterLimitStatus.evaluate(text: chapterForm.endnotes, field: .notes)
        if endStatus.severity == .exceeded {
            return StudioPostCheckItem(
                id: .textReady,
                status: .fail,
                title: "End notes are too long",
                detail: endStatus.overLimitMessage ?? "End notes exceed AO3's limit."
            )
        }
        return nil
    }

    private static func chapterCountCheck(
        chapterForm: AO3ChapterForm,
        workForm: AO3WorkForm?
    ) -> StudioPostCheckItem {
        let position = resolvedChapterPosition(chapterForm: chapterForm, workForm: workForm)
        let rawTotal = chapterForm.wipLength.trimmingCharacters(in: .whitespacesAndNewlines)

        if !rawTotal.isEmpty, rawTotal != "?", positiveInt(rawTotal) == nil {
            return StudioPostCheckItem(
                id: .chapterCount,
                status: .fail,
                title: "Chapter count",
                detail: "Enter a whole number for the planned chapter total, or leave it blank for ?.",
                actionTitle: "Change"
            )
        }

        let planned = resolvedPlannedTotal(chapterForm: chapterForm, workForm: workForm)
        if let planned {
            if planned < position {
                return StudioPostCheckItem(
                    id: .chapterCount,
                    status: .fail,
                    title: "Chapter count",
                    detail: "Chapter \(position) is past the planned total of \(planned). "
                        + "Update the total before posting.",
                    actionTitle: "Change"
                )
            }
            if planned == position {
                return StudioPostCheckItem(
                    id: .chapterCount,
                    status: .warning,
                    title: "Chapter count",
                    detail: "Marks the work complete at \(position) of \(planned). "
                        + "Change it here if more chapters are coming.",
                    actionTitle: "Change"
                )
            }
            return StudioPostCheckItem(
                id: .chapterCount,
                status: .warning,
                title: "Chapter count",
                detail: "Still \(planned) planned? Change it here if the story grew",
                actionTitle: "Change"
            )
        }

        return StudioPostCheckItem(
            id: .chapterCount,
            status: .pass,
            title: "Chapter count",
            detail: "Becomes \(position) of ? on AO3 · work stays in progress",
            actionTitle: "Change"
        )
    }

    private static func commentsCheck(workForm: AO3WorkForm?) -> StudioPostCheckItem {
        guard let workForm else {
            return StudioPostCheckItem(
                id: .comments,
                status: .warning,
                title: "Comments",
                detail: "Comment settings carry over from your work on AO3."
            )
        }
        let summary = commentSummary(
            permissions: workForm.commentPermissions,
            options: workForm.commentPermissionOptions,
            moderated: workForm.moderatedCommenting
        )
        return StudioPostCheckItem(
            id: .comments,
            status: .pass,
            title: "Comments",
            detail: summary
        )
    }

    static func commentSummary(
        permissions: String,
        options: [AO3FormOption],
        moderated: Bool
    ) -> String {
        let who: String
        switch permissions {
        case "enable_all":
            who = "Everyone can comment"
        case "disable_anon":
            who = "Registered users can comment"
        case "disable_all":
            who = "Comments are turned off"
        default:
            if let option = options.first(where: { $0.value == permissions }), !option.title.isEmpty {
                who = option.title
            } else {
                who = "Registered users can comment"
            }
        }
        let mod = moderated ? "moderation on" : "moderation off"
        return "\(who) · \(mod)"
    }
}
