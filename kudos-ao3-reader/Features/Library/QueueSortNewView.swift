import SwiftData
import SwiftUI

/// What the queue page presents for T-529's Sort New: the queue and the `New`
/// memberships to go through, in the queue's order.
struct QueueSortNewRequest: Identifiable {
    let id = UUID()
    let queueID: UUID
    let membershipIDs: [UUID]
}

/// T-529: the board's (`Queue-Sections`) filled "Sort" in the queue page's New
/// header — one work at a time — beside T-528's sort-everything "Sort into line".
struct QueueSortNewButton: View {
    let count: Int
    let action: () -> Void

    @Environment(\.accentFill) private var accentFill

    var body: some View {
        Button(action: action) {
            Text("Sort")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(accentFill, in: Capsule())
        }
        .buttonStyle(.plain)
        .minimumHitTarget()
        .accessibilityLabel(count == 1 ? "Sort 1 new work" : "Sort \(count) new works")
    }
}

/// T-529 Sort New (board `Queue-Sort`): the queue's `New` works one at a time,
/// with everything AO3 says about each, and Keep / Later / Drop plus Undo back
/// to the start of the session. Keep sorts into `In line`, Later leaves the work
/// in `New`, Drop takes it out of the queue (a queue-only work goes to Recently
/// Deleted; a Library work stays in the Library).
struct QueueSortNewView: View {
    let queue: ReadingQueue

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accentFill) private var accentFill
    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var themeManager
    @Environment(PrivacyGate.self) private var gate
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure

    private struct PendingDecision {
        let action: QueueSortAction
        let membershipID: UUID
        let workID: UUID
    }

    @State private var session: QueueSortSession
    /// Finger drag while the gesture is active; resets to 0 automatically if
    /// the enclosing ScrollView or a system gesture cancels the drag.
    @GestureState private var liveDragOffset: CGFloat = 0
    /// Fly-out and spring-back horizontal travel, separate from live drag.
    @State private var flyOutOffset: CGFloat = 0
    /// Captured at decision time so concurrent queue changes during the 0.18 s
    /// fly-out cannot redirect the decision to the next work, and Close /
    /// disappear can flush it once without losing it.
    @State private var pendingDecision: PendingDecision?
    @State private var containerWidth: CGFloat = 390
    @State private var undoErrorMessage: String?

    /// Caps the card on iPad / wide macOS windows so it does not stretch edge-to-edge.
    private static let maxCardWidth: CGFloat = 560

    init(queue: ReadingQueue, request: QueueSortNewRequest) {
        self.queue = queue
        _session = State(initialValue: QueueSortSession(queueID: queue.id, membershipIDs: request.membershipIDs))
    }

    private var theme: ReaderTheme { themeManager.appTheme }
    private var isCommitting: Bool { pendingDecision != nil }
    private var cardOffset: CGFloat { flyOutOffset + liveDragOffset }
    private var flyOutDistance: CGFloat { max(640, containerWidth + 80) }

    private func isWorkVisible(_ work: SavedWork) -> Bool {
        !gate.isHidden(work, enabled: hideMature, mode: matureMode)
    }

    private var currentMembership: ReadingQueueMembership? {
        guard let id = session.currentMembershipID,
              let membership = QueueSortNew.membership(id, in: queue),
              let work = membership.work,
              isWorkVisible(work)
        else { return nil }
        return membership
    }

    /// True when at least one live, visible work remains after the current one.
    private var hasNextVisibleWork: Bool {
        session.membershipIDs.dropFirst(session.sortedCount + 1).contains { id in
            guard !session.unrevisitableIDs.contains(id),
                  let work = QueueSortNew.membership(id, in: queue)?.work
            else { return false }
            return isWorkVisible(work)
        }
    }

    /// Identity token of every live, visible membership in `queue`; changes when
    /// a work is soft-deleted, replaced at the same count, or hidden by privacy.
    private var activeMembershipIDs: Set<UUID> {
        guard queue.modelContext != nil, !queue.isPendingDeletion else { return [] }
        return Set(queue.memberships.compactMap { membership in
            guard !membership.isPendingDeletion,
                  let work = membership.work,
                  work.modelContext != nil,
                  !work.isPendingDeletion,
                  isWorkVisible(work)
            else { return nil }
            return membership.id
        })
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.cardBackdrop.ignoresSafeArea())
                .toolbar { toolbarContent }
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .navigationDestination(for: SavedWork.self) { WorkDetailView(work: $0) }
                .navigationDestination(for: LocalWorkDestination.self) {
                    LocalWorkDestinationView(destination: $0)
                }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
        .onAppear {
            if queue.modelContext == nil || queue.isPendingDeletion {
                dismiss()
                return
            }
            skipMissing()
        }
        .onChange(of: queue.isPendingDeletion) { _, deleted in
            if deleted {
                pendingDecision = nil
                dismiss()
            }
        }
        .onChange(of: activeMembershipIDs) { _, _ in
            guard !isCommitting else { return }
            skipMissing()
        }
        // If the reader drilled into Work Details from a card and tapped a tag or
        // author there, close Sort New so the destination is shown rather than
        // hidden behind the full-screen cover.
        .onChange(of: router.pendingTagSearch) { _, search in
            if search != nil {
                finishPendingDecision(animated: false)
                dismiss()
            }
        }
        .onChange(of: router.authorProfileNavigationEpoch) { _, _ in
            finishPendingDecision(animated: false)
            dismiss()
        }
        .onDisappear {
            finishPendingDecision(animated: false)
        }
        .alert(
            "Couldn’t Undo",
            isPresented: Binding(
                get: { undoErrorMessage != nil },
                set: { if !$0 { undoErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(undoErrorMessage ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                finishPendingDecision(animated: false)
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Close")
        }
        ToolbarItem(placement: .principal) {
            VStack(spacing: 0) {
                Text("Sort New")
                    .font(.headline)
                Text(session.subtitle(queueName: queue.displayName))
                    .font(.caption)
                    .foregroundStyle(.secondaryInk)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Undo", action: undo)
                .disabled(!session.canUndo || isCommitting)
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private var content: some View {
        if let membership = currentMembership, let work = membership.work {
            if dynamicTypeSize.isAccessibilitySize {
                // AX sizes: the card alone can outgrow the screen, so the actions
                // scroll with it rather than pinning over it (VoiceOver also has
                // them as actions on the card).
                ScrollView {
                    VStack(spacing: 16) {
                        progressBar
                        card(membership: membership, work: work)
                        swipeHint
                        accessibilitySizeActions
                    }
                    .frame(maxWidth: Self.maxCardWidth)
                    .padding(.horizontal, SubjectMetrics.gutter)
                    .padding(.vertical, 12)
                    // Pin the column to the screen's width: at AX sizes the row's
                    // ideal width is wider than the screen, and a ScrollView
                    // would let it run off both edges (seen at AX5, 2026-11-19).
                    .containerRelativeFrame(.horizontal)
                }
            } else {
                VStack(spacing: 0) {
                    progressBar
                        .frame(maxWidth: Self.maxCardWidth)
                        .padding(.horizontal, SubjectMetrics.gutter)
                        .padding(.top, 8)
                    ScrollView {
                        card(membership: membership, work: work)
                            .padding(.horizontal, SubjectMetrics.gutter)
                            .padding(.top, 20)
                            .padding(.bottom, 16)
                            .frame(maxWidth: .infinity)
                            .containerRelativeFrame(.horizontal)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 16) {
                        swipeHint
                        actionButtons
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
            }
        } else {
            finishedView
        }
    }

    /// The board's segmented bar: sorted works full, the one on screen at 45 %,
    /// the rest at 15 %. A long New list draws one continuous bar instead of
    /// segments too thin to tell apart.
    private var progressBar: some View {
        Group {
            if session.total <= 30 {
                HStack(spacing: 3) {
                    ForEach(Array(session.segments.enumerated()), id: \.offset) { _, segment in
                        Capsule()
                            .fill(accentFill.opacity(opacity(for: segment)))
                            .frame(height: 5)
                    }
                }
            } else {
                GeometryReader { proxy in
                    let share = CGFloat(session.sortedCount) / CGFloat(max(session.total, 1))
                    ZStack(alignment: .leading) {
                        Capsule().fill(accentFill.opacity(0.15))
                        Capsule().fill(accentFill).frame(width: proxy.size.width * share)
                    }
                }
                .frame(height: 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(session.progressAccessibilityLabel)
    }

    private func opacity(for segment: QueueSortSession.Segment) -> Double {
        switch segment {
        case .sorted: 1
        case .current: 0.45
        case .upcoming: 0.15
        }
    }

    private func card(membership: ReadingQueueMembership, work: SavedWork) -> some View {
        let isConcealed = gate.isConcealed(work, enabled: hideMature)
        let footer = isConcealed ? nil : QueueSortSession.footerLine(
            minutes: ReadingQueueFacts.minutesLeft(for: work),
            originLabel: membership.origin?.label
        )
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            SensitiveWorkRow(
                work: work,
                expandAll: true,
                openMode: .detail,
                presentation: .standard,
                showsFavoriteStar: true,
                showsFullLedgerStats: true,
                wide: true,
                showsSeparator: false,
                usesInlineNavigation: true
            )
            // Keep triage cards offline and local: fandom, tag, and author taps
            // must not fire hidden AO3 searches or push behind the cover.
            .environment(\.ao3AuthorNavigationEnabled, false)
            .environment(\.workTagSearchEnabled, false)
            .padding(.vertical, 4)
            if let footer {
                Divider()
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SubjectMetrics.gutter)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
            }
        }
        // The card keeps the column's width (capped on wide screens) and aligns
        // content to topLeading so an oversized child cannot vertically center
        // the card body with blank space above the fandom label.
        .containerRelativeFrame(.horizontal, alignment: .topLeading) { length, _ in
            min(max(0, length - 2 * SubjectMetrics.gutter), Self.maxCardWidth)
        }
        .background(theme.cardSurface, in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(theme.cardBorder, lineWidth: 0.5))
        .shadow(color: theme.cardShadow.color, radius: theme.cardShadow.radius * 2, y: theme.cardShadow.y * 2)
        .background(alignment: .top) {
            // The next work waiting behind this one (the board's peeking card).
            if hasNextVisibleWork {
                shape
                    .fill(theme.cardSurface.opacity(0.7))
                    .frame(height: 80)
                    .padding(.horizontal, 16)
                    .offset(y: -10)
                    .accessibilityHidden(true)
            }
        }
        .offset(x: cardOffset)
        .rotationEffect(.degrees(reduceMotion ? 0 : Double(cardOffset) / 30), anchor: .bottom)
        .simultaneousGesture(swipeGesture)
        .id(membership.id)
        .transition(cardTransition)
        .accessibilityAction(named: "Keep in queue") { decide(.keep) }
        .accessibilityAction(named: "Decide later") { decide(.later) }
        .accessibilityAction(named: "Drop from queue") { decide(.drop) }
        .modifier(UndoAccessibilityAction(enabled: session.canUndo, action: undo))
    }

    /// Reduce Motion: the next card fades in; otherwise it settles in from a
    /// little smaller, the way a stacked card comes forward.
    private var cardTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity), removal: .opacity)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .updating($liveDragOffset) { value, state, _ in
                guard !isCommitting else { return }
                state = QueueSortSwipe.dragOffset(for: value.translation)
            }
            .onEnded { value in
                guard !isCommitting else { return }
                let startOffset = QueueSortSwipe.dragOffset(for: value.translation)
                if let action = QueueSortSwipe.decision(for: value.translation) {
                    decide(action, from: startOffset)
                } else if startOffset != 0 {
                    var snap = Transaction()
                    snap.disablesAnimations = true
                    withTransaction(snap) { flyOutOffset = startOffset }
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) { flyOutOffset = 0 }
                }
            }
    }

    private var swipeHint: some View {
        Text("Swipe left to drop, right to keep")
            .font(.footnote)
            .foregroundStyle(.secondaryInk)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

extension QueueSortNewView {
    /// The board's three round buttons: Drop and Keep at 64 pt, Later at 52 pt
    /// and set a little lower. Keep is the filled accent.
    private var actionButtons: some View {
        HStack(alignment: .top, spacing: 36) {
            roundAction(.drop, diameter: 64)
            roundAction(.later, diameter: 52)
                .padding(.top, 6)
            roundAction(.keep, diameter: 64)
        }
        .frame(maxWidth: .infinity)
    }

    private func roundAction(_ action: QueueSortAction, diameter: CGFloat) -> some View {
        Button {
            decide(action)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: Self.symbol(for: action))
                    .font(.system(size: diameter * 0.36, weight: .semibold))
                    .foregroundStyle(action == .keep ? AnyShapeStyle(.white) : glyphStyle(for: action))
                    .frame(width: diameter, height: diameter)
                    .background {
                        Circle().fill(action == .keep ? AnyShapeStyle(accentFill) : AnyShapeStyle(theme.cardSurface))
                    }
                    .overlay(Circle().strokeBorder(action == .keep ? .clear : theme.cardBorder, lineWidth: 0.5))
                    .shadow(
                        color: action == .keep ? accentFill.opacity(0.25) : Color.black.opacity(0.10),
                        radius: 10,
                        y: 6
                    )
                Text(Self.title(for: action))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCommitting)
        .accessibilityLabel(Self.accessibilityLabel(for: action))
    }

    /// AX sizes: the same three actions as full-width rows, so the label never
    /// clips beside its neighbours.
    private var accessibilitySizeActions: some View {
        VStack(spacing: 10) {
            ForEach([QueueSortAction.keep, .later, .drop], id: \.self) { action in
                Button {
                    decide(action)
                } label: {
                    Label(Self.title(for: action), systemImage: Self.symbol(for: action))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(action == .keep ? AnyShapeStyle(.white) : glyphStyle(for: action))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            action == .keep ? AnyShapeStyle(accentFill) : AnyShapeStyle(theme.cardSurface),
                            in: Capsule()
                        )
                        .overlay(Capsule().strokeBorder(action == .keep ? .clear : theme.cardBorder, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .disabled(isCommitting)
                .accessibilityLabel(Self.accessibilityLabel(for: action))
            }
        }
    }

    /// Drop's cross is the destructive red, as on the board; Later's clock is ink.
    private func glyphStyle(for action: QueueSortAction) -> AnyShapeStyle {
        action == .drop ? AnyShapeStyle(Color.red) : AnyShapeStyle(.primary)
    }

    private var finishedView: some View {
        ContentUnavailableView {
            Label("All sorted", systemImage: "checkmark.circle")
        } description: {
            Text(finishedSummary)
        } actions: {
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .accentFill()
        }
    }

    private var finishedSummary: String {
        let kept = session.count(of: .keep)
        let later = session.count(of: .later)
        let dropped = session.count(of: .drop)
        return "\(kept) kept · \(later) left for later · \(dropped) dropped"
    }

    // MARK: - Actions

    static func symbol(for action: QueueSortAction) -> String {
        switch action {
        case .keep: "checkmark"
        case .later: "clock"
        case .drop: "xmark"
        }
    }

    static func title(for action: QueueSortAction) -> String {
        switch action {
        case .keep: "Keep"
        case .later: "Later"
        case .drop: "Drop"
        }
    }

    static func accessibilityLabel(for action: QueueSortAction) -> String {
        switch action {
        case .keep: "Keep in queue"
        case .later: "Decide later"
        case .drop: "Drop from queue"
        }
    }

    private func decide(_ action: QueueSortAction, from startOffset: CGFloat = 0) {
        guard !isCommitting,
              let membership = currentMembership,
              let targetID = session.currentMembershipID,
              membership.id == targetID,
              let targetWorkID = membership.work?.id
        else { return }
        Haptics.selection()
        // Reduce Motion: no fly-out, the cards cross-fade. Later has nowhere to
        // fly (the work stays in New), so it only steps to the next card.
        if reduceMotion || action == .later {
            flyOutOffset = 0
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.28)) {
                commit(action, membershipID: targetID, workID: targetWorkID)
            }
            return
        }
        pendingDecision = PendingDecision(action: action, membershipID: targetID, workID: targetWorkID)
        if startOffset != 0 {
            var handoff = Transaction()
            handoff.disablesAnimations = true
            withTransaction(handoff) { flyOutOffset = startOffset }
        }
        let target = action == .keep ? flyOutDistance : -flyOutDistance
        withAnimation(.easeIn(duration: 0.18)) {
            flyOutOffset = target
        } completion: {
            finishPendingDecision(animated: true)
        }
    }

    private func finishPendingDecision(animated: Bool) {
        guard let pending = pendingDecision else { return }
        pendingDecision = nil
        var settle = Transaction()
        settle.disablesAnimations = true
        withTransaction(settle) { flyOutOffset = 0 }
        if animated {
            withAnimation(.snappy(duration: 0.28)) {
                commit(pending.action, membershipID: pending.membershipID, workID: pending.workID)
            }
        } else {
            commit(pending.action, membershipID: pending.membershipID, workID: pending.workID)
        }
    }

    private func commit(_ action: QueueSortAction, membershipID: UUID, workID: UUID) {
        QueueSortNew.apply(
            action,
            session: &session,
            queue: queue,
            context: context,
            expectedMembershipID: membershipID,
            expectedWorkID: workID
        )
        skipMissing()
    }

    private func skipMissing() {
        QueueSortNew.skipMissing(session: &session, queue: queue, isVisible: isWorkVisible)
    }

    private func undo() {
        guard session.canUndo, !isCommitting else { return }
        Haptics.selection()
        flyOutOffset = 0
        var outcome: QueueSortUndoResult = .nothingToUndo
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.28)) {
            outcome = QueueSortNew.undo(
                session: &session,
                queue: queue,
                context: context,
                isVisible: isWorkVisible
            )
        }
        if case .blocked = outcome {
            undoErrorMessage =
                "That change couldn’t be undone because the work or queue was changed or deleted elsewhere."
        }
    }
}

private struct UndoAccessibilityAction: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.accessibilityAction(named: "Undo", action)
        } else {
            content
        }
    }
}
