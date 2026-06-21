import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A lightweight, privacy-respecting bug reporter. Reached by shaking the device
/// (iOS) or from Settings → About. Nothing is sent automatically: the user writes
/// the report, sees exactly which app/system details are attached, and submits it
/// as a prefilled GitHub issue they can review and edit first.
struct BugReportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var summary = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Found a bug? Describe what happened and Kudos will open a "
                         + "prefilled GitHub issue you can review and post. Nothing is "
                         + "sent automatically.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("What went wrong?") {
                    TextField(
                        "What happened, and what did you expect instead?",
                        text: $summary,
                        axis: .vertical
                    )
                    .lineLimit(4...10)
                }

                Section("Included with your report") {
                    LabeledContent("App version", value: AboutView.versionString)
                    LabeledContent("System", value: Self.systemInfo)
                    Text("Only these app and system details are attached — no personal "
                         + "data, and never your AO3 account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if let url = issueURL {
                        Link(destination: url) {
                            Label("Continue on GitHub", systemImage: "ladybug")
                        }
                        .disabled(trimmedSummary.isEmpty)
                    }
                    if let issues = URL(string: AppLinks.issues) {
                        Link(destination: issues) {
                            Label("Browse existing issues", systemImage: "list.bullet")
                        }
                        .font(.subheadline)
                    }
                } footer: {
                    Text("Please don't contact the AO3 team about Kudos — they can't "
                         + "provide support for this app.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Report a Bug")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var trimmedSummary: String {
        summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A prefilled new-issue URL. The body includes the user's description plus the
    /// app/system details shown above — nothing more.
    private var issueURL: URL? {
        let body = """
        **What happened?**

        \(trimmedSummary)

        ---
        - App: \(AboutView.versionString)
        - System: \(Self.systemInfo)
        """
        return AppLinks.newIssue(title: "Bug report", body: body)
    }

    static var systemInfo: String {
        #if os(iOS)
        return "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        #else
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #endif
    }
}
