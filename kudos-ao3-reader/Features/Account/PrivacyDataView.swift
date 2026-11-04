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
    @ScaledMetric(relativeTo: .headline) private var promiseTitleSize = 17
    @ScaledMetric(relativeTo: .body) private var promiseBodySize = 13
    @ScaledMetric(relativeTo: .headline) private var voicePackTitleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .footnote) private var voicePackBodySize: CGFloat = 12.5

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
    ///
    /// Gated on `isProtected`, not on `isQueuedForLater` alone. The confirmation
    /// promises "Your saved and downloaded works are not affected", and the old
    /// filter did not keep it: a work the reader had SAVED or FAVOURITED but
    /// never downloaded has no EPUB, so it matched, and clearing history
    /// soft-deleted the very records the dialog said it would leave alone.
    ///
    /// `isProtected` also covers non-AO3 imports and works AO3 has 404'd — both
    /// of which the dialog's other promise, that the works "can be re-downloaded
    /// from AO3 anytime", is simply untrue for.
    private var freedHistory: [SavedWork] {
        LocalDataClearDialogs.freedHistory(from: works)
    }

    @State private var footprint = LocalStorageFootprint()
    @State private var hasMeasured = false
    @State private var confirmingLogOut = false
    @State private var confirmClearHistory = false
    @State private var confirmClearDownloads = false
    @State private var confirmClearPositions = false
    @State private var confirmClearBrowseCache = false
    @State private var browseCacheCleared = false

    var body: some View {
        List {
            // `selfGuttered` is for the two blocks that already pad themselves —
            // the header block at its own gutter, and `SectionRuleHeader` at
            // `SubjectMetrics.gutter`. Everything else takes the account gutter
            // from the row, so a panel cannot end up flush to the screen edge.
            Section {
                promisePanel.pageBodyRow(top: 12, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Stored on This Device")
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
                SectionRuleHeader(title: "AO3 Session")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                sessionPanel.pageBodyRow(top: 8, gutter: gutter)
            }

            Section {
                SectionRuleHeader(title: "Read Aloud Downloads")
                    .pageBodyRow(top: 18, gutter: selfGuttered)
                voicePackPanel.pageBodyRow(top: 8, gutter: gutter)
            }
        }
        .cardList()
        // Rows at their own padding, not the List minimum (L3-FORM-1).
        .environment(\.defaultMinListRowHeight, 0)
        .subjectScreenWash(title: "Privacy", palette: accountPalette)
        .task { await measureIfNeeded() }
        .refreshable { await measure() }
        .modifier(LocalDataClearDialogs(
            works: works,
            confirmHistory: $confirmClearHistory,
            confirmDownloads: $confirmClearDownloads,
            confirmPositions: $confirmClearPositions,
            confirmBrowseCache: $confirmClearBrowseCache,
            browseCacheCleared: $browseCacheCleared,
            cacheLabel: byteLabel(footprint.cacheBytes),
            onMeasure: { Task { await measure() } }
        ))
    }

    /// The account's own hue, not a work's — every account surface is scoped to
    /// the app accent (spec 1m).
    private var accountPalette: SubjectPalette {
        theme.scopePalette
    }

    private var promisePalette: SubjectPalette {
        guard let mint = SubjectHueSwatches.all.first(where: { $0.name == "Mint" }) else {
            return accountPalette
        }
        return theme.appTheme.subjectPalette(hue: mint.hue)
    }

    // MARK: The promise

    private var promisePanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No ads or tracking, and no separate Kudos account")
                .font(.system(size: promiseTitleSize, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            // Spec 1ac's line is "The app talks to AO3 and to nothing else."
            // Left as written it would be **false on this very screen**: the
            // Read Aloud section below says a Voice Pack host can see your IP
            // address. The old copy named that exception and this keeps it. A
            // privacy page that overclaims is worse than one that says less.
            Text("Kudos connects to AO3. After you approve a Voice Pack download, it also "
                + "connects to the service providing the pack. Your library, reading positions, "
                + "tags, collections, and AO3 sign-in stay on this device.")
                .font(.system(size: promiseBodySize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .fill(promisePalette.panelWash)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(promisePalette.rowBorder, lineWidth: 0.5)
        )
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
            label: "Downloaded Works",
            value: byteLabel(footprint.downloadedWorkBytes),
            isMonospaced: true
        )
        if footprint.readingCopyBytes > 0 {
            SubjectRowSeparator()
            SubjectFormRow(
                label: "Works You're Reading",
                value: byteLabel(footprint.readingCopyBytes),
                isMonospaced: true
            )
        }
        if footprint.preservedOriginalBytes > 0 {
            SubjectRowSeparator()
            SubjectFormRow(
                label: "Original Files Kept",
                value: byteLabel(footprint.preservedOriginalBytes),
                isMonospaced: true
            )
        }
        if footprint.importedFontBytes > 0 {
            SubjectRowSeparator()
            SubjectFormRow(
                label: "Imported Fonts",
                value: byteLabel(footprint.importedFontBytes),
                isMonospaced: true
            )
        }
        SubjectRowSeparator()
        SubjectFormRow(
            label: "Draft Recovery",
            value: byteLabel(footprint.draftRecoveryBytes),
            isMonospaced: true
        )
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
            label: "Reading Positions",
            value: countLabel(positionedWorks.count, "work"),
            isMonospaced: true
        )
        SubjectRowSeparator()
        SubjectFormRow(
            label: "Local Collections",
            value: "\(collections.count)",
            isMonospaced: true
        )
        SubjectRowSeparator()
        SubjectFormRow(
            label: "Saved Searches",
            value: "\(savedSearches.count)",
            isMonospaced: true
        )
        SubjectRowSeparator()
        SubjectFormRow(label: "Search History", value: "Not recorded")
    }

    private var storedFootnote: some View {
        footnote("The sizes shown are measured on this device. Browse keeps fandom and category "
            + "lists so it opens faster; it rebuilds them when needed, and your device may "
            + "remove them to free space.")
    }

    // MARK: Clear

    private var clearPanel: some View {
        VStack(spacing: 0) {
            SubjectFormRow(
                label: "Free Up Space",
                value: countLabel(freeableDownloads.count, "file"),
                showsDisclosure: true,
                isDisabled: freeableDownloads.isEmpty,
                isDestructive: true,
                isMonospaced: true,
                action: { confirmClearDownloads = true }
            )
            SubjectRowSeparator()
            SubjectFormRow(
                label: "Clear Reading Positions",
                value: countLabel(positionedWorks.count, "work"),
                showsDisclosure: true,
                isDisabled: positionedWorks.isEmpty,
                isDestructive: true,
                isMonospaced: true,
                action: { confirmClearPositions = true }
            )
            SubjectRowSeparator()
            SubjectFormRow(
                label: "Clear Reading History",
                value: countLabel(freedHistory.count, "work"),
                showsDisclosure: true,
                isDisabled: freedHistory.isEmpty,
                isDestructive: true,
                isMonospaced: true,
                action: { confirmClearHistory = true }
            )
            SubjectRowSeparator()
            SubjectFormRow(
                label: browseCacheCleared ? "Browse Cache Cleared" : "Clear Browse Cache",
                value: byteLabel(footprint.cacheBytes),
                showsDisclosure: !browseCacheCleared,
                isDisabled: browseCacheCleared,
                isDestructive: !browseCacheCleared,
                isMonospaced: true,
                // This row cleared on the tap itself, while the footnote below
                // promises "each of these asks first and names what it will
                // touch". Three rows kept that promise; the fourth broke it.
                action: { confirmClearBrowseCache = true }
            )
        }
        .subjectPanel()
    }

    private var clearFootnote: some View {
        footnote("Each option asks before it clears anything and tells you what will change on "
            + "this device. Your AO3 reading history is separate; clear it from History or turn "
            + "it off in AO3 Preferences.")
    }

    // MARK: AO3 session

    private var sessionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                switch auth.status {
                case let .signedIn(username):
                    SubjectFormRow(label: "Signed In", value: username)
                    SubjectRowSeparator()
                    SubjectFormRow(
                        label: "Remove AO3 Session",
                        value: "",
                        isDestructive: true,
                        action: { confirmingLogOut = true }
                    )
                    .logOutConfirmation(isPresented: $confirmingLogOut) { Task { await auth.logout() } }
                default:
                    SubjectFormRow(label: "AO3 Account", value: "Not signed in")
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
            "Your AO3 sign-in is kept only on this device and is never shared."
                + (notice.map { " " + $0 } ?? "")
        )
    }

    // MARK: Read Aloud

    private var voicePackPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Optional Voice Pack downloads stay separate from your reading data.")
                .font(.system(size: voicePackTitleSize, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Kudos never sends a work's text, spoken audio, your AO3 sign-in, saved works, "
                + "reading history, usage information, or anything that identifies your account "
                + "to the Voice Pack provider. The provider can see your IP address and basic "
                + "details about the connection. Kudos tells you this before downloading a "
                + "Voice Pack, and the installed voices stay on this device.")
                .font(.system(size: voicePackBodySize))
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
            .font(.system(size: voicePackBodySize))
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
        let readingCopies = works.filter { $0.hasEPUB && !$0.isDownloaded }.map(\.fileURL)
        footprint = await LocalDataFootprintScanner.measure(readingCopies: readingCopies)
        hasMeasured = true
    }
}
