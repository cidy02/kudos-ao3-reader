import SwiftUI

/// A generated "cover" placeholder — EPUBs carry no cover art, so each work gets a
/// stable gradient (hued from its title) with a book glyph, giving the dashboard a
/// Books-like, cover-forward feel without real artwork.
struct CoverArt: View {
    let title: String

    var body: some View {
        let hue = Self.hue(for: title)
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(LinearGradient(
                colors: [
                    Color(hue: hue, saturation: 0.42, brightness: 0.74),
                    Color(hue: hue, saturation: 0.58, brightness: 0.46)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .overlay {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
    }

    /// A stable hue in 0...1 derived from the title (djb2-ish hash).
    static func hue(for string: String) -> Double {
        let hash = string.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1.value) }
        return Double(hash % 360) / 360
    }
}

/// Standard carousel card: cover + title + author + an optional footer (e.g. "Ch 3").
struct WorkCoverCard: View {
    let work: SavedWork
    var footer: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverArt(title: work.title)
                .frame(width: 120, height: 172)
            Text(work.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
            if !work.author.isEmpty {
                Text(work.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let footer {
                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 120, alignment: .leading)
    }
}

/// The "Reading Now" hero card: a wider, horizontal layout with the current
/// chapter and a progress bar.
struct HeroReadingCard: View {
    let work: SavedWork

    var body: some View {
        HStack(spacing: 14) {
            CoverArt(title: work.title)
                .frame(width: 82, height: 120)
            VStack(alignment: .leading, spacing: 5) {
                Text(work.title)
                    .font(.headline)
                    .lineLimit(2)
                if !work.author.isEmpty {
                    Text(work.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(chapterLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let fraction = progressFraction {
                    ProgressView(value: fraction)
                        .tint(.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(width: 320, height: 148, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }

    private var chapterLabel: String {
        work.lastSpineIndex > 0 ? "Chapter \(work.lastSpineIndex + 1)" : "Just started"
    }

    /// Best-effort progress: reading position over the work's AO3 chapter count
    /// (the "5/10" stats string). Nil — so no bar — when the total is unknown (WIP
    /// works show "5/?").
    private var progressFraction: Double? {
        let parts = work.chapters.split(separator: "/")
        guard parts.count == 2,
              let total = Int(parts[1].trimmingCharacters(in: .whitespaces)), total > 1
        else { return nil }
        return min(1, Double(work.lastSpineIndex + 1) / Double(total))
    }
}

/// How the dashboard opens a tapped work: straight into the reader when the EPUB is
/// on disk, otherwise its detail page (which can re-download a freed file).
struct HomeWorkDestination: View {
    let work: SavedWork

    var body: some View {
        if work.hasEPUB {
            ReaderView(work: work)
        } else {
            WorkDetailView(work: work)
        }
    }
}
