import Foundation

// MARK: - New work required fields & template (`Studio-Post-New-Work`)

nonisolated enum StudioNewWorkRequiredFieldKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case title
    case rating
    case warnings
    case fandom
    case language
    case text

    var id: String { rawValue }

    var label: String {
        switch self {
        case .title: "Title"
        case .rating: "Rating"
        case .warnings: "Warnings"
        case .fandom: "Fandom"
        case .language: "Language"
        case .text: "Text"
        }
    }

    var missingPlaceholder: String {
        switch self {
        case .title: "Add a title"
        case .rating: "Choose a rating"
        case .warnings: "Choose at least one"
        case .fandom: "Add at least one"
        case .language: "Choose a language"
        case .text: "Add text"
        }
    }

    /// Phrase inserted into `"Post — <phrase> first"` when this is the sole missing required field.
    var postButtonPhrase: String {
        switch self {
        case .title: "add a Title"
        case .rating: "choose a Rating"
        case .warnings: "choose Archive Warnings"
        case .fandom: "add a Fandom"
        case .language: "choose a Language"
        case .text: "add the Text"
        }
    }
}

nonisolated struct StudioNewWorkRequiredItem: Identifiable, Equatable, Hashable, Sendable {
    let kind: StudioNewWorkRequiredFieldKind
    let value: String
    let isComplete: Bool
    /// Replaces `kind.postButtonPhrase` when the field is filled but AO3 will still reject it.
    var buttonPhrase: String? = nil

    var id: StudioNewWorkRequiredFieldKind { kind }
    var label: String { kind.label }
}

/// Evaluates AO3's 6 required work fields (`works/_standard_form`) for `Studio-Post-New-Work`.
nonisolated struct StudioNewWorkRequirements: Equatable, Sendable {
    let items: [StudioNewWorkRequiredItem]
    /// Phrase for `"Post — <phrase> first"` when every required field is filled
    /// but a length limit AO3 enforces (`TITLE_MAX`, `SUMMARY_MAX`, `NOTES_MAX`) still fails.
    let rejectionReason: String?

    var missingItems: [StudioNewWorkRequiredItem] {
        items.filter { !$0.isComplete }
    }

    var remainingCount: Int { missingItems.count }
    var canPost: Bool { missingItems.isEmpty && rejectionReason == nil }

    var remainingBadgeText: String? {
        remainingCount > 0 ? "\(remainingCount) left" : nil
    }

    var postButtonTitle: String {
        let missing = missingItems
        if missing.isEmpty {
            if let rejectionReason {
                return "Post — \(rejectionReason) first"
            }
            return "Post"
        }
        if missing.count == 1, let only = missing.first {
            let phrase = only.buttonPhrase ?? only.kind.postButtonPhrase
            return "Post — \(phrase) first"
        }
        return "Post — \(missing.count) required fields left"
    }

    /// Why a post must be refused after `missingRequiredFields()` came back empty.
    /// Nil when the block is an ordinary missing field (the flow names those itself).
    var lengthRefusal: String? {
        if missingItems.isEmpty {
            return rejectionReason
        }
        guard missingItems.count == 1, let only = missingItems.first, let phrase = only.buttonPhrase else {
            return nil
        }
        return phrase
    }

    static func evaluate(_ form: AO3WorkForm) -> StudioNewWorkRequirements {
        let trimmedTitle = form.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleTooLong = !trimmedTitle.isEmpty
            && form.title.unicodeScalars.count > StudioPostChapterChecker.maxTitleCharacters
        let titleValue: String
        if trimmedTitle.isEmpty {
            titleValue = StudioNewWorkRequiredFieldKind.title.missingPlaceholder
        } else if titleTooLong {
            titleValue = "AO3 accepts up to \(StudioPostChapterChecker.maxTitleCharacters) characters"
        } else {
            titleValue = trimmedTitle
        }
        let titleItem = StudioNewWorkRequiredItem(
            kind: .title,
            value: titleValue,
            isComplete: !trimmedTitle.isEmpty && !titleTooLong,
            buttonPhrase: titleTooLong ? "shorten the Title" : nil
        )

        let trimmedRating = form.rating.trimmingCharacters(in: .whitespacesAndNewlines)
        let ratingTitle = form.ratingOptions.first { $0.value == trimmedRating }?.title ?? trimmedRating
        let ratingItem = StudioNewWorkRequiredItem(
            kind: .rating,
            value: trimmedRating.isEmpty ? StudioNewWorkRequiredFieldKind.rating.missingPlaceholder : ratingTitle,
            isComplete: !trimmedRating.isEmpty
        )

        let warningTitles = form.warnings.map { raw in
            form.warningOptions.first { $0.value == raw }?.title ?? raw
        }
        let warningsItem = StudioNewWorkRequiredItem(
            kind: .warnings,
            value: warningTitles.isEmpty
                ? StudioNewWorkRequiredFieldKind.warnings.missingPlaceholder
                : warningTitles.joined(separator: ", "),
            isComplete: !form.warnings.isEmpty
        )

        let fandomsClean = form.fandoms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let fandomItem = StudioNewWorkRequiredItem(
            kind: .fandom,
            value: fandomsClean.isEmpty
                ? StudioNewWorkRequiredFieldKind.fandom.missingPlaceholder
                : fandomsClean.joined(separator: ", "),
            isComplete: !fandomsClean.isEmpty
        )

        let trimmedLanguageID = form.languageID.trimmingCharacters(in: .whitespacesAndNewlines)
        let languageTitle = form.languageOptions.first { $0.value == trimmedLanguageID }?.title
            ?? trimmedLanguageID
        let languageItem = StudioNewWorkRequiredItem(
            kind: .language,
            value: trimmedLanguageID.isEmpty
                ? StudioNewWorkRequiredFieldKind.language.missingPlaceholder
                : languageTitle,
            isComplete: !trimmedLanguageID.isEmpty
        )

        let contentText = form.chapter?.content ?? ""
        let requiresContent = (form.kind == .new || form.isDraft) && (form.chapter?.contentServed != false)
        let hasContent = !contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let contentCount = contentText.unicodeScalars.count
        let textTooShort = hasContent && contentCount < StudioPostChapterChecker.minChapterCharacters
        let textTooLong = hasContent && contentCount > StudioPostChapterChecker.maxChapterCharacters
        let textValue: String
        let textPhrase: String?
        let textComplete: Bool
        if !requiresContent {
            textValue = "Multi-chapter draft on AO3"
            textPhrase = nil
            textComplete = true
        } else if !hasContent {
            textValue = StudioNewWorkRequiredFieldKind.text.missingPlaceholder
            textPhrase = nil
            textComplete = false
        } else if textTooShort {
            textValue = "AO3 needs at least \(StudioPostChapterChecker.minChapterCharacters) characters"
            textPhrase = "lengthen the Text"
            textComplete = false
        } else if textTooLong {
            textValue = "Too long for AO3"
            textPhrase = "shorten the Text"
            textComplete = false
        } else {
            let words = AO3WordCounter.count(contentText)
            let wordLabel = words == 1 ? "1 word" : "\(words.formatted()) words"
            textValue = "\(wordLabel) from your document"
            textPhrase = nil
            textComplete = true
        }
        let textItem = StudioNewWorkRequiredItem(
            kind: .text,
            value: textValue,
            isComplete: textComplete,
            buttonPhrase: textPhrase
        )

        return StudioNewWorkRequirements(
            items: [
                titleItem,
                ratingItem,
                warningsItem,
                fandomItem,
                languageItem,
                textItem
            ],
            rejectionReason: lengthRejection(for: form)
        )
    }

    /// Limits AO3 enforces on fields that are not in the six required blanks.
    /// Hidden chapter text (`contentServed == false`) is not counted: it is not sent.
    private static func lengthRejection(for form: AO3WorkForm) -> String? {
        let summaryLimit = AO3ChapterFieldLimit.summary.characterLimit
        let notesLimit = AO3ChapterFieldLimit.notes.characterLimit
        if form.summary.unicodeScalars.count > summaryLimit {
            return "shorten the Summary"
        }
        if form.notes.unicodeScalars.count > notesLimit || form.endnotes.unicodeScalars.count > notesLimit {
            return "shorten the Notes"
        }
        if let chapter = form.chapter {
            if chapter.title.unicodeScalars.count > StudioPostChapterChecker.maxTitleCharacters {
                return "shorten the Chapter Title"
            }
            if chapter.summary.unicodeScalars.count > summaryLimit {
                return "shorten the Summary"
            }
        }
        return nil
    }
}

/// Optional starter details copied onto a fresh `AO3WorkForm` when posting a new work.
nonisolated struct StudioPostWorkTemplate: Equatable, Sendable {
    var sourceTitle: String
    var rating: String
    var warnings: [String]
    var fandoms: [String]
    var languageID: String
    var restricted: Bool

    func applying(to form: AO3WorkForm) -> (form: AO3WorkForm, copiedLabels: [String]) {
        var copy = form
        var copied: [String] = []
        if copy.rating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !rating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            copy.rating = rating
            copied.append("rating")
        }
        if copy.warnings.isEmpty, !warnings.isEmpty {
            copy.warnings = warnings
            copied.append("warnings")
        }
        if copy.fandoms.isEmpty, !fandoms.isEmpty {
            copy.fandoms = fandoms
            copied.append("fandom")
        }
        if copy.languageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !languageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            copy.languageID = languageID
            copied.append("language")
        }
        if restricted && !copy.restricted {
            copy.restricted = true
            copied.append("privacy")
        }
        return (copy, copied)
    }

    static func bannerText(sourceTitle: String, copiedLabels: [String]) -> String {
        let title = sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? "your work" : title
        if copiedLabels.isEmpty {
            return "Started from \(displayTitle) — your details are filled in. Change anything."
        }
        let joined = StudioPostHTMLInspection.joinNaturalList(copiedLabels)
        return "Started from \(displayTitle) — \(joined) copied. Change anything."
    }

    static func overlayChapterDraft(
        workTitle: String,
        chapterTitle: String,
        summary: String,
        notesBefore: String,
        notesAfter: String,
        content: String,
        onto form: AO3WorkForm
    ) -> AO3WorkForm {
        var updated = form
        if updated.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !workTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.title = workTitle
        }
        if !summary.isEmpty { updated.summary = summary }
        if !notesBefore.isEmpty { updated.notes = notesBefore }
        if !notesAfter.isEmpty { updated.endnotes = notesAfter }
        var chapter = updated.chapter ?? AO3WorkChapterDraft()
        if !chapterTitle.isEmpty { chapter.title = chapterTitle }
        if chapter.contentServed, !content.isEmpty {
            chapter.content = content
        }
        updated.chapter = chapter
        return updated
    }

    static func overlayChapterDraft(
        chapterTitle: String,
        summary: String,
        notesBefore: String,
        notesAfter: String,
        content: String,
        onto form: AO3ChapterForm
    ) -> AO3ChapterForm {
        var updated = form
        if !chapterTitle.isEmpty { updated.title = chapterTitle }
        if !summary.isEmpty { updated.summary = summary }
        if !notesBefore.isEmpty { updated.notes = notesBefore }
        if !notesAfter.isEmpty { updated.endnotes = notesAfter }
        if !content.isEmpty { updated.content = content }
        return updated
    }
}

// MARK: - Pure submission coordinators (reusing existing AO3WorkActions)

/// Pure submission flow for `StudioPostChapterSheet`.
/// Reuses `AO3AuthService.createChapter`, `updateChapter`, and `updateWorkTotals`
/// with the same session-generation fence and sequential total update as `AddChapterView`.
@MainActor
enum StudioPostChapterSubmissionFlow {
    enum Action: Equatable, Sendable {
        case post
        case saveDraft
    }

    enum Outcome: Equatable, Sendable {
        case succeeded(notice: String, isDraft: Bool)
        case savedChapterButTotalFailed(String)
        case blockedByChecks(String)
        case sessionChanged
        case mayHaveGoneThrough(String)
        case failed(String)
    }

    static let mayHaveGoneThroughMessage =
        "This may have gone through on AO3. Check your work on AO3 before trying again."

    static func submitAction(for action: Action, chapterID: Int?) -> AO3WorkSubmitAction {
        switch action {
        case .saveDraft:
            return .saveDraft
        case .post:
            return chapterID == nil ? .postWithoutPreview : .post
        }
    }

    static func run(
        action: Action,
        chapterForm: AO3ChapterForm,
        workForm: AO3WorkForm?,
        checks: [StudioPostCheckItem],
        newWorkTotal: Int?,
        expectedGeneration: Int,
        currentGeneration: @MainActor () -> Int,
        now: Date? = nil,
        createChapter: @MainActor (AO3ChapterForm, AO3WorkSubmitAction) async throws -> String,
        updateChapter: @MainActor (AO3ChapterForm, AO3WorkSubmitAction) async throws -> String,
        updateWorkTotals: @MainActor (Int, Int) async throws -> String
    ) async -> Outcome {
        if action == .post, let blocking = checks.first(where: { $0.status == .fail }) {
            return .blockedByChecks(blocking.detail)
        }
        guard expectedGeneration == currentGeneration() else {
            return .sessionChanged
        }

        // The row says "Today" when the year is blank. An update that omits
        // published_at keeps AO3's old date, so send the date the row shows.
        let formToSend = formShowingPublicationDate(chapterForm, now: now ?? Date())
        let submit = submitAction(for: action, chapterID: formToSend.chapterID)
        let notice: String
        do {
            if formToSend.chapterID == nil {
                notice = try await createChapter(formToSend, submit)
            } else {
                notice = try await updateChapter(formToSend, submit)
            }
        } catch {
            if AO3WriteOutcomeClassifier.mayHaveGoneThrough(error) {
                return .mayHaveGoneThrough(mayHaveGoneThroughMessage)
            }
            return .failed(UserFacingError.message(for: error))
        }

        if let newWorkTotal,
           shouldUpdateWorkTotal(newTotal: newWorkTotal, existingWorkTotal: workForm?.chapterTotal) {
            guard expectedGeneration == currentGeneration() else {
                return .savedChapterButTotalFailed(
                    "The chapter was saved, but your AO3 session changed before the work total could be updated."
                )
            }
            do {
                _ = try await updateWorkTotals(formToSend.workID, newWorkTotal)
            } catch {
                return .savedChapterButTotalFailed(
                    "The chapter was saved, but the work total was not updated. "
                        + UserFacingError.message(for: error)
                )
            }
        }

        return .succeeded(notice: notice, isDraft: action == .saveDraft)
    }

    static func formShowingPublicationDate(_ form: AO3ChapterForm, now: Date) -> AO3ChapterForm {
        guard form.publishedYear.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return form
        }
        var copy = form
        let fields = AO3PublicationDate.fields(for: now)
        copy.publishedYear = fields.year
        copy.publishedMonth = fields.month
        copy.publishedDay = fields.day
        return copy
    }

    static func shouldUpdateWorkTotal(newTotal: Int?, existingWorkTotal: String?) -> Bool {
        guard let newTotal, newTotal > 0 else { return false }
        let existing = existingWorkTotal.flatMap(StudioPostChapterChecker.positiveInt)
        return existing != newTotal
    }
}

/// Pure submission flow for `StudioPostNewWorkSheet`.
/// Reuses `AO3AuthService.saveWork` (`AO3WorkSubmitAction.post` / `.saveDraft`).
@MainActor
enum StudioPostNewWorkSubmissionFlow {
    enum Action: Equatable, Sendable {
        case post
        case saveDraft
    }

    enum Outcome: Equatable, Sendable {
        case succeeded(notice: String, isDraft: Bool)
        case missingRequired([String])
        case sessionChanged
        case mayHaveGoneThrough(String)
        case failed(String)
    }

    static let mayHaveGoneThroughMessage =
        "This may have gone through on AO3. Check your works and drafts on AO3 before trying again."

    static func run(
        action: Action,
        form: AO3WorkForm,
        expectedGeneration: Int,
        currentGeneration: @MainActor () -> Int,
        saveWork: @MainActor (AO3WorkForm, AO3WorkSubmitAction) async throws -> String
    ) async -> Outcome {
        if action == .post {
            var missing = form.missingRequiredFields()
            if (form.kind == .new || form.isDraft), form.chapter == nil, !missing.contains("Work Text") {
                missing.append("Work Text")
            }
            if !missing.isEmpty {
                return .missingRequired(missing)
            }
            let requirements = StudioNewWorkRequirements.evaluate(form)
            if !requirements.canPost {
                if let refusal = requirements.lengthRefusal {
                    return .missingRequired([refusal])
                }
                return .missingRequired(requirements.missingItems.map(\.label))
            }
        }
        guard expectedGeneration == currentGeneration() else {
            return .sessionChanged
        }
        // AO3's work form posts only on `post_button` (same as `WorkEditView.postSubmit`).
        let submit: AO3WorkSubmitAction = action == .post ? .post : .saveDraft
        do {
            let notice = try await saveWork(form, submit)
            return .succeeded(notice: notice, isDraft: action == .saveDraft)
        } catch {
            if AO3WriteOutcomeClassifier.mayHaveGoneThrough(error) {
                return .mayHaveGoneThrough(mayHaveGoneThroughMessage)
            }
            return .failed(UserFacingError.message(for: error))
        }
    }
}
