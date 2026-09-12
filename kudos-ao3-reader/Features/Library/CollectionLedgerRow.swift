import SwiftUI

/// Artboard 1d's collection ledger row: previews up to four miniature work covers
/// in a 2×2 grid beside the collection title, work count, and a trailing chevron.
///
/// Miniature covers respect the mature-content gate: works that fail `passesPrivacy`
/// (e.g. hidden adult content) are excluded so their covers are never shown here.
struct CollectionLedgerRow: View {
    @Environment(ThemeManager.self) private var themeManager
    let collection: WorkCollection
    let previewWorks: [SavedWork]

    private var totalWorkCount: Int {
        collection.works.filter { !$0.isPendingDeletion }.count
    }

    private var previewSlice: [SavedWork] {
        Array(previewWorks.prefix(4))
    }

    var body: some View {
        HStack(spacing: 13) {
            previewGrid
            labelColumn
            Spacer(minLength: 8)
            chevron
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            let shape = RoundedRectangle(cornerRadius: SubjectMetrics.rowRadius, style: .continuous)
            shape
                .fill(themeManager.appTheme.cardSurface)
                .overlay(shape.fill(themeManager.appTheme.glassFill(0.06)))
                .overlay(
                    shape.strokeBorder(
                        themeManager.appTheme.isDarkFamily
                            ? Color.white.opacity(0.07)
                            : themeManager.appTheme.glassStroke(0.10),
                        lineWidth: 0.5
                    )
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: SubjectMetrics.rowRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(collection.name), \(totalWorkCount) work\(totalWorkCount == 1 ? "" : "s")")
        .accessibilityHint("Opens collection.")
    }

    /// The 128×114 thumbnail preview area: a 2×2 grid of miniature work covers
    /// with 6pt spacing.
    private var previewGrid: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                miniatureCell(at: 0)
                miniatureCell(at: 1)
            }
            HStack(spacing: 6) {
                miniatureCell(at: 2)
                miniatureCell(at: 3)
            }
        }
        .frame(width: 128, height: 114)
    }

    @ViewBuilder
    private func miniatureCell(at index: Int) -> some View {
        if previewSlice.indices.contains(index) {
            MiniatureWorkCover(work: previewSlice[index])
        } else {
            EmptyMiniatureWorkCover()
        }
    }

    private var labelColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(collection.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)

            Text("\(totalWorkCount) work\(totalWorkCount == 1 ? "" : "s")")
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(
                themeManager.appTheme.isDarkFamily
                    ? Color.white.opacity(0.34)
                    : Color.secondary.opacity(0.5)
            )
    }
}

/// A miniature work cover (61×54) in the 2×2 collection preview grid:
/// diagonal card wash derived from the work's hue, a 13×2 accent rule,
/// 2-line title, and 1-line author.
private struct MiniatureWorkCover: View {
    @Environment(ThemeManager.self) private var themeManager
    let work: SavedWork

    var body: some View {
        let hue = CoverArt.workHue(fandoms: work.workFandoms, title: work.title)
        let palette = themeManager.appTheme.subjectPalette(hue: hue)
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(palette.accent)
                .frame(width: 13, height: 2)
                .padding(.bottom, 4)

            Text(work.title)
                .font(.system(size: 9, weight: .semibold))
                .lineSpacing(1.5)
                .foregroundStyle(
                    themeManager.appTheme.isDarkFamily
                        ? Color.white.opacity(0.92)
                        : Color.primary
                )
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if !work.author.isEmpty {
                Text(work.author)
                    .font(.system(size: 8))
                    .foregroundStyle(
                        themeManager.appTheme.isDarkFamily
                            ? Color.white.opacity(0.62)
                            : Color.secondary
                    )
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(width: 61, height: 54, alignment: .topLeading)
        .background {
            shape
                .fill(palette.cardWash)
                .overlay(
                    shape.strokeBorder(
                        themeManager.appTheme.isDarkFamily
                            ? Color.white.opacity(0.10)
                            : palette.cardBorder,
                        lineWidth: 0.5
                    )
                )
        }
        .clipShape(shape)
    }
}

/// An empty placeholder slot in the 2×2 miniature cover grid for collections
/// with fewer than four works.
private struct EmptyMiniatureWorkCover: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        shape
            .fill(themeManager.appTheme.glassFill(0.04))
            .overlay(
                shape.strokeBorder(themeManager.appTheme.glassStroke(0.06), lineWidth: 0.5)
            )
            .frame(width: 61, height: 54)
    }
}

/// Artboard 1d's "New collection" row in ledger mode: dashed border, 128×114
/// icon container with a 32pt centered plus glyph, and title/subtitle.
struct NewCollectionLedgerRow: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack(spacing: 13) {
            iconContainer
            labelColumn
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            let shape = RoundedRectangle(cornerRadius: SubjectMetrics.rowRadius, style: .continuous)
            shape.strokeBorder(
                themeManager.appTheme.isDarkFamily
                    ? Color.white.opacity(0.22)
                    : Color.secondary.opacity(0.35),
                style: StrokeStyle(lineWidth: 1, dash: [5])
            )
        }
        .contentShape(RoundedRectangle(cornerRadius: SubjectMetrics.rowRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("New collection")
        .accessibilityHint("Tap to create a new collection.")
    }

    private var iconContainer: some View {
        ZStack {
            Circle()
                .fill(
                    themeManager.appTheme.isDarkFamily
                        ? Color.white.opacity(0.12)
                        : Color.secondary.opacity(0.12)
                )
                .frame(width: 32, height: 32)

            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(
                    themeManager.appTheme.isDarkFamily
                        ? Color.white.opacity(0.75)
                        : Color.secondary
                )
        }
        .frame(width: 128, height: 114)
    }

    private var labelColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("New collection")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)

            Text("Tap to create")
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
        }
    }
}
