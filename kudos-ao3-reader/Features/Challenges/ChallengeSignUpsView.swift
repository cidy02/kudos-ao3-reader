import SwiftUI

/// Artboard **1bz** — Challenge sign-ups.
///
/// Moderator view of participants who signed up for the challenge, showing matched
/// state joined client-side with assignment records. Provides All / Matched /
/// Unmatched segmented filtering, a single-line request tag summary per row, and
/// shortcuts to view or create your own sign-up.
struct ChallengeSignUpsView: View {
    let collectionSlug: String
    var collectionTitle: String = ""

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme

    @State private var signUps: [AO3ChallengeSignUp] = []
    @State private var currentPage: Int = 1
    @State private var totalPages: Int = 1
    @State private var filterSelection: SignUpFilter = .all
    @State private var phase: Phase = .idle
    @State private var closeDateText: String = ""
    @State private var showOwnSignUp: Bool = false
    @State private var showCreateSignUp: Bool = false
    @State private var selectedSignUp: AO3ChallengeSignUp?

    enum SignUpFilter: String, CaseIterable, Hashable, Sendable {
        case all = "All"
        case matched = "Matched"
        case unmatched = "Unmatched"
    }

    private enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private var gutter: CGFloat { SubjectMetrics.accountGutter }
    private var selfGuttered: CGFloat { 0 }

    private var palette: SubjectPalette {
        theme.appTheme.subjectPalette(
            hue: CoverArt.workHue(fandoms: [], title: collectionTitle.isEmpty ? collectionSlug : collectionTitle)
        )
    }

    private var effectiveTitle: String {
        collectionTitle.isEmpty ? collectionSlug : collectionTitle
    }

    private var filteredSignUps: [AO3ChallengeSignUp] {
        switch filterSelection {
        case .all:
            return signUps
        case .matched:
            return signUps.filter(\.isMatched)
        case .unmatched:
            return signUps.filter { !$0.isMatched }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            List {
                Section {
                    header.pageBodyRow(top: 20, gutter: selfGuttered)
                    filterSegment.pageBodyRow(top: 14, gutter: gutter)
                }

                switch phase {
                case .loading where signUps.isEmpty:
                    Section {
                        loadingRow.pageBodyRow(top: 20, gutter: gutter)
                    }
                case let .failed(message) where signUps.isEmpty:
                    Section {
                        failureCard(message).pageBodyRow(top: 14, gutter: gutter)
                    }
                default:
                    contentSections
                }

                // Space for floating bottom action bar
                Section {
                    Spacer(minLength: 70)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .cardList()
            #if os(macOS)
            .navigationTitle("Sign-ups")
            #endif
            .subjectScreenWash(palette: palette)

            bottomActionBar
        }
        .task { await loadSignUpsIfNeeded() }
        .refreshable { await loadSignUps(resetPage: true) }
        .sheet(isPresented: $showOwnSignUp) {
            ChallengeSignUpView(
                collectionSlug: collectionSlug,
                collectionTitle: effectiveTitle
            )
        }
        .sheet(isPresented: $showCreateSignUp) {
            ChallengeSignUpView(
                collectionSlug: collectionSlug,
                collectionTitle: effectiveTitle
            )
        }
    }

    // MARK: - Header & Filter

    private var subtitleText: String {
        let count = "\(signUps.count) sign-up\(signUps.count == 1 ? "" : "s")"
        if !closeDateText.isEmpty {
            return "\(count) · \(closeDateText)"
        }
        return count
    }

    private var header: some View {
        SubjectHeaderBlock(
            kicker: effectiveTitle,
            title: "Sign-ups",
            subtitle: subtitleText,
            palette: palette,
            gutter: SubjectMetrics.accountGutter
        )
    }

    private var filterSegment: some View {
        SubjectSegmentedControl(
            options: SignUpFilter.allCases,
            title: \.rawValue,
            selection: $filterSelection
        )
    }

    // MARK: - Content Sections

    @ViewBuilder
    private var contentSections: some View {
        Section {
            SectionRuleHeader(title: "Sign-ups", count: filteredSignUps.count)
                .pageBodyRow(top: 18, gutter: selfGuttered)

            if filteredSignUps.isEmpty {
                emptyFilteredCard.pageBodyRow(top: 8, gutter: gutter)
            } else {
                signUpsPanel.pageBodyRow(top: 8, gutter: gutter)
            }

            footnoteText.pageBodyRow(top: 8, gutter: gutter)
        }

        if currentPage < totalPages {
            Section {
                loadMoreRow.pageBodyRow(top: 10, gutter: gutter)
            }
        }
    }

    private var signUpsPanel: some View {
        VStack(spacing: 0) {
            ForEach(Array(filteredSignUps.enumerated()), id: \.element.id) { index, signUp in
                if index > 0 {
                    SubjectRowSeparator()
                }
                signUpRow(signUp)
            }
        }
        .subjectPanel()
    }

    private func signUpRow(_ signUp: AO3ChallengeSignUp) -> some View {
        Button {
            selectedSignUp = signUp
        } label: {
            HStack(alignment: .top, spacing: 11) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .center, spacing: 7) {
                        Text(signUp.pseud)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)

                        matchedStatusBadge(isMatched: signUp.isMatched)
                    }

                    Text("\(signUp.requests.count) requests · \(signUp.offers.count) offers")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.secondary.opacity(0.85))
                        .monospacedDigit()

                    if !signUp.requestTagSummary.isEmpty {
                        Text(signUp.requestTagSummary)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary.opacity(0.65))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.42))
                    .padding(.top, 4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func matchedStatusBadge(isMatched: Bool) -> some View {
        Text(isMatched ? "MATCHED" : "UNMATCHED")
            .font(.system(size: 8.5, weight: .bold))
            .tracking(8.5 * 0.07)
            .foregroundStyle(isMatched ? palette.accent : Color.secondary.opacity(0.7))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isMatched ? palette.accent.opacity(0.18) : Color.white.opacity(0.10))
            )
    }

    private var emptyFilteredCard: some View {
        VStack(spacing: 6) {
            Text("No \(filterSelection.rawValue.lowercased()) sign-ups")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            Text("No sign-ups in this page match the \"\(filterSelection.rawValue)\" filter.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .subjectPanel()
    }

    private var footnoteText: some View {
        Text("AO3 pages sign-ups twenty to a page, so the list is fetched a page at a time "
            + "and the segment filters what has been fetched, not the whole challenge. "
            + "The tag summary is the sign-up’s own requests, truncated to one line.")
            .font(.system(size: 11.5))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private var loadMoreRow: some View {
        Button {
            Task { await loadNextPage() }
        } label: {
            HStack {
                if phase == .loading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                }
                Text("Load page \(currentPage + 1) of \(totalPages)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.accent)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .disabled(phase == .loading)
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        HStack(spacing: 9) {
            Button {
                showOwnSignUp = true
            } label: {
                Text("Your sign-up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
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

            Button {
                showCreateSignUp = true
            } label: {
                Text("Create sign-up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.accentOnFill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(palette.accent)
                    )
            }
            .buttonStyle(.plain)
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

    // MARK: - State Cards

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading sign-ups…")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }

    private func failureCard(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Couldn't load sign-ups")
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadSignUps(resetPage: true) }
            }
            .buttonStyle(.bordered)
            .tint(palette.accent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .subjectPanel()
    }

    // MARK: - Actions

    private func loadSignUpsIfNeeded() async {
        guard phase == .idle else { return }
        await loadSignUps(resetPage: true)
    }

    private func loadSignUps(resetPage: Bool) async {
        if resetPage {
            currentPage = 1
        }
        phase = .loading

        // Attempt to read challenge settings for schedule dates
        if let settingsRequest = try? auth.authenticatedRequest(
            for: AO3ChallengeURL.giftExchangeEdit(slug: collectionSlug)
        ), let form = try? await AO3Client.shared.challengeSettings(slug: collectionSlug, request: settingsRequest) {
            if let closeDate = form.settings.signupsCloseAt.date {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                closeDateText = "open until \(formatter.string(from: closeDate))"
            }
        }

        do {
            let request = try auth.authenticatedRequest(
                for: AO3ChallengeURL.signUps(slug: collectionSlug, page: currentPage)
            )

            // Attempt joined signups (signups + assignments)
            do {
                let page = try await AO3Client.shared.challengeSignUpsJoinedToAssignments(
                    slug: collectionSlug, page: currentPage, request: request
                )
                if resetPage {
                    signUps = page.signUps
                } else {
                    signUps.append(contentsOf: page.signUps)
                }
                totalPages = page.totalPages
                phase = .loaded
            } catch {
                // KNOWN DEFECT work-around: parseChallengeAssignmentsPage does not match real
                // otwarchive markup. If joining fails, degrade gracefully to plain sign-ups so the
                // list displays without crashing or claiming falsified match states.
                let plainPage = try await AO3Client.shared.challengeSignUps(
                    slug: collectionSlug, page: currentPage, request: request
                )
                if resetPage {
                    signUps = plainPage.signUps
                } else {
                    signUps.append(contentsOf: plainPage.signUps)
                }
                totalPages = plainPage.totalPages
                phase = .loaded
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func loadNextPage() async {
        guard currentPage < totalPages, phase != .loading else { return }
        currentPage += 1
        await loadSignUps(resetPage: false)
    }
}
