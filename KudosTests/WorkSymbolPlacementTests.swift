import SwiftUI
import Testing
@testable import Kudos

/// Settings › Appearance › Work Symbols (T-504): the 2×2 beside the title, or a row under it.
struct WorkSymbolPlacementTests {
    /// The stored values are what `@AppStorage` keeps; renaming one would reset everyone's choice.
    @Test func storedValuesAreStable() {
        #expect(WorkSymbolPlacement.storageKey == "workSymbolPlacement")
        #expect(WorkSymbolPlacement.beside.rawValue == "beside")
        #expect(WorkSymbolPlacement.underTitle.rawValue == "underTitle")
        #expect(WorkSymbolPlacement(rawValue: "unknown") == nil)
        #expect(WorkSymbolPlacement.allCases == [.beside, .underTitle])
    }

    /// Beside keeps every inset the row had before the setting.
    @Test func besideKeepsTheExistingSeparatorInsets() {
        let inset = { (stacked: Bool, wide: Bool, selecting: CGFloat?) in
            WorkRowMetrics.separatorInset(placement: .beside, stacked: stacked, wide: wide, selectingInset: selecting)
        }
        #expect(inset(false, false, nil) == WorkRowMetrics.textColumnInset)
        #expect(inset(true, false, nil) == WorkRowMetrics.screenInset)
        #expect(inset(false, true, nil) == WorkRowMetrics.screenInset)
        #expect(inset(false, false, 115) == 115)
    }

    /// Under the Title the text starts at the screen inset, or past the leading check while selecting.
    @Test func underTitleStartsTheSeparatorWithTheText() {
        for stacked in [false, true] {
            for wide in [false, true] {
                #expect(WorkRowMetrics.separatorInset(
                    placement: .underTitle, stacked: stacked, wide: wide, selectingInset: nil
                ) == WorkRowMetrics.screenInset)
                #expect(WorkRowMetrics.separatorInset(
                    placement: .underTitle, stacked: stacked, wide: wide, selectingInset: 115
                ) == WorkRowMetrics.selectingUnderTitleInset)
            }
        }
        #expect(WorkRowMetrics.selectingUnderTitleInset == 52)
    }

    /// The row under the title is bare, like the strip.
    @Test func rowArrangementIsBare() {
        #expect(!WorkStatusIconGrid.drawsBacking(arrangement: .row, backed: true))
    }

    @Test func settingsSearchFindsTheOption() {
        #expect(SettingsRoute.appearance.matches(query: "symbols", currentValue: ""))
    }

    // MARK: - Backup and folder sync

    private func makeDefaults() throws -> UserDefaults {
        let suite = "WorkSymbolPlacementTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func roundTrip(_ settings: KudosBackupSettings) throws -> KudosBackupSettings {
        try JSONDecoder().decode(KudosBackupSettings.self, from: JSONEncoder().encode(settings))
    }

    /// A chosen placement travels to the other device.
    @Test func placementRoundTripsThroughBackupSettings() throws {
        let source = try makeDefaults()
        source.set(WorkSymbolPlacement.underTitle.rawValue, forKey: WorkSymbolPlacement.storageKey)
        let decoded = try roundTrip(KudosBackupSettings.capture(defaults: source))
        #expect(decoded.workSymbolPlacement == "underTitle")

        let destination = try makeDefaults()
        decoded.apply(to: destination)
        #expect(destination.string(forKey: WorkSymbolPlacement.storageKey) == "underTitle")
    }

    /// A device that never chose writes no key, so it cannot reset a chosen device;
    /// an unknown value from a newer build is ignored.
    @Test func absentOrUnknownPlacementLeavesTheLocalChoice() throws {
        let unchosen = try roundTrip(KudosBackupSettings.capture(defaults: try makeDefaults()))
        #expect(unchosen.workSymbolPlacement == nil)

        let destination = try makeDefaults()
        destination.set(WorkSymbolPlacement.underTitle.rawValue, forKey: WorkSymbolPlacement.storageKey)
        unchosen.apply(to: destination)
        #expect(destination.string(forKey: WorkSymbolPlacement.storageKey) == "underTitle")

        var unknown = unchosen
        unknown.workSymbolPlacement = "sideways"
        try roundTrip(unknown).apply(to: destination)
        #expect(destination.string(forKey: WorkSymbolPlacement.storageKey) == "underTitle")
    }
}
