import SwiftUI
import UniformTypeIdentifiers

// MARK: - ChapterEditorScreen integration

extension ChapterEditorScreen {
    var betaReadingSheetView: some View {
        BetaReadingSheet(
            workTitle: resolvedWorkTitle,
            chapterNumber: resolvedChapterNumber,
            chapterTitle: chapterDisplayTitle,
            authorName: account,
            documentBridge: documentBridge,
            session: session,
            fallbackContent: { content },
            ensureDocumentOpen: { await openDocumentBridge() },
            commitAndPersistHTML: { await commitAndPersist(kind: .edit) },
            onAnnotationsChanged: {
                scheduleAnnotationSync(useCurrentHTML: true)
            }
        )
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Beta Reading sheet (`Editor-Beta.dc.html`)

struct BetaReadingSheet: View {
    let workTitle: String
    let chapterNumber: Int?
    let chapterTitle: String
    let authorName: String
    let documentBridge: ChapterEditorDocumentBridge
    let session: DraftSession?
    let fallbackContent: () -> String
    let ensureDocumentOpen: () async -> Void
    let commitAndPersistHTML: () async -> String
    let onAnnotationsChanged: () -> Void

    @Environment(\.dismiss) var dismiss
    @Environment(ThemeManager.self) var themeManager: ThemeManager?
    @Environment(\.accentFill) var envAccentFill
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    @State var copies: [BetaCopyRecord] = []
    @State var recentNames: [String] = []
    @State var selectedCopyID: UUID?
    @State var activeModal: ActiveModal?
    @State var pendingSendAfterDismiss: PendingSendRequest?
    @State var isImportingDOCX = false
    @State var importingForCopyID: UUID?
    @State var showingReviewAllDialog = false
    @State var pendingBulkAction: BulkReviewAction?
    @State var isWorking = false
    @State var copiedSuggestionID: UUID?
    @State var copiedResetTask: Task<Void, Never>?
    @State var bulkStatusMessage: String?
    @State var errorMessage: String?

    #if os(macOS)
    @State var isExportingOnMac = false
    @State var macExportDocument = BetaExportFileDocument(data: Data())
    @State var macExportFilename = "Chapter.docx"
    #endif

    init(
        workTitle: String,
        chapterNumber: Int?,
        chapterTitle: String,
        authorName: String,
        documentBridge: ChapterEditorDocumentBridge,
        session: DraftSession?,
        fallbackContent: @escaping () -> String,
        ensureDocumentOpen: @escaping () async -> Void,
        commitAndPersistHTML: @escaping () async -> String,
        onAnnotationsChanged: @escaping () -> Void
    ) {
        self.workTitle = workTitle
        self.chapterNumber = chapterNumber
        self.chapterTitle = chapterTitle
        self.authorName = authorName
        self.documentBridge = documentBridge
        self.session = session
        self.fallbackContent = fallbackContent
        self.ensureDocumentOpen = ensureDocumentOpen
        self.commitAndPersistHTML = commitAndPersistHTML
        self.onAnnotationsChanged = onAnnotationsChanged
    }

    struct PendingSendRequest {
        let betaName: String
        let format: BetaCopyFormat
    }

    enum ActiveModal: Identifiable {
        case namePrompt(BetaCopyFormat)
        #if os(iOS)
        case share(BetaShareFileItem)
        #endif

        var id: String {
            switch self {
            case let .namePrompt(format): "name-\(format.rawValue)"
            #if os(iOS)
            case let .share(item): "share-\(item.id.uuidString)"
            #endif
            }
        }
    }

    enum BulkReviewAction: Identifiable {
        case acceptAll(copyID: UUID, count: Int, skippedPasteCount: Int)
        case rejectAll(copyID: UUID, count: Int)
        case resolveAllComments(copyID: UUID, count: Int)

        var id: String {
            switch self {
            case let .acceptAll(copyID, _, _): "accept-\(copyID.uuidString)"
            case let .rejectAll(copyID, _): "reject-\(copyID.uuidString)"
            case let .resolveAllComments(copyID, _): "comments-\(copyID.uuidString)"
            }
        }

        var alertTitle: String {
            switch self {
            case let .acceptAll(_, count, _):
                "Accept all \(count) \(count == 1 ? "suggestion" : "suggestions")?"
            case let .rejectAll(_, count):
                "Reject all \(count) \(count == 1 ? "suggestion" : "suggestions")?"
            case let .resolveAllComments(_, count):
                "Mark all \(count) \(count == 1 ? "comment" : "comments") done?"
            }
        }

        var alertMessage: String {
            switch self {
            case let .acceptAll(_, _, skippedPasteCount):
                if skippedPasteCount > 0 {
                    let pasteNote = skippedPasteCount == 1
                        ? "1 added paragraph needs pasting by hand and will be skipped."
                        : "\(skippedPasteCount) added paragraphs need pasting by hand and will be skipped."
                    return "Kudos saves a version of the chapter first. \(pasteNote) "
                        + "Any other suggestion that can’t be placed will stay on screen so you can copy it."
                }
                return "Kudos saves a version of the chapter first. Any suggestion that can’t be placed "
                    + "will stay on screen so you can copy it."
            case .rejectAll:
                "All remaining suggestions from this beta will be marked rejected. "
                    + "Your chapter text stays unchanged."
            case .resolveAllComments:
                "This marks all remaining comments from this beta as resolved in your chapter notes."
            }
        }

        var confirmLabel: String {
            switch self {
            case .acceptAll: "Accept All"
            case .rejectAll: "Reject All"
            case .resolveAllComments: "Mark Done"
            }
        }

        var isDestructive: Bool {
            if case .rejectAll = self { return true }
            return false
        }
    }

    var appTheme: ReaderTheme { themeManager?.appTheme ?? .light }
    var effectiveTint: Color { themeManager?.effectiveTint ?? envAccentFill }
    var accentInk: Color { themeManager?.accentInk ?? effectiveTint }

    var chapterSubtitle: String {
        let trimmedTitle = chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = trimmedTitle.isEmpty ? "Untitled" : trimmedTitle
        if let chapterNumber, chapterNumber > 0 {
            return "Chapter \(chapterNumber) · \(displayTitle)"
        }
        return displayTitle
    }

    var selectedReturnedCopy: BetaCopyRecord? {
        if let selectedCopyID,
           let matched = copies.first(where: { $0.id == selectedCopyID && $0.returnedAt != nil }) {
            return matched
        }
        return copies.first { $0.status == .cameBack }
            ?? copies.first { $0.returnedAt != nil }
    }

    var body: some View {
        NavigationStack {
            withPresentations(
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerBlock
                        sendCopySection
                        if !copies.isEmpty {
                            withYourBetasSection
                        }
                        if let activeCopy = selectedReturnedCopy {
                            reviewSection(for: activeCopy)
                        } else {
                            footerPromiseText
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, SubjectMetrics.gutter)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .background(appTheme.cardBackdrop.ignoresSafeArea())
                .navigationTitle("Beta Reading")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityLabel("Done")
                    }
                }
                .task {
                    await loadBetaData()
                }
                .onDisappear {
                    copiedResetTask?.cancel()
                }
            )
        }
    }

    private func withPresentations<Content: View>(_ content: Content) -> some View {
        content
            .sheet(
                item: $activeModal,
                onDismiss: {
                    if let queued = pendingSendAfterDismiss {
                        pendingSendAfterDismiss = nil
                        Task { await sendCopy(to: queued.betaName, format: queued.format) }
                    }
                }
            ) { modal in
                modalSheetView(for: modal)
            }
            .fileImporter(
                isPresented: $isImportingDOCX,
                allowedContentTypes: [BetaDOCXContentType.docx],
                allowsMultipleSelection: false
            ) { result in
                handleDOCXImportResult(result)
            }
            #if os(macOS)
            .fileExporter(
                isPresented: $isExportingOnMac,
                document: macExportDocument,
                contentType: BetaDOCXContentType.docx,
                defaultFilename: macExportFilename
            ) { result in
                if case let .failure(error) = result {
                    errorMessage = UserFacingError.message(for: error)
                }
            }
            #endif
            .confirmationDialog(
                "Review All",
                isPresented: $showingReviewAllDialog,
                titleVisibility: .visible
            ) {
                reviewAllDialogActions
            }
            .alert(
                pendingBulkAction?.alertTitle ?? "",
                isPresented: Binding(
                    get: { pendingBulkAction != nil },
                    set: { if !$0 { pendingBulkAction = nil } }
                ),
                presenting: pendingBulkAction
            ) { action in
                Button(action.confirmLabel, role: action.isDestructive ? .destructive : nil) {
                    pendingBulkAction = nil
                    Task { await performBulkAction(action) }
                }
                Button("Cancel", role: .cancel) {
                    pendingBulkAction = nil
                }
            } message: { action in
                Text(action.alertMessage)
            }
            .alert(
                "Beta Reading Error",
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

    @ViewBuilder
    private func modalSheetView(for modal: ActiveModal) -> some View {
        switch modal {
        case let .namePrompt(format):
            BetaNamePromptSheet(
                format: format,
                recentNames: recentNames,
                onSend: { betaName in
                    pendingSendAfterDismiss = PendingSendRequest(
                        betaName: betaName,
                        format: format
                    )
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        #if os(iOS)
        case let .share(item):
            BetaShareActivitySheet(url: item.url) {
                BetaShareFileItem.cleanUp(item.url)
            }
        #endif
        }
    }

    @ViewBuilder
    private var reviewAllDialogActions: some View {
        if let activeCopy = selectedReturnedCopy {
            let acceptableCount = activeCopy.acceptablePendingSuggestions.count
            let pasteOnlyCount = activeCopy.pasteOnlyPendingSuggestions.count
            let pendingCount = activeCopy.pendingSuggestions.count
            if acceptableCount > 0 {
                Button("Accept All Suggestions (\(acceptableCount))") {
                    pendingBulkAction = .acceptAll(
                        copyID: activeCopy.id,
                        count: acceptableCount,
                        skippedPasteCount: pasteOnlyCount
                    )
                }
            }
            if pendingCount > 0 {
                Button("Reject All Suggestions (\(pendingCount))", role: .destructive) {
                    pendingBulkAction = .rejectAll(copyID: activeCopy.id, count: pendingCount)
                }
            }
            let openComments = activeCopy.openComments.count
            if openComments > 0 {
                Button("Mark All Comments Done (\(openComments))") {
                    pendingBulkAction = .resolveAllComments(copyID: activeCopy.id, count: openComments)
                }
            }
        }
        Button("Cancel", role: .cancel) {}
    }
}

// MARK: - Sections

extension BetaReadingSheet {
    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(chapterSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sendCopySection: some View {
        let formats = BetaCopyFormat.availableSendFormats
        let shape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Send a copy")
            VStack(spacing: 0) {
                ForEach(Array(formats.enumerated()), id: \.element.id) { index, format in
                    if index > 0 {
                        rowDivider
                    }
                    Button {
                        activeModal = .namePrompt(format)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(format.rowTitle)
                                    .font(.body)
                                    .foregroundStyle(Color.primary)
                                    .multilineTextAlignment(.leading)
                                Text(format.rowDetail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondaryInk)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "square.and.arrow.up")
                                .font(.body)
                                .foregroundStyle(accentInk)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                    .accessibilityLabel("Send as \(format.rowTitle). \(format.rowDetail)")
                }
            }
            .background(appTheme.cardSurface, in: shape)
            .overlay(shape.strokeBorder(appTheme.cardBorder, lineWidth: 0.5))

            Text("Each beta gets their own copy, so their notes don’t sway each other.")
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
                .padding(.horizontal, 16)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var withYourBetasSection: some View {
        let shape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            sectionHeader("With your betas")
            VStack(spacing: 0) {
                ForEach(Array(copies.enumerated()), id: \.element.id) { index, copy in
                    if index > 0 {
                        rowDivider
                    }
                    betaCopyRow(copy)
                }
            }
            .background(appTheme.cardSurface, in: shape)
            .overlay(shape.strokeBorder(appTheme.cardBorder, lineWidth: 0.5))
        }
    }

    private func betaCopyRow(_ copy: BetaCopyRecord) -> some View {
        let isSelected = selectedReturnedCopy?.id == copy.id && copy.returnedAt != nil
        let dateText = ChapterEditorAnnotationListBuilder.shortDateString(copy.sentAt)
        let detail = "\(copy.format.sentDetailLabel) · sent \(dateText)"
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                handleCopyRowTap(copy)
            } label: {
                betaCopyRowHeader(copy: copy, detail: detail)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(copy.betaName), \(detail), \(copy.status.chipTitle)")

            if copy.status == .waiting, copy.format.supportsReturnImport {
                Button {
                    beginImport(for: copy)
                } label: {
                    Label("Bring Back Their Copy", systemImage: "square.and.arrow.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(accentInk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(minHeight: 34)
                        .background(
                            effectiveTint.opacity(appTheme.isDarkFamily ? 0.22 : 0.10),
                            in: SubjectMetrics.controlShape(dynamicTypeSize)
                        )
                        .contentShape(SubjectMetrics.controlShape(dynamicTypeSize))
                }
                .buttonStyle(.plain)
                .minimumHitTarget(44)
                .disabled(isWorking)
                .accessibilityLabel("Bring back \(copy.betaName)’s Word document")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? effectiveTint.opacity(appTheme.isDarkFamily ? 0.14 : 0.06) : Color.clear)
        .contextMenu {
            if copy.format.supportsReturnImport {
                Button {
                    beginImport(for: copy)
                } label: {
                    Label(
                        copy.returnedAt == nil ? "Bring Back Copy" : "Bring Back Updated Copy",
                        systemImage: "square.and.arrow.down"
                    )
                }
            }
            if copy.status == .waiting, !copy.format.supportsReturnImport {
                Button {
                    Task { await markPDFCopyReviewed(copy) }
                } label: {
                    Label("Mark Reviewed", systemImage: "checkmark.circle")
                }
            }
            Button(role: .destructive) {
                Task { await deleteCopy(copy) }
            } label: {
                Label("Remove Copy", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func betaCopyRowHeader(copy: BetaCopyRecord, detail: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                Text(copy.betaName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.primary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                BetaCopyStatusChip(status: copy.status)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        } else {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(copy.betaName)
                        .font(.body)
                        .foregroundStyle(Color.primary)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                BetaCopyStatusChip(status: copy.status)
            }
            .contentShape(Rectangle())
        }
    }

    private func reviewSection(for copy: BetaCopyRecord) -> some View {
        let cards = copy.orderedReviewCards
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader(copy.reviewSectionTitle)

            if let bulkStatusMessage {
                bulkStatusBanner(bulkStatusMessage)
            }

            if cards.isEmpty {
                let shape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                Text("\(copy.betaName)’s copy matched what you sent, with no suggestions or comments.")
                    .font(.subheadline)
                    .foregroundStyle(.secondaryInk)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(appTheme.cardSurface, in: shape)
                    .overlay(shape.strokeBorder(appTheme.cardBorder, lineWidth: 0.5))
            } else {
                ForEach(cards) { card in
                    switch card {
                    case let .suggestion(suggestion):
                        BetaSuggestionCardView(
                            suggestion: suggestion,
                            isBusy: isWorking,
                            wasCopied: copiedSuggestionID == suggestion.id,
                            onAccept: {
                                Task { await acceptSuggestion(suggestion, in: copy.id) }
                            },
                            onReject: {
                                Task { await setSuggestionState(.rejected, id: suggestion.id, in: copy.id) }
                            },
                            onCopy: {
                                copyToClipboard(suggestion.copyableText, suggestionID: suggestion.id)
                            },
                            onDismissUnplaceable: {
                                Task { await setSuggestionState(.dismissed, id: suggestion.id, in: copy.id) }
                            }
                        )
                    case let .comment(comment):
                        BetaCommentCardView(
                            comment: comment,
                            isBusy: isWorking,
                            onMarkDone: {
                                Task { await markCommentDone(comment, in: copy.id) }
                            }
                        )
                    }
                }
            }

            if copy.remainingCount > 0 {
                Button {
                    showingReviewAllDialog = true
                } label: {
                    Text("Review All \(copy.remainingCount)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.kudosPrimaryConfirm)
                .disabled(isWorking)
                .accessibilityLabel("Review all \(copy.remainingCount) remaining items from \(copy.betaName)")
                .padding(.top, 6)
            }

            footerPromiseText
        }
    }

    private func bulkStatusBanner(_ message: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.footnote)
                .foregroundStyle(accentInk)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                bulkStatusMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondaryInk)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .minimumHitTarget(44)
            .accessibilityLabel("Dismiss notice")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(appTheme.cardSurface, in: shape)
        .overlay(shape.strokeBorder(appTheme.cardBorder, lineWidth: 0.5))
    }

    private var footerPromiseText: some View {
        Text(
            "Kudos saves a version of the chapter before anything comes in. "
                + "Nothing changes until you accept it."
        )
        .font(.footnote)
        .foregroundStyle(.secondaryInk)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote)
            .textCase(.uppercase)
            .foregroundStyle(.secondaryInk)
            .padding(.leading, 16)
            .accessibilityAddTraits(.isHeader)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(appTheme.appSeparator ?? appTheme.glassStroke(0.10))
            .frame(height: 0.5)
            .padding(.leading, 14)
            .accessibilityHidden(true)
    }
}
