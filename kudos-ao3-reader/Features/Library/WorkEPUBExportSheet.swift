#if os(iOS)
import SwiftData
import SwiftUI
import UIKit

/// One sheet serves Work Detail and every selection-mode action bar.
struct WorkEPUBExportSheet: View {
    let works: [SavedWork]
    @Environment(\.dismiss) private var dismiss
    @Environment(PrivacyGate.self) private var gate
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("workExportIncludesCover") private var includeCover = true
    @State private var files: [URL] = []
    @State private var directory: URL?
    @State private var showingShare = false
    @State private var error: String?
    @State private var failures: [String] = []
    @State private var exportTotal = 0
    @State private var progress: Int?
    @State private var exportTask: Task<Void, Never>?

    private var eligibleWorks: [SavedWork] {
        Self.exportable(works, gate: gate, hideMature: hideMature)
    }

    static func exportable(_ works: [SavedWork], gate: PrivacyGate,
                           hideMature: Bool) -> [SavedWork] {
        works.filter { $0.hasEPUB && !gate.isConcealed($0, enabled: hideMature) }
    }

    var body: some View {
        NavigationStack {
            let exportCount = eligibleWorks.count
            Form {
                Section {
                    Toggle("Include Cover", isOn: $includeCover)
                        .disabled(progress != nil)
                } footer: {
                    Text("Existing EPUB covers are kept. A cover is added only to a copy for export.")
                }
                .appThemedRows()
                Section {
                    Text("Export \(exportCount) EPUB\(exportCount == 1 ? "" : "s") to Files or another app.")
                    let omitted = works.count - eligibleWorks.count
                    if omitted > 0 {
                        Text("\(omitted) unavailable or hidden work\(omitted == 1 ? "" : "s") will be skipped.")
                    }
                    if let progress {
                        ProgressView(value: Double(progress), total: Double(max(exportTotal, 1))) {
                            Text("Preparing \(progress) of \(exportTotal)")
                        }
                    }
                    if !failures.isEmpty {
                        Text("\(failures.count) work\(failures.count == 1 ? "" : "s") could not be exported:")
                        ForEach(failures, id: \.self) { failure in Text(failure) }
                    }
                }
                .appThemedRows()
            }
            .appThemedScroll()
            .navigationTitle("Export Works")
            .navigationBarTitleDisplayMode(.inline)
            .wrappingInlineTitle("Export Works", isActive: dynamicTypeSize.isAccessibilitySize)
            .modifier(ScopeSurfaceAccent())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(progress == nil ? "Cancel" : "Cancel Export") {
                        if progress == nil { dismiss() } else { exportTask?.cancel() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") { prepare() }
                        .disabled(eligibleWorks.isEmpty || progress != nil || showingShare)
                }
            }
            .alert("Export failed", isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } }
            )) { Button("OK") { error = nil } } message: { Text(error ?? "") }
            .sheet(isPresented: $showingShare, onDismiss: cleanUp) {
                WorkEPUBActivitySheet(files: files, onComplete: cleanUp)
            }
            .onDisappear {
                exportTask?.cancel()
                if progress == nil && !showingShare { cleanUp() }
            }
        }
    }

    static func safeFilename(title: String, id: UUID) -> String {
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))
        let clean = title.unicodeScalars.map { forbidden.contains($0) ? "-" : String($0) }.joined()
        return String(clean.prefix(70)) + "-" + id.uuidString + ".epub"
    }

    static func removeStaleExports(in temp: URL, olderThan cutoff: Date) {
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: temp, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey]
        ) else { return }
        for folder in folders where folder.lastPathComponent.hasPrefix("KudosWorkExport-") {
            guard let values = try? folder.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey]),
                  values.isDirectory == true, let modified = values.contentModificationDate,
                  modified < cutoff else { continue }
            try? FileManager.default.removeItem(at: folder)
        }
    }

    struct ExportOutcome {
        let files: [URL]
        let failures: [String]
    }

    static func prepareFiles(
        for selected: [SavedWork],
        in folder: URL,
        wantsCover: Bool,
        gate: PrivacyGate,
        hideMature: @MainActor () -> Bool,
        onProgress: @MainActor (Int) -> Void = { _ in }
    ) async -> ExportOutcome {
        var created: [(SavedWork, URL)] = []
        var failures: [String] = []
        for (index, work) in selected.enumerated() {
            if Task.isCancelled { break }
            // Check at the boundary, even if selection or privacy changed after the sheet opened.
            guard work.modelContext != nil,
                  !gate.isConcealed(work, enabled: hideMature()) else {
                onProgress(index + 1)
                continue
            }
            let target = folder.appendingPathComponent(Self.safeFilename(title: work.title, id: work.id))
            do {
                let source = work.fileURL
                let recipe = wantsCover ? work.generatedCoverRecipe : nil
                guard FileManager.default.fileExists(atPath: source.path) else {
                    throw EPUBError.unreadableFile
                }
                var cover: Data?
                if wantsCover {
                    // The work's own art only when its resolved Cover choice wants it (T-573).
                    let wantsArt = CoverArtPreference.wantsEmbeddedArt(for: work)
                    let embedded = Task.detached { wantsArt ? EPUBCoverExport.embeddedJPEG(at: source) : nil }
                    cover = await withTaskCancellationHandler {
                        await embedded.value
                    } onCancel: { embedded.cancel() }
                    try Task.checkCancellation()
                    guard work.modelContext != nil,
                          !gate.isConcealed(work, enabled: hideMature()) else {
                        onProgress(index + 1)
                        continue
                    }
                    if cover == nil, let recipe { cover = EPUBCoverExport.generatedJPEG(recipe: recipe) }
                }
                let coverJPEG = cover
                let worker = Task.detached {
                    try EPUBCoverExport.copy(from: source, to: target,
                                             includeCover: wantsCover, coverJPEG: coverJPEG)
                }
                try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
                created.append((work, target))
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: target)
                break
            } catch {
                try? FileManager.default.removeItem(at: target)
                let detail = error is EPUBError || error is MiniZipError
                    || error is EPUBCoverExport.ExportError
                    ? error.localizedDescription : "Could not read or write its EPUB."
                failures.append("Work \(index + 1): \(detail)")
            }
            onProgress(index + 1)
            await Task.yield()
        }
        guard !Task.isCancelled else {
            return ExportOutcome(files: [], failures: failures)
        }
        for (work, url) in created where work.modelContext == nil
            || gate.isConcealed(work, enabled: hideMature()) {
            try? FileManager.default.removeItem(at: url)
        }
        let files = created.filter {
            $0.0.modelContext != nil && !gate.isConcealed($0.0, enabled: hideMature())
        }.map(\.1)
        return ExportOutcome(files: files, failures: failures)
    }

    private func prepare() {
        Self.removeStaleExports(in: FileManager.default.temporaryDirectory,
                                olderThan: Date().addingTimeInterval(-24 * 60 * 60))
        let selected = eligibleWorks
        let wantsCover = includeCover
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "KudosWorkExport-\(UUID().uuidString)", isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            self.error = "The export folder could not be created."
            return
        }
        directory = folder
        failures = []
        exportTotal = selected.count
        progress = 0
        exportTask = Task {
            let outcome = await Self.prepareFiles(
                for: selected,
                in: folder,
                wantsCover: wantsCover,
                gate: gate,
                hideMature: { hideMature },
                onProgress: { progress = $0 }
            )
            if Task.isCancelled {
                cleanUp()
            } else {
                failures = outcome.failures
                files = outcome.files
                if files.isEmpty {
                    error = failures.isEmpty ? "No works were available to export."
                        : "No EPUBs could be exported. See the per-work failures below."
                    cleanUp()
                } else {
                    showingShare = true
                }
            }
            progress = nil
            exportTask = nil
        }
    }

    private func cleanUp() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        files = []
    }
}

private struct WorkEPUBActivitySheet: UIViewControllerRepresentable {
    let files: [URL]
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
        let controller = UIActivityViewController(activityItems: files, applicationActivities: nil)
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
#endif
