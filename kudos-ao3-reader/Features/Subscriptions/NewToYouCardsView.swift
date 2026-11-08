import SwiftData
import SwiftUI

/// The Subscriptions "New to you" triage: one unfamiliar work at a time, with
/// Save / Not for me / Next. Renders what it is handed and reports each decision;
/// the caller owns fetching and persisting.
struct NewToYouCardsView: View {
    private enum Decision: Equatable { case saved, dismissed, deferred }

    let cards: [NewToYouCard]
    /// Not for me. Throw to leave the card in the deck.
    var onDismiss: (NewToYouCard) throws -> Void = { _ in }
    /// Save. Throw — including `AO3Error.maintenance` — to leave the card in the deck.
    var onSave: (NewToYouCard) async throws -> Void = { _ in }
    var onFinished: () -> Void = {}
    /// A parent with more specific source state can supply its own honest empty view.
    var showsEmptyState = true

    @Environment(ThemeManager.self) private var theme
    @Environment(PrivacyGate.self) private var privacyGate
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure
    // Ids, not an index: a caller that drops decided cards must not make the deck skip.
    @State private var handled = Set<Int>()
    @State private var isSaving = false
    @State private var actionError: String?

    private static let maxContentWidth: CGFloat = 560 // keeps the card readable on iPad and macOS

    private var isAccessibilitySize: Bool { typeSize.isAccessibilitySize }

    // Decisions are keyed by id, so a repeated id would be handled twice and the last-card check would never fire.
    private var uniqueCards: [NewToYouCard] {
        var seen = Set<Int>()
        return cards.filter { seen.insert($0.id).inserted }
    }

    private var undecidedCards: [NewToYouCard] {
        uniqueCards.filter { !handled.contains($0.id) }
    }

    private var remaining: [NewToYouCard] {
        undecidedCards.filter {
            !privacyGate.isHidden($0.summary, enabled: hideMature, mode: matureMode)
        }
    }

    private var current: NewToYouCard? { remaining.first }

    private func isObscured(_ card: NewToYouCard) -> Bool {
        // The gate's rule, so a card whose rating is not known yet stays concealed too.
        privacyGate.isBlurred(card.summary, enabled: hideMature, mode: matureMode)
    }

    private var positionText: String {
        "\(handled.count + 1) of \(handled.count + remaining.count)"
    }

    /// VoiceOver text when the deck runs out. Hide can empty the visible deck
    /// while works remain, so "All caught up" is only for a truly empty deck.
    private var emptyDeckText: String {
        undecidedCards.isEmpty ? "All caught up" : "\(undecidedCards.count) hidden by Hide mature content"
    }

    /// AO3's own boilerplate warnings say nothing, so they stay off the card (as in `WorkRow`).
    private func warnings(of work: AO3WorkSummary) -> [String] {
        work.warnings.filter {
            !$0.localizedCaseInsensitiveContains("No Archive Warnings")
                && !$0.localizedCaseInsensitiveContains("Chose Not To Use")
        }
    }

    /// Removes the card from this visit. `wasLast` is captured before the decision
    /// runs, because a successful Save refreshes the deck before this returns.
    private func drop(_ card: NewToYouCard, wasLast: Bool) {
        // shortcut: Next drops the card for this session instead of cycling back to it, upgrade when deferred works should resurface in-session
        handled.insert(card.id)
        if wasLast { onFinished() }
    }

    private func dismiss(_ card: NewToYouCard) {
        let wasLast = remaining.count == 1
        do {
            try onDismiss(card)
            drop(card, wasLast: wasLast)
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? "That work is still in the deck."
        }
    }

    private func save(_ card: NewToYouCard) async {
        guard !isSaving else { return }
        let wasLast = remaining.count == 1
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(card)
            drop(card, wasLast: wasLast)
        } catch is CancellationError {
            return
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? "The work couldn't be saved."
        }
    }

    var body: some View {
        Group {
            if let card = current {
                deck(card)
            } else if !undecidedCards.isEmpty {
                // Every card left is hidden by Hide mode.
                ContentUnavailableView {
                    Label("Sensitive works hidden", systemImage: "eye.slash")
                } description: {
                    Text("Works without a recognized General or Teen rating are hidden. Reveal them to read.")
                } actions: {
                    Button("Show mature") { privacyGate.toggleRevealAll() }
                }
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
                    isObscured($0) ? "\(positionText), hidden mature work" : "\(positionText), \($0.headline)"
                } ?? emptyDeckText
                AccessibilityNotification.Announcement(text).post()
            }
            .toolbar {
                // T-284: the toggle is on every works screen while privacy is on.
                if hideMature {
                    ToolbarItem(placement: .primaryAction) {
                        MatureRevealToggle()
                    }
                }
            }
            .alert(
                "Couldn't finish",
                isPresented: Binding(
                    get: { actionError != nil },
                    set: { if !$0 { actionError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { actionError = nil }
            } message: {
                Text(actionError ?? "")
            }
    }

    private func deck(_ card: NewToYouCard) -> some View {
        ScrollView {
            VStack(spacing: CardListMetrics.interCardSpacing) {
                Text(positionText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityLabel("Work \(positionText)")
                    .accessibilityAddTraits(.isHeader)

                privacyAwareCard(card)

                // Three buttons do not fit abreast at accessibility sizes, so the bar scrolls with the card there.
                if isAccessibilitySize, !isObscured(card) { actionBar(for: card) }
            }
            .frame(maxWidth: Self.maxContentWidth)
            .padding(.horizontal, CardListMetrics.sideMargin)
            .padding(.vertical, CardListMetrics.interCardSpacing)
            .frame(maxWidth: .infinity)
        }
        // A fresh card starts at the top, not wherever the last summary was scrolled to.
        .id(card.id)
        .safeAreaInset(edge: .bottom) {
            if !isAccessibilitySize, !isObscured(card) {
                actionBar(for: card)
                    .frame(maxWidth: Self.maxContentWidth)
                    .padding(.horizontal, CardListMetrics.sideMargin)
                    .padding(.vertical, CardListMetrics.interCardSpacing)
                    .frame(maxWidth: .infinity)
                    .background(theme.appTheme.cardBackdrop)
            }
        }
    }

    @ViewBuilder
    private func privacyAwareCard(_ card: NewToYouCard) -> some View {
        if isObscured(card) {
            Button {
                privacyGate.reveal(card.summary)
            } label: {
                cardBody(card)
                    .blur(radius: 6)
                    .overlay { MatureRevealCapsule() }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hidden mature work. Activate to reveal.")
        } else {
            cardBody(card)
        }
    }

    private func cardBody(_ card: NewToYouCard) -> some View {
        let work = card.summary
        return VStack(alignment: .leading, spacing: 10) {
            // The headline is the subscription URL, not the preface title.
            Text(card.headline)
                .font(.title3.bold())
                .fixedSize(horizontal: false, vertical: true)

            if let attribution = card.attribution {
                Text(attribution)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
                    if !work.rating.isEmpty { cardStat(work.rating, symbol: "checkmark.shield") }
                    // Unknown completion (nil) says nothing rather than claiming "In progress".
                    if let complete = work.isComplete {
                        cardStat(
                            complete ? "Complete" : "In progress",
                            symbol: complete ? "checkmark.circle" : "hourglass"
                        )
                    }
                    if !work.chapters.isEmpty { cardStat(work.chapters, symbol: "book") }
                    if let words = work.words { cardStat(words.formatted(), symbol: "textformat.size") }
                    if let kudos = work.kudos { cardStat(kudos.formatted(), symbol: "heart") }
                    if !work.dateUpdated.isEmpty { cardStat(work.dateUpdated, symbol: "calendar") }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

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
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .fill(theme.appTheme.cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
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

    /// `WorkStatLabel` is one line at its ideal width, and that default is shared
    /// by every other caller. At accessibility sizes a rating such as "Teen And Up
    /// Audiences" is wider than this card, so the stat wraps here instead of clipping.
    @ViewBuilder
    private func cardStat(_ text: String, symbol: String) -> some View {
        if isAccessibilitySize {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Image(systemName: symbol)
                    .font(.caption2.weight(.bold))
                Text(text)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            WorkStatLabel(text: text, symbol: symbol)
        }
    }

    private func actionBar(for card: NewToYouCard) -> some View {
        let layout = isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            action("Save", .saved, on: card, label: "Save \(card.headline)")
                .buttonStyle(.borderedProminent)
            // `.bordered` inherits the user accent, a fixed hex and not colorScheme-adaptive, so it fails contrast on the dark backdrop; `.borderedProminent` is fine.
            action(
                "Not for me", .dismissed, on: card,
                label: "Not for me, \(card.headline). Won't show it again"
            )
            .buttonStyle(.bordered)
            .foregroundStyle(.primary)
            action("Next", .deferred, on: card, label: "Next. Decide on \(card.headline) later")
                .buttonStyle(.bordered)
                .foregroundStyle(.primary)
        }
        .disabled(isSaving)
    }

    /// The frame lives inside the label so the button's own background fills it; outside, it would not.
    private func action(
        _ title: String, _ decision: Decision, on card: NewToYouCard, label: String
    ) -> some View {
        Button {
            switch decision {
            case .saved: Task { await save(card) }
            case .dismissed: dismiss(card)
            case .deferred: drop(card, wasLast: remaining.count == 1)
            }
        } label: {
            Text(title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityLabel(label)
    }
}

#if os(iOS)
/// New to you fed by stored mail updates, minus works already in the library
/// or already decided.
struct NewToYouMailDeck: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(MailSubscriptionDriver.self) private var mailDriver
    @State private var library = WorkIdentityIndex([])
    @State private var ready = false

    private var cards: [NewToYouCard] {
        NewToYouDeck.cards(
            from: mailDriver.updates,
            library: library,
            decidedWorkIDs: Set(mailDriver.decisions.map(\.workID))
        )
    }

    var body: some View {
        Group {
            if ready {
                NewToYouCardsView(
                    cards: cards,
                    onDismiss: { card in
                        try mailDriver.recordDecision(.notForMe, workID: card.workID)
                    },
                    onSave: { card in
                        _ = try await NewToYouLibrary.save(card, in: modelContext) { workID in
                            try mailDriver.recordDecision(.saved, workID: workID)
                        }
                        reloadLibrary()
                    }
                )
            } else {
                ProgressView("Checking your library…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { reloadLibrary() }
    }

    private func reloadLibrary() {
        let works = (try? modelContext.fetch(FetchDescriptor<SavedWork>())) ?? []
        library = WorkIdentityIndex(works)
        ready = true
    }
}
#endif

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

    let cards = deck.map { NewToYouCard(preview: $0, source: .author("saltwindow")) }
    return TabView {
        NavigationStack { NewToYouCardsView(cards: cards) }
            .tabItem { Text("Full deck") }
        NavigationStack { NewToYouCardsView(cards: [cards[2]]) }
            .tabItem { Text("Last card") }
        NavigationStack { NewToYouCardsView(cards: []) }
            .tabItem { Text("Empty") }
    }
    .environment(ThemeManager())
    .environment(PrivacyGate())
}
