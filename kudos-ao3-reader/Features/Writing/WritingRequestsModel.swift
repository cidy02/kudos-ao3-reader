import Foundation
import Observation

/// State and sequential AO3 loading for `WritingRequestsView` and
/// `WritingRefusedGiftsView`. Nothing loads automatically: callers invoke
/// `loadAll()` when the Requests screen opens (or refreshes) and
/// `loadRefusedGifts()` only when the user opens Refused Gifts.
@MainActor
@Observable
final class WritingRequestsModel {
    enum SectionPhase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// Injectable service boundary so screen-logic tests can exercise
    /// `stateChanged` reloads without hitting AO3.
    struct Service {
        var loadCoCreatorRequests: @MainActor (Int) async throws -> AO3CoCreatorRequestsPage
        var answerCoCreatorRequests: @MainActor ([Int], Bool, Int) async throws -> String
        var loadRelatedWorks: @MainActor () async throws -> AO3RelatedWorksPage
        var setRelatedWorkLinkApproved: @MainActor (Int, Bool) async throws -> String
        var removeMyRelatedWorkLink: @MainActor (Int) async throws -> Void
        var loadGifts: @MainActor (Bool, Int) async throws -> AO3GiftsPage
        var setGiftRefused: @MainActor (Int, Int, Bool, Int) async throws -> String

        static func live(auth: AO3AuthService) -> Service {
            Service(
                loadCoCreatorRequests: { page in
                    try await auth.loadCoCreatorRequests(page: page)
                },
                answerCoCreatorRequests: { ids, accept, page in
                    try await auth.answerCoCreatorRequests(ids: ids, accept: accept, page: page)
                },
                loadRelatedWorks: {
                    try await auth.loadRelatedWorks()
                },
                setRelatedWorkLinkApproved: { id, approved in
                    try await auth.setRelatedWorkLinkApproved(id: id, approved: approved)
                },
                removeMyRelatedWorkLink: { id in
                    try await auth.removeMyRelatedWorkLink(id: id)
                },
                loadGifts: { refused, page in
                    try await auth.loadGifts(refused: refused, page: page)
                },
                setGiftRefused: { giftID, workID, refused, page in
                    try await auth.setGiftRefused(
                        giftID: giftID, workID: workID, refused: refused, page: page
                    )
                }
            )
        }
    }

    static let stateChangedMessage = "This changed on AO3 before your answer went through."

    // MARK: Co-creator invitations

    private(set) var coCreatorsPhase: SectionPhase = .idle
    private(set) var coCreatorRequests: [AO3CoCreatorRequest] = []
    private(set) var coCreatorsCurrentPage = 1
    private(set) var coCreatorsTotalPages = 1
    private(set) var isLoadingMoreCoCreators = false
    private var coCreatorPageByID: [Int: Int] = [:]

    // MARK: Related works

    private(set) var relatedWorksPhase: SectionPhase = .idle
    private(set) var relatedWorks: AO3RelatedWorksPage?

    // MARK: Accepted gifts

    private(set) var giftsPhase: SectionPhase = .idle
    private(set) var acceptedGifts: [AO3GiftRow] = []
    private(set) var giftsCurrentPage = 1
    private(set) var giftsTotalPages = 1
    private(set) var isLoadingMoreGifts = false
    private var acceptedGiftPageByID: [Int: Int] = [:]

    // MARK: Refused gifts (loaded on demand when Refused Gifts opens)

    private(set) var refusedGiftsPhase: SectionPhase = .idle
    private(set) var refusedGifts: [AO3GiftRow] = []
    private(set) var refusedGiftsCurrentPage = 1
    private(set) var refusedGiftsTotalPages = 1
    private(set) var isLoadingMoreRefusedGifts = false
    private var refusedGiftPageByID: [Int: Int] = [:]

    // MARK: Write feedback & selection

    var isSelectingCoCreators = false
    var selectedCoCreatorIDs: Set<Int> = []
    private(set) var isSubmitting = false
    var statusMessage: String?
    var actionError: String?

    private(set) var boundSessionGeneration: Int?

    var hasMoreCoCreators: Bool {
        coCreatorsPhase == .loaded && coCreatorsCurrentPage < coCreatorsTotalPages
    }

    var hasMoreGifts: Bool {
        giftsPhase == .loaded && giftsCurrentPage < giftsTotalPages
    }

    var hasMoreRefusedGifts: Bool {
        refusedGiftsPhase == .loaded && refusedGiftsCurrentPage < refusedGiftsTotalPages
    }

    var totalRelatedWorksCount: Int {
        guard let page = relatedWorks else { return 0 }
        return page.translationsOfMe.count
            + page.inspiredByMe.count
            + page.translationsByMe.count
            + page.thatInspiredMe.count
    }

    func resetForSession(_ generation: Int) {
        guard boundSessionGeneration != generation else { return }
        boundSessionGeneration = generation
        coCreatorsPhase = .idle
        coCreatorRequests = []
        coCreatorsCurrentPage = 1
        coCreatorsTotalPages = 1
        coCreatorPageByID = [:]
        relatedWorksPhase = .idle
        relatedWorks = nil
        giftsPhase = .idle
        acceptedGifts = []
        giftsCurrentPage = 1
        giftsTotalPages = 1
        acceptedGiftPageByID = [:]
        refusedGiftsPhase = .idle
        refusedGifts = []
        refusedGiftsCurrentPage = 1
        refusedGiftsTotalPages = 1
        refusedGiftPageByID = [:]
        isSelectingCoCreators = false
        selectedCoCreatorIDs = []
        statusMessage = nil
        actionError = nil
    }

    // MARK: Sequential initial load & refresh

    /// Loads co-creator requests, related works, and accepted gifts one after
    /// another through `AO3Client` pacing. Checks cancellation between pages.
    func loadAll(using service: Service) async {
        await loadCoCreators(page: 1, append: false, using: service)
        guard !Task.isCancelled else { return }
        await loadRelatedWorks(using: service)
        guard !Task.isCancelled else { return }
        await loadGifts(page: 1, append: false, using: service)
    }

    func loadCoCreators(page: Int, append: Bool, using service: Service) async {
        if append {
            guard !isLoadingMoreCoCreators else { return }
            isLoadingMoreCoCreators = true
        } else {
            coCreatorsPhase = .loading
        }
        defer {
            if append { isLoadingMoreCoCreators = false }
        }
        do {
            let loaded = try await service.loadCoCreatorRequests(page)
            guard !Task.isCancelled else { return }
            if append {
                let existing = Set(coCreatorRequests.map(\.id))
                for request in loaded.requests where !existing.contains(request.id) {
                    coCreatorRequests.append(request)
                    coCreatorPageByID[request.id] = loaded.currentPage
                }
            } else {
                coCreatorRequests = loaded.requests
                coCreatorPageByID = Dictionary(
                    uniqueKeysWithValues: loaded.requests.map { ($0.id, loaded.currentPage) }
                )
                let visible = Set(loaded.requests.map(\.id))
                selectedCoCreatorIDs = selectedCoCreatorIDs.intersection(visible)
                if loaded.requests.isEmpty { isSelectingCoCreators = false }
            }
            coCreatorsCurrentPage = loaded.currentPage
            coCreatorsTotalPages = max(loaded.totalPages, 1)
            coCreatorsPhase = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            if append {
                actionError = UserFacingError.message(for: error)
            } else {
                coCreatorsPhase = .failed(UserFacingError.message(for: error))
            }
        }
    }

    func loadRelatedWorks(using service: Service) async {
        relatedWorksPhase = .loading
        do {
            let loaded = try await service.loadRelatedWorks()
            guard !Task.isCancelled else { return }
            relatedWorks = loaded
            relatedWorksPhase = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            relatedWorksPhase = .failed(UserFacingError.message(for: error))
        }
    }

    func loadGifts(page: Int, append: Bool, using service: Service) async {
        if append {
            guard !isLoadingMoreGifts else { return }
            isLoadingMoreGifts = true
        } else {
            giftsPhase = .loading
        }
        defer {
            if append { isLoadingMoreGifts = false }
        }
        do {
            let loaded = try await service.loadGifts(false, page)
            guard !Task.isCancelled else { return }
            if append {
                let existing = Set(acceptedGifts.map(\.giftID))
                for gift in loaded.gifts where !existing.contains(gift.giftID) {
                    acceptedGifts.append(gift)
                    acceptedGiftPageByID[gift.giftID] = loaded.currentPage
                }
            } else {
                acceptedGifts = loaded.gifts
                acceptedGiftPageByID = Dictionary(
                    uniqueKeysWithValues: loaded.gifts.map { ($0.giftID, loaded.currentPage) }
                )
            }
            giftsCurrentPage = loaded.currentPage
            giftsTotalPages = max(loaded.totalPages, 1)
            giftsPhase = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            if append {
                actionError = UserFacingError.message(for: error)
            } else {
                giftsPhase = .failed(UserFacingError.message(for: error))
            }
        }
    }

    func loadRefusedGifts(page: Int, append: Bool, using service: Service) async {
        if append {
            guard !isLoadingMoreRefusedGifts else { return }
            isLoadingMoreRefusedGifts = true
        } else {
            refusedGiftsPhase = .loading
        }
        defer {
            if append { isLoadingMoreRefusedGifts = false }
        }
        do {
            let loaded = try await service.loadGifts(true, page)
            guard !Task.isCancelled else { return }
            if append {
                let existing = Set(refusedGifts.map(\.giftID))
                for gift in loaded.gifts where !existing.contains(gift.giftID) {
                    refusedGifts.append(gift)
                    refusedGiftPageByID[gift.giftID] = loaded.currentPage
                }
            } else {
                refusedGifts = loaded.gifts
                refusedGiftPageByID = Dictionary(
                    uniqueKeysWithValues: loaded.gifts.map { ($0.giftID, loaded.currentPage) }
                )
            }
            refusedGiftsCurrentPage = loaded.currentPage
            refusedGiftsTotalPages = max(loaded.totalPages, 1)
            refusedGiftsPhase = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            if append {
                actionError = UserFacingError.message(for: error)
            } else {
                refusedGiftsPhase = .failed(UserFacingError.message(for: error))
            }
        }
    }

    // MARK: Single-shot writes (never auto-retried)

    func answerCoCreators(ids: [Int], accept: Bool, using service: Service) async {
        guard !isSubmitting, !ids.isEmpty else { return }
        isSubmitting = true
        actionError = nil
        statusMessage = nil
        let page = ids.count == 1 ? (coCreatorPageByID[ids[0]] ?? 1) : coCreatorsCurrentPage
        defer { isSubmitting = false }
        do {
            let notice = try await service.answerCoCreatorRequests(ids, accept, page)
            selectedCoCreatorIDs.subtract(ids)
            if selectedCoCreatorIDs.isEmpty { isSelectingCoCreators = false }
            statusMessage = notice
            await loadCoCreators(page: 1, append: false, using: service)
        } catch AO3WorkWriteError.stateChanged {
            actionError = Self.stateChangedMessage
            await loadCoCreators(page: 1, append: false, using: service)
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }

    func setRelatedWorkApproved(
        _ row: AO3RelatedWorkRow, approved: Bool, using service: Service
    ) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        actionError = nil
        statusMessage = nil
        defer { isSubmitting = false }
        do {
            let notice = try await service.setRelatedWorkLinkApproved(row.id, approved)
            statusMessage = notice
            await loadRelatedWorks(using: service)
        } catch AO3WorkWriteError.stateChanged {
            actionError = Self.stateChangedMessage
            await loadRelatedWorks(using: service)
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }

    func removeMyRelatedWork(_ row: AO3RelatedWorkRow, using service: Service) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        actionError = nil
        statusMessage = nil
        defer { isSubmitting = false }
        do {
            try await service.removeMyRelatedWorkLink(row.id)
            statusMessage = "Link removed."
            await loadRelatedWorks(using: service)
        } catch AO3WorkWriteError.stateChanged {
            actionError = Self.stateChangedMessage
            await loadRelatedWorks(using: service)
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }

    func setGiftRefused(
        _ row: AO3GiftRow, refused: Bool, using service: Service
    ) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        actionError = nil
        statusMessage = nil
        let page = refused
            ? (acceptedGiftPageByID[row.giftID] ?? 1)
            : (refusedGiftPageByID[row.giftID] ?? 1)
        defer { isSubmitting = false }
        do {
            let notice = try await service.setGiftRefused(row.giftID, row.workID, refused, page)
            statusMessage = notice
            if refused {
                await loadGifts(page: 1, append: false, using: service)
            } else {
                await loadRefusedGifts(page: 1, append: false, using: service)
            }
        } catch AO3WorkWriteError.stateChanged {
            actionError = Self.stateChangedMessage
            if refused {
                await loadGifts(page: 1, append: false, using: service)
            } else {
                await loadRefusedGifts(page: 1, append: false, using: service)
            }
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }

    // MARK: Co-creator selection helpers

    func toggleCoCreatorSelection(_ id: Int) {
        if selectedCoCreatorIDs.contains(id) {
            selectedCoCreatorIDs.remove(id)
        } else {
            selectedCoCreatorIDs.insert(id)
        }
    }

    func selectAllCoCreators() {
        selectedCoCreatorIDs = Set(coCreatorRequests.map(\.id))
    }

    func clearCoCreatorSelection() {
        selectedCoCreatorIDs = []
    }
}
