import Foundation
import SwiftData

/// Pure submission coordinator for `OrphanSheet`, separated so tests can verify
/// that nothing is sent to AO3 when a local copy fails, when the sheet is
/// cancelled/dismissed mid-flow, or when the final system alert is cancelled.
@MainActor
enum OrphanSubmissionFlow {
    struct WorkCopyItem: Equatable, Sendable {
        let workID: Int
        let title: String
    }

    enum FinalAlertDecision: Equatable, Sendable {
        case confirmed
        case cancelled
    }

    enum Outcome: Equatable, Sendable {
        case cancelled
        case copyFailed(workTitle: String, reason: String)
        case orphaned(String)
        case mayHaveGoneThrough(String)
        case failed(String)
    }

    static let mayHaveGoneThroughMessage =
        "This may have gone through on AO3. Check your works on AO3 before trying again."

    static func run(
        target: AO3OrphanTarget,
        keepPseudCopy: Bool,
        keepLocalCopy: Bool,
        finalAlertDecision: FinalAlertDecision,
        form: AO3OrphanForm,
        resolveWorks: @MainActor () async throws -> [WorkCopyItem],
        copyWork: @MainActor (Int) async throws -> Void,
        submitOrphan: @MainActor (AO3OrphanTarget, Bool, AO3OrphanForm) async throws -> String
    ) async -> Outcome {
        guard finalAlertDecision == .confirmed, !Task.isCancelled else { return .cancelled }

        if keepLocalCopy {
            if let copyOutcome = await copyAllWorks(
                form: form,
                resolveWorks: resolveWorks,
                copyWork: copyWork
            ) {
                return copyOutcome
            }
        }

        guard !Task.isCancelled else { return .cancelled }
        do {
            let notice = try await submitOrphan(target, keepPseudCopy, form)
            return .orphaned(notice)
        } catch is CancellationError {
            return .cancelled
        } catch {
            if AO3WriteOutcomeClassifier.mayHaveGoneThrough(error) {
                return .mayHaveGoneThrough(mayHaveGoneThroughMessage)
            }
            return .failed(UserFacingError.message(for: error))
        }
    }

    private static func copyAllWorks(
        form: AO3OrphanForm,
        resolveWorks: @MainActor () async throws -> [WorkCopyItem],
        copyWork: @MainActor (Int) async throws -> Void
    ) async -> Outcome? {
        let items: [WorkCopyItem]
        do {
            items = try await resolveWorks()
        } catch is CancellationError {
            return .cancelled
        } catch let copyError as AO3OrphanCopyError {
            return .copyFailed(
                workTitle: copyError.workTitle,
                reason: UserFacingError.message(for: copyError)
            )
        } catch {
            if Task.isCancelled { return .cancelled }
            let fallback = form.titles.first ?? "this series"
            return .copyFailed(
                workTitle: fallback,
                reason: UserFacingError.message(for: error)
            )
        }
        guard !Task.isCancelled else { return .cancelled }
        for item in items {
            guard !Task.isCancelled else { return .cancelled }
            do {
                try await copyWork(item.workID)
            } catch is CancellationError {
                return .cancelled
            } catch {
                if Task.isCancelled { return .cancelled }
                return .copyFailed(
                    workTitle: item.title,
                    reason: UserFacingError.message(for: error)
                )
            }
            guard !Task.isCancelled else { return .cancelled }
        }
        return nil
    }

    /// Saves a single AO3 work into the local SwiftData library the same way
    /// Work Detail's Download action does, awaiting completion before returning.
    static func saveLocalCopy(
        workID: Int,
        in context: ModelContext,
        downloadEPUB: ((Int) async throws -> URL)? = nil
    ) async throws {
        let sourceURL = AO3Client.workURL(workID: workID)
        if let existing = existingWork(forSource: sourceURL, in: context) {
            if existing.isPendingDeletion {
                PreservedWorkService.restore(existing, in: context)
            }
            if !WorkReaderPreparation.hasReadableEPUB(for: existing) {
                try await WorkReaderPreparation.restoreReadableEPUB(
                    for: existing,
                    in: context,
                    downloadEPUB: downloadEPUB
                )
            }
            WorkLifecycle.setSaved(existing, true, in: context)
            return
        }
        let tempURL = if let downloadEPUB {
            try await downloadEPUB(workID)
        } else {
            try await AO3Client.shared.downloadEPUB(workID: workID)
        }
        let saved = try await importEPUB(
            tempURL,
            source: sourceURL,
            verifyAvailability: false,
            into: context
        )
        WorkLifecycle.setSaved(saved, true, in: context)
    }

    static func resolveCopyItems(
        for target: AO3OrphanTarget,
        form: AO3OrphanForm,
        auth: AO3AuthService,
        using client: AO3Client = .shared
    ) async throws -> [WorkCopyItem] {
        switch target {
        case let .work(id):
            if let item = form.workItems.first(where: { $0.workID == id }) {
                return [WorkCopyItem(workID: item.workID, title: item.title)]
            }
            return [WorkCopyItem(workID: id, title: form.titles.first ?? "Work \(id)")]
        case let .works(ids):
            if !form.workItems.isEmpty {
                return form.workItems.map { WorkCopyItem(workID: $0.workID, title: $0.title) }
            }
            return ids.enumerated().map { index, id in
                let title = index < form.titles.count ? form.titles[index] : "Work \(id)"
                return WorkCopyItem(workID: id, title: title)
            }
        case let .series(seriesID):
            let works = try await auth.loadSeriesWorksForOrphanCopy(
                seriesID: seriesID,
                using: client
            )
            return works.map { WorkCopyItem(workID: $0.workID, title: $0.title) }
        }
    }
}

/// Pure outcome handler for "Remove Me as Co-Creator" on both works and series,
/// guaranteeing `.onlyCreator` surfaces the exact message and mutates nothing.
@MainActor
enum WorkCoCreatorRemovalFlow {
    enum TargetKind: Equatable, Sendable {
        case work
        case series

        var onlyCreatorMessage: String {
            switch self {
            case .work:
                "You're the only creator of this work. You can orphan it or delete it instead."
            case .series:
                "You're the only creator of this series. You can orphan it or delete it instead."
            }
        }
    }

    enum Outcome: Equatable, Sendable {
        case removed(String)
        case onlyCreator(String)
        case failed(String)
    }

    static func run(
        kind: TargetKind,
        remove: @MainActor () async throws -> String,
        onRemoved: @MainActor () -> Void
    ) async -> Outcome {
        do {
            let notice = try await remove()
            onRemoved()
            return .removed(notice)
        } catch AO3WorkWriteError.onlyCreator {
            return .onlyCreator(kind.onlyCreatorMessage)
        } catch {
            return .failed(UserFacingError.message(for: error))
        }
    }
}

/// Pure submission coordinator for `ImportWorkView`, classifying post-send
/// network errors / timeouts into their own outcome so the sheet does not invite
/// a duplicate import before the user checks Drafts.
@MainActor
enum AO3ImportSubmissionFlow {
    enum Outcome: Equatable, Sendable {
        case draft(Int)
        case posted(Int)
        case several([Int], failures: String?)
        case mayHaveGoneThrough(String)
        case failed(String)
    }

    static let mayHaveGoneThroughMessage =
        "This may have gone through on AO3. Check Drafts before trying again."

    static func canSubmit(
        verdict: AO3ImportValidation.Verdict,
        isSubmitting: Bool,
        ambiguousOutcomeMessage: String?
    ) -> Bool {
        verdict.canImport && !isSubmitting && ambiguousOutcomeMessage == nil
    }

    static func run(
        request: AO3ImportRequest,
        form: AO3ImportForm,
        submit: @MainActor (AO3ImportRequest, AO3ImportForm) async throws -> AO3ImportResult
    ) async -> Outcome {
        do {
            switch try await submit(request, form) {
            case let .draft(workID):
                return .draft(workID)
            case let .posted(workID):
                return .posted(workID)
            case let .several(ids, failures):
                return .several(ids, failures: failures)
            case let .failed(message):
                return .failed(message)
            }
        } catch {
            if AO3WriteOutcomeClassifier.mayHaveGoneThrough(error) {
                return .mayHaveGoneThrough(mayHaveGoneThroughMessage)
            }
            return .failed(UserFacingError.message(for: error))
        }
    }
}
