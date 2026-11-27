import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

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

    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    @State private var presenter = NewIdeaSheetPresenter()
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .onChange(of: request.isPresenting, initial: true) { _, isPresenting in
                presenter.sync(request: request, theme: theme, shouldPresent: isPresenting)
            }
            .onChange(of: request.requestID) { _, _ in
                if request.isPresenting {
                    presenter.sync(request: request, theme: theme, shouldPresent: true)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, request.isPresenting {
                    presenter.sync(request: request, theme: theme, shouldPresent: true)
                }
            }
            .onDisappear {
                presenter.cancelPending()
            }
        #else
        content
            .sheet(isPresented: Binding(
                get: { request.isPresenting },
                set: { request.isPresenting = $0 }
            )) {
                NewIdeaSheet()
                    .environment(theme)
                    .accentTint(theme.effectiveTint, on: theme.appTheme)
            }
        #endif
    }
}

#if os(iOS)
/// Presents `NewIdeaSheet` from the topmost UIKit view controller so a root `.sheet` on
/// `ContentView` isn't silently dropped (and wedged) when another sheet or cover is already up.
@MainActor
private final class NewIdeaSheetPresenter: NSObject, UIAdaptivePresentationControllerDelegate {
    private weak var presentedHost: UIViewController?
    private weak var activeRequest: NewIdeaRequest?
    private var retryTask: Task<Void, Never>?

    func sync(request: NewIdeaRequest, theme: ThemeManager, shouldPresent: Bool) {
        activeRequest = request
        if !shouldPresent {
            retryTask?.cancel()
            retryTask = nil
            if let host = presentedHost, host.presentingViewController != nil, !host.isBeingDismissed {
                host.dismiss(animated: true)
            }
            presentedHost = nil
            return
        }
        if let host = presentedHost, host.presentingViewController != nil, !host.isBeingDismissed {
            return
        }
        retryTask?.cancel()
        retryTask = Task { @MainActor [weak self, weak request, weak theme] in
            guard let self, let request, let theme else { return }
            await self.presentWhenReady(request: request, theme: theme)
        }
    }

    func cancelPending() {
        retryTask?.cancel()
        retryTask = nil
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        handleDismissed(presentationController.presentedViewController)
    }

    private func handleDismissed(_ controller: UIViewController) {
        guard presentedHost === controller else { return }
        presentedHost = nil
        activeRequest?.isPresenting = false
    }

    private func presentWhenReady(request: NewIdeaRequest, theme: ThemeManager) async {
        // Yield once so cold-launch covers register before we look for the topmost presenter, and
        // so synchronous test toggles clear before any UIKit presentation happens.
        await Task.yield()
        for _ in 0..<20 {
            guard !Task.isCancelled, request.isPresenting else { return }
            if let host = presentedHost, host.presentingViewController != nil, !host.isBeingDismissed {
                return
            }
            if let top = Self.topPresentableViewController(),
               presentSheet(on: top, request: request, theme: theme) {
                return
            }
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    private func presentSheet(
        on presenter: UIViewController,
        request: NewIdeaRequest,
        theme: ThemeManager
    ) -> Bool {
        let host = UIHostingController<AnyView>(rootView: AnyView(EmptyView()))
        let sheetView = NewIdeaSheet(onDismiss: { [weak self, weak host] in
            guard let self, let host else { return }
            self.handleDismissed(host)
        })
        .environment(theme)
        .accentTint(theme.effectiveTint, on: theme.appTheme)
        .preferredColorScheme(theme.appTheme.colorScheme)
        host.rootView = AnyView(sheetView)
        host.modalPresentationStyle = .pageSheet
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        host.presentationController?.delegate = self
        activeRequest = request
        presenter.present(host, animated: true)
        guard host.presentingViewController != nil else { return false }
        presentedHost = host
        return true
    }

    private static func topPresentableViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
        guard let scene = activeScene else { return nil }
        let window = scene.windows.first { $0.isKeyWindow && $0.rootViewController != nil }
            ?? scene.windows.first { $0.rootViewController != nil }
        guard var controller = window?.rootViewController,
              controller.viewIfLoaded?.window != nil else { return nil }
        while let presented = controller.presentedViewController {
            if presented.isBeingDismissed { return nil }
            controller = presented
        }
        if controller.isBeingPresented || controller.isBeingDismissed { return nil }
        return controller
    }
}
#endif
