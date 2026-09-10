import Foundation

/// Result of the URL-name uniqueness probe. AO3 has no cheap HEAD or
/// autocomplete-for-availability endpoint (`Collection` validates uniqueness
/// on save only). The client GETs `/collections/<name>` through `AO3Client`
/// (coordinator-wrapped): **404 → available**, **200 → taken**, anything else
/// → **unknown**. Reserved routes (`new`, `list_challenges`, …) are taken.
nonisolated enum AO3CollectionNameAvailability: String, Hashable, Sendable {
    case available
    case taken
    case unknown
    case invalid
}

nonisolated enum AO3CollectionParticipantRole: String, Hashable, Sendable {
    case none = "None"
    case owner = "Owner"
    case moderator = "Moderator"
    case member = "Member"
    case invited = "Invited"

    init?(ao3: String) {
        let trimmed = ao3.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "none": self = .none
        case "owner": self = .owner
        case "moderator": self = .moderator
        case "member": self = .member
        case "invited": self = .invited
        default: return nil
        }
    }

    var isMaintainer: Bool { self == .owner || self == .moderator }
    var isMembershipRequest: Bool { self == .none }
    var isInvitation: Bool { self == .invited }
}

nonisolated struct AO3CollectionParticipant: Hashable, Sendable, Identifiable {
    var id: Int
    var collectionSlug: String
    var pseud: String
    var role: AO3CollectionParticipantRole
    var identity: AO3AuthorIdentity? = nil
    var updateURL: URL? = nil
}

nonisolated struct AO3CollectionPerson: Hashable, Sendable, Identifiable {
    var id: String { identity.id }
    var identity: AO3AuthorIdentity
    var workCount: Int? = nil
}

nonisolated struct AO3CollectionPeoplePage: Hashable, Sendable {
    var people: [AO3CollectionPerson]
    var currentPage: Int
    var totalPages: Int
}

/// AO3 maintainer item tabs (`collection_items#index` `status:`). The five
/// pills 1s draws map onto these, not a synthetic "all"/"unposted" pair —
/// AO3's else-branch is unreviewed-by-collection, and unposted is a property
/// of the item (`posted?`), not a status filter.
nonisolated enum AO3CollectionItemTab: String, Hashable, Sendable, CaseIterable {
    case unreviewed = "unreviewed_by_collection"
    case invited = "unreviewed_by_user"
    case rejected = "rejected_by_collection"
    case rejectedByUser = "rejected_by_user"
    case approved = "approved"

    var queryValue: String? {
        // Default maintainer landing omits `status` and AO3 applies unreviewed.
        self == .unreviewed ? nil : rawValue
    }
}

nonisolated enum AO3CollectionItemApproval: String, Hashable, Sendable {
    case unreviewed
    case approved
    case rejected

    init?(ao3: String) {
        switch ao3.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "unreviewed", "": self = .unreviewed
        case "approved": self = .approved
        case "rejected": self = .rejected
        default: return nil
        }
    }
}

nonisolated struct AO3CollectionItem: Hashable, Sendable, Identifiable {
    var id: Int
    var collectionSlug: String
    var collectionTitle: String
    var workTitle: String
    var workURL: URL? = nil
    var workID: Int? = nil
    var itemType: String = "Work"
    var role: String = ""
    var creatorApproval: AO3CollectionItemApproval = .unreviewed
    var moderatorApproval: AO3CollectionItemApproval = .unreviewed
    var isUnrevealed: Bool = false
    var isAnonymous: Bool = false
    var isPosted: Bool = true
    var recipient: String = ""
    var creatorByline: String = ""
    /// Tokens needed to stage then submit item updates (`collection_items[id][…]`).
    var userApprovalField: String
    var collectionApprovalField: String
    var unrevealedField: String
    var anonymousField: String
    var removeField: String
}

nonisolated struct AO3CollectionItemsPage: Hashable, Sendable {
    var items: [AO3CollectionItem]
    var tab: AO3CollectionItemTab
    var currentPage: Int
    var totalPages: Int
    var actionURL: URL
    var csrfToken: String
    var httpMethodOverride: String?
}

nonisolated struct AO3CollectionItemDraft: Hashable, Sendable {
    var itemID: Int
    var creatorApproval: AO3CollectionItemApproval?
    var moderatorApproval: AO3CollectionItemApproval?
    var isUnrevealed: Bool?
    var isAnonymous: Bool?
    var remove: Bool = false
}

nonisolated struct AO3CollectionShow: Hashable, Sendable, Identifiable {
    var collection: AO3Collection
    var headerImageURL: URL? = nil
    var introduction: String = ""
    var faq: String = ""
    var rules: String = ""
    var canJoin: Bool = false
    var canLeave: Bool = false
    var leaveParticipantID: Int? = nil
    var canPostWork: Bool = false
    var isMaintainer: Bool = false
    var dashboard: AO3CollectionDashboard = AO3CollectionDashboard()

    var id: String { collection.name }

    var deleteOpenOnAO3: URL { AO3CollectionURL.confirmDelete(slug: collection.name) }
    var closeOpenOnAO3: URL { AO3CollectionURL.edit(slug: collection.name) }
}

nonisolated struct AO3CollectionDashboard: Hashable, Sendable {
    var profileURL: URL? = nil
    var worksURL: URL? = nil
    var bookmarksURL: URL? = nil
    var peopleURL: URL? = nil
    var itemsURL: URL? = nil
    var participantsURL: URL? = nil
    var signUpsURL: URL? = nil
    var assignmentsURL: URL? = nil
    var promptsURL: URL? = nil
    var challengeSettingsURL: URL? = nil
    var postToCollectionURL: URL? = nil
}

nonisolated struct AO3CollectionForm: Hashable, Sendable {
    var actionURL: URL
    var httpMethodOverride: String?
    var csrfToken: String
    var isNew: Bool
    var collectionSlug: String
    // Header
    var name: String
    /// Artboard 1bl locks the URL name on edit even though AO3's form still
    /// posts `collection[name]`. Always POST the existing name on update.
    var nameIsLocked: Bool
    var title: String
    var parentName: String
    var email: String
    var headerImageURL: String
    var headerImageAlt: String
    var iconURL: URL?
    var iconAlt: String
    var iconComment: String
    var deleteIcon: Bool
    var description: String
    var tagString: String
    var isMultifandom: Bool
    var ownerPseudIDs: [String]
    // Preferences — four independent bools
    var isClosed: Bool
    var isModerated: Bool
    var isUnrevealed: Bool
    var isAnonymous: Bool
    var showRandom: Bool
    var emailNotify: Bool
    var challengeType: String
    var preferenceID: String
    // Profile
    var introduction: String
    var faq: String
    var rules: String
    var giftNotification: String
    var assignmentNotification: String
    var profileID: String
    var maintainers: [AO3CollectionParticipant]
    var invitationField: String
    var revealScheduleText: String
    var fieldErrors: [String: String]
    var generalErrors: [String]
    var hiddenFields: [(name: String, value: String)]

    var deleteOpenOnAO3: URL? {
        isNew ? nil : AO3CollectionURL.confirmDelete(slug: collectionSlug)
    }
    var closeOpenOnAO3: URL? {
        isNew ? nil : AO3CollectionURL.edit(slug: collectionSlug)
    }

    var isValid: Bool { fieldErrors.isEmpty && generalErrors.isEmpty }

    static func == (lhs: AO3CollectionForm, rhs: AO3CollectionForm) -> Bool {
        lhs.actionURL == rhs.actionURL
            && lhs.httpMethodOverride == rhs.httpMethodOverride
            && lhs.csrfToken == rhs.csrfToken
            && lhs.isNew == rhs.isNew
            && lhs.collectionSlug == rhs.collectionSlug
            && lhs.name == rhs.name
            && lhs.title == rhs.title
            && lhs.parentName == rhs.parentName
            && lhs.email == rhs.email
            && lhs.headerImageURL == rhs.headerImageURL
            && lhs.headerImageAlt == rhs.headerImageAlt
            && lhs.iconURL == rhs.iconURL
            && lhs.iconAlt == rhs.iconAlt
            && lhs.iconComment == rhs.iconComment
            && lhs.deleteIcon == rhs.deleteIcon
            && lhs.description == rhs.description
            && lhs.tagString == rhs.tagString
            && lhs.isMultifandom == rhs.isMultifandom
            && lhs.ownerPseudIDs == rhs.ownerPseudIDs
            && lhs.isClosed == rhs.isClosed
            && lhs.isModerated == rhs.isModerated
            && lhs.isUnrevealed == rhs.isUnrevealed
            && lhs.isAnonymous == rhs.isAnonymous
            && lhs.showRandom == rhs.showRandom
            && lhs.emailNotify == rhs.emailNotify
            && lhs.challengeType == rhs.challengeType
            && lhs.preferenceID == rhs.preferenceID
            && lhs.introduction == rhs.introduction
            && lhs.faq == rhs.faq
            && lhs.rules == rhs.rules
            && lhs.giftNotification == rhs.giftNotification
            && lhs.assignmentNotification == rhs.assignmentNotification
            && lhs.profileID == rhs.profileID
            && lhs.maintainers == rhs.maintainers
            && lhs.invitationField == rhs.invitationField
            && lhs.revealScheduleText == rhs.revealScheduleText
            && lhs.fieldErrors == rhs.fieldErrors
            && lhs.generalErrors == rhs.generalErrors
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(actionURL)
        hasher.combine(csrfToken)
        hasher.combine(collectionSlug)
        hasher.combine(name)
        hasher.combine(title)
        hasher.combine(isClosed)
        hasher.combine(isModerated)
        hasher.combine(isUnrevealed)
        hasher.combine(isAnonymous)
    }
}

nonisolated enum AO3CollectionSaveOutcome: Sendable {
    case saved(message: String, form: AO3CollectionForm)
    case invalid(AO3CollectionForm)
}

nonisolated struct AO3CollectionModeration: Hashable, Sendable {
    var slug: String
    var awaitingReview: [AO3CollectionItem]
    var membershipRequests: [AO3CollectionParticipant]
    var maintainers: [AO3CollectionParticipant]
    var invitations: [AO3CollectionParticipant]
    var revealScheduleText: String
    var itemsForm: AO3CollectionItemsPage?
}

nonisolated enum AO3CollectionParam {
    static let name = "collection[name]"
    static let title = "collection[title]"
    static let email = "collection[email]"
    static let headerImageURL = "collection[header_image_url]"
    static let description = "collection[description]"
    static let parentName = "collection[parent_name]"
    static let iconAlt = "collection[icon_alt_text]"
    static let iconComment = "collection[icon_comment_text]"
    static let tagString = "collection[tag_string]"
    static let multifandom = "collection[multifandom]"
    static let deleteIcon = "collection[delete_icon]"
    static let ownerPseuds = "owner_pseuds[]"
    static let challengeType = "challenge_type"
    static let preferenceID = "collection[collection_preference_attributes][id]"
    static let moderated = "collection[collection_preference_attributes][moderated]"
    static let closed = "collection[collection_preference_attributes][closed]"
    static let unrevealed = "collection[collection_preference_attributes][unrevealed]"
    static let anonymous = "collection[collection_preference_attributes][anonymous]"
    static let showRandom = "collection[collection_preference_attributes][show_random]"
    static let emailNotify = "collection[collection_preference_attributes][email_notify]"
    static let profileID = "collection[collection_profile_attributes][id]"
    static let intro = "collection[collection_profile_attributes][intro]"
    static let faq = "collection[collection_profile_attributes][faq]"
    static let rules = "collection[collection_profile_attributes][rules]"
    static let giftNotification = "collection[collection_profile_attributes][gift_notification]"
    static let assignmentNotification = "collection[collection_profile_attributes][assignment_notification]"
    static let participantsToInvite = "participants_to_invite"
    static let participantRole = "collection_participant[participant_role]"
    static let collectionNames = "collection_names"

    static func itemUserApproval(_ id: Int) -> String {
        "collection_items[\(id)][user_approval_status]"
    }
    static func itemCollectionApproval(_ id: Int) -> String {
        "collection_items[\(id)][collection_approval_status]"
    }
    static func itemUnrevealed(_ id: Int) -> String {
        "collection_items[\(id)][unrevealed]"
    }
    static func itemAnonymous(_ id: Int) -> String {
        "collection_items[\(id)][anonymous]"
    }
    static func itemRemove(_ id: Int) -> String {
        "collection_items[\(id)][remove]"
    }
}

nonisolated enum AO3CollectionURL {
    static let host = "https://archiveofourown.org"

    static func show(slug: String) -> URL? {
        let slug = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty else { return nil }
        return URL(string: "\(host)/collections/\(slug)")
    }

    static func edit(slug: String) -> URL {
        URL(string: "\(host)/collections/\(slug)/edit")!
    }

    static func `new`() -> URL {
        URL(string: "\(host)/collections/new")!
    }

    static func create() -> URL {
        URL(string: "\(host)/collections")!
    }

    static func confirmDelete(slug: String) -> URL {
        URL(string: "\(host)/collections/\(slug)/confirm_delete")!
    }

    static func profile(slug: String) -> URL {
        URL(string: "\(host)/collections/\(slug)/profile")!
    }

    static func bookmarks(slug: String, page: Int = 1) -> URL? {
        paged("/collections/\(slug)/bookmarks", page: page)
    }

    static func people(slug: String, page: Int = 1) -> URL? {
        paged("/collections/\(slug)/people", page: page)
    }

    static func items(slug: String, tab: AO3CollectionItemTab, page: Int = 1) -> URL {
        var components = URLComponents(string: "\(host)/collections/\(slug)/items")!
        var items: [URLQueryItem] = []
        if let status = tab.queryValue {
            items.append(URLQueryItem(name: "status", value: status))
        }
        if page > 1 { items.append(URLQueryItem(name: "page", value: String(page))) }
        if !items.isEmpty { components.queryItems = items }
        return components.url!
    }

    static func itemsUpdateMultiple(slug: String) -> URL {
        URL(string: "\(host)/collections/\(slug)/items/update_multiple")!
    }

    static func participants(slug: String) -> URL {
        URL(string: "\(host)/collections/\(slug)/participants")!
    }

    static func participantsJoin(slug: String) -> URL {
        URL(string: "\(host)/collections/\(slug)/participants/join")!
    }

    static func participantsAdd(slug: String) -> URL {
        URL(string: "\(host)/collections/\(slug)/participants/add")!
    }

    static func participant(slug: String, id: Int) -> URL {
        URL(string: "\(host)/collections/\(slug)/participants/\(id)")!
    }

    static func workCollectionItems(workID: Int) -> URL {
        URL(string: "\(host)/works/\(workID)/collection_items")!
    }

    static func paged(_ path: String, page: Int) -> URL? {
        var components = URLComponents(string: "\(host)\(path)")
        if page > 1 {
            components?.queryItems = [URLQueryItem(name: "page", value: String(page))]
        }
        return components?.url
    }

    static let reservedSlugs: Set<String> = [
        "new", "edit", "list_challenges", "list_ge_challenges", "list_pm_challenges"
    ]
}
