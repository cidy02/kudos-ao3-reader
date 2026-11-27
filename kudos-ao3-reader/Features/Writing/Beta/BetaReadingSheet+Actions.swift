import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Testable beta review actions (import, accept, accept-all)

@MainActor
enum BetaReviewActions {
    enum AcceptOutcome: Equatable {
        case applied
        case skippedManualPaste
        case unplaceable
        case abortedSnapshot
    }

    struct AcceptAllResult: Equatable {
        var appliedCount = 0
        var unplaceableCount = 0
        var skippedManualPasteCount = 0
        var abortedSnapshot = false

        var manualPasteNotice: String? {
            guard skippedManualPasteCount > 0 else { return nil }
            if skippedManualPasteCount == 1 {
                return "1 added paragraph was skipped — copy and paste it where it goes."
            }
            return "\(skippedManualPasteCount) added paragraphs were skipped — "
                + "copy and paste them where they go."
        }
    }

    /// Parses and compares a returned `.docx`, persists the updated beta record FIRST so a failed
    /// `betas.json` write never orphans chapter notes, and skips `sourceCommentID`s already linked
    /// to an annotation on retry.
    static func importReturnedDOCX(
        docxData: Data,
        into copy: BetaCopyRecord,
        workID: UUID,
        chapterID: UUID,
        documentBridge: ChapterEditorDocumentBridge,
        liveHTML: String,
        now: Date = Date(),
        onAnnotationsChanged: (() -> Void)? = nil
    ) async throws -> (copy: BetaCopyRecord, addedAnnotations: Bool) {
        let sentHTML = copy.sentHTML
        let betaName = copy.betaName
        let comparison = try await Task.detached(priority: .userInitiated) {
            let docx = try BetaDOCXReader.read(docxData: docxData)
            return BetaComparisonEngine.compare(
                sentHTML: sentHTML,
                returned: docx,
                betaName: betaName
            )
        }.value

        let preparedComments = reuseExistingAnnotationLinks(
            for: comparison.comments,
            previousComments: copy.comments,
            existingAnnotations: documentBridge.annotations
        )

        var updatedCopy = copy
        updatedCopy.returnedAt = now
        updatedCopy.suggestions = comparison.suggestions
        updatedCopy.comments = preparedComments
        updatedCopy.hasSnapshottedBeforeAccept = false
        updatedCopy.refreshStatusFromItems()

        // Write betas.json before creating notes so a failed write cannot leave duplicate notes.
        updatedCopy = try await documentBridge.store.updateBetaCopy(
            workID: workID, chapterID: chapterID, copy: updatedCopy
        )

        var addedAnnotations = false
        for idx in updatedCopy.comments.indices where updatedCopy.comments[idx].annotationID == nil {
            let comment = updatedCopy.comments[idx]
            let anchor = BetaComparisonEngine.anchor(for: comment, sentHTML: updatedCopy.sentHTML, in: liveHTML)
            if let created = await documentBridge.addAnnotation(
                anchor: anchor,
                text: comment.annotationNoteText,
                kind: .note
            ) {
                updatedCopy.comments[idx].annotationID = created.id
                addedAnnotations = true
            }
        }

        if addedAnnotations {
            onAnnotationsChanged?()
            updatedCopy = try await documentBridge.store.updateBetaCopy(
                workID: workID, chapterID: chapterID, copy: updatedCopy
            )
        }
        return (updatedCopy, addedAnnotations)
    }

    private static func reuseExistingAnnotationLinks(
        for incoming: [BetaCommentItem],
        previousComments: [BetaCommentItem],
        existingAnnotations: [WritingAnnotation]
    ) -> [BetaCommentItem] {
        var annotationBySourceID: [String: UUID] = [:]
        for existing in previousComments {
            if let sourceID = existing.sourceCommentID, let annID = existing.annotationID {
                annotationBySourceID[sourceID] = annID
            }
        }
        let resolvedIDs = Set(existingAnnotations.filter { $0.resolvedAt != nil }.map(\.id))
        return incoming.map { comment in
            var item = comment
            if let sourceID = item.sourceCommentID, let annID = annotationBySourceID[sourceID] {
                item.annotationID = annID
                if resolvedIDs.contains(annID) { item.isDone = true }
            }
            return item
        }
    }

    /// Confirms the decoded text at `range` in `session.currentHTML()` still equals `deletedText`
    /// in both Rich Text and HTML mode before calling `session.replaceText`.
    static func verifiedReplaceText(
        in range: RichEditorTextRange,
        expectingDeletedText deletedText: String,
        with insertedText: String,
        in session: DraftSession,
        precheckedHTML: String? = nil
    ) async -> Bool {
        let html: String? = if let precheckedHTML {
            precheckedHTML
        } else {
            await readCurrentHTML(from: session)
        }
        guard let html,
              BetaComparisonEngine.rangeMatchesDeletedText(deletedText, at: range, in: html)
        else {
            return false
        }
        return await session.replaceText(in: range, with: insertedText)
    }

    private enum PreparedPlacement {
        case ready(session: DraftSession, liveHTML: String, htmlRange: RichEditorTextRange)
        case skippedManualPaste
        case unplaceable
    }

    private static func resolvePlacement(
        for suggestion: BetaSuggestionItem,
        in session: DraftSession?
    ) async -> PreparedPlacement {
        guard let session, let liveHTML = await readCurrentHTML(from: session) else {
            return .unplaceable
        }
        switch BetaComparisonEngine.place(suggestion, in: liveHTML) {
        case let .placed(htmlRange):
            guard BetaComparisonEngine.rangeMatchesDeletedText(
                suggestion.deletedText,
                at: htmlRange,
                in: liveHTML
            ) else {
                return .unplaceable
            }
            return .ready(session: session, liveHTML: liveHTML, htmlRange: htmlRange)
        case .wholeParagraphAddition:
            return .skippedManualPaste
        case .crossesFormatting, .notFound:
            return .unplaceable
        }
    }

    @discardableResult
    static func acceptSuggestion(
        suggestionID: UUID,
        in copy: inout BetaCopyRecord,
        workID: UUID,
        chapterID: UUID,
        store: WritingDocumentStore,
        session: DraftSession?,
        snapshotErrorHandler: ((Error) -> Void)? = nil,
        persistErrorHandler: ((Error) -> Void)? = nil
    ) async -> AcceptOutcome {
        guard let sugIdx = copy.suggestions.firstIndex(where: { $0.id == suggestionID }) else {
            return .unplaceable
        }
        let suggestion = copy.suggestions[sugIdx]
        guard suggestion.state == .pending else { return .unplaceable }
        if suggestion.isWholeParagraphAddition { return .skippedManualPaste }

        let activeSession: DraftSession
        let liveHTML: String
        let htmlRange: RichEditorTextRange
        switch await resolvePlacement(for: suggestion, in: session) {
        case let .ready(resolvedSession, resolvedHTML, resolvedRange):
            activeSession = resolvedSession
            liveHTML = resolvedHTML
            htmlRange = resolvedRange
        case .skippedManualPaste:
            return .skippedManualPaste
        case .unplaceable:
            await persistSuggestionState(
                .unplaceable, suggestionID: suggestionID, in: &copy,
                workID: workID, chapterID: chapterID, store: store, onError: persistErrorHandler
            )
            return .unplaceable
        }

        var didSnapshot = false
        if !copy.hasSnapshottedBeforeAccept {
            do {
                _ = try await store.snapshotChapterVersion(
                    workID: workID, chapterID: chapterID, bodyHTML: liveHTML
                )
                copy.hasSnapshottedBeforeAccept = true
                copy = try await store.updateBetaCopy(workID: workID, chapterID: chapterID, copy: copy)
                didSnapshot = true
            } catch {
                snapshotErrorHandler?(error)
                return .abortedSnapshot
            }
        }

        let applied = await verifiedReplaceText(
            in: htmlRange,
            expectingDeletedText: suggestion.deletedText,
            with: suggestion.insertedText,
            in: activeSession,
            precheckedHTML: didSnapshot ? nil : liveHTML
        )
        await persistSuggestionState(
            applied ? .accepted : .unplaceable, suggestionID: suggestionID, in: &copy,
            workID: workID, chapterID: chapterID, store: store, onError: persistErrorHandler
        )
        return applied ? .applied : .unplaceable
    }

    static func acceptAll(
        in copy: inout BetaCopyRecord,
        workID: UUID,
        chapterID: UUID,
        store: WritingDocumentStore,
        session: DraftSession?,
        snapshotErrorHandler: ((Error) -> Void)? = nil,
        persistErrorHandler: ((Error) -> Void)? = nil
    ) async -> AcceptAllResult {
        var result = AcceptAllResult()
        let pendingIDs = copy.pendingSuggestions.map(\.id)
        for sugID in pendingIDs {
            let outcome = await acceptSuggestion(
                suggestionID: sugID,
                in: &copy,
                workID: workID,
                chapterID: chapterID,
                store: store,
                session: session,
                snapshotErrorHandler: snapshotErrorHandler,
                persistErrorHandler: persistErrorHandler
            )
            switch outcome {
            case .applied:
                result.appliedCount += 1
            case .skippedManualPaste:
                result.skippedManualPasteCount += 1
            case .unplaceable:
                result.unplaceableCount += 1
            case .abortedSnapshot:
                result.abortedSnapshot = true
                return result
            }
        }
        return result
    }

    static func readCurrentHTML(from session: DraftSession) async -> String? {
        if let html = await session.currentHTML() {
            return html
        }
        if session.owner == .source {
            return session.source.text
        }
        return nil
    }

    private static func persistSuggestionState(
        _ newState: BetaSuggestionState,
        suggestionID: UUID,
        in copy: inout BetaCopyRecord,
        workID: UUID,
        chapterID: UUID,
        store: WritingDocumentStore,
        onError: ((Error) -> Void)?
    ) async {
        guard let sugIdx = copy.suggestions.firstIndex(where: { $0.id == suggestionID }) else { return }
        var updated = copy
        updated.suggestions[sugIdx].state = newState
        updated.refreshStatusFromItems()
        do {
            copy = try await store.updateBetaCopy(
                workID: workID,
                chapterID: chapterID,
                copy: updated
            )
        } catch {
            onError?(error)
        }
    }
}

// MARK: - Actions & round-trip orchestration

extension BetaReadingSheet {
    typealias AcceptOutcome = BetaReviewActions.AcceptOutcome

    func loadBetaData() async {
        if documentBridge.workID == nil || documentBridge.chapterID == nil {
            await ensureDocumentOpen()
        }
        guard let workID = documentBridge.workID, let chapterID = documentBridge.chapterID else { return }
        do {
            var loaded = try await documentBridge.store.listBetaCopies(workID: workID, chapterID: chapterID)
            loaded = await syncResolvedCommentsFromAnnotations(loaded, workID: workID, chapterID: chapterID)
            copies = loaded
            recentNames = try await documentBridge.store.recentBetaNames(preferringWorkID: workID)
            if selectedCopyID == nil {
                selectedCopyID = loaded.first { $0.status == .cameBack }?.id
                    ?? loaded.first { $0.returnedAt != nil }?.id
            }
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func syncResolvedCommentsFromAnnotations(
        _ records: [BetaCopyRecord],
        workID: UUID,
        chapterID: UUID
    ) async -> [BetaCopyRecord] {
        let annotationsByID = Dictionary(
            uniqueKeysWithValues: documentBridge.annotations.map { ($0.id, $0) }
        )
        var synced: [BetaCopyRecord] = []
        for var record in records {
            var changed = false
            for idx in record.comments.indices where !record.comments[idx].isDone {
                if let annID = record.comments[idx].annotationID,
                   let annotation = annotationsByID[annID],
                   annotation.resolvedAt != nil {
                    record.comments[idx].isDone = true
                    changed = true
                }
            }
            if changed {
                record.refreshStatusFromItems()
                if let saved = try? await documentBridge.store.updateBetaCopy(
                    workID: workID, chapterID: chapterID, copy: record
                ) {
                    record = saved
                }
            }
            synced.append(record)
        }
        return synced
    }

    func sendCopy(to betaName: String, format: BetaCopyFormat) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        if documentBridge.workID == nil || documentBridge.chapterID == nil {
            await ensureDocumentOpen()
        }
        guard let workID = documentBridge.workID, let chapterID = documentBridge.chapterID else {
            errorMessage = "Couldn’t open the local copy of this chapter."
            return
        }

        let sentHTML = await commitAndPersistHTML()
        let fileName = BetaExportFileName.make(
            chapterNumber: chapterNumber, chapterTitle: chapterTitle, betaName: betaName, format: format
        )

        do {
            let fileData: Data
            switch format {
            case .docx:
                fileData = try BetaDOCXWriter.writeDOCX(html: sentHTML, title: chapterSubtitle, author: authorName)
            case .pdf:
                #if os(iOS)
                fileData = BetaPDFExporter.renderPDF(
                    workTitle: workTitle,
                    chapterNumber: chapterNumber,
                    chapterTitle: chapterTitle,
                    bodyHTML: sentHTML
                )
                #else
                return
                #endif
            }

            _ = try await documentBridge.store.recordBetaCopy(
                workID: workID, chapterID: chapterID, betaName: betaName, format: format, sentHTML: sentHTML
            )
            copies = try await documentBridge.store.listBetaCopies(workID: workID, chapterID: chapterID)
            recentNames = try await documentBridge.store.recentBetaNames(preferringWorkID: workID)

            #if os(iOS)
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("kudos-beta-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let fileURL = tempDir.appendingPathComponent(fileName)
            try fileData.write(to: fileURL, options: .atomic)
            activeModal = .share(BetaShareFileItem(url: fileURL))
            #else
            macExportDocument = BetaExportFileDocument(data: fileData)
            macExportFilename = fileName
            isExportingOnMac = true
            #endif
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func handleCopyRowTap(_ copy: BetaCopyRecord) {
        if copy.returnedAt != nil {
            if selectedCopyID != copy.id { bulkStatusMessage = nil }
            selectedCopyID = copy.id
        } else if copy.format.supportsReturnImport {
            beginImport(for: copy)
        }
    }

    func beginImport(for copy: BetaCopyRecord) {
        importingForCopyID = copy.id
        isImportingDOCX = true
    }

    func handleDOCXImportResult(_ result: Result<[URL], Error>) {
        guard let copyID = importingForCopyID else { return }
        importingForCopyID = nil
        switch result {
        case let .failure(error):
            errorMessage = UserFacingError.message(for: error)
        case let .success(urls):
            guard let url = urls.first else { return }
            Task { await importReturnedDOCX(from: url, forCopyID: copyID) }
        }
    }

    private func importReturnedDOCX(from url: URL, forCopyID copyID: UUID) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        guard let workID = documentBridge.workID,
              let chapterID = documentBridge.chapterID,
              let copy = copies.first(where: { $0.id == copyID })
        else { return }

        do {
            let fileData = try await Task.detached(priority: .userInitiated) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return try BetaDOCXReader.readFileData(at: url)
            }.value

            let liveHTML = await readCurrentHTML() ?? fallbackContent()
            let imported = try await BetaReviewActions.importReturnedDOCX(
                docxData: fileData,
                into: copy,
                workID: workID,
                chapterID: chapterID,
                documentBridge: documentBridge,
                liveHTML: liveHTML,
                onAnnotationsChanged: onAnnotationsChanged
            )
            copies = try await documentBridge.store.listBetaCopies(workID: workID, chapterID: chapterID)
            selectedCopyID = imported.copy.id
            bulkStatusMessage = nil
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func acceptSuggestion(_ suggestion: BetaSuggestionItem, in copyID: UUID) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        _ = await performAcceptSuggestion(suggestionID: suggestion.id, in: copyID)
    }

    @discardableResult
    private func performAcceptSuggestion(suggestionID: UUID, in copyID: UUID) async -> AcceptOutcome {
        guard let workID = documentBridge.workID,
              let chapterID = documentBridge.chapterID,
              let copyIdx = copies.firstIndex(where: { $0.id == copyID })
        else { return .unplaceable }

        var copy = copies[copyIdx]
        let outcome = await BetaReviewActions.acceptSuggestion(
            suggestionID: suggestionID,
            in: &copy,
            workID: workID,
            chapterID: chapterID,
            store: documentBridge.store,
            session: session,
            snapshotErrorHandler: { error in
                errorMessage = "Couldn’t save a backup version before applying edits: "
                    + UserFacingError.message(for: error)
            },
            persistErrorHandler: { error in errorMessage = UserFacingError.message(for: error) }
        )
        if let latestIdx = copies.firstIndex(where: { $0.id == copyID }) {
            copies[latestIdx] = copy
        }
        if outcome == .applied { onAnnotationsChanged() }
        return outcome
    }

    func setSuggestionState(_ newState: BetaSuggestionState, id suggestionID: UUID, in copyID: UUID) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        await persistSuggestionState(newState, suggestionID: suggestionID, in: copyID)
    }

    private func persistSuggestionState(
        _ newState: BetaSuggestionState,
        suggestionID: UUID,
        in copyID: UUID
    ) async {
        guard let workID = documentBridge.workID,
              let chapterID = documentBridge.chapterID,
              let copyIdx = copies.firstIndex(where: { $0.id == copyID }),
              let sugIdx = copies[copyIdx].suggestions.firstIndex(where: { $0.id == suggestionID })
        else { return }

        var updated = copies[copyIdx]
        updated.suggestions[sugIdx].state = newState
        updated.refreshStatusFromItems()
        do {
            copies[copyIdx] = try await documentBridge.store.updateBetaCopy(
                workID: workID, chapterID: chapterID, copy: updated
            )
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func markCommentDone(_ comment: BetaCommentItem, in copyID: UUID) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        await performMarkCommentDone(commentID: comment.id, in: copyID)
    }

    private func performMarkCommentDone(commentID: UUID, in copyID: UUID) async {
        guard let workID = documentBridge.workID,
              let chapterID = documentBridge.chapterID,
              let copyIdx = copies.firstIndex(where: { $0.id == copyID }),
              let commentIdx = copies[copyIdx].comments.firstIndex(where: { $0.id == commentID })
        else { return }

        let comment = copies[copyIdx].comments[commentIdx]
        if let annID = comment.annotationID,
           let annotation = documentBridge.annotations.first(where: { $0.id == annID }),
           annotation.resolvedAt == nil {
            _ = await documentBridge.setAnnotationResolved(annotation, resolved: true)
            onAnnotationsChanged()
        }

        var updated = copies[copyIdx]
        updated.comments[commentIdx].isDone = true
        updated.refreshStatusFromItems()
        do {
            copies[copyIdx] = try await documentBridge.store.updateBetaCopy(
                workID: workID, chapterID: chapterID, copy: updated
            )
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func performBulkAction(_ action: BulkReviewAction) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        bulkStatusMessage = nil

        switch action {
        case let .acceptAll(copyID, _, _):
            guard let workID = documentBridge.workID,
                  let chapterID = documentBridge.chapterID,
                  let copyIdx = copies.firstIndex(where: { $0.id == copyID })
            else { return }
            var copy = copies[copyIdx]
            let result = await BetaReviewActions.acceptAll(
                in: &copy,
                workID: workID,
                chapterID: chapterID,
                store: documentBridge.store,
                session: session,
                snapshotErrorHandler: { error in
                    errorMessage = "Couldn’t save a backup version before applying edits: "
                        + UserFacingError.message(for: error)
                },
                persistErrorHandler: { error in errorMessage = UserFacingError.message(for: error) }
            )
            if let latestIdx = copies.firstIndex(where: { $0.id == copyID }) {
                copies[latestIdx] = copy
            }
            if result.appliedCount > 0 { onAnnotationsChanged() }
            bulkStatusMessage = result.manualPasteNotice
        case let .rejectAll(copyID, _):
            guard let workID = documentBridge.workID,
                  let chapterID = documentBridge.chapterID,
                  let copyIdx = copies.firstIndex(where: { $0.id == copyID })
            else { return }
            var updated = copies[copyIdx]
            for idx in updated.suggestions.indices where updated.suggestions[idx].state == .pending {
                updated.suggestions[idx].state = .rejected
            }
            updated.refreshStatusFromItems()
            do {
                copies[copyIdx] = try await documentBridge.store.updateBetaCopy(
                    workID: workID, chapterID: chapterID, copy: updated
                )
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
        case let .resolveAllComments(copyID, _):
            guard let copy = copies.first(where: { $0.id == copyID }) else { return }
            for commentID in copy.openComments.map(\.id) {
                await performMarkCommentDone(commentID: commentID, in: copyID)
            }
        }
    }

    func markPDFCopyReviewed(_ copy: BetaCopyRecord) async {
        guard let workID = documentBridge.workID, let chapterID = documentBridge.chapterID else { return }
        var updated = copy
        updated.status = .reviewed
        do {
            _ = try await documentBridge.store.updateBetaCopy(workID: workID, chapterID: chapterID, copy: updated)
            copies = try await documentBridge.store.listBetaCopies(workID: workID, chapterID: chapterID)
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func deleteCopy(_ copy: BetaCopyRecord) async {
        guard let workID = documentBridge.workID, let chapterID = documentBridge.chapterID else { return }
        do {
            try await documentBridge.store.deleteBetaCopy(workID: workID, chapterID: chapterID, copyID: copy.id)
            copies = try await documentBridge.store.listBetaCopies(workID: workID, chapterID: chapterID)
            if selectedCopyID == copy.id {
                selectedCopyID = copies.first { $0.status == .cameBack }?.id
                    ?? copies.first { $0.returnedAt != nil }?.id
            }
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func readCurrentHTML() async -> String? {
        guard let session else { return nil }
        return await BetaReviewActions.readCurrentHTML(from: session)
    }

    func copyToClipboard(_ text: String, suggestionID: UUID) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        copiedSuggestionID = suggestionID
        copiedResetTask?.cancel()
        copiedResetTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            copiedSuggestionID = nil
        }
    }
}
