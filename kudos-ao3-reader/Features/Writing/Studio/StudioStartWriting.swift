import Foundation
import SwiftUI

/// Destination target pointing at a newly created or existing local manuscript chapter.
nonisolated struct StudioLocalDocumentTarget: Identifiable, Hashable, Sendable {
    let workID: UUID
    let chapterID: UUID
    let title: String

    var id: String { "\(workID.uuidString):\(chapterID.uuidString)" }
}

/// Start Writing action (`Studio-Start-Writing.dc.html`): creates a local manuscript and first
/// chapter in `WritingDocumentStore` and reveals the Writing tab immediately, signed in or not.
enum StudioStartWritingAction {
    /// One create per store root, so a double tap cannot write two first manuscripts.
    @MainActor
    private static var inFlight: [String: Task<StudioLocalDocumentTarget, Error>] = [:]

    @MainActor
    static func createFirstDocument(
        in store: WritingDocumentStore = WritingDocumentStore(root: WritingDocumentStore.defaultRoot),
        router: AppRouter?,
        title: String = ""
    ) async throws -> StudioLocalDocumentTarget {
        let key = store.root.standardizedFileURL.path
        if let existing = inFlight[key] {
            return try await existing.value
        }
        let task = Task { @MainActor in
            defer { inFlight[key] = nil }
            return try await makeFirstDocument(in: store, router: router, title: title)
        }
        inFlight[key] = task
        return try await task.value
    }

    @MainActor
    private static func makeFirstDocument(
        in store: WritingDocumentStore,
        router: AppRouter?,
        title: String
    ) async throws -> StudioLocalDocumentTarget {
        let work = try await store.createWork(title: title)
        let chapter = try await store.addChapter(workID: work.id, title: "")
        router?.noteLocalDocumentCreated()
        WritingTabEvents.notifyLocalDocumentsChanged(root: store.root)
        return StudioLocalDocumentTarget(
            workID: work.id,
            chapterID: chapter.id,
            title: work.title
        )
    }
}

/// The "Write without an account" card shown on the signed-out Account sheet when the
/// Writing tab is still hidden (`Studio-Start-Writing.dc.html`).
struct StudioSignedOutStartWritingCard: View {
    let isCreating: Bool
    let onStartWriting: () -> Void

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let cardShape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
        let buttonShape = SubjectMetrics.controlShape(dynamicTypeSize)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(StudioTonePalette.paperBackground(for: theme.appTheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(StudioTonePalette.paperBorder(for: theme.appTheme), lineWidth: 0.5)
                    )
                    .overlay {
                        Image(systemName: "pencil.line")
                            .font(.title2.weight(.medium))
                            .foregroundStyle(.accentInk)
                    }
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)

                Text("Write without an account")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 0)
            }

            Text(
                "Start a document and keep your drafts on this \(ThisDevice.name). "
                    + "The Writing tab appears with your first document; sign in whenever you want to post."
            )
            .font(.subheadline)
            .foregroundStyle(.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)

            Button(action: onStartWriting) {
                HStack(spacing: 7) {
                    if isCreating {
                        ProgressView()
                            .controlSize(.small)
                            .accentFill()
                    }
                    Text(isCreating ? "Starting…" : "Start Writing")
                }
                .font(.headline)
                .foregroundStyle(.accentInk)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(StudioTonePalette.softAccentFill(for: theme), in: buttonShape)
                .contentShape(buttonShape)
            }
            .buttonStyle(.plain)
            .disabled(isCreating)
            .opacity(isCreating ? 0.65 : 1)
            .accessibilityLabel("Start Writing")
            .accessibilityHint("Creates a local document on this \(ThisDevice.name) and opens the editor")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(cardShape.fill(theme.appTheme.cardSurface))
        .overlay(cardShape.strokeBorder(theme.accentInk, lineWidth: 2))
    }
}
