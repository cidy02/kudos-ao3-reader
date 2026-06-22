import SwiftUI

// Reusable wireframe skeletons for the first-load state of remote/AO3-backed content.
// Perceived-performance only: skeletons never trigger or change any AO3 request — they
// just show the shape of content that an *already in-flight* request will fill in.
// Each skeleton is hidden from VoiceOver, non-interactive, and its shimmer is disabled
// under Reduce Motion (see `skeletonShimmer()`).

// MARK: - Primitives

/// A rounded wireframe block. `width: nil` fills the available width.
struct SkeletonBlock: View {
    var height: CGFloat = 12
    var width: CGFloat? = nil
    var cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.quaternary)
            .frame(height: height)
            .frame(maxWidth: width ?? .infinity, alignment: .leading)
    }
}

/// A placeholder text line — a block rounded and sized like a line of text.
struct SkeletonTextLine: View {
    var height: CGFloat = 13
    var width: CGFloat? = nil

    var body: some View {
        SkeletonBlock(height: height, width: width, cornerRadius: height / 2.5)
    }
}

// MARK: - Shimmer (Reduce-Motion aware)

private struct SkeletonShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion ? 0.85 : (dim ? 0.5 : 0.9))
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                value: dim
            )
            .onAppear { dim = true }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

extension View {
    /// A calm, subtle pulse for skeleton placeholders. Disabled under Reduce Motion;
    /// also hides the content from VoiceOver and makes it non-interactive.
    func skeletonShimmer() -> some View { modifier(SkeletonShimmer()) }
}

// MARK: - Work skeletons

/// Wireframe roughly matching `AO3WorkRow` / `WorkRow`: title, author, fandom,
/// summary lines, and a stats row.
struct AO3WorkRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonTextLine(height: 16, width: 230)   // title
            SkeletonTextLine(height: 13, width: 130)   // author
            SkeletonTextLine(height: 12, width: 190)   // fandom
            VStack(alignment: .leading, spacing: 5) {
                SkeletonTextLine(height: 12)
                SkeletonTextLine(height: 12)
                SkeletonTextLine(height: 12, width: 210)
            }
            .padding(.top, 1)
            HStack(spacing: 16) {
                SkeletonBlock(height: 11, width: 46)
                SkeletonBlock(height: 11, width: 58)
                SkeletonBlock(height: 11, width: 40)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .skeletonShimmer()
    }
}

/// Wireframe matching the carousel cover cards (`WorkCoverCard` / `AO3WorkCoverCard`).
struct WorkCoverCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SkeletonBlock(height: 172, width: 120, cornerRadius: 10)   // cover
            SkeletonTextLine(height: 13, width: 112)                   // title
            SkeletonTextLine(height: 11, width: 78)                    // author
            SkeletonBlock(height: 10, width: 60, cornerRadius: 4)      // stat line
        }
        .frame(width: 120, alignment: .leading)
        .skeletonShimmer()
    }
}

/// Wireframe matching the Browse category card (icon + name, divider, stats line).
struct CategoryCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SkeletonBlock(height: 24, width: 24, cornerRadius: 6)
                SkeletonTextLine(height: 16, width: 170)
            }
            Divider().opacity(0.4)
            HStack(spacing: 16) {
                SkeletonBlock(height: 11, width: 90)
                SkeletonBlock(height: 11, width: 72)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .skeletonShimmer()
    }
}

/// Wireframe matching the fandom-list rows (name + work count).
struct FandomRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            SkeletonTextLine(height: 15, width: 200)
            Spacer(minLength: 24)
            SkeletonBlock(height: 12, width: 56, cornerRadius: 4)
        }
        .padding(.vertical, 8)
        .skeletonShimmer()
    }
}

// MARK: - Ready-made lists (match the real card lists they replace)

/// A card list of work-row skeletons — Search, Fandom works, and Account AO3 lists.
struct AO3WorkRowSkeletonList: View {
    var count: Int = 6

    var body: some View {
        List {
            Section {
                ForEach(0..<count, id: \.self) { _ in AO3WorkRowSkeleton() }
                    .cardRow()
            }
        }
        .cardList()
    }
}

/// A card list of category-card skeletons — the Browse root first load.
struct CategoryCardSkeletonList: View {
    var count: Int = 8

    var body: some View {
        List {
            Section {
                ForEach(0..<count, id: \.self) { _ in CategoryCardSkeleton() }
                    .cardRow()
            } header: {
                Text("Browse by fandom")
            }
        }
        .cardList()
    }
}

/// A card list of fandom-row skeletons — the fandom-list first load.
struct FandomRowSkeletonList: View {
    var count: Int = 10

    var body: some View {
        List {
            ForEach(0..<count, id: \.self) { _ in FandomRowSkeleton() }
                .cardRow()
        }
        .cardList()
    }
}
