import SwiftUI

/// Artboard **1ab**'s page head: the "AO3 Account" eyebrow with its short rule,
/// the 32pt title, and the line saying what this screen does not do.
///
/// Reuses `SubjectHeaderBlock` rather than restating the type sizes, so Settings
/// keeps step with the rest of the redesigned pages when those move. Its own
/// file because `SettingsView` is already at the type checker's limit.
struct SettingsHeaderBlock: View {
    @Environment(ThemeManager.self) private var theme

    private var palette: SubjectPalette {
        // Settings has no subject of its own to take a hue from — it is the
        // app's page, not a work's or a collection's — so it takes the accent
        // the reader chose, which is the only colour on this screen that is
        // theirs.
        theme.appTheme.subjectPalette(hue: CoverArt.workHue(fandoms: [], title: "Settings"))
    }

    var body: some View {
        SubjectHeaderBlock(
            kicker: "AO3 Account",
            title: "Settings",
            subtitle: "App only · nothing here reaches AO3",
            palette: palette,
            gutter: SubjectMetrics.accountGutter
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Settings")
        .accessibilityValue(
            "These settings are stored on this device only and are never sent to AO3."
        )
    }
}
