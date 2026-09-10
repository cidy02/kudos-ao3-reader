import SwiftUI

// Artboard 1a's ON AO3 row: the four archive actions promoted out of the
// overflow menu and onto the page, as chips under a field label.
//
// They are the same four `AO3WorkActionsMenu` carries, driven by the same
// `AO3WorkActionsModel`, so there is one implementation of each action and the
// two surfaces cannot drift. The menu keeps them for now — it is shared with the
// reader, where there is no page to put chips on, and spec 1a's own overflow
// menu (Add to Queue / Add to Collection / Share / Open on AO3) is part of the
// floating-chrome swap that is staged until someone has a device. Until then
// this page offers both, which is duplication worth naming rather than hiding.

/// The ON AO3 chip row: Kudos, Subscribe, Bookmark, Mark for Later.
struct WorkAO3ActionChips: View {
    let workID: Int
    /// The work's kudos tally, printed on the chip the way spec 1a does
    /// ("Kudos · 412"). Nil on a work whose blurb carried no figure.
    let kudosCount: Int?
    let actions: AO3WorkActionsModel
    let palette: SubjectPalette

    @Environment(AO3AuthService.self) private var auth

    /// AO3's own view of this work, when it is already known. **Never fetched
    /// from here.** `AO3WorkActionsModel.refreshWorkPageStates` costs a
    /// work-page GET, and the menu spends it only when a user opens the menu;
    /// calling it from a row that renders on every work-detail open would spend
    /// one per page view, which `docs/AO3_NETWORKING_POLICY.md` does not permit
    /// for a fact nobody asked for. Nil simply means the chips read as their
    /// default verbs, exactly as the menu's own labels do before it is opened.
    private var knownStates: AO3WorkActionStates? { actions.workPageStates }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SubjectFieldLabel(text: "On AO3")

            FlowLayout(spacing: 8, rowSpacing: 8) {
                chip(kudosLabel, systemImage: "heart", isDone: false) {
                    actions.giveKudos(workID: workID, auth: auth)
                }
                subscribeChip
                bookmarkChip
                chip("Mark for Later", systemImage: "clock.badge", isDone: false) {
                    actions.markForLater(workID: workID, auth: auth)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Spec 1a draws this chip tinted, meaning "you have left kudos here". The
    /// app cannot know that: AO3's work page does not say whether *you* gave
    /// kudos, and `AO3WorkActionStates` carries only subscription and bookmark.
    /// So the count rides along as a fact about the work and the chip stays
    /// neutral, rather than claiming a state that would be a guess.
    private var kudosLabel: String {
        guard let kudosCount else { return "Kudos" }
        return "Kudos · " + kudosCount.formatted()
    }

    private var subscribeChip: some View {
        let isSubscribed = knownStates?.isSubscribed == true
        return chip(
            isSubscribed ? "Subscribed" : "Subscribe",
            systemImage: isSubscribed ? "bell.slash" : "bell",
            isDone: isSubscribed
        ) {
            actions.subscribe(workID: workID, auth: auth)
        }
    }

    private var bookmarkChip: some View {
        let isBookmarked = knownStates?.existingBookmark != nil
        return chip(
            isBookmarked ? "Edit Bookmark" : "Bookmark",
            systemImage: isBookmarked ? "bookmark.fill" : "bookmark",
            isDone: isBookmarked
        ) {
            actions.startBookmark()
        }
    }

    /// `isDone` is the spec's tint rule — a tinted chip is one whose action you
    /// have already taken — applied only to the two states AO3 actually tells
    /// us about.
    private func chip(
        _ text: String,
        systemImage: String,
        isDone: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            SubjectChip(
                text: text,
                style: isDone ? .tinted : .neutral,
                systemImage: systemImage,
                palette: palette
            )
        }
        .buttonStyle(.plain)
        .disabled(actions.isWorking)
        .minimumHitTarget(30)
    }
}
