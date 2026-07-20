import SwiftUI

/// Settings → About: app identity, the GPL-3.0 license, open-source credits, and
/// the AO3/OTW disclaimer. Presented as a sheet from the Settings page.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingBugReport = false

    var body: some View {
        Form {
            Group {
                Section {
                    VStack(spacing: 6) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(.tint)
                        Text("Kudos").font(.title2.bold())
                        Text("Version \(Self.versionString)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("A native reader for Archive of Our Own.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                Section("License") {
                    Text("Kudos is free software, released under the "
                        + "**GNU General Public License v3.0**. You may use, study, "
                        + "share, and modify it under the terms of that license.")
                    NavigationLink("Read the Full License Text") {
                        LegalNoticesView(document: .gpl)
                    }
                }

                Section("Open-Source Components") {
                    creditRow(
                        "SwiftSoup", license: "MIT",
                        detail: "HTML parsing for AO3 scraping.",
                        url: "https://github.com/scinfu/SwiftSoup"
                    )
                    creditRow(
                        "Readium Swift Toolkit", license: "BSD-3-Clause",
                        detail: "The EPUB reading engine on the Readium reader build (iOS/iPadOS).",
                        url: "https://github.com/readium/swift-toolkit"
                    )
                    creditRow(
                        "CryptoSwift", license: "Zlib",
                        detail: "Cryptographic primitives used by the Readium toolkit.",
                        url: "https://github.com/krzyzanowskim/CryptoSwift"
                    )
                    creditRow(
                        "DifferenceKit", license: "Apache-2.0",
                        detail: "Diffing algorithms used by the Readium toolkit.",
                        url: "https://github.com/ra1028/DifferenceKit"
                    )
                    creditRow(
                        "Fuzi", license: "MIT",
                        detail: "XML/HTML parsing used by the Readium toolkit.",
                        url: "https://github.com/readium/Fuzi"
                    )
                    creditRow(
                        "GCDWebServer", license: "BSD-3-Clause",
                        detail: "Local HTTP server used by the Readium toolkit.",
                        url: "https://github.com/readium/GCDWebServer"
                    )
                    creditRow(
                        "SQLite.swift", license: "MIT",
                        detail: "SQLite access used by the Readium toolkit.",
                        url: "https://github.com/stephencelis/SQLite.swift"
                    )
                    creditRow(
                        "Zip", license: "MIT",
                        detail: "Archive extraction used by the legacy macOS reader.",
                        url: "https://github.com/marmelroy/Zip"
                    )
                    creditRow(
                        "ZIPFoundation", license: "MIT",
                        detail: "Archive extraction used by the Readium toolkit.",
                        url: "https://github.com/readium/ZIPFoundation"
                    )
                    creditRow(
                        "ao3_api", license: "Reference",
                        detail: "AO3 page selectors are ported from this project.",
                        url: "https://github.com/ArmindoFlores/ao3_api"
                    )
                    NavigationLink("Read Full Third-Party Notices") {
                        LegalNoticesView(document: .thirdParty)
                    }
                }

                Section("Help & Feedback") {
                    Button {
                        showingBugReport = true
                    } label: {
                        Label("Report a Bug", systemImage: "ladybug")
                    }
                    if let repo = URL(string: AppLinks.repository) {
                        Link(destination: repo) {
                            Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                    }
                }

                Section("Disclaimer") {
                    Text("Kudos is an unofficial, personal project. It is not "
                        + "affiliated with or endorsed by the Organization for "
                        + "Transformative Works or Archive of Our Own, and it reads "
                        + "AO3's public web pages — AO3 has no official API.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .appThemedRows()
        }
        .formStyle(.grouped)
        .appThemedScroll()
        .navigationTitle("About")
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .presentationDragIndicator(.visible)
            .sheet(isPresented: $showingBugReport) { BugReportView() }
    }

    private func creditRow(_ name: String, license: String, detail: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name).font(.body.weight(.medium))
                Spacer()
                Text(license).font(.caption).foregroundStyle(.secondary)
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
            if let link = URL(string: url) {
                Link(url.replacingOccurrences(of: "https://", with: ""), destination: link)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    static var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        // Stamped into the Info.plist by the "Inject Info.plist keys" build
        // phase; absent when the build didn't come from a git checkout.
        if let sha = Bundle.main.object(forInfoDictionaryKey: "GitCommitSHA") as? String, !sha.isEmpty {
            return "\(version) (\(build)) · \(sha)"
        }
        return "\(version) (\(build))"
    }
}
