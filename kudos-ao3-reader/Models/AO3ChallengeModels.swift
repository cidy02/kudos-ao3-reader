import Foundation

/// AO3 stores a challenge as a second object on top of a collection. Gift
/// exchange and prompt meme are two layouts, not a toggle — UI switches on this.
nonisolated enum AO3ChallengeKind: String, Hashable, Sendable, Codable {
    case giftExchange
    case promptMeme

    var otwarchiveType: String {
        switch self {
        case .giftExchange: "GiftExchange"
        case .promptMeme: "PromptMeme"
        }
    }

    /// What a reader sees. Separate from `otwarchiveType`, which is AO3's wire
    /// value and would read as a class name on a chip.
    var displayName: String {
        switch self {
        case .giftExchange: "Gift Exchange"
        case .promptMeme: "Prompt Meme"
        }
    }

    init?(otwarchiveType: String) {
        switch otwarchiveType.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "GiftExchange", "gift_exchange", "gift exchange":
            self = .giftExchange
        case "PromptMeme", "prompt_meme", "prompt meme":
            self = .promptMeme
        default:
            return nil
        }
    }
}

// MARK: - UTC wire dates

/// POSIX parsing and formatting with a fixed GMT formatter, so the device zone
/// never touches a wire value. `AO3ChallengeInstant` uses it to carry AO3's
/// wall-clock digits unchanged; which zone those digits are in is its concern.
///
/// Wire formatters are ISO 8601 and POSIX `en_US_POSIX` + GMT. Built per call
/// so they are not shared mutable `DateFormatter` state.
nonisolated enum AO3ChallengeUTCDate {
    static func iso8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    static func iso8601FormatterNoFraction() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    static func posixUTCFormatter(dateFormat: String = "yyyy-MM-dd HH:mm:ss") -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = dateFormat
        return formatter
    }

    /// Parses an AO3 challenge datetime. Accepts ISO 8601 (`…Z` / offset) and
    /// POSIX UTC `yyyy-MM-dd HH:mm[:ss]` (optional trailing ` UTC` / `Z`).
    static func parse(_ raw: String?) -> Date? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        if let date = iso8601Formatter().date(from: trimmed) { return date }
        if let date = iso8601FormatterNoFraction().date(from: trimmed) { return date }
        var candidate = trimmed
        if candidate.hasSuffix(" UTC") || candidate.hasSuffix(" gmt") {
            candidate = String(candidate.dropLast(4)).trimmingCharacters(in: .whitespaces)
        }
        if candidate.hasSuffix("Z"), candidate.count > 1 {
            candidate = String(candidate.dropLast())
        }
        candidate = candidate.replacingOccurrences(of: "T", with: " ")
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd"
        ]
        for format in formats {
            if let date = posixUTCFormatter(dateFormat: format).date(from: candidate) {
                return date
            }
        }
        return nil
    }

    /// Formats `date` as POSIX UTC `yyyy-MM-dd HH:mm:ss` for AO3's
    /// `*_at_string` fields. Passing `time_zone=UTC` with this string avoids
    /// zone conversion on the wire.
    static func wireString(from date: Date?) -> String {
        guard let date else { return "" }
        return posixUTCFormatter().string(from: date)
    }

    static func iso8601String(from date: Date?) -> String {
        guard let date else { return "" }
        return iso8601FormatterNoFraction().string(from: date)
    }
}

/// One challenge schedule date. AO3's `*_at_string` fields are wall-clock times
/// in the challenge's own `time_zone` (the form's select), not UTC, so the digits
/// are kept as they are and posted back with that zone: an untouched date cannot
/// move. `wallClock` carries those digits in a `Date` read as UTC — format it in
/// UTC to get AO3's own text back; it is not the moment itself (`instant` is).
nonisolated struct AO3ChallengeInstant: Hashable, Sendable {
    var wallClock: Date?
    var wireString: String
    /// The challenge form's zone (`UTC`, an IANA id, or a Rails name such as
    /// `Eastern Time (US & Canada)`).
    var timeZoneName: String
    /// AO3 renders works_reveal_at only for unrevealed collections and
    /// authors_reveal_at only for anonymous ones (Q4). A date whose input was not
    /// on the form is never posted: an empty value would clear it.
    var isOnForm: Bool = true

    init(wallClock: Date? = nil, wireString: String = "", timeZoneName: String = "UTC", isOnForm: Bool = true) {
        self.wallClock = wallClock
        self.wireString = wireString
        self.timeZoneName = timeZoneName.isEmpty ? "UTC" : timeZoneName
        self.isOnForm = isOnForm
    }

    static func parse(_ raw: String?, timeZoneName: String = "UTC", isOnForm: Bool = true) -> AO3ChallengeInstant {
        let wire = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return AO3ChallengeInstant(
            wallClock: AO3ChallengeUTCDate.parse(wire),
            wireString: wire,
            timeZoneName: timeZoneName,
            isOnForm: isOnForm
        )
    }

    /// The moment itself, for comparing with now.
    ///
    /// ponytail: resolves only zones Foundation knows (UTC and IANA ids). A Rails
    /// name such as "Eastern Time (US & Canada)" gives `nil`, so no late claim is
    /// made; add ActiveSupport's zone MAPPING if challenges turn out to use them.
    var instant: Date? {
        guard let wallClock, let zone = TimeZone(identifier: timeZoneName) else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var local = utc
        local.timeZone = zone
        return local.date(from: utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: wallClock))
    }

    /// Value posted on `gift_exchange[signups_open_at_string]` and friends, in
    /// `timeZoneName`: the edited digits, or the original text if unparsed.
    var postedString: String {
        if let wallClock {
            return AO3ChallengeUTCDate.wireString(from: wallClock)
        }
        return wireString
    }

    /// AO3's own date, as its profile page prints it in the challenge's zone.
    var dateText: String? {
        guard let wallClock else { return wireString.isEmpty ? nil : wireString }
        return wallClock.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt))
    }
}

// MARK: - Settings

nonisolated struct AO3ChallengeSignUpLimits: Hashable, Sendable {
    var requestsRequired: Int = 1
    var requestsAllowed: Int = 1
    var offersRequired: Int = 1
    var offersAllowed: Int = 1
}

nonisolated struct AO3PromptRestrictionSnapshot: Hashable, Sendable {
    var id: String = ""
    var optionalTagsAllowed: Bool = false
    var titleRequired: Bool = false
    var titleAllowed: Bool = false
    var descriptionRequired: Bool = false
    var descriptionAllowed: Bool = false
    var urlRequired: Bool = false
    var urlAllowed: Bool = false
    var fandomRequired: Int = 0
    var fandomAllowed: Int = 0
    var allowAnyFandom: Bool = false
    var requireUniqueFandom: Bool = false
    var characterRequired: Int = 0
    var characterAllowed: Int = 0
    var allowAnyCharacter: Bool = false
    var requireUniqueCharacter: Bool = false
    var relationshipRequired: Int = 0
    var relationshipAllowed: Int = 0
    var allowAnyRelationship: Bool = false
    var requireUniqueRelationship: Bool = false
    var freeformRequired: Int = 0
    var freeformAllowed: Int = 0
    var allowAnyFreeform: Bool = false
    var requireUniqueFreeform: Bool = false
    var ratingRequired: Int = 0
    var ratingAllowed: Int = 0
    var categoryRequired: Int = 0
    var categoryAllowed: Int = 0
    var archiveWarningRequired: Int = 0
    var archiveWarningAllowed: Int = 0
    var tagSetsToAdd: String = ""

    /// 1by's "Allow any prompt": whether a request may pick AO3's "Any" option
    /// for any of the four tag types.
    var allowsAnyTag: Bool {
        allowAnyFandom || allowAnyCharacter || allowAnyRelationship || allowAnyFreeform
    }
}

/// Gift-exchange / prompt-meme settings as AO3 stores them on the challenge
/// object. Matching is **not** a client write — use `matchingOpenOnAO3`.
nonisolated struct AO3ChallengeSettings: Hashable, Sendable, Identifiable {
    var collectionSlug: String
    var kind: AO3ChallengeKind
    var signupOpen: Bool = false
    var timeZoneName: String = "UTC"
    /// The five dates, in AO3's own order (1by / 1cf).
    var signupsOpenAt: AO3ChallengeInstant = AO3ChallengeInstant()
    var signupsCloseAt: AO3ChallengeInstant = AO3ChallengeInstant()
    var assignmentsDueAt: AO3ChallengeInstant = AO3ChallengeInstant()
    var worksRevealAt: AO3ChallengeInstant = AO3ChallengeInstant()
    var authorsRevealAt: AO3ChallengeInstant = AO3ChallengeInstant()
    var limits: AO3ChallengeSignUpLimits = AO3ChallengeSignUpLimits()
    var requestsSummaryVisible: Bool = false
    var isAnonymous: Bool = false
    var signupInstructionsGeneral: String = ""
    var signupInstructionsRequests: String = ""
    var signupInstructionsOffers: String = ""
    var requestURLLabel: String = ""
    var offerURLLabel: String = ""
    var requestDescriptionLabel: String = ""
    var offerDescriptionLabel: String = ""
    var requestRestriction: AO3PromptRestrictionSnapshot = AO3PromptRestrictionSnapshot()
    var offerRestriction: AO3PromptRestrictionSnapshot = AO3PromptRestrictionSnapshot()
    var assignmentsSentAt: Date?

    var id: String { collectionSlug }

    /// When works are due. otwarchive prints `assignments_due_at` as "Assignments
    /// Due:" and mails it as the due date; `works_reveal_at` is only the reveal.
    var worksDueAt: AO3ChallengeInstant { assignmentsDueAt }

    /// AO3 matching is not exposed to clients (`potential_matches#generate`).
    var matchingOpenOnAO3: URL {
        AO3ChallengeURL.potentialMatches(slug: collectionSlug)
    }
}

/// Editable challenge-settings DTO. Local validation runs first so a failed
/// AO3 round-trip can return this same value with `fieldErrors` populated
/// instead of discarding the caller's input.
nonisolated struct AO3ChallengeSettingsForm: Hashable, Sendable {
    var actionURL: URL
    var httpMethodOverride: String?
    var csrfToken: String
    var kind: AO3ChallengeKind
    var collectionSlug: String
    var settings: AO3ChallengeSettings
    var fieldErrors: [String: String] = [:]
    var generalErrors: [String] = []
    var hiddenFields: [(name: String, value: String)] = []

    var isValid: Bool { fieldErrors.isEmpty && generalErrors.isEmpty }

    /// Client-side checks that mirror GiftExchange/PromptMeme date + limit
    /// validations. Does not POST.
    func validated() -> AO3ChallengeSettingsForm {
        var copy = self
        copy.fieldErrors = [:]
        copy.generalErrors = []
        let dates: [(String, Date?)] = [
            ("signups_open_at", settings.signupsOpenAt.wallClock),
            ("signups_close_at", settings.signupsCloseAt.wallClock),
            ("assignments_due_at", settings.assignmentsDueAt.wallClock),
            ("works_reveal_at", settings.worksRevealAt.wallClock),
            ("authors_reveal_at", settings.authorsRevealAt.wallClock)
        ]
        // All five are in the challenge's one zone, so wall clocks compare.
        for (index, current) in dates.enumerated() where index > 0 {
            if let earlier = dates[index - 1].1, let later = current.1, later < earlier {
                copy.fieldErrors[current.0] = "This date is before the previous deadline."
            }
        }
        if settings.limits.requestsRequired < 1 {
            copy.fieldErrors["requests_num_required"] = "At least one request is required."
        }
        if settings.limits.requestsRequired > settings.limits.requestsAllowed {
            copy.fieldErrors["requests_num_allowed"] =
                "Allowed requests cannot be fewer than required requests."
        }
        if settings.kind == .giftExchange {
            if settings.limits.offersRequired < 1 {
                copy.fieldErrors["offers_num_required"] = "At least one offer is required."
            }
            if settings.limits.offersRequired > settings.limits.offersAllowed {
                copy.fieldErrors["offers_num_allowed"] =
                    "Allowed offers cannot be fewer than required offers."
            }
        }
        return copy
    }

    static func == (lhs: AO3ChallengeSettingsForm, rhs: AO3ChallengeSettingsForm) -> Bool {
        lhs.actionURL == rhs.actionURL
            && lhs.httpMethodOverride == rhs.httpMethodOverride
            && lhs.csrfToken == rhs.csrfToken
            && lhs.kind == rhs.kind
            && lhs.collectionSlug == rhs.collectionSlug
            && lhs.settings == rhs.settings
            && lhs.fieldErrors == rhs.fieldErrors
            && lhs.generalErrors == rhs.generalErrors
            && lhs.hiddenFields.map(\.name) == rhs.hiddenFields.map(\.name)
            && lhs.hiddenFields.map(\.value) == rhs.hiddenFields.map(\.value)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(actionURL)
        hasher.combine(csrfToken)
        hasher.combine(kind)
        hasher.combine(collectionSlug)
        hasher.combine(settings)
        hasher.combine(fieldErrors)
        hasher.combine(generalErrors)
    }
}

nonisolated enum AO3ChallengeSettingsSaveOutcome: Sendable {
    case saved(message: String, form: AO3ChallengeSettingsForm)
    /// Local or AO3 validation failed. `form` still holds the submitted values.
    case invalid(AO3ChallengeSettingsForm)
}

// MARK: - Sign-ups / prompts / assignments

nonisolated enum AO3ChallengePromptKind: String, Hashable, Sendable {
    case request
    case offer
}

nonisolated struct AO3ChallengePrompt: Hashable, Sendable, Identifiable {
    var id: Int
    var kind: AO3ChallengePromptKind
    var title: String = ""
    var promptText: String = ""
    var url: String = ""
    var isAnonymous: Bool = false
    var fandoms: [String] = []
    var characters: [String] = []
    var relationships: [String] = []
    var freeforms: [String] = []
    var anyFandom: Bool = false
    var anyCharacter: Bool = false
    var anyRelationship: Bool = false
    var anyFreeform: Bool = false
    var destroy: Bool = false
    /// Read-only, from the sign-ups index's `ul.optional.tags` (1bz detail).
    var optionalTags: [String] = []
}

nonisolated struct AO3ChallengeAssignment: Hashable, Sendable, Identifiable {
    var id: Int
    var collectionSlug: String
    var requestSignupID: Int?
    var offerSignupID: Int?
    var requestPseud: String = ""
    var offerPseud: String = ""
    var pinchHitterPseud: String = ""
    var isDefaulted: Bool = false
    var isFulfilled: Bool = false
    var isCovered: Bool = false
    var sentAt: Date?

    var isMatched: Bool {
        // Complete rows omit signup IDs; the join can prove the recipient by
        // byline instead. A giver is what makes the joined request matched.
        offerSignupID != nil || !offerPseud.isEmpty
    }

    enum Badge { case delivered, late, defaulted }

    /// 1cb's row badge. Late is derived, not parsed: past the challenge's
    /// works-due date and not complete. No due date, no late claim.
    func badge(dueAt: Date?, now: Date = .now) -> Badge? {
        if isFulfilled { return .delivered }
        if isDefaulted { return .defaulted }
        if let dueAt, now > dueAt { return .late }
        return nil
    }
}

nonisolated struct AO3ChallengeSignUp: Hashable, Sendable, Identifiable {
    var id: Int
    var collectionSlug: String
    var pseud: String
    var pseudID: String = ""
    var requests: [AO3ChallengePrompt] = []
    var offers: [AO3ChallengePrompt] = []
    /// Joined from the assignments object, never from the sign-up itself (1bz).
    var assignment: AO3ChallengeAssignment?

    /// A defaulted, uncovered assignment has lost its giver: 1cb lists it
    /// under "Unmatched sign-ups", so it is not matched here either.
    var isMatched: Bool { assignment.map { $0.isMatched && !$0.isDefaulted } ?? false }

    /// The distinct fandoms the sign-up requests, in order (1bz's one-liner).
    var requestTagSummary: String {
        var seen = Set<String>()
        return requests.flatMap { $0.fandoms + ($0.anyFandom ? ["Any Fandom"] : []) }
            .filter { seen.insert($0).inserted }.joined(separator: ", ")
    }
}

nonisolated struct AO3ChallengeSignUpPage: Hashable, Sendable {
    var signUps: [AO3ChallengeSignUp]
    var currentPage: Int
    var totalPages: Int
}

nonisolated struct AO3ChallengeSignUpForm: Hashable, Sendable {
    var actionURL: URL
    var httpMethodOverride: String?
    var csrfToken: String
    var collectionSlug: String
    var signUpID: Int?
    var pseudID: String
    var requests: [AO3ChallengePrompt]
    var offers: [AO3ChallengePrompt]
    var fieldErrors: [String: String] = [:]
    var generalErrors: [String] = []
    var hiddenFields: [(name: String, value: String)] = []
    var limits: AO3ChallengeSignUpLimits = AO3ChallengeSignUpLimits()

    var isNew: Bool { signUpID == nil }
    var isValid: Bool { fieldErrors.isEmpty && generalErrors.isEmpty }

    /// Unsaved prompts take negative ids, one below the lowest in use, so
    /// `ForEach` identity stays unique. Only AO3's own (positive) ids are posted.
    var nextDraftPromptID: Int { min(0, (requests + offers).map(\.id).min() ?? 0) - 1 }

    /// Rows list only live prompts (`destroy` filtered out), so a row's position
    /// is not a position in `requests`/`offers`: prompts are found by id and kind.
    func prompt(id: Int, kind: AO3ChallengePromptKind) -> AO3ChallengePrompt? {
        (kind == .request ? requests : offers).first { $0.id == id }
    }

    /// Writes back the prompt with the same id and kind; one that has gone is not recreated.
    mutating func updatePrompt(_ prompt: AO3ChallengePrompt) {
        if prompt.kind == .request, let index = requests.firstIndex(where: { $0.id == prompt.id }) {
            requests[index] = prompt
        } else if prompt.kind == .offer, let index = offers.firstIndex(where: { $0.id == prompt.id }) {
            offers[index] = prompt
        }
    }

    func validated() -> AO3ChallengeSignUpForm {
        var copy = self
        copy.fieldErrors = [:]
        copy.generalErrors = []
        let liveRequests = requests.filter { !$0.destroy }
        let liveOffers = offers.filter { !$0.destroy }
        if liveRequests.count < limits.requestsRequired {
            copy.fieldErrors["requests"] =
                "This challenge requires at least \(limits.requestsRequired) request(s)."
        }
        if liveRequests.count > limits.requestsAllowed {
            copy.fieldErrors["requests"] =
                "This challenge allows at most \(limits.requestsAllowed) request(s)."
        }
        if liveOffers.count < limits.offersRequired {
            copy.fieldErrors["offers"] =
                "This challenge requires at least \(limits.offersRequired) offer(s)."
        }
        if liveOffers.count > limits.offersAllowed {
            copy.fieldErrors["offers"] =
                "This challenge allows at most \(limits.offersAllowed) offer(s)."
        }
        return copy
    }

    static func == (lhs: AO3ChallengeSignUpForm, rhs: AO3ChallengeSignUpForm) -> Bool {
        lhs.actionURL == rhs.actionURL
            && lhs.httpMethodOverride == rhs.httpMethodOverride
            && lhs.csrfToken == rhs.csrfToken
            && lhs.collectionSlug == rhs.collectionSlug
            && lhs.signUpID == rhs.signUpID
            && lhs.pseudID == rhs.pseudID
            && lhs.requests == rhs.requests
            && lhs.offers == rhs.offers
            && lhs.fieldErrors == rhs.fieldErrors
            && lhs.generalErrors == rhs.generalErrors
            && lhs.limits == rhs.limits
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(actionURL)
        hasher.combine(csrfToken)
        hasher.combine(collectionSlug)
        hasher.combine(signUpID)
        hasher.combine(pseudID)
        hasher.combine(requests)
        hasher.combine(offers)
        hasher.combine(limits)
    }
}

nonisolated struct AO3ChallengeAssignmentPage: Hashable, Sendable {
    var assignments: [AO3ChallengeAssignment]
    var currentPage: Int
    var totalPages: Int
}

nonisolated enum AO3ChallengeAssignmentList: String, Hashable, Sendable {
    /// Defaulted and uncovered — the unmatched/default queue a moderator acts on (1cb).
    case defaults
    case pinchHits
    case unfulfilled
    case assignments

    /// Every sent assignment: Complete (?fulfilled) plus Open (?unfulfilled),
    /// which already includes pinch-hit covers (Q3). 1cb's Matched, 1by's count.
    static let sent: [Self] = [.assignments, .unfulfilled]
}

nonisolated struct AO3PromptMemePrompt: Hashable, Sendable, Identifiable {
    var id: Int
    var collectionSlug: String
    var promptText: String
    var title: String = ""
    var tagSummary: String = ""
    var isAnonymous: Bool = false
    /// Hidden when `isAnonymous` even if a later cache knows the owner (1cc).
    var ownerPseud: String?
    var claimID: Int?
    var claimedByCurrentUser: Bool = false
    var isClaimed: Bool { claimID != nil }

    var displayedOwner: String? {
        isAnonymous ? nil : ownerPseud
    }
}

nonisolated struct AO3PromptMemePage: Hashable, Sendable {
    var prompts: [AO3PromptMemePrompt]
    var currentPage: Int
    var totalPages: Int
}

// MARK: - Tag sets

nonisolated enum AO3TagNominationState: String, Hashable, Sendable {
    case unreviewed
    case approved
    case rejected
}

nonisolated enum AO3TagSetField: String, Hashable, Sendable, CaseIterable {
    case fandom
    case character
    case relationship
    case freeform

    var tagnamesToAddParam: String {
        "owned_tag_set[tag_set_attributes][\(rawValue)_tagnames_to_add]"
    }

    var nominationLimitParam: String {
        "owned_tag_set[\(rawValue)_nomination_limit]"
    }
}

nonisolated struct AO3TagNomination: Hashable, Sendable, Identifiable {
    var id: Int
    var tagName: String
    var field: AO3TagSetField
    var state: AO3TagNominationState
    var synonym: String = ""
    var parentTagName: String = ""
}

nonisolated struct AO3TagSet: Hashable, Sendable, Identifiable {
    var id: Int
    var title: String
    var description: String = ""
    var isVisible: Bool = true
    var isNominated: Bool = false
    var fandomCount: Int = 0
    var characterCount: Int = 0
    var relationshipCount: Int = 0
    var freeformCount: Int = 0
    var fandomNominationLimit: Int = 0
    var characterNominationLimit: Int = 0
    var relationshipNominationLimit: Int = 0
    var freeformNominationLimit: Int = 0
    /// Four comma-separated tag-name fields AO3 saves together.
    var fandomTagnames: String = ""
    var characterTagnames: String = ""
    var relationshipTagnames: String = ""
    var freeformTagnames: String = ""
    var reviewQueue: [AO3TagNomination] = []
    var csrfToken: String = ""
    var actionURL: URL?
    var httpMethodOverride: String? = "put"

    /// Finishing tag-set association is not a client write.
    var associationOpenOnAO3: URL {
        AO3ChallengeURL.tagSetAssociations(id: id)
    }
}

nonisolated struct AO3TagSetSave: Hashable, Sendable {
    var fandomTagnames: String
    var characterTagnames: String
    var relationshipTagnames: String
    var freeformTagnames: String
}

// MARK: - URLs (challenge-specific; not generic enough for AO3URLResolver)

nonisolated enum AO3ChallengeURL {
    static let host = "https://archiveofourown.org"

    static func giftExchangeEdit(slug: String) -> URL {
        URL(string: "\(host)/collections/\(slug)/gift_exchange/edit")!
    }

    static func giftExchange(slug: String) -> URL {
        URL(string: "\(host)/collections/\(slug)/gift_exchange")!
    }

    static func promptMemeEdit(slug: String) -> URL {
        URL(string: "\(host)/collections/\(slug)/prompt_meme/edit")!
    }

    static func promptMeme(slug: String) -> URL {
        URL(string: "\(host)/collections/\(slug)/prompt_meme")!
    }

    static func signUps(slug: String, page: Int = 1) -> URL {
        paged("/collections/\(slug)/signups", page: page)
    }

    static func signUp(slug: String, id: Int) -> URL {
        URL(string: "\(host)/collections/\(slug)/signups/\(id)")!
    }

    static func newSignUp(slug: String) -> URL {
        URL(string: "\(host)/collections/\(slug)/signups/new")!
    }

    static func editSignUp(slug: String, id: Int) -> URL {
        URL(string: "\(host)/collections/\(slug)/signups/\(id)/edit")!
    }

    static func confirmDeleteSignUp(slug: String, id: Int) -> URL {
        URL(string: "\(host)/collections/\(slug)/signups/\(id)/confirm_delete")!
    }

    static func assignments(slug: String, list: AO3ChallengeAssignmentList, page: Int = 1) -> URL {
        var items: [URLQueryItem] = []
        switch list {
        case .defaults: break
        case .pinchHits: items.append(URLQueryItem(name: "pinch_hit", value: "true"))
        case .unfulfilled: items.append(URLQueryItem(name: "unfulfilled", value: "true"))
        case .assignments: items.append(URLQueryItem(name: "fulfilled", value: "true"))
        }
        if page > 1 { items.append(URLQueryItem(name: "page", value: String(page))) }
        var components = URLComponents(string: "\(host)/collections/\(slug)/assignments")!
        if !items.isEmpty { components.queryItems = items }
        return components.url!
    }

    static func assignmentDefault(slug: String, id: Int) -> URL {
        URL(string: "\(host)/collections/\(slug)/assignments/\(id)/default")!
    }

    static func assignmentUpdateMultiple(slug: String) -> URL {
        URL(string: "\(host)/collections/\(slug)/assignments/update_multiple")!
    }

    static func requests(slug: String, page: Int = 1) -> URL {
        paged("/collections/\(slug)/requests", page: page)
    }

    static func claims(slug: String, page: Int = 1, forUser: Bool = false) -> URL {
        var components = URLComponents(string: "\(host)/collections/\(slug)/claims")!
        var items: [URLQueryItem] = []
        if forUser { items.append(URLQueryItem(name: "for_user", value: "true")) }
        if page > 1 { items.append(URLQueryItem(name: "page", value: String(page))) }
        if !items.isEmpty { components.queryItems = items }
        return components.url!
    }

    static func claim(slug: String, id: Int) -> URL {
        URL(string: "\(host)/collections/\(slug)/claims/\(id)")!
    }

    static func potentialMatches(slug: String) -> URL {
        URL(string: "\(host)/collections/\(slug)/potential_matches")!
    }

    static func tagSet(_ id: Int) -> URL {
        URL(string: "\(host)/tag_sets/\(id)")!
    }

    static func tagSetEdit(_ id: Int) -> URL {
        URL(string: "\(host)/tag_sets/\(id)/edit")!
    }

    static func tagSetNominations(_ id: Int) -> URL {
        URL(string: "\(host)/tag_sets/\(id)/nominations")!
    }

    static func tagSetAssociations(id: Int) -> URL {
        URL(string: "\(host)/tag_sets/\(id)/associations")!
    }

    static func paged(_ path: String, page: Int) -> URL {
        var components = URLComponents(string: "\(host)\(path)")!
        if page > 1 {
            components.queryItems = [URLQueryItem(name: "page", value: String(page))]
        }
        return components.url!
    }
}

/// Join matched-state from the assignments object onto sign-up rows (1bz).
nonisolated enum AO3ChallengeSignUpMatching {
    enum State { case matched, unmatched, unknown }

    /// Match state needs assignment rows. Without them — the fetch failed (`nil`),
    /// AO3 withholds the lists while sign-ups are open, or they are all empty
    /// because nothing has been sent yet — no row can honestly be called unmatched.
    static func state(of signUp: AO3ChallengeSignUp, assignments: [AO3ChallengeAssignment]?) -> State {
        guard let assignments, !assignments.isEmpty else { return .unknown }
        return signUp.isMatched ? .matched : .unmatched
    }

    /// The viewer's own row, by byline: otwarchive prints `name` for a default
    /// pseud and `name (login)` otherwise.
    static func ownSignUpID(in signUps: [AO3ChallengeSignUp], login: String) -> Int? {
        let login = login.lowercased()
        guard !login.isEmpty else { return nil }
        return signUps.first {
            let byline = $0.pseud.lowercased()
            return byline == login || byline.hasSuffix("(\(login))")
        }?.id
    }

    static func joining(
        _ signUps: [AO3ChallengeSignUp],
        assignments: [AO3ChallengeAssignment]
    ) -> [AO3ChallengeSignUp] {
        var bySignupID: [Int: AO3ChallengeAssignment] = [:]
        var byRequestPseud: [String: AO3ChallengeAssignment] = [:]
        for assignment in assignments {
            if let id = assignment.requestSignupID {
                bySignupID[id] = assignment
            }
            let key = assignment.requestPseud.lowercased()
            if !key.isEmpty, byRequestPseud[key] == nil {
                byRequestPseud[key] = assignment
            }
        }
        return signUps.map { signUp in
            var copy = signUp
            copy.assignment = bySignupID[signUp.id]
                ?? byRequestPseud[signUp.pseud.lowercased()]
            return copy
        }
    }
}

/// Rows behind a "Load more" button (1bz). A page counts only once it has loaded,
/// so a failed page leaves `rows` and `loadedPages` alone: Load more stays and
/// retries that page rather than skipping it.
nonisolated struct AO3LoadMorePages<Row: Sendable>: Sendable {
    private(set) var rows: [Row] = []
    private(set) var loadedPages = 0
    private(set) var totalPages = 1

    var hasMore: Bool { loadedPages < totalPages }

    mutating func loadNext(_ fetch: (Int) async throws -> (rows: [Row], totalPages: Int)) async throws {
        let page = loadedPages + 1
        let result = try await fetch(page)
        rows += result.rows
        loadedPages = page
        totalPages = result.totalPages
    }
}

/// Count labels that say what was actually read (1bz, 1by, 1cc, 1cf).
nonisolated enum AO3ChallengeCountText {
    static func plural(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    /// A count taken from one page of several is labelled with that page.
    static func pageQualifier(page: Int, totalPages: Int) -> String? {
        totalPages > 1 ? "on page \(page) of \(totalPages)" : nil
    }
}
