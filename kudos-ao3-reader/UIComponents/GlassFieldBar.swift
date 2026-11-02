import SwiftUI

/// A plain text field with a leading icon and a trailing accessory, padded to sit
/// inside a toolbar's glass capsule (which supplies the background). Shared by the
/// Search field and the Browse address bar so both keep one consistent look —
/// same internal padding, frame, and cross-platform input behaviour.
struct GlassFieldBar<Leading: View, Trailing: View>: View {
    @Binding var text: String
    let placeholder: String
    var submitLabel: SubmitLabel = .search
    var onSubmit: () -> Void = {}
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack(spacing: 6) {
            leading()
            TextField(placeholder, text: $text, prompt: themeManager.appTheme.sepiaPrompt(placeholder))
                .textFieldStyle(.plain)
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
            #if !os(macOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            #endif
            trailing()
        }
        // Internal breathing room so the icons aren't flush with the toolbar's
        // glass pill edges (the toolbar provides the pill background itself).
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minWidth: 220, idealWidth: 480, maxWidth: 680)
    }
}

extension ReaderTheme {
    /// Sepia's system placeholder is tan on cream (about 2:1); this darkens it with the
    /// theme's own text colour. Other themes return nil and keep the system placeholder.
    func sepiaPrompt(_ text: String) -> Text? {
        self == .sepia ? Text(text).foregroundStyle(textColor.opacity(0.6)) : nil
    }
}
