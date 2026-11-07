import SwiftUI

/// The Subscriptions "New to you" triage: one unfamiliar work at a time, with
/// Save / Not for me / Next. Renders what it is handed and reports each decision;
/// the caller owns fetching and persisting.
struct NewToYouCardsView: View {
    enum Decision: Equatable, Sendable { case saved, dismissed, deferred }

    let works: [AO3WorkSummary]
    var onDecide: (AO3WorkSummary, Decision) -> Void = { _, _ in }
    var onFinished: () -> Void = {}
    /// A parent with more specific source state can supply its own honest empty view.
    var showsEmptyState = true

    @Environment(ThemeManager.self) private var theme
    @Environment(PrivacyGate.self) private var privacyGate
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure
    // Ids, not an index: a caller that drops decided works from `works` must not make the deck skip.
    @State private var handled = Set<Int>()

    private static let maxContentWidth: CGFloat = 560 // keeps the card readable on iPad and macOS

    private var isAccessibilitySize: Bool { typeSize.isAccessibilitySize }

    // Decisions are keyed by id, so a repeated id would be handled twice and the last-card check would never fire.
    private var uniqueWorks: [AO3WorkSummary] {
        var seen = Set<Int>()
        return works.filter { seen.insert($0.id).inserted }
    }

    private var undecidedWorks: [AO3WorkSummary] {
        uniqueWorks.filter { !handled.contains($0.id) }
    }

    private var remaining: [AO3WorkSummary] {
        undecidedWorks.filter {
            !privacyGate.isHidden($0, enabled: hideMature, mode: matureMode)
        }
    }

    private var current: AO3WorkSummary? { remaining.first }

    private func isObscured(_ work: AO3WorkSummary) -> Bool {
        hideMature && work.isAdult && matureMode == .obscure && !privacyGate.isRevealed(work)
    }

    private var positionText: String {
        "\(handled.count + 1) of \(handled.count + remaining.count)"
    }

    /// AO3's own boilerplate warnings say nothing, so they stay off the card (as in `WorkRow`).
    private func warnings(of work: AO3WorkSummary) -> [String] {
        work.warnings.filter {
            !$0.localizedCaseInsensitiveContains("No Archive Warnings")
                && !$0.localizedCaseInsensitiveContains("Chose Not To Use")
        }
    }

    private func decide(_ decision: Decision, on work: AO3WorkSummary) {
        let wasLast = remaining.count == 1
        // shortcut: Next drops the card for this session instead of cycling back to it, upgrade when deferred works should resurface in-session
        handled.insert(work.id)
        onDecide(work, decision)
        if wasLast { onFinished() }
    }

    var body: some View {
        Group {
            if let work = current {
                deck(work)
            } else if !undecidedWorks.isEmpty {
                MatureContentHiddenView()
            } else if showsEmptyState, handled.isEmpty {
                ContentUnavailableView(
                    "Nothing new to you",
                    systemImage: "sparkles",
                    description: Text("Works you haven't seen before will show up here.")
                )
            } else if handled.isEmpty {
                EmptyView()
            } else {
                ContentUnavailableView(
                    "All caught up",
                    systemImage: "checkmark.circle",
                    description: Text("You've been through every new work.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.appTheme.cardBackdrop.ignoresSafeArea())
        .navigationTitle("New to you")
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            // The decided card disappears under VoiceOver focus, so say what replaced it.
            .onChange(of: current?.id) {
                let text = current.map {
                    isObscured($0) ? "\(positionText), hidden mature work" : "\(positionText), \($0.title)"
                } ?? "All caught up"
                AccessibilityNotification.Announcement(text).post()
            }
            .toolbar {
                if PrivacyGate.hasVisibleMatureWorks(in: undecidedWorks, hideMature: hideMature) {
                    ToolbarItem(placement: .primaryAction) {
                        MatureRevealToggle()
                    }
                }
            }
    }

    private func deck(_ work: AO3WorkSummary) -> some View {
        ScrollView {
            VStack(spacing: CardListMetrics.interCardSpacing) {
                Text(positionText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityLabel("Work \(positionText)")
                    .accessibilityAddTraits(.isHeader)

                privacyAwareCard(work)

                // Three buttons do not fit abreast at accessibility sizes, so the bar scrolls with the card there.
                if isAccessibilitySize, !isObscured(work) { actionBar(for: work) }
            }
            .frame(maxWidth: Self.maxContentWidth)
            .padding(.horizontal, CardListMetrics.sideMargin)
            .padding(.vertical, CardListMetrics.interCardSpacing)
            .frame(maxWidth: .infinity)
        }
        // A fresh card starts at the top, not wherever the last summary was scrolled to.
        .id(work.id)
        .safeAreaInset(edge: .bottom) {
            if !isAccessibilitySize, !isObscured(work) {
                actionBar(for: work)
                    .frame(maxWidth: Self.maxContentWidth)
                    .padding(.horizontal, CardListMetrics.sideMargin)
                    .padding(.vertical, CardListMetrics.interCardSpacing)
                    .frame(maxWidth: .infinity)
                    .background(theme.appTheme.cardBackdrop)
            }
        }
    }

    @ViewBuilder
    private func privacyAwareCard(_ work: AO3WorkSummary) -> some View {
        if isObscured(work) {
            Button {
                privacyGate.reveal(work)
            } label: {
                card(work)
                    .blur(radius: 6)
                    .overlay { MatureContentRevealLabel() }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hidden mature work. Activate to reveal.")
        } else {
            card(work)
        }
    }

    private func card(_ work: AO3WorkSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(work.title)
                .font(.title3.bold())
                .fixedSize(horizontal: false, vertical: true)

            // `.tint` would put the icons in the user's accent, which fails contrast on the dark card
            // surface; WorkStatLabel draws them with it, so redirect it for this block.
            VStack(alignment: .leading, spacing: 4) {
                FlowLayout(spacing: 12, rowSpacing: 4) {
                    if !work.authors.isEmpty {
                        // Truncating: a pseud and a fandom list are free text, unlike the stats below.
                        WorkStatLabel(text: work.authorText, symbol: "person", truncates: true)
                    }
                    if !work.fandoms.isEmpty {
                        WorkStatLabel(
                            text: work.fandoms.joined(separator: ", "), symbol: "books.vertical", truncates: true
                        )
                    }
                }
                FlowLayout(spacing: 12, rowSpacing: 4) {
                    if !work.rating.isEmpty { WorkStatLabel(text: work.rating, symbol: "checkmark.shield") }
                    // Unknown completion (nil) says nothing rather than claiming "In progress".
                    if let complete = work.isComplete {
                        WorkStatLabel(
                            text: complete ? "Complete" : "In progress",
                            symbol: complete ? "checkmark.circle" : "hourglass"
                        )
                    }
                    if !work.chapters.isEmpty { WorkStatLabel(text: work.chapters, symbol: "book") }
                    if let words = work.words { WorkStatLabel(text: words.formatted(), symbol: "textformat.size") }
                    if let kudos = work.kudos { WorkStatLabel(text: kudos.formatted(), symbol: "heart") }
                    if !work.dateUpdated.isEmpty { WorkStatLabel(text: work.dateUpdated, symbol: "calendar") }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .tint(Color.secondary)

            if !warnings(of: work).isEmpty {
                Label(warnings(of: work).joined(separator: ", "), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !work.summary.isEmpty {
                Text(work.summary)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(CardListMetrics.innerHorizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: CardListMetrics.cornerRadius, style: .continuous)
                .fill(theme.appTheme.cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: CardListMetrics.cornerRadius, style: .continuous)
                        .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
                )
                .shadow(
                    color: theme.appTheme.cardShadow.color,
                    radius: theme.appTheme.cardShadow.radius,
                    x: 0, y: theme.appTheme.cardShadow.y
                )
        }
        .accessibilityElement(children: .combine)
    }

    private func actionBar(for work: AO3WorkSummary) -> some View {
        let layout = isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            action("Save", .saved, on: work, label: "Save \(work.title)")
                .buttonStyle(.borderedProminent)
            // `.bordered` inherits the user accent, a fixed hex and not colorScheme-adaptive, so it fails contrast on the dark backdrop; `.borderedProminent` is fine.
            action("Not for me", .dismissed, on: work, label: "Not for me, \(work.title). Won't show it again")
                .buttonStyle(.bordered)
                .tint(Color.primary)
            action("Next", .deferred, on: work, label: "Next. Decide on \(work.title) later")
                .buttonStyle(.bordered)
                .tint(Color.primary)
        }
    }

    /// The frame lives inside the label so the button's own background fills it; outside, it would not.
    private func action(
        _ title: String, _ decision: Decision, on work: AO3WorkSummary, label: String
    ) -> some View {
        Button {
            decide(decision, on: work)
        } label: {
            Text(title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityLabel(label)
    }
}

#Preview {
    func work(
        _ id: Int, _ title: String, _ author: String, complete: Bool? = nil, chapters: String = "",
        summary: String = ""
    ) -> AO3WorkSummary {
        var result = AO3WorkSummary.subscription(id: id, title: title, authors: [author])
        result.isComplete = complete
        result.chapters = chapters
        result.summary = summary
        result.fandoms = ["Original Work"]
        result.rating = "Teen And Up Audiences"
        result.words = 48_210
        result.kudos = 1_204
        result.dateUpdated = "2026-10-30"
        return result
    }

    let deck = [
        work(1, "The Lantern Keeper", "saltwindow", complete: false, chapters: "9/?",
             summary: "A lighthouse keeper finds the lamp has been lit by someone else for years."),
        work(2, "Paper Boats", "a pseud long enough to need truncating at the ideal width",
             complete: true, chapters: "24/24"),
        work(3, "A Quiet Harbour", "marrowlight")
    ]

    return TabView {
        NavigationStack { NewToYouCardsView(works: deck) }
            .tabItem { Text("Full deck") }
        NavigationStack { NewToYouCardsView(works: [deck[2]]) }
            .tabItem { Text("Last card") }
        NavigationStack { NewToYouCardsView(works: []) }
            .tabItem { Text("Empty") }
    }
    .environment(ThemeManager())
    .environment(PrivacyGate())
}
