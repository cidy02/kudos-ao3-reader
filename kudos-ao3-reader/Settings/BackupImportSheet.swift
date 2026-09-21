import SwiftUI

/// One sheet for importing a backup, in place of a chain of alerts.
///
/// Choosing a backup used to raise either a "Restore from Backup" alert (empty
/// library) or an "Import this backup?" confirmation dialog (non-empty), and
/// the Replace branch then opened a second sheet on top — with more
/// notification-style alerts afterwards for whatever the import had to say.
/// The owner's call: one sheet that presents the decision, and alerts kept for
/// destructive confirmation only.
///
/// So this is the whole decision in one place — what the file holds, what each
/// mode means, and what will not come back — and Replace's own gate is the
/// second step of the same sheet rather than a new one.
struct BackupImportSheet: View {
    let manifest: KudosBackupManifest
    let localWorks: [SavedWork]
    let syncIsConnected: Bool
    /// Imported originals on this device, which a backup does not carry.
    let preservedOriginalCount: Int
    let onMerge: () -> Void
    let onReplace: (Bool) -> Void
    let onCancel: () -> Void
    let makePreReplaceBackup: () -> Result<String, Error>

    private enum Step { case choose, replace }
    @State private var step: Step = .choose

    var body: some View {
        if step == .replace {
            ReplaceLibraryConfirmationView(
                manifest: manifest,
                localWorks: localWorks,
                syncIsConnected: syncIsConnected,
                onConfirm: onReplace,
                // Back to the choice, not out of the flow: the reader opened
                // Replace to read what it does, and changing their mind about
                // Replace is not changing their mind about importing.
                onCancel: { step = .choose },
                makePreReplaceBackup: makePreReplaceBackup
            )
        } else {
            chooseStep
        }
    }

    private var chooseStep: some View {
        NavigationStack {
            Form {
                contentsSection
                mergeSection
                if !localWorks.isEmpty { replaceSection }
                if preservedOriginalCount > 0 { originalsSection }
            }
            .appThemedRows()
            .appThemedScroll()
            .navigationTitle("Import Backup")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                }
        }
    }

    private var contentsSection: some View {
        Section("This backup") {
            LabeledContent("Library records", value: "\(manifest.works.count)")
            LabeledContent("Saved links", value: "\(manifest.bookmarks.count)")
            LabeledContent("Reading queues", value: "\(manifest.readingQueues.count)")
            LabeledContent("Collections", value: "\(manifest.collections.count)")
            LabeledContent("Custom fonts", value: "\(manifest.fonts.count)")
        }
    }

    private var mergeSection: some View {
        Section {
            Button("Merge", action: onMerge)
        } footer: {
            Text("Keeps everything already on this device and adds anything in "
                + "the backup you do not have. Nothing is removed.")
        }
    }

    /// Only offered when there is something to replace. On an empty library
    /// Replace and Merge do the same thing, and offering the destructive
    /// wording for it was never anything but a way to frighten someone.
    private var replaceSection: some View {
        Section {
            Button("Replace Library…", role: .destructive) { step = .replace }
        } footer: {
            Text("Makes this device match the backup exactly. Works, reading "
                + "positions, notes, collections and queues all become what the "
                + "backup says, and works it does not contain are removed. "
                + "You will be asked to confirm, and an undo copy is written first.")
        }
    }

    private var originalsSection: some View {
        Section {
            Text(originalsMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var originalsMessage: String {
        let noun = preservedOriginalCount == 1 ? "original file is" : "original files are"
        return "\(preservedOriginalCount.formatted()) imported \(noun) kept on this "
            + "device only. A backup carries converted EPUBs, not the documents they "
            + "were made from."
    }
}
