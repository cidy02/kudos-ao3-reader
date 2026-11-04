import LocalAuthentication
import OSLog
import SwiftUI

/// How Mature/Explicit works are presented when content privacy is on.
enum MaturePrivacyMode: String, CaseIterable, Identifiable {
    case obscure, hide
    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .obscure: "Blur"
        case .hide: "Hide"
        }
    }
}

extension SavedWork {
    /// AO3-rated Mature or Explicit — the works the privacy feature shields.
    var isAdult: Bool {
        rating == "Mature" || rating == "Explicit"
    }
}

extension AO3WorkSummary {
    /// AO3-rated Mature or Explicit — the works the privacy feature shields.
    var isAdult: Bool {
        rating == "Mature" || rating == "Explicit"
    }
}

/// One reveal affordance everywhere a mature item keeps its blurred footprint.
struct MatureRevealCapsule: View {
    var body: some View {
        Label("Tap to Reveal", systemImage: "eye.slash")
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .accessibilityHidden(true)
    }
}

/// Tracks which sensitive works the user has temporarily revealed this session,
/// and gates reveals behind device biometrics when the user has enabled that.
@MainActor
@Observable
final class PrivacyGate {
    private(set) var revealedIDs: Set<UUID> = []
    private(set) var revealedRemoteIDs: Set<Int> = []
    /// When true, every sensitive work is shown until toggled back off.
    private(set) var revealAll = false

    func isRevealed(_ work: SavedWork) -> Bool {
        let remoteID = work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL)
        return revealAll || revealedIDs.contains(work.id)
            || (remoteID.map { revealedRemoteIDs.contains($0) } ?? false)
    }

    func isRevealed(_ work: AO3WorkSummary) -> Bool {
        revealAll || revealedRemoteIDs.contains(work.id)
    }

    func isRevealed(remoteID: Int) -> Bool {
        revealAll || revealedRemoteIDs.contains(remoteID)
    }

    /// Reveals a single work (a Blur-mode tap), authenticating first if required.
    /// `alsoRemoteID` is the canonical remote twin's id, revealed in the same (single) authentication.
    func reveal(_ work: SavedWork, alsoRemoteID: Int? = nil) {
        authenticate {
            self.revealedIDs.insert(work.id)
            if let ao3ID = work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL) {
                self.revealedRemoteIDs.insert(ao3ID)
            }
            if let alsoRemoteID { self.revealedRemoteIDs.insert(alsoRemoteID) }
            Log.privacy.info("Revealed a mature work for this session")
        }
    }

    func reveal(_ work: AO3WorkSummary) {
        reveal(remoteID: work.id)
    }

    func reveal(remoteID: Int) {
        authenticate {
            self.revealedRemoteIDs.insert(remoteID)
            Log.privacy.info("Revealed a mature remote work for this session")
        }
    }

    /// Shows or re-hides every sensitive work for the session.
    func toggleRevealAll() {
        if revealAll {
            revealAll = false
            revealedIDs.removeAll()
            revealedRemoteIDs.removeAll()
            Log.privacy.info("Re-hid all mature works")
        } else {
            authenticate {
                self.revealAll = true
                Log.privacy.info("Revealed all mature works for this session")
            }
        }
    }

    /// Whether this work should be omitted from a list right now (Hide mode only).
    func isHidden(_ work: SavedWork, enabled: Bool, mode: MaturePrivacyMode) -> Bool {
        enabled && work.isAdult && mode == .hide && !isRevealed(work)
    }

    func isHidden(_ work: AO3WorkSummary, enabled: Bool, mode: MaturePrivacyMode) -> Bool {
        enabled && work.isAdult && mode == .hide && !isRevealed(work)
    }

    /// Whether this work is drawn blurred right now (Blur mode only): until it is revealed,
    /// nothing may open it or name it.
    func isBlurred(_ work: SavedWork, enabled: Bool, mode: MaturePrivacyMode) -> Bool {
        enabled && work.isAdult && mode == .obscure && !isRevealed(work)
    }

    /// An unknown rating is drawn blurred in either mode (we do not know it is safe), and
    /// stays revealable by its id; once enrichment supplies a rating the normal rules apply.
    func isBlurred(_ work: AO3WorkSummary, enabled: Bool, mode: MaturePrivacyMode) -> Bool {
        (enabled && work.isAdult && mode == .obscure && !isRevealed(work))
            || isPrivacyUndetermined(work, enabled: enabled)
    }

    /// Whether a place that shows a work's title or author must leave this one out right
    /// now: Hide keeps it out of lists, and Blur lets nothing name it until it is revealed.
    /// For anything that cannot draw the blurred card (a picker row, a tile's small cover).
    func isConcealed(_ work: SavedWork, enabled: Bool) -> Bool {
        enabled && work.isAdult && !isRevealed(work)
    }

    func isConcealed(_ work: AO3WorkSummary, enabled: Bool) -> Bool {
        (enabled && work.isAdult && !isRevealed(work)) || isPrivacyUndetermined(work, enabled: enabled)
    }

    /// A sparse AO3 listing has not supplied the rating yet. Keep it anonymous
    /// while privacy is on rather than briefly exposing a possibly-adult work.
    func isPrivacyUndetermined(_ work: AO3WorkSummary, enabled: Bool) -> Bool {
        enabled
            && work.rating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isRevealed(work)
    }

    func isHidden(_ work: CanonicalWork, enabled: Bool, mode: MaturePrivacyMode) -> Bool {
        (work.local.map { isHidden($0, enabled: enabled, mode: mode) } ?? false)
            || (work.remote.map { isHidden($0, enabled: enabled, mode: mode) } ?? false)
    }

    /// A sparse remote with no rating defers to a rated local twin instead of blurring it.
    private func remoteDefersToLocal(_ work: CanonicalWork) -> Bool {
        guard let local = work.local, let remote = work.remote else { return false }
        return !local.rating.isEmpty
            && remote.rating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func isBlurred(_ work: CanonicalWork, enabled: Bool, mode: MaturePrivacyMode) -> Bool {
        (work.local.map { isBlurred($0, enabled: enabled, mode: mode) } ?? false)
            || (!remoteDefersToLocal(work)
                && (work.remote.map { isBlurred($0, enabled: enabled, mode: mode) } ?? false))
    }

    func isConcealed(_ work: CanonicalWork, enabled: Bool) -> Bool {
        (work.local.map { isConcealed($0, enabled: enabled) } ?? false)
            || (!remoteDefersToLocal(work)
                && (work.remote.map { isConcealed($0, enabled: enabled) } ?? false))
    }

    /// A series-edit row carries only its blurb's rating and id: concealed (title masked) once
    /// it is Mature/Explicit and unrevealed, in Blur and Hide alike (the row cannot be omitted
    /// without breaking the reorder it belongs to).
    func isConcealed(_ row: AO3SeriesWorkRow, enabled: Bool) -> Bool {
        enabled && row.isAdult && !(row.sourceWorkID.map { isRevealed(remoteID: $0) } ?? false)
    }

    private func authenticate(_ onSuccess: @escaping () -> Void) {
        guard UserDefaults.standard.bool(forKey: "requireBiometricToReveal") else {
            onSuccess(); return
        }
        let context = LAContext()
        var error: NSError?
        // If no passcode/biometrics are enrolled, don't lock the user out of their library.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            onSuccess(); return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "View mature content") { success, _ in
            if success {
                Task { @MainActor in onSuccess() }
            } else {
                Log.privacy.notice("Biometric auth failed or was cancelled; mature content stays hidden")
            }
        }
    }
}

/// A work row that respects content privacy. When the work is Mature/Explicit and
/// Blur mode is on, it blurs the row and reveals on tap; in Hide mode the list
/// filters the work out before it reaches this view (or this view renders EmptyView).
/// Otherwise it's a normal navigation row. The caller still attaches its own `.swipeActions`.
struct SensitiveWorkRow: View {
    private enum Target {
        case saved(SavedWork)
        case remote(AO3WorkSummary)
    }

    private let target: Target
    var expandAll: Bool = false
    var openMode: LocalWorkRowOpenMode = .detail
    var onSelect: (() -> Void)?
    var isSelecting: Bool = false
    var isSelected: Bool = false
    var onToggleSelection: (() -> Void)?
    var savedPresentation: WorkRow.Presentation = .standard
    var remotePresentation: AO3WorkRow.Presentation = .standard
    var showsFavoriteStar = false
    var showsFullLedgerStats = false
    var showsPerformance = false
    var bookmark: AO3AuthorBookmark?
    var signal: String?
    var qualitySignal: WorkSignal? = nil
    var rankedContext: RankedWork? = nil
    var remoteBadgeTitle: String?
    var showsSummary = true
    var showsTags = true
    var showsProgress = true
    var leadingSelection = false
    var badgeCount = 0
    var wide = false
    var showsSeparator = true
    var usesInlineNavigation: Bool = false
    var contentInsets = EdgeInsets()
    var scopedRemoval: ScopedRemoval?
    var queueMenu: QueueItemMenuActions?
    /// The canonical remote twin of a saved work: if it is Mature/Explicit the row is
    /// concealed even when the local copy's rating is empty or stale.
    private var twin: AO3WorkSummary?

    @Environment(PrivacyGate.self) private var gate
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var mode: MaturePrivacyMode = .obscure
    @State private var blurredExpanded = false

    init(
        work: SavedWork,
        expandAll: Bool = false,
        openMode: LocalWorkRowOpenMode = .detail,
        onSelect: (() -> Void)? = nil,
        isSelecting: Bool = false,
        isSelected: Bool = false,
        onToggleSelection: (() -> Void)? = nil,
        presentation: WorkRow.Presentation = .standard,
        showsFavoriteStar: Bool = false,
        showsFullLedgerStats: Bool = false,
        showsSummary: Bool = true,
        showsTags: Bool = true,
        showsProgress: Bool = true,
        leadingSelection: Bool = false,
        badgeCount: Int = 0,
        wide: Bool = false,
        showsSeparator: Bool = true,
        usesInlineNavigation: Bool = false,
        contentInsets: EdgeInsets = EdgeInsets(),
        scopedRemoval: ScopedRemoval? = nil,
        queueMenu: QueueItemMenuActions? = nil,
        twin: AO3WorkSummary? = nil
    ) {
        self.target = .saved(work)
        self.twin = twin
        self.expandAll = expandAll
        self.openMode = openMode
        self.onSelect = onSelect
        self.isSelecting = isSelecting
        self.isSelected = isSelected
        self.onToggleSelection = onToggleSelection
        self.savedPresentation = presentation
        self.showsFavoriteStar = showsFavoriteStar
        self.showsFullLedgerStats = showsFullLedgerStats
        self.showsSummary = showsSummary
        self.showsTags = showsTags
        self.showsProgress = showsProgress
        self.leadingSelection = leadingSelection
        self.badgeCount = badgeCount
        self.wide = wide
        self.showsSeparator = showsSeparator
        self.usesInlineNavigation = usesInlineNavigation
        self.contentInsets = contentInsets
        self.scopedRemoval = scopedRemoval
        self.queueMenu = queueMenu
    }

    init(
        work: AO3WorkSummary,
        expandAll: Bool = false,
        onSelect: (() -> Void)? = nil,
        isSelecting: Bool = false,
        isSelected: Bool = false,
        onToggleSelection: (() -> Void)? = nil,
        presentation: AO3WorkRow.Presentation = .standard,
        showsPerformance: Bool = false,
        bookmark: AO3AuthorBookmark? = nil,
        signal: String? = nil,
        qualitySignal: WorkSignal? = nil,
        rankedContext: RankedWork? = nil,
        badgeTitle: String? = nil,
        showsSummary: Bool = true,
        badgeCount: Int = 0,
        wide: Bool = false,
        showsSeparator: Bool = true,
        usesInlineNavigation: Bool = false,
        contentInsets: EdgeInsets = EdgeInsets()
    ) {
        self.target = .remote(work)
        self.expandAll = expandAll
        self.onSelect = onSelect
        self.isSelecting = isSelecting
        self.isSelected = isSelected
        self.onToggleSelection = onToggleSelection
        self.remotePresentation = presentation
        self.showsPerformance = showsPerformance
        self.bookmark = bookmark
        self.signal = signal
        self.qualitySignal = qualitySignal
        self.rankedContext = rankedContext
        self.remoteBadgeTitle = badgeTitle
        self.showsSummary = showsSummary
        self.badgeCount = badgeCount
        self.wide = wide
        self.showsSeparator = showsSeparator
        self.usesInlineNavigation = usesInlineNavigation
        self.contentInsets = contentInsets
    }

    private var isHidden: Bool {
        switch target {
        case .saved(let work):
            gate.isHidden(work, enabled: hideMature, mode: mode)
                || (twin.map { gate.isHidden($0, enabled: hideMature, mode: mode) } ?? false)
        case .remote(let work):
            gate.isHidden(work, enabled: hideMature, mode: mode)
        }
    }

    private var blurred: Bool {
        switch target {
        case .saved(let work):
            gate.isBlurred(work, enabled: hideMature, mode: mode)
                || (twin.map { gate.isBlurred($0, enabled: hideMature, mode: mode) } ?? false)
        case .remote(let work):
            gate.isBlurred(work, enabled: hideMature, mode: mode)
        }
    }

    var body: some View {
        if isHidden {
            EmptyView()
        } else if blurred {
            blurredBody
        } else {
            visibleBody
        }
    }

    @ViewBuilder
    private var blurredBody: some View {
        switch target {
        case .saved(let work):
            let isExpandableWork = savedPresentation == .standard
                && WorkRow.isExpandable(for: work, showsSummary: showsSummary)
            let content = WorkRow(
                work: work,
                expandAll: expandAll,
                showsExpandButton: false,
                externalExpanded: $blurredExpanded,
                presentation: savedPresentation,
                showsFavoriteStar: showsFavoriteStar,
                showsFullLedgerStats: showsFullLedgerStats,
                showsSummary: showsSummary,
                showsTags: showsTags,
                showsProgress: showsProgress,
                leadingSelection: leadingSelection,
                badgeCount: badgeCount,
                wide: wide,
                showsSeparator: showsSeparator
            )
            .padding(contentInsets)
            .environment(\.ao3AuthorNavigationEnabled, false)
            .blur(radius: 6)
            .overlay {
                if !isSelecting {
                    MatureRevealCapsule()
                }
            }
            .contentShape(Rectangle())
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 6) {
                    if isExpandableWork {
                        WorkRowExpandButton(expanded: $blurredExpanded)
                    }
                    if isSelecting && !leadingSelection {
                        WorkSelectionBubble(isSelected: isSelected)
                    }
                }
                // The unblurred row's controls sit inside its gutter; 8 pt left them out of line.
                .padding(.top, 8)
                .padding(.trailing, SubjectMetrics.gutter + contentInsets.trailing)
            }
            .overlay(alignment: .leading) {
                if isSelecting && leadingSelection {
                    WorkLeadingSelectionCheck(isSelected: isSelected)
                        .padding(.leading, WorkRowMetrics.horizontalPadding)
                }
            }
            sensitiveActionContainer(for: content)

        case .remote(let work):
            let isExpandableWork = remotePresentation != .searchLedger
                && AO3WorkRow.isExpandable(for: work, bookmark: bookmark, showsSummary: showsSummary)
            let content = AO3WorkRow(
                work: work,
                expandAll: expandAll,
                isSelecting: isSelecting,
                isSelected: isSelected,
                showsSelectionIndicator: false,
                presentation: remotePresentation,
                showsPerformance: showsPerformance,
                bookmark: bookmark,
                signal: signal,
                qualitySignal: qualitySignal,
                rankedContext: rankedContext,
                badgeTitle: remoteBadgeTitle,
                showsSummary: showsSummary,
                badgeCount: badgeCount,
                wide: wide,
                showsSeparator: showsSeparator,
                showsExpandButton: false,
                externalExpanded: $blurredExpanded,
                showsContextMenu: false
            )
            .padding(contentInsets)
            .environment(\.ao3AuthorNavigationEnabled, false)
            .blur(radius: 6)
            .overlay {
                if !isSelecting {
                    MatureRevealCapsule()
                }
            }
            .contentShape(Rectangle())
            .overlay(alignment: .topTrailing) {
                if isExpandableWork {
                    WorkRowExpandButton(expanded: $blurredExpanded)
                        // The unblurred row's controls sit inside its gutter; 8 pt left them out of line.
                        .padding(.top, 8)
                        .padding(.trailing, SubjectMetrics.gutter + contentInsets.trailing)
                }
            }
            .overlay(alignment: .topLeading) {
                if isSelecting {
                    WorkLeadingSelectionCheck(isSelected: isSelected)
                        .frame(height: WorkRowMetrics.gridColumn)
                        .padding(.top, WorkRowMetrics.verticalPadding + contentInsets.top)
                        .padding(.leading, WorkRowMetrics.horizontalPadding + contentInsets.leading)
                }
            }
            sensitiveActionContainer(for: content)
        }
    }

    @ViewBuilder
    private func sensitiveActionContainer(for content: some View) -> some View {
        if isSelecting {
            Button {
                onToggleSelection?()
            } label: {
                content
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hidden mature work")
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select") this work.")
        } else {
            Button {
                revealTarget()
            } label: {
                content
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hidden mature work")
            .accessibilityHint("Activate to reveal.")
        }
    }

    private func revealTarget() {
        switch target {
        case .saved(let work):
            gate.reveal(work, alsoRemoteID: twin?.id)
        case .remote(let work):
            gate.reveal(work)
        }
    }

    @ViewBuilder
    private var visibleBody: some View {
        switch target {
        case .saved(let work):
            let row = WorkRow(
                work: work,
                expandAll: expandAll,
                isSelecting: isSelecting,
                isSelected: isSelected,
                presentation: savedPresentation,
                showsFavoriteStar: showsFavoriteStar,
                showsFullLedgerStats: showsFullLedgerStats,
                showsSummary: showsSummary,
                showsTags: showsTags,
                showsProgress: showsProgress,
                leadingSelection: leadingSelection,
                badgeCount: badgeCount,
                wide: wide,
                showsSeparator: showsSeparator
            )
            .padding(contentInsets)
            .contentShape(Rectangle())
            .localWorkContextMenu(
                work: work, onSelect: onSelect, scopedRemoval: scopedRemoval, queueMenu: queueMenu
            )
            selectingOrNavigating(for: row, title: work.title) {
                if usesInlineNavigation {
                    switch openMode {
                    case .detail:
                        NavigationLink(value: work) { row }.buttonStyle(.plain)
                    case .reader:
                        NavigationLink(value: LocalWorkDestination.reader(work)) { row }.buttonStyle(.plain)
                    }
                } else {
                    switch openMode {
                    case .detail:
                        row.cardNavigation(to: work, accessibilityLabel: work.title)
                    case .reader:
                        row.cardNavigation(to: LocalWorkDestination.reader(work), accessibilityLabel: work.title)
                    }
                }
            }

        case .remote(let work):
            let row = AO3WorkRow(
                work: work,
                expandAll: expandAll,
                isSelecting: isSelecting,
                isSelected: isSelected,
                presentation: remotePresentation,
                showsPerformance: showsPerformance,
                bookmark: bookmark,
                signal: signal,
                qualitySignal: qualitySignal,
                rankedContext: rankedContext,
                badgeTitle: remoteBadgeTitle,
                showsSummary: showsSummary,
                badgeCount: badgeCount,
                wide: wide,
                showsSeparator: showsSeparator,
                showsContextMenu: true
            )
            .padding(contentInsets)
            .contentShape(Rectangle())
            selectingOrNavigating(for: row, title: work.title) {
                if usesInlineNavigation {
                    NavigationLink(value: work) { row }.buttonStyle(.plain)
                } else {
                    row.cardNavigation(to: work, accessibilityLabel: work.title)
                }
            }
        }
    }

    @ViewBuilder
    private func selectingOrNavigating(
        for row: some View,
        title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        if isSelecting {
            Button {
                onToggleSelection?()
            } label: {
                row.environment(\.ao3AuthorNavigationEnabled, false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select") this work.")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            content()
        }
    }
}

/// A carousel card that respects content privacy, mirroring `SensitiveWorkRow` for
/// `WorkCoverCard` and `AO3WorkCoverCard`. When the work is Mature/Explicit and Blur mode is on, it blurs
/// the card and reveals on tap; in Hide mode the carousel filters the work out (or this view renders EmptyView).
struct SensitiveWorkCoverCard: View {
    private enum Target {
        case saved(SavedWork)
        case remote(AO3WorkSummary)
    }

    private let target: Target
    var footer: String?
    var progress: Double?
    var metadataStyle: WorkCoverMetadataStyle = .standard
    var showsProvenanceBadge: Bool = false
    var isSelecting: Bool = false
    var isSelected: Bool = false
    var onToggleSelection: (() -> Void)?
    /// The canonical remote twin of a saved work (see `SensitiveWorkRow.twin`).
    private var twin: AO3WorkSummary?
    @Environment(PrivacyGate.self) private var gate
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var mode: MaturePrivacyMode = .obscure

    init(
        work: SavedWork,
        footer: String? = nil,
        progress: Double? = nil,
        metadataStyle: WorkCoverMetadataStyle = .standard,
        isSelecting: Bool = false,
        isSelected: Bool = false,
        onToggleSelection: (() -> Void)? = nil,
        twin: AO3WorkSummary? = nil
    ) {
        self.target = .saved(work)
        self.twin = twin
        self.footer = footer
        self.progress = progress
        self.metadataStyle = metadataStyle
        self.showsProvenanceBadge = false
        self.isSelecting = isSelecting
        self.isSelected = isSelected
        self.onToggleSelection = onToggleSelection
    }

    init(
        work: AO3WorkSummary,
        showsProvenanceBadge: Bool = false,
        isSelecting: Bool = false,
        isSelected: Bool = false,
        onToggleSelection: (() -> Void)? = nil
    ) {
        self.target = .remote(work)
        self.footer = nil
        self.progress = nil
        self.metadataStyle = .standard
        self.showsProvenanceBadge = showsProvenanceBadge
        self.isSelecting = isSelecting
        self.isSelected = isSelected
        self.onToggleSelection = onToggleSelection
    }

    private var isHidden: Bool {
        switch target {
        case .saved(let work):
            gate.isHidden(work, enabled: hideMature, mode: mode)
                || (twin.map { gate.isHidden($0, enabled: hideMature, mode: mode) } ?? false)
        case .remote(let work):
            gate.isHidden(work, enabled: hideMature, mode: mode)
        }
    }

    private var blurred: Bool {
        switch target {
        case .saved(let work):
            gate.isBlurred(work, enabled: hideMature, mode: mode)
                || (twin.map { gate.isBlurred($0, enabled: hideMature, mode: mode) } ?? false)
        case .remote(let work):
            gate.isBlurred(work, enabled: hideMature, mode: mode)
        }
    }

    var body: some View {
        if isHidden {
            EmptyView()
        } else if blurred {
            blurredCard
        } else {
            visibleCard
        }
    }

    @ViewBuilder
    private var blurredCard: some View {
        switch target {
        case .saved(let work):
            let card = WorkCoverCard(
                work: work,
                footer: footer,
                progress: progress,
                metadataStyle: metadataStyle,
                showsInitial: false,
                isMatureObscured: true,
                showsMatureRevealCapsule: !isSelecting
            )
            .environment(\.ao3AuthorNavigationEnabled, false)
            .contentShape(Rectangle())
            sensitiveCoverContainer(for: card)

        case .remote(let work):
            let card = AO3WorkCoverCard(
                work: work,
                showsProvenanceBadge: showsProvenanceBadge,
                showsInitial: false,
                isMatureObscured: true,
                showsMatureRevealCapsule: !isSelecting,
                showsContextMenu: false
            )
            .environment(\.ao3AuthorNavigationEnabled, false)
            .contentShape(Rectangle())
            sensitiveCoverContainer(for: card)
        }
    }

    @ViewBuilder
    private func sensitiveCoverContainer(for card: some View) -> some View {
        if isSelecting {
            card
                .overlay(alignment: .topTrailing) {
                    WorkSelectionBubble(isSelected: isSelected)
                        .padding(8)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                        .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.clear), lineWidth: 2)
                        .allowsHitTesting(false)
                }
                .onTapGesture { onToggleSelection?() }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Hidden mature work")
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select") this work.")
        } else {
            card
                .onTapGesture { revealTarget() }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Hidden mature work")
                .accessibilityHint("Activate to reveal.")
        }
    }

    private func revealTarget() {
        switch target {
        case .saved(let work):
            gate.reveal(work, alsoRemoteID: twin?.id)
        case .remote(let work):
            gate.reveal(work)
        }
    }

    @ViewBuilder
    private var visibleCard: some View {
        switch target {
        case .saved(let work):
            if isSelecting {
                Button {
                    onToggleSelection?()
                } label: {
                    SelectableWorkCoverCard(
                        work: work,
                        footer: footer,
                        progress: progress,
                        metadataStyle: metadataStyle,
                        isSelected: isSelected
                    )
                    .environment(\.ao3AuthorNavigationEnabled, false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(work.title)
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select") this work.")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            } else {
                WorkCoverCard(
                    work: work,
                    footer: footer,
                    progress: progress,
                    metadataStyle: metadataStyle
                )
            }

        case .remote(let work):
            if isSelecting {
                Button {
                    onToggleSelection?()
                } label: {
                    AO3WorkCoverCard(
                        work: work,
                        showsProvenanceBadge: showsProvenanceBadge,
                        showsInitial: true,
                        showsContextMenu: false
                    )
                    .overlay(alignment: .topTrailing) {
                        WorkSelectionBubble(isSelected: isSelected)
                            .padding(8)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                            .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.clear), lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                    .environment(\.ao3AuthorNavigationEnabled, false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(work.title)
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select") this work.")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            } else {
                AO3WorkCoverCard(
                    work: work,
                    showsProvenanceBadge: showsProvenanceBadge,
                    showsInitial: true,
                    showsContextMenu: true
                )
            }
        }
    }
}

/// Privacy wrapper for remote work cards with a surface-specific layout.
/// It keeps the real card in place under Blur and owns navigation after reveal.
struct SensitiveRemoteWorkCard<Content: View>: View {
    let work: AO3WorkSummary
    let content: Content
    /// False for a surface that owns its own destination (an own draft opens the editor).
    var opensWork = true

    @Environment(PrivacyGate.self) private var gate
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var mode: MaturePrivacyMode = .obscure

    init(work: AO3WorkSummary, opensWork: Bool = true, @ViewBuilder content: () -> Content) {
        self.work = work
        self.opensWork = opensWork
        self.content = content()
    }

    var body: some View {
        if gate.isHidden(work, enabled: hideMature, mode: mode) {
            EmptyView()
        } else if gate.isBlurred(work, enabled: hideMature, mode: mode) {
            Button { gate.reveal(work) } label: {
                content
                    .environment(\.ao3AuthorNavigationEnabled, false)
                    .blur(radius: 6)
                    .overlay { MatureRevealCapsule() }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hidden mature work")
            .accessibilityHint("Activate to reveal.")
        } else if opensWork {
            content.cardNavigation(to: work, accessibilityLabel: work.title)
        } else {
            content
        }
    }
}

/// The eye toolbar button that reveals / re-hides Mature works for the session
/// (gated by Face ID when enabled). Shared by Library, History, and Favorites.
struct MatureRevealToggle: View {
    @Environment(PrivacyGate.self) private var gate

    var body: some View {
        Button {
            gate.toggleRevealAll()
        } label: {
            Label(gate.revealAll ? "Hide Mature" : "Show Mature",
                  systemImage: gate.revealAll ? "eye.slash" : "eye")
        }
        // Matches FilterButton: neutral unless actively toggled on. .tint(), not
        // .foregroundStyle() — see FilterButton's own comment on why.
        // nil inherits the screen's tint.
        .tint(gate.revealAll ? nil : Color.primary)
    }
}
