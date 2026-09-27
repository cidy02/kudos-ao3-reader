import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// The reader's display options — theme, text size, layout, read-aloud and font —
/// in the reader's options sheet (iOS) and inspector (macOS).
///
/// Settings shows the same Reader, Listening and Font sections on its own pages
/// (`SettingsReaderPage`, `SettingsListeningPage`, `SettingsFontPage`) through the
/// shared views below, so the two always show the same controls and stay in sync
/// via `@AppStorage`. App-wide settings live on those pages, not here.
struct ReaderOptionsForm: View {
    /// Whether the two-page spread can take effect (the reader passes its window
    /// width).
    var twoPageAvailable: Bool = true

    @Environment(ThemeManager.self) private var themeManager
    @State private var isImportingFonts = false
    @State private var showCustomize = false

    private var readerThemeBinding: Binding<ReaderTheme> {
        Binding(get: { themeManager.readerTheme }, set: { themeManager.readerTheme = $0 })
    }

    var body: some View {
        Form {
            // Group so .appThemedRows() (a .listRowBackground) reaches every section's
            // rows — it does NOT propagate from the Form container, only from a Group/
            // Section/ForEach around the rows.
            Group {
                Section("Appearance") {
                    // Inside the reader: this picks the reader theme (which re-themes
                    // the app too while App & Reader are matched).
                    ReaderThemePicker(title: "Theme", selection: readerThemeBinding)

                    #if os(iOS)
                    Button {
                        showCustomize = true
                    } label: {
                        Label("Customize Theme…", systemImage: "slider.horizontal.3")
                    }
                    #endif
                }

                #if os(iOS)
                Section("Text Size") {
                    TextSizeSlider()
                }
                #endif

                ReaderLayoutSection(twoPageAvailable: twoPageAvailable)

                #if os(iOS)
                // Voice / rate / pitch for the Readium read-aloud mini player.
                // macOS still uses the legacy WKWebView reader without TTS.
                ReaderSpeechSettingsSection()
                #endif

                ReaderFontSection(onAddFont: { isImportingFonts = true })
            }
            .appThemedRows()
        }
        .formStyle(.grouped)
        .appThemedScroll()
        .readerFontImporter(isPresented: $isImportingFonts)
        #if os(iOS)
        .sheet(isPresented: $showCustomize) {
            CustomizeThemeView()
                .environment(themeManager)
                .tint(themeManager.effectiveTint)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        #endif
    }
}

/// A segmented Light/Sepia/Dark/OLED picker bound to the given selection.
struct ReaderThemePicker: View {
    let title: String
    @Binding var selection: ReaderTheme

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(ReaderTheme.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelStyle(.titleOnly)
    }
}

/// Layout, two-page spread and keep screen awake — the reader's sheet and
/// Settings › Reader.
struct ReaderLayoutSection: View {
    /// Whether the two-page spread can take effect (the reader passes its window
    /// width; Settings has no window context, so it allows the toggle freely).
    var twoPageAvailable: Bool = true

    @AppStorage("readerMode") private var readingMode: ReadingMode = .scroll
    @AppStorage("readerTwoPage") private var twoPageEnabled = false
    @AppStorage("keepScreenAwake") private var keepScreenAwake = false

    /// Two-page spread is offered on iPad and macOS but never on iPhone. (iPad
    /// compiles under `os(iOS)`, so this is a runtime idiom check.)
    private var twoPageSpreadAvailable: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom != .phone
        #else
        return true
        #endif
    }

    var body: some View {
        Section {
            Picker("Layout", selection: $readingMode) {
                ForEach(ReadingMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelStyle(.titleOnly)

            // Two-page spread is hidden on iPhone (no practical use); shown on
            // iPad and macOS.
            if twoPageSpreadAvailable {
                Toggle("Two-page spread", isOn: $twoPageEnabled)
                    .disabled(readingMode != .paged || !twoPageAvailable)
            }

            // 1ab files this under Reading. iOS only: macOS has no idle
            // timer to hold open, and a switch that did nothing there
            // would be worse than its absence.
            #if os(iOS)
            Toggle("Keep screen awake", isOn: $keepScreenAwake)
            #endif
        } header: {
            Text("Reading")
        } footer: {
            Text(twoPageSpreadAvailable
                ? "Two-page spread is available in Paged mode on wider windows."
                : "Choose how pages turn while reading.")
        }
    }
}

/// The font list — the reader's sheet and Settings › Font. The host presents
/// the file picker (`readerFontImporter`), because a view node honours only one
/// file-dialog presenter and the host is where that one lives.
struct ReaderFontSection: View {
    let onAddFont: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \CustomFont.dateAdded) private var customFonts: [CustomFont]
    @AppStorage("readerFontID") private var fontID: String = "system"

    /// All selectable fonts: built-ins followed by imported ones.
    private var fontOptions: [ReaderFontOption] {
        ReaderFontOption.options(customFonts: customFonts)
    }

    var body: some View {
        Section("Font") {
            ForEach(fontOptions) { option in
                Button {
                    fontID = option.id
                } label: {
                    HStack {
                        Text(option.name).foregroundStyle(.primary)
                        if option.isCustom {
                            Image(systemName: "person.crop.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if option.id == fontID {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: deleteCustomFonts)

            Button(action: onAddFont) {
                Label("Add Font…", systemImage: "plus")
            }
        }
    }

    private func deleteCustomFonts(at offsets: IndexSet) {
        for index in offsets where index < fontOptions.count {
            let option = fontOptions[index]
            guard option.isCustom,
                  let font = customFonts.first(where: { $0.selectionID == option.id })
            else { continue }
            if fontID == font.selectionID { fontID = "system" }
            try? FileManager.default.removeItem(at: font.fileURL)
            context.delete(font)
        }
        try? context.save()
    }
}

extension View {
    /// The font file picker and its result alert, for a host of `ReaderFontSection`.
    func readerFontImporter(isPresented: Binding<Bool>) -> some View {
        modifier(ReaderFontImporter(isPresented: isPresented))
    }
}

private struct ReaderFontImporter: ViewModifier {
    @Binding var isPresented: Bool

    @Environment(\.modelContext) private var context
    @AppStorage("readerFontID") private var fontID: String = "system"
    @State private var fontNotice: SettingsNotice?

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: [.font],
                allowsMultipleSelection: true
            ) { result in
                if case let .success(urls) = result { urls.forEach(importFont) }
            }
            .settingsNoticeAlert($fontNotice)
    }

    private func importFont(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            fontNotice = SettingsNotice(
                title: "Couldn't Add Font",
                message: "That file couldn't be read."
            )
            return
        }
        let ext = url.pathExtension.isEmpty ? "ttf" : url.pathExtension
        let fileName = "\(UUID().uuidString).\(ext)"

        // Checked against the rules a restore enforces, before anything is
        // written. Nothing used to check: the picker's `.font` type accepts
        // `.ttc`, `.woff` and the rest, and no size was looked at — so a font
        // the app installed happily could make the reader's whole library
        // backup refuse to restore, discovered only on the new phone.
        if let reason = KudosBackupContents.fontRejectionReason(fileName: fileName, data: data) {
            fontNotice = SettingsNotice(
                title: "Couldn't Add Font",
                message: reason + " Keeping it would stop your library backup from restoring."
            )
            return
        }
        if let reason = fontTotalRejectionReason(adding: data.count) {
            fontNotice = SettingsNotice(title: "Couldn't Add Font", message: reason)
            return
        }

        let destination = Storage.fontsDirectory.appendingPathComponent(fileName)
        guard (try? data.write(to: destination)) != nil else {
            fontNotice = SettingsNotice(
                title: "Couldn't Add Font",
                message: "The font couldn't be saved to this device."
            )
            return
        }

        let font = CustomFont(name: url.deletingPathExtension().lastPathComponent, fileName: fileName)
        context.insert(font)
        try? context.save()
        fontID = font.selectionID
    }

    /// Restore caps the *total* font payload too, and rejects the whole backup
    /// when the set is over it — so fonts that are each perfectly valid can
    /// still cost a library between them. Measured against what is installed,
    /// fetched at the add itself (a modifier has no `@Query` of its own).
    private func fontTotalRejectionReason(adding newBytes: Int) -> String? {
        let customFonts = (try? context.fetch(FetchDescriptor<CustomFont>())) ?? []
        let installed = customFonts.reduce(0) { total, font in
            total + ((try? font.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        guard installed + newBytes > KudosBackupContents.maxTotalFontBytes else { return nil }
        let limit = KudosBackupContents.maxTotalFontBytes / (1024 * 1024)
        return "Your fonts would go over the \(limit) MB a backup can carry, "
            + "which would stop your library backup from restoring."
    }
}

/// Classify Replace confirmation counts with the same identity order restore uses.
enum BackupReplaceWorkDelta {
    @MainActor
    static func classify(
        localWorks: [SavedWork],
        incoming: [KudosBackupWork]
    ) -> (willAdd: Int, willRemove: Int, inBoth: Int) {
        let index = WorkIdentityIndex(localWorks)
        var matchedLocalIDs = Set<UUID>()
        var willAdd = 0
        for archived in incoming {
            if let existing = index.existingWork(
                ao3WorkID: archived.ao3WorkID,
                sourceURL: archived.sourceURL,
                recordID: archived.id
            ) {
                matchedLocalIDs.insert(existing.id)
            } else {
                willAdd += 1
            }
        }
        return (
            willAdd,
            localWorks.filter { !matchedLocalIDs.contains($0.id) }.count,
            matchedLocalIDs.count
        )
    }
}

/// Extra step for Replace Library: counts, checkbox, delayed red button, optional
/// pause-sync, and a pre-replace backup of the current library.
struct ReplaceLibraryConfirmationView: View {
    let manifest: KudosBackupManifest
    let localWorks: [SavedWork]
    let syncIsConnected: Bool
    let onConfirm: (Bool) -> Void
    let onCancel: () -> Void
    let makePreReplaceBackup: () -> Result<String, Error>

    @State private var acknowledgedRemoval = false
    /// The pending "enable the red button" wait, held so a re-tick starts its
    /// own 1.5 seconds instead of inheriting what is left of the last one.
    @State private var enableTask: Task<Void, Never>?
    @State private var pauseSync = true
    @State private var replaceEnabled = false
    @State private var backupFileName: String?
    @State private var backupError: String?
    /// What Replace actually does, because the previous wording was not true.
    ///
    /// It read: "It does not plant deletion records that would block a later
    /// Merge of your own backup." That holds for works — they are soft-deleted
    /// into Recently Deleted with no tombstone, and the code says why: standing
    /// tombstones would block a later merge. It does not hold for the
    /// immediate-delete classes. Replace hard-deletes saved links, saved
    /// searches, reading history, stars and fandom watermarks and mints a
    /// signed tombstone for each, which is exactly a deletion record that
    /// blocks a later Merge. `replaceThenMergeDoesNotResurrectOmittedBookmarkOrSavedSearch`
    /// pins that on purpose: without the tombstone, merging any older backup
    /// would resurrect them.
    ///
    /// So the behaviour stays and the sentence changes — and it now names the
    /// recovery that does work. Restore bypasses tombstones entirely in
    /// `.replaceLibrary`, so importing the undo copy with **Replace** brings
    /// these records back, while importing it with Merge silently will not.
    /// That is the difference between an undo and a promise of one, and this is
    /// the screen where the reader decides.
    ///
    /// Held as one string rather than built in the body: this view is already
    /// at the type checker's limit.
    private static let replaceFooterText = """
        Replace Library only changes this device. Works it removes go to Recently \
        Deleted, so a later Merge can bring them back. Saved links, saved searches, \
        reading history, stars and fandom watermarks are removed outright and \
        recorded as deletions, which a Merge will not undo. To undo this \
        completely, import the undo copy with Replace rather than Merge.
        """

    /// Whether this presentation actually produced an undo copy.
    @State private var backupSucceeded = false
    /// Whether to offer the override. True only when the safety backup failed
    /// AND it had already failed on a previous attempt — so a first failure
    /// blocks outright and only a deliberate retry can opt out.
    @State private var offersRiskOverride = false
    @State private var riskAccepted = false
    /// Survives this sheet so "they tried again" is knowable at all.
    @AppStorage("backup.replaceBlockedBySafetyFailure") private var wasBlockedBefore = false

    /// Replace needs the deliberation delay AND a real undo copy — or, on a
    /// repeat attempt, an explicit acceptance of the risk. The delay alone used
    /// to be the whole gate, so a failed safety backup showed an error and then
    /// let the destructive action proceed anyway.
    private var canReplace: Bool {
        guard replaceEnabled else { return false }
        if backupSucceeded { return true }
        return offersRiskOverride && riskAccepted
    }

    /// Same identity order restore uses: ao3WorkID → canonical sourceURL → recordID.
    private var replaceDelta: (willAdd: Int, willRemove: Int, inBoth: Int) {
        BackupReplaceWorkDelta.classify(localWorks: localWorks, incoming: manifest.works)
    }

    private var willRemove: Int { replaceDelta.willRemove }
    private var willAdd: Int { replaceDelta.willAdd }
    private var inBoth: Int { replaceDelta.inBoth }
    private var backupIsMuchSmaller: Bool { willRemove >= 20 && willRemove >= willAdd * 10 }

    /// What the undo copy did or did not do, and the way out if it failed twice.
    ///
    /// Its own property because this view's `Form` is already long enough that
    /// adding branches inline pushes the type checker past its limit in this
    /// file — the same reason `AboutSettingsSection` was split out.
    @ViewBuilder
    private var safetyBackupStatus: some View {
        if let backupFileName, backupSucceeded {
            Text("A copy of your current library was saved as \(backupFileName).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if let backupError {
            VStack(alignment: .leading, spacing: 8) {
                Text("Could not save an undo copy")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
                Text(backupError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                if offersRiskOverride {
                    Text("This is the second time. Replacing now will delete works "
                        + "with no way to undo it — there is no copy of your current "
                        + "library to put back.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                    Toggle(isOn: $riskAccepted) {
                        Text("I understand the risks")
                            .font(.footnote.weight(.semibold))
                    }
                } else {
                    Text("Replace is blocked until a copy can be saved. Free some "
                        + "space and try again.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("This backup") {
                    LabeledContent("Works in your library", value: "\(localWorks.count)")
                    LabeledContent("Works in this backup", value: "\(manifest.works.count)")
                    LabeledContent("Will be added", value: "\(willAdd)")
                    LabeledContent("Will be removed", value: "\(willRemove)")
                    LabeledContent("In both", value: "\(inBoth)")
                }
                if backupIsMuchSmaller {
                    Section {
                        Text("This backup is much smaller than your library.")
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    Toggle(isOn: $acknowledgedRemoval) {
                        Text("Remove \(willRemove) works that are not in this backup")
                    }
                    if syncIsConnected {
                        Toggle("Pause Library Sync on this device", isOn: $pauseSync)
                        Text("Sync will put removed works back. Pause sync for this device?")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    safetyBackupStatus
                } footer: {
                    Text(Self.replaceFooterText)
                }
            }
            .navigationTitle("Replace Library")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Replace Library") {
                        onConfirm(syncIsConnected && pauseSync)
                    }
                    .disabled(!canReplace)
                    .foregroundStyle(canReplace ? .red : .secondary)
                }
            }
            .onAppear {
                // Read BEFORE recording this attempt, or a first failure would
                // immediately look like a repeat and offer its own override.
                let hadBeenBlocked = wasBlockedBefore
                switch makePreReplaceBackup() {
                case let .success(name):
                    backupFileName = name
                    backupSucceeded = true
                    // A good copy clears the escalation: the next Replace starts
                    // from a blocked state again rather than a standing override.
                    wasBlockedBefore = false
                case let .failure(error):
                    backupError = error.localizedDescription
                    backupSucceeded = false
                    offersRiskOverride = hadBeenBlocked
                    wasBlockedBefore = true
                }
            }
            .onChange(of: acknowledgedRemoval) { _, checked in
                // Cancel the one already waiting. The delay exists so the red
                // button cannot be reached by a reflex, and without this a
                // check / uncheck / re-check could ride the FIRST sleep to
                // completion — the re-check only has to land before it
                // finishes, and the current-value test at the end would then
                // see a box that is ticked and enable the button early.
                enableTask?.cancel()
                replaceEnabled = false
                guard checked else { return }
                enableTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled, acknowledgedRemoval else { return }
                    replaceEnabled = true
                }
            }
        }
    }
}

/// Names the pre-replace safety copy.
///
/// Its own type so the uniqueness rule can be tested: this file is a SwiftUI
/// view and `makePreReplaceBackup` cannot be called from a test.
nonisolated enum PreReplaceBackupNaming {
    /// How many times a safety backup is attempted before Replace is blocked.
    /// More than one because a single write failure is not proof the disk is
    /// full, and the cost of wrongly giving up is an unrecoverable replace.
    static let attemptLimit = 3

    static let fileExtension = "kudosbackup"

    /// Seconds, not just the date. A date alone meant every copy taken on one
    /// day shared a filename.
    ///
    /// Built per call rather than held as one shared instance. `DateFormatter`
    /// cannot be used from two threads at once, and this type is `nonisolated`,
    /// so nothing stops that from happening — two concurrent callers took the
    /// process down. A few allocations on a path that runs once per Replace is
    /// not worth a lock, and a crash here costs the reader their only undo.
    static func makeTimestampFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return formatter
    }

    static func fileName(at date: Date, attempt: Int) -> String {
        let stamp = makeTimestampFormatter().string(from: date)
        // A retry within the same second still gets its own name, so the retry
        // cannot be the thing that overwrites the copy it is retrying for.
        let suffix = attempt == 0 ? "" : " (\(attempt + 1))"
        return "Kudos Library Before Replace \(stamp)\(suffix)"
    }

    static func url(in directory: URL, at date: Date, attempt: Int) -> URL {
        directory
            .appendingPathComponent(fileName(at: date, attempt: attempt))
            .appendingPathExtension(fileExtension)
    }
}
