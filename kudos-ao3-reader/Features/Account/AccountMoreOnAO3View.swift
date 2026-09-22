import SwiftUI

/// Site-wide AO3 pages displayed in the "The archive" section of `AccountMoreOnAO3View` (artboard **1aa**).
/// These open archiveofourown.org in the app's Browse web view without requiring a user session.
enum AO3ArchivePage: String, CaseIterable, Identifiable, Sendable {
    case support = "/support"
    case reportAbuse = "/abuse_reports/new"
    case termsOfService = "/tos"
    case contentPolicy = "/content"
    case privacyPolicy = "/privacy"
    case faqs = "/faq"
    case donate = "/donate"

    var id: String { rawValue }
    var path: String { rawValue }

    var title: String {
        switch self {
        case .support: "Support and feedback"
        case .reportAbuse: "Report abuse"
        case .termsOfService: "Terms of Service"
        case .contentPolicy: "Content policy"
        case .privacyPolicy: "Privacy policy"
        case .faqs: "FAQs"
        case .donate: "Donate to the OTW"
        }
    }

    var systemImage: String {
        switch self {
        case .support: "questionmark.circle"
        case .reportAbuse: "exclamationmark.triangle"
        case .termsOfService: "doc.text"
        case .contentPolicy: "doc.plaintext"
        case .privacyPolicy: "hand.raised"
        case .faqs: "questionmark.bubble"
        case .donate: "heart"
        }
    }

    /// Non-optional because every `path` here is a literal verified against
    /// otwarchive's routes.rb; the builder only fails on a malformed string.
    var url: URL {
        guard let url = AccountExternalNavCard.siteWideURL(path: path) else {
            preconditionFailure("AO3ArchivePage.\(rawValue) is not a valid URL path")
        }
        return url
    }
}

/// Artboard 1aa routes that are easy to point at the wrong AO3 path.
///
/// Checked against otwarchive master on 2026-09-21 (`config/routes.rb`,
/// `features/support/paths.rb`, and the views those routes render). Import is
/// `GET /works/new?import=true`, not `/works/new/import`. Bulk edit is the GET
/// `show_multiple` page; `edit_multiple` is POST-only.
enum AO3MoreOnAO3Route {
    static let importWork = "/works/new?import=true"
    static let editWorksInBulk = "works/show_multiple"
    static let collectionItems = "collection_items"
    static let invitations = "invitations"
}

/// Long-tail AO3 destinations that open in Browse, artboard **1aa**.
///
/// Restyled onto the shared 1o account header (`SubjectHeaderBlock`) and the
/// form family (`PrivacyDataView.swift`), keeping all existing creator and challenge
/// destinations, and adding the site-wide "The archive" section for general AO3 pages.
struct AccountMoreOnAO3View: View {
    @Environment(ThemeManager.self) private var theme

    private var gutter: CGFloat { SubjectMetrics.accountGutter }
    private var selfGuttered: CGFloat { 0 }

    private var accountPalette: SubjectPalette {
        theme.scopePalette
    }

    private var header: some View {
        SubjectHeaderBlock(
            kicker: "AO3 Account",
            title: "More on AO3",
            subtitle: "Opens on AO3 in Browse",
            palette: accountPalette,
            gutter: SubjectMetrics.accountGutter
        )
    }

    var body: some View {
        List {
            Section {
                header.pageBodyRow(top: 20, gutter: selfGuttered)
            }

            Section {
                SectionRuleHeader(title: "Post and manage")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                postAndManagePanel.pageBodyRow(top: 8, gutter: gutter)
                creatorToolsFootnote.pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Challenges")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                challengesPanel.pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Your account")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                yourAccountPanel.pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "The archive")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                archivePanel.pageBodyRow(top: 8, gutter: gutter)
                archiveFootnote.pageBodyRow(top: 8, gutter: gutter)
            }
        }
        .cardList()
        #if os(macOS)
        .navigationTitle("More on AO3")
        #endif
        .subjectScreenWash(palette: accountPalette)
    }

    // MARK: - Panels

    /// 1aa's first group, in the drawn row order. Drafts is not on the artboard;
    /// it stays at the end because this screen already offered it.
    ///
    /// No count badges. The figures drawn beside bulk edit, collection items,
    /// and related works are not in `AO3AccountListCountsCache`, and this screen
    /// does not fetch AO3 to fill them.
    ///
    /// Paths checked against otwarchive master on 2026-09-21. Import is
    /// `GET /works/new?import=true` (`WorksController#new` renders the import
    /// form when `params[:import]` is set). `/works/new/import` is not a route,
    /// and `POST /works/import` only submits that form. Bulk edit is
    /// `GET /users/:id/works/show_multiple` ("Edit Multiple Works");
    /// `edit_multiple` is POST-only and is not a page you can open. Collection
    /// items is `GET /users/:id/collection_items`, the "Manage Collection Items"
    /// link on the user's own collections index.
    private var postAndManagePanel: some View {
        VStack(spacing: 0) {
            AccountExternalNavCard(
                title: "Post new work",
                systemImage: "square.and.pencil",
                sitePath: "/works/new",
                isFormRow: true
            )
            SubjectRowSeparator()
            AccountExternalNavCard(
                title: "Import work",
                systemImage: "square.and.arrow.down",
                sitePath: AO3MoreOnAO3Route.importWork,
                isFormRow: true
            )
            SubjectRowSeparator()
            AccountExternalNavCard(
                title: "Edit works in bulk",
                systemImage: "checklist",
                pathSuffix: AO3MoreOnAO3Route.editWorksInBulk,
                isFormRow: true
            )
            SubjectRowSeparator()
            AccountExternalNavCard(
                title: "Manage collection items",
                systemImage: "rectangle.stack",
                pathSuffix: AO3MoreOnAO3Route.collectionItems,
                isFormRow: true
            )
            SubjectRowSeparator()
            AccountExternalNavCard(
                title: "Related works",
                systemImage: "arrow.triangle.branch",
                pathSuffix: "related_works",
                isFormRow: true
            )
            SubjectRowSeparator()
            AccountExternalNavCard(
                title: "Drafts",
                systemImage: "doc.badge.clock",
                pathSuffix: "works/drafts",
                isFormRow: true
            )
        }
        .subjectPanel()
    }

    /// 1aa's third group, drawn order, then destinations this screen already had
    /// that the artboard does not name (Pseuds, Co-Creator Requests, Statistics).
    ///
    /// Invitations is `GET /users/:id/invitations` ("Invite a friend"). The
    /// "N left" figure on the artboard is that page's unsent-invite count, and
    /// nothing caches it. Fannish next of kin is absent on purpose: otwarchive
    /// has no user route for it (only an admin `update_next_of_kin`), profile
    /// edit does not carry the field, and AO3 tells people to contact Support,
    /// which is already the first row of The archive.
    private var yourAccountPanel: some View {
        VStack(spacing: 0) {
            AccountExternalNavCard(
                title: "Profile",
                systemImage: "person.text.rectangle",
                pathSuffix: "profile",
                isFormRow: true
            )
            SubjectRowSeparator()
            AccountExternalNavCard(
                title: "Invitations",
                systemImage: "envelope",
                pathSuffix: AO3MoreOnAO3Route.invitations,
                isFormRow: true
            )
            SubjectRowSeparator()
            AccountExternalNavCard(
                title: "Skins and site styles",
                systemImage: "paintpalette",
                pathSuffix: "skins",
                isFormRow: true
            )
            SubjectRowSeparator()
            AccountExternalNavCard(
                title: "Pseuds",
                systemImage: "person.2",
                pathSuffix: "pseuds",
                isFormRow: true
            )
            SubjectRowSeparator()
            AccountExternalNavCard(
                title: "Co-Creator Requests",
                systemImage: "person.badge.plus",
                pathSuffix: "creatorships",
                isFormRow: true
            )
            SubjectRowSeparator()
            AccountExternalNavCard(
                title: "Statistics",
                systemImage: "chart.bar",
                pathSuffix: "stats",
                isFormRow: true
            )
        }
        .subjectPanel()
    }

    private var creatorToolsFootnote: some View {
        footnote(
            "These open your AO3 pages in Browse. Native versions can land later. "
            + "Works, series, bookmarks, history, and inbox live under Account's "
            + "Reading, Writing, and Activity tabs."
        )
    }

    private var challengesPanel: some View {
        VStack(spacing: 0) {
            AccountExternalNavCard(
                title: "Sign-ups",
                systemImage: "pencil.and.list.clipboard",
                pathSuffix: "signups",
                isFormRow: true
            )
            SubjectRowSeparator()
            AccountExternalNavCard(
                title: "Assignments",
                systemImage: "list.clipboard",
                pathSuffix: "assignments",
                isFormRow: true
            )
            SubjectRowSeparator()
            AccountExternalNavCard(
                title: "Claims",
                systemImage: "flag",
                pathSuffix: "claims",
                isFormRow: true
            )
            SubjectRowSeparator()
            AccountExternalNavCard(
                title: "Gifts given and received",
                systemImage: "gift",
                pathSuffix: "gifts",
                isFormRow: true
            )
        }
        .subjectPanel()
    }

    private var archivePanel: some View {
        VStack(spacing: 0) {
            ForEach(Array(AO3ArchivePage.allCases.enumerated()), id: \.element.id) { index, page in
                if index > 0 {
                    SubjectRowSeparator()
                }
                AccountExternalNavCard(
                    title: page.title,
                    systemImage: page.systemImage,
                    sitePath: page.path,
                    isFormRow: true
                )
            }
        }
        .subjectPanel()
    }

    private var archiveFootnote: some View {
        footnote(
            "The archive's own pages, not your account's. These open in Browse and need no "
            + "sign-in — they are listed here so they are findable rather than missing."
        )
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
