import SwiftData
import SwiftUI

/// The shelf's own glyph. The colour is identity, the same way a queue's colour
/// is, and never the colour of a control.
struct LibraryShelfGlyph: View {
    var systemImage: String
    var identityHex: String
    var diameter: CGFloat

    init(shelf: LibraryShelfID, diameter: CGFloat = 30) {
        self.systemImage = shelf.systemImage
        self.identityHex = shelf.identityHex
        self.diameter = diameter
    }

    init(systemImage: String, identityHex: String, diameter: CGFloat = 30) {
        self.systemImage = systemImage
        self.identityHex = identityHex
        self.diameter = diameter
    }

    static func allWorks(diameter: CGFloat = 30) -> LibraryShelfGlyph {
        LibraryShelfGlyph(
            systemImage: LibraryShelfID.allWorksSystemImage,
            identityHex: LibraryShelfID.allWorksIdentityHex,
            diameter: diameter
        )
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: diameter * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .background {
                Circle().fill(Color(hex: identityHex) ?? Color.gray)
            }
            .accessibilityHidden(true)
    }
}

extension ReaderTheme {
    /// The grey 16 pt tile surface for Library shelf buttons (T-498).
    /// Grey (#F2F2F7) on Light's white content ground; elevated card surface in Sepia/Dark/OLED.
    var shelfTileSurface: Color {
        switch self {
        case .light:
            #if os(iOS)
            Color(uiColor: .systemGroupedBackground)
            #else
            Color(nsColor: .underPageBackgroundColor)
            #endif
        case .sepia, .dark, .oled:
            cardSurface
        }
    }
}

/// One 16 pt grey shelf tile on the Library dashboard (T-498).
///
/// Reminders-style layout: a 30 pt coloured circle with a solid white glyph,
/// tabular-figured count top-right, and the shelf label below.
struct LibraryShelfTile: View {
    var shelf: LibraryShelfID
    var count: Int

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                LibraryShelfGlyph(shelf: shelf)
                Spacer(minLength: 8)
                Text(count.compactCount)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 2)
            Text(shelf.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(themeManager.appTheme.shelfTileSurface)
        }
    }
}

/// The Shelves grid: one button per shelf that is not a section. The count
/// stays on the tile. Edit opens the sheet that moves shelves between the
/// page and this grid.
struct LibraryShelfButtonGrid: View {
    var buttons: [LibraryShelfID]
    var counts: [LibraryShelfID: Int]
    var onEdit: () -> Void
    var onOpen: (LibraryShelfID) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// Pure layout logic for responsive column count across compact (2 columns),
    /// accessibility size (1 column), and regular width / Duo 669 display (3 columns).
    static func columnCount(isAccessibilitySize: Bool, isRegularWidth: Bool) -> Int {
        if isAccessibilitySize { return 1 }
        return isRegularWidth ? 3 : 2
    }

    private var columns: [GridItem] {
        let isRegular: Bool
        #if os(iOS)
        isRegular = horizontalSizeClass == .regular
        #else
        isRegular = true
        #endif
        let count = Self.columnCount(
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
            isRegularWidth: isRegular
        )
        return (0..<count).map { _ in GridItem(.flexible(), spacing: 10) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionRuleHeader(
                title: "Shelves",
                actionTitle: "Edit",
                onSeeAll: onEdit
            )

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(buttons) { shelf in
                    Button {
                        onOpen(shelf)
                    } label: {
                        LibraryShelfTile(shelf: shelf, count: counts[shelf] ?? 0)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(shelf.title), \(counts[shelf] ?? 0)")
                    .accessibilityHint("Opens the \(shelf.title) shelf")
                }
            }
            .padding(.horizontal, SubjectMetrics.gutter)
        }
    }
}

/// A queue as a ledger row: the name, how many works, where the reader is in
/// it, what is kept offline, its tags and its note. The carousel card keeps
/// the short footer; this is the list's fuller line.
struct LibraryQueueLedgerRow: View {
    let queue: ReadingQueue

    @Environment(ThemeManager.self) private var themeManager
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 17
    @ScaledMetric(relativeTo: .footnote) private var detailSize: CGFloat = 13

    var body: some View {
        let works = ReadingQueueService.orderedWorks(in: queue)
        let states = works.map(\.readingState)
        let progress = ReadingQueueFacts.progress(of: states)
        let preserved = works.filter { $0.hasEPUB && FileManager.default.fileExists(atPath: $0.fileURL.path) }
        let legend = ReadingQueueFacts.legend(progress, offlineCount: preserved.count)
        let tags = queue.tags.map(\.name).sorted()
        let note = queue.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let identity = queue.colorHex.flatMap(Color.init(hex:))
            ?? Color(hue: queue.displayHue, saturation: 0.55, brightness: 0.72)

        return HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(identity)
                .frame(width: 10, height: 10)
                .padding(.top, 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(queue.displayName)
                        .font(.system(size: titleSize, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(works.count.compactCount)
                        .font(.system(size: detailSize, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(ReadingQueueFacts.cardFooter(states: states))
                    .font(.system(size: detailSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(legend)
                    .font(.system(size: detailSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !tags.isEmpty {
                    Text(tags.joined(separator: " · "))
                        .font(.system(size: detailSize))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !note.isEmpty {
                    Text(note)
                        .font(.system(size: detailSize))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .fill(themeManager.appTheme.cardSurface)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A list-style shelf on the dashboard. Same collapse key as that shelf's
/// carousel, so folding it survives a switch between Carousel and List.
struct LibraryCollapsingShelf<Content: View>: View {
    var title: String
    var count: Int
    var countText: String?
    var actionTitle: String?
    var onSeeAll: (() -> Void)?
    @ViewBuilder var content: () -> Content

    init(
        title: String,
        count: Int,
        countText: String? = nil,
        actionTitle: String? = nil,
        onSeeAll: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.count = count
        self.countText = countText
        self.actionTitle = actionTitle
        self.onSeeAll = onSeeAll
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionRuleHeader(
                title: title,
                count: count,
                countText: countText,
                actionTitle: actionTitle ?? (onSeeAll != nil ? "See All" : nil),
                onSeeAll: onSeeAll
            )
            content()
        }
    }
}
