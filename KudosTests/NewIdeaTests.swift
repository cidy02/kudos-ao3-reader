import Foundation
import Testing
@testable import Kudos

private func withIdeaStores(
    _ body: (WritingDocumentStore, IdeaInbox) async throws -> Void
) async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("new-idea-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = WritingDocumentStore(root: root.appendingPathComponent("Writing"), deviceID: "device-test")
    let inbox = IdeaInbox(url: root.appendingPathComponent("Ideas").appendingPathComponent("ideas.json"))
    try await body(store, inbox)
}

@MainActor
struct NewIdeaHandOffTests {
    @Test func requestFlipsTheObservable() {
        let request = NewIdeaRequest()
        #expect(request.isPresenting == false)
        request.request()
        #expect(request.isPresenting == true)
        request.isPresenting = false
        #expect(request.isPresenting == false)
    }

    @Test func intentAsksTheSharedRequestToPresent() async throws {
        NewIdeaRequest.shared.isPresenting = false
        _ = try await NewIdeaIntent().perform()
        #expect(NewIdeaRequest.shared.isPresenting == true)
        NewIdeaRequest.shared.isPresenting = false
    }

    @Test func repeatedRequestAdvancesRequestID() {
        let request = NewIdeaRequest()
        let initial = request.requestID
        request.request()
        let first = request.requestID
        request.request()
        let second = request.requestID
        #expect(request.isPresenting == true)
        #expect(first != initial)
        #expect(second != first)
    }
}

struct NewIdeaNoteNameTests {
    @Test func nameIsTheFirstLine() {
        #expect(NewIdeaNote.name(for: "Marta knows about the boat\nand has since the storm") == "Marta knows about the boat")
    }

    @Test func leadingBlankLinesAreSkipped() {
        #expect(NewIdeaNote.name(for: "\n  \n  What if the tide never turns?\nmore") == "What if the tide never turns?")
    }

    @Test func trailingWhitespaceOnTheFirstLineIsTrimmed() {
        #expect(NewIdeaNote.name(for: "First line   \t \nSecond line") == "First line")
        let padded = String(repeating: "a", count: 55) + "          extra"
        #expect(NewIdeaNote.name(for: padded) == String(repeating: "a", count: 55))
    }

    @Test func nameIsCutToSixtyCharacters() {
        let line = String(repeating: "a", count: 80)
        let name = NewIdeaNote.name(for: line + "\nsecond line")
        #expect(name.count == 60)
        #expect(name == String(repeating: "a", count: 60))
    }

    @Test func aShortLineIsKeptWhole() {
        #expect(NewIdeaNote.name(for: "Boat") == "Boat")
    }

    @Test func restoredDestinationFallsBackToTheInbox() {
        let work = WritingWork(
            id: UUID(), title: "A", ao3WorkID: nil, createdAt: Date(), updatedAt: Date(),
            updatedBy: "d", chapterOrder: []
        )
        #expect(NewIdeaDestination.restore(work.id.uuidString, among: [work]) == .work(work.id))
        #expect(NewIdeaDestination.restore(UUID().uuidString, among: [work]) == .inbox)
        #expect(NewIdeaDestination.restore("inbox", among: [work]) == .inbox)
        #expect(NewIdeaDestination.restore("", among: []) == .inbox)
    }
}

struct NewIdeaSavingTests {
    @Test func savingToTheInboxKeepsTheTrimmedText() async throws {
        try await withIdeaStores { store, inbox in
            let saver = NewIdeaSaver(store: store, inbox: inbox)
            try await saver.save("  Marta already knows\nabout the boat \n", to: .inbox)
            let ideas = try await inbox.list()
            #expect(ideas.count == 1)
            #expect(ideas.first?.text == "Marta already knows\nabout the boat")
        }
    }

    @Test func whitespaceOnlyIsRefused() async throws {
        try await withIdeaStores { store, inbox in
            let saver = NewIdeaSaver(store: store, inbox: inbox)
            await #expect(throws: NewIdeaError.empty) {
                try await saver.save("  \n\t ", to: .inbox)
            }
            let ideas = try await inbox.list()
            #expect(ideas.isEmpty)
        }
    }

    @Test func savingToAWorkAddsAnUnpinnedOtherNote() async throws {
        try await withIdeaStores { store, inbox in
            let work = try await store.createWork(title: "What the Tide Keeps")
            let saver = NewIdeaSaver(store: store, inbox: inbox)
            try await saver.save("What if Marta knew?\nSince the storm.", to: .work(work.id))
            let notes = try await store.listStoryNotes(workID: work.id)
            #expect(notes.count == 1)
            #expect(notes.first?.kind == .other)
            #expect(notes.first?.name == "What if Marta knew?")
            #expect(notes.first?.detail == "What if Marta knew?\nSince the storm.")
            #expect(notes.first?.pinned == false)
            let ideas = try await inbox.list()
            #expect(ideas.isEmpty)
        }
    }

    @Test func movingAnIdeaToAWorkRemovesItFromTheInbox() async throws {
        try await withIdeaStores { store, inbox in
            let work = try await store.createWork(title: "A Story")
            let saver = NewIdeaSaver(store: store, inbox: inbox)
            try await saver.save("First", to: .inbox)
            try await saver.save("Second\nline two", to: .inbox)
            let ideas = try await inbox.list()
            #expect(ideas.map(\.text) == ["Second\nline two", "First"])

            try await saver.move(ideas[0], toWork: work.id)
            let remaining = try await inbox.list()
            let notes = try await store.listStoryNotes(workID: work.id)
            #expect(remaining.map(\.text) == ["First"])
            #expect(notes.map(\.name) == ["Second"])
        }
    }

    @Test func aFailedMoveKeepsTheIdea() async throws {
        try await withIdeaStores { store, inbox in
            let saver = NewIdeaSaver(store: store, inbox: inbox)
            try await saver.save("Keep me", to: .inbox)
            let stored = try await inbox.list()
            let idea = try #require(stored.first)
            await #expect(throws: WritingDocumentError.self) {
                try await saver.move(idea, toWork: UUID())
            }
            let remaining = try await inbox.list()
            #expect(remaining == [idea])
        }
    }

    @Test func deletingAnIdeaRemovesOnlyThatOne() async throws {
        try await withIdeaStores { _, inbox in
            let first = try await inbox.add("one")
            try await inbox.add("two")
            try await inbox.remove(id: first.id)
            let remaining = try await inbox.list()
            #expect(remaining.map(\.text) == ["two"])
        }
    }

    @Test func missingInboxListsEmptyAndRemoveDoesNotCreateAFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("new-idea-missing-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Ideas").appendingPathComponent("ideas.json")
        let inbox = IdeaInbox(url: url)

        let initial = try await inbox.list()
        #expect(initial.isEmpty)
        try await inbox.remove(id: UUID())
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func corruptInboxThrowsAndPreservesOriginalFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("new-idea-corrupt-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Ideas", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("ideas.json")
        let corrupt = Data("{not valid json".utf8)
        try corrupt.write(to: url)
        let inbox = IdeaInbox(url: url)

        await #expect(throws: WritingDocumentError.corrupt("ideas.json")) {
            _ = try await inbox.list()
        }
        await #expect(throws: WritingDocumentError.corrupt("ideas.json")) {
            _ = try await inbox.add("new idea")
        }
        await #expect(throws: WritingDocumentError.corrupt("ideas.json")) {
            try await inbox.remove(id: UUID())
        }
        let preserved = try Data(contentsOf: url)
        #expect(preserved == corrupt)
    }

    @Test func concurrentAddsAcrossSeparateInstancesKeepEveryIdea() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("new-idea-concurrent-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Ideas").appendingPathComponent("ideas.json")
        let first = IdeaInbox(url: url)
        let second = IdeaInbox(url: url)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                let target = index.isMultiple(of: 2) ? first : second
                let text = "idea-\(index)"
                group.addTask {
                    _ = try await target.add(text)
                }
            }
            try await group.waitForAll()
        }

        let stored = try await IdeaInbox(url: url).list()
        #expect(stored.count == 20)
        #expect(Set(stored.map(\.text)) == Set((0..<20).map { "idea-\($0)" }))
    }
}
