import SwiftUI

/// Artboard 1d's collection ledger row: previews up to four miniature work covers
/// in a 2×2 grid beside the collection title, work count, and a trailing chevron.
///
/// Miniature covers name a work, so the caller leaves out every work the privacy
/// setting is keeping back (`PrivacyGate.isConcealed`): hidden, or blurred.
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

    @ScaledMetric(relativeTo: .headline) private var rowTitleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var detailSize: CGFloat = 12

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
            let shape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
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
        .contentShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
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
                .font(.system(size: rowTitleSize, weight: .semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)

            Text("\(totalWorkCount) work\(totalWorkCount == 1 ? "" : "s")")
                .font(.system(size: detailSize))
                .foregroundStyle(.secondaryInk)
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

/// A miniature work cover in the 2×2 collection preview grid.
private struct MiniatureWorkCover: View {
    let work: SavedWork

    var body: some View {
        GeneratedCoverView(recipe: work.generatedCoverRecipe,
           width: 61, epubURL: work.hasEPUB ? work.fileURL : nil, epubWorkID: work.id,
           height: 54, showsWords: false)
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
