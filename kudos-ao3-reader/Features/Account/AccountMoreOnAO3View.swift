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
        case .contentPolicy: "Content Policy"
        case .privacyPolicy: "Privacy policy"
        case .faqs: "FAQ"
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
/// Restyled onto the form family (`PrivacyDataView.swift`), keeping all existing
/// creator and challenge destinations, and adding the site-wide "The archive"
/// section for general AO3 pages.
struct AccountMoreOnAO3View: View {
    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var theme
    @ScaledMetric(relativeTo: .footnote) private var footnoteSize: CGFloat = 12.5

    @State private var showingRequests = false
    @State private var showingImport = false
    @State private var importedDraftWorkID: Int?

    private var gutter: CGFloat { SubjectMetrics.accountGutter }
    private var selfGuttered: CGFloat { 0 }

    private var accountPalette: SubjectPalette {
        theme.scopePalette
    }

    var body: some View {
        List {
            Section {
                SectionRuleHeader(title: "Your account")
                    .pageBodyRow(top: 14, gutter: selfGuttered)
                yourAccountPanel.pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "AO3")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                archivePanel.pageBodyRow(top: 8, gutter: gutter)
                archiveFootnote.pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Post and Manage")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                postAndManagePanel.pageBodyRow(top: 8, gutter: gutter)
                creatorToolsFootnote.pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Challenges")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                challengesPanel.pageBodyRow(top: 8, gutter: gutter)
            }
        }
        .cardList()
        .subjectScreenWash(title: "Open AO3", palette: accountPalette)
        .navigationDestination(isPresented: $showingRequests) {
            WritingRequestsView()
        }
        .navigationDestination(item: $importedDraftWorkID) { workID in
            WritingWorkDestination(workID: workID)
        }
        .sheet(isPresented: $showingImport) {
            ImportWorkView(
                onOpenDraft: { workID in importedDraftWorkID = workID },
                onOpenWork: { workID in
                    router.openAO3Link(AO3Client.workURL(workID: workID))
                }
            )
        }
    }

    // MARK: - Panels

    /// Additional creator destinations already available from Account.
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
            nativeUserRow(
                title: "Related works",
                systemImage: "arrow.triangle.branch"
            ) {
                showingRequests = true
            }
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

    /// Existing account destinations, with the board’s rows first.
    private var yourAccountPanel: some View {
        VStack(spacing: 0) {
            AccountExternalNavCard(
                title: "Gifts",
                systemImage: "gift",
                pathSuffix: "gifts",
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
            nativeUserRow(
                title: "Co-creator requests",
                systemImage: "person.badge.plus"
            ) {
                showingRequests = true
            }
            SubjectRowSeparator()
            AccountExternalNavCard(
                title: "Invitations",
                systemImage: "envelope",
                pathSuffix: AO3MoreOnAO3Route.invitations,
                isFormRow: true
            )
            SubjectRowSeparator()
            nativeUserRow(
                title: "Import works",
                systemImage: "square.and.arrow.down"
            ) {
                showingImport = true
            }
            SubjectRowSeparator()
            AccountExternalNavCard(
                title: "Profile",
                systemImage: "person.text.rectangle",
                pathSuffix: "profile",
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
            "These open your AO3 pages in Browse. You can find works, series, bookmarks, "
            + "history and inbox in the Reading, Writing and Activity sections of Account."
        )
    }

    private var challengesPanel: some View {
        VStack(spacing: 0) {
            AccountExternalNavCard(
                title: "Sign-Ups",
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
        }
        .subjectPanel()
    }

    private var archivePanel: some View {
        let pages: [AO3ArchivePage] = [
            .faqs, .termsOfService, .contentPolicy, .donate, .support, .reportAbuse, .privacyPolicy
        ]
        return VStack(spacing: 0) {
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
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
        footnote("These open AO3 in the in-app browser.")
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: footnoteSize))
            .foregroundStyle(.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nativeUserRow(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        let isDisabled = !auth.isLoggedIn
        return Button(action: action) {
            AccountNavCardLabel(
                title: title,
                systemImage: systemImage,
                opensExternally: false
            )
            .padding(.horizontal, 14)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }
}
