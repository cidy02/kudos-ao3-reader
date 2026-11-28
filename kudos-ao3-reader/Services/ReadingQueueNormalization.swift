import Foundation
import SwiftData

extension ReadingQueueService {
    static func normalizeAllQueuedWorks(in context: ModelContext) {
        let batchSize = 250
        var pending = 0
        var seen = Set<UUID>()
        var directory: URL? = nil
        // Restore runs this inside an unsaved transaction. Its inverse edits
        // must be read from the live graph instead of trusting a store join.
        let hasPendingGraphEdits = context.hasChanges

        func fileExists(_ work: SavedWork) -> Bool {
            let base = directory ?? Storage.worksDirectory
            directory = base
            let name = Storage.safeEPUBAssetIdentifier(work.effectiveAssetIdentifier, fallbackID: work.id)
            return FileManager.default.fileExists(atPath: base.appendingPathComponent(name).path)
        }

        func saveBatch() {
            if context.hasChanges {
                context.saveBestEffort(reason: "Saving queue normalization failed")
            }
            pending = 0
        }

        func countRepair() {
            pending += 1
            if pending == batchSize { saveBatch() }
        }

        let brokenLinks = FetchDescriptor<ReadingQueueMembership>(predicate: #Predicate {
            $0.queue == nil || $0.work == nil || $0.work?.isQueuedForLater == false
        })
        let storedBrokenLinks = hasPendingGraphEdits ? nil : try? context.fetch(brokenLinks)
        let memberships = storedBrokenLinks
            ?? ((try? context.fetch(FetchDescriptor<ReadingQueueMembership>())) ?? []).filter {
                $0.queue == nil || $0.work == nil || $0.work?.isQueuedForLater == false
            }
        for membership in memberships {
            let linkedWork = membership.work
            if membership.queue == nil || linkedWork == nil {
                membership.queue?.memberships.removeAll { $0.id == membership.id }
                linkedWork?.queueMemberships.removeAll { $0.id == membership.id }
                context.delete(membership)
            }
            // An orphan can lose its work endpoint immediately on detach.
            // Its old work still needs repair if it keeps the queued flag.
            let work = membership.work ?? linkedWork.flatMap { $0.isQueuedForLater ? $0 : nil }
            if let work, seen.insert(work.id).inserted {
                normalize(work, hasMembership: work.queueMemberships.contains { $0.queue != nil },
                          fileExists: fileExists)
            }
            countRepair()
        }

        let missingLinks = FetchDescriptor<SavedWork>(predicate: #Predicate {
            $0.isQueuedForLater && $0.queueMemberships.isEmpty
        })
        let flaggedDescriptor = FetchDescriptor<SavedWork>(
            predicate: #Predicate { $0.isQueuedForLater }
        )
        let storedUnlinked = hasPendingGraphEdits ? nil : try? context.fetch(missingLinks)
        let unlinked = storedUnlinked ?? ((try? context.fetch(flaggedDescriptor)) ?? []).filter {
            !$0.queueMemberships.contains { $0.queue != nil }
        }
        for work in unlinked where seen.insert(work.id).inserted {
            normalize(work, hasMembership: false, fileExists: fileExists)
            countRepair()
        }

        let normalizedPreservation = EPUBPreservationStatus.allCases.filter { $0 != .notPreserved }.map(\.rawValue)
        let resolvedMetadata = MetadataSyncStatus.allCases.filter { $0 != .unknown }.map(\.rawValue)
        let preserved = EPUBPreservationStatus.preserved.rawValue
        let candidates = FetchDescriptor<SavedWork>(predicate: #Predicate {
            $0.isQueuedForLater && (
                $0.hasEPUB || $0.epubPreservationStatusRaw == preserved
                    || !normalizedPreservation.contains($0.epubPreservationStatusRaw)
                    || (!resolvedMetadata.contains($0.metadataSyncStatusRaw) && !$0.ao3Unavailable)
                    || ($0.ao3WorkID == nil && $0.sourceURL != "")
                    || ($0.ao3SeriesID == nil && $0.seriesURL != "")
            )
        })
        // The earlier passes repaired missing endpoints and flag mismatches. This
        // pass needs no membership graph. EPUB claims still need a disk check,
        // because a file can disappear without changing any SwiftData field.
        let works = (try? context.fetch(candidates)) ?? (try? context.fetch(flaggedDescriptor)) ?? []
        for work in works where seen.insert(work.id).inserted {
            normalize(work, hasMembership: true, fileExists: fileExists)
            countRepair()
        }
        saveBatch()
    }

    static func normalize(_ work: SavedWork) {
        normalize(work, hasMembership: work.queueMemberships.contains { $0.queue != nil }) {
            FileManager.default.fileExists(atPath: $0.fileURL.path)
        }
    }

    private static func normalize(
        _ work: SavedWork,
        hasMembership: Bool,
        fileExists: (SavedWork) -> Bool
    ) {
        if work.ao3WorkID == nil, !work.sourceURL.isEmpty,
           let id = WorkTags.ao3WorkID(from: work.sourceURL) {
            work.ao3WorkID = id
        }
        if work.ao3SeriesID == nil, !work.seriesURL.isEmpty,
           let id = ao3SeriesID(from: work.seriesURL) {
            work.ao3SeriesID = id
        }
        if work.isQueuedForLater != hasMembership { work.isQueuedForLater = hasMembership }

        let preservation = work.epubPreservationStatus
        if (work.hasEPUB || (hasMembership && preservation == .preserved)), !fileExists(work) {
            if work.hasEPUB { work.hasEPUB = false }
            if hasMembership, preservation == .preserved { work.epubPreservationStatus = .missingFile }
        }

        if hasMembership {
            if work.hasEPUB {
                if preservation != .preserving, preservation != .preserved {
                    work.epubPreservationStatus = .preserved
                }
                if work.preservedAt == nil { work.preservedAt = Date() }
            } else if preservation == .notPreserved {
                work.epubPreservationStatus = .queued
            }
            if work.metadataSyncStatus == .unknown, work.needsAO3Refresh {
                work.metadataSyncStatus = .pending
            }
        } else if preservation != .notPreserved {
            work.epubPreservationStatus = .notPreserved
            work.preservedAt = nil
        }
    }
}
