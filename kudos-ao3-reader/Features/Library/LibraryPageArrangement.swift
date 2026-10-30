import Foundation

/// One shelf the reader can put on the Library page or in the Shelves grid.
///
/// All Works is not a shelf. It stays in the header. Want to Read is the
/// Saved for Later queue; the page uses the export's name.
nonisolated enum LibraryShelfID: String, Codable, CaseIterable, Identifiable, Sendable {
    case favourites
    case collections
    case downloaded
    case wantToRead
    case readingNow
    case finished
    case queues
    case history
    case imported

    var id: String { rawValue }

    /// The export's names. Favorites is "Favourites", Saved for Later is
    /// "Want to Read", and Reading History is "History" on this page.
    var title: String {
        switch self {
        case .favourites: "Favourites"
        case .collections: "Collections"
        case .downloaded: "Downloaded"
        case .wantToRead: "Want to Read"
        case .readingNow: "Reading Now"
        case .finished: "Finished"
        case .queues: "Queues"
        case .history: "History"
        case .imported: "Imported"
        }
    }

    /// Identity glyph for the shelf tile and the edit row. Not a control colour.
    var systemImage: String {
        switch self {
        case .favourites: "star.fill"
        case .collections: "rectangle.stack.fill"
        case .downloaded: "arrow.down"
        case .wantToRead: "bookmark.fill"
        case .readingNow: "book.fill"
        case .finished: "checkmark"
        case .queues: "list.bullet"
        case .history: "clock.fill"
        case .imported: "doc.fill"
        }
    }

    /// Reminders-style identity colour from the Library board. Controls stay
    /// on the app accent; this paint is only the shelf's own glyph.
    var identityHex: String {
        switch self {
        case .favourites: "#E0A100"
        case .collections: "#9C2F6B"
        case .downloaded: "#5856D6"
        case .wantToRead: "#1E63C8"
        case .readingNow: "#E07000"
        case .finished: "#2F8F3A"
        case .queues: "#7B3FA0"
        case .history: "#6C6C70"
        case .imported: "#6C6C70"
        }
    }

    /// A work belongs on Imported when it did not come from AO3 and it is not
    /// only a queue entry. Other sites and files with no source URL count.
    static func isImported(origin: WorkOrigin, isQueueOnly: Bool) -> Bool {
        !isQueueOnly && origin != .archiveOfOurOwn
    }
}

/// Carousel or ledger rows. A shelf that is a button does not store a style;
/// putting it on the page starts as a carousel.
nonisolated enum LibrarySectionStyle: String, Codable, CaseIterable, Sendable {
    case carousel
    case list

    var title: String {
        switch self {
        case .carousel: "Carousel"
        case .list: "List"
        }
    }
}

nonisolated struct LibraryPageSection: Codable, Equatable, Identifiable, Sendable {
    var id: LibraryShelfID
    var style: LibrarySectionStyle
}

/// Which shelves are sections, in order, and which are buttons, in order.
///
/// The two lists partition every shelf: each shelf is in exactly one. Anything
/// not stored is repaired onto the button list, in `LibraryShelfID` order.
/// An unknown id is dropped. A shelf named in both lists stays a section.
nonisolated struct LibraryPageArrangement: Codable, Equatable, Sendable, RawRepresentable {
    var sections: [LibraryPageSection]
    var buttons: [LibraryShelfID]

    static let storageKey = "library.page.arrangement"

    /// Favourites, Collections, Downloaded as carousels. Everything else is a
    /// button, in the Library board's order.
    static let `default` = LibraryPageArrangement(
        sections: [
            LibraryPageSection(id: .favourites, style: .carousel),
            LibraryPageSection(id: .collections, style: .carousel),
            LibraryPageSection(id: .downloaded, style: .carousel)
        ],
        buttons: [.wantToRead, .readingNow, .finished, .queues, .history, .imported]
    )

    init(sections: [LibraryPageSection], buttons: [LibraryShelfID]) {
        let partition = Self.partition(sections: sections, buttons: buttons)
        self.sections = partition.sections
        self.buttons = partition.buttons
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sections = try container.decodeIfPresent([FailableSection].self, forKey: .sections) ?? []
        let buttons = try container.decodeIfPresent([FailableShelf].self, forKey: .buttons) ?? []
        self.init(
            sections: sections.compactMap(\.section),
            buttons: buttons.compactMap(\.id)
        )
    }

    /// UserDefaults string. Nil when the string is not this arrangement, so
    /// `@AppStorage` falls back to `default` instead of drawing a broken page.
    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(LibraryPageArrangement.self, from: data) else {
            return nil
        }
        self = decoded
    }

    var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    static func stored(in defaults: UserDefaults) -> LibraryPageArrangement {
        guard let raw = defaults.string(forKey: storageKey) else { return .default }
        return LibraryPageArrangement(rawValue: raw) ?? .default
    }

    func style(of id: LibraryShelfID) -> LibrarySectionStyle? {
        sections.first { $0.id == id }?.style
    }

    /// Take a section off the page and append it to the shelf buttons.
    func removingFromPage(_ id: LibraryShelfID) -> LibraryPageArrangement {
        guard sections.contains(where: { $0.id == id }) else { return self }
        return LibraryPageArrangement(
            sections: sections.filter { $0.id != id },
            buttons: buttons + [id]
        )
    }

    /// Put a button on the page, at the end, as a carousel.
    func addingToPage(_ id: LibraryShelfID) -> LibraryPageArrangement {
        guard buttons.contains(id), style(of: id) == nil else { return self }
        return LibraryPageArrangement(
            sections: sections + [LibraryPageSection(id: id, style: .carousel)],
            buttons: buttons.filter { $0 != id }
        )
    }

    func settingStyle(_ id: LibraryShelfID, to style: LibrarySectionStyle) -> LibraryPageArrangement {
        guard sections.contains(where: { $0.id == id }) else { return self }
        return LibraryPageArrangement(
            sections: sections.map { $0.id == id ? LibraryPageSection(id: id, style: style) : $0 },
            buttons: buttons
        )
    }

    func movingSections(from offsets: IndexSet, to destination: Int) -> LibraryPageArrangement {
        LibraryPageArrangement(
            sections: Self.moved(sections, from: offsets, to: destination),
            buttons: buttons
        )
    }

    func movingButtons(from offsets: IndexSet, to destination: Int) -> LibraryPageArrangement {
        LibraryPageArrangement(
            sections: sections,
            buttons: Self.moved(buttons, from: offsets, to: destination)
        )
    }

    /// "214 works". One stays singular.
    static func workCountPhrase(_ count: Int) -> String {
        "\(count) work\(count == 1 ? "" : "s")"
    }

    /// The line under the Library title. `byteText` is the formatted size of
    /// the downloaded copies, so this function stays free of the formatter.
    static func headerTally(works: Int, downloaded: Int, byteText: String) -> String {
        "\(workCountPhrase(works)) · \(downloaded) downloaded · \(byteText)"
    }

    /// Same move `List.onMove` uses: `destination` is an index in the original
    /// list, pointing at the gap the items are dropped into.
    static func moved<Element>(_ items: [Element], from offsets: IndexSet, to destination: Int) -> [Element] {
        guard !offsets.isEmpty, offsets.allSatisfy({ items.indices.contains($0) }) else { return items }
        var result = items
        let moving = offsets.sorted().map { items[$0] }
        for index in offsets.sorted(by: >) {
            result.remove(at: index)
        }
        let shift = offsets.filter { $0 < destination }.count
        let index = min(max(destination - shift, 0), result.count)
        result.insert(contentsOf: moving, at: index)
        return result
    }

    private static func partition(
        sections: [LibraryPageSection],
        buttons: [LibraryShelfID]
    ) -> (sections: [LibraryPageSection], buttons: [LibraryShelfID]) {
        var seen = Set<LibraryShelfID>()
        var keptSections: [LibraryPageSection] = []
        for section in sections where seen.insert(section.id).inserted {
            keptSections.append(section)
        }
        var keptButtons: [LibraryShelfID] = []
        for id in buttons where seen.insert(id).inserted {
            keptButtons.append(id)
        }
        for id in LibraryShelfID.allCases where seen.insert(id).inserted {
            keptButtons.append(id)
        }
        return (keptSections, keptButtons)
    }

    private enum CodingKeys: String, CodingKey {
        case sections
        case buttons
    }

    /// A section whose id or style this build does not know is skipped, rather
    /// than failing the whole arrangement.
    private struct FailableSection: Decodable {
        var section: LibraryPageSection?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let id = try container.decodeIfPresent(FailableShelf.self, forKey: .id)?.id
            let styleRaw = try container.decodeIfPresent(String.self, forKey: .style)
            if let id {
                section = LibraryPageSection(
                    id: id,
                    style: styleRaw.flatMap(LibrarySectionStyle.init(rawValue:)) ?? .carousel
                )
            } else {
                section = nil
            }
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case style
        }
    }

    private struct FailableShelf: Decodable {
        var id: LibraryShelfID?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = try? container.decode(String.self)
            id = raw.flatMap(LibraryShelfID.init(rawValue:))
        }
    }
}
