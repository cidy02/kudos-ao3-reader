import SwiftUI

/// Artboard **1cb** — Assignments.
///
/// The maintainer's read of a Gift Exchange's matching pass: who is matched, whose
/// giver defaulted with no cover yet, and who is covering as a pinch hitter. Does not apply to
/// Prompt Meme (1cc), which has no matching step at all.
///
/// Matching is AO3's own algorithm (`potential_matches#generate`), and AO3 has no
/// "request a pinch hit" write — asking for volunteers happens off-site — so both
/// actions on an unmatched card open AO3's own assignments page. The bottom bar's
/// two writes are the owner's fields on that page (`update_multiple`): a Default
/// box on an open assignment and a Pinch Hitter name on a defaulted one, each
/// behind a picker and a confirmation.
struct ChallengeAssignmentsView: View {
    let collectionSlug: String
    var collectionTitle: String = ""
    var viewerIsOwner: Bool

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .body) private var rowTitleSize: CGFloat = 14.5
    @ScaledMetric(relativeTo: .headline) private var cardTitleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .subheadline) private var buttonLabelSize: CGFloat = 14
    @ScaledMetric(relativeTo: .subheadline) private var loadingSize: CGFloat = 14
    @ScaledMetric(relativeTo: .footnote) private var bodySize: CGFloat = 12.5
    @ScaledMetric(relativeTo: .footnote) private var failureBodySize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 11.5
    @ScaledMetric(relativeTo: .caption) private var pillLabelSize: CGFloat = 12

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
    /// Which assignment list the bottom bar's picker is choosing from.
    @State private var picking: WriteKind?
    /// A chosen write awaiting its confirmation.
    @State private var pendingWrite: PendingWrite?
    /// The AO3 session the lists were read under; a write under another is refused.
    @State private var loadedGeneration: Int?
    @State private var loadGeneration = 0

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
        ZStack(alignment: .bottom) {
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

                // Room for the floating bottom bar.
                Section {
                    Spacer(minLength: 70)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .cardList()
            // Rows at their own padding, not the List minimum (L3-FORM-1).
            .environment(\.defaultMinListRowHeight, 0)
            #if os(macOS)
            .navigationTitle("Assignments")
            #endif
            .subjectScreenWash(palette: palette)

            if auth.isLoggedIn, phase == .loaded,
               AO3CollectionOwnerControls.areVisible(viewerIsOwner: viewerIsOwner) {
                bottomActionBar
            }
        }
        .task(id: auth.sessionGeneration) { await load() }
        .refreshable { await load() }
        .confirmationDialog(
            picking?.title ?? "",
            isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
            titleVisibility: .visible,
            presenting: picking
        ) { kind in
            ForEach(candidates(for: kind)) { assignment in
                Button(candidateLabel(assignment)) {
                    pendingWrite = PendingWrite(kind: kind, assignment: assignment)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            pendingWrite?.kind.confirmTitle ?? "",
            isPresented: Binding(get: { pendingWrite != nil }, set: { if !$0 { pendingWrite = nil } }),
            presenting: pendingWrite
        ) { write in
            Button(write.kind.confirmButton, role: write.kind == .reportDefault ? .destructive : nil) {
                Task { await perform(write) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { write in
            Text(confirmationMessage(write))
        }
            .screenTint(palette)
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
        if let due = worksDueAt?.dateText {
            parts.append("works due \(due)")
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

    private var pinchHitRows: [AO3PinchHitRow] {
        AO3PinchHitRow.rows(open: unmatched, claimed: pinchHits)
    }

    private var pinchHitsSection: some View {
        Section {
            SectionRuleHeader(title: "Pinch hits", count: pinchHitRows.count)
                .pageBodyRow(top: 18, gutter: selfGuttered)
            if let error = loadErrors[.pinchHits] ?? loadErrors[.unmatched] {
                failureCard(error, title: "Couldn't load pinch hits").pageBodyRow(top: 8, gutter: gutter)
            } else if pinchHitRows.isEmpty {
                emptyCard("No pinch hits open right now.").pageBodyRow(top: 8, gutter: gutter)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(pinchHitRows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { SubjectRowSeparator() }
                        pinchHitRow(row)
                    }
                }
                .subjectPanel()
                .pageBodyRow(top: 8, gutter: gutter)
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
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, assignment in
                if index > 0 { SubjectRowSeparator() }
                assignmentRow(assignment)
            }
        }
        .subjectPanel()
    }

    private func assignmentRow(_ assignment: AO3ChallengeAssignment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(displayName(assignment.requestPseud)) → \(giverDisplay(for: assignment))")
                    .font(.system(size: rowTitleSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)

                if let secondary = secondaryLine(for: assignment) {
                    Text(secondary)
                        .font(.system(size: captionSize))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            statusBadge(for: assignment)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
        switch assignment.badge(dueAt: worksDueAt?.instant) {
        case .delivered: badge("Delivered", color: .green)
        case .late: badge("Late", color: .secondary)
        case .defaulted: badge("Defaulted", color: .orange)
        case nil: EmptyView()
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .lineLimit(1)
            .fixedSize()
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
        if let due = worksDueAt?.dateText {
            parts.append("due \(due)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func claimButton(for assignment: AO3ChallengeAssignment) -> some View {
        let isInFlight = itemInFlight == assignment.id
        return Button {
            pendingWrite = PendingWrite(kind: .claimPinchHit, assignment: assignment)
        } label: {
            HStack(spacing: 4) {
                if isInFlight {
                    ProgressView().controlSize(.small)
                }
                Text("Claim")
                    .font(.system(size: pillLabelSize, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
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
                .font(.system(size: cardTitleSize, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(unmatchedProse(pair))
                .font(.system(size: bodySize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Both buttons opened the same AO3 page; one says what it does. The
            // pinch-hit request itself is made on AO3 (1cb).
            openOnAO3Button(title: "Open on AO3", tint: .secondary)
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

    /// Neither label is a native write — AO3 has no "request a pinch hit"
    /// endpoint. Both open AO3's own assignments page with the pinch-hits
    /// filter, per the file's own header note.
    private func openOnAO3Button(title: String, tint: Color) -> some View {
        Button {
            router.open(AO3ChallengeURL.assignments(slug: collectionSlug, list: .pinchHits))
        } label: {
            Label(title, systemImage: "safari")
                .font(.system(size: pillLabelSize, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .tint(tint)
    }

    /// The spec's footnote also says the app can report a default and send a
    /// pinch-hit request; neither is a native write here yet, so it doesn't.
    private var footnote: some View {
        Text("Assignments and pinch hits are paged lists. The app reads them, reports a default and "
            + "claims a pinch hit; a pinch-hit request opens AO3, and it cannot run AO3’s matching, "
            + "so no screen here offers to.")
            .font(.system(size: captionSize))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
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

    private func load() async {
        loadGeneration = AO3CollectionSessionReload.nextLoadGeneration(loadGeneration)
        let capturedLoadGeneration = loadGeneration
        let capturedSessionGeneration = auth.sessionGeneration
        clearLoadedState()
        guard auth.isLoggedIn else {
            phase = .failed("Sign in to AO3 to view assignments.")
            return
        }
        phase = .loading

        // Matched is every sent assignment: otwarchive's Complete (?fulfilled)
        // plus Open (?unfulfilled). Each list fails on its own.
        let matchedResult = await allPages(of: AO3ChallengeAssignmentList.sent)
        guard shouldApply(capturedLoadGeneration, capturedSessionGeneration) else { return }
        matched = matchedResult.rows
        if let error = matchedResult.error { loadErrors[.matched] = error }

        let unmatchedResult = await allPages(of: [.defaults])
        guard shouldApply(capturedLoadGeneration, capturedSessionGeneration) else { return }
        unmatched = unmatchedResult.rows
        if let error = unmatchedResult.error { loadErrors[.unmatched] = error }

        let pinchHitResult = await allPages(of: [.pinchHits])
        guard shouldApply(capturedLoadGeneration, capturedSessionGeneration) else { return }
        pinchHits = pinchHitResult.rows
        if let error = pinchHitResult.error { loadErrors[.pinchHits] = error }

        // Works-due is read off the owner-only settings form, best-effort: a
        // failure just leaves the header/rows without a due date (and no "late").
        if let request = try? auth.authenticatedRequest(
            for: AO3ChallengeURL.giftExchangeEdit(slug: collectionSlug)
        ), let form = try? await AO3Client.shared.challengeSettings(slug: collectionSlug, request: request) {
            guard shouldApply(capturedLoadGeneration, capturedSessionGeneration) else { return }
            worksDueAt = form.settings.worksDueAt
        }

        guard shouldApply(capturedLoadGeneration, capturedSessionGeneration) else { return }
        loadedGeneration = capturedSessionGeneration
        phase = .loaded
    }

    private func allPages(
        of lists: [AO3ChallengeAssignmentList]
    ) async -> (rows: [AO3ChallengeAssignment], error: String?) {
        do {
            let request = try auth.authenticatedRequest(
                for: AO3ChallengeURL.assignments(slug: collectionSlug, list: lists[0])
            )
            let rows = try await AO3Client.shared.allChallengeAssignments(
                slug: collectionSlug, lists: lists, request: request
            )
            return (rows, nil)
        } catch {
            return ([], UserFacingError.message(for: error))
        }
    }

    private func shouldApply(_ capturedLoad: Int, _ capturedSession: Int) -> Bool {
        AO3CollectionSessionReload.shouldApplyLoad(
            capturedLoadGeneration: capturedLoad,
            loadGeneration: loadGeneration,
            capturedSessionGeneration: capturedSession,
            sessionGeneration: auth.sessionGeneration
        )
    }

    private func clearLoadedState() {
        matched = []
        unmatched = []
        pinchHits = []
        loadErrors = [:]
        worksDueAt = nil
        loadedGeneration = nil
        itemInFlight = nil
        actionErrorMessage = nil
        picking = nil
        pendingWrite = nil
    }
}

// MARK: - Pinch-hit rows and 1cb's two writes

extension ChallengeAssignmentsView {
    // MARK: - State Cards

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading assignments…")
                .font(.system(size: loadingSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }

    private func emptyCard(_ message: String) -> some View {
        Text(message)
            .font(.system(size: bodySize))
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
                .font(.system(size: cardTitleSize, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.system(size: failureBodySize))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again") {
                Task { await load() }
            }
            .buttonStyle(.bordered)
            .tint(palette.tint)
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
                .font(.system(size: bodySize))
                .foregroundStyle(Color.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
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

    /// The spec's "Pinch hit #1 · open / Requested by …" and "Pinch hit #2 ·
    /// claimed / Claimed by … · due …".
    private func pinchHitRow(_ row: AO3PinchHitRow) -> some View {
        HStack(alignment: .center, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text("Pinch hit #\(row.number)")
                        .font(.system(size: cardTitleSize, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(row.isOpen ? "OPEN" : "CLAIMED")
                        .font(.system(size: 8.5, weight: .bold))
                        .lineLimit(1)
                        .fixedSize()
                        .tracking(8.5 * 0.07)
                        .foregroundStyle(row.isOpen ? palette.accent : Color.secondary.opacity(0.7))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(row.isOpen ? palette.accent.opacity(0.18) : Color.secondary.opacity(0.12))
                        )
                }
                Text(row.detail(dueText: worksDueAt?.dateText))
                    .font(.system(size: captionSize))
                    .foregroundStyle(Color.secondary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if row.isOpen, auth.isLoggedIn,
               AO3CollectionOwnerControls.areVisible(viewerIsOwner: viewerIsOwner) {
                claimButton(for: row.assignment)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    /// Runs a confirmed write, then reloads: both writes move the assignment
    /// between AO3's lists, so the lists are re-read rather than patched.
    private func perform(_ write: PendingWrite) async {
        guard let loadedGeneration else { return }
        itemInFlight = write.assignment.id
        actionErrorMessage = nil
        do {
            switch write.kind {
            case .claimPinchHit:
                try await auth.claimPinchHit(
                    slug: collectionSlug, assignmentID: write.assignment.id, byline: auth.username ?? "",
                    expectedGeneration: loadedGeneration
                )
            case .reportDefault:
                try await auth.markAssignmentDefaulted(
                    slug: collectionSlug, assignmentID: write.assignment.id, expectedGeneration: loadedGeneration
                )
            }
            try auth.requireSessionGeneration(loadedGeneration)
            itemInFlight = nil
            await load()
        } catch is CancellationError {
            return
        } catch {
            itemInFlight = nil
            actionErrorMessage = "\(write.kind.failure): \(UserFacingError.message(for: error))"
        }
    }

    // MARK: - Writes (confirmed)

    /// The spec's bottom bar. Both are AO3 writes that only collection owners
    /// may make; each goes through a picker and a confirmation.
    private var bottomActionBar: some View {
        HStack(spacing: 9) {
            Button {
                picking = .reportDefault
            } label: {
                Text("Report a default")
                    .font(.system(size: buttonLabelSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(theme.appTheme.glassFill(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(theme.appTheme.glassStroke(0.16), lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(reportable.isEmpty || itemInFlight != nil)

            Button {
                picking = .claimPinchHit
            } label: {
                Text("Claim a pinch hit")
                    .font(.system(size: buttonLabelSize, weight: .semibold))
                    .foregroundStyle(palette.labelOnAccent)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.accent))
            }
            .buttonStyle(.plain)
            .disabled(unmatched.isEmpty || itemInFlight != nil)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 26)
        .background(
            LinearGradient(
                colors: [
                    theme.appTheme.cardBackdrop,
                    theme.appTheme.cardBackdrop.opacity(0.96),
                    theme.appTheme.cardBackdrop.opacity(0.0)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        )
    }

    /// Open assignments a giver can default on: sent, not delivered, not
    /// already defaulted.
    private var reportable: [AO3ChallengeAssignment] {
        matched.filter { !$0.isFulfilled && !$0.isDefaulted }
    }

    private func candidates(for kind: WriteKind) -> [AO3ChallengeAssignment] {
        kind == .reportDefault ? reportable : unmatched
    }

    private func candidateLabel(_ assignment: AO3ChallengeAssignment) -> String {
        "\(giverDisplay(for: assignment)) → \(displayName(assignment.requestPseud))"
    }

    private func confirmationMessage(_ write: PendingWrite) -> String {
        let recipient = displayName(write.assignment.requestPseud)
        switch write.kind {
        case .reportDefault:
            return "AO3 will mark \(giverDisplay(for: write.assignment))'s assignment for \(recipient) as "
                + "defaulted, and it moves to the pinch hits waiting for cover."
        case .claimPinchHit:
            let due = worksDueAt?.dateText.map { ", due \($0)" } ?? ""
            return "You'll be the pinch hitter for \(recipient)'s gift\(due)."
        }
    }
}

extension ChallengeAssignmentsView {
    enum WriteKind: String, Identifiable {
        case reportDefault, claimPinchHit
        var id: String { rawValue }

        var title: String { self == .reportDefault ? "Report a default" : "Claim a pinch hit" }
        var confirmTitle: String { self == .reportDefault ? "Report this default?" : "Claim this pinch hit?" }
        var confirmButton: String { self == .reportDefault ? "Report default" : "Claim" }
        var failure: String {
            self == .reportDefault ? "Couldn't record the default" : "Couldn't claim that pinch hit"
        }
    }

    struct PendingWrite: Identifiable {
        var kind: WriteKind
        var assignment: AO3ChallengeAssignment
        var id: String { "\(kind.rawValue)-\(assignment.id)" }
    }
}
