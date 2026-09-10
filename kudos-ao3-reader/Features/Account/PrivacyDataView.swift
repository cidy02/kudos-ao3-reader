import SwiftData
import SwiftUI

/// Account → Settings → Privacy, artboard **1ac**.
///
/// The spec's shape: a breadcrumb kicker, the page's own 32pt name, one line
/// saying nothing leaves the device, a plain statement of what the app does not
/// do, then two panels — what is stored here, and what can be cleared.
///
/// **Why the figures are measured rather than described.** The old version of
/// this screen said the right things ("everything stays on this device", "safe
/// to clear") and gave the reader no way to check any of them. A privacy page is
/// the one page where being asked to take a claim on trust is the wrong ask, and
/// the spec agrees: 1ac prints `412 MB`, `318 works`, `6`, and lets you clear
/// each. `LocalDataFootprintScanner` walks the app's own directories for those
/// bytes; the counts come from the store.
///
/// **What the spec omits and this keeps.** 1ac draws no Voice Pack section and
/// no AO3 session row. Both stay: the Voice Pack paragraph is the app's only
/// statement of what an optional model host does and does not receive, and the
/// session row is where a reader removes their AO3 credentials. `AGENTS.md`
/// treats a cleaner screen that drops metadata as a regression, and dropping
/// those two would drop the two hardest privacy facts on the page.
///
/// **What the spec asks for and the app does not have.** 1ac lists "Search
/// history · 84 searches" with a "Clear search history" button. The app keeps no
/// search history at all — `SavedSearch` is a search the reader named and saved,
/// which is their content, not a log of what they looked for. So the row says
/// that instead. On this screen, "we never recorded it" is a better answer than
/// a clear button.
struct PrivacyDataView: View {
    @Environment(\.modelContext) private var context
    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme

    /// Every live work, for the stored-on-device counts and the two bulk clears.
    /// Soft-deleted works are excluded here and again inside `LocalDataClearing`
    /// — they belong to Recently Deleted, and clearing from this screen must not
    /// reach into a queue the reader can still undo from.
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion })
    private var works: [SavedWork]

    @Query(filter: #Predicate<WorkCollection> { !$0.isPendingDeletion })
    private var collections: [WorkCollection]

    @Query private var savedSearches: [SavedSearch]

    /// Works whose file was already freed — the local reading history the
    /// existing "Clear Reading History" action moves to Recently Deleted.
    private var freedHistory: [SavedWork] {
        works.filter { !$0.hasEPUB && !$0.isQueuedForLater }
    }

    @State private var footprint = LocalStorageFootprint()
    @State private var hasMeasured = false
    @State private var confirmClearHistory = false
    @State private var confirmClearDownloads = false
    @State private var confirmClearPositions = false
    @State private var browseCacheCleared = false

    var body: some View {
        List {
            // `selfGuttered` is for the two blocks that already pad themselves —
            // the header block at its own gutter, and `SectionRuleHeader` at
            // `SubjectMetrics.gutter`. Everything else takes the account gutter
            // from the row, so a panel cannot end up flush to the screen edge.
            Section {
                header.pageBodyRow(top: 20, gutter: selfGuttered)
                promisePanel.pageBodyRow(top: 14, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Stored on this device")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                storedPanel.pageBodyRow(top: 8, gutter: gutter)
                storedFootnote.pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Clear")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                clearPanel.pageBodyRow(top: 8, gutter: gutter)
                clearFootnote.pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "AO3 session")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                sessionPanel.pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Read Aloud downloads")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                voicePackPanel.pageBodyRow(top: 8, gutter: gutter)
            }
        }
        .cardList()
        .subjectScreenWash(palette: accountPalette)
        .task { await measureIfNeeded() }
        .refreshable { await measure() }
        .confirmationDialog(
            "Clear Reading History?",
            isPresented: $confirmClearHistory,
            titleVisibility: .visible
        ) {
            Button("Clear \(countLabel(freedHistory.count, "Work"))", role: .destructive) {
                for work in freedHistory {
                    PreservedWorkService.softDelete(work, in: context)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Moves your local reading-history records to Recently Deleted for 90 days. "
                + "The works themselves can also be re-downloaded from AO3 anytime.")
        }
        .confirmationDialog(
            "Clear Downloads?",
            isPresented: $confirmClearDownloads,
            titleVisibility: .visible
        ) {
            Button("Free \(countLabel(freeableDownloads.count, "File"))", role: .destructive) {
                LocalDataClearing.clearFreeableDownloads(from: works, in: context)
                Task { await measure() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Frees the files of works you have finished and not kept. Downloaded, "
                + "favourited and queued works are left alone, and anything freed "
                + "re-downloads from AO3 when you open it.")
        }
        .confirmationDialog(
            "Clear Reading Positions?",
            isPresented: $confirmClearPositions,
            titleVisibility: .visible
        ) {
            Button("Clear \(countLabel(positionedWorks.count, "Position"))", role: .destructive) {
                LocalDataClearing.clearReadingPositions(from: works, in: context)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Forgets where you had got to in every work. The works, and the order they "
                + "appear in Continue Reading, are kept.")
        }
    }

    // MARK: Header

    /// Spec 1ac heads the page "AO3 Account › Settings" — a breadcrumb rather
    /// than a scope name, because this is two pushes deep and the kicker is the
    /// only thing on the page that says so once the navigation bar is gone.
    private var header: some View {
        SubjectHeaderBlock(
            kicker: "AO3 Account › Settings",
            title: "Privacy",
            subtitle: "Nothing leaves your device",
            palette: accountPalette,
            gutter: SubjectMetrics.accountGutter
        )
    }

    /// The account's own hue, not a work's — every account surface is scoped to
    /// the app accent (spec 1m).
    private var accountPalette: SubjectPalette {
        theme.appTheme.subjectPalette(hue: theme.scopeHue)
    }

    // MARK: The promise

    private var promisePanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No analytics, no tracking, no accounts but yours")
                .font(.system(size: 15, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("The app talks to AO3 and to nothing else. Reading position, downloads and "
                + "local collections stay on this device.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .subjectPanel()
    }

    // MARK: Stored on this device

    /// Split into two builders on purpose: `ViewBuilder` takes at most ten
    /// children, and the sizes and counts together are thirteen rows. Splitting
    /// on the sizes/counts seam also matches what the two halves are — one is
    /// measured off disk and waits for the scan, the other is known from the
    /// store the moment the page opens.
    private var storedPanel: some View {
        VStack(spacing: 0) {
            storedSizeRows
            SubjectRowSeparator()
            storedCountRows
        }
        .subjectPanel()
    }

    @ViewBuilder
    private var storedSizeRows: some View {
        SubjectFormRow(
            label: "Downloaded works",
            value: byteLabel(footprint.downloadedWorkBytes),
            isMonospaced: true
        )
        if footprint.preservedOriginalBytes > 0 {
            SubjectRowSeparator()
            SubjectFormRow(
                label: "Original files kept",
                value: byteLabel(footprint.preservedOriginalBytes),
                isMonospaced: true
            )
        }
        if footprint.importedFontBytes > 0 {
            SubjectRowSeparator()
            SubjectFormRow(
                label: "Imported fonts",
                value: byteLabel(footprint.importedFontBytes),
                isMonospaced: true
            )
        }
        SubjectRowSeparator()
        SubjectFormRow(
            label: "Caches",
            value: byteLabel(footprint.cacheBytes),
            isMonospaced: true
        )
    }

    @ViewBuilder
    private var storedCountRows: some View {
        SubjectFormRow(
            label: "Reading positions",
            value: countLabel(positionedWorks.count, "work"),
            isMonospaced: true
        )
        SubjectRowSeparator()
        SubjectFormRow(
            label: "Local collections",
            value: "\(collections.count)",
            isMonospaced: true
        )
        SubjectRowSeparator()
        SubjectFormRow(
            label: "Saved searches",
            value: "\(savedSearches.count)",
            isMonospaced: true
        )
        SubjectRowSeparator()
        SubjectFormRow(label: "Search history", value: "Not recorded")
    }

    private var storedFootnote: some View {
        footnote("Sizes are measured on this device, not estimated. Caches are rebuilt on "
            + "demand and the system may free them at any time.")
    }

    // MARK: Clear

    private var clearPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(
                label: "Clear downloads",
                value: countLabel(freeableDownloads.count, "file"),
                showsDisclosure: true,
                isDisabled: freeableDownloads.isEmpty,
                isMonospaced: true,
                action: { confirmClearDownloads = true }
            )
            SubjectRowSeparator()
            SubjectFormRow(
                label: "Clear reading positions",
                value: countLabel(positionedWorks.count, "work"),
                showsDisclosure: true,
                isDisabled: positionedWorks.isEmpty,
                isMonospaced: true,
                action: { confirmClearPositions = true }
            )
            SubjectRowSeparator()
            SubjectFormRow(
                label: "Clear reading history",
                value: countLabel(freedHistory.count, "work"),
                showsDisclosure: true,
                isDisabled: freedHistory.isEmpty,
                isMonospaced: true,
                action: { confirmClearHistory = true }
            )
            SubjectRowSeparator()
            SubjectFormRow(
                label: browseCacheCleared ? "Browse cache cleared" : "Clear browse cache",
                value: byteLabel(footprint.cacheBytes),
                isDisabled: browseCacheCleared,
                isMonospaced: true,
                action: {
                    FandomCatalog.shared.clearCache()
                    browseCacheCleared = true
                    Task { await measure() }
                }
            )
        }
        .subjectPanel()
    }

    private var clearFootnote: some View {
        footnote("Clearing is local and two-step — each of these asks first and names what it "
            + "will touch. Your reading history on AO3 is separate: clear it from History, or "
            + "turn it off in AO3 Preferences.")
    }

    // MARK: AO3 session

    private var sessionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                switch auth.status {
                case let .signedIn(username):
                    SubjectFormRow(label: "Signed in", value: username)
                    SubjectRowSeparator()
                    SubjectFormRow(
                        label: "Remove AO3 session",
                        value: "",
                        isDestructive: true,
                        action: { Task { await auth.logout() } }
                    )
                default:
                    SubjectFormRow(label: "AO3 account", value: "Not signed in")
                }
            }
            .subjectPanel()

            sessionFootnote
        }
    }

    @ViewBuilder
    private var sessionFootnote: some View {
        let notice = auth.noticeMessage
        footnote(
            "Your AO3 session is stored only on this device and is never shared."
                + (notice.map { " " + $0 } ?? "")
        )
    }

    // MARK: Read Aloud

    private var voicePackPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Optional Voice Pack downloads stay separate from your reading data.")
                .font(.system(size: 15, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Kudos never sends book text, generated audio, AO3 credentials, saved works, "
                + "reading history, analytics, or an account identifier to a Voice Pack host. "
                + "The host or its CDN can receive your IP address and standard connection "
                + "metadata. Kokoro shows this before a Voice Pack downloads; installed voice "
                + "files remain on this device.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .subjectPanel()
    }

    // MARK: Shared bits

    private var freeableDownloads: [SavedWork] {
        LocalDataClearing.selectFreeableDownloads(from: works)
    }

    private var positionedWorks: [SavedWork] {
        LocalDataClearing.selectReadingPositions(from: works)
    }

    /// A measured size, or an em dash until the scan lands. Deliberately not a
    /// redacted placeholder: the counts beside these rows are known from the
    /// store the moment the page opens, and redacting the panel to hide four
    /// pending figures would have blanked three that were already true.
    private func byteLabel(_ bytes: Int64) -> String {
        hasMeasured ? LocalStorageFootprint.formatted(bytes: bytes) : "—"
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Spec 1o's gutter for an account page, taken by the row so that a block
    /// which does not pad itself still lands on it.
    private var gutter: CGFloat { SubjectMetrics.accountGutter }

    /// For a block that already carries its own horizontal padding. Named rather
    /// than written as a bare `0`, because a `0` here reads as "flush to the
    /// edge" and means the opposite.
    private var selfGuttered: CGFloat { 0 }

    /// "1 work" / "4 works", and the capitalized form the confirmation buttons
    /// need. One helper so a plural `s` cannot go missing from one of the seven
    /// places this page counts something.
    private func countLabel(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    private func measureIfNeeded() async {
        guard !hasMeasured else { return }
        await measure()
    }

    private func measure() async {
        footprint = await LocalDataFootprintScanner.measure()
        hasMeasured = true
    }
}
