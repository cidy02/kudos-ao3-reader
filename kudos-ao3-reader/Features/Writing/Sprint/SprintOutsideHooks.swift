import Foundation
#if os(iOS)
import ActivityKit
import WidgetKit
#endif

/// What a sprint tells the system outside the app (T-576e): the Live Activity and the Lock Screen widget's count. The
/// editor passes `.system`; tests leave it out, so they never start a real Live Activity.
@MainActor
struct SprintOutsideHooks {
    var started: (SprintState) -> Void
    var progressed: (SprintState) -> Void
    var finished: (SprintResult) -> Void

    static let system = SprintOutsideHooks(
        started: { state in
            #if os(iOS)
            SprintLiveActivityController.start(state)
            #endif
        },
        progressed: { state in
            #if os(iOS)
            SprintLiveActivityController.update(words: state.words, endsAt: state.endsAt)
            #endif
        },
        finished: { result in
            #if os(iOS)
            SprintLiveActivityController.end(words: result.words)
            #endif
            KudosWidgetBridge.noteSprint(words: result.words, at: result.endedAt)
        }
    )
}

/// Keeps the Lock Screen widget's snapshot (`KudosShared/KudosWidgetSnapshot.swift`) current.
@MainActor
enum KudosWidgetBridge {
    static func noteEditing(work: String, chapter: String) {
        let work = work.trimmingCharacters(in: .whitespacesAndNewlines)
        let chapter = chapter.trimmingCharacters(in: .whitespacesAndNewlines)
        reload(if: KudosWidgetSnapshotStore.update(at: KudosAppGroup.snapshotURL) {
            $0.workTitle = work.isEmpty ? nil : work
            $0.chapterTitle = chapter.isEmpty ? nil : chapter
        })
    }

    static func noteSprint(words: Int, at date: Date) {
        reload(if: KudosWidgetSnapshotStore.update(at: KudosAppGroup.snapshotURL) { $0.addSprint(words: words, at: date) })
    }

    private static func reload(if changed: Bool) {
        #if os(iOS)
        if changed { WidgetCenter.shared.reloadTimelines(ofKind: "KudosWriting") }
        #endif
    }
}

#if os(iOS)
/// Starts, updates and ends the sprint Live Activity. Quiet when the writer has Live Activities off.
@MainActor
enum SprintLiveActivityController {
    private static var activity: Activity<SprintActivityAttributes>?
    private static var lastWords = 0
    private static var lastUpdate = Date.distantPast
    /// The countdown runs on its own; the word count needs no more than this.
    static let updateInterval: TimeInterval = 5

    static func start(_ state: SprintState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end(words: nil) // one sprint at a time
        let content = ActivityContent(
            state: SprintActivityAttributes.ContentState(words: 0, endsAt: state.endsAt, isFinished: false),
            staleDate: state.endsAt
        )
        let attributes = SprintActivityAttributes(startedAt: state.startedAt, plannedMinutes: state.plannedMinutes)
        activity = try? Activity.request(attributes: attributes, content: content)
        lastWords = 0
        lastUpdate = Date()
    }

    static func update(words: Int, endsAt: Date, now: Date = Date()) {
        guard let activity, words != lastWords, now.timeIntervalSince(lastUpdate) >= updateInterval else { return }
        lastWords = words
        lastUpdate = now
        let content = ActivityContent(
            state: SprintActivityAttributes.ContentState(words: words, endsAt: endsAt, isFinished: false),
            staleDate: endsAt
        )
        Task { await activity.update(content) }
    }

    /// Shows the final count for a few minutes, then goes.
    static func end(words: Int?) {
        guard let activity else { return }
        self.activity = nil
        let content = ActivityContent(
            state: SprintActivityAttributes.ContentState(words: words ?? lastWords, endsAt: Date(), isFinished: true),
            staleDate: nil
        )
        Task { await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(5 * 60))) }
    }
}
#endif
