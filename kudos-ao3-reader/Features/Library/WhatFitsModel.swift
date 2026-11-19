import Foundation

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
        let queueNames: [String]
        let encounterOrder: Int
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
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> WhatFitsPlan {
        let activeQueues = orderedActiveQueues(from: queues)
        let candidates = deduplicatedCandidates(in: activeQueues)

        var hasAnyVisibleWorks = false
        var hasAnyUnfinishedWorks = false
        var hasAnyWordCounts = false
        var hasHiddenMatureFits = false
        var timedCandidates: [TimedCandidate] = []

        for candidate in candidates {
            let work = candidate.work
            guard isVisible(work) else {
                if !work.isFinished,
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
                encounterOrder: candidate.encounterOrder
            ))
        }

        let matching = timedCandidates.filter { bucket.fits(minutes: $0.minutesLeft) }
        let sorted = matching.sorted { lhs, rhs in
            if lhs.isOffline != rhs.isOffline { return lhs.isOffline }
            if abs(lhs.minutesLeft - rhs.minutesLeft) > 1e-6 {
                return lhs.minutesLeft < rhs.minutesLeft
            }
            return lhs.encounterOrder < rhs.encounterOrder
        }

        let entries = sorted.map {
            WhatFitsEntry(
                work: $0.work,
                section: $0.section,
                minutesLeft: $0.minutesLeft,
                isOffline: $0.isOffline,
                queueNames: $0.queueNames
            )
        }
        let finishInThisSitting = entries.filter { $0.section == .finishInThisSitting }
        let startAndFinish = entries.filter { $0.section == .startAndFinish }

        let nextFitting: (bucket: WhatFitsBucket, count: Int)?
        if entries.isEmpty && !timedCandidates.isEmpty {
            nextFitting = WhatFitsBucket.allCases
                .filter { $0 != bucket }
                .compactMap { candidateBucket -> (WhatFitsBucket, Int)? in
                    let count = timedCandidates.count { candidateBucket.fits(minutes: $0.minutesLeft) }
                    return count > 0 ? (candidateBucket, count) : nil
                }
                .first
        } else {
            nextFitting = nil
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

    private static func deduplicatedCandidates(in queues: [ReadingQueue]) -> [Candidate] {
        var orderedIDs: [UUID] = []
        var workByID: [UUID: SavedWork] = [:]
        var queueNamesByID: [UUID: [String]] = [:]

        for queue in queues {
            // `orderedWorks` is the membership list for a manual queue and the
            // computed matches for a smart one. A work is still counted once.
            for work in ReadingQueueService.orderedWorks(in: queue) where !work.isPendingDeletion {
                if workByID[work.id] == nil {
                    orderedIDs.append(work.id)
                    workByID[work.id] = work
                }
                var names = queueNamesByID[work.id, default: []]
                let name = queue.displayName
                if !names.contains(name) {
                    names.append(name)
                    queueNamesByID[work.id] = names
                }
            }
        }

        return orderedIDs.enumerated().compactMap { index, id in
            guard let work = workByID[id] else { return nil }
            return Candidate(
                work: work,
                queueNames: queueNamesByID[id, default: []],
                encounterOrder: index
            )
        }
    }
}
