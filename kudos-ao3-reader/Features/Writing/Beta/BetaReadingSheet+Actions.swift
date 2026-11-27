import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Actions & round-trip orchestration

extension BetaReadingSheet {
    enum AcceptOutcome {
        case applied
        case unplaceable
        case abortedSnapshot
    }

    func loadBetaData() async {
        if documentBridge.workID == nil || documentBridge.chapterID == nil {
            await ensureDocumentOpen()
        }
        guard let workID = documentBridge.workID, let chapterID = documentBridge.chapterID else { return }
        do {
            var loaded = try await documentBridge.store.listBetaCopies(
                workID: workID,
                chapterID: chapterID
            )
            loaded = await syncResolvedCommentsFromAnnotations(
                loaded,
                workID: workID,
                chapterID: chapterID
            )
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
                    workID: workID,
                    chapterID: chapterID,
                    copy: record
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
            chapterNumber: chapterNumber,
            chapterTitle: chapterTitle,
            betaName: betaName,
            format: format
        )

        do {
            let fileData: Data
            switch format {
            case .docx:
                fileData = try BetaDOCXWriter.writeDOCX(
                    html: sentHTML,
                    title: chapterSubtitle,
                    author: authorName
                )
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
                workID: workID,
                chapterID: chapterID,
                betaName: betaName,
                format: format,
                sentHTML: sentHTML
            )
            copies = try await documentBridge.store.listBetaCopies(
                workID: workID,
                chapterID: chapterID
            )
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
              var copy = copies.first(where: { $0.id == copyID })
        else { return }

        do {
            let fileData: Data = try {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return try Data(contentsOf: url)
            }()

            let sentHTML = copy.sentHTML
            let betaName = copy.betaName
            let comparison = try await Task.detached(priority: .userInitiated) {
                let docx = try BetaDOCXReader.read(docxData: fileData)
                return BetaComparisonEngine.compare(
                    sentHTML: sentHTML,
                    returned: docx,
                    betaName: betaName
                )
            }.value

            let liveHTML = await readCurrentHTML() ?? fallbackContent()
            var linkedComments: [BetaCommentItem] = []
            for var comment in comparison.comments {
                let anchor = BetaComparisonEngine.anchor(
                    for: comment,
                    sentHTML: copy.sentHTML,
                    in: liveHTML
                )
                if let created = await documentBridge.addAnnotation(
                    anchor: anchor,
                    text: comment.annotationNoteText,
                    kind: .note
                ) {
                    comment.annotationID = created.id
                }
                linkedComments.append(comment)
            }
            if !linkedComments.isEmpty {
                onAnnotationsChanged()
            }

            copy.returnedAt = Date()
            copy.suggestions = comparison.suggestions
            copy.comments = linkedComments
            copy.hasSnapshottedBeforeAccept = false
            copy.refreshStatusFromItems()

            _ = try await documentBridge.store.updateBetaCopy(
                workID: workID,
                chapterID: chapterID,
                copy: copy
            )
            copies = try await documentBridge.store.listBetaCopies(
                workID: workID,
                chapterID: chapterID
            )
            selectedCopyID = copy.id
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
    private func performAcceptSuggestion(
        suggestionID: UUID,
        in copyID: UUID
    ) async -> AcceptOutcome {
        guard let workID = documentBridge.workID,
              let chapterID = documentBridge.chapterID,
              let copyIdx = copies.firstIndex(where: { $0.id == copyID }),
              let sugIdx = copies[copyIdx].suggestions.firstIndex(where: { $0.id == suggestionID })
        else { return .unplaceable }

        let suggestion = copies[copyIdx].suggestions[sugIdx]
        guard suggestion.state == .pending else { return .unplaceable }

        guard let session, let liveHTML = await readCurrentHTML() else {
            await persistSuggestionState(.unplaceable, suggestionID: suggestionID, in: copyID)
            return .unplaceable
        }

        guard case let .placed(htmlRange) = BetaComparisonEngine.place(suggestion, in: liveHTML) else {
            await persistSuggestionState(.unplaceable, suggestionID: suggestionID, in: copyID)
            return .unplaceable
        }

        if !copies[copyIdx].hasSnapshottedBeforeAccept {
            do {
                _ = try await documentBridge.store.snapshotChapterVersion(
                    workID: workID,
                    chapterID: chapterID,
                    bodyHTML: liveHTML
                )
                copies[copyIdx].hasSnapshottedBeforeAccept = true
                _ = try await documentBridge.store.updateBetaCopy(
                    workID: workID,
                    chapterID: chapterID,
                    copy: copies[copyIdx]
                )
            } catch {
                errorMessage = "Couldn’t save a backup version before applying edits: "
                    + UserFacingError.message(for: error)
                return .abortedSnapshot
            }
        }

        let applied = await session.replaceText(in: htmlRange, with: suggestion.insertedText)
        if applied {
            await persistSuggestionState(.accepted, suggestionID: suggestionID, in: copyID)
            onAnnotationsChanged()
            return .applied
        } else {
            await persistSuggestionState(.unplaceable, suggestionID: suggestionID, in: copyID)
            return .unplaceable
        }
    }

    func setSuggestionState(
        _ newState: BetaSuggestionState,
        id suggestionID: UUID,
        in copyID: UUID
    ) async {
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
            let saved = try await documentBridge.store.updateBetaCopy(
                workID: workID,
                chapterID: chapterID,
                copy: updated
            )
            copies[copyIdx] = saved
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
            let saved = try await documentBridge.store.updateBetaCopy(
                workID: workID,
                chapterID: chapterID,
                copy: updated
            )
            copies[copyIdx] = saved
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func performBulkAction(_ action: BulkReviewAction) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        switch action {
        case let .acceptAll(copyID, _):
            guard let copy = copies.first(where: { $0.id == copyID }) else { return }
            let pendingIDs = copy.pendingSuggestions.map(\.id)
            for sugID in pendingIDs {
                let outcome = await performAcceptSuggestion(suggestionID: sugID, in: copyID)
                if outcome == .abortedSnapshot { break }
            }
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
                    workID: workID,
                    chapterID: chapterID,
                    copy: updated
                )
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
        case let .resolveAllComments(copyID, _):
            guard let copy = copies.first(where: { $0.id == copyID }) else { return }
            let openIDs = copy.openComments.map(\.id)
            for commentID in openIDs {
                await performMarkCommentDone(commentID: commentID, in: copyID)
            }
        }
    }

    func markPDFCopyReviewed(_ copy: BetaCopyRecord) async {
        guard let workID = documentBridge.workID, let chapterID = documentBridge.chapterID else { return }
        var updated = copy
        updated.status = .reviewed
        do {
            _ = try await documentBridge.store.updateBetaCopy(
                workID: workID,
                chapterID: chapterID,
                copy: updated
            )
            copies = try await documentBridge.store.listBetaCopies(
                workID: workID,
                chapterID: chapterID
            )
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func deleteCopy(_ copy: BetaCopyRecord) async {
        guard let workID = documentBridge.workID, let chapterID = documentBridge.chapterID else { return }
        do {
            try await documentBridge.store.deleteBetaCopy(
                workID: workID,
                chapterID: chapterID,
                copyID: copy.id
            )
            copies = try await documentBridge.store.listBetaCopies(
                workID: workID,
                chapterID: chapterID
            )
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
        if let html = await session.currentHTML() {
            return html
        }
        if session.owner == .source {
            return session.source.text
        }
        return nil
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
