import SwiftUI
import SwiftData

/// Native AO3 work page. Shows the work's metadata and lets the user download +
/// read it in the app, or open it on AO3 as a fallback.
struct AO3WorkDetailView: View {
    let work: AO3WorkSummary
    @Binding var path: NavigationPath

    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router

    @State private var downloading = false
    @State private var loadError: String?

    var body: some View {
        Form {
          // Group so .appThemedRows() reaches every section's rows (it doesn't
          // propagate from the Form container, only from a Group/Section/ForEach).
          Group {
            Section {
                Button(action: read) {
                    HStack {
                        Label(downloading ? "Downloading…" : "Read", systemImage: "book")
                        Spacer()
                        if downloading { ProgressView() }
                    }
                }
                .disabled(downloading)

                Button {
                    router.open(work.workURL)
                } label: {
                    Label("Open on AO3", systemImage: "safari")
                }
            } footer: {
                if let loadError {
                    Text(loadError).foregroundStyle(.red)
                }
            }

            Section("Details") {
                LabeledContent("Author", value: work.authorText)
                if !work.fandoms.isEmpty {
                    LabeledContent("Fandom", value: work.fandoms.joined(separator: ", "))
                }
                if !work.rating.isEmpty { LabeledContent("Rating", value: work.rating) }
                if !work.warnings.isEmpty {
                    LabeledContent("Warnings", value: work.warnings.joined(separator: ", "))
                }
                if !work.categories.isEmpty {
                    LabeledContent("Category", value: work.categories.joined(separator: ", "))
                }
                if let complete = work.isComplete {
                    LabeledContent("Status", value: complete ? "Complete" : "Work in Progress")
                }
                if !work.language.isEmpty { LabeledContent("Language", value: work.language) }
                if let words = work.words {
                    LabeledContent("Words", value: words.formatted())
                }
                if !work.chapters.isEmpty { LabeledContent("Chapters", value: work.chapters) }
                if !work.dateUpdated.isEmpty { LabeledContent("Updated", value: work.dateUpdated) }
            }

            Section("Stats") {
                if let kudos = work.kudos { LabeledContent("Kudos", value: kudos.formatted()) }
                if let comments = work.comments { LabeledContent("Comments", value: comments.formatted()) }
                if let hits = work.hits { LabeledContent("Hits", value: hits.formatted()) }
            }

            if !work.summary.isEmpty {
                Section("Summary") { Text(work.summary) }
            }

            if !work.tags.isEmpty {
                Section("Tags") {
                    Text(work.tags.joined(separator: " · "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
          }
          .appThemedRows()
        }
        .formStyle(.grouped)
        .appThemedScroll()
        .navigationTitle(work.title)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// Opens the work in the reader, downloading + importing it first if it isn't
    /// already in the library (so we never make a duplicate).
    private func read() {
        Task {
            // Already in the library: open it (re-downloading first if it's a freed
            // history entry) instead of making a duplicate.
            if let existing = existingWork(forSource: work.workURL, in: context) {
                if existing.hasEPUB {
                    path.append(existing)
                    return
                }
                await redownload(into: existing)
                return
            }
            downloading = true
            loadError = nil
            do {
                let temp = try await AO3Client.shared.downloadEPUB(workID: work.id)
                let saved = try await importEPUB(temp, source: work.workURL,
                                                 isComplete: work.isComplete ?? false,
                                                 seriesURL: work.seriesURL ?? "", into: context)
                path.append(saved)
            } catch let error as AO3Error {
                loadError = error.errorDescription
            } catch {
                loadError = "The download couldn't be saved."
            }
            downloading = false
        }
    }

    /// Re-downloads a freed history entry's EPUB into its existing record.
    private func redownload(into existing: SavedWork) async {
        downloading = true
        loadError = nil
        do {
            let temp = try await AO3Client.shared.downloadEPUB(workID: work.id)
            try? FileManager.default.removeItem(at: existing.fileURL)
            try FileManager.default.moveItem(at: temp, to: existing.fileURL)
            existing.hasEPUB = true
            existing.isFinished = false
            existing.lastSpineIndex = 0
            try? context.save()
            path.append(existing)
        } catch let error as AO3Error {
            loadError = error.errorDescription
        } catch {
            loadError = error.localizedDescription
        }
        downloading = false
    }
}
