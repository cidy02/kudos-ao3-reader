import Foundation
import Testing
@testable import Kudos

@MainActor
struct AO3WritingRequestsScreensTests {

    // MARK: - Orphan flow

    @Test func orphanFlowSendsNothingWhenLocalCopyFails() async {
        let form = makeOrphanForm(target: .works([101, 102]), titles: ["First Story", "Second Story"])
        var copiedIDs: [Int] = []
        var orphanCalls = 0

        let outcome = await OrphanSubmissionFlow.run(
            target: .works([101, 102]),
            keepPseudCopy: false,
            keepLocalCopy: true,
            finalAlertDecision: .confirmed,
            form: form,
            resolveWorks: {
                [
                    OrphanSubmissionFlow.WorkCopyItem(workID: 101, title: "First Story"),
                    OrphanSubmissionFlow.WorkCopyItem(workID: 102, title: "Second Story")
                ]
            },
            copyWork: { workID in
                copiedIDs.append(workID)
                if workID == 102 {
                    throw AO3Error.network("Timed out")
                }
            },
            submitOrphan: { _, _, _ in
                orphanCalls += 1
                return "Orphaning was successful."
            }
        )

        #expect(copiedIDs == [101, 102])
        #expect(orphanCalls == 0)
        if case let .copyFailed(workTitle, reason) = outcome {
            #expect(workTitle == "Second Story")
            #expect(!reason.isEmpty)
        } else {
            Issue.record("Expected copyFailed, got \(outcome)")
        }
    }

    @Test func orphanFlowHandlesBothFinalAlertDecisions() async {
        let form = makeOrphanForm(target: .work(424242), titles: ["The Weight of Water"])
        var resolveCalls = 0
        var copyCalls = 0
        var orphanCalls = 0

        let cancelled = await OrphanSubmissionFlow.run(
            target: .work(424242),
            keepPseudCopy: false,
            keepLocalCopy: true,
            finalAlertDecision: .cancelled,
            form: form,
            resolveWorks: {
                resolveCalls += 1
                return [OrphanSubmissionFlow.WorkCopyItem(workID: 424242, title: "The Weight of Water")]
            },
            copyWork: { _ in copyCalls += 1 },
            submitOrphan: { _, _, _ in
                orphanCalls += 1
                return "Orphaning was successful."
            }
        )

        #expect(cancelled == .cancelled)
        #expect(resolveCalls == 0)
        #expect(copyCalls == 0)
        #expect(orphanCalls == 0)

        let confirmed = await OrphanSubmissionFlow.run(
            target: .work(424242),
            keepPseudCopy: false,
            keepLocalCopy: true,
            finalAlertDecision: .confirmed,
            form: form,
            resolveWorks: {
                resolveCalls += 1
                return [OrphanSubmissionFlow.WorkCopyItem(workID: 424242, title: "The Weight of Water")]
            },
            copyWork: { _ in copyCalls += 1 },
            submitOrphan: { _, _, _ in
                orphanCalls += 1
                return "Orphaning was successful."
            }
        )

        #expect(confirmed == .orphaned("Orphaning was successful."))
        #expect(resolveCalls == 1)
        #expect(copyCalls == 1)
        #expect(orphanCalls == 1)
    }

    @Test func orphanFlowSubmitsOnceAfterCopiesSucceed() async {
        let form = makeOrphanForm(target: .work(424242), titles: ["The Weight of Water"])
        var copiedIDs: [Int] = []
        var submittedKeepPseud: Bool?
        var orphanCalls = 0

        let outcome = await OrphanSubmissionFlow.run(
            target: .work(424242),
            keepPseudCopy: true,
            keepLocalCopy: true,
            finalAlertDecision: .confirmed,
            form: form,
            resolveWorks: {
                [OrphanSubmissionFlow.WorkCopyItem(workID: 424242, title: "The Weight of Water")]
            },
            copyWork: { copiedIDs.append($0) },
            submitOrphan: { _, keepPseud, _ in
                orphanCalls += 1
                submittedKeepPseud = keepPseud
                return "Orphaning was successful."
            }
        )

        #expect(outcome == .orphaned("Orphaning was successful."))
        #expect(copiedIDs == [424242])
        #expect(orphanCalls == 1)
        #expect(submittedKeepPseud == true)
    }

    // MARK: - Import validation (25 works / 200 chapters / language required)

    @Test func importValidationRequiresURLsAndLanguage() {
        let blankURLs = AO3ImportValidation.evaluate(
            urlsText: "   \n\n  ",
            mode: .works,
            languageID: "1"
        )
        #expect(blankURLs.urls.isEmpty)
        #expect(!blankURLs.canImport)

        let missingLanguage = AO3ImportValidation.evaluate(
            urlsText: "https://example.com/story/1",
            mode: .works,
            languageID: ""
        )
        #expect(missingLanguage.isLanguageMissing)
        #expect(!missingLanguage.canImport)

        let valid = AO3ImportValidation.evaluate(
            urlsText: "https://example.com/story/1\n\nhttps://example.com/story/2",
            mode: .works,
            languageID: "1"
        )
        #expect(valid.urls.count == 2)
        #expect(valid.canImport)
        #expect(valid.overLimitNote == nil)
    }

    @Test func importValidationEnforces25WorksAnd200ChaptersLimits() {
        let urls25 = (1 ... 25).map { "https://example.com/work/\($0)" }.joined(separator: "\n")
        let atWorksLimit = AO3ImportValidation.evaluate(
            urlsText: urls25, mode: .works, languageID: "1"
        )
        #expect(atWorksLimit.canImport)
        #expect(!atWorksLimit.isOverLimit)
        #expect(atWorksLimit.overLimitNote == nil)

        let urls26 = (1 ... 26).map { "https://example.com/work/\($0)" }.joined(separator: "\n")
        let overWorksLimit = AO3ImportValidation.evaluate(
            urlsText: urls26, mode: .works, languageID: "1"
        )
        #expect(!overWorksLimit.canImport)
        #expect(overWorksLimit.isOverLimit)
        #expect(overWorksLimit.overLimitNote?.contains("25") == true)

        let urls200 = (1 ... 200).map { "https://example.com/ch/\($0)" }.joined(separator: "\n")
        let atChaptersLimit = AO3ImportValidation.evaluate(
            urlsText: urls200, mode: .chapters, languageID: "1"
        )
        #expect(atChaptersLimit.canImport)
        #expect(!atChaptersLimit.isOverLimit)
        #expect(atChaptersLimit.overLimitNote == nil)

        let urls201 = (1 ... 201).map { "https://example.com/ch/\($0)" }.joined(separator: "\n")
        let overChaptersLimit = AO3ImportValidation.evaluate(
            urlsText: urls201, mode: .chapters, languageID: "1"
        )
        #expect(!overChaptersLimit.canImport)
        #expect(overChaptersLimit.isOverLimit)
        #expect(overChaptersLimit.overLimitNote?.contains("200") == true)
    }

    // MARK: - Requests reloads affected section on stateChanged

    @Test func requestsReloadsOnlyGiftsSectionOnGiftStateChanged() async {
        let model = WritingRequestsModel()
        var coCreatorLoads = 0
        var relatedLoads = 0
        var acceptedGiftLoads = 0
        var refusedGiftLoads = 0
        let refreshedGift = makeGiftRow(giftID: 9001, workID: 2001, title: "Still Here", isRefused: false)

        let service = WritingRequestsModel.Service(
            loadCoCreatorRequests: { _ in
                coCreatorLoads += 1
                return AO3CoCreatorRequestsPage(
                    requests: [], csrfToken: "c", actionURL: nil, currentPage: 1, totalPages: 1
                )
            },
            answerCoCreatorRequests: { _, _, _ in "" },
            loadRelatedWorks: {
                relatedLoads += 1
                return AO3RelatedWorksPage(
                    translationsOfMe: [], translationsByMe: [],
                    inspiredByMe: [], thatInspiredMe: [], csrfToken: "r"
                )
            },
            setRelatedWorkLinkApproved: { _, _ in "" },
            removeMyRelatedWorkLink: { _ in },
            loadGifts: { refused, _ in
                if refused {
                    refusedGiftLoads += 1
                    return AO3GiftsPage(
                        gifts: [], isRefusedList: true, csrfToken: "g", currentPage: 1, totalPages: 1
                    )
                }
                acceptedGiftLoads += 1
                return AO3GiftsPage(
                    gifts: [refreshedGift],
                    isRefusedList: false,
                    csrfToken: "g",
                    currentPage: 1,
                    totalPages: 1
                )
            },
            setGiftRefused: { _, _, _, _ in
                throw AO3WorkWriteError.stateChanged
            }
        )

        let staleGift = makeGiftRow(giftID: 8801, workID: 1001, title: "Old Gift", isRefused: false)
        await model.setGiftRefused(staleGift, refused: true, using: service)

        #expect(model.actionError == "This changed on AO3 before your answer went through.")
        #expect(acceptedGiftLoads == 1)
        #expect(refusedGiftLoads == 0)
        #expect(coCreatorLoads == 0)
        #expect(relatedLoads == 0)
        #expect(model.acceptedGifts == [refreshedGift])
    }

    @Test func requestsReloadsOnlyRelatedWorksSectionOnRelatedWorkStateChanged() async {
        let model = WritingRequestsModel()
        var coCreatorLoads = 0
        var relatedLoads = 0
        var giftLoads = 0
        let approvedRow = AO3RelatedWorkRow(
            id: 301,
            parentWork: AO3RelatedWorkRef(workID: 101, title: "Original", url: nil, creators: []),
            childWork: AO3RelatedWorkRef(workID: 201, title: "Translation", url: nil, creators: ["tr"]),
            fromLanguage: "English",
            toLanguage: "Français",
            isApproved: true,
            action: .toggleReciprocal(isApproved: true)
        )

        let service = WritingRequestsModel.Service(
            loadCoCreatorRequests: { _ in
                coCreatorLoads += 1
                return AO3CoCreatorRequestsPage(
                    requests: [], csrfToken: "c", actionURL: nil, currentPage: 1, totalPages: 1
                )
            },
            answerCoCreatorRequests: { _, _, _ in "" },
            loadRelatedWorks: {
                relatedLoads += 1
                return AO3RelatedWorksPage(
                    translationsOfMe: [approvedRow],
                    translationsByMe: [],
                    inspiredByMe: [],
                    thatInspiredMe: [],
                    csrfToken: "r"
                )
            },
            setRelatedWorkLinkApproved: { _, _ in
                throw AO3WorkWriteError.stateChanged
            },
            removeMyRelatedWorkLink: { _ in },
            loadGifts: { _, _ in
                giftLoads += 1
                return AO3GiftsPage(
                    gifts: [], isRefusedList: false, csrfToken: "g", currentPage: 1, totalPages: 1
                )
            },
            setGiftRefused: { _, _, _, _ in "" }
        )

        var staleRow = approvedRow
        staleRow.isApproved = false
        staleRow.action = .toggleReciprocal(isApproved: false)
        await model.setRelatedWorkApproved(staleRow, approved: true, using: service)

        #expect(model.actionError == "This changed on AO3 before your answer went through.")
        #expect(relatedLoads == 1)
        #expect(coCreatorLoads == 0)
        #expect(giftLoads == 0)
        #expect(model.relatedWorks?.translationsOfMe == [approvedRow])
    }

    // MARK: - Remove Me on onlyCreator changes nothing

    @Test func removeMeOnOnlyCreatorChangesNothingForWorkAndSeries() async {
        var workMutated = false
        let workOutcome = await WorkCoCreatorRemovalFlow.run(
            kind: .work,
            remove: { throw AO3WorkWriteError.onlyCreator },
            onRemoved: { workMutated = true }
        )
        #expect(!workMutated)
        #expect(
            workOutcome
                == .onlyCreator(
                    "You're the only creator of this work. You can orphan it or delete it instead."
                )
        )

        var seriesMutated = false
        let seriesOutcome = await WorkCoCreatorRemovalFlow.run(
            kind: .series,
            remove: { throw AO3WorkWriteError.onlyCreator },
            onRemoved: { seriesMutated = true }
        )
        #expect(!seriesMutated)
        #expect(
            seriesOutcome
                == .onlyCreator(
                    "You're the only creator of this series. You can orphan it or delete it instead."
                )
        )
    }

    // MARK: - Helpers

    private func makeOrphanForm(target: AO3OrphanTarget, titles: [String]) -> AO3OrphanForm {
        AO3OrphanForm(
            target: target,
            actionURL: AO3Client.orphansCreateURL(),
            csrfToken: "orphan-csrf==",
            titles: titles,
            pseudOptions: [
                AO3FormOption(value: "true", title: "Take my pseud off as well"),
                AO3FormOption(value: "false", title: "Leave a copy of my pseud on")
            ],
            cautionTexts: [],
            submitLabel: "Yes, I'm sure"
        )
    }

    private func makeGiftRow(
        giftID: Int, workID: Int, title: String, isRefused: Bool
    ) -> AO3GiftRow {
        let summary = AO3WorkSummary(
            id: workID,
            title: title,
            authors: ["kestrel"],
            fandoms: ["Original Work"],
            rating: "General Audiences",
            warnings: ["No Archive Warnings Apply"],
            categories: ["Gen"],
            isComplete: true,
            dateUpdated: "12 Oct 2026",
            tags: [],
            summary: "",
            language: "English",
            words: 1200,
            chapters: "1/1",
            comments: nil,
            kudos: nil,
            hits: nil
        )
        return AO3GiftRow(
            giftID: giftID,
            workID: workID,
            title: title,
            creators: ["kestrel"],
            isAnonymous: false,
            isRefused: isRefused,
            work: summary
        )
    }
}

#if DEBUG
@MainActor
struct AO3WritingRequestsDemoTests {
    private final class DemoFixtureAnchor {}

    private func demoHTML(for url: URL) throws -> String {
        let name = try #require(DemoNetworkBlock.fixture(for: url))
        let fileURL = try #require(
            Bundle(for: DemoFixtureAnchor.self).url(forResource: name, withExtension: "html")
        )
        let raw = try String(contentsOf: fileURL, encoding: .utf8)
        return DemoNetworkBlock.responseHTML(for: url, from: raw)
    }

    @Test func demoNetworkBlockMapsNewWritingRequestRoutes() {
        #expect(
            DemoNetworkBlock.fixture(
                for: URL(string: "https://archiveofourown.org/works/1001/edit")!
            ) == "ao3_demo_work_edit"
        )
        #expect(
            DemoNetworkBlock.fixture(
                for: URL(string: "https://archiveofourown.org/users/AO3_Reader/creatorships")!
            ) == "ao3_demo_creatorships"
        )
        #expect(
            DemoNetworkBlock.fixture(
                for: URL(string: "https://archiveofourown.org/users/AO3_Reader/gifts")!
            ) == "ao3_demo_gifts_accepted"
        )
        #expect(
            DemoNetworkBlock.fixture(
                for: URL(string: "https://archiveofourown.org/users/AO3_Reader/gifts?refused=true")!
            ) == "ao3_demo_gifts_refused"
        )
        #expect(
            DemoNetworkBlock.fixture(
                for: URL(string: "https://archiveofourown.org/users/AO3_Reader/related_works")!
            ) == "ao3_demo_related_works"
        )
        #expect(
            DemoNetworkBlock.fixture(
                for: URL(string: "https://archiveofourown.org/related_works/301")!
            ) == "ao3_demo_related_work_approve"
        )
        #expect(
            DemoNetworkBlock.fixture(
                for: URL(string: "https://archiveofourown.org/related_works/303")!
            ) == "ao3_demo_related_work_remove"
        )
        #expect(
            DemoNetworkBlock.fixture(
                for: URL(string: "https://archiveofourown.org/orphans/new?work_id=1001")!
            ) == "ao3_demo_orphan_work"
        )
        #expect(
            DemoNetworkBlock.fixture(
                for: URL(string: "https://archiveofourown.org/orphans/new?series_id=321")!
            ) == "ao3_demo_orphan_series"
        )
        #expect(
            DemoNetworkBlock.fixture(
                for: URL(string: "https://archiveofourown.org/works/new?import=true")!
            ) == "ao3_demo_work_import_form"
        )
        #expect(
            DemoNetworkBlock.fixture(
                for: URL(string: "https://archiveofourown.org/works/new")!
            ) == "ao3_work_new_draft"
        )
    }

    @Test func demoFixturesParseWithExactDebugShotAndDemoLibraryIDs() throws {
        // 1. Posted demo work edit (`shot:orphansheet` opens `acct:workedit:1001`):
        // must expose both Remove Me and Orphan actions, and its orphan form must parse.
        let editShot = try #require(DebugShots.byName["orphansheet"])
        let shotWorkID = try #require(Int(editShot.route.replacingOccurrences(of: "acct:workedit:", with: "")))
        let editForm = try AO3Client.parseWorkForm(from: try demoHTML(for: AO3Client.workEditURL(workID: shotWorkID)))
        #expect(editForm.isPosted)
        #expect(editForm.canRemoveMe)
        #expect(editForm.canOrphan)

        let shotOrphanURL = try #require(AO3Client.orphanNewURL(for: .work(shotWorkID)))
        let shotOrphan = try AO3Client.parseOrphanForm(
            from: try demoHTML(for: shotOrphanURL), target: .work(shotWorkID)
        )
        #expect(shotOrphan.titles == ["The Weight of Water"])

        if let formWorkID = editForm.workID {
            let formOrphanURL = try #require(AO3Client.orphanNewURL(for: .work(formWorkID)))
            let formOrphan = try AO3Client.parseOrphanForm(
                from: try demoHTML(for: formOrphanURL), target: .work(formWorkID)
            )
            #expect(formOrphan.titles == ["The Weight of Water"])
        }

        // 2. Several-works orphan path (exact IDs from `ao3_edit_multiple.html`).
        let bulkForm = try AO3Client.parseBulkEditForm(
            from: try demoHTML(for: try #require(AO3Client.editMultipleWorksURL(username: "AO3_Reader")))
        )
        let multiURL = try #require(AO3Client.orphanNewURL(for: .works(bulkForm.workIDs)))
        let multiOrphan = try AO3Client.parseOrphanForm(
            from: try demoHTML(for: multiURL), target: .works(bulkForm.workIDs)
        )
        #expect(multiOrphan.titles.count == bulkForm.workIDs.count)

        // 3. Series orphan path (series 321 "The Dawn Cycle" in `ao3_demo_author_series.html`).
        let seriesURL = try #require(AO3Client.orphanNewURL(for: .series(321)))
        let seriesOrphan = try AO3Client.parseOrphanForm(
            from: try demoHTML(for: seriesURL), target: .series(321)
        )
        #expect(seriesOrphan.titles == ["The Dawn Cycle"])

        // 4. Requests screen demo pages (`shot:writingrequests`): co-creators, gifts, related works.
        let coCreators = try AO3Client.parseCoCreatorRequests(
            from: try demoHTML(for: try #require(AO3Client.coCreatorRequestsURL(username: "AO3_Reader"))), page: 1
        )
        #expect(coCreators.requests.count == 2)

        let acceptedGifts = try AO3Client.parseGiftsPage(
            from: try demoHTML(for: try #require(AO3Client.giftsURL(username: "AO3_Reader", refused: false))),
            refused: false, page: 1
        )
        #expect(acceptedGifts.gifts.count == 2)

        let refusedGifts = try AO3Client.parseGiftsPage(
            from: try demoHTML(for: try #require(AO3Client.giftsURL(username: "AO3_Reader", refused: true))),
            refused: true, page: 1
        )
        #expect(refusedGifts.gifts.count == 1)

        let related = try AO3Client.parseRelatedWorks(
            from: try demoHTML(for: try #require(AO3Client.relatedWorksURL(username: "AO3_Reader")))
        )
        for row in related.translationsOfMe + related.inspiredByMe {
            guard case let .toggleReciprocal(isApproved) = row.action else { continue }
            let show = try AO3Client.parseRelatedWorkShow(
                from: try demoHTML(for: AO3Client.relatedWorkURL(id: row.id))
            )
            let expected: AO3RelatedWorkShowMode = isApproved ? .remove : .approve
            #expect(show.mode == expected, "Demo /related_works/\(row.id) mode must match index row state")
            #expect(show.id == row.id)
        }

        // 5. Import form (`shot:importwork`).
        let importForm = try AO3Client.parseImportForm(from: try demoHTML(for: AO3Client.importWorkFormURL()))
        #expect(!importForm.languageOptions.isEmpty)
    }
}
#endif
