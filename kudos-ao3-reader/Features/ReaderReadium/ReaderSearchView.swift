#if os(iOS)
import ReadiumShared
import SwiftUI
import UIKit

/// Drives Readium's own search service for "Find in Work".
///
/// Results arrive a page at a time from a `SearchIterator`, so this loads the
/// first page eagerly and then more on demand as the list is scrolled — a long
/// AO3 work can match thousands of times and materialising them all would stall
/// the sheet.
///
/// **Only ever one iterator call may be in flight.** Readium's search iterator
/// is a plain class with mutable scan state, not an actor, and `next()` is
/// `nonisolated async`, so awaiting it hops off the main actor. Two overlapping
/// calls therefore run its string/lookahead buffers concurrently and corrupt the
/// heap — observed as a `SIGSEGV` inside `_StringGuts.append` with three threads
/// simultaneously inside `next()`. That happened because `Task {}` does not run
/// synchronously: several row `.onAppear` callbacks in a single runloop turn all
/// cleared a boolean guard before any of them had set it. The in-flight task is
/// therefore recorded *synchronously* on the main actor in `startPageLoad`,
/// which closes that window, and every path funnels through it.
///
/// **Results stream in strict document order, batched per resource.** For a
/// common term, "This Chapter"'s own hits can sit behind hundreds of earlier
/// ones and never load without the reader scrolling that far — Readium's
/// `SearchOptions` has no chapter-scoping to search just one resource first.
/// So once `currentChapterHrefKey` is set, page loads auto-continue (not
/// waiting for scroll) until a batch covering that chapter has been seen, or
/// `maxAutoPages` is hit — bounded so a huge work whose current chapter is very
/// deep (or that simply has no match there) can't auto-page indefinitely.
@MainActor
@Observable
final class ReaderSearchModel {
    struct Result: Identifiable {
        let id: Int
        let locator: Locator
        /// Context leading up to the match, clipped to its tail. Readium hands
        /// back a whole sentence or more, and an unclipped `before` pushes the
        /// match itself past the row's line limit — rows then show none of the
        /// term that was searched for.
        var before: String {
            let full = locator.text.before ?? ""
            guard full.count > Self.leadingContextLimit else { return full }
            return "…" + full.suffix(Self.leadingContextLimit)
        }

        private static let leadingContextLimit = 70
        var match: String { locator.text.highlight ?? "" }
        var after: String { locator.text.after ?? "" }
        /// Section title if the locator carries one, else empty.
        var title: String { locator.title ?? "" }

        /// Full passage for the **Copy** action — deliberately *not* `before`,
        /// which prepends a display-only "…" once the leading context is
        /// clipped. That glyph doesn't exist in the book's own text, so
        /// copying `before` and pasting it back into the search bar (a real
        /// thing people do to jump straight to a passage) reliably found
        /// nothing: the pasted string could never appear as a substring of
        /// anything Readium actually indexed.
        var copyText: String {
            (locator.text.before ?? "") + match + after
        }
    }

    enum Phase: Equatable {
        case idle
        case searching
        /// Finished with at least one result, or finished empty.
        case done(isEmpty: Bool)
        case failed(String)
    }

    private(set) var results: [Result] = []
    private(set) var phase: Phase = .idle
    /// True while another page is being fetched, so the list can show a spinner
    /// at the bottom without replacing what's already visible.
    private(set) var isLoadingMore = false
    /// True once a batch has been seen containing a hit in
    /// `currentChapterHrefKey` — meaning if that chapter has any matches at
    /// all, they've been loaded. Also true immediately when there's no current
    /// chapter to look for.
    private(set) var hasCoveredCurrentChapter = true

    /// The reader's live chapter, normalized the same way
    /// `ReaderSearchGrouping` matches results to sections
    /// (`ReaderSectionBuilder.hrefKey`). Set alongside each `search()` call —
    /// see the type doc for why this drives auto-paging.
    var currentChapterHrefKey: String?

    private var iterator: SearchIterator?
    private var searchTask: Task<Void, Never>?
    /// The single in-flight page fetch. Non-nil means the iterator is busy.
    private var pageTask: Task<Void, Never>?
    private var reachedEnd = false
    private var autoPagesFetched = 0
    /// Chapters' worth of batches auto-paged trying to reach the current
    /// chapter before giving up and falling back to scroll-driven paging.
    private static let maxAutoPages = 40

    /// True while auto-paging ahead specifically to find "This Chapter"'s own
    /// hits — the results list uses this to show a "Searching this chapter…"
    /// placeholder where that group will land, rather than looking like the
    /// current chapter simply has no matches while it's still loading.
    var isSearchingCurrentChapter: Bool {
        currentChapterHrefKey != nil && !hasCoveredCurrentChapter && !reachedEnd
    }

    /// Whether this publication supports search at all. Readium synthesises a
    /// content-based service for EPUBs, but a publication without one should
    /// disable the control rather than silently return nothing.
    static func isSearchable(_ publication: Publication?) -> Bool {
        publication?.isSearchable ?? false
    }

    func search(_ query: String, in publication: Publication?) {
        // Drop the old search *and* any page fetch still running against the
        // previous iterator before building a new one. `reset()` would also
        // clear `currentChapterHrefKey`, which the caller just set for *this*
        // search — so it's preserved across the reset explicitly.
        let chapterKey = currentChapterHrefKey
        reset()
        currentChapterHrefKey = chapterKey
        hasCoveredCurrentChapter = chapterKey == nil
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let publication, !trimmed.isEmpty else { return }

        phase = .searching
        searchTask = Task { [weak self] in
            let outcome = await publication.search(query: trimmed)
            guard !Task.isCancelled, let self else { return }
            switch outcome {
            case let .success(iterator):
                self.iterator = iterator
                self.startPageLoad(initial: true)
            case let .failure(error):
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Asks for the next page once the list is within a few rows of the end.
    /// No-ops while a fetch is already in flight or the iterator is exhausted.
    func loadMoreIfNeeded(currentItem: Result?) {
        guard let currentItem, !reachedEnd, pageTask == nil, phase != .searching else { return }
        // `id` is the append index, so this is O(1) — scanning `results` for a
        // UUID would be O(n) per row and quadratic over a long result set.
        guard currentItem.id >= results.count - 5 else { return }
        startPageLoad(initial: false)
    }

    func reset() {
        searchTask?.cancel()
        searchTask = nil
        pageTask?.cancel()
        pageTask = nil
        iterator = nil
        results = []
        reachedEnd = false
        isLoadingMore = false
        phase = .idle
        currentChapterHrefKey = nil
        hasCoveredCurrentChapter = true
        autoPagesFetched = 0
    }

    /// Starts a page fetch, recording the task synchronously so a second caller
    /// in the same runloop turn cannot start an overlapping one.
    private func startPageLoad(initial: Bool) {
        guard pageTask == nil, !reachedEnd, iterator != nil else { return }
        isLoadingMore = !initial
        pageTask = Task { [weak self] in
            await self?.loadNextPage(initial: initial)
            self?.pageTask = nil
            self?.isLoadingMore = false
            self?.continueAutoPagingIfNeeded()
        }
    }

    /// Keeps paging — ahead of any scroll — while the current chapter's own
    /// hits still haven't turned up, up to `maxAutoPages`.
    private func continueAutoPagingIfNeeded() {
        guard !hasCoveredCurrentChapter, !reachedEnd, pageTask == nil,
              autoPagesFetched < Self.maxAutoPages
        else { return }
        autoPagesFetched += 1
        startPageLoad(initial: false)
    }

    private func loadNextPage(initial: Bool) async {
        guard let iterator else { return }

        switch await iterator.next() {
        case let .success(collection):
            // A newer search may have replaced the iterator while this was
            // suspended; its results must not be mixed into the new list.
            guard !Task.isCancelled, self.iterator === iterator else { return }
            guard let collection, !collection.locators.isEmpty else {
                reachedEnd = true
                phase = .done(isEmpty: results.isEmpty)
                return
            }
            let base = results.count
            let newResults = collection.locators.enumerated().map { offset, locator in
                Result(id: base + offset, locator: locator)
            }
            results.append(contentsOf: newResults)
            if let currentChapterHrefKey, !hasCoveredCurrentChapter,
               newResults.contains(where: {
                   ReaderSectionBuilder.hrefKey($0.locator.href.string) == currentChapterHrefKey
               })
            {
                hasCoveredCurrentChapter = true
            }
            phase = .done(isEmpty: results.isEmpty)
        case let .failure(error):
            guard !Task.isCancelled, self.iterator === iterator else { return }
            // An initial failure is worth surfacing; a mid-scroll one just stops
            // paging rather than throwing away results already on screen.
            if initial || results.isEmpty {
                phase = .failed(error.localizedDescription)
            }
            reachedEnd = true
        }
    }
}

/// The Find in Work sheet: a search field over Readium's search service, and a
/// result list that jumps to the tapped locator.
struct ReaderSearchView: View {
    @Bindable var model: ReaderSearchModel
    let publication: Publication?
    let sections: [ReaderSection]
    /// The reader's live chapter, for grouping the current chapter's hits under
    /// "This Chapter" ahead of the rest.
    let currentSpineIndex: Int?
    let onSelect: (Locator) -> Void
    let onBookmark: (Locator) -> Void

    @State private var query = ""
    @State private var debounceTask: Task<Void, Never>?
    @FocusState private var isFieldFocused: Bool

    /// Waits out a short pause in typing before hitting the search service —
    /// each keystroke would otherwise start (and immediately cancel) a full
    /// publication scan.
    private func scheduleSearch(_ text: String) {
        debounceTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            model.reset()
            return
        }
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            runSearch(trimmed)
        }
    }

    /// `book.sections`-basis href for the reader's live chapter — the same key
    /// `ReaderSearchGrouping` matches results against, so the model's
    /// auto-paging and the view's grouping agree on "which chapter is current".
    private var currentChapterHrefKey: String? {
        guard let currentSpineIndex else { return nil }
        return sections.first { $0.spineIndex == currentSpineIndex }
            .map { ReaderSectionBuilder.hrefKey($0.href) }
    }

    private func runSearch(_ text: String) {
        model.currentChapterHrefKey = currentChapterHrefKey
        model.search(text, in: publication)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            content
        }
        .onAppear { isFieldFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find in Work", text: $query)
                .focused($isFieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                // Searches as you type (debounced), like Apple Books, so results
                // appear without a trip to the Return key. `.onSubmit` is kept for
                // people who do press it, but it only re-runs the same query.
                .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
                .onSubmit { runSearch(query) }
            if !query.isEmpty {
                Button {
                    query = ""
                    model.reset()
                    isFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView(
                "Find in Work", systemImage: "magnifyingglass",
                description: Text("Search this work's text. Results jump straight to the passage.")
            )
        case .searching:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView(
                "Couldn't Search", systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case let .done(isEmpty):
            if isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                resultList
            }
        }
    }

    /// Current chapter's hits first, then the rest by chapter, most recent
    /// chapter first. Recomputed on every `model.results` growth (pagination) —
    /// fine at the result counts a single work's text search produces.
    private var groupedResults: [ReaderSearchGrouping.Group<ReaderSearchModel.Result>] {
        ReaderSearchGrouping.grouped(
            model.results,
            hrefKey: { ReaderSectionBuilder.hrefKey($0.locator.href.string) },
            sections: sections,
            currentSpineIndex: currentSpineIndex
        )
    }

    /// True once "This Chapter" (if it has any hits) has actually landed as the
    /// first group — not just once the model reports it's still trying.
    private var isCurrentChapterGroupPending: Bool {
        model.isSearchingCurrentChapter && groupedResults.first?.spineIndex != currentSpineIndex
    }

    private var resultList: some View {
        List {
            if isCurrentChapterGroupPending {
                Section("This Chapter") {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Searching…")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(groupedResults) { group in
                Section(group.title) {
                    ForEach(group.results) { result in
                        resultRow(result)
                            // `.onAppear` keys off the flat append order (`result.id`),
                            // not display order, since grouping reorders chapters —
                            // this still fires once we've rendered results from near
                            // the end of what's loaded so far, regardless of which
                            // chapter section they land in.
                            .onAppear { model.loadMoreIfNeeded(currentItem: result) }
                    }
                }
            }
            if model.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .listStyle(.plain)
    }

    private func resultRow(_ result: ReaderSearchModel.Result) -> some View {
        Button {
            onSelect(result.locator)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                if !result.title.isEmpty {
                    Text(result.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                }
                // The match itself is emphasised inside its surrounding sentence, so
                // a result is readable in context rather than as a bare keyword.
                (Text(result.before).foregroundStyle(.secondary)
                    + Text(result.match).bold()
                    + Text(result.after).foregroundStyle(.secondary))
                    .font(.callout)
                    // Roomy enough to show real context either side of the match
                    // rather than a keyword stranded on its own line.
                    .lineLimit(5)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            // Full swipe defaults to the first action — Go, matching the tap.
            Button {
                onSelect(result.locator)
            } label: {
                Label("Go", systemImage: "arrow.forward.circle")
            }
            .tint(.accentColor)

            Button {
                onBookmark(result.locator)
            } label: {
                Label("Bookmark", systemImage: "bookmark")
            }
            .tint(.orange)

            Button {
                UIPasteboard.general.string = result.copyText
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .tint(.gray)
        }
    }
}
#endif
