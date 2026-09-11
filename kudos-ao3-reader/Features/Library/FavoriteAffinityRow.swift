import SwiftUI

/// One aggregate row in Favorites' Authors / Fandoms / Tags scopes — artboards
/// **1ak**, **1bc** and **1bd**.
///
/// The spec draws the three scopes with the same row: an initial tile, the name,
/// one line of log facts, and a library line underneath saying what is still
/// unread. Keeping them one type rather than three means the initial, the spacing
/// and the "no unread works" wording cannot drift between scopes that sit one tap
/// apart.
struct FavoriteAffinityRow: View {
    let row: ReadingAffinities.Row
    let palette: SubjectPalette
    /// `#` for tags, the name's first letter for authors and fandoms — the spec's
    /// own distinction, and it is doing work: a tag's first letter is not a thing
    /// anyone sorts or scans by.
    var usesHashTile = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            tile
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                Text(logLine)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                libraryLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .subjectCard(palette: palette)
        .combinedAccessibilityRow("\(row.name). \(logLine). \(libraryText)")
    }

    private var tile: some View {
        Text(usesHashTile ? "#" : String(row.name.prefix(1)).uppercased())
            .font(.system(size: 15, weight: .bold, design: usesHashTile ? .monospaced : .default))
            .foregroundStyle(palette.accent)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.chipFill)
            )
            .accessibilityHidden(true)
    }

    /// Spec 1ak: "6 works read · 31h 12m · last read 4 Sep 2026". Each fact is
    /// dropped rather than zeroed when it has nothing to say — "0h 00m" on a row
    /// whose sessions predate the log is a wrong number, not a small one.
    private var logLine: String {
        var parts = ["\(row.worksRead) work\(row.worksRead == 1 ? "" : "s") read"]
        if row.totalSeconds > 0 {
            parts.append(ReadingInsights.durationLabel(row.totalSeconds))
        }
        if let lastRead = row.lastRead {
            parts.append("last read \(lastRead.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var libraryLine: some View {
        Text(libraryText)
            .font(.system(size: 11))
            .foregroundStyle(row.unreadInLibrary > 0 ? palette.accent : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Spec 1bd's second line, including its wording for the empty case: "No unread
    /// works · Everything tagged this way is finished". That sentence is the reason
    /// the line exists — it is the one that tells you there is nothing left here.
    private var libraryText: String {
        guard row.unreadInLibrary > 0 else {
            return "No unread works in your library"
        }
        var text = "\(row.unreadInLibrary) unread work\(row.unreadInLibrary == 1 ? "" : "s")"
        var extras: [String] = []
        if row.downloadedInLibrary > 0 { extras.append("\(row.downloadedInLibrary) downloaded") }
        if row.savedForLater > 0 { extras.append("\(row.savedForLater) in Saved for Later") }
        if !extras.isEmpty { text += " · " + extras.joined(separator: " · ") }
        return text
    }
}
