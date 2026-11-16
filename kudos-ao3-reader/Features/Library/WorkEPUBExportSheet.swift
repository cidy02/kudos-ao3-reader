#if os(iOS)
import SwiftUI
import UIKit

/// One sheet serves Work Detail and every selection-mode action bar.
struct WorkEPUBExportSheet: View {
    let works: [SavedWork]
    @Environment(\.dismiss) private var dismiss
    @AppStorage("workExportIncludesCover") private var includeCover = true
    @State private var files: [URL] = []
    @State private var directory: URL?
    @State private var showingShare = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Include Cover", isOn: $includeCover)
                Text("Export \(works.count) EPUB\(works.count == 1 ? "" : "s") to Files or another app.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Export Works")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") { prepare() }
                        .disabled(works.isEmpty)
                }
            }
            .alert("Export failed", isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } }
            )) { Button("OK") { error = nil } } message: { Text(error ?? "") }
            .sheet(isPresented: $showingShare, onDismiss: cleanUp) {
                WorkEPUBActivitySheet(files: files)
            }
            .onDisappear { if !showingShare { cleanUp() } }
        }
    }

    private func prepare() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "KudosWorkExport-\(UUID().uuidString)", isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            directory = folder
            for work in works {
                guard work.hasEPUB, FileManager.default.fileExists(atPath: work.fileURL.path) else { continue }
                let safeTitle = work.title.replacingOccurrences(of: #"[/\\:]"#, with: "-", options: .regularExpression)
                let name = String(safeTitle.prefix(70)) + "-" + work.id.uuidString + ".epub"
                let target = folder.appendingPathComponent(name)
                let cover = includeCover ? EPUBCoverExport.jpeg(for: work) : nil
                try EPUBCoverExport.copy(from: work.fileURL, to: target,
                                         includeCover: includeCover, coverJPEG: cover)
                files.append(target)
            }
            guard !files.isEmpty else { throw EPUBError.unreadableFile }
            showingShare = true
        } catch {
            self.error = error.localizedDescription
            cleanUp()
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

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: files, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
#endif
