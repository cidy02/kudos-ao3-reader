import Foundation
import SwiftData

/// Time budgets offered on `Queue-TimeFit.dc.html`: `15 min`, `30 min`, `1 h`, `2 h +`.
enum WhatFitsBucket: String, CaseIterable, Identifiable, Hashable {
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case twoHoursPlus

    static let defaultSelection: Self = .thirtyMinutes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fifteenMinutes: "15 min"
        case .thirtyMinutes: "30 min"
        case .oneHour: "1 h"
        case .twoHoursPlus: "2 h +"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        case .twoHoursPlus: "2 hours or more"
        }
    }

    /// Maximum reading time in minutes for capped buckets; `nil` means 2 hours or more.
    var maxMinutes: Int? {
        switch self {
        case .fifteenMinutes: 15
        case .thirtyMinutes: 30
        case .oneHour: 60
        case .twoHoursPlus: nil
        }
    }

    /// True when `minutes` fits inside this bucket (`<= maxMinutes` with a tiny
    /// binary-float tolerance so exact percentages like `1 - 0.7` do not miss).
    func fits(minutes: Double) -> Bool {
        guard minutes.isFinite, minutes >= 0 else { return false }
        guard let maxMinutes else { return true }
        return minutes <= Double(maxMinutes) + 1e-6
    }
}

/// One queued work matched against a `WhatFitsBucket`.
struct WhatFitsEntry: Identifiable {
    enum Section: Equatable {
        case finishInThisSitting
        case startAndFinish
    }

    let work: SavedWork
    let section: Section
    let minutesLeft: Double
    let isOffline: Bool
    let queueNames: [String]

    var id: UUID { work.id }

    var timeLabel: String {
        let duration = WhatFitsPlanner.durationLabel(minutes: minutesLeft)
        return section == .finishInThisSitting ? "\(duration) left" : duration
    }

    var queueSummary: String {
        queueNames.joined(separator: ", ")
    }

    var accessibilitySummary: String {
        let spokenDuration = WhatFitsPlanner.spokenDurationLabel(minutes: minutesLeft)
        let timePhrase = section == .finishInThisSitting ? "\(spokenDuration) left" : spokenDuration
        var parts = [timePhrase]
        if !queueSummary.isEmpty {
            parts.append("in \(queueSummary)")
        }
        if !isOffline {
            parts.append("needs download")
        }
        return parts.joined(separator: ", ")
    }
}

/// Pure, local-only plan for `WhatFitsView`.
struct WhatFitsPlan {
    let queueCount: Int
    let finishInThisSitting: [WhatFitsEntry]
    let startAndFinish: [WhatFitsEntry]
    let hasAnyVisibleWorks: Bool
    let hasAnyUnfinishedWorks: Bool
    let hasAnyWordCounts: Bool
    let hasHiddenMatureFits: Bool
    let nextFittingBucket: (bucket: WhatFitsBucket, count: Int)?

    var isEmpty: Bool {
        finishInThisSitting.isEmpty && startAndFinish.isEmpty
    }

    var allEntries: [WhatFitsEntry] {
        finishInThisSitting + startAndFinish
    }
}

/// Computes `WhatFitsPlan` locally across all active queues using `ReadingQueueFacts.minutesLeft(for:)`.
enum WhatFitsPlanner {
    private struct Candidate {
        let work: SavedWork
        var queueNames: [String] = []
        private var seenQueueNames: Set<String> = []

        init(work: SavedWork, queueName: String) {
            self.work = work
            addQueueName(queueName)
        }

        mutating func addQueueName(_ name: String) {
            if seenQueueNames.insert(name).inserted { queueNames.append(name) }
        }
    }

    private struct TimedCandidate {
        let work: SavedWork
        let queueNames: [String]
        let section: WhatFitsEntry.Section
        let minutesLeft: Double
        let isOffline: Bool
        let encounterOrder: Int
    }

    /// Formats a reading-time duration in minutes as `"8 min"`, `"1 h"`, or `"1 h 15 min"`.
    static func durationLabel(minutes rawMinutes: Double) -> String {
        guard rawMinutes >= 0.5 else { return "< 1 min" }
        let totalMinutes = Int(rawMinutes.rounded())
        if totalMinutes < 60 { return "\(totalMinutes) min" }
        let hours = totalMinutes / 60
        let remainder = totalMinutes % 60
        return remainder > 0 ? "\(hours) h \(remainder) min" : "\(hours) h"
    }

    /// VoiceOver-friendly duration (`"19 minutes"`, `"1 hour 15 minutes"`).
    static func spokenDurationLabel(minutes rawMinutes: Double) -> String {
        guard rawMinutes >= 0.5 else { return "less than 1 minute" }
        let totalMinutes = Int(rawMinutes.rounded())
        let hours = totalMinutes / 60
        let remainder = totalMinutes % 60
        var parts: [String] = []
        if hours > 0 {
            parts.append(hours == 1 ? "1 hour" : "\(hours) hours")
        }
        if remainder > 0 {
            parts.append(remainder == 1 ? "1 minute" : "\(remainder) minutes")
        }
        return parts.joined(separator: " ")
    }

    static func plan(
        queues: [ReadingQueue],
        bucket: WhatFitsBucket,
        isVisible: (SavedWork) -> Bool,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        libraryWorks: [SavedWork]? = nil,
        tagAliases: TagAliasResolver? = nil
    ) -> WhatFitsPlan {
        let activeQueues = orderedActiveQueues(from: queues)
        var visibility: [ObjectIdentifier: Bool] = [:]
        func visible(_ work: SavedWork) -> Bool {
            let key = ObjectIdentifier(work)
            if let cached = visibility[key] { return cached }
            let result = isVisible(work)
            visibility[key] = result
            return result
        }
        let candidates = deduplicatedCandidates(
            in: activeQueues,
            libraryWorks: libraryWorks,
            tagAliases: tagAliases,
            isVisible: visible
        )

        var hasAnyVisibleWorks = false
        var hasAnyUnfinishedWorks = false
        var hasAnyWordCounts = false
        var hasHiddenMatureFits = false
        var timedCandidates: [TimedCandidate] = []
        var nonFittingMinutes: [Double] = []

        for (encounterOrder, candidate) in candidates.enumerated() {
            let work = candidate.work
            guard visible(work) else {
                if !hasHiddenMatureFits, !work.isFinished,
                   let minutes = ReadingQueueFacts.minutesLeft(for: work),
                   bucket.fits(minutes: minutes) {
                    hasHiddenMatureFits = true
                }
                continue
            }
            hasAnyVisibleWorks = true
            guard !work.isFinished else { continue }
            hasAnyUnfinishedWorks = true
            guard let minutes = ReadingQueueFacts.minutesLeft(for: work) else { continue }
            hasAnyWordCounts = true
            guard bucket.fits(minutes: minutes) else {
                nonFittingMinutes.append(minutes)
                continue
            }

            let section: WhatFitsEntry.Section = work.hasStartedReading
                ? .finishInThisSitting
                : .startAndFinish
            let isOffline = work.hasEPUB && fileExists(work.fileURL)
            timedCandidates.append(TimedCandidate(
                work: work,
                queueNames: candidate.queueNames,
                section: section,
                minutesLeft: minutes,
                isOffline: isOffline,
                encounterOrder: encounterOrder
            ))
        }

        let sorted = timedCandidates.sorted { lhs, rhs in
            if lhs.isOffline != rhs.isOffline { return lhs.isOffline }
            if abs(lhs.minutesLeft - rhs.minutesLeft) > 1e-6 {
                return lhs.minutesLeft < rhs.minutesLeft
            }
            return lhs.encounterOrder < rhs.encounterOrder
        }

        var finishInThisSitting: [WhatFitsEntry] = []
        var startAndFinish: [WhatFitsEntry] = []
        for candidate in sorted {
            let entry = WhatFitsEntry(
                work: candidate.work,
                section: candidate.section,
                minutesLeft: candidate.minutesLeft,
                isOffline: candidate.isOffline,
                queueNames: candidate.queueNames
            )
            switch entry.section {
            case .finishInThisSitting: finishInThisSitting.append(entry)
            case .startAndFinish: startAndFinish.append(entry)
            }
        }

        var nextFitting: (bucket: WhatFitsBucket, count: Int)? = nil
        if sorted.isEmpty && !nonFittingMinutes.isEmpty {
            for other in WhatFitsBucket.allCases where other != bucket {
                let count = nonFittingMinutes.count { other.fits(minutes: $0) }
                if count > 0 {
                    nextFitting = (other, count)
                    break
                }
            }
        }

        return WhatFitsPlan(
            queueCount: activeQueues.count,
            finishInThisSitting: finishInThisSitting,
            startAndFinish: startAndFinish,
            hasAnyVisibleWorks: hasAnyVisibleWorks,
            hasAnyUnfinishedWorks: hasAnyUnfinishedWorks,
            hasAnyWordCounts: hasAnyWordCounts,
            hasHiddenMatureFits: hasHiddenMatureFits,
            nextFittingBucket: nextFitting
        )
    }

    private static func orderedActiveQueues(from queues: [ReadingQueue]) -> [ReadingQueue] {
        queues
            .filter { !$0.isPendingDeletion }
            .sorted { lhs, rhs in
                // User queues (list and smart) before Saved for Later, then sort order.
                if lhs.isUserQueue != rhs.isUserQueue { return lhs.isUserQueue }
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    private static func deduplicatedCandidates(
        in queues: [ReadingQueue],
        libraryWorks: [SavedWork]?,
        tagAliases: TagAliasResolver?,
        isVisible: (SavedWork) -> Bool
    ) -> [Candidate] {
        var candidates: [Candidate] = []
        var indexByID: [UUID: Int] = [:]

        let hasSmartQueue = queues.contains { $0.kind == .smart }
        let smartSnapshot: ReadingQueueService.SmartLibrarySnapshot? = if hasSmartQueue {
            if let libraryWorks {
                ReadingQueueService.SmartLibrarySnapshot(
                    works: libraryWorks,
                    aliases: tagAliases ?? .empty
                )
            } else if let context = queues.first(where: { $0.kind == .smart })?.modelContext {
                ReadingQueueService.SmartLibrarySnapshot(in: context)
            } else {
                nil
            }
        } else {
            nil
        }

        for queue in queues {
            let queueWorks: [SavedWork] = if let smartSnapshot, queue.kind == .smart {
                smartSnapshot.matchingForWhatFits(queue, where: isVisible)
            } else {
                ReadingQueueService.orderedMemberships(in: queue).compactMap(\.work)
            }
            let name = queue.displayName
            for work in queueWorks where !work.isPendingDeletion {
                let id = work.id
                if let index = indexByID[id] {
                    candidates[index].addQueueName(name)
                } else {
                    indexByID[id] = candidates.count
                    candidates.append(Candidate(work: work, queueName: name))
                }
            }
        }

        return candidates
    }
}
