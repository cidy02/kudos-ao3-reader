import Foundation
import SwiftData

/// Pure logic and formatting for the Reader's End of Work screen (board 34, T-496).
public enum ReaderEndOfWorkFacts {
    /// Heading: "The End" for completed works, "You're caught up" for WIPs.
    public static func heading(isComplete: Bool) -> String {
        isComplete ? "The End" : "You're caught up"
    }

    /// Formats a reading duration in minutes or hours and minutes: e.g. "1 h 20 min", "45 min".
    public static func durationString(seconds: Double, wordCount: Int = 0) -> String {
        let positiveSeconds = max(0, seconds)
        let totalMinutes: Int
        if positiveSeconds >= 60 {
            totalMinutes = Int((positiveSeconds / 60).rounded())
        } else if positiveSeconds > 0 {
            totalMinutes = 1
        } else if wordCount > 0 {
            // Fall back to silent reading estimate (~200 wpm)
            totalMinutes = max(1, Int((Double(wordCount) / 200).rounded()))
        } else {
            totalMinutes = 1
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return minutes > 0 ? "\(hours) h \(minutes) min" : "\(hours) h"
        } else {
            return "\(totalMinutes) min"
        }
    }

    /// Subtitle under the title on the End of Work screen.
    /// Complete: "Read in 1 h 20 min · moved to Finished"
    /// WIP: "Read in 1 h 20 min"
    public static func subtitle(durationSeconds: Double, wordCount: Int = 0, isComplete: Bool) -> String {
        let dur = durationString(seconds: durationSeconds, wordCount: wordCount)
        if isComplete {
            return "Read in \(dur) · moved to Finished"
        } else {
            return "Read in \(dur)"
        }
    }

    /// Reading time estimate for a work: "about 50 min" or "about 1 h 20 min".
    public static func readingTimeEstimate(wordCount: Int) -> String {
        ReadingQueueFacts.readingTimeEstimate(wordCount: wordCount) ?? "about 1 min"
    }

    /// Next work metadata line: "author · 12,400 words · about 50 min"
    public static func nextWorkMeta(author: String, wordCount: Int) -> String {
        var parts: [String] = []
        let trimmedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAuthor.isEmpty {
            parts.append(trimmedAuthor)
        }
        if wordCount > 0 {
            let formattedWords = NumberFormatter.localizedString(from: NSNumber(value: wordCount), number: .decimal)
            parts.append("\(formattedWords) words")
            parts.append(readingTimeEstimate(wordCount: wordCount))
        }
        return parts.joined(separator: " · ")
    }

    /// Next work in the queue relative to the current work.
    /// Filters out deleted works, works pending deletion, and works ineligible under privacy.
    public static func nextWorkInQueue(
        orderedWorks: [SavedWork],
        currentWorkID: UUID,
        isEligible: (SavedWork) -> Bool = { _ in true }
    ) -> SavedWork? {
        guard let currentIndex = orderedWorks.firstIndex(where: { $0.id == currentWorkID }) else {
            return nil
        }
        let candidate: (SavedWork) -> Bool = {
            $0.id != currentWorkID && !$0.isPendingDeletion && isEligible($0)
        }
        let after = orderedWorks.suffix(from: currentIndex + 1)
        if let nextUnfinished = after.first(where: { candidate($0) && !$0.isFinished }) {
            return nextUnfinished
        }
        let before = orderedWorks.prefix(upTo: currentIndex)
        if let prevUnfinished = before.first(where: { candidate($0) && !$0.isFinished }) {
            return prevUnfinished
        }
        if let nextAny = after.first(where: candidate) {
            return nextAny
        }
        return nil
    }

    /// Finds candidate next work from the active queues containing `work`.
    /// Prefers custom/specific queues over generic `savedForLater`.
    @MainActor
    public static func findUpNext(
        for work: SavedWork,
        isEligible: (SavedWork) -> Bool = { _ in true }
    ) -> (queueName: String, nextWork: SavedWork)? {
        let sortedMemberships = work.activeQueueMemberships.sorted { m1, m2 in
            let q1Later = m1.queue?.kind == .savedForLater ? 1 : 0
            let q2Later = m2.queue?.kind == .savedForLater ? 1 : 0
            return q1Later < q2Later
        }
        for membership in sortedMemberships {
            guard let queue = membership.queue, !queue.isPendingDeletion else { continue }
            let ordered = ReadingQueueService.orderedWorks(in: queue)
            if let next = nextWorkInQueue(orderedWorks: ordered, currentWorkID: work.id, isEligible: isEligible) {
                return (queue.displayName, next)
            }
        }
        return nil
    }
}
