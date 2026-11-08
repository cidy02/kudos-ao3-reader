import SwiftUI

/// Header facts for Waiting when the scan, not mail, is the source.
struct WaitingScanStatus: Equatable {
    var checkedLabel: String?
    var waitingCount: Int
    var followsLine: String
    var checkTitle: String
    var note: String?
}

/// The Subscriptions "Waiting" list: what changed, grouped by day, down a 40pt
/// gutter and a 14pt progress rail. Renders what it is handed; the caller owns
/// fetching.
///
/// A `.workOnly` update is a quieter row, not a lesser one: it says the work
/// updated and nothing more. Every chapter claim goes through
/// `canDeepLinkToChapter`, so a value the parser could not establish never
/// reaches the screen.
struct WaitingListView: View {
    let updates: [SubscriptionUpdate]
    /// Scanning has no event times, so the gutter counts places instead of
    /// showing a clock.
    var showsPosition = false
    /// A parent with more specific source state can supply its own honest empty view.
    var showsEmptyState = true
    var mailSince: Date?
    var unverifiedCount: UInt64 = 0
    var refreshError: String?
    /// Present only when Waiting is showing the on-device scan. Mail leaves it nil.
    var scanStatus: WaitingScanStatus?
    /// First-look baselines while a scan is still partial. Not new-chapter rows.
    var baselines: [SubscriptionScanSnapshot] = []
    var alphabeticalNote: String?
    var onCheck: (() -> Void)?

    @Environment(PrivacyGate.self) private var privacyGate
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure

    private struct Day: Identifiable {
        let start: Date
        let updates: [SubscriptionUpdate]
        var id: Date { start }
    }

    private var days: [Day] {
        let calendar = Calendar.current
        let shown = updates.filter {
            !privacyGate.isHidden(remoteID: Int(clamping: $0.workID), rating: $0.rating, enabled: hideMature, mode: matureMode)
        }
        return Dictionary(grouping: shown.sorted { $0.at > $1.at }) { calendar.startOfDay(for: $0.at) }
            .map { Day(start: $0.key, updates: $0.value) }
            .sorted { $0.start > $1.start }
    }

    var body: some View {
        List {
            // Group so .appThemedRows() reaches every section's rows — it doesn't
            // propagate from the List container, only from a Group/Section/ForEach.
            Group {
                if let mailSince {
                    Section {
                        WaitingMailHeader(
                            since: mailSince,
                            updateCount: updates.count,
                            unverifiedCount: unverifiedCount,
                            refreshError: refreshError
                        )
                        .listRowSeparator(.hidden)
                    }
                }
                if let scanStatus {
                    Section {
                        WaitingScanHeader(status: scanStatus, onCheck: onCheck)
                            .listRowSeparator(.hidden)
                        if let alphabeticalNote {
                            Text(alphabeticalNote)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .listRowSeparator(.hidden)
                        }
                    }
                }
                if !baselines.isEmpty {
                    Section {
                        ForEach(baselines) { snapshot in
                            WaitingBaselineRow(snapshot: snapshot)
                                // A scan snapshot carries no rating.
                                .concealedForPrivacy(privacyGate.isBlurred(
                                    remoteID: snapshot.workID, rating: nil,
                                    enabled: hideMature, mode: matureMode
                                )) {
                                    privacyGate.reveal(remoteID: snapshot.workID)
                                }
                        }
                    } header: {
                        Text("By updated date")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .textCase(nil)
                    }
                }
                ForEach(days) { day in
                    Section {
                        ForEach(Array(day.updates.enumerated()), id: \.element.id) { index, update in
                            WaitingRow(
                                update: update,
                                position: index + 1,
                                showsPosition: showsPosition,
                                isFirst: index == 0,
                                isLast: index == day.updates.count - 1
                            )
                            .concealedForPrivacy(privacyGate.isBlurred(
                                remoteID: Int(clamping: update.workID), rating: update.rating,
                                enabled: hideMature, mode: matureMode
                            )) {
                                privacyGate.reveal(remoteID: Int(clamping: update.workID))
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        WaitingDayHeader(start: day.start, count: day.updates.count)
                    }
                }
            }
            .appThemedRows()
        }
        .listStyle(.plain)
        .appThemedScroll()
        .overlay {
            if showsEmptyState, updates.isEmpty {
                ContentUnavailableView("Nothing waiting", systemImage: "tray")
            }
        }
        .navigationTitle("Waiting")
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

private struct WaitingScanHeader: View {
    let status: WaitingScanStatus
    var onCheck: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                if let checkedLabel = status.checkedLabel {
                    Text(checkedLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Text("\(status.waitingCount.formatted()) waiting")
                    .font(.largeTitle.bold())

                Text(status.followsLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let note = status.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            Button(status.checkTitle) { onCheck?() }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(onCheck == nil)
        }
        .padding(.vertical, 8)
    }
}

private struct WaitingBaselineRow: View {
    let snapshot: SubscriptionScanSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.title.isEmpty ? "Work #\(snapshot.workID)" : snapshot.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            if !snapshot.author.isEmpty {
                Text(snapshot.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        if let posted = snapshot.chaptersPosted {
            if let total = snapshot.chaptersTotal {
                parts.append("\(posted)/\(total)")
            } else {
                parts.append("\(posted)/?")
            }
        }
        if !snapshot.updatedText.isEmpty {
            parts.append("Updated \(snapshot.updatedText)")
        }
        parts.append("Baseline")
        return parts.joined(separator: " · ")
    }
}

private struct WaitingMailHeader: View {
    let since: Date
    let updateCount: Int
    let unverifiedCount: UInt64
    let refreshError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                "From AO3 notifications · \(updateCount.formatted()) updates since "
                    + since.formatted(.dateTime.month(.abbreviated).year())
            )
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)

            Text("\(updateCount.formatted()) waiting")
                .font(.largeTitle.bold())

            Text("no requests to AO3")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if unverifiedCount > 0 {
                Label(
                    "\(unverifiedCount.formatted()) updates couldn't be verified",
                    systemImage: "exclamationmark.shield"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if let refreshError {
                Text(refreshError)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct WaitingDayHeader: View {
    let start: Date
    let count: Int

    private var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(start) { return "Today" }
        if calendar.isDateInYesterday(start) { return "Yesterday" }
        return start.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text("\(count)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }
        .textCase(nil)
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(count) waiting")
    }
}

/// Clock text for the 40pt gutter. `time` is the hour and minute in the
/// locale's own separator and hour cycle; `marker` is the day period only
/// when that cycle prints one. Field boundaries come from the formatter, so
/// a leading marker ("오후 3:00") and a trailing one ("3:00 PM") split the
/// same way, and the no-break space between them stays out of both tokens.
struct WaitingGutterClock: Equatable {
    var time: String
    var marker: String?

    static func parts(
        for date: Date,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> WaitingGutterClock {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
            .hour()
            .minute()
        let attributed = date.formatted(style.attributedStyle)
        var time = ""
        var marker = ""
        for run in attributed.runs {
            let piece = String(attributed[run.range].characters)
            if run.dateField == .amPM {
                marker += piece
            } else {
                time += piece
            }
        }
        let trimmedMarker = marker.trimmingCharacters(in: .whitespaces)
        return WaitingGutterClock(
            time: time.trimmingCharacters(in: .whitespaces),
            marker: trimmedMarker.isEmpty ? nil : trimmedMarker
        )
    }
}

private struct WaitingRow: View {
    let update: SubscriptionUpdate
    let position: Int
    let showsPosition: Bool
    let isFirst: Bool
    let isLast: Bool

    private var isConfirmed: Bool { update.certainty == .confirmed }

    /// The chapter number, only where a chapter can be offered at all.
    private var chapter: Int? {
        guard update.canDeepLinkToChapter, case let .newChapter(number) = update.change else { return nil }
        return number
    }

    /// The headline, which must only ever state something AO3 established.
    ///
    /// A work subscription's footer IS the work's unsubscribe URL, so its title
    /// is AO3's and leads the row. An author or series subscription pins no work
    /// — the title was read from the body, where the author's own text lives — so
    /// the headline falls back to the one thing the Rails-built URL did establish,
    /// which is whose updates these are. The body's title still appears, as
    /// `claimedTitle` below, attributed rather than asserted: blanking it outright
    /// would reduce every author-subscription row to "Work #83701926", and the
    /// reader needs something to decide on.
    private var headline: String {
        if update.pinsTheWork {
            return update.workTitle.isEmpty ? "Work #\(update.workID)" : update.workTitle
        }
        switch update.source {
        case let .author(name): return "New from \(name)"
        case let .series(name): return "New in \(name)"
        case .work, .unknown: return "New in a work you follow"
        }
    }

    /// The body's own title on an unpinned row — shown in quotes, as the email's
    /// claim. Nil when the work is pinned (the title is the headline already) or
    /// when the preface was contested and nothing survived it.
    private var claimedTitle: String? {
        guard !update.pinsTheWork, !update.workTitle.isEmpty else { return nil }
        return update.workTitle
    }

    /// AO3 batches several creations into one email. The crate counts the ones it
    /// did not parse so this never reads as the whole message.
    private var alsoInThisEmail: String? {
        guard update.extraCreations > 0 else { return nil }
        let extras = update.extraCreations
        return extras == 1
            ? "and 1 more update in the same notification"
            : "and \(extras) more updates in the same notification"
    }

    private var whatChanged: String {
        guard isConfirmed else {
            // "This work updated" asserts the work, which is the one thing an
            // author or series notification does not pin — see `pinsTheWork`.
            return update.pinsTheWork
                ? "This work updated. Open it to see what changed."
                : "Something new from this follow. Open it on AO3 to see what."
        }
        switch update.change {
        case .newChapter: return chapter.map { "Chapter \($0) posted" } ?? "A new chapter was posted"
        case .newWork: return "A new work was posted"
        case .unknown: return "This work updated."
        }
    }

    private var badge: String {
        guard isConfirmed else { return update.pinsTheWork ? "Updated" : "Check" }
        switch update.change {
        case .newChapter: return chapter.map { "+1 · Ch. \($0)" } ?? "Updated"
        case .newWork: return "New"
        case .unknown: return "Updated"
        }
    }

    /// The 40pt gutter cannot scale — widening it with the text would leave the
    /// content column too narrow to read on a phone — so at accessibility sizes
    /// it goes away entirely and its value moves into the metadata strip, which
    /// wraps. 54 fixed points of indent is affordable at the default size and is
    /// most of a small screen at AX5.
    @Environment(\.dynamicTypeSize) private var typeSize
    private var isAccessibilitySize: Bool { typeSize.isAccessibilitySize }

    /// The gutter's value has to live somewhere once the gutter is gone.
    private var showsValueInStrip: Bool { showsPosition || isAccessibilitySize }

    /// Smaller than caption2, and it tracks caption2 as the type size grows.
    @ScaledMetric(relativeTo: .caption2) private var gutterMarkerSize: CGFloat = 9

    private var gutter: some View {
        Group {
            if showsPosition {
                Text("\(position)")
            } else {
                gutterClock
            }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 40, alignment: .trailing)
        .padding(.top, 12)
    }

    /// Digits stay full size. The day-period marker, when the locale has one,
    /// sits on a second line: "3:00 AM" does not fit this column, and the
    /// formatter joins the marker with a narrow no-break space, so a wrap
    /// lands inside the marker. Each token scales instead of breaking when
    /// the type size makes even one of them wider than 40pt.
    private var gutterClock: some View {
        let clock = WaitingGutterClock.parts(for: update.at)
        return VStack(alignment: .trailing, spacing: 0) {
            Text(clock.time)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let marker = clock.marker {
                Text(marker)
                    .font(.system(size: gutterMarkerSize))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(update.at.formatted(.dateTime.hour().minute()))
    }

    private var sourceLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(update.source.kind)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(update.source.color, in: Capsule())
            Text(update.source.line)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var badgeLabel: some View {
        Text(badge)
            .font(.caption.bold())
            // `.primary` in both states, and neither `.tint` nor `.secondary`.
            // `.tint` is the user's accent (AO3 red by default), a fixed hex
            // rather than a colorScheme colour, so on `.quaternary` over the
            // dark surface it falls under 2:1. `.secondary` is no good either:
            // at caption size this is 12pt bold, under the 14pt that would let
            // it pass as large text, so it needs 4.5:1 — and `.secondary` on
            // `.quaternary` measures about 3.2:1 on light and sepia. The hedge
            // is carried by the words ("Check" vs "+1 · Ch. 9") and by the
            // rail's outline dot, neither of which depends on contrast ratio.
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
            .fixedSize()
    }

    private var titleText: some View {
        Text(headline)
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The badge is `.fixedSize()`, so beside the title it wins the compression
    /// and squeezes the title into a tall sliver. Stacked, both get the width.
    @ViewBuilder private var titleAndBadge: some View {
        if isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                titleText
                badgeLabel
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                titleText
                Spacer(minLength: 0)
                badgeLabel
            }
        }
    }

    /// Nothing here for a row whose byline could not be read and whose gutter
    /// value is still in the gutter.
    @ViewBuilder private var metadata: some View {
        if !update.author.isEmpty || showsValueInStrip {
            FlowLayout(spacing: 12, rowSpacing: 4) {
                if !update.author.isEmpty {
                    // Truncating: a pseud is free text, unlike the bounded stats
                    // this label usually carries.
                    WorkStatLabel(text: update.author, symbol: "person", truncates: true)
                }
                // Only once the gutter that would have shown it is gone.
                if showsPosition, isAccessibilitySize {
                    WorkStatLabel(text: "#\(position)", symbol: "number")
                }
                if showsValueInStrip {
                    WorkStatLabel(text: update.at.formatted(.dateTime.hour().minute()), symbol: "clock")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if !isAccessibilitySize {
                gutter
            }

            WaitingRail(isConfirmed: isConfirmed, isFirst: isFirst, isLast: isLast)

            VStack(alignment: .leading, spacing: 6) {
                sourceLine
                titleAndBadge
                metadata
                if let claimedTitle {
                    // Quoted and attributed: the email said this, AO3 did not.
                    Text("AO3's notification names \u{201C}\(claimedTitle)\u{201D}")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(whatChanged)
                    .font(.subheadline)
                    .foregroundStyle(isConfirmed ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let alsoInThisEmail {
                    Text(alsoInThisEmail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 10)
            .padding(.leading, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The 14pt rail beside the gutter. Segments stop at the dot, so a row's own
/// line never runs through it; the dot is solid for a confirmed update and an
/// outline for a work-only one.
///
/// The dot deliberately takes no colour of its own. The source fills are
/// saturated colours chosen to carry white chip text, and against the dark
/// themes' card background the work red reads at about 1.35:1 — invisible. The
/// app's `.tint` is no better: it resolves to the user's accent, a fixed hex
/// defaulting to AO3 red, so it is not a `colorScheme` colour and lands near
/// 1.6:1 on the same surface. `.primary` and `.secondary` are dynamic by
/// construction, so the one distinction the dot actually carries — confirmed
/// from work-only — survives on all four themes, whatever accent is set. The
/// kind stays colour-coded on the chip beside it, where the contrast holds.
private struct WaitingRail: View {
    @Environment(ThemeManager.self) private var theme
    let isConfirmed: Bool
    let isFirst: Bool
    let isLast: Bool

    private var line: some View {
        Rectangle()
            .fill(theme.appTheme.threadSpine)
            .frame(width: 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            line.frame(height: 12).opacity(isFirst ? 0 : 1)
            Group {
                if isConfirmed {
                    Circle().fill(.primary)
                } else {
                    Circle().strokeBorder(.secondary, lineWidth: 2)
                }
            }
            .frame(width: 10, height: 10)
            line.frame(maxHeight: .infinity).opacity(isLast ? 0 : 1)
        }
        .frame(width: 14)
        .accessibilityHidden(true)
    }
}

private extension SubscriptionUpdate.Source {
    var kind: String {
        switch self {
        case .work: "Work"
        case .series: "Series"
        case .author: "Author"
        case .unknown: "Update"
        }
    }

    var line: String {
        switch self {
        case .work: "Following this work"
        case let .series(name): "Following \(name)"
        case let .author(name): "Following \(name)"
        case .unknown: "From a subscription"
        }
    }

    /// The chip's fill. Fixed rather than themed because the chip carries white
    /// text: each of these clears 5.7:1 against white, which a theme-derived
    /// colour would not guarantee. Only the chip uses it — see `WaitingRail`.
    var color: Color {
        switch self {
        case .work: Color(red: 0x82 / 255, green: 0x10 / 255, blue: 0x19 / 255)
        case .series: Color(red: 0x1E / 255, green: 0x63 / 255, blue: 0xC8 / 255)
        case .author: Color(red: 0x7B / 255, green: 0x3F / 255, blue: 0xA0 / 255)
        // Neutral: there is no kind to signal, and the chip still needs to
        // carry white text.
        case .unknown: Color(red: 0x4A / 255, green: 0x4A / 255, blue: 0x4F / 255)
        }
    }
}

#Preview {
    let now = Date()
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now

    func update(
        _ id: UInt64, chapter: Int? = 9, isNew: Bool = false, contested: Bool = false,
        anchored: Bool = true, title: String, author: String, at: Date,
        source: SubscriptionUpdate.Source = .work
    ) -> SubscriptionUpdate {
        SubscriptionUpdate(
            uid: UInt32(id), workID: id, chapterID: id * 10,
            chapterNumber: chapter, isNewWork: isNew,
            isContested: contested, isAnchoredToWork: anchored,
            workTitle: title, author: author, at: at, source: source
        )
    }

    return NavigationStack {
        WaitingListView(updates: [
            update(1, title: "The Lantern Keeper", author: "saltwindow", at: now - 600),
            update(2, isNew: true, title: "Salt and Ember", author: "quietfern", at: now - 3_600,
                   source: .series("Winter Court")),
            update(3, chapter: 3, title: "A Quiet Harbour", author: "marrowlight", at: now - 7_200,
                   source: .author("marrowlight")),
            update(4, contested: true, title: "", author: "", at: yesterday),
            update(5, chapter: nil, anchored: false, title: "Paper Boats", author: "wrenfield",
                   at: yesterday - 3_600, source: .author("wrenfield"))
        ])
    }
    .environment(PrivacyGate())
    .environment(ThemeManager())
}
