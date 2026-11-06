import Foundation

/// One thing that changed in a subscription, as the Subscriptions screen shows it.
///
/// This is deliberately not a mirror of `kudos-mail-core`'s `Ao3Event`. The crate
/// reports what it could establish and how far; this type reports what the screen
/// is allowed to say. The translation between them is `init(readingA:)` below, and
/// it is the single place where the crate's hard-won caution is either honoured or
/// thrown away.
///
/// Thirteen adversarial review passes on the parser converged on one rule: when a
/// notification's preface cannot be told from an AO3 author's imitation of one, the
/// crate reports nothing read from it rather than guessing. All of that is undone
/// if the UI then fills the gap with a plausible-looking chapter, so the gap is
/// represented here instead of being papered over.
struct SubscriptionUpdate: Equatable, Identifiable, Sendable {
    /// How much of this update is AO3's own word.
    enum Certainty: Equatable, Sendable {
        /// The work is AO3's — it came from the footer's unsubscribe URL, which
        /// AO3 generates — and so is everything else here.
        case confirmed
        /// The work is AO3's, but what changed within it is not: either the
        /// preface was contested, or the subscription is to an author or series
        /// and nothing pinned the work at all. Show that the work updated;
        /// never claim which chapter. Confirm against AO3 before acting.
        case workOnly
    }

    /// What changed, when it can be said at all.
    enum Change: Equatable, Sendable {
        case newChapter(number: Int?)
        case newWork
        /// The notification was genuine but its preface was not readable.
        case unknown
    }

    let workID: UInt64
    /// Nil whenever `certainty` is `.workOnly` — enforced by the initializer, not
    /// by convention, because a chapter id is what a deep link and an unread count
    /// are built from.
    let chapterID: UInt64?
    let change: Change
    let certainty: Certainty
    /// Empty when the preface could not be read.
    let workTitle: String
    let author: String
    let at: Date

    var id: String { "\(workID)-\(chapterID.map(String.init) ?? "work")-\(at.timeIntervalSince1970)" }

    /// True when the screen may offer to open a specific chapter.
    var canDeepLinkToChapter: Bool { certainty == .confirmed && chapterID != nil }

    /// Build from the crate's own answer.
    ///
    /// `kind` and `identity` are the crate's two signals and both must be
    /// respected: `Ao3EventKind.contested` means the preface lost, and
    /// `Identity.body` means nothing pinned the work. Either one demotes the
    /// update to `.workOnly` and drops the chapter — taking the primitives rather
    /// than the generated UniFFI types so this rule is unit-testable before the
    /// binding is wired into the project.
    init(
        workID: UInt64,
        chapterID: UInt64?,
        chapterNumber: Int?,
        isNewWork: Bool,
        isContested: Bool,
        isAnchoredToWork: Bool,
        workTitle: String,
        author: String,
        at: Date
    ) {
        self.workID = workID
        self.at = at

        let trustworthy = !isContested && isAnchoredToWork
        certainty = trustworthy ? .confirmed : .workOnly

        if trustworthy {
            self.chapterID = chapterID
            change = isNewWork ? .newWork : .newChapter(number: chapterNumber)
            self.workTitle = workTitle
            self.author = author
        } else {
            // Everything below the work id came out of the preface, so none of it
            // survives. Dropping the title too is deliberate: a half-filled update
            // reads as authoritative, and the point is that it is not.
            self.chapterID = nil
            change = isContested ? .unknown : (isNewWork ? .newWork : .newChapter(number: nil))
            self.workTitle = isContested ? "" : workTitle
            self.author = isContested ? "" : author
        }
    }
}
