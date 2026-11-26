import Foundation
import SwiftUI

/// Everything on AO3 waiting for the signed-in creator's answer: co-creator
/// invitations, works that link to yours, gifts to you, and collection
/// invitations. Loads sequentially when opened and on pull to refresh; cancels
/// when dismissed.
struct WritingRequestsView: View {
    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var model = WritingRequestsModel()
    @State private var pendingRemoveMyLink: AO3RelatedWorkRow?

    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .footnote) private var subtitleSize: CGFloat = 13

    private var gutter: CGFloat { SubjectMetrics.accountGutter }
    private var palette: SubjectPalette { theme.scopePalette }
    private var service: WritingRequestsModel.Service { .live(auth: auth) }

    var body: some View {
        List {
            if let status = model.statusMessage {
                Section {
                    WritingRequestFeedbackBanner(message: status, isError: false) {
                        model.statusMessage = nil
                    }
                    .pageBodyRow(top: 12, gutter: gutter)
                }
            }
            if let error = model.actionError {
                Section {
                    WritingRequestFeedbackBanner(message: error, isError: true) {
                        model.actionError = nil
                    }
                    .pageBodyRow(top: 12, gutter: gutter)
                }
            }

            if !auth.isLoggedIn {
                Section {
                    WritingRequestEmptyPanel(message: "Log in to AO3 to view and answer requests.")
                        .pageBodyRow(top: 14, gutter: gutter)
                }
            } else {
                coCreatorsSection
                relatedWorksSection
                giftsSection
                collectionInvitationsSection
            }
        }
        .cardList()
        .environment(\.defaultMinListRowHeight, 0)
        .subjectScreenWash(title: "Requests", palette: palette)
        .task(id: "\(auth.sessionGeneration):\(auth.isLoggedIn)") {
            guard auth.isLoggedIn else { return }
            if model.boundSessionGeneration != auth.sessionGeneration {
                model.resetForSession(auth.sessionGeneration)
                await model.loadAll(using: service)
            }
        }
        .refreshable {
            guard auth.isLoggedIn else { return }
            model.statusMessage = nil
            model.actionError = nil
            await model.loadAll(using: service)
        }
        .alert(
            "Remove link?",
            isPresented: Binding(
                get: { pendingRemoveMyLink != nil },
                set: { if !$0 { pendingRemoveMyLink = nil } }
            )
        ) {
            Button("Remove Link", role: .destructive) {
                guard let row = pendingRemoveMyLink else { return }
                pendingRemoveMyLink = nil
                Task { await model.removeMyRelatedWork(row, using: service) }
            }
            Button("Cancel", role: .cancel) { pendingRemoveMyLink = nil }
        } message: {
            if let row = pendingRemoveMyLink {
                Text(
                    "Remove the link from \"\(row.childWork.title)\" to \"\(row.parentWork.title)\"? "
                        + "Neither work is deleted."
                )
            }
        }
    }

    // MARK: - 1. Co-creator invitations

    @ViewBuilder
    private var coCreatorsSection: some View {
        Section {
            if model.isSelectingCoCreators, !model.coCreatorRequests.isEmpty {
                coCreatorSelectionBar
                    .pageBodyRow(top: 10, gutter: gutter)
            }
            switch model.coCreatorsPhase {
            case .idle, .loading where model.coCreatorRequests.isEmpty:
                WritingRequestLoadingPanel(title: "Loading co-creator requests…")
                    .pageBodyRow(top: 10, gutter: gutter)
            case let .failed(message) where model.coCreatorRequests.isEmpty:
                WritingRequestErrorPanel(message: message) {
                    Task { await model.loadCoCreators(page: 1, append: false, using: service) }
                }
                .pageBodyRow(top: 10, gutter: gutter)
            default:
                if model.coCreatorRequests.isEmpty {
                    WritingRequestEmptyPanel(message: "No co-creator requests")
                        .pageBodyRow(top: 10, gutter: gutter)
                } else {
                    coCreatorRowsPanel
                        .pageBodyRow(top: 10, gutter: gutter)
                    if model.hasMoreCoCreators {
                        WritingRequestLoadMoreButton(
                            title: "Load More Co-Creator Requests",
                            isLoading: model.isLoadingMoreCoCreators
                        ) {
                            Task {
                                await model.loadCoCreators(
                                    page: model.coCreatorsCurrentPage + 1,
                                    append: true,
                                    using: service
                                )
                            }
                        }
                        .pageBodyRow(top: 8, gutter: gutter)
                    }
                }
            }
        } header: {
            SectionRuleHeader(
                title: "Co-creator invitations",
                count: model.coCreatorRequests.isEmpty ? nil : model.coCreatorRequests.count,
                actionTitle: model.coCreatorRequests.isEmpty
                    ? nil
                    : (model.isSelectingCoCreators ? "Done" : "Select"),
                onSeeAll: model.coCreatorRequests.isEmpty ? nil : {
                    model.isSelectingCoCreators.toggle()
                    if !model.isSelectingCoCreators { model.clearCoCreatorSelection() }
                }
            )
            .pageBodyRow(top: 16, gutter: 0)
        }
    }

    private var coCreatorSelectionBar: some View {
        let count = model.selectedCoCreatorIDs.count
        let allSelected = count == model.coCreatorRequests.count && !model.coCreatorRequests.isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button(allSelected ? "Select None" : "Select All") {
                    if allSelected {
                        model.clearCoCreatorSelection()
                    } else {
                        model.selectAllCoCreators()
                    }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(theme.accentInk)
                .buttonStyle(.plain)
                Spacer(minLength: 8)
                Text("\(count) selected")
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .monospacedDigit()
            }
            actionPair {
                Button("Accept (\(count))") {
                    let ids = model.coCreatorRequests
                        .map(\.id)
                        .filter { model.selectedCoCreatorIDs.contains($0) }
                    Task { await model.answerCoCreators(ids: ids, accept: true, using: service) }
                }
                .buttonStyle(.kudosPrimary)
                .disabled(model.selectedCoCreatorIDs.isEmpty || model.isSubmitting)
                .accessibilityLabel("Accept \(count) selected co-creator requests")

                Button("Decline (\(count))", role: .destructive) {
                    let ids = model.coCreatorRequests
                        .map(\.id)
                        .filter { model.selectedCoCreatorIDs.contains($0) }
                    Task { await model.answerCoCreators(ids: ids, accept: false, using: service) }
                }
                .buttonStyle(.kudosSecondary)
                .tint(.red)
                .disabled(model.selectedCoCreatorIDs.isEmpty || model.isSubmitting)
                .accessibilityLabel("Decline \(count) selected co-creator requests")
            }
        }
        .padding(14)
        .subjectPanel()
    }

    private var coCreatorRowsPanel: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.coCreatorRequests.enumerated()), id: \.element.id) { index, request in
                if index > 0 { SubjectRowSeparator() }
                coCreatorRow(request)
            }
        }
        .subjectPanel()
    }

    // MARK: - 2. Works that link to yours

    @ViewBuilder
    private var relatedWorksSection: some View {
        Section {
            switch model.relatedWorksPhase {
            case .idle, .loading where model.relatedWorks == nil:
                WritingRequestLoadingPanel(title: "Loading related works…")
                    .pageBodyRow(top: 10, gutter: gutter)
            case let .failed(message) where model.relatedWorks == nil:
                WritingRequestErrorPanel(message: message) {
                    Task { await model.loadRelatedWorks(using: service) }
                }
                .pageBodyRow(top: 10, gutter: gutter)
            default:
                if let page = model.relatedWorks, model.totalRelatedWorksCount > 0 {
                    relatedWorksPanel(page)
                        .pageBodyRow(top: 10, gutter: gutter)
                } else {
                    WritingRequestEmptyPanel(message: "No related works")
                        .pageBodyRow(top: 10, gutter: gutter)
                }
            }
        } header: {
            SectionRuleHeader(
                title: "Works that link to yours",
                count: model.totalRelatedWorksCount > 0 ? model.totalRelatedWorksCount : nil
            )
            .pageBodyRow(top: 18, gutter: 0)
        }
    }

    // MARK: - 3. Gifts to you

    @ViewBuilder
    private var giftsSection: some View {
        Section {
            switch model.giftsPhase {
            case .idle, .loading where model.acceptedGifts.isEmpty:
                WritingRequestLoadingPanel(title: "Loading gifts…")
                    .pageBodyRow(top: 10, gutter: gutter)
            case let .failed(message) where model.acceptedGifts.isEmpty:
                WritingRequestErrorPanel(message: message) {
                    Task { await model.loadGifts(page: 1, append: false, using: service) }
                }
                .pageBodyRow(top: 10, gutter: gutter)
            default:
                if model.acceptedGifts.isEmpty {
                    WritingRequestEmptyPanel(message: "No accepted gifts")
                        .pageBodyRow(top: 10, gutter: gutter)
                } else {
                    VStack(spacing: 0) {
                        ForEach(
                            Array(model.acceptedGifts.enumerated()),
                            id: \.element.id
                        ) { index, gift in
                            if index > 0 { SubjectRowSeparator() }
                            WritingRequestGiftRow(
                                gift: gift,
                                refuseAction: true,
                                isSubmitting: model.isSubmitting
                            ) {
                                Task { await model.setGiftRefused(gift, refused: true, using: service) }
                            }
                        }
                    }
                    .subjectPanel()
                    .pageBodyRow(top: 10, gutter: gutter)

                    if model.hasMoreGifts {
                        WritingRequestLoadMoreButton(
                            title: "Load More Gifts",
                            isLoading: model.isLoadingMoreGifts
                        ) {
                            Task {
                                await model.loadGifts(
                                    page: model.giftsCurrentPage + 1,
                                    append: true,
                                    using: service
                                )
                            }
                        }
                        .pageBodyRow(top: 8, gutter: gutter)
                    }
                }
            }
            SubjectFormRow(label: "Refused Gifts", value: "", showsDisclosure: true)
                .subjectRowNavigation(accessibilityLabel: "Refused gifts") {
                    WritingRefusedGiftsView(model: model)
                }
                .subjectPanel()
                .pageBodyRow(top: 10, gutter: gutter)
        } header: {
            SectionRuleHeader(
                title: "Gifts to you",
                count: model.acceptedGifts.isEmpty ? nil : model.acceptedGifts.count
            )
            .pageBodyRow(top: 18, gutter: 0)
        }
    }

    // MARK: - 4. Collection invitations

    private var collectionInvitationsSection: some View {
        Section {
            SubjectFormRow(label: "Collection Invitations", value: "", showsDisclosure: true)
                .subjectRowNavigation(accessibilityLabel: "Collection invitations") {
                    AO3CollectionItemsView(slug: nil, title: "Collection Invitations")
                }
                .subjectPanel()
                .pageBodyRow(top: 10, gutter: gutter)
        } header: {
            SectionRuleHeader(title: "Collection invitations")
                .pageBodyRow(top: 18, gutter: 0)
        }
    }
}

private extension WritingRequestsView {
    struct RelatedWorkEntry: Identifiable {
        let row: AO3RelatedWorkRow
        let heading: String
        let detail: String
        var id: String { "\(row.id)-\(heading)" }
    }

    @ViewBuilder
    func coCreatorRow(_ request: AO3CoCreatorRequest) -> some View {
        let meta = [request.creationType, request.invitedPseud, request.dateText]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " · ")
        if model.isSelectingCoCreators {
            let isSelected = model.selectedCoCreatorIDs.contains(request.id)
            Button {
                model.toggleCoCreatorSelection(request.id)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? theme.accentInk : .secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(request.title)
                            .font(.system(size: titleSize, weight: .semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !meta.isEmpty {
                            Text(meta)
                                .font(.system(size: subtitleSize))
                                .foregroundStyle(.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(request.title), \(meta)")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.title)
                        .font(.system(size: titleSize, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !meta.isEmpty {
                        Text(meta)
                            .font(.system(size: subtitleSize))
                            .foregroundStyle(.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                actionPair {
                    Button("Accept") {
                        Task {
                            await model.answerCoCreators(ids: [request.id], accept: true, using: service)
                        }
                    }
                    .buttonStyle(.kudosPrimary)
                    .disabled(model.isSubmitting)
                    .accessibilityLabel("Accept co-creator invitation for \(request.title)")

                    Button("Decline", role: .destructive) {
                        Task {
                            await model.answerCoCreators(ids: [request.id], accept: false, using: service)
                        }
                    }
                    .buttonStyle(.kudosSecondary)
                    .tint(.red)
                    .disabled(model.isSubmitting)
                    .accessibilityLabel("Decline co-creator invitation for \(request.title)")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    func relatedWorksPanel(_ page: AO3RelatedWorksPage) -> some View {
        let entries = relatedWorkEntries(from: page)
        return VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { SubjectRowSeparator() }
                relatedWorkRow(entry)
            }
        }
        .subjectPanel()
    }

    func relatedWorkEntries(from page: AO3RelatedWorksPage) -> [RelatedWorkEntry] {
        var entries: [RelatedWorkEntry] = []
        for row in page.translationsOfMe {
            let langs = languageSummary(from: row.fromLanguage, to: row.toLanguage)
            let byline = creatorSuffix(row.childWork.creators)
            let parts = ["Translation of \"\(row.parentWork.title)\"", langs, byline].compactMap { $0 }
            entries.append(RelatedWorkEntry(
                row: row,
                heading: displayWorkTitle(row.childWork),
                detail: parts.joined(separator: " · ")
            ))
        }
        for row in page.inspiredByMe {
            let byline = creatorSuffix(row.childWork.creators)
            let parts = ["Inspired by \"\(row.parentWork.title)\"", byline].compactMap { $0 }
            entries.append(RelatedWorkEntry(
                row: row,
                heading: displayWorkTitle(row.childWork),
                detail: parts.joined(separator: " · ")
            ))
        }
        for row in page.translationsByMe {
            let langs = languageSummary(from: row.fromLanguage, to: row.toLanguage)
            let byline = creatorSuffix(row.parentWork.creators)
            let parts = ["Your translation of \"\(row.parentWork.title)\"", langs, byline].compactMap { $0 }
            entries.append(RelatedWorkEntry(
                row: row,
                heading: displayWorkTitle(row.childWork),
                detail: parts.joined(separator: " · ")
            ))
        }
        for row in page.thatInspiredMe {
            let byline = creatorSuffix(row.parentWork.creators)
            let parts = ["Inspired by \"\(row.parentWork.title)\"", byline].compactMap { $0 }
            entries.append(RelatedWorkEntry(
                row: row,
                heading: displayWorkTitle(row.childWork),
                detail: parts.joined(separator: " · ")
            ))
        }
        return entries
    }

    func relatedWorkRow(_ entry: RelatedWorkEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.heading)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.detail)
                    .font(.system(size: subtitleSize))
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            switch entry.row.action {
            case let .toggleReciprocal(isApproved):
                if isApproved {
                    Button("Remove Link", role: .destructive) {
                        Task {
                            await model.setRelatedWorkApproved(entry.row, approved: false, using: service)
                        }
                    }
                    .buttonStyle(.kudosSecondary)
                    .tint(.red)
                    .disabled(model.isSubmitting)
                    .accessibilityLabel("Remove link to \(entry.heading)")
                } else {
                    Button("Approve Link") {
                        Task {
                            await model.setRelatedWorkApproved(entry.row, approved: true, using: service)
                        }
                    }
                    .buttonStyle(.kudosPrimary)
                    .disabled(model.isSubmitting)
                    .accessibilityLabel("Approve link to \(entry.heading)")
                }
            case .removeLink:
                Button("Remove Link", role: .destructive) {
                    pendingRemoveMyLink = entry.row
                }
                .buttonStyle(.kudosSecondary)
                .tint(.red)
                .disabled(model.isSubmitting)
                .accessibilityLabel("Remove link from \(entry.heading)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    func actionPair<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout { content() }
    }

    func displayWorkTitle(_ ref: AO3RelatedWorkRef) -> String {
        if ref.isUnrevealed { return ref.title.isEmpty ? "Unrevealed work" : ref.title }
        return ref.title.isEmpty ? "Untitled work" : ref.title
    }

    func creatorSuffix(_ creators: [String]) -> String? {
        creators.isEmpty ? nil : "by \(creators.joined(separator: ", "))"
    }

    func languageSummary(from source: String?, to target: String?) -> String? {
        guard let source, let target, !source.isEmpty, !target.isEmpty else { return nil }
        return "\(source) → \(target)"
    }
}
