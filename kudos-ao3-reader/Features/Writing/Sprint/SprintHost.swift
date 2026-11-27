import SwiftUI

/// Wires a `SprintController` into the editor screen in one modifier: word-count updates, the end
/// of the sprint (also after a trip to the background), the length picker and the Sprint Done sheet.
private struct SprintHost: ViewModifier {
    let controller: SprintController
    let words: Int
    let workID: UUID?
    let isClosing: Bool

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task { await controller.loadHistory() }
            .onChange(of: words) { _, new in controller.noteWords(new) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { controller.tick() }
            }
            .onChange(of: isClosing) { _, closing in
                if closing { controller.finish(showsResult: false) }
            }
            .onDisappear { controller.finish(showsResult: false) }
            .task(id: controller.active?.id) { await controller.runUntilEnd() }
            .confirmationDialog(
                "Start a Sprint",
                isPresented: Binding(
                    get: { controller.isChoosingDuration },
                    set: { controller.isChoosingDuration = $0 }
                ),
                titleVisibility: .visible
            ) {
                ForEach(SprintController.durations, id: \.self) { minutes in
                    Button(
                        minutes == SprintController.defaultMinutes
                            ? "\(minutes) minutes (default)" : "\(minutes) minutes"
                    ) {
                        controller.start(minutes: minutes, currentWords: words, workID: workID)
                    }
                }
            } message: {
                Text("Words you write from now on are counted. The timer keeps running if you leave the app.")
            }
            .sheet(item: Binding(
                get: { controller.result },
                set: { controller.result = $0 }
            )) { result in
                SprintDoneSheet(result: result) { minutes in
                    controller.start(minutes: minutes, currentWords: words, workID: workID)
                }
            }
    }
}

extension View {
    /// Adds writing sprints to an editor screen. `words` is the chapter's live word count.
    func sprintHost(
        _ controller: SprintController,
        words: Int,
        workID: UUID?,
        isClosing: Bool
    ) -> some View {
        modifier(SprintHost(controller: controller, words: words, workID: workID, isClosing: isClosing))
    }
}
