import SwiftData
import SwiftUI

/// The shelf's own glyph. The colour is identity, the same way a queue's colour
/// is, and never the colour of a control.
struct LibraryShelfGlyph: View {
    var shelf: LibraryShelfID
    var diameter: CGFloat = 30

    var body: some View {
        Image(systemName: shelf.systemImage)
            .font(.system(size: diameter * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .background {
                Circle().fill(Color(hex: shelf.identityHex) ?? Color.gray)
            }
            .accessibilityHidden(true)
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
    @Environment(ThemeManager.self) private var themeManager
    @ScaledMetric(relativeTo: .caption2) private var labelSize: CGFloat = 11

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            [GridItem(.flexible())]
        } else {
            [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("SHELVES")
                    .font(.system(size: min(labelSize, 22), weight: .bold))
                    .tracking(min(labelSize, 22) * 0.127)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button("Edit", action: onEdit)
                    .font(.body)
                    .foregroundStyle(.accentFill)
                    .accessibilityHint("Choose which shelves are sections, and carousel or list")
            }
            .padding(.horizontal, SubjectMetrics.gutter)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(buttons) { shelf in
                    Button {
                        onOpen(shelf)
                    } label: {
                        tile(shelf)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(shelf.title), \(counts[shelf] ?? 0)")
                }
            }
            .padding(.horizontal, SubjectMetrics.gutter)
        }
    }

    private func tile(_ shelf: LibraryShelfID) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                LibraryShelfGlyph(shelf: shelf)
                Spacer(minLength: 8)
                Text((counts[shelf] ?? 0).compactCount)
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            Text(shelf.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(themeManager.appTheme.cardSurface)
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
            RoundedRectangle(cornerRadius: SubjectMetrics.rowRadius, style: .continuous)
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
    var onSeeAll: (() -> Void)?
    @ViewBuilder var content: () -> Content

    @AppStorage private var collapsed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        collapseKey: String,
        count: Int,
        countText: String? = nil,
        onSeeAll: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.count = count
        self.countText = countText
        self.onSeeAll = onSeeAll
        self.content = content
        _collapsed = AppStorage(wrappedValue: false, "section.collapsed.\(collapseKey)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionRuleHeader(
                title: title,
                count: count,
                countText: countText,
                isCollapsed: collapsed,
                onToggleCollapse: {
                    withAnimationUnlessReduced(.snappy(duration: 0.22), reduceMotion: reduceMotion) {
                        collapsed.toggle()
                    }
                },
                onSeeAll: onSeeAll
            )
            if !collapsed {
                content()
            }
        }
    }
}
