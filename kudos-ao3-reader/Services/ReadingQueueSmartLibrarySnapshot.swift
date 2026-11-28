import Foundation
import SwiftData

extension ReadingQueueService {
    /// A single evaluation pass over the library. Each rule uses positions in
    /// shortest-first order, so length ranges and categorical sets can be
    /// combined before any visibility check or result limit.
    @MainActor
    final class SmartLibrarySnapshot {
        let eligible: [SavedWork]
        private let works: [SavedWork]
        private let facts: [SmartQueueWorkFacts]
        private let rowsInInputOrder: [Int]
        private let byID: [UUID: SavedWork]
        private let aliases: TagAliasResolver
        private let knownLengthCount: Int
        private var otherOrders: [SmartQueueDocument.Sort: [Int]] = [:]
        private lazy var completion = index { $0.isComplete }
        private lazy var progress: [SmartQueueDocument.Rule.Progress: IndexSet] = index { work in
            if work.isFinished { return .finished }
            return work.hasStartedReading ? .inProgress : .notStarted
        }
        private lazy var readingStatus = index { $0.readingStatus }
        private lazy var fandoms = fandomIndex()

        init(works: [SavedWork], aliases: TagAliasResolver = .empty) {
            let eligible = works.filter { !$0.isPendingDeletion && !$0.isQueueOnlyWork }
            let unsorted = eligible.map(SmartQueueWorkFacts.init(work:))
            let order = unsorted.indices.sorted {
                Self.lengthOrder(unsorted[$0], unsorted[$1], longest: false)
            }
            self.eligible = eligible
            self.works = order.map { eligible[$0] }
            facts = order.map { unsorted[$0] }
            var inputRows = Array(repeating: 0, count: order.count)
            for (row, input) in order.enumerated() { inputRows[input] = row }
            rowsInInputOrder = inputRows
            knownLengthCount = order.firstIndex { unsorted[$0].wordCount <= 0 } ?? order.count
            byID = Dictionary(zip(unsorted.map(\.id), eligible), uniquingKeysWith: { first, _ in first })
            self.aliases = aliases
        }

        convenience init(in context: ModelContext) {
            let library = (try? context.fetch(FetchDescriptor<SavedWork>())) ?? []
            self.init(works: library, aliases: TagAliasStore.resolver(in: context))
        }

        /// Visibility applies before the document's cap.
        func matching(_ queue: ReadingQueue, where include: ((SavedWork) -> Bool)? = nil) -> [SavedWork] {
            matching(queue, include: include, includeHiddenPrefix: false)
        }

        /// What Fits also needs hidden works from the unrestricted prefix to
        /// tell the reader when a mature work would have fit.
        func matchingForWhatFits(_ queue: ReadingQueue, where include: (SavedWork) -> Bool) -> [SavedWork] {
            withoutActuallyEscaping(include) { visible in
                matching(queue, include: visible, includeHiddenPrefix: true)
            }
        }

        private func matching(
            _ queue: ReadingQueue,
            include: ((SavedWork) -> Bool)?,
            includeHiddenPrefix: Bool
        ) -> [SavedWork] {
            guard queue.kind == .smart,
                  let document = SmartQueueRules.decode(queue.smartRulesJSON),
                  let firstRule = document.rules.first
            else { return [] }

            var matches = rows(matching: firstRule)
            for rule in document.rules.dropFirst() {
                switch document.match {
                case .all:
                    if matches.isEmpty { return [] }
                    matches.formIntersection(rows(matching: rule))
                case .any:
                    matches.formUnion(rows(matching: rule))
                }
            }
            guard !matches.isEmpty else { return [] }
            let limit = document.limit.flatMap { $0 > 0 ? $0 : nil } ?? Int.max
            if document.sort == .shortestFirst {
                return select(from: matches, limit: limit, include: include, includeHiddenPrefix: includeHiddenPrefix)
            }
            return select(
                from: order(for: document.sort).lazy.filter { matches.contains($0) },
                limit: limit,
                include: include,
                includeHiddenPrefix: includeHiddenPrefix
            )
        }

        private func select<Rows: Sequence>(
            from rows: Rows,
            limit: Int,
            include: ((SavedWork) -> Bool)?,
            includeHiddenPrefix: Bool
        ) -> [SavedWork] where Rows.Element == Int {
            var shown: [SavedWork] = []
            var hidden: [SavedWork] = []
            var prefixRemaining = includeHiddenPrefix ? limit : 0
            for row in rows {
                let work = works[row]
                let resolved = byID[facts[row].id] ?? work
                let isVisible = include?(work) ?? true
                if shown.count < limit, isVisible { shown.append(resolved) }
                if prefixRemaining > 0 {
                    let resolvedIsVisible = resolved === work ? isVisible : (include?(resolved) ?? true)
                    if !resolvedIsVisible { hidden.append(resolved) }
                    prefixRemaining -= 1
                }
                if shown.count == limit, prefixRemaining == 0 { break }
            }
            shown.append(contentsOf: hidden)
            return shown
        }

        private func rows(matching rule: SmartQueueDocument.Rule) -> IndexSet {
            switch rule.kind {
            case .length:
                guard let words = rule.words, words >= 0 else { return [] }
                let boundary = lowerBound(count: knownLengthCount) { facts[$0].wordCount < words }
                switch rule.lengthComparison ?? .under {
                case .under: return IndexSet(integersIn: 0..<boundary)
                case .atLeast: return IndexSet(integersIn: boundary..<knownLengthCount)
                }
            case .completion:
                return completion[(rule.completion ?? .complete) == .complete] ?? []
            case .progress:
                return progress[rule.progress ?? .notStarted] ?? []
            case .readingStatus:
                guard let status = rule.readingStatus else { return [] }
                return readingStatus[status] ?? []
            case .fandom:
                let wanted = aliases.resolveIgnoringCase(rule.fandom ?? "", kind: .fandom)
                guard !wanted.isEmpty else { return [] }
                let names = fandoms
                let start = lowerBound(count: names.count) {
                    names[$0].name.caseInsensitiveCompare(wanted) == .orderedAscending
                }
                var matches = IndexSet()
                for entry in names[start...] {
                    guard entry.name.caseInsensitiveCompare(wanted) == .orderedSame else { break }
                    matches.formUnion(entry.rows)
                }
                return matches
            }
        }

        private func lowerBound(count: Int, isBefore: (Int) -> Bool) -> Int {
            var low = 0
            var high = count
            while low < high {
                let middle = low + (high - low) / 2
                if isBefore(middle) {
                    low = middle + 1
                } else {
                    high = middle
                }
            }
            return low
        }

        private func index<Key: Hashable>(_ key: (SmartQueueWorkFacts) -> Key) -> [Key: IndexSet] {
            var result: [Key: IndexSet] = [:]
            for (row, work) in facts.enumerated() {
                result[key(work), default: []].insert(row)
            }
            return result
        }

        private func fandomIndex() -> [(name: String, rows: IndexSet)] {
            var byName: [String: IndexSet] = [:]
            var canonical: [String: String] = [:]
            for (row, work) in facts.enumerated() {
                for name in work.fandoms {
                    let resolved: String
                    if let cached = canonical[name] {
                        resolved = cached
                    } else {
                        resolved = aliases.resolveIgnoringCase(name, kind: .fandom)
                        canonical[name] = resolved
                    }
                    if !resolved.isEmpty { byName[resolved, default: []].insert(row) }
                }
            }
            return byName.sorted { $0.key.caseInsensitiveCompare($1.key) == .orderedAscending }
                .map { (name: $0.key, rows: $0.value) }
        }

        private func order(for sort: SmartQueueDocument.Sort) -> [Int] {
            if let cached = otherOrders[sort] { return cached }
            // Start in input order so the stable sort keeps original ties.
            let order = rowsInInputOrder.sorted { left, right in
                let lhs = facts[left]
                let rhs = facts[right]
                switch sort {
                case .shortestFirst:
                    return Self.lengthOrder(lhs, rhs, longest: false)
                case .longestFirst:
                    return Self.lengthOrder(lhs, rhs, longest: true)
                case .recentlyAdded:
                    if lhs.dateAdded != rhs.dateAdded { return lhs.dateAdded > rhs.dateAdded }
                    return Self.titleOrder(lhs, rhs)
                case .title:
                    return Self.titleOrder(lhs, rhs)
                }
            }
            otherOrders[sort] = order
            return order
        }

        private static func lengthOrder(_ lhs: SmartQueueWorkFacts, _ rhs: SmartQueueWorkFacts, longest: Bool) -> Bool {
            let lhsUnknown = lhs.wordCount <= 0
            let rhsUnknown = rhs.wordCount <= 0
            if lhsUnknown != rhsUnknown { return rhsUnknown }
            if !lhsUnknown, lhs.wordCount != rhs.wordCount {
                return longest ? lhs.wordCount > rhs.wordCount : lhs.wordCount < rhs.wordCount
            }
            return titleOrder(lhs, rhs)
        }

        private static func titleOrder(_ lhs: SmartQueueWorkFacts, _ rhs: SmartQueueWorkFacts) -> Bool {
            let compared = lhs.title.localizedStandardCompare(rhs.title)
            if compared != .orderedSame { return compared == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
