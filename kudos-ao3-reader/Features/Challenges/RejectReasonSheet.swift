import SwiftUI

/// Artboard **1ce** — Reject with a reason.
///
/// AO3 emails the rejection reason to the creator; it cannot be edited afterwards,
/// and a failed reject must leave the submission in the queue rather than
/// optimistically removing it.
struct RejectReasonSheet: View {
    let collectionSlug: String
    let item: AO3CollectionItem
    let palette: SubjectPalette
    let onRejected: () -> Void

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var reason: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?

    private let maxReasonLength: Int = 1000

    private var trimmedReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedReason.isEmpty && trimmedReason.count <= maxReasonLength && !isSubmitting
    }

    private var creatorName: String {
        item.creatorByline.isEmpty ? "the creator" : item.creatorByline
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                grabberHandle

                Text("Reject this submission")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(.top, 4)

                Text("AO3 emails your reason to \(creatorName). It cannot be edited afterwards, "
                    + "and the work stays on AO3 either way — only its place in the collection changes.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                reasonPanel

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                actionButtons
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 26)
            .background(theme.appTheme.cardBackdrop)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var grabberHandle: some View {
        RoundedRectangle(cornerRadius: 99, style: .continuous)
            .fill(Color.secondary.opacity(0.24))
            .frame(width: 38, height: 4)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 6)
            .accessibilityHidden(true)
    }

    private var reasonPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            SubjectFieldLabel(text: "Reason", style: .formGroup)

            ZStack(alignment: .topLeading) {
                if reason.isEmpty {
                    Text("Explain why this work is being rejected from the collection…")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                }

                TextEditor(text: $reason)
                    .font(.system(size: 14))
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }

            HStack {
                Text("Required")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary.opacity(0.8))

                Spacer()

                Text("\(trimmedReason.count) / \(maxReasonLength)")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(trimmedReason.count > maxReasonLength ? Color.red : .secondary.opacity(0.8))
            }
        }
        .padding(14)
        .subjectPanel()
    }

    private var actionButtons: some View {
        HStack(spacing: 9) {
            Button("Cancel") {
                dismiss()
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.appTheme.glassFill(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(theme.appTheme.glassStroke(0.16), lineWidth: 0.5)
                    )
            )
            .buttonStyle(.plain)
            .disabled(isSubmitting)

            Button {
                Task { await performReject() }
            } label: {
                HStack(spacing: 6) {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(palette.accentOnFill)
                    }
                    Text("Reject and send")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.accentOnFill)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(canSubmit ? palette.accent : palette.accent.opacity(0.35))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
    }

    private func performReject() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            try await auth.rejectCollectionItem(slug: collectionSlug, itemID: item.id, reason: trimmedReason)
            onRejected()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSubmitting = false
        }
    }
}
