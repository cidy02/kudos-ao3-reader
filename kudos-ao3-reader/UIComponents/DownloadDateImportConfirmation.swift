import SwiftUI

struct PendingDocumentImport: Identifiable {
    let id = UUID()
    let url: URL
    let detection: DownloadDateDetection
}

struct SelectedDocumentImport {
    let url: URL
    let downloadedAt: Date
}

/// The one confirmation surface used by Settings imports and Open in Kudos.
struct DownloadDateImportConfirmation: View {
    private enum BatchChoice: String, CaseIterable, Identifiable {
        case detected
        case today

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    let imports: [PendingDocumentImport]
    let onImport: ([SelectedDocumentImport]) -> Void
    let onCancel: () -> Void

    @State private var dates: [UUID: Date]
    @State private var batchChoice: BatchChoice = .detected
    private let today: Date

    init(
        imports: [PendingDocumentImport],
        now: Date = Date(),
        onCancel: @escaping () -> Void = {},
        onImport: @escaping ([SelectedDocumentImport]) -> Void
    ) {
        self.imports = imports
        self.onImport = onImport
        self.onCancel = onCancel
        today = now
        _dates = State(initialValue: Dictionary(uniqueKeysWithValues: imports.map { ($0.id, $0.detection.date) }))
    }

    var body: some View {
        NavigationStack {
            Form {
                if imports.count > 1 {
                    Section {
                        Picker("Download date", selection: $batchChoice) {
                            Text("Use each file's download date").tag(BatchChoice.detected)
                            Text("Use today").tag(BatchChoice.today)
                        }
                        .pickerStyle(.inline)
                    }
                }

                Section(imports.count == 1 ? "Downloaded" : "Files") {
                    ForEach(imports) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            if imports.count > 1 {
                                Text(item.url.deletingPathExtension().lastPathComponent)
                                    .font(.body.weight(.medium))
                                    .lineLimit(1)
                            }
                            Text(Self.explanation(for: item.detection))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if imports.count == 1 {
                            DatePicker(
                                "Change date",
                                selection: Binding(
                                    get: { dates[item.id] ?? item.detection.date },
                                    set: { dates[item.id] = $0 }
                                ),
                                in: ...today,
                                displayedComponents: .date
                            )
                        }
                    }
                }
            }
            .navigationTitle(imports.count == 1 ? "Confirm Import" : "Confirm Imports")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        let selected = imports.map { item in
                            SelectedDocumentImport(
                                url: item.url,
                                downloadedAt: batchChoice == .today
                                    ? today
                                    : dates[item.id] ?? item.detection.date
                            )
                        }
                        dismiss()
                        onImport(selected)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    static func explanation(for detection: DownloadDateDetection) -> String {
        let date = detection.date.formatted(date: .abbreviated, time: .omitted)
        return switch detection.source {
        case .file: "Downloaded \(date) · from the file"
        case .ao3Generated: "AO3 generated this copy \(date)"
        case .importTime: "Couldn't tell. Using today"
        }
    }
}
