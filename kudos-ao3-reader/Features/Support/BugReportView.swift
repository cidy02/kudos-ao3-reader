import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A lightweight, privacy-respecting bug reporter. Reached by shaking the device
/// (iOS) or from Settings → About. Nothing is sent automatically: the user writes
/// the report, sees exactly which app/system details are attached, and submits it
/// as a prefilled GitHub issue they can review and edit first. When opened by a
/// shake, a screenshot of the moment is offered to attach.
struct BugReportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var summary = ""

    #if os(iOS)
    /// The screen snapshot captured at shake time (nil when opened from Settings).
    var screenshot: UIImage?
    @State private var includeScreenshot = true
    #endif

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
                    .lineLimit(4 ... 10)
                }

                screenshotSection

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
        .presentationDragIndicator(.visible)
    }

    /// The screenshot attach UI (shake path, iOS). Because a prefilled GitHub issue
    /// URL can't carry an image, the user saves/shares the screenshot and adds it to
    /// the issue — honest, no faked attachment.
    @ViewBuilder
    private var screenshotSection: some View {
        #if os(iOS)
        if let screenshot {
            Section {
                Toggle("Include a screenshot", isOn: $includeScreenshot)
                if includeScreenshot {
                    Image(uiImage: screenshot)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(.quaternary)
                        )
                        .padding(.vertical, 2)
                    ShareLink(
                        item: Image(uiImage: screenshot),
                        preview: SharePreview("Kudos screenshot", image: Image(uiImage: screenshot))
                    ) {
                        Label("Save or Share Screenshot", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text("Screenshot")
            } footer: {
                Text("GitHub can't attach images automatically — save the screenshot, "
                    + "then drag or paste it into the issue.")
            }
        }
        #endif
    }

    private var trimmedSummary: String {
        summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether a screenshot will accompany the report (drives the issue-body note).
    private var attachingScreenshot: Bool {
        #if os(iOS)
        return screenshot != nil && includeScreenshot
        #else
        return false
        #endif
    }

    /// A prefilled new-issue URL. The body includes the user's description plus the
    /// app/system details shown above — nothing more.
    private var issueURL: URL? {
        var body = """
        **What happened?**

        \(trimmedSummary)

        ---
        - App: \(AboutView.versionString)
        - System: \(Self.systemInfo)
        """
        if attachingScreenshot {
            body += "\n- Screenshot: attached below (added separately)"
        }
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
