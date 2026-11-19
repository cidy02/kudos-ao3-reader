import Foundation

extension AO3Client {
    /// UserDefaults key for the 429 hold on the weekly saved-series check (T-519b).
    nonisolated static let savedSeriesHoldKey = "savedSeries.retryAfterUntil"

    /// Page 1 of `/series/<id>`, anonymous, for the weekly saved-series check: the shared slot, `pace()`, its own
    /// `feature=` tag and 429 hold. The caller spaces series 3 s apart (policy row "Saved series, weekly check").
    func savedSeriesFirstPage(seriesID: Int) async throws -> String {
        guard seriesID > 0, let url = URL(string: "https://archiveofourown.org/series/\(seriesID)") else {
            throw AO3Error.network("Invalid AO3 series ID.")
        }
        try Self.rejectIfUntrusted(url)
        try Self.throwIfSavedSeriesHeld()
        do {
            return try await AO3RequestCoordinator.shared.withSlot {
                try await pace()
                try Task.checkCancellation()
                try Self.throwIfSavedSeriesHeld()
                do {
                    var request = URLRequest(url: url)
                    request.httpShouldHandleCookies = false
                    request.setValue(AO3RequestDefaults.userAgent(feature: .savedSeriesChecks),
                                     forHTTPHeaderField: "User-Agent")
                    let (body, response) = try await session.data(for: request)
                    defer { Self.purgeSessionCookie(from: session.configuration.httpCookieStorage, url: url) }
                    try checkStatus(response) { body }
                    return Self.htmlString(from: body)
                } catch AO3Error.rateLimited(let retryAfter) {
                    let delay = retryAfter.flatMap { $0.isFinite ? max($0, 0) : nil } ?? 6 * 60 * 60
                    let until = Date().addingTimeInterval(delay)
                    let current = UserDefaults.standard.object(forKey: Self.savedSeriesHoldKey) as? Date ?? .distantPast
                    UserDefaults.standard.set(max(until, current), forKey: Self.savedSeriesHoldKey)
                    throw AO3Error.rateLimited(retryAfter: retryAfter)
                }
            }
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }
    }

    nonisolated static func throwIfSavedSeriesHeld(now: Date = Date()) throws {
        if let until = UserDefaults.standard.object(forKey: savedSeriesHoldKey) as? Date, until > now {
            throw AO3Error.rateLimited(retryAfter: until.timeIntervalSinceNow)
        }
    }
}
