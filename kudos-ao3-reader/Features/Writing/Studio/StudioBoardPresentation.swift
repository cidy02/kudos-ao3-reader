import SwiftUI

/// Shared date and time copy helpers matching the Writing Studio boards
/// (`yesterday`, `Oct 2`, `edited yesterday, 23:10`, `edited 20 min ago`).
nonisolated enum StudioDateCopy {
    /// Short calendar date used in row meta lines and recent cards:
    /// `"today"`, `"yesterday"`, `"Oct 2"` (same year), or `"Oct 2, 2025"` (other year).
    static func shortDate(
        _ date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let startOfDate = calendar.startOfDay(for: date)
        let startOfNow = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: startOfDate, to: startOfNow).day ?? 0
        if days == 0 { return "today" }
        if days == 1 { return "yesterday" }
        var style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
            .locale(locale)
            .month(.abbreviated)
            .day()
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) {
            style = style.year()
        }
        return date.formatted(style)
    }

    /// Formats an AO3 calendar-date string (`yyyy-MM-dd` / `20 Oct 2026`) using the board's
    /// short month-and-day style for the current year, keeping the raw string when unparseable.
    static func shortAO3Date(
        _ rawText: String,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = WorkStat.date(from: trimmed) else { return trimmed }
        var gmtCalendar = Calendar(identifier: .gregorian)
        gmtCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let sameYear = gmtCalendar.component(.year, from: parsed) == calendar.component(.year, from: now)
        var style = Date.FormatStyle(calendar: gmtCalendar, timeZone: gmtCalendar.timeZone)
            .locale(locale)
            .month(.abbreviated)
            .day()
        if !sameYear {
            style = style.year()
        }
        return parsed.formatted(style)
    }

    /// Continue-card edit phrase matching `Studio-Overview` (`edited yesterday, 23:10`)
    /// and `Studio-Offline` (`edited 20 min ago`).
    static func editedPhrase(
        _ date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed >= 0, elapsed < 60 {
            return "edited just now"
        }
        if elapsed >= 60, elapsed < 3_600 {
            let minutes = max(1, Int(elapsed / 60))
            return "edited \(minutes) min ago"
        }
        let startOfDate = calendar.startOfDay(for: date)
        let startOfNow = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: startOfDate, to: startOfNow).day ?? 0
        let timeStyle = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
            .locale(locale)
            .hour()
            .minute()
        if days == 0 {
            return "edited today, \(date.formatted(timeStyle))"
        }
        if days == 1 {
            return "edited yesterday, \(date.formatted(timeStyle))"
        }
        return "edited \(shortDate(date, now: now, calendar: calendar, locale: locale))"
    }
}

/// Theme-aware palette tokens shared by Writing Studio cards, icons, and pills
/// across Light, Dark, OLED, and Sepia.
enum StudioTonePalette {
    /// Warm paper surface used on Continue, Recent paper thumbnails, and Start Writing icon tiles.
    static func paperBackground(for appTheme: ReaderTheme) -> Color {
        switch appTheme {
        case .light: Color(red: 0.984, green: 0.980, blue: 0.965)
        case .sepia, .dark, .oled: appTheme.cardSurface
        }
    }

    static func paperBorder(for appTheme: ReaderTheme) -> Color {
        switch appTheme {
        case .light: Color(red: 0.898, green: 0.875, blue: 0.824)
        case .sepia: appTheme.cardBorder
        case .dark, .oled: appTheme.glassStroke(0.18)
        }
    }

    /// Readable warm amber ink for AO3 draft badges and status lines (passes contrast on all themes).
    static func draftAmberInk(for appTheme: ReaderTheme) -> Color {
        switch appTheme {
        case .light: Color(red: 0.420, green: 0.227, blue: 0.000)
        case .sepia: Color(red: 0.360, green: 0.195, blue: 0.000)
        case .dark, .oled: appTheme.favoriteColor
        }
    }

    static func draftAmberFill(for appTheme: ReaderTheme) -> Color {
        switch appTheme {
        case .light: Color(red: 1.0, green: 0.957, blue: 0.898)
        case .sepia: appTheme.favoriteColor.opacity(0.18)
        case .dark, .oled: appTheme.favoriteColor.opacity(0.20)
        }
    }

    /// Readable teal ink and soft fill for work folders and Work details (`Studio-Files`, `Studio-Work-Files`).
    static func workFolderInk(for appTheme: ReaderTheme) -> Color {
        switch appTheme {
        case .light: Color(red: 0.122, green: 0.369, blue: 0.400)
        case .sepia: Color(red: 0.140, green: 0.340, blue: 0.360)
        case .dark, .oled: Color(red: 0.430, green: 0.800, blue: 0.840)
        }
    }

    static func workFolderFill(for appTheme: ReaderTheme) -> Color {
        switch appTheme {
        case .light: Color(red: 0.890, green: 0.933, blue: 0.941)
        case .sepia: workFolderInk(for: appTheme).opacity(0.14)
        case .dark, .oled: workFolderInk(for: appTheme).opacity(0.22)
        }
    }

    /// Soft accent-tinted background for secondary Studio pills (`Reply`, `Sign In to AO3`, `Start Writing`).
    static func softAccentFill(for theme: ThemeManager) -> Color {
        theme.effectiveTint.opacity(theme.appTheme.isDarkFamily ? 0.22 : 0.12)
    }
}

/// Sentence/Title-case status pill used across `Studio-Documents`, `Studio-Files`, and
/// `Studio-Work-Files` (`Posted`, `Draft`, `AO3 draft`, `iPhone`, `Not started`).
struct StudioStatusPill: View {
    enum Tone: Equatable {
        case posted
        case draft
        case onDevice
        case notStarted
    }

    let text: String
    let tone: Tone

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                if let fill = backgroundColor {
                    shape.fill(fill)
                }
            }
            .overlay {
                if tone == .notStarted {
                    shape.strokeBorder(
                        theme.appTheme.glassStroke(0.32),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                    )
                }
            }
            .accessibilityLabel(text)
    }

    private var foregroundStyle: AnyShapeStyle {
        switch tone {
        case .posted:
            AnyShapeStyle(theme.appTheme.statusSuccessColor)
        case .draft:
            AnyShapeStyle(StudioTonePalette.draftAmberInk(for: theme.appTheme))
        case .onDevice:
            AnyShapeStyle(Color.primary.opacity(theme.appTheme.isDarkFamily ? 0.85 : 0.78))
        case .notStarted:
            AnyShapeStyle(.secondaryInk)
        }
    }

    private var backgroundColor: Color? {
        switch tone {
        case .posted:
            theme.appTheme.statusSuccessColor.opacity(theme.appTheme.isDarkFamily ? 0.22 : 0.14)
        case .draft:
            StudioTonePalette.draftAmberFill(for: theme.appTheme)
        case .onDevice:
            theme.appTheme.glassFill(0.12)
        case .notStarted:
            nil
        }
    }
}
