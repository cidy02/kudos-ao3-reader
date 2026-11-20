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
            let top = (regions.barStatusBottom > 0 ? regions.barStatusBottom : safe.top) + railTopGap
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
        .padding(axis == .vertical ? .vertical : .horizontal, 2)
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
        VStack(spacing: 10) {
            ReaderDuoCloseButton(diameter: 48, action: onClose)
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
