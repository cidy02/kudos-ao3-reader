import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

// MARK: - Platform share / file export helpers for beta reading

nonisolated enum BetaDOCXContentType {
    static let docx = UTType(filenameExtension: "docx") ?? .data
}

nonisolated struct BetaShareFileItem: Identifiable, Sendable {
    let id = UUID()
    let url: URL

    static func cleanUp(_ url: URL) {
        let parent = url.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: parent)
    }
}

#if os(iOS)
struct BetaShareActivitySheet: UIViewControllerRepresentable {
    let url: URL
    let onComplete: @MainActor @Sendable () -> Void

    final class Coordinator {
        var onComplete: (@MainActor @Sendable () -> Void)?

        init(onComplete: @escaping @MainActor @Sendable () -> Void) {
            self.onComplete = onComplete
        }

        func finish() {
            let action = onComplete
            onComplete = nil
            action?()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        let coordinator = context.coordinator
        controller.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in coordinator.finish() }
        }
        return controller
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}

    static func dismantleUIViewController(_: UIActivityViewController, coordinator: Coordinator) {
        coordinator.finish()
    }
}
#else
nonisolated struct BetaExportFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [BetaDOCXContentType.docx] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#endif
