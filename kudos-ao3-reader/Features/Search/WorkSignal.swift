import Foundation

/// A quality signal displayed on ranked search results (Quality-Results board).
///
/// Contains the tone, badge label, and quiet note describing reader response
/// computed purely from the figures AO3 blurbs already carry.
struct WorkSignal: Equatable, Hashable, Sendable {
    enum Tone: String, Equatable, Hashable, CaseIterable, Sendable {
        case high
        case good
        case late
        case neutral
        case unusual
    }

    let label: String
    let note: String?
    let tone: Tone

    /// VoiceOver reads the signal as one phrase, e.g. "2.4× kudos per hit, Steady · 26% saved".
    var accessibilityText: String {
        if let note, !note.isEmpty {
            return "\(label), \(note)"
        }
        return label
    }
}

extension WorkSignal: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        self.init(label: value, note: nil, tone: .neutral)
    }
}

/// Pure logic for choosing signal tone, label, and secondary note (FID40).
enum QualitySignalTones {
    /// Evaluates the tone and visible copy from a work's figures and ranking state.
    ///
    /// Hard rule: every number, label and confidence word comes strictly from existing
    /// blurb figures (kudos, hits, bookmarks, comments) and computed ratios.
    static func chooseTone(
        rank: LoadedWorksRank,
        shown: Double?,
        figures: LoadedWorksRanker.Figures,
        setAside: Bool,
        hasPrevious: Bool = false
    ) -> WorkSignal? {
        guard rank != .ao3Order else { return nil }

        if setAside {
            let note: String
            if let kudos = figures.kudos, let hits = figures.hits, kudos > hits {
                note = "More kudos than hits"
            } else if let kudos = figures.kudos, kudos >= LoadedWorksRanker.unusualKudosFloor,
                      let bookmarks = figures.bookmarks, bookmarks * 100 < kudos {
                note = "Thousands of kudos and almost no bookmarks"
            } else {
                note = "Unusual stats"
            }
            return WorkSignal(label: "Unusual stats", note: note, tone: .unusual)
        }

        guard let shown else {
            return WorkSignal(label: "Not enough figures to rank", note: nil, tone: .neutral)
        }

        let kudos = figures.kudos ?? 0
        let confidenceWord: String = {
            if kudos >= 200 { return "Steady" }
            if kudos >= 50 { return "Settling" }
            return "Early"
        }()

        switch rank {
        case .ao3Order:
            return nil

        case .kudosPerHitAdjusted:
            let label = "\(decimal(shown))× kudos per hit"
            let tone: WorkSignal.Tone = {
                // 1.0× is typical (spec §4.1): only a clearly higher figure stands out;
                // a check mark on an average work would read as praise.
                if shown >= 1.2 { return .high }
                return .neutral
            }()

            let note: String
            if confidenceWord == "Early" && (figures.hits ?? 0) < 3_000 && (figures.bookmarks ?? 0) == 0 {
                note = "Early · few readers yet"
            } else if let bookmarks = figures.bookmarks, kudos > 0 {
                let pct = Int(round(Double(bookmarks) / Double(kudos) * 100))
                note = "\(confidenceWord) · \(pct)% saved"
            } else {
                note = confidenceWord
            }
            return WorkSignal(label: label, note: note, tone: tone)

        case .savesPerKudos:
            let pct = decimal(shown * 100)
            let label = "\(pct)% saved"
            let tone: WorkSignal.Tone = shown >= 0.20 ? .high : .neutral
            return WorkSignal(label: label, note: confidenceWord, tone: tone)

        case .commentsPerKudos:
            let pct = decimal(shown * 100)
            let label = "\(pct)% comments"
            let tone: WorkSignal.Tone = shown >= 0.05 ? .high : .neutral
            return WorkSignal(label: label, note: confidenceWord, tone: tone)

        case .momentum:
            if hasPrevious {
                let gained = Int(shown)
                let label = gained > 0 ? "+\(gained.formatted()) kudos" : "No new kudos"
                let tone: WorkSignal.Tone = gained > 0 ? .high : .neutral
                return WorkSignal(label: label, note: "Since you last saw it", tone: tone)
            } else {
                return WorkSignal(label: "First time seen", note: "No earlier sighting", tone: .neutral)
            }

        case .kudosPerThousandWords:
            let label = "\(decimal(shown)) kudos/1k words"
            let tone: WorkSignal.Tone = shown >= 15 ? .high : .neutral
            return WorkSignal(label: label, note: confidenceWord, tone: tone)
        }
    }

    /// One decimal below ten, none above ("2.4", "0.8", "26").
    static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value < 10 ? 1 : 0)))
    }
}
