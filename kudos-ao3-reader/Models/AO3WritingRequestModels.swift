import Foundation

// MARK: - Co-creator invitations (otwarchive 452391b6 `creatorships/show`)

/// One pending co-creator invitation row from `GET /users/:login/creatorships`.
/// Ground truth: otwarchive master `452391b6` `app/views/creatorships/show.html.erb`
/// and `app/controllers/creatorships_controller.rb`.
nonisolated struct AO3CoCreatorRequest: Identifiable, Equatable, Hashable, Sendable {
    /// The `Creatorship` id posted as `selected[]=<id>`.
    var id: Int
    /// Link text (`title_for_creation`: title for a work/series, or
    /// `"Chapter N of <work title>"` for a chapter).
    var title: String
    var creationURL: URL?
    /// AO3's `creation_type` column (`"Work"`, `"Series"`, `"Chapter"`).
    var creationType: String
    var workID: Int?
    var seriesID: Int?
    var chapterID: Int?
    var invitedPseud: String
    var dateText: String
}

/// One paginated page of `GET /users/:login/creatorships`.
nonisolated struct AO3CoCreatorRequestsPage: Equatable, Sendable {
    var requests: [AO3CoCreatorRequest]
    var csrfToken: String
    var actionURL: URL?
    var currentPage: Int
    var totalPages: Int
}

// MARK: - Gifts to you (otwarchive 452391b6 `gifts/index`, `gifts/_gift_blurb`)

/// One gift row from `GET /users/:login/gifts` (accepted or `?refused=true`).
/// Reuses `AO3WorkSummary` from `AO3Client.parseBlurb` alongside the recipient's
/// `toggle_rejected` link state.
nonisolated struct AO3GiftRow: Identifiable, Equatable, Hashable, Sendable {
    var giftID: Int
    var workID: Int
    var title: String
    /// Creator names from the blurb; `["Anonymous"]` for anonymous gifts.
    var creators: [String]
    var isAnonymous: Bool
    /// True when the recipient action link reads `"Accept Gift"` (currently
    /// refused); false when it reads `"Refuse Gift"` (currently accepted).
    var isRefused: Bool
    /// Full blurb metadata parsed by `AO3Client.parseBlurb`.
    var work: AO3WorkSummary

    var id: Int { giftID }
}

/// One paginated page of the signed-in user's accepted or refused gifts.
nonisolated struct AO3GiftsPage: Equatable, Sendable {
    var gifts: [AO3GiftRow]
    var isRefusedList: Bool
    var csrfToken: String
    var currentPage: Int
    var totalPages: Int
}

// MARK: - Related works (otwarchive 452391b6 `related_works/index`, `show`)

/// Which mutation applies to a row on `GET /users/:login/related_works`.
nonisolated enum AO3RelatedWorkAction: Equatable, Hashable, Sendable {
    /// Owner of the parent work: open `/related_works/:id` and PATCH
    /// `reciprocal` to approve (`isApproved == false`) or remove
    /// (`isApproved == true`) the link shown on your work.
    case toggleReciprocal(isApproved: Bool)
    /// Owner of the child work: DELETE `/related_works/:id` to remove your
    /// work's link to the parent work.
    case removeLink
}

/// One side (parent or child) of a related-work link.
nonisolated struct AO3RelatedWorkRef: Equatable, Hashable, Sendable {
    var workID: Int?
    var title: String
    var url: URL?
    var creators: [String]
    var isUnrevealed: Bool = false
}

/// One entry in any of the four sections of `GET /users/:login/related_works`.
nonisolated struct AO3RelatedWorkRow: Identifiable, Equatable, Hashable, Sendable {
    var id: Int
    /// The original / parent work.
    var parentWork: AO3RelatedWorkRef
    /// The translation or inspired / remix work.
    var childWork: AO3RelatedWorkRef
    var fromLanguage: String?
    var toLanguage: String?
    /// True when AO3 shows `"Remove"` on a parent-owned link; false when AO3
    /// shows `"Approve"`; nil on child-owned links (index does not show
    /// reciprocal state).
    var isApproved: Bool?
    var action: AO3RelatedWorkAction
}

/// All four sections of `GET /users/:login/related_works`.
/// Ground truth: otwarchive master `452391b6` `app/views/related_works/index.html.erb`
/// renders `#translationsofme` and `#translationsbyme` as `<table>` elements, and
/// the two inspired/remix sections as `<dl class="inspired index group">` lists.
nonisolated struct AO3RelatedWorksPage: Equatable, Sendable {
    /// Other people's translations of your works (`table#translationsofme`).
    var translationsOfMe: [AO3RelatedWorkRow]
    /// Your translations of other people's works (`table#translationsbyme`).
    var translationsByMe: [AO3RelatedWorkRow]
    /// Other people's works inspired by yours (`dl.inspired` with `dt.child` / `dd.parent`).
    var inspiredByMe: [AO3RelatedWorkRow]
    /// Other people's works that inspired yours (`dl.inspired` with `dt.parent` / `dd.child`).
    var thatInspiredMe: [AO3RelatedWorkRow]
    var csrfToken: String?
}

/// Which partial `GET /related_works/:id` rendered (`_approve` vs `_remove`).
nonisolated enum AO3RelatedWorkShowMode: Equatable, Hashable, Sendable {
    /// Heading `"Approve Link"`; submitting approves the link on your work.
    case approve
    /// Heading `"Remove Link"`; submitting removes the link from your work.
    case remove
}

/// Parsed `GET /related_works/:id` toggle confirmation page.
nonisolated struct AO3RelatedWorkShow: Equatable, Sendable {
    var id: Int?
    var mode: AO3RelatedWorkShowMode
    var actionURL: URL
    var httpMethodOverride: String?
    var csrfToken: String
    var commitValue: String
}

// MARK: - Orphan (otwarchive 452391b6 `orphans_controller`, `orphans/new`)

/// What the user is asking AO3 to permanently orphan.
nonisolated enum AO3OrphanTarget: Equatable, Hashable, Sendable {
    case work(Int)
    case works([Int])
    case series(Int)
}

/// Parsed `GET /orphans/new?…` confirmation form.
nonisolated struct AO3OrphanForm: Equatable, Sendable {
    var target: AO3OrphanTarget
    var actionURL: URL
    var csrfToken: String
    /// Work titles listed in `dl.work.index`, or the series title from the
    /// caution notice on `_orphan_series`.
    var titles: [String]
    /// Paired `(workID, title)` entries scraped from `dl.work.index > dt > a`
    /// hrefs on `_orphan_work` forms so work IDs stay paired with their own
    /// titles regardless of AO3's DB order (`Work.where(id:)`).
    var workItems: [AO3OrphanCopyWork] = []
    /// `use_default` radio options (`"true"` = take pseud off, `"false"` = keep pseud copy).
    var pseudOptions: [AO3FormOption]
    var cautionTexts: [String]
    var submitLabel: String
}

/// One work resolved for Orphan's "Keep a copy" step before sending `POST /orphans`.
nonisolated struct AO3OrphanCopyWork: Equatable, Sendable {
    let workID: Int
    let title: String
}

/// Failures enumerating every work in a series before orphaning with "Keep a copy" on.
nonisolated enum AO3OrphanCopyError: LocalizedError, Equatable, Sendable {
    /// AO3's `DownloadsController#check_download_posted_status` refuses drafts
    /// (`otwarchive 452391b6`), so a series containing a draft cannot be copied as EPUBs.
    case draftWorkCannotBeDownloaded(title: String)
    /// `/series/:id/manage` listed a work whose downloadable work ID was absent from
    /// signed-in `/series/:id`, so we fail closed instead of silently skipping it.
    case unenumerableWork(title: String)

    var workTitle: String {
        switch self {
        case let .draftWorkCannotBeDownloaded(title), let .unenumerableWork(title):
            title
        }
    }

    var errorDescription: String? {
        switch self {
        case .draftWorkCannotBeDownloaded:
            "AO3 doesn't allow downloading EPUB copies of drafts. "
                + "Post it or save its text first, or turn off Keep a copy."
        case .unenumerableWork:
            "Couldn't find this work's download link on AO3. "
                + "Save a copy yourself first, or turn off Keep a copy."
        }
    }
}

/// Classifies whether an error thrown after a single-shot write POST was dispatched
/// means AO3 may still have processed the write (timeout, dropped connection,
/// gateway 5xx, unconfirmed 2xx/307/308) rather than definitely failing beforehand.
enum AO3WriteOutcomeClassifier {
    static func mayHaveGoneThrough(_ error: Error) -> Bool {
        switch error {
        case AO3WriteError.unconfirmed, AO3WorkWriteError.unconfirmed:
            return true
        case AO3Error.network, AO3Error.server:
            return true
        case let urlError as URLError:
            return isAmbiguousPostSendURLError(urlError.code)
        default:
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                return isAmbiguousPostSendURLError(URLError.Code(rawValue: nsError.code))
            }
            return false
        }
    }

    private static func isAmbiguousPostSendURLError(_ code: URLError.Code) -> Bool {
        // Failures that happen before HTTP bytes leave the device (offline, DNS,
        // refused TCP/TLS handshake, bad URL, or explicit cancel) did not reach AO3.
        switch code {
        case .badURL, .unsupportedURL,
             .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff,
             .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost,
             .secureConnectionFailed, .serverCertificateUntrusted,
             .serverCertificateHasBadDate, .serverCertificateNotYetValid,
             .serverCertificateHasUnknownRoot, .clientCertificateRejected,
             .clientCertificateRequired, .cancelled:
            return false
        default:
            return true
        }
    }
}

// MARK: - Import from URL (otwarchive 452391b6 `works/new_import`, `works#import`)

/// Whether multiple URLs import as separate works or chapters of one work.
nonisolated enum AO3ImportMode: String, Equatable, Hashable, Sendable {
    case works
    case chapters
}

/// Parsed `GET /works/new?import=true` form.
nonisolated struct AO3ImportForm: Equatable, Sendable {
    var actionURL: URL
    var csrfToken: String
    var languageOptions: [AO3FormOption]
    var selectedLanguageID: String
    var encodingOptions: [AO3FormOption]
    var ratingOptions: [AO3FormOption]
    var warningOptions: [AO3FormOption]
    var categoryOptions: [AO3FormOption]
    var commentPermissionOptions: [AO3FormOption]
    var defaultCommentPermissions: String
}

/// Input to `POST /works/import`. Never emits archivist-only parameters
/// (`importing_for_others`, `external_author_*`, `external_coauthor_*`) or
/// `pseuds_to_apply` (absent from `new_import.html.erb`, and `build_options`
/// looks pseud names up globally across all users).
nonisolated struct AO3ImportRequest: Equatable, Sendable {
    var urls: [String]
    var importMultiple: AO3ImportMode = .works
    var languageID: String
    var encoding: String = ""
    var postWithoutPreview: Bool = false
    var restricted: Bool = false
    var commentPermissions: String = "disable_anon"
    var moderatedCommenting: Bool = false
    var overrideTags: Bool = false
    var tags: AO3WorkTagSet = AO3WorkTagSet()
    var notes: String = ""

    /// Form body for `POST /works/import` matching `WorksController#build_options`
    /// (otwarchive master `452391b6` `app/controllers/works_controller.rb:881-909`),
    /// `app/views/works/new_import.html.erb:109` (`detect_tags` always `"true"`),
    /// and `app/views/works/_work_form_tags.html.erb:39,74`.
    /// Always sends the single-valued `work[…]` keys (blank when not overriding)
    /// so `params[:work]` exists, and omits `work[archive_warning_strings][]` and
    /// `work[category_strings][]` when unchecked (`include_hidden: !include_blank`
    /// with `include_blank: true` on `new_import`, so a browser sends neither key
    /// and `[""]` would survive `compact_blank!`).
    func parameters(csrfToken: String) -> [(String, String)] {
        let joinedURLs = urls
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        var pairs: [(String, String)] = [
            (AO3WorkFormField.authenticityToken, csrfToken),
            ("urls", joinedURLs),
            ("import_multiple", importMultiple.rawValue),
            ("language_id", languageID),
            ("encoding", encoding)
        ]
        // `works/new_import.html.erb` uses `check_box_tag` (no hidden "0"):
        // in Ruby `"0"` is truthy and passes `.compact_blank!`, so unchecked
        // boxes must be omitted rather than sent as `"0"`.
        if postWithoutPreview {
            pairs.append(("post_without_preview", "1"))
        }
        if restricted {
            pairs.append(("restricted", "1"))
        }
        if !commentPermissions.isEmpty {
            pairs.append(("comment_permissions", commentPermissions))
        }
        if moderatedCommenting {
            pairs.append(("moderated_commenting_enabled", "1"))
        }
        // AO3's form defaults `detect_tags` to true (`new_import.html.erb:109`,
        // `radio_button_tag "detect_tags", true, true`) in both modes so blank
        // override fields fall back to values extracted from the source pages.
        pairs.append(("detect_tags", "true"))
        if overrideTags {
            pairs.append(("override_tags", "1"))
        }

        // Single-value `work[…]` keys ensure `params[:work]` exists for
        // `WorksController#build_options` lines 894-900; checkbox array keys
        // (`warnings`, `categories`) are omitted when empty to match browsers.
        pairs.append((AO3WorkFormField.rating, overrideTags ? tags.rating : ""))
        if overrideTags, !tags.warnings.isEmpty {
            for warning in tags.warnings {
                pairs.append((AO3WorkFormField.warnings, warning))
            }
        }
        if overrideTags, !tags.categories.isEmpty {
            for category in tags.categories {
                pairs.append((AO3WorkFormField.categories, category))
            }
        }
        pairs.append((AO3WorkFormField.fandoms, overrideTags ? AO3TagListDiff.joined(tags.fandoms) : ""))
        pairs.append((
            AO3WorkFormField.relationships,
            overrideTags ? AO3TagListDiff.joined(tags.relationships) : ""
        ))
        pairs.append((AO3WorkFormField.characters, overrideTags ? AO3TagListDiff.joined(tags.characters) : ""))
        pairs.append((
            AO3WorkFormField.additionalTags,
            overrideTags ? AO3TagListDiff.joined(tags.additionalTags) : ""
        ))
        pairs.append(("notes", overrideTags ? notes : ""))
        pairs.append(("commit", "Import"))
        return pairs
    }
}

/// Outcome of `POST /works/import`.
nonisolated enum AO3ImportResult: Equatable, Sendable {
    /// Single work imported as a draft (`/works/:id/preview`).
    case draft(Int)
    /// Single work imported and posted (`/works/:id`).
    case posted(Int)
    /// Several works imported (`works/import` template listing their links),
    /// with any failed-URLs error flash AO3 returned alongside the successes.
    case several([Int], failures: String?)
    /// AO3 re-rendered the form with an error flash.
    case failed(String)
}
