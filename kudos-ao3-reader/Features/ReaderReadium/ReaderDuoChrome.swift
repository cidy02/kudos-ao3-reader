#if os(iOS)
import SwiftUI
import UIKit

/// Which set of reader bars the host's layout calls for (T-562a, Duo boards).
///
/// Decided from the host's traits and reserved regions, never from the device:
/// - `.rail` when the system puts its bars on a side edge (`verticalBarEdge`): the
///   iPhone Duo's cover and its inner screen in landscape, flat or in Book pose.
/// - `.foldTopBar` when the screen has a fold (active or not) but its bars run along
///   the top: the Duo's inner screen in portrait.
/// - `.standard` everywhere else: the iPhone and iPad reader, unchanged.
nonisolated enum ReaderChromeLayout: Equatable, Sendable {
    case standard
    case rail(ReaderVerticalBar)
    case foldTopBar

    static func resolve(_ regions: ReaderHostRegions) -> Self {
        switch regions.verticalBar {
        case .left, .right: .rail(regions.verticalBar)
        case .none: regions.fold == nil ? .standard : .foldTopBar
        }
    }

    /// Themes & Settings opens as a panel by the Duo bars (T-562b); the iPhone and
    /// iPad keep the sheet.
    var showsSettingsAsPanel: Bool { self != .standard }

    /// The Duo held upright (inner portrait, the top bar) reads one page, like the
    /// portrait board, even with Two-page spread on (owner, 2026-11-20). The stored
    /// setting is untouched: the rail layouts and wide iPad layouts still use it.
    var allowsTwoPageSpread: Bool { self != .foldTopBar }

    /// Effective two-page spread input for `ReadiumReaderStyleMapper`: honours the
    /// stored setting and size class, gated by `allowsTwoPageSpread`.
    func effectiveTwoPageSpread(enabled: Bool, wideLayout: Bool) -> Bool {
        enabled && wideLayout && allowsTwoPageSpread
    }
}

/// Where the Duo chrome sits, in host points measured from the physical left and
/// right edges. Pure, so the board's numbers are testable without a device.
nonisolated struct ReaderDuoChromePlacement: Equatable, Sendable {
    /// `DuoSideBar`: a 64 pt column of 48 pt buttons.
    static let railWidth: CGFloat = 64
    /// Space between the rail and the position bar.
    static let railGap: CGFloat = 12
    /// Space between the fold and the position bar on the rail's page.
    static let foldGap: CGFloat = 8
    /// The bar's inset from a free screen edge, and the portrait bar's width.
    static let edgeInset: CGFloat = 16
    static let portraitBarWidth: CGFloat = 440
    /// Between the status block and the rail's Close button.
    static let railTopGap: CGFloat = 10
    /// The portrait top bar's 44 pt row and 8 pt under it, kept clear above the page.
    static let topBarReserve: CGFloat = 52
    /// The rail's Close circle, the gap under it, and the action group's end padding:
    /// together, how far below `railTop` the group's first button (Aa) starts.
    static let railCloseDiameter: CGFloat = 48
    static let railSpacing: CGFloat = 10
    static let groupEndPadding: CGFloat = 2
    /// Total height of the rail (Close + spacing + 5 action slots + group end padding).
    static let railHeight: CGFloat = railCloseDiameter + railSpacing + 5 * 44 + 2 * groupEndPadding

    /// From the rail's edge to the rail's centre: the middle of the system bar's column.
    var railCenterInset: CGFloat = 0
    var railTop: CGFloat = 0
    /// Position bar insets from the physical left and right edges.
    var barLeft: CGFloat = edgeInset
    var barRight: CGFloat = edgeInset

    /// - Parameters:
    ///   - safe: the page box's held insets (the bar edge is at least the rail).
    ///   - regions: the bar edge, its status block, and the fold.
    static func resolve(
        layout: ReaderChromeLayout, size: CGSize, safe: UIEdgeInsets, regions: ReaderHostRegions
    ) -> Self {
        switch layout {
        case .standard:
            return Self()
        case .foldTopBar:
            let available = max(0, size.width - safe.left - safe.right - 2 * edgeInset)
            let width = min(portraitBarWidth, available)
            let side = max(0, (size.width - width) / 2)
            return Self(barLeft: side, barRight: side)
        case let .rail(bar):
            let barInset = max(bar == .left ? safe.left : safe.right, ReaderPageBoxGeometry.verticalBarReserve)
            let center = barInset / 2
            let railSide = center + railWidth / 2 + railGap
            let unclampedTop = (regions.barStatusBottom > 0 ? regions.barStatusBottom : safe.top) + railTopGap
            // Never push the rail onto the bottom safe area (e.g. a fallback status
            // height carried over from a taller orientation on Cover landscape).
            let top = size.height > 1
                ? max(0, min(unclampedTop, size.height - safe.bottom - Self.railHeight))
                : unclampedTop
            // A vertical fold puts the bar on the rail's own page, clear of the crease.
            let fold = regions.fold.flatMap { $0.height > $0.width ? $0 : nil }
            switch bar {
            case .left:
                let right = fold.map { max(edgeInset, size.width - $0.minX + foldGap) } ?? edgeInset + safe.right
                return Self(railCenterInset: center, railTop: top, barLeft: railSide, barRight: right)
            case .right, .none:
                let left = fold.map { max(edgeInset, $0.maxX + foldGap) } ?? edgeInset + safe.left
                return Self(railCenterInset: center, railTop: top, barLeft: left, barRight: railSide)
            }
        }
    }
}

/// Where Themes & Settings opens in the Duo layouts (T-562b): a 360 pt panel, not a
/// sheet (`Duo-Open-Reader`, `showSettings`: right 84, top 150, width 360). Host points
/// from the physical left edge, like `ReaderDuoChromePlacement`.
///
/// - Rail: hugs the rail (the position bar's rail-side edge), top level with the Aa
///   button, on the rail's own page — never across a vertical fold. On the cover, which
///   has no fold, it runs to the free edge's margin, so its Done stays clear of the
///   status column the rail stands under.
/// - Portrait top bar: under the bar, trailing-aligned with it (so under Aa and the rest
///   of the group), and above a horizontal fold when that leaves the panel room.
nonisolated struct ReaderDuoSettingsPanelPlacement: Equatable, Sendable {
    static let width: CGFloat = 360
    static let cornerRadius: CGFloat = 24
    /// Below this the panel gives up the anchor (starts higher, or crosses the
    /// portrait fold) rather than show a sliver.
    static let minimumHeight: CGFloat = 280

    var left: CGFloat
    var top: CGFloat
    var width: CGFloat
    var height: CGFloat

    /// nil for `.standard`: the iPhone and iPad keep the sheet.
    /// - Parameters:
    ///   - chrome: the bars' placement for the same layout and size.
    ///   - chromeTop: the top safe inset the portrait bar sits under.
    static func resolve(
        layout: ReaderChromeLayout, chrome: ReaderDuoChromePlacement, size: CGSize,
        safe: UIEdgeInsets, regions: ReaderHostRegions, chromeTop: CGFloat,
        layoutDirection: LayoutDirection = .leftToRight
    ) -> Self? {
        let margin = ReaderDuoChromePlacement.edgeInset
        let foldGap = ReaderDuoChromePlacement.foldGap
        let screenBottom = size.height - max(margin, safe.bottom)
        var bottom = screenBottom
        let anchoredTop: CGFloat
        let leftLimit: CGFloat
        let rightLimit: CGFloat
        let hugsLeft: Bool
        switch layout {
        case .standard:
            return nil
        case let .rail(bar):
            anchoredTop = chrome.railTop + ReaderDuoChromePlacement.railCloseDiameter
                + ReaderDuoChromePlacement.railSpacing + ReaderDuoChromePlacement.groupEndPadding
            let fold = regions.fold.flatMap { $0.height > $0.width ? $0 : nil }
            hugsLeft = bar == .left
            if hugsLeft {
                leftLimit = chrome.barLeft
                rightLimit = fold.map { $0.minX - foldGap } ?? size.width - max(margin, safe.right)
            } else {
                leftLimit = fold.map { $0.maxX + foldGap } ?? max(margin, safe.left)
                rightLimit = size.width - chrome.barRight
            }
        case .foldTopBar:
            anchoredTop = chromeTop + ReaderDuoChromePlacement.topBarReserve
            // In RTL `ReaderDuoTopBar` places the action group (Aa) on the physical left.
            hugsLeft = layoutDirection == .rightToLeft
            leftLimit = safe.left + margin
            rightLimit = size.width - safe.right - margin
            if let fold = regions.fold, fold.width >= fold.height,
               fold.minY - foldGap - anchoredTop >= minimumHeight {
                bottom = fold.minY - foldGap
            }
        }
        let width = max(0, min(Self.width, rightLimit - leftLimit))
        let top = bottom - anchoredTop >= minimumHeight
            ? anchoredTop
            : max(min(anchoredTop, bottom - minimumHeight), max(margin, safe.top))
        return Self(
            left: hugsLeft ? leftLimit : rightLimit - width, top: top,
            width: width, height: max(0, bottom - top)
        )
    }
}

/// The light scrim behind the Duo settings panel: a tap anywhere outside closes it.
/// Sits under the bars, so the rail's Aa still toggles the panel.
struct ReaderDuoPanelScrim: View {
    let onClose: () -> Void

    var body: some View {
        Button(action: onClose) {
            Color.black.opacity(0.14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .ignoresSafeArea()
        .accessibilityLabel("Dismiss")
    }
}

/// The Duo settings panel's card: the content (a navigation stack with its own Done)
/// clipped to the board's 24 pt corners, with its shadow. VoiceOver stays inside it;
/// the escape gesture closes it.
struct ReaderDuoSettingsPanel<Content: View>: View {
    let placement: ReaderDuoSettingsPanelPlacement
    let onClose: () -> Void
    @ViewBuilder var content: () -> Content

    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        GeometryReader { proxy in
            // Placement is physical; offset from the layout's leading edge.
            let leading = layoutDirection == .leftToRight
                ? placement.left : proxy.size.width - placement.left - placement.width
            content()
                .frame(width: placement.width, height: placement.height)
                .clipShape(RoundedRectangle(
                    cornerRadius: ReaderDuoSettingsPanelPlacement.cornerRadius, style: .continuous
                ))
                .shadow(color: .black.opacity(0.24), radius: 25, y: 18)
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape, onClose)
                .offset(x: leading, y: placement.top)
        }
        .ignoresSafeArea()
    }
}

/// One button of the Duo action group: Themes & Settings ("Aa"), Contents,
/// Bookmark, Read Aloud. Each wraps the reader's existing action.
struct ReaderDuoGroupItem: Identifiable {
    let id: String
    let accessibilityLabel: String
    var text: String?
    var systemImage = ""
    /// Pressed look (accent tint), e.g. a bookmarked page or Read Aloud running.
    var isOn = false
    var isEnabled = true
    let action: () -> Void
}

/// The group of reader actions in one glass capsule, then More. Vertical on the
/// rail, horizontal in the portrait top bar (`DuoSideBar` / `DuoTopBar`).
struct ReaderDuoActionGroup<More: View>: View {
    let axis: Axis
    let items: [ReaderDuoGroupItem]
    /// The reader's accent ink, for pressed buttons.
    let tint: Color
    @ViewBuilder var more: () -> More

    static var railButtonSize: CGSize { CGSize(width: 48, height: 44) }
    static var barButtonSize: CGSize { CGSize(width: 44, height: 40) }

    private var buttonSize: CGSize {
        axis == .vertical ? Self.railButtonSize : Self.barButtonSize
    }

    var body: some View {
        let layout = axis == .vertical
            ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            ForEach(items) { item in
                Button(action: item.action) {
                    label(for: item)
                        .foregroundStyle(item.isOn ? tint : Color.primary)
                        .frame(width: buttonSize.width, height: buttonSize.height)
                        .background {
                            if item.isOn { Capsule().fill(tint.opacity(0.12)) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!item.isEnabled)
                .accessibilityLabel(item.accessibilityLabel)
                .accessibilityAddTraits(item.isOn ? [.isSelected] : [])
                .accessibilityShowsLargeContentViewer()
            }
            more()
        }
        .padding(axis == .vertical ? .vertical : .horizontal, ReaderDuoChromePlacement.groupEndPadding)
        .glassEffect(.regular, in: Capsule())
    }

    @ViewBuilder
    private func label(for item: ReaderDuoGroupItem) -> some View {
        if let text = item.text {
            Text(text).font(.system(size: 16, weight: .semibold))
        } else {
            Image(systemName: item.systemImage)
                .font(.system(size: 18, weight: .regular))
                .contentTransition(.symbolEffect(.replace))
        }
    }
}

/// Close, in its own glass circle (`DuoSideBar` / `DuoTopBar` nav = close).
struct ReaderDuoCloseButton: View {
    let diameter: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: Circle())
        .accessibilityLabel("Close reader")
        .accessibilityShowsLargeContentViewer()
    }
}

/// The trailing rail: Close, then the action group, under the system's status block.
struct ReaderDuoRail<More: View>: View {
    let items: [ReaderDuoGroupItem]
    let tint: Color
    let onClose: () -> Void
    @ViewBuilder var more: () -> More

    var body: some View {
        VStack(spacing: ReaderDuoChromePlacement.railSpacing) {
            ReaderDuoCloseButton(diameter: ReaderDuoChromePlacement.railCloseDiameter, action: onClose)
            ReaderDuoActionGroup(axis: .vertical, items: items, tint: tint, more: more)
        }
        .frame(width: ReaderDuoChromePlacement.railWidth)
    }
}

/// The inner screen's portrait bar: Close at the leading edge, the same actions at
/// the trailing edge, no title (`Duo-Portrait-Reader`).
struct ReaderDuoTopBar<More: View>: View {
    let items: [ReaderDuoGroupItem]
    let tint: Color
    let onClose: () -> Void
    @ViewBuilder var more: () -> More

    var body: some View {
        HStack(spacing: 10) {
            ReaderDuoCloseButton(diameter: 44, action: onClose)
            Spacer(minLength: 0)
            ReaderDuoActionGroup(axis: .horizontal, items: items, tint: tint, more: more)
        }
        .padding(.horizontal, ReaderChromeTopBar.edgeInset)
    }
}
#endif
