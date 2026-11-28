import SwiftUI

/// About Kudos, presented from its Settings page.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var themeManager
    @State private var showingBugReport = false
    @State private var showingWhatsNew = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                identity
                whatsNewCard
                aboutLinks
                Text("Kudos is a fan-made, open-source app. It is not affiliated with the Organization "
                    + "for Transformative Works or Archive of Our Own.")
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            .padding(.horizontal, SubjectMetrics.gutter)
            .padding(.vertical, 8)
        }
        .appScreenSurface(.grouped)
        .navigationTitle("About")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { dismiss() } label: {
                    Image(systemName: "checkmark")
                }
                .sheetConfirmStyle()
                .accessibilityLabel("Done")
            }
        }
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingBugReport) {
            BugReportView()
                .environment(themeManager)
                .accentTint(themeManager.effectiveTint, on: themeManager.appTheme)
        }
        .sheet(isPresented: $showingWhatsNew) {
            WhatsNewView(entries: Changelog.entries) {
                Changelog.markSeen()
                showingWhatsNew = false
            }
            .environment(themeManager)
            .accentTint(themeManager.effectiveTint, on: themeManager.appTheme)
        }
    }

    private var identity: some View {
        VStack(spacing: 10) {
            Image("AppIconArt")
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .accessibilityHidden(true)
            VStack(spacing: 1) {
                Text("Kudos").font(.title.bold())
                Text("Version \(Self.versionString)")
                    .font(.subheadline)
                    .foregroundStyle(.secondaryInk)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private var whatsNewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                showingWhatsNew = true
            } label: {
                Text("What’s New")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)

            #if os(iOS)
            feature("Natural Read Aloud", symbol: "waveform",
                    detail: "Voices that run on your iPhone, and keep reading when you close the reader.")
            feature("Made for iPhone Duo", symbol: "book.pages")
            #endif
            feature("Queues remember your place", symbol: "list.bullet.rectangle",
                    detail: "Every work in a queue picks up where you left off.")
        }
        .padding(16)
        .background(themeManager.appTheme.cardSurface, in: cardShape)
    }

    private func feature(_ title: String, symbol: String, detail: String? = nil) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.accentInk)
                .frame(width: 32)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var aboutLinks: some View {
        VStack(spacing: 0) {
            Text("Help & Feedback")
                .foregroundStyle(.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .frame(minHeight: 46)
                .accessibilityAddTraits(.isHeader)
            rowSeparator
            Button {
                showingBugReport = true
            } label: {
                row("Report a Bug")
            }
            if let repo = URL(string: AppLinks.repository) {
                rowSeparator
                Link(destination: repo) {
                    row("Source on GitHub", icon: "arrow.up.right")
                }
            }
            rowSeparator
            NavigationLink {
                LegalNoticesView(document: .gpl)
            } label: {
                row("Licence", value: "AGPL-3.0")
            }
            rowSeparator
            NavigationLink {
                components
            } label: {
                row("Open-Source Components")
            }
            rowSeparator
            NavigationLink {
                SystemLegalNoticesOverview()
            } label: {
                row("Legal Notices")
            }
        }
        .buttonStyle(.plain)
        .background(themeManager.appTheme.cardSurface, in: cardShape)
    }

    private var components: some View {
        Form {
            Section {
                creditRow(
                    "Readium Swift Toolkit", license: "BSD-3-Clause",
                    detail: "Displays downloaded works in the reader on iPhone and iPad.",
                    url: "https://github.com/readium/swift-toolkit"
                )
                creditRow(
                    "SwiftSoup", license: "MIT",
                    detail: "Reads AO3 pages so Kudos can show works.",
                    url: "https://github.com/scinfu/SwiftSoup"
                )
                creditRow(
                    "ao3_api", license: "Reference",
                    detail: "Helped guide how Kudos reads AO3 pages.",
                    url: "https://github.com/ArmindoFlores/ao3_api"
                )
            }
            .appThemedRows()
        }
        .formStyle(.grouped)
        .appThemedScroll()
        .navigationTitle("Open-Source Components")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
    }

    private var rowSeparator: some View {
        SubjectRowSeparator(inset: 16)
    }

    private func row(_ title: String, value: String? = nil, icon: String = "chevron.right") -> some View {
        let valueLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(spacing: 8))
        return HStack(spacing: 8) {
            valueLayout {
                Text(title)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let value {
                    Text(value).foregroundStyle(.secondaryInk)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondaryInk)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 46)
        .contentShape(Rectangle())
    }

    private func creditRow(_ name: String, license: String, detail: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.body.weight(.medium))
            Text(license).font(.footnote).foregroundStyle(.secondaryInk)
            Text(detail).font(.footnote).foregroundStyle(.secondaryInk)
            if let link = URL(string: url) {
                Link(url.replacingOccurrences(of: "https://", with: ""), destination: link)
                    .font(.footnote)
            }
        }
        .padding(.vertical, 2)
    }

    /// Marketing version, build number, and — on a build made by
    /// `Scripts/build-unsigned-ipa.sh` — the commit and branch it came from.
    ///
    /// The commit matters for sideloaded builds specifically. The committed
    /// project pins `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, so every
    /// build called itself "1.0 (1)" and installing a newer IPA over an older
    /// one was indistinguishable from installing nothing — which is exactly the
    /// question someone testing a branch build needs answered. The build script
    /// writes `KudosBuildCommit` / `KudosBuildBranch` into the bundle; a build
    /// made any other way simply has neither, and this falls back to the pair
    /// it always showed.
    static var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        var described = "\(version) (\(build))"
        if let commit = Bundle.main.object(forInfoDictionaryKey: "KudosBuildCommit") as? String,
           !commit.isEmpty {
            described += " · \(commit)"
        }
        if let branch = Bundle.main.object(forInfoDictionaryKey: "KudosBuildBranch") as? String,
           !branch.isEmpty, branch != "main" {
            described += " · \(branch)"
        }
        return described
    }
}

private struct SystemLegalNoticesOverview: View {
    var body: some View {
        Form {
            Group {
                Section("Kudos") {
                    if let url = URL(string: AppLinks.repository) {
                        Link(destination: url) {
                            HStack {
                                noticeRow("Kudos", detail: "AGPL-3.0 · source on GitHub", symbol: "heart")
                                Spacer(minLength: 8)
                                Image(systemName: "arrow.up.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondaryInk)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }

                Section("Open-source parts") {
                    noticeRow("Readium Swift Toolkit", detail: "BSD-3-Clause")
                    noticeRow("SwiftSoup", detail: "MIT")
                    noticeRow("FluidAudio", detail: "Apache-2.0")
                    noticeRow("Kokoro TTS voices", detail: "Apache-2.0")
                    noticeRow("MuPDF", detail: "AGPL-3.0")
                    NavigationLink {
                        LegalNoticesView(document: .thirdParty)
                    } label: {
                        Text("Third-Party Notices")
                    }
                }

                Section("AO3") {
                    noticeRow("Not affiliated with the OTW",
                              detail: "Kudos is an independent reader for Archive of Our Own",
                              symbol: "info.circle")
                }
            }
            .appThemedRows()
        }
        .formStyle(.grouped)
        .appThemedScroll()
        .navigationTitle("Legal Notices")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func noticeRow(
        _ title: String, detail: String, symbol: String = "chevron.left.forwardslash.chevron.right"
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.accentInk)
                .frame(width: 24)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(detail).font(.footnote).foregroundStyle(.secondaryInk)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
