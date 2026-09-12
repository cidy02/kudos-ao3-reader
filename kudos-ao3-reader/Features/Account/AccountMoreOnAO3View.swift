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
        theme.appTheme.subjectPalette(hue: theme.scopeHue)
    }

    private var header: some View {
        SubjectHeaderBlock(
            kicker: "AO3 Account",
            title: "More on AO3",
            subtitle: "Opens ao3.org in your browser",
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
                SectionRuleHeader(title: "Creator tools")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                creatorToolsPanel.pageBodyRow(top: 8, gutter: gutter)
                creatorToolsFootnote.pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Challenges & gifts")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                challengesPanel.pageBodyRow(top: 8, gutter: gutter)
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

    private var creatorToolsPanel: some View {
        VStack(spacing: 0) {
            AccountExternalNavCard(
                title: "Drafts",
                systemImage: "doc.badge.clock",
                pathSuffix: "works/drafts",
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
                title: "Skins",
                systemImage: "paintpalette",
                pathSuffix: "skins",
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
            Group {
                AccountExternalNavCard(
                    title: "Co-Creator Requests",
                    systemImage: "person.badge.plus",
                    pathSuffix: "creatorships",
                    isFormRow: true
                )
                SubjectRowSeparator()
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
            }
            SubjectRowSeparator()
            Group {
                AccountExternalNavCard(
                    title: "Claims",
                    systemImage: "flag",
                    pathSuffix: "claims",
                    isFormRow: true
                )
                SubjectRowSeparator()
                AccountExternalNavCard(
                    title: "Related Works",
                    systemImage: "arrow.triangle.branch",
                    pathSuffix: "related_works",
                    isFormRow: true
                )
                SubjectRowSeparator()
                AccountExternalNavCard(
                    title: "Gifts",
                    systemImage: "gift",
                    pathSuffix: "gifts",
                    isFormRow: true
                )
            }
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
