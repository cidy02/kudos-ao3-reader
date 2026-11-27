import Foundation
import SwiftUI

/// New Idea (`Phone-Capture.dc.html`): a text field with focus at once, and where it goes. Skips the
/// design's Dictate button (dictation is another lane) and its lock-screen framing.
struct NewIdeaSheet: View {
    let store: WritingDocumentStore
    let inbox: IdeaInbox
    let onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @AppStorage(NewIdeaDestination.lastChosenKey) private var lastChosen = ""
    @State private var text = ""
    @State private var works: [WritingWork] = []
    @State private var destination: NewIdeaDestination = .inbox
    @State private var isSaving = false
    @State private var saveFailed = false
    @FocusState private var fieldFocused: Bool

    init(
        store: WritingDocumentStore = WritingDocumentStore(root: WritingDocumentStore.defaultRoot),
        inbox: IdeaInbox = .shared,
        onDismiss: (() -> Void)? = nil
    ) {
        self.store = store
        self.inbox = inbox
        self.onDismiss = onDismiss
    }

    private var canSave: Bool {
        !isSaving && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var destinationTitle: String {
        switch destination {
        case .inbox:
            return "Ideas inbox"
        case let .work(id):
            return works.first { $0.id == id }.map(Self.menuTitle(for:)) ?? "Ideas inbox"
        }
    }

    private static func menuTitle(for work: WritingWork) -> String {
        "\(work.title.isEmpty ? "Untitled" : work.title) · Story notes"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("What's the idea?", text: $text, axis: .vertical)
                        .font(.system(.body, design: .serif))
                        .lineLimit(3...12)
                        .focused($fieldFocused)
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel("Idea")

                    destinationMenu

                    if saveFailed {
                        Text("Couldn't save this idea. Try again.")
                            .font(.footnote)
                            .foregroundStyle(.secondaryInk)
                    }
                }
                .padding(16)
            }
            .navigationTitle("New Idea")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 260)
        #endif
        .task {
            fieldFocused = true
            works = (try? await store.listWorks()) ?? []
            destination = NewIdeaDestination.restore(lastChosen, among: works)
        }
        .onDisappear {
            onDismiss?()
        }
    }

    private var destinationMenu: some View {
        Menu {
            Picker("Add to", selection: $destination) {
                Text("Ideas inbox").tag(NewIdeaDestination.inbox)
                ForEach(works, id: \.id) { work in
                    Text(Self.menuTitle(for: work)).tag(NewIdeaDestination.work(work.id))
                }
            }
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    Text("Add to").foregroundStyle(.secondaryInk)
                    Text(destinationTitle).fontWeight(.semibold).lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondaryInk)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add to").foregroundStyle(.secondaryInk)
                    Text(destinationTitle).fontWeight(.semibold)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add to, \(destinationTitle)")
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        saveFailed = false
        let target = destination
        Task {
            do {
                try await NewIdeaSaver(store: store, inbox: inbox).save(text, to: target)
                lastChosen = target.storageValue
                dismiss()
            } catch {
                saveFailed = true
                isSaving = false
            }
        }
    }
}

extension View {
    /// Presents `NewIdeaSheet` whenever the "New Idea" App Intent asks, on top of whatever tab,
    /// sheet or full-screen cover is currently showing.
    func newIdeaSheetPresenter(request: NewIdeaRequest, theme: ThemeManager) -> some View {
        modifier(NewIdeaSheetPresenterModifier(request: request, theme: theme))
    }
}

private struct NewIdeaSheetPresenterModifier: ViewModifier {
    let request: NewIdeaRequest
    let theme: ThemeManager

    // shortcut: a plain root .sheet, so New Idea can't open while another sheet is already up (SwiftUI shows one at a
    // time); asking again after that sheet closes works (NewIdeaRequest.request). Presenting from the topmost UIKit
    // controller would lift the limit; revisit with the Lock Screen widget, which opens the app the same way.
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { request.isPresenting },
                set: { request.isPresenting = $0 }
            )) {
                NewIdeaSheet()
                    .environment(theme)
                    .accentTint(theme.effectiveTint, on: theme.appTheme)
                    .onAppear { request.isShowing = true }
                    .onDisappear { request.isShowing = false }
            }
    }
}
