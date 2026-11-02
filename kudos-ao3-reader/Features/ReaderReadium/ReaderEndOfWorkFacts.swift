import Foundation
import SwiftData

/// Pure logic and formatting for the Reader's End of Work screen (board 34, T-496).
public enum ReaderEndOfWorkFacts {
    /// Heading: "The End" for completed works, "You're caught up" for WIPs.
    public static func heading(isComplete: Bool) -> String {
        isComplete ? "The End" : "You're caught up"
    }

    /// Formats logged reading time in minutes or hours and minutes: e.g. "1 h 20 min", "45 min".
    /// Nil when nothing was logged: the end card never invents a time.
    public static func durationString(seconds: Double) -> String? {
        guard seconds > 0 else { return nil }
        let totalMinutes = seconds >= 60 ? Int((seconds / 60).rounded()) : 1
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return minutes > 0 ? "\(hours) h \(minutes) min" : "\(hours) h"
        }
        return "\(totalMinutes) min"
    }

    /// Subtitle under the title on the End of Work screen, or nil when there is nothing to say.
    /// Logged time and finished: "Read in 1 h 20 min · moved to Finished"
    /// Logged time only: "Read in 1 h 20 min"
    /// Finished with no logged time: "Moved to Finished"
    public static func subtitle(durationSeconds: Double, isFinished: Bool) -> String? {
        let read = durationString(seconds: durationSeconds).map { "Read in \($0)" }
        switch (read, isFinished) {
        case let (read?, true): return "\(read) · moved to Finished"
        case let (read?, false): return read
        case (nil, true): return "Moved to Finished"
        case (nil, false): return nil
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
    /// Skips finished works, works pending deletion, and works ineligible under privacy;
    /// nil when nothing unfinished remains.
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
