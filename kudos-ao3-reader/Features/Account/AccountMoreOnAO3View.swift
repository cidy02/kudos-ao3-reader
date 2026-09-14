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

    /// 1aa's first group. It also draws Import work, Edit works in bulk and
    /// Manage collection items; those are not here because their AO3 paths could
    /// not be confirmed — GitHub was unreachable for otwarchive's routes and AO3
    /// answered those probes with Cloudflare 525s, which say nothing either way.
    /// A row that sends someone to a 404 in Browse is worse than a missing row.
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
                title: "Drafts",
                systemImage: "doc.badge.clock",
                pathSuffix: "works/drafts",
                isFormRow: true
            )
            SubjectRowSeparator()
            // 1aa files Related works under posting rather than challenges.
            AccountExternalNavCard(
                title: "Related works",
                systemImage: "arrow.triangle.branch",
                pathSuffix: "related_works",
                isFormRow: true
            )
        }
        .subjectPanel()
    }

    /// 1aa's third group. Its Invitations and Fannish next of kin rows are
    /// absent: the first could not be confirmed, and `fannish_next_of_kin` under
    /// a user path answered a definite 404, so whatever AO3 calls that page, it
    /// is not that.
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
                title: "Pseuds",
                systemImage: "person.2",
                pathSuffix: "pseuds",
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
