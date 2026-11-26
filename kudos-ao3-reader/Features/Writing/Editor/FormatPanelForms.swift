import Foundation
import SwiftUI

/// Editable draft state for the native Link form opened from `FormatPanel`.
nonisolated struct FormatLinkDraft: Equatable, Sendable {
    var address: String
    var isInLink: Bool

    init(address: String = "", isInLink: Bool = false) {
        self.address = address
        self.isInLink = isInLink
    }

    var trimmedAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSubmit: Bool {
        FormatInputValidation.isValidLinkAddress(trimmedAddress)
    }

    var showsValidationHint: Bool {
        !trimmedAddress.isEmpty && !canSubmit
    }

    func submitCommand() -> FormatCommand? {
        guard canSubmit else { return nil }
        return .setLink(url: trimmedAddress)
    }

    func removeCommand() -> FormatCommand? {
        isInLink ? .unlink : nil
    }
}

/// Editable draft state for the native Image form opened from `FormatPanel`.
nonisolated struct FormatImageDraft: Equatable, Sendable {
    var address: String
    var description: String
    var widthText: String
    var heightText: String

    init(
        address: String = "",
        description: String = "",
        widthText: String = "",
        heightText: String = ""
    ) {
        self.address = address
        self.description = description
        self.widthText = widthText
        self.heightText = heightText
    }

    var trimmedAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isAddressValid: Bool {
        FormatInputValidation.isValidImageAddress(trimmedAddress)
    }

    var areDimensionsValid: Bool {
        FormatInputValidation.isValidOptionalDimension(widthText)
            && FormatInputValidation.isValidOptionalDimension(heightText)
    }

    var canSubmit: Bool {
        isAddressValid && areDimensionsValid
    }

    func submitCommand() -> FormatCommand? {
        guard canSubmit else { return nil }
        let spec = FormatImageSpec(
            address: trimmedAddress,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            width: FormatInputValidation.parsePositiveDimension(widthText),
            height: FormatInputValidation.parsePositiveDimension(heightText)
        )
        return .insertImage(spec)
    }
}

/// Native form for adding, editing, or removing a link (`FormatCommand.setLink` / `.unlink`).
struct FormatLinkFormSheet: View {
    @State private var draft: FormatLinkDraft
    let onCommand: (FormatCommand) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager: ThemeManager?

    private var appTheme: ReaderTheme { themeManager?.appTheme ?? .light }

    init(initialDraft: FormatLinkDraft, onCommand: @escaping (FormatCommand) -> Void) {
        _draft = State(initialValue: initialDraft)
        self.onCommand = onCommand
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "https://example.com",
                        text: $draft.address,
                        prompt: appTheme.sepiaPrompt("https://example.com")
                    )
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .accessibilityLabel("Web address")
                } header: {
                    Text("Address")
                } footer: {
                    if draft.showsValidationHint {
                        Text("Enter an http, https, or mailto address.")
                            .foregroundStyle(appTheme.errorColor)
                    } else {
                        Text("AO3 accepts http, https, and mailto links.")
                    }
                }
                .listRowBackground(appTheme.appElevatedBackground)

                if draft.isInLink {
                    Section {
                        Button(role: .destructive) {
                            if let command = draft.removeCommand() {
                                onCommand(command)
                                dismiss()
                            }
                        } label: {
                            Label("Remove Link", systemImage: "link.badge.minus")
                        }
                        .accessibilityLabel("Remove Link")
                    }
                    .listRowBackground(appTheme.appElevatedBackground)
                }
            }
            .scrollContentBackground(appTheme.appBaseBackground == nil ? .automatic : .hidden)
            .background((appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
            .navigationTitle(draft.isInLink ? "Edit Link" : "Add Link")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(draft.isInLink ? "Save" : "Insert") {
                        if let command = draft.submitCommand() {
                            onCommand(command)
                            dismiss()
                        }
                    }
                    .disabled(!draft.canSubmit)
                    .accessibilityLabel(draft.isInLink ? "Save link" : "Insert link")
                }
            }
        }
    }
}

/// Native form for inserting an external image (`FormatCommand.insertImage`).
struct FormatImageFormSheet: View {
    @State private var draft: FormatImageDraft
    let onCommand: (FormatCommand) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager: ThemeManager?

    private var appTheme: ReaderTheme { themeManager?.appTheme ?? .light }

    init(
        initialDraft: FormatImageDraft = FormatImageDraft(),
        onCommand: @escaping (FormatCommand) -> Void
    ) {
        _draft = State(initialValue: initialDraft)
        self.onCommand = onCommand
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "https://example.com/image.jpg",
                        text: $draft.address,
                        prompt: appTheme.sepiaPrompt("https://example.com/image.jpg")
                    )
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .accessibilityLabel("Image web address")

                    TextField(
                        "Description for readers",
                        text: $draft.description,
                        prompt: appTheme.sepiaPrompt("Description for readers"),
                        axis: .vertical
                    )
                    .lineLimit(1 ... 4)
                    .accessibilityLabel("Image description")
                } header: {
                    Text("Image")
                } footer: {
                    Text("AO3 doesn’t host images. Use a direct http or https web address.")
                }
                .listRowBackground(appTheme.appElevatedBackground)

                Section {
                    TextField(
                        "Width (pixels, optional)",
                        text: $draft.widthText,
                        prompt: appTheme.sepiaPrompt("Width (pixels, optional)")
                    )
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .accessibilityLabel("Width in pixels")

                    TextField(
                        "Height (pixels, optional)",
                        text: $draft.heightText,
                        prompt: appTheme.sepiaPrompt("Height (pixels, optional)")
                    )
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .accessibilityLabel("Height in pixels")
                } header: {
                    Text("Size (Optional)")
                } footer: {
                    if !draft.areDimensionsValid {
                        Text("Enter a whole number greater than zero, or leave blank.")
                            .foregroundStyle(appTheme.errorColor)
                    }
                }
                .listRowBackground(appTheme.appElevatedBackground)
            }
            .scrollContentBackground(appTheme.appBaseBackground == nil ? .automatic : .hidden)
            .background((appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
            .navigationTitle("Insert Image")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Insert") {
                        if let command = draft.submitCommand() {
                            onCommand(command)
                            dismiss()
                        }
                    }
                    .disabled(!draft.canSubmit)
                    .accessibilityLabel("Insert image")
                }
            }
        }
    }
}

#Preview("Link Form (In Link)") {
    FormatLinkFormSheet(
        initialDraft: FormatLinkDraft(address: "https://archiveofourown.org", isInLink: true),
        onCommand: { _ in }
    )
    .environment(ThemeManager())
}

#Preview("Image Form") {
    FormatImageFormSheet(onCommand: { _ in })
        .environment(ThemeManager())
}
