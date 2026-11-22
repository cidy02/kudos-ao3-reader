import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ReaderSettingLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label {
            Text(title).foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(.tint)
                .frame(minWidth: 22) // one icon column, so titles line up row to row
        }
    }
}

/// The reader's display options — theme, text size, layout and font — in the
/// reader's options sheet (iOS), its iPhone Duo panel, and the inspector (macOS).
///
/// Settings shows the same Reader and Font sections on its own pages
/// (`SettingsReaderPage`, `SettingsFontPage`) through the shared views below, so
/// the two always show the same controls and stay in sync via `@AppStorage`.
/// App-wide settings live on those pages, not here.
///
/// Read Aloud is not here (T-562b, owner): its voice settings live in the Read
/// Aloud controls (`ReaderSpeechSettingsSheet`, from the mini player and More ›
/// Read Aloud Settings) and in Settings › Listening.
struct ReaderOptionsForm: View {
    /// An additional host constraint on spreads (the macOS reader checks its width).
    var twoPageAvailable: Bool = true
    /// Set when the form is the iPhone Duo panel (T-562b), and called by its Done.
    /// The panel is an overlay inside the pushed reader, where a navigation stack
    /// would take over the app's own (it popped the reader on the Duo), so the form
    /// draws the sheet's header itself — Customize…, the title, Done — and lists
    /// Font as one row under Text Size that opens the font list in a sheet: the
    /// board's order (`Duo-Open-Reader`), instead of the whole list after Reading.
    var panelDone: (() -> Void)?
    /// False where the host reads one page whatever the setting (the Duo held
    /// upright): the toggle stays, and the Reading footnote says where it applies.
    var twoPageSpreadApplies: Bool = true

    @Environment(ThemeManager.self) private var themeManager
    #if os(iOS)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #endif
    @State private var isImportingFonts = false
    @State private var showCustomize = false

    private var readerThemeBinding: Binding<ReaderTheme> {
        Binding(get: { themeManager.readerTheme }, set: { themeManager.readerTheme = $0 })
    }

    private var isPanel: Bool { panelDone != nil }

    var body: some View {
        #if os(iOS)
        if let panelDone {
            VStack(spacing: 0) {
                panelHeader(done: panelDone)
                form
            }
        } else {
            form
        }
        #else
        form
        #endif
    }

    #if os(iOS)
    /// The sheet's navigation bar, drawn for the panel: Customize… (inline in the
    /// form instead at accessibility sizes, as in the sheet), the title, Done.
    @ViewBuilder
    private func panelHeader(done: @escaping () -> Void) -> some View {
        let title = Text("Themes & Settings")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
        let doneButton = Button(action: done) {
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .frame(width: 30, height: 30)
        }
        .sheetConfirmStyle()
        .buttonBorderShape(.circle)
        .accessibilityLabel("Done")
        // At accessibility sizes the centred title would run under the buttons:
        // it leads and wraps instead (Customize… is already inline in the form).
        if dynamicTypeSize.isAccessibilitySize {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                title.frame(maxWidth: .infinity, alignment: .leading)
                doneButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            // Stops where a navigation bar's title stops growing, as in the sheet:
            // at AX5 the header otherwise took a third of a cover-sized panel.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        } else {
            // Spaced like the board's header: Customize… · title · Done.
            HStack(spacing: 0) {
                Button("Customize…") { showCustomize = true }
                    .buttonStyle(.glass)
                    .lineLimit(1)
                Spacer(minLength: 8)
                title.lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                doneButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
        }
    }
    #endif

    private var form: some View {
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
                    if dynamicTypeSize.isAccessibilitySize {
                        Button {
                            showCustomize = true
                        } label: {
                            Label("Customize Theme…", systemImage: "slider.horizontal.3")
                        }
                    }
                    #endif
                }

                #if os(iOS)
                Section("Text Size") {
                    TextSizeSlider()
                }

                if isPanel {
                    Section {
                        ReaderFontRow()
                    }
                }
                #endif

                ReaderLayoutSection(
                    twoPageAvailable: twoPageAvailable, twoPageSpreadApplies: twoPageSpreadApplies
                )

                if !isPanel {
                    ReaderFontSection(onAddFont: { isImportingFonts = true })
                }
            }
            .appThemedRows()
        }
        .formStyle(.grouped)
        .appThemedScroll()
        .readerFontImporter(isPresented: $isImportingFonts)
        #if os(iOS)
        .toolbar {
            if !dynamicTypeSize.isAccessibilitySize, !isPanel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Customize…") { showCustomize = true }
                }
            }
        }
        .sheet(isPresented: $showCustomize) {
            CustomizeThemeView()
                .environment(themeManager)
                .accentTint(themeManager.effectiveTint, on: themeManager.appTheme)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        #endif
    }
}

#if os(iOS)
/// Font, with the chosen font's name, opening the same list Settings › Font shows
/// (in a sheet: the Duo panel has no navigation stack to push onto).
private struct ReaderFontRow: View {
    @Environment(ThemeManager.self) private var themeManager
    @Query(sort: \CustomFont.dateAdded) private var customFonts: [CustomFont]
    @AppStorage("readerFontID") private var fontID: String = "system"
    @State private var showFonts = false

    private var fontName: String {
        ReaderFontOption.options(customFonts: customFonts).first { $0.id == fontID }?.name ?? ""
    }

    var body: some View {
        Button {
            showFonts = true
        } label: {
            LabeledContent {
                HStack(spacing: 6) {
                    Text(fontName)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            } label: {
                ReaderSettingLabel(title: "Font", systemImage: "textformat")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showFonts) {
            NavigationStack {
                SettingsFontPage()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button { showFonts = false } label: {
                                Image(systemName: "checkmark")
                            }
                            .sheetConfirmStyle()
                            .accessibilityLabel("Done")
                        }
                    }
            }
            .accentTint(themeManager.effectiveTint, on: themeManager.readerChromeTheme)
            .preferredColorScheme(themeManager.readerPage.colorScheme)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}
#endif

/// Light/Sepia/Dark/OLED tiles on iOS; the macOS inspector keeps its segmented picker.
struct ReaderThemePicker: View {
    let title: String
    @Binding var selection: ReaderTheme

    #if os(iOS)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        let count = ThemePreviewTilePicker.columnCount(
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
        )
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }
    #endif

    var body: some View {
        #if os(iOS)
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(ReaderTheme.allCases) { theme in
                ReaderThemeTile(
                    theme: theme,
                    isSelected: selection == theme,
                    onSelect: { selection = theme }
                )
            }
        }
        .padding(.vertical, 4)
        #else
        Picker(title, selection: $selection) {
            ForEach(ReaderTheme.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
        }
        .pickerStyle(.segmented)
        .accentFill()
        .labelStyle(.titleOnly)
        #endif
    }
}

#if os(iOS)
private struct ReaderThemeTile: View {
    let theme: ReaderTheme
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.accentFill) private var accentFill

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                Text("Aa")
                    .font(.system(.title2, design: .serif))
                    .foregroundStyle(theme.textColor)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(theme.backgroundColor, in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                isSelected ? accentFill : Color.secondary.opacity(0.3),
                                lineWidth: isSelected ? 2.5 : 0.5
                            )
                    }
                Text(theme.title)
                    .font(.footnote.weight(isSelected ? .bold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ThemePreviewTilePicker.accessibilityLabel(for: theme))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif

/// Layout, page turn (iOS), two-page spread and keep screen awake — the
/// reader's sheet and Settings › Reader.
struct ReaderLayoutSection: View {
    /// An additional host constraint; iOS availability also follows this view's size classes.
    var twoPageAvailable: Bool = true
    /// False in the iPhone Duo's upright layout, which shows one page whatever the
    /// setting: the toggle stays usable and the footnote says so.
    var twoPageSpreadApplies: Bool = true

    /// The footnote's spread line where the reader shows one page anyway.
    static let uprightSpreadNote =
        "Held upright, iPhone Duo shows one page. Two-page spread applies when it is open in landscape."

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage(ReaderPageTurnStyle.storageKey) private var pageTurn: ReaderPageTurnStyle = .slide
    #endif

    @AppStorage("readerMode") private var readingMode: ReadingMode = .scroll
    @AppStorage("readerTwoPage") private var twoPageEnabled = false
    @AppStorage("keepScreenAwake") private var keepScreenAwake = false

    /// Offer spreads in a regular/regular iOS layout; macOS keeps its toggle.
    private var twoPageSpreadAvailable: Bool {
        #if os(iOS)
        return WideLayout.isAvailable(horizontal: horizontalSizeClass, vertical: verticalSizeClass)
        #else
        return true
        #endif
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                ReaderSettingLabel(title: "Layout", systemImage: "book.pages")
                    .accessibilityHidden(true) // the picker below already says "Layout"
                Picker("Layout", selection: $readingMode) {
                    ForEach(ReadingMode.allCases) {
                        Label($0.title, systemImage: $0.symbol)
                            .labelStyle(.titleOnly)
                            .tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .accentFill()
                .labelsHidden()
            }

            // iOS only. macOS reads in the legacy web view, which has no
            // Readium page-turn animation to choose. Disabled outside Paged,
            // same as Two-page spread: the stored choice stays put.
            #if os(iOS)
            Picker(selection: $pageTurn) {
                ForEach(ReaderPageTurnStyle.pickerCases) { style in
                    Text(style.title).tag(style)
                }
            } label: {
                ReaderSettingLabel(title: "Page Turn", systemImage: "arrow.left.arrow.right")
            }
            .disabled(readingMode != .paged)
            .accentFill()
            .accessibilityHint("Applies in Paged layout")
            #endif

            if twoPageSpreadAvailable {
                Toggle(isOn: $twoPageEnabled) {
                    ReaderSettingLabel(title: "Two-page spread", systemImage: "rectangle.split.2x1")
                }
                    .disabled(readingMode != .paged || !twoPageAvailable)
                    .accentFill()
            }

            // 1ab files this under Reading. iOS only: macOS has no idle
            // timer to hold open, and a switch that did nothing there
            // would be worse than its absence.
            #if os(iOS)
            Toggle(isOn: $keepScreenAwake) {
                ReaderSettingLabel(title: "Keep screen awake", systemImage: "sun.max")
            }
            .accentFill()
            #endif
        } header: {
            Text("Reading")
        } footer: {
            Text(readingSectionFooter)
        }
    }

    private var readingSectionFooter: String {
        #if os(iOS)
        let spread = if !twoPageSpreadAvailable {
            "Choose whether you turn pages or scroll while reading."
        } else if twoPageSpreadApplies {
            "Two-page spread shows two pages side by side in Paged mode on wide screens, "
                + "and on iPhone Duo when it is open in landscape."
        } else {
            Self.uprightSpreadNote
        }
        return spread + " Page Turn applies in Paged mode."
        #else
        return twoPageSpreadAvailable
            ? "Two-page spread shows two pages side by side in Paged mode in a wide window."
            : "Choose whether you turn pages or scroll while reading."
        #endif
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
                                .font(.caption).foregroundStyle(.secondaryInk)
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
        Replace only changes this device. Removed works go to Recently Deleted and \
        can return through Merge; saved links, saved searches, reading history, stars, \
        and fandom visits are deleted completely and remembered as deleted, so Merge \
        will not bring them back. To restore everything, import the saved copy and \
        choose Replace.
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
                .foregroundStyle(.secondaryInk)
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
                    Text("This is the second attempt. Replacing now will delete works without "
                        + "an undo because no copy of your current library was saved.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                    Toggle(isOn: $riskAccepted) {
                        Text("I understand the risks")
                            .font(.footnote.weight(.semibold))
                    }
                    .accentFill()
                } else {
                    Text("You can't replace your library until a copy can be saved. Free some "
                        + "space and try again.")
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Themed as the import sheet it follows (A87: white under Sepia).
                Group {
                    Section("This backup") {
                        LabeledContent("Works in your library", value: "\(localWorks.count)")
                        LabeledContent("Works in this backup", value: "\(manifest.works.count)")
                        LabeledContent("Will be added", value: "\(willAdd)")
                        LabeledContent("Will be removed", value: "\(willRemove)")
                        LabeledContent("In both", value: "\(inBoth)")
                    }
                    if backupIsMuchSmaller {
                        Section {
                            Text("This backup has far fewer works than your current library.")
                                .foregroundStyle(.orange)
                        }
                    }
                    Section {
                        Toggle(isOn: $acknowledgedRemoval) {
                            Text("Remove \(willRemove) works that are not in this backup")
                        }
                        .accentFill()
                        if syncIsConnected {
                            Toggle("Pause Library Sync on this device", isOn: $pauseSync).accentFill()
                            Text("If you leave Library Sync on, it will add the removed works back. "
                                + "Pause it on this device?")
                                .font(.footnote)
                                .foregroundStyle(.secondaryInk)
                        }
                        safetyBackupStatus
                    } footer: {
                        Text(Self.replaceFooterText)
                    }
                }
                .appThemedRows()
            }
            .appThemedScroll()
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
                    .foregroundStyle(canReplace ? AnyShapeStyle(.red) : AnyShapeStyle(.secondaryInk))
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
