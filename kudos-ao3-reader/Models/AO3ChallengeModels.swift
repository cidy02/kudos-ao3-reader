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

/// Challenge dates are UTC on AO3. Round-trip through the device timezone by
/// converting the stored `Date` (an instant) locally at display time — never by
/// parsing/formatting the **wire** value with `DateFormatter.autoupdatingCurrent`,
/// which would drift as the zone or DST offset changes.
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

/// One of the five challenge schedule instants, kept as a UTC `Date` plus the
/// original wire string so an untouched field round-trips without reformatting.
nonisolated struct AO3ChallengeInstant: Hashable, Sendable {
    var date: Date?
    var wireString: String
    /// ActiveSupport zone name from the challenge form (`UTC`, `Eastern Time (US & Canada)`, …).
    var timeZoneName: String

    init(date: Date? = nil, wireString: String = "", timeZoneName: String = "UTC") {
        self.date = date
        self.wireString = wireString
        self.timeZoneName = timeZoneName.isEmpty ? "UTC" : timeZoneName
    }

    static func parse(_ raw: String?, timeZoneName: String = "UTC") -> AO3ChallengeInstant {
        let wire = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return AO3ChallengeInstant(
            date: AO3ChallengeUTCDate.parse(wire),
            wireString: wire,
            timeZoneName: timeZoneName
        )
    }

    /// Value posted on `gift_exchange[signups_open_at_string]` and friends.
    /// If the instant was edited (`date` set), emit POSIX UTC; otherwise keep
    /// the original wire string so an untouched field cannot drift.
    var postedString: String {
        if let date {
            return AO3ChallengeUTCDate.wireString(from: date)
        }
        return wireString
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
    var assignmentsSentAt: Date? = nil

    var id: String { collectionSlug }

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
            ("signups_open_at", settings.signupsOpenAt.date),
            ("signups_close_at", settings.signupsCloseAt.date),
            ("assignments_due_at", settings.assignmentsDueAt.date),
            ("works_reveal_at", settings.worksRevealAt.date),
            ("authors_reveal_at", settings.authorsRevealAt.date)
        ]
        for (index, current) in dates.enumerated() where index > 0 {
            if let earlier = dates[index - 1].1, let later = current.1, later < earlier {
                copy.fieldErrors[current.0] =
                    "This date is before the previous deadline. AO3 stores all five as UTC instants."
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

    /// One-line tag summary for the sign-up row (1bz).
    var tagSummary: String {
        var parts = fandoms + characters + relationships + freeforms
        if anyFandom { parts.append("Any Fandom") }
        if anyCharacter { parts.append("Any Character") }
        if anyRelationship { parts.append("Any Relationship") }
        if anyFreeform { parts.append("Any Additional Tag") }
        return parts.joined(separator: ", ")
    }
}

nonisolated struct AO3ChallengeAssignment: Hashable, Sendable, Identifiable {
    var id: Int
    var collectionSlug: String
    var requestSignupID: Int? = nil
    var offerSignupID: Int? = nil
    var requestPseud: String = ""
    var offerPseud: String = ""
    var pinchHitterPseud: String = ""
    var isDefaulted: Bool = false
    var isFulfilled: Bool = false
    var isCovered: Bool = false
    var sentAt: Date? = nil

    var isMatched: Bool {
        // No parser sets `requestSignupID`, and AO3's Complete tab never links the
        // request sign-up at all — the join proves the request side, so a giver is
        // what makes it matched.
        offerSignupID != nil || !offerPseud.isEmpty
    }
}

nonisolated struct AO3ChallengeSignUp: Hashable, Sendable, Identifiable {
    var id: Int
    var collectionSlug: String
    var pseud: String
    var pseudID: String = ""
    var userURL: URL? = nil
    var requests: [AO3ChallengePrompt] = []
    var offers: [AO3ChallengePrompt] = []
    /// Joined from the assignments object, never from the sign-up itself (1bz).
    var assignment: AO3ChallengeAssignment? = nil

    var isMatched: Bool { assignment?.isMatched == true }

    var requestTagSummary: String {
        requests.map(\.tagSummary).filter { !$0.isEmpty }.joined(separator: " · ")
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
    case assignments
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
    var claimID: Int? = nil
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
    var actionURL: URL? = nil
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
