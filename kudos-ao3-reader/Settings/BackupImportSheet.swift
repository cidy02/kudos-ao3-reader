import Foundation
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
    let archiveByteCount: Int?
    let localWorks: [SavedWork]
    /// Whether this library holds anything Replace would take away. Not the
    /// same as "has works": saved links, saved searches, collections and
    /// reading queues are all pruned by Replace and all outlive the last work,
    /// so a library emptied of works can still have plenty to remove — and
    /// offering only Merge there makes it impossible to remove.
    let hasReplaceableRecords: Bool
    let syncIsConnected: Bool
    let onMerge: () -> Void
    let onReplace: (Bool) -> Void
    let onCancel: () -> Void
    let makePreReplaceBackup: () -> Result<String, Error>

    @Environment(ThemeManager.self) private var themeManager

    private enum Step { case choose, replace }
    private enum RestoreChoice { case merge, replace }
    @State private var mode: RestoreChoice = .merge
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
            ScrollView {
                VStack(spacing: 14) {
                    contentsCard

                    VStack(spacing: 0) {
                        modeRow(.merge, title: "Merge with This Library",
                                detail: "Keeps existing works and adds missing items from the backup")
                        if hasReplaceableRecords {
                            SubjectRowSeparator(inset: 16)
                            modeRow(.replace, title: "Replace This Library",
                                    detail: "Changes data included in the backup to match it")
                        }
                    }
                    .background(themeManager.appTheme.cardSurface, in: cardShape)

                    Button {
                        if hasReplaceableRecords && mode == .replace {
                            step = .replace
                        } else {
                            onMerge()
                        }
                    } label: {
                        Text("Restore")
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.kudosPrimaryConfirm)

                    if hasReplaceableRecords {
                        Text("Works removed by Replace go to Recently Deleted. Review what will change "
                            + "before confirming.")
                            .font(.footnote)
                            .foregroundStyle(.secondaryInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.horizontal, SubjectMetrics.gutter)
                .padding(.vertical, 8)
            }
            .appScreenSurface(.grouped)
            .navigationTitle("Restore Backup")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
    }

    private var contentsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(SystemBackupBoardCopy.title(exportedAt: manifest.exportedAt))
                        .font(.headline)
                    Text(SystemBackupBoardCopy.summary(
                        works: manifest.works.count, queues: manifest.readingQueues.count,
                        collections: manifest.collections.count, byteCount: archiveByteCount
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                }
            } icon: {
                Image(systemName: "arrow.down.to.line")
                    .foregroundStyle(.accentInk)
                    .accessibilityHidden(true)
            }
            LabeledContent("Saved links", value: "\(manifest.bookmarks.count)")
                .font(.footnote)
            LabeledContent("Custom fonts", value: "\(manifest.fonts.count)")
                .font(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(themeManager.appTheme.cardSurface, in: cardShape)
    }

    private func modeRow(_ value: RestoreChoice, title: String, detail: String) -> some View {
        let selected = mode == value
        return Button {
            mode = value
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? AnyShapeStyle(.accentInk) : AnyShapeStyle(.secondaryInk))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.footnote).foregroundStyle(.secondaryInk)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

enum SystemBackupBoardCopy {
    static func title(exportedAt: Date) -> String {
        "Kudos backup, \(exportedAt.formatted(.dateTime.month(.abbreviated).day()))"
    }

    static func summary(works: Int, queues: Int, collections: Int, byteCount: Int?) -> String {
        var parts = [
            "\(works) work\(works == 1 ? "" : "s")",
            "\(queues) queue\(queues == 1 ? "" : "s")",
            "\(collections) collection\(collections == 1 ? "" : "s")"
        ]
        if let byteCount {
            parts.append(LocalStorageFootprint.formatted(bytes: Int64(byteCount)))
        }
        return parts.joined(separator: " · ")
    }
}
