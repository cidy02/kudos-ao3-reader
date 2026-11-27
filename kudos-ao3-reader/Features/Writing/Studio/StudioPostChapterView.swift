import SwiftUI

/// Streamlined sheet for posting a new or draft chapter to an already-posted AO3 work
/// (`Studio-Post-Chapter.dc.html`), opened from `ChapterEditorScreen`'s `••• → Post`.
///
/// Reuses `AO3AuthService.loadChapterForm`, `loadWorkForm`, `createChapter`,
/// `updateChapter`, `updateWorkTotals`, `previewChapter`, `WritingPreviewView`, and
/// `StudioWorkDetailsDestination`. Skips the board's "Remind me" toggle because Kudos
/// does not have a reminder scheduler yet.
struct StudioPostChapterSheet: View {
    let workID: Int
    let chapterID: Int?
    let workTitle: String
    @Binding var chapterTitle: String
    @Binding var summary: String
    @Binding var notesBefore: String
    @Binding var notesAfter: String
    @Binding var content: String
    var openTKCount: Int = 0
    var openNoteCount: Int = 0
    var onCompleted: (_ isDraft: Bool) -> Void = { _ in }

    @Environment(\.dismiss) var dismiss
    @Environment(AO3AuthService.self) var auth
    @Environment(ThemeManager.self) var theme
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    @State var chapterForm: AO3ChapterForm?
    @State var workForm: AO3WorkForm?
    @State var editingGeneration: Int?
    @State var isLoading = true
    @State var loadError: String?
    @State var reloadToken = 0

    @State var showingChapterCountEditor = false
    @State var showingEndNotesField = false
    @State var showingPublicationDateEditor = false
    @State var isLastChapter = false

    @State var isSubmitting = false
    @State var isPreviewing = false
    @State var preview: AO3PreviewHTML?
    @State var showingWorkDetails = false
    @State var showingPostConfirmation = false
    @State var errorMessage: String?
    @State var ambiguousOutcomeMessage: String?
    @State var chapterSavedTotalRetryPending = false
    @State var pendingTotalToRetry: Int?

    var appTheme: ReaderTheme { theme.appTheme }

    var warningAmber: Color {
        appTheme.isDarkFamily ? .subjectAmber : Color(red: 0.698, green: 0.369, blue: 0.0)
    }

    var paperBackground: Color {
        switch appTheme {
        case .light: Color(red: 0.984, green: 0.980, blue: 0.965)
        case .sepia, .dark, .oled: appTheme.cardSurface
        }
    }

    var paperBorder: Color {
        switch appTheme {
        case .light: Color(red: 0.898, green: 0.875, blue: 0.824)
        case .sepia: appTheme.cardBorder
        case .dark, .oled: appTheme.glassStroke(0.16)
        }
    }

    var checks: [StudioPostCheckItem] {
        guard let chapterForm else { return [] }
        return StudioPostChapterChecker.checks(
            chapterForm: chapterForm,
            workForm: workForm,
            openTKCount: openTKCount,
            openNoteCount: openNoteCount
        )
    }

    var resolvedPosition: Int {
        guard let chapterForm else { return 1 }
        return StudioPostChapterChecker.resolvedChapterPosition(
            chapterForm: chapterForm,
            workForm: workForm
        )
    }

    var resolvedPlannedTotal: Int? {
        guard let chapterForm else { return nil }
        if isLastChapter { return resolvedPosition }
        return StudioPostChapterChecker.resolvedPlannedTotal(
            chapterForm: chapterForm,
            workForm: workForm
        )
    }

    var resolvedWorkTitle: String {
        let fromForm = workForm?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fromForm.isEmpty { return fromForm }
        let fromProp = workTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return fromProp.isEmpty ? "Untitled" : fromProp
    }

    var postButtonTitle: String {
        "Post Chapter \(resolvedPosition)"
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let loadError, chapterForm == nil {
                    loadErrorView(loadError)
                } else if chapterForm != nil {
                    contentScrollView
                }
            }
            .background(appTheme.contentBackdrop.ignoresSafeArea())
            .navigationTitle("Post Chapter")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { sheetToolbar }
            .navigationDestination(isPresented: $showingWorkDetails) {
                StudioWorkDetailsDestination(workID: workID, workTitle: resolvedWorkTitle) {
                    Task { await reloadWorkFormOnly() }
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { preview != nil },
                set: { if !$0 { preview = nil } }
            )) {
                previewDestination
            }
            .task(id: "\(auth.sessionGeneration):\(reloadToken)") {
                await loadForms()
            }
            .alert("\(postButtonTitle)?", isPresented: $showingPostConfirmation) {
                Button(postButtonTitle) {
                    Task { await submit(.post) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Posting notifies your subscribers and can't be undone.")
            }
            .alert(
                "AO3 could not save the chapter",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .interactiveDismissDisabled(isSubmitting || isPreviewing)
        .presentationDragIndicator(.visible)
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 620)
        #endif
    }

    @ToolbarContentBuilder
    private var sheetToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", role: .cancel) { dismiss() }
                .disabled(isSubmitting || isPreviewing)
                .accessibilityLabel("Cancel")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Preview") { openPreview() }
                .disabled(
                    chapterForm == nil || isLoading || isSubmitting || isPreviewing
                        || ambiguousOutcomeMessage != nil
                )
                .accessibilityLabel("Preview chapter on AO3")
        }
    }

    @ViewBuilder
    private var previewDestination: some View {
        if let preview, let chapterForm {
            WritingPreviewView(
                preview: preview,
                subtitle: AddChapterView.subtitle(
                    workTitle: resolvedWorkTitle,
                    chapterTitle: chapterForm.title,
                    position: chapterForm.position
                ),
                postTitle: postButtonTitle,
                confirmation: (
                    "\(postButtonTitle)?",
                    "Posting notifies your subscribers and can't be undone."
                ),
                post: { try await postFromPreview() }
            )
        }
    }

    // MARK: - Top sections

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView("Preparing chapter for AO3…")
                .accentFill()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadErrorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't Load Chapter Form", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { reloadToken += 1 }
                .buttonStyle(.kudosPrimary)
            Button("Keep on \(ThisDevice.name)") { dismiss() }
                .buttonStyle(.kudosSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                chapterSummaryCard
                checksPanel
                chapterDetailsPanel
                if let ambiguousOutcomeMessage {
                    ambiguousOutcomeBanner(ambiguousOutcomeMessage)
                }
                actionButtonsSection
            }
            .padding(.horizontal, SubjectMetrics.gutter)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .disabled(isSubmitting || isPreviewing)
    }

    private var chapterSummaryCard: some View {
        let trimmedTitle = (chapterForm?.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let heading = trimmedTitle.isEmpty
            ? "Chapter \(resolvedPosition)"
            : "Chapter \(resolvedPosition) · \(trimmedTitle)"
        let wordCount = AO3WordCounter.count(chapterForm?.content ?? content)
        let meta = StudioPostChapterChecker.chapterMetaLine(
            wordCount: wordCount,
            position: resolvedPosition,
            plannedTotal: resolvedPlannedTotal
        )
        let shape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)

        return VStack(alignment: .leading, spacing: 4) {
            Text(resolvedWorkTitle)
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Text(heading)
                .font(.system(.title2, design: .serif).weight(.semibold))
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(meta)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(paperBackground, in: shape)
        .overlay(shape.strokeBorder(paperBorder, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }

    private var checksPanel: some View {
        let currentChecks = checks
        return VStack(spacing: 0) {
            ForEach(Array(currentChecks.enumerated()), id: \.element.id) { index, check in
                if index > 0 { SubjectRowSeparator(inset: 48) }
                checkRow(check)
            }
        }
        .subjectPanel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Checks before posting")
    }

    @ViewBuilder
    private func checkRow(_ check: StudioPostCheckItem) -> some View {
        let textColumn = VStack(alignment: .leading, spacing: 2) {
            Text(check.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(check.detail)
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        checkStatusBadge(check.status)
                        textColumn
                    }
                    if let actionTitle = check.actionTitle {
                        checkActionButton(for: check, title: actionTitle)
                            .padding(.leading, 34)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    checkStatusBadge(check.status)
                    textColumn
                    if let actionTitle = check.actionTitle {
                        checkActionButton(for: check, title: actionTitle)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .contain)
    }

    private func checkStatusBadge(_ status: StudioPostCheckStatus) -> some View {
        let fill: Color
        let symbol: String
        let spoken: String
        switch status {
        case .pass:
            fill = appTheme.statusSuccessColor
            symbol = "checkmark"
            spoken = "Passed"
        case .warning:
            fill = warningAmber
            symbol = "exclamationmark"
            spoken = "Check"
        case .fail:
            fill = appTheme.errorColor
            symbol = "xmark"
            spoken = "Needs fix"
        }
        return Image(systemName: symbol)
            .font(.caption.weight(.heavy))
            .foregroundStyle(Color.white)
            .frame(width: 22, height: 22)
            .background(fill, in: Circle())
            .accessibilityLabel(spoken)
    }

    private func checkActionButton(for check: StudioPostCheckItem, title: String) -> some View {
        Button(title) {
            switch check.id {
            case .workDetails:
                showingWorkDetails = true
            case .chapterCount:
                showingChapterCountEditor.toggle()
            case .textReady, .comments:
                break
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(theme.accentInk)
        .buttonStyle(.plain)
        .minimumHitTarget(36)
        .accessibilityLabel("\(title) \(check.title)")
    }
}
