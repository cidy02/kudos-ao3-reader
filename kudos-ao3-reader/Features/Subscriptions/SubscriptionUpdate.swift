import Foundation

/// One thing that changed in a subscription, as the Subscriptions screen shows it.
///
/// This is deliberately not a mirror of `kudos-mail-core`'s `Ao3Event`. The crate
/// reports what it could establish and how far; this type reports what the screen
/// is allowed to say. The translation between them is `init(reading:)` below, and
/// it is the single place where the crate's hard-won caution is either honoured or
/// thrown away.
///
/// Thirteen adversarial review passes on the parser converged on one rule: when a
/// notification's preface cannot be told from an AO3 author's imitation of one, the
/// crate reports nothing read from it rather than guessing. All of that is undone
/// if the UI then fills the gap with a plausible-looking chapter, so the gap is
/// represented here instead of being papered over.
struct SubscriptionUpdate: Codable, Equatable, Identifiable, Sendable {
    /// How much of this update is AO3's own word.
    enum Certainty: Codable, Equatable, Sendable {
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
    enum Change: Codable, Equatable, Sendable {
        case newChapter(number: Int?)
        case newWork
        /// The notification was genuine but its preface was not readable.
        case unknown
    }

    /// Which subscription brought this update in. The name is the series or author
    /// followed, not the work.
    enum Source: Codable, Equatable, Sendable {
        case work
        case series(String)
        case author(String)
        /// The footer's unsubscribe URL did not parse, so not even the kind is
        /// known — the crate's `Subscription.unknown`. Present so the mapping
        /// from the crate never has to pick a kind it cannot support: calling
        /// this `.work` would report the work as pinned when nothing is.
        case unknown
    }

    /// The IMAP UID of the notification this was read from.
    ///
    /// This is what makes two otherwise identical updates distinct, and it has to
    /// come from outside: a contested event drops its chapter id, so a work with
    /// two unreadable notifications in the same second would otherwise produce the
    /// same identity twice — and an author can send exactly that pair deliberately.
    /// SwiftUI's behaviour on duplicate `ForEach` ids is undefined.
    ///
    /// shortcut: unique within one mailbox at one UIDVALIDITY, which is all the
    /// single-account cursor tracks today; widen it if a second mailbox is ever read.
    let uid: UInt32
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
    let source: Source
    /// Creations in the same batch mail beyond the one this row describes. AO3
    /// sends one email for several new chapters or works; the crate parses only
    /// the first and reports this count precisely so a caller never presents one
    /// row as the whole message. The extras are deliberately NOT parsed —
    /// telling creations apart inside a body is the forgeable ground the parser
    /// refuses to walk — so this is a prompt to go and look, not data.
    let extraCreations: UInt64

    var id: String { "\(uid)-\(workID)" }

    /// True when the screen may offer to open a specific chapter.
    var canDeepLinkToChapter: Bool { certainty == .confirmed && chapterID != nil }

    /// Whether AO3's own footer fixed *which work* this is.
    ///
    /// The footer's unsubscribe URL is built by Rails from the subscribed record,
    /// so a work subscription pins the work; an author or series subscription
    /// cannot — it names a user or a series, and which of their works changed was
    /// only ever read from the body, where the author's own text also lives.
    ///
    /// So the source tells the screen which kind of doubt a `.workOnly` row is:
    /// with a `.work` source the work is AO3's and the preface was contested, and
    /// with any other source the work itself is a hint. The copy differs, because
    /// "this work updated" asserts the very thing that is unpinned in the second
    /// case. `source` therefore has no default — a wrong `.work` here would make
    /// an unpinned update read as a definite one.
    var pinsTheWork: Bool { source == .work }

    /// Build from the crate's own answer.
    ///
    /// `kind` and `identity` are the crate's two signals and both must be
    /// respected: `Ao3EventKind.contested` means the preface lost, and
    /// `Identity.body` means nothing pinned the work. Either one demotes the
    /// update to `.workOnly` and drops the chapter — taking the primitives rather
    /// than the generated UniFFI types so this rule is unit-testable before the
    /// binding is wired into the project.
    init(
        uid: UInt32,
        workID: UInt64,
        chapterID: UInt64?,
        chapterNumber: Int?,
        isNewWork: Bool,
        isContested: Bool,
        isAnchoredToWork: Bool,
        workTitle: String,
        author: String,
        at: Date,
        source: Source,
        extraCreations: UInt64 = 0
    ) {
        self.uid = uid
        self.workID = workID
        self.at = at
        self.source = source
        self.extraCreations = extraCreations

        let trustworthy = !isContested && isAnchoredToWork && source == .work
        certainty = trustworthy ? .confirmed : .workOnly

        if trustworthy {
            self.chapterID = chapterID
            change = isNewWork ? .newWork : .newChapter(number: chapterNumber)
            self.workTitle = workTitle
            self.author = author
        } else {
            // A contested preface loses everything read from it. An UNPINNED work
            // (author or series subscription, `Identity::Body`) keeps its title
            // and byline: the crate itself still returns them, and blanking them
            // would reduce every author-subscription row to "Work #12345".
            //
            // That is a deliberate asymmetry, not an oversight, and it is the
            // open question two reviewers have now raised: the subtitle and the
            // "Check" badge hedge, but the HEADLINE is still preface text for a
            // work nothing pinned. Awaiting the owner's call; do not silently
            // change it either way.
            self.chapterID = nil
            change = isContested ? .unknown : (isNewWork ? .newWork : .newChapter(number: nil))
            self.workTitle = isContested ? "" : workTitle
            self.author = isContested ? "" : author
        }
    }
}

#if os(iOS)
extension SubscriptionUpdate {
    init?(reading: Reading) {
        // Only provider-attested mail may become a row.
        //
        // This was briefly relaxed to admit `.senderOnly` as a `.workOnly` row,
        // on the reasoning that refusing it silently discarded a watched
        // folder's mail. That reasoning was wrong twice over. The crate's own
        // module doc is blunt about what the weaker tier is worth — "a `From`
        // address is trivially forged, so `Verdict::SenderOnly` means *this
        // claims to be from AO3* and nothing more" — so such a message has no
        // authenticated root, and its work id, title and byline are all
        // choosable by whoever sent it. And the watched-folder case cannot be
        // told apart anyway: `read_new` documents that a nil `authserv_id`
        // yields SenderOnly, so a live IMAP session with no provider to believe
        // produces exactly the same verdict as a file someone dropped in.
        // `.workOnly` hedges which chapter changed; it cannot hedge "this
        // message may be entirely fabricated".
        //
        // Exhaustive on purpose, with no `default`: a verdict added to the crate
        // later becomes a compile error here rather than silently becoming a
        // visible row. An earlier `!= .rejected` guard claimed to fail closed
        // and did the opposite.
        switch reading.verdict {
        case .trusted: break
        case .senderOnly, .rejected: return nil
        }

        // shortcut: refusing returns nil and nothing counts it, so a mailbox of
        // unattested mail still looks empty rather than withheld, which is this
        // initializer's one remaining dishonesty.
        //
        // The driver has to count that itself. Do NOT look for it in `Harvest`:
        // its `refused` and `otherAo3Mail` tally what the CRATE rejected, and a
        // sender-only message is not rejected — it parses fine and arrives in
        // `harvest.readings` with its verdict attached. So the count comes from
        // the readings in hand (`verdict != .trusted`, or the nils this returns),
        // and needs no crate change. An earlier version of this comment pointed
        // at those two fields, which would have sent the next reader looking for
        // a counter that does not exist, or adding one that is not needed.

        let event = reading.event
        // Only the values AO3's unsubscribe URL supplies. `name` is the footer
        // SENTENCE, which an author can forge: the crate's own fixture
        // `f4_title_in_footer_moves_the_rule` asserts a work title can end the
        // layout rule early and plant a second sentence, yielding
        // `Author { username: "lamplighter", name: Some("impostor") }`. Printing
        // `name` would caption that row "Following impostor" for someone who
        // follows lamplighter. The username and the series id come from
        // `polymorphic_url` and cannot be moved.
        //
        // shortcut: a series therefore shows its id rather than its title,
        // because the title only ever arrives in the forgeable sentence; resolve
        // the real title from AO3 by id once the screen can fetch.
        let source: Source = switch event.via {
        case .work: .work
        case let .series(id, _): .series("Series #\(id)")
        case let .author(username, _): .author(username)
        case .unknown: .unknown
        }

        let chapterNumber: Int?
        let isNewWork: Bool
        let isContested: Bool
        switch event.kind {
        case .contested:
            chapterNumber = nil
            isNewWork = false
            isContested = true
        case let .newChapter(number):
            chapterNumber = number.map(Int.init)
            isNewWork = false
            isContested = false
        case .newWork:
            chapterNumber = nil
            isNewWork = true
            isContested = false
        }

        self.init(
            uid: reading.uid,
            workID: event.workId,
            chapterID: event.chapterId,
            chapterNumber: chapterNumber,
            isNewWork: isNewWork,
            isContested: isContested,
            isAnchoredToWork: event.identity == .work,
            workTitle: event.workTitle,
            author: event.author,
            at: Date(timeIntervalSince1970: TimeInterval(event.at)),
            source: source,
            extraCreations: event.extraCreations
        )
    }
}
#endif
