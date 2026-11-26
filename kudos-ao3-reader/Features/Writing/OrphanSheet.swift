import Foundation
import SwiftData
import SwiftUI

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
    @State private var submissionTask: Task<Void, Never>?
    @State private var submissionStatus: String?
    @State private var submissionError: String?
    @State private var ambiguousOutcomeMessage: String?

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
                    handleFinalAlertDecision(.confirmed)
                }
                Button("Cancel", role: .cancel) {
                    handleFinalAlertDecision(.cancelled)
                }
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
        .interactiveDismissDisabled(isSubmitting)
        .onDisappear {
            submissionTask?.cancel()
            submissionTask = nil
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

        if let ambiguousOutcomeMessage {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(ambiguousOutcomeMessage)
                        .font(.footnote)
                        .foregroundStyle(theme.appTheme.errorColor)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Dismiss") {
                        self.ambiguousOutcomeMessage = nil
                    }
                    .buttonStyle(.kudosSecondary)
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
            .disabled(isSubmitting || ambiguousOutcomeMessage != nil)
            .opacity(isSubmitting || ambiguousOutcomeMessage != nil ? 0.5 : 1)
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

    func handleFinalAlertDecision(_ decision: OrphanSubmissionFlow.FinalAlertDecision) {
        guard !isSubmitting, ambiguousOutcomeMessage == nil, let form else { return }
        submissionTask?.cancel()
        submissionTask = Task {
            await submitOrphan(decision: decision, form: form)
        }
    }

    func submitOrphan(
        decision: OrphanSubmissionFlow.FinalAlertDecision,
        form: AO3OrphanForm
    ) async {
        defer {
            isSubmitting = false
            submissionStatus = nil
            submissionTask = nil
        }
        if decision == .confirmed {
            isSubmitting = true
            submissionError = nil
            ambiguousOutcomeMessage = nil
            submissionStatus = keepLocalCopy ? "Saving a local copy first…" : "Orphaning on AO3…"
        }
        let context = modelContext
        let authService = auth
        let outcome = await OrphanSubmissionFlow.run(
            target: target,
            keepPseudCopy: keepPseudCopy,
            keepLocalCopy: keepLocalCopy,
            finalAlertDecision: decision,
            form: form,
            resolveWorks: {
                try await OrphanSubmissionFlow.resolveCopyItems(
                    for: target,
                    form: form,
                    auth: authService
                )
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
        switch outcome {
        case .cancelled:
            break
        case let .copyFailed(workTitle, reason):
            submissionError = "Couldn't save a local copy of \"\(workTitle)\". "
                + "Nothing was orphaned. \(reason)"
        case .orphaned:
            onOrphaned("Orphaned.")
            dismiss()
        case let .mayHaveGoneThrough(message):
            ambiguousOutcomeMessage = message
        case let .failed(message):
            submissionError = message
        }
    }
}
