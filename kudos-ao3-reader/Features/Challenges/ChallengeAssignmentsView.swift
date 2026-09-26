import SwiftUI

/// Artboard **1cb** — Assignments.
///
/// The maintainer's read of a Gift Exchange's matching pass: who is matched, whose
/// giver defaulted with no cover yet, and who is covering as a pinch hitter. Does not apply to
/// Prompt Meme (1cc), which has no matching step at all.
///
/// Matching is AO3's own algorithm (`potential_matches#generate`) and there is no
/// maintainer-side client write to request a pinch hit — only `claimPinchHit`
/// exists, and that is the *participant* side of claiming a pinch hit AO3 has
/// already opened. So both actions on an unmatched pair's card — "Send pinch-hit
/// request" and "Open on AO3" — are the same Open-on-AO3 escape hatch to AO3's own
/// assignments/pinch-hits page, not two different native writes.
struct ChallengeAssignmentsView: View {
    let collectionSlug: String
    var collectionTitle: String = ""

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(AppRouter.self) private var router

    @State private var matched: [AO3ChallengeAssignment] = []
    @State private var unmatched: [AO3ChallengeAssignment] = []
    @State private var pinchHits: [AO3ChallengeAssignment] = []
    /// A list whose fetch failed shows its error, never an empty-state claim.
    @State private var loadErrors: [Segment: String] = [:]
    /// Works-due is challenge-wide, not per-assignment, so it is read once off the
    /// settings form (`AO3ChallengeSettings.worksDueAt`) rather than invented per row.
    @State private var worksDueAt: AO3ChallengeInstant?
    /// Unmatched leads: it is the only part a moderator has to act on.
    @State private var segment: Segment = .unmatched
    @State private var phase: Phase = .idle
    @State private var itemInFlight: Int?
    @State private var actionErrorMessage: String?

    private enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private enum Segment: String, CaseIterable, Hashable {
        case matched
        case unmatched
        case pinchHits

        var title: String {
            switch self {
            case .matched: "Matched"
            case .unmatched: "Unmatched"
            case .pinchHits: "Pinch hits"
            }
        }
    }

    private var gutter: CGFloat { SubjectMetrics.accountGutter }
    private var selfGuttered: CGFloat { 0 }

    private var palette: SubjectPalette {
        theme.appTheme.subjectPalette(hue: CoverArt.workHue(fandoms: [], title: effectiveTitle))
    }

    private var effectiveTitle: String { collectionTitle.isEmpty ? collectionSlug : collectionTitle }

    var body: some View {
        List {
            Section {
                header.pageBodyRow(top: 20, gutter: selfGuttered)
                segmentStrip.pageBodyRow(top: 14, gutter: gutter)
            }

            switch phase {
            case .loading:
                Section { loadingRow.pageBodyRow(top: 20, gutter: gutter) }
            case let .failed(message):
                Section { failureCard(message).pageBodyRow(top: 14, gutter: gutter) }
            case .idle, .loaded:
                contentSections
            }
        }
        .cardList()
        #if os(macOS)
        .navigationTitle("Assignments")
        #endif
        .subjectScreenWash(palette: palette)
        .task { await loadIfNeeded() }
        .refreshable { await load() }
    }

    // MARK: - Header

    private var header: some View {
        SubjectHeaderBlock(
            kicker: effectiveTitle,
            title: "Assignments",
            subtitle: subtitleLine,
            palette: palette,
            gutter: SubjectMetrics.accountGutter
        )
    }

    private var subtitleLine: String {
        var parts: [String] = []
        if phase == .loaded {
            if loadErrors[.matched] == nil { parts.append("\(matched.count) matched") }
            if loadErrors[.unmatched] == nil { parts.append("\(unmatched.count) unmatched") }
        }
        if let date = worksDueAt?.date {
            parts.append("works due \(mediumDate(date))")
        }
        return parts.joined(separator: " · ")
    }

    private var segmentStrip: some View {
        SubjectSegmentedControl(options: Segment.allCases, title: \.title, selection: $segment)
    }

    // MARK: - Content Sections

    @ViewBuilder
    private var contentSections: some View {
        if let actionErrorMessage {
            Section {
                actionErrorCard(actionErrorMessage).pageBodyRow(top: 8, gutter: gutter)
            }
        }

        switch segment {
        case .matched: matchedSection
        case .unmatched: unmatchedSection
        case .pinchHits: pinchHitsSection
        }

        Section {
            footnote.pageBodyRow(top: 8, gutter: gutter)
        }
    }

    private var matchedSection: some View {
        Section {
            SectionRuleHeader(title: "Matched", count: matched.count)
                .pageBodyRow(top: 18, gutter: selfGuttered)
            if let error = loadErrors[.matched] {
                failureCard(error, title: "Couldn't load matched assignments").pageBodyRow(top: 8, gutter: gutter)
            } else if matched.isEmpty {
                emptyCard("No matched assignments yet.").pageBodyRow(top: 8, gutter: gutter)
            } else {
                assignmentRows(matched).pageBodyRow(top: 8, gutter: gutter)
            }
        }
    }

    private var pinchHitsSection: some View {
        Section {
            SectionRuleHeader(title: "Pinch hits", count: pinchHits.count)
                .pageBodyRow(top: 18, gutter: selfGuttered)
            if let error = loadErrors[.pinchHits] {
                failureCard(error, title: "Couldn't load pinch hits").pageBodyRow(top: 8, gutter: gutter)
            } else if pinchHits.isEmpty {
                emptyCard("No pinch hits open right now.").pageBodyRow(top: 8, gutter: gutter)
            } else {
                assignmentRows(pinchHits).pageBodyRow(top: 8, gutter: gutter)
            }
        }
    }

    private var unmatchedSection: some View {
        Section {
            SectionRuleHeader(title: "Unmatched sign-ups", count: unmatched.count)
                .pageBodyRow(top: 18, gutter: selfGuttered)
            if let error = loadErrors[.unmatched] {
                failureCard(error, title: "Couldn't load defaults").pageBodyRow(top: 8, gutter: gutter)
            } else if unmatched.isEmpty {
                emptyCard("No defaulted assignments are waiting for a pinch hitter.")
                    .pageBodyRow(top: 8, gutter: gutter)
            } else {
                unmatchedCards.pageBodyRow(top: 8, gutter: gutter)
            }
        }
    }

    // MARK: - Matched / Pinch hits rows

    private func assignmentRows(_ rows: [AO3ChallengeAssignment]) -> some View {
        VStack(spacing: 9) {
            ForEach(rows) { assignment in
                assignmentRow(assignment)
            }
        }
    }

    private func assignmentRow(_ assignment: AO3ChallengeAssignment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(displayName(assignment.requestPseud)) → \(giverDisplay(for: assignment))")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let secondary = secondaryLine(for: assignment) {
                    Text(secondary)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 8) {
                statusBadge(for: assignment)
                if segment == .pinchHits, assignment.pinchHitterPseud.isEmpty {
                    claimButton(for: assignment)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .subjectCard(palette: palette)
    }

    private func displayName(_ pseud: String) -> String {
        pseud.isEmpty ? "An anonymous sign-up" : pseud
    }

    /// The pinch hitter covers when one has claimed; otherwise the original
    /// giver; otherwise the slot is still open.
    private func giverDisplay(for assignment: AO3ChallengeAssignment) -> String {
        if !assignment.pinchHitterPseud.isEmpty { return assignment.pinchHitterPseud }
        if !assignment.offerPseud.isEmpty { return assignment.offerPseud }
        return "Unclaimed"
    }

    @ViewBuilder
    private func statusBadge(for assignment: AO3ChallengeAssignment) -> some View {
        switch assignment.badge(dueAt: worksDueAt?.date) {
        case .delivered: badge("Delivered", color: .green)
        case .late: badge("Late", color: .secondary)
        case .defaulted: badge("Defaulted", color: .orange)
        case nil: EmptyView()
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.opacity(0.16))
                    .overlay(Capsule().strokeBorder(color.opacity(0.34), lineWidth: 0.5))
            )
    }

    /// "Assigned <date> · due <date>", each half dropped when its date is
    /// unknown. `sentAt` is the only per-assignment date the model carries —
    /// there is no separate "assigned at" field, so it stands in for it rather
    /// than a date being invented.
    private func secondaryLine(for assignment: AO3ChallengeAssignment) -> String? {
        var parts: [String] = []
        if let sentAt = assignment.sentAt {
            parts.append("Assigned \(mediumDate(sentAt))")
        }
        if let due = worksDueAt?.date {
            parts.append("due \(mediumDate(due))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func claimButton(for assignment: AO3ChallengeAssignment) -> some View {
        let isInFlight = itemInFlight == assignment.id
        return Button {
            Task { await claimPinchHit(assignment) }
        } label: {
            HStack(spacing: 4) {
                if isInFlight {
                    ProgressView().controlSize(.small)
                }
                Text("Claim")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(palette.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(palette.accent.opacity(0.16))
                    .overlay(Capsule().strokeBorder(palette.accent.opacity(0.32), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
        .disabled(itemInFlight != nil)
    }

    // MARK: - Unmatched cards

    /// AO3's defaults queue lists one stuck request per row, not a pairing. The
    /// spec draws two names per card, so consecutive rows are grouped two at a
    /// time for layout only; an odd one out gets the singular copy. Truly
    /// unmatched sign-ups live on potential_matches, which nothing parses, so
    /// the copy says what the defaults list proves: a giver defaulted and no
    /// pinch hitter has covered it.
    private var unmatchedPairs: [[String]] {
        let names = unmatched.map { displayName($0.requestPseud) }
        return stride(from: 0, to: names.count, by: 2).map { Array(names[$0..<min($0 + 2, names.count)]) }
    }

    private var unmatchedCards: some View {
        VStack(spacing: 9) {
            ForEach(Array(unmatchedPairs.enumerated()), id: \.offset) { _, pair in
                unmatchedCard(pair)
            }
        }
    }

    private func unmatchedCard(_ pair: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(pair.count == 2 ? "Two sign-ups lost their giver" : "One sign-up lost its giver")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            Text(unmatchedProse(pair))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                openOnAO3Button(title: "Send pinch-hit request", tint: palette.accent)
                openOnAO3Button(title: "Open on AO3", tint: .secondary)
            }
        }
        .padding(14)
        .subjectCard(palette: palette)
    }

    private func unmatchedProse(_ pair: [String]) -> String {
        let lead = pair.count == 2
            ? "The givers for \(pair[0]) and \(pair[1]) defaulted, and no pinch hitter has covered them yet."
            : "The giver for \(pair[0]) defaulted, and no pinch hitter has covered it yet."
        return lead + " AO3 runs matching on its side, so the fix is either a pinch hit or a manual assignment there."
    }

    /// Neither label is a native write — there is no maintainer-side "request a
    /// pinch hit" endpoint, only the participant-side `claimPinchHit`. Both open
    /// AO3's own assignments page with the pinch-hits filter, per the file's own
    /// header note.
    private func openOnAO3Button(title: String, tint: Color) -> some View {
        Button {
            router.open(AO3ChallengeURL.assignments(slug: collectionSlug, list: .pinchHits))
        } label: {
            Label(title, systemImage: "safari")
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .tint(tint)
    }

    /// The spec's footnote also says the app can report a default and send a
    /// pinch-hit request; neither is a native write here yet, so it doesn't.
    private var footnote: some View {
        Text("Assignments and pinch hits are paged lists, and the app reads every page. "
            + "A pinch-hit request opens AO3, and the app cannot run AO3’s matching, so no screen here offers to.")
            .font(.system(size: 11.5))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    // MARK: - State Cards

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading assignments…")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }

    private func emptyCard(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .subjectPanel()
    }

    private func failureCard(_ message: String, title: String = "Couldn't load assignments") -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await load() }
            }
            .buttonStyle(.bordered)
            .tint(palette.accent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .subjectPanel()
    }

    private func actionErrorCard(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color.red)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                actionErrorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .subjectPanel()
    }

    // MARK: - Helpers & Actions

    private func mediumDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func loadIfNeeded() async {
        guard phase == .idle else { return }
        await load()
    }

    private func load() async {
        guard auth.isLoggedIn else {
            phase = .failed("Sign in to AO3 to view assignments.")
            return
        }
        phase = .loading
        loadErrors = [:]

        // Matched is every sent assignment: otwarchive's Complete (?fulfilled)
        // plus Open (?unfulfilled). Each list fails on its own.
        matched = await allPages(of: [.assignments, .unfulfilled], for: .matched)
        unmatched = await allPages(of: [.defaults], for: .unmatched)
        pinchHits = await allPages(of: [.pinchHits], for: .pinchHits)

        // Works-due is read off the owner-only settings form, best-effort: a
        // failure just leaves the header/rows without a due date (and no "late").
        if let request = try? auth.authenticatedRequest(
            for: AO3ChallengeURL.giftExchangeEdit(slug: collectionSlug)
        ), let form = try? await AO3Client.shared.challengeSettings(slug: collectionSlug, request: request) {
            worksDueAt = form.settings.worksDueAt
        }

        phase = .loaded
    }

    private func allPages(
        of lists: [AO3ChallengeAssignmentList], for segment: Segment
    ) async -> [AO3ChallengeAssignment] {
        do {
            let request = try auth.authenticatedRequest(
                for: AO3ChallengeURL.assignments(slug: collectionSlug, list: lists[0])
            )
            return try await AO3Client.shared.allChallengeAssignments(
                slug: collectionSlug, lists: lists, request: request
            )
        } catch {
            loadErrors[segment] = error.localizedDescription
            return []
        }
    }

    private func claimPinchHit(_ assignment: AO3ChallengeAssignment) async {
        itemInFlight = assignment.id
        actionErrorMessage = nil
        do {
            let byline = auth.username ?? ""
            try await auth.claimPinchHit(slug: collectionSlug, assignmentID: assignment.id, byline: byline)
            if let index = pinchHits.firstIndex(where: { $0.id == assignment.id }) {
                withAnimation {
                    pinchHits[index].pinchHitterPseud = byline
                }
            }
        } catch {
            actionErrorMessage = "Couldn't claim that pinch hit: \(error.localizedDescription)"
        }
        itemInFlight = nil
    }
}
