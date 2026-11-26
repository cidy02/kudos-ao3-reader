import Foundation
import SwiftData
import SwiftUI

/// Pure submission coordinator for `OrphanSheet`, separated so tests can verify
/// that nothing is sent to AO3 when a local copy fails or the final system alert
/// is cancelled.
@MainActor
enum OrphanSubmissionFlow {
    struct WorkCopyItem: Equatable, Sendable {
        let workID: Int
        let title: String
    }

    enum Outcome: Equatable, Sendable {
        case cancelled
        case copyFailed(workTitle: String, reason: String)
        case orphaned(String)
        case failed(String)
    }

    static func run(
        target: AO3OrphanTarget,
        keepPseudCopy: Bool,
        keepLocalCopy: Bool,
        confirmedFinalAlert: Bool,
        form: AO3OrphanForm,
        resolveWorks: @MainActor () async throws -> [WorkCopyItem],
        copyWork: @MainActor (Int) async throws -> Void,
        submitOrphan: @MainActor (AO3OrphanTarget, Bool, AO3OrphanForm) async throws -> String
    ) async -> Outcome {
        guard confirmedFinalAlert else { return .cancelled }

        if keepLocalCopy {
            let items: [WorkCopyItem]
            do {
                items = try await resolveWorks()
            } catch {
                let fallback = form.titles.first ?? "this series"
                return .copyFailed(
                    workTitle: fallback,
                    reason: UserFacingError.message(for: error)
                )
            }
            for item in items {
                do {
                    try await copyWork(item.workID)
                } catch {
                    return .copyFailed(
                        workTitle: item.title,
                        reason: UserFacingError.message(for: error)
                    )
                }
            }
        }

        do {
            let notice = try await submitOrphan(target, keepPseudCopy, form)
            return .orphaned(notice)
        } catch {
            return .failed(UserFacingError.message(for: error))
        }
    }

    /// Saves a single AO3 work into the local SwiftData library the same way
    /// Work Detail's Download action does, awaiting completion before returning.
    static func saveLocalCopy(workID: Int, in context: ModelContext) async throws {
        let sourceURL = AO3Client.workURL(workID: workID)
        if let existing = existingWork(forSource: sourceURL, in: context) {
            if existing.isPendingDeletion {
                PreservedWorkService.restore(existing, in: context)
            }
            if !WorkReaderPreparation.hasReadableEPUB(for: existing) {
                try await WorkReaderPreparation.restoreReadableEPUB(for: existing, in: context)
            }
            WorkLifecycle.setSaved(existing, true, in: context)
            return
        }
        let tempURL = try await AO3Client.shared.downloadEPUB(workID: workID)
        let saved = try await importEPUB(
            tempURL,
            source: sourceURL,
            verifyAvailability: false,
            into: context
        )
        WorkLifecycle.setSaved(saved, true, in: context)
    }

    static func resolveCopyItems(
        for target: AO3OrphanTarget,
        form: AO3OrphanForm
    ) async throws -> [WorkCopyItem] {
        switch target {
        case let .work(id):
            return [WorkCopyItem(workID: id, title: form.titles.first ?? "Work \(id)")]
        case let .works(ids):
            return ids.enumerated().map { index, id in
                let title = index < form.titles.count ? form.titles[index] : "Work \(id)"
                return WorkCopyItem(workID: id, title: title)
            }
        case let .series(seriesID):
            let seriesURL = AO3Client.seriesURL(seriesID: seriesID)
            let works = try await AO3Client.shared.seriesWorks(seriesURL: seriesURL)
            return works.map { WorkCopyItem(workID: $0.id, title: $0.title) }
        }
    }
}

/// Pure outcome handler for "Remove Me as Co-Creator" on both works and series,
/// guaranteeing `.onlyCreator` surfaces the exact message and mutates nothing.
@MainActor
enum WorkCoCreatorRemovalFlow {
    enum TargetKind: Equatable, Sendable {
        case work
        case series

        var onlyCreatorMessage: String {
            switch self {
            case .work:
                "You're the only creator of this work. You can orphan it or delete it instead."
            case .series:
                "You're the only creator of this series. You can orphan it or delete it instead."
            }
        }
    }

    enum Outcome: Equatable, Sendable {
        case removed(String)
        case onlyCreator(String)
        case failed(String)
    }

    static func run(
        kind: TargetKind,
        remove: @MainActor () async throws -> String,
        onRemoved: @MainActor () -> Void
    ) async -> Outcome {
        do {
            let notice = try await remove()
            onRemoved()
            return .removed(notice)
        } catch AO3WorkWriteError.onlyCreator {
            return .onlyCreator(kind.onlyCreatorMessage)
        } catch {
            return .failed(UserFacingError.message(for: error))
        }
    }
}

/// Confirmation sheet for permanently orphaning a work, several works, or a
/// series on AO3 (`GET /orphans/new?…` → `POST /orphans`).
struct OrphanSheet: View {
    let target: AO3OrphanTarget
    var fallbackTitles: [String] = []
    let onOrphaned: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme

    @State private var form: AO3OrphanForm?
    @State private var loadError: String?
    @State private var isNotOwned = false
    @State private var isLoading = true
    @State private var reload = 0
    @State private var keepPseudCopy = false
    @State private var keepLocalCopy = true
    @State private var showFinalAlert = false
    @State private var isSubmitting = false
    @State private var submissionStatus: String?
    @State private var submissionError: String?

    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .footnote) private var bodySize: CGFloat = 13.5

    private var gutter: CGFloat { SubjectMetrics.accountGutter }
    private var palette: SubjectPalette { theme.scopePalette }

    private var isPlural: Bool {
        switch target {
        case .work: false
        case let .works(ids): ids.count != 1
        case .series: true
        }
    }

    private var displayTitles: [String] {
        if let titles = form?.titles, !titles.isEmpty { return titles }
        return fallbackTitles
    }

    private var primaryActionLabel: String {
        switch target {
        case .work:
            let title = displayTitles.first ?? "Work"
            return "Orphan \"\(title)\""
        case let .works(ids):
            if ids.count == 1, let title = displayTitles.first {
                return "Orphan \"\(title)\""
            }
            return "Orphan \(ids.count) Works"
        case .series:
            let title = displayTitles.first ?? "Series"
            return "Orphan \"\(title)\""
        }
    }

    private var finalAlertTitle: String {
        switch target {
        case .work:
            let title = displayTitles.first ?? "this work"
            return "Orphan \"\(title)\" permanently?"
        case let .works(ids):
            if ids.count == 1, let title = displayTitles.first {
                return "Orphan \"\(title)\" permanently?"
            }
            return "Orphan \(ids.count) works permanently?"
        case .series:
            let title = displayTitles.first ?? "this series"
            return "Orphan \"\(title)\" permanently?"
        }
    }

    private var keepCopyLabel: String {
        #if os(macOS)
        "Keep a copy on this Mac"
        #else
        "Keep a copy on this iPhone"
        #endif
    }

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView().accentFill()
                            Text("Loading orphan confirmation…")
                                .font(.footnote)
                                .foregroundStyle(.secondaryInk)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .subjectPanel()
                        .pageBodyRow(top: 16, gutter: gutter)
                    }
                } else if isNotOwned, let loadError {
                    Section {
                        notOwnedPanel(loadError)
                            .pageBodyRow(top: 16, gutter: gutter)
                    }
                } else if let loadError, form == nil {
                    Section {
                        loadErrorPanel(loadError)
                            .pageBodyRow(top: 16, gutter: gutter)
                    }
                } else if form != nil {
                    formSections
                }
            }
            .cardList()
            .environment(\.defaultMinListRowHeight, 0)
            .subjectScreenWash(title: "Orphan", palette: palette)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .disabled(isSubmitting)
                }
            }
            .task(id: "\(auth.sessionGeneration):\(reload)") {
                await loadForm()
            }
            .alert(finalAlertTitle, isPresented: $showFinalAlert) {
                Button("Orphan", role: .destructive) {
                    Task { await submitOrphan(confirmed: true) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    keepLocalCopy
                        ? "Kudos will save a copy on this device first, then permanently move "
                            + (isPlural ? "these to AO3's orphan_account." : "this work to AO3's orphan_account.")
                        : "This can't be undone. Nobody at AO3 can give "
                            + (isPlural ? "them back." : "it back.")
                )
            }
        }
        .presentationDragIndicator(.visible)
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }

    @ViewBuilder
    private var formSections: some View {
        Section {
            warningPanel
                .pageBodyRow(top: 12, gutter: gutter)
        }

        if !displayTitles.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(displayTitles.enumerated()), id: \.offset) { index, title in
                        if index > 0 { SubjectRowSeparator() }
                        Text(title)
                            .font(.system(size: titleSize, weight: .medium))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    }
                }
                .subjectPanel()
                .pageBodyRow(top: 8, gutter: gutter)
            } header: {
                SectionRuleHeader(title: titlesSectionTitle)
                    .pageBodyRow(top: 16, gutter: 0)
            }
        }

        Section {
            pseudPanel
                .disabled(isSubmitting)
                .pageBodyRow(top: 8, gutter: gutter)
        } header: {
            SectionRuleHeader(title: "Your pseud")
                .pageBodyRow(top: 16, gutter: 0)
        }

        Section {
            SubjectFormRow(label: keepCopyLabel, arrangement: .control) {
                Toggle(keepCopyLabel, isOn: $keepLocalCopy)
                    .labelsHidden()
                    .accentFill()
            }
            .subjectPanel()
            .disabled(isSubmitting)
            .pageBodyRow(top: 14, gutter: gutter)

            Text(
                "Downloads every work into your library before sending anything to AO3. "
                    + "If any copy fails, nothing is orphaned."
            )
            .font(.footnote)
            .foregroundStyle(.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .pageBodyRow(top: 8, gutter: gutter)
        }

        if let submissionStatus {
            Section {
                HStack(spacing: 10) {
                    ProgressView().accentFill()
                    Text(submissionStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .subjectPanel()
                .pageBodyRow(top: 12, gutter: gutter)
            }
        }

        if let submissionError {
            Section {
                Text(submissionError)
                    .font(.footnote)
                    .foregroundStyle(theme.appTheme.errorColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .subjectPanel()
                    .pageBodyRow(top: 12, gutter: gutter)
            }
        }

        Section {
            Button(role: .destructive) {
                showFinalAlert = true
            } label: {
                Text(primaryActionLabel)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                            .fill(Color.red)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
            .opacity(isSubmitting ? 0.5 : 1)
            .accessibilityLabel(primaryActionLabel)
            .pageBodyRow(top: 16, gutter: gutter)
        }
    }
}

private extension OrphanSheet {
    var titlesSectionTitle: String {
        switch target {
        case .work: "Work to orphan"
        case let .works(ids): ids.count == 1 ? "Work to orphan" : "Works to orphan"
        case .series: "Series to orphan"
        }
    }

    var warningPanel: some View {
        let shape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            Text("This can't be undone.")
                .font(.headline)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            Text(warningMiddleSentence)
                .font(.system(size: bodySize))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(warningFinalSentence)
                .font(.system(size: bodySize))
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(shape.fill(Color.red.opacity(0.08)))
        .overlay(shape.strokeBorder(Color.red.opacity(0.32), lineWidth: 0.5))
    }

    var warningMiddleSentence: String {
        switch target {
        case .work:
            "AO3 moves the work to its orphan_account and removes your name from the work, "
                + "its chapters, its series, and your replies to comments on it."
        case let .works(ids) where ids.count == 1:
            "AO3 moves the work to its orphan_account and removes your name from the work, "
                + "its chapters, its series, and your replies to comments on it."
        case .works:
            "AO3 moves these works to its orphan_account and removes your name from the works, "
                + "their chapters, their series, and your replies to comments on them."
        case .series:
            "AO3 moves this series and its works to its orphan_account and removes your name from "
                + "the series, its works and chapters, and your replies to comments on them."
        }
    }

    var warningFinalSentence: String {
        if isPlural {
            return "After that you can't edit or delete them, and nobody at AO3 can give them back."
        }
        return "After that you can't edit or delete it, and nobody at AO3 can give it back."
    }

    var pseudPanel: some View {
        VStack(spacing: 0) {
            pseudChoiceRow(
                label: "Take my pseud off as well",
                isSelected: !keepPseudCopy
            ) {
                keepPseudCopy = false
            }
            SubjectRowSeparator()
            pseudChoiceRow(
                label: "Leave a copy of my pseud on",
                isSelected: keepPseudCopy
            ) {
                keepPseudCopy = true
            }
        }
        .subjectPanel()
    }

    func pseudChoiceRow(
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        SubjectFormRow(label: label, action: action) {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.accentInk)
            }
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    func notOwnedPanel(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Can't orphan on AO3")
                .font(.headline)
                .foregroundStyle(.primary)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button("Close") { dismiss() }
                .buttonStyle(.kudosSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .subjectPanel()
    }

    func loadErrorPanel(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(theme.appTheme.errorColor)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try Again") { reload += 1 }
                .buttonStyle(.kudosSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .subjectPanel()
    }

    func loadForm() async {
        isLoading = true
        loadError = nil
        isNotOwned = false
        let generation = auth.sessionGeneration
        do {
            let loaded = try await auth.loadOrphanForm(target)
            guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
            form = loaded
        } catch AO3WorkWriteError.notOwned {
            guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
            isNotOwned = true
            loadError = AO3WorkWriteError.notOwned.localizedDescription
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
            loadError = UserFacingError.message(for: error)
        }
        isLoading = false
    }

    func submitOrphan(confirmed: Bool) async {
        guard !isSubmitting, let form else { return }
        isSubmitting = true
        submissionError = nil
        submissionStatus = keepLocalCopy ? "Saving a local copy first…" : "Orphaning on AO3…"
        let context = modelContext
        let authService = auth
        let outcome = await OrphanSubmissionFlow.run(
            target: target,
            keepPseudCopy: keepPseudCopy,
            keepLocalCopy: keepLocalCopy,
            confirmedFinalAlert: confirmed,
            form: form,
            resolveWorks: {
                try await OrphanSubmissionFlow.resolveCopyItems(for: target, form: form)
            },
            copyWork: { workID in
                try await OrphanSubmissionFlow.saveLocalCopy(workID: workID, in: context)
            },
            submitOrphan: { target, keepPseud, orphanForm in
                submissionStatus = "Orphaning on AO3…"
                return try await authService.orphan(
                    target, keepPseudCopy: keepPseud, form: orphanForm
                )
            }
        )
        isSubmitting = false
        submissionStatus = nil
        switch outcome {
        case .cancelled:
            break
        case let .copyFailed(workTitle, reason):
            submissionError = "Couldn't save a local copy of \"\(workTitle)\". "
                + "Nothing was orphaned. \(reason)"
        case .orphaned:
            onOrphaned("Orphaned.")
            dismiss()
        case let .failed(message):
            submissionError = message
        }
    }
}
