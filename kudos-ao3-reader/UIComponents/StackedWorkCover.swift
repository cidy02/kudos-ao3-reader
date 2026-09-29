import SwiftUI

/// Spec 1c's collection tile: a 2×2 grid of the first four works, with faint
/// placeholders for empty slots. The historical name remains because this is the
/// shared collection-cover component; no other screen uses it.
struct StackedWorkCover: View {
    let works: [SavedWork]
    var cardSize = ScaledCarouselCardSize()

    @Environment(ThemeManager.self) private var themeManager

    private var scale: CGFloat {
        cardSize.width / CarouselCardMetrics.width
    }

    private var tileHeight: CGFloat {
        221 * scale
    }

    private var visibleWorks: [SavedWork] {
        Array(works.prefix(4))
    }

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: CarouselCardMetrics.cornerRadius * scale,
            style: .continuous
        )
        VStack(spacing: 7 * scale) {
            HStack(spacing: 7 * scale) {
                cell(at: 0)
                cell(at: 1)
            }
            HStack(spacing: 7 * scale) {
                cell(at: 2)
                cell(at: 3)
            }
        }
        .padding(10 * scale)
        .frame(width: cardSize.width, height: tileHeight)
        .background(shape.fill(themeManager.appTheme.glassFill(0.06)))
        .overlay(shape.strokeBorder(themeManager.appTheme.glassStroke(0.07), lineWidth: 0.5 * scale))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func cell(at index: Int) -> some View {
        if visibleWorks.indices.contains(index) {
            workCell(visibleWorks[index])
        } else {
            placeholderCell
        }
    }

    private func workCell(_ work: SavedWork) -> some View {
        let hue = CoverArt.workHue(fandoms: work.workFandoms, title: work.title)
        let palette = themeManager.appTheme.subjectPalette(hue: hue)
        let shape = RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(palette.accent)
                .frame(width: 14 * scale, height: 2 * scale)
                .padding(.bottom, 6 * scale)
            Text(work.title)
                .font(.system(size: 9.5 * scale, weight: .semibold))
                .foregroundStyle(themeManager.appTheme.isDarkFamily ? Color.white.opacity(0.92) : .primary)
                .lineLimit(2)
            Spacer(minLength: 4 * scale)
            HStack(spacing: 3 * scale) {
                Image(systemName: "person")
                    .font(.system(size: 7 * scale))
                Text(work.author)
                    .font(.system(size: 8.5 * scale))
                    .lineLimit(1)
            }
            .foregroundStyle(themeManager.appTheme.isDarkFamily ? Color.white.opacity(0.62) : .secondary)
        }
        .padding(.vertical, 6 * scale)
        .padding(.horizontal, 7 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(shape.fill(palette.cardWash))
        .overlay(shape.strokeBorder(themeManager.appTheme.glassStroke(0.10), lineWidth: 0.5 * scale))
        .clipShape(shape)
    }

    private var placeholderCell: some View {
        let shape = RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
        return shape
            .fill(themeManager.appTheme.glassFill(0.04))
            .overlay(shape.strokeBorder(themeManager.appTheme.glassStroke(0.06), lineWidth: 0.5 * scale))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
