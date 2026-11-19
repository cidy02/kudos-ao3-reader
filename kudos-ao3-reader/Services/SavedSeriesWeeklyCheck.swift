import Foundation
import SwiftData

/// T-519b (owner, 2026-11-18): each saved series is re-checked by itself about once a week, at its own slot in the
/// week so the checks are spread over the days and hours, most viewed first, and never for a series whose AO3
/// subscription notifications already arrive by mail. Settings › Library can turn the checks off; mail still applies.
@MainActor
enum SavedSeriesWeeklyCheck {
    static let enabledKey = "checksSavedSeriesWeekly"
    static let perPass = 3
    static let spacing: TimeInterval = 3
    /// Home must stay open this long before the first request, so a launch never fetches.
    static let settleDelay: TimeInterval = 30
    static let minimumAge: TimeInterval = 6 * 86_400

    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    /// The series' hour in the week (0..<168), from its AO3 id: stable across launches and devices
    /// (FNV-1a, not `hashValue`, which changes per launch).
    nonisolated static func homeSlot(seriesID: Int) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in String(seriesID).utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return Int(hash % 168)
    }

    /// The latest time at or before `now` that this series' slot came round. Calendar arithmetic, so a DST week
    /// keeps the slot at the same wall-clock hour.
    nonisolated static func lastSlotTime(seriesID: Int, now: Date, calendar: Calendar = .current) -> Date {
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let slot = homeSlot(seriesID: seriesID)
        func slotTime(in start: Date) -> Date {
            let day = calendar.date(byAdding: .day, value: slot / 24, to: start) ?? start
            return calendar.date(bySettingHour: slot % 24, minute: 0, second: 0, of: day) ?? day
        }
        let thisWeek = slotTime(in: weekStart)
        if thisWeek <= now { return thisWeek }
        let previousWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart
        return slotTime(in: previousWeek)
    }

    nonisolated static func isDue(seriesID: Int, checkedAt: Date, now: Date, calendar: Calendar = .current) -> Bool {
        now.timeIntervalSince(checkedAt) >= minimumAge
            && checkedAt < lastSlotTime(seriesID: seriesID, now: now, calendar: calendar)
    }

    /// Which series a pass checks: due, not covered by mail, most viewed first, oldest check breaking ties.
    static func plan(
        _ rows: [SavedSeries],
        isCoveredByMail: (SavedSeries) -> Bool,
        now: Date,
        calendar: Calendar = .current
    ) -> [SavedSeries] {
        rows.filter { !isCoveredByMail($0) && isDue(seriesID: $0.ao3SeriesID, checkedAt: $0.checkedAt, now: now,
                                                    calendar: calendar) }
            .sorted { ($0.viewCount, $1.checkedAt) > ($1.viewCount, $0.checkedAt) }
            .prefix(perPass)
            .map { $0 }
    }

    /// "Part 4 of …" in a notification's series line.
    nonisolated static func partNumber(in seriesLine: String?) -> Int? {
        guard let seriesLine, let match = seriesLine.firstMatch(of: #/Part\s+(\d+)\s+of\b/#) else { return nil }
        return Int(match.1).flatMap { $0 > 0 ? $0 : nil }
    }

    /// A series notification names the new work: record it without asking AO3. It says where the work sits ("Part
    /// N") and its words, never whether the series is now complete, so completion waits for the reader's next visit.
    static func applyMail(_ updates: [SubscriptionUpdate], in context: ModelContext, now: Date = Date()) {
        for update in updates {
            guard let seriesID = update.source.seriesID, seriesID > 0,
                  update.workID > 0, update.workID <= UInt64(Int.max) else { continue }
            let workID = Int(update.workID)
            let saved = SavedSeriesStore.series(for: seriesID, in: context) ?? {
                let created = SavedSeries(ao3SeriesID: seriesID, checkedAt: now)
                context.insert(created)
                return created
            }()
            saved.isSubscribed = true
            guard !saved.partWorkIDs.contains(workID) else { continue }
            let part = partNumber(in: update.series)
            if let part, part - 1 <= saved.partWorkIDs.count {
                saved.partWorkIDs.insert(workID, at: part - 1)
            } else if part == nil, saved.partWorkIDs.count == saved.partCount {
                saved.partWorkIDs.append(workID)
            }
            // A part beyond a list that is not whole leaves the list alone: it would claim to be complete.
            saved.partCount = max(saved.partCount, part ?? saved.partCount + 1, saved.partWorkIDs.count)
            if let words = update.words, words <= UInt64(Int.max) { saved.wordCount += Int(words) }
            saved.lastModifiedAt = now
        }
    }

    static func recordView(seriesID: Int?, in context: ModelContext, now: Date = Date()) {
        guard let seriesID, let saved = SavedSeriesStore.series(for: seriesID, in: context) else { return }
        saved.viewCount += 1
        saved.lastViewedAt = now
    }

    static func run(
        in context: ModelContext,
        mail: () -> (isConnected: Bool, updates: [SubscriptionUpdate]),
        isScreenActive: () -> Bool,
        defaults: UserDefaults = .standard,
        now: () -> Date = Date.init,
        sleep: (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
        isHeld: () async -> Bool = {
            (try? AO3Client.throwIfSavedSeriesHeld()) == nil ? true : await AO3Client.shared.isHeldForMaintenance
        },
        fetch: (Int) async throws -> String = { try await AO3Client.shared.savedSeriesFirstPage(seriesID: $0) }
    ) async {
        guard !Task.isCancelled, isScreenActive() else { return }
        applyMail(mail().updates, in: context, now: now())
        guard isEnabled(defaults) else { return }
        do { try await sleep(settleDelay) } catch { return }
        guard !Task.isCancelled, isScreenActive(), isEnabled(defaults) else { return }
        // Read mail again after the wait: notifications that arrived meanwhile count.
        let current = mail()
        applyMail(current.updates, in: context, now: now())
        let rows = (try? context.fetch(FetchDescriptor<SavedSeries>())) ?? []
        let picks = plan(rows, isCoveredByMail: { current.isConnected && $0.isSubscribed }, now: now())
        for (index, saved) in picks.enumerated() {
            if index > 0 { do { try await sleep(spacing) } catch { return } }
            // A hold is checked before any stamp, so a series is never marked checked without a request.
            guard !Task.isCancelled, isScreenActive(), isEnabled(defaults), !(await isHeld()) else { return }
            let seriesID = saved.ao3SeriesID
            do {
                let html = try await fetch(seriesID)
                // The header alone is worth keeping; the works list only fills `partWorkIDs`.
                let page = try? AO3Client.parseSearchPage(html, page: 1)
                let ids = page?.works.map(\.id) ?? []
                guard var parsed = AO3ParsedSeries.parse(
                    html: html, ao3SeriesID: seriesID, pageWorkIDs: ids, isWholeList: false
                ), parsed.partCount >= saved.partCount else {
                    // An anonymous view can count fewer works (restricted ones are hidden); keep what we had.
                    saved.checkedAt = now()
                    continue
                }
                // Whole only when one page lists every work the header counts (an anonymous view may list fewer).
                parsed.hasCompleteWorkList = (page?.totalPages ?? 2) <= 1 && ids.count == parsed.partCount
                SavedSeriesStore.upsert(parsed, in: context, now: now())
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                // Stamp the attempt so a failing series waits for its next slot; a hold or outage ends the pass.
                saved.checkedAt = now()
                if FollowedTagChecks.shouldStopPass(on: error) { return }
            }
        }
    }
}
