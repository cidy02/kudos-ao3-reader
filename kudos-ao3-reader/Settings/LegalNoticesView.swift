import SwiftUI

/// Full offline legal text reachable from About: the bundled GPL-3.0 license
/// and the third-party notices for every pinned Swift package. Both source
/// files ship in the app bundle (`kudos-ao3-reader/Legal/`) so they read
/// without network access. Presented as a push destination from `AboutView`,
/// not a new Settings/Account surface.
struct LegalNoticesView: View {
    enum Document: String, CaseIterable, Identifiable {
        case gpl = "LICENSE"
        case thirdParty = "ThirdPartyNotices"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .gpl: return "GNU GPL v3.0"
            case .thirdParty: return "Third-Party Notices"
            }
        }
    }

    let document: Document

    var body: some View {
        ScrollView {
            Text(Self.load(document))
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .appThemedScroll()
        .navigationTitle(document.title)
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// Reads the bundled notice file. A missing resource is a packaging bug
    /// (`Scripts/check-invariants.sh` catches it before this ever ships), so
    /// this surfaces the gap in-app rather than silently showing nothing.
    static func load(_ document: Document) -> String {
        guard let url = Bundle.main.url(forResource: document.rawValue, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "This notice file is missing from the app bundle. Please report this as a bug."
        }
        return text
    }
}
