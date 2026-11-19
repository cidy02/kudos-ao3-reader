import Foundation
import SwiftData

/// T-519b (owner, 2026-11-18): each saved series is re-checked by itself about once a week, at its own slot in the
/// week so the checks are spread over the days and hours, most viewed first, and never for a series whose AO3
/// subscription notifications already arrive by mail. Settings › Library can turn it off.
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

    /// The latest time at or before `now` that this series' slot came round.
    nonisolated static func lastSlotTime(seriesID: Int, now: Date, calendar: Calendar = .current) -> Date {
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let slot = weekStart.addingTimeInterval(Double(homeSlot(seriesID: seriesID)) * 3_600)
        return slot <= now ? slot : slot.addingTimeInterval(-7 * 86_400)
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

    /// A series notification names the new work: add it to the saved series without asking AO3. The email does
    /// not say where in the series the work sits or whether the series is now complete, so the work is appended
    /// and completion waits for the reader's next visit to the series.
    static func applyMail(_ updates: [SubscriptionUpdate], to rows: [SavedSeries], now: Date = Date()) {
        let byID = Dictionary(rows.map { ($0.ao3SeriesID, $0) }, uniquingKeysWith: { first, _ in first })
        for update in updates {
            guard let seriesID = update.source.seriesID, let saved = byID[seriesID],
                  update.workID > 0, update.workID <= UInt64(Int.max) else { continue }
            let workID = Int(update.workID)
            guard !saved.partWorkIDs.contains(workID) else { continue }
            saved.isSubscribed = true
            saved.partWorkIDs.append(workID)
            saved.partCount = max(saved.partCount, saved.partWorkIDs.count)
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
        isMailConnected: Bool,
        mailUpdates: [SubscriptionUpdate],
        isScreenActive: () -> Bool,
        defaults: UserDefaults = .standard,
        now: () -> Date = Date.init,
        sleep: (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
        fetch: (Int) async throws -> String = { try await AO3Client.shared.savedSeriesFirstPage(seriesID: $0) }
    ) async {
        guard isEnabled(defaults) else { return }
        let rows = (try? context.fetch(FetchDescriptor<SavedSeries>())) ?? []
        guard !rows.isEmpty else { return }
        applyMail(mailUpdates, to: rows, now: now())
        let mailSeries = Set(mailUpdates.compactMap(\.source.seriesID))
        let picks = plan(rows, isCoveredByMail: {
            isMailConnected && ($0.isSubscribed || mailSeries.contains($0.ao3SeriesID))
        }, now: now())
        guard !picks.isEmpty else { return }
        do { try await sleep(settleDelay) } catch { return }
        for (index, saved) in picks.enumerated() {
            if index > 0 { do { try await sleep(spacing) } catch { return } }
            guard !Task.isCancelled, isScreenActive(), isEnabled(defaults) else { return }
            let seriesID = saved.ao3SeriesID
            do {
                let html = try await fetch(seriesID)
                // The header alone is worth keeping; the works list only fills `partWorkIDs`.
                let page = try? AO3Client.parseSearchPage(html, page: 1)
                if let parsed = AO3ParsedSeries.parse(
                    html: html, ao3SeriesID: seriesID, pageWorkIDs: page?.works.map(\.id) ?? [],
                    isWholeList: (page?.totalPages ?? 2) <= 1
                ) {
                    SavedSeriesStore.upsert(parsed, in: context, now: now())
                } else {
                    saved.checkedAt = now()
                }
            } catch is CancellationError {
                return
            } catch {
                // Stamp the attempt so a failing series waits for its next slot; a hold or outage ends the pass.
                saved.checkedAt = now()
                if FollowedTagChecks.shouldStopPass(on: error) { return }
            }
        }
    }
}
