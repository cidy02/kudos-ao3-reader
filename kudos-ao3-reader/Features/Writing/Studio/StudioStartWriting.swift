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
    @MainActor
    static func createFirstDocument(
        in store: WritingDocumentStore = WritingDocumentStore(root: WritingDocumentStore.defaultRoot),
        router: AppRouter?,
        title: String = ""
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
    @ScaledMetric(relativeTo: .footnote) private var bodySize: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 13) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.appTheme.nestedCardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
                    )
                    .overlay {
                        Image(systemName: "pencil.line")
                            .font(.title3.weight(.semibold))
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
            .font(.system(size: bodySize))
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
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.kudosSecondaryConfirm)
            .disabled(isCreating)
            .accessibilityLabel("Start Writing")
            .accessibilityHint("Creates a local document on this \(ThisDevice.name) and opens the editor")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .subjectPanel()
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.effectiveTint, lineWidth: 1.5)
        )
    }
}
